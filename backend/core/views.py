from collections import Counter
from datetime import datetime, time, timedelta

from django.db import transaction
from django.db.models import Case, Count, F, IntegerField, Q, Value, When
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import filters, mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

import re

from django.contrib.auth import get_user_model

from .models import ActivityLog, Comment, Notification, Project, ProjectMember, Task, log_activity, notify
from .permissions import (
    CAN_COMMENT,
    CAN_MANAGE_ALL_TASKS,
    CAN_MANAGE_MEMBERS,
    IsProjectMember,
    IsTaskProjectMember,
    get_role,
)
from accounts.serializers import UserSummarySerializer

from .serializers import (
    ActivityLogSerializer,
    CommentSerializer,
    NotificationSerializer,
    ProjectMemberSerializer,
    ProjectSerializer,
    TaskSerializer,
)

Action = ActivityLog.Action
Role = ProjectMember.Role
Kind = Notification.Kind
User = get_user_model()
MENTION_RE = re.compile(r"(?<![\w@])@([\w.+-]+)")


def mentioned_members(text, project):
    """Project members whose @username appears in [text]."""
    names = {n.rstrip(".").lower() for n in MENTION_RE.findall(text or "")}
    if not names:
        return []
    return [m for m in User.objects.filter(memberships__project=project) if m.username.lower() in names]
PRIORITY_RANK = Case(
    When(priority="low", then=Value(1)),
    When(priority="medium", then=Value(2)),
    When(priority="high", then=Value(3)),
    When(priority="urgent", then=Value(4)),
    output_field=IntegerField(),
)


def user_project_ids(user):
    return ProjectMember.objects.filter(user=user).values("project_id")


def csv_param(request, name):
    raw = request.query_params.get(name, "")
    return [v.strip() for v in raw.split(",") if v.strip()]


def describe_changes(old, new, fields):
    changes = []
    for field in fields:
        before, after = getattr(old, field), getattr(new, field)
        if before != after:
            label = field.replace("_", " ")
            changes.append(f"{label}: {before or '—'} → {after or '—'}")
    return changes


# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------
class ProjectViewSet(viewsets.ModelViewSet):
    serializer_class = ProjectSerializer
    permission_classes = [IsAuthenticated, IsProjectMember]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["name", "description"]
    ordering_fields = ["name", "deadline", "created_at", "updated_at", "status"]
    ordering = ["-created_at"]

    def get_queryset(self):
        today = timezone.localdate()
        qs = (
            Project.objects.filter(id__in=user_project_ids(self.request.user))
            .select_related("owner")
            .prefetch_related("memberships")
            .annotate(
                task_count=Count("tasks", distinct=True),
                completed_task_count=Count("tasks", filter=Q(tasks__status=Task.Status.COMPLETED), distinct=True),
                overdue_task_count=Count(
                    "tasks",
                    filter=Q(tasks__due_date__lt=today) & ~Q(tasks__status=Task.Status.COMPLETED),
                    distinct=True,
                ),
                member_count=Count("memberships", distinct=True),
            )
        )
        if statuses := csv_param(self.request, "status"):
            qs = qs.filter(status__in=statuses)
        if priorities := csv_param(self.request, "priority"):
            qs = qs.filter(priority__in=priorities)
        if self.request.query_params.get("owned") == "true":
            qs = qs.filter(owner=self.request.user)
        return qs

    def _reload(self, pk):
        return self.get_queryset().get(pk=pk)

    @transaction.atomic
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        project = serializer.save(owner=request.user)
        ProjectMember.objects.create(project=project, user=request.user, role=Role.OWNER)
        log_activity(project=project, user=request.user, action=Action.CREATED,
                     message=f'{request.user.display_name} created project "{project.name}"')
        data = self.get_serializer(self._reload(project.pk)).data
        return Response(data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        project = self.get_object()
        before = Project.objects.get(pk=project.pk)
        serializer = self.get_serializer(project, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        changes = describe_changes(before, project, ["name", "status", "priority", "start_date", "deadline"])
        if before.description != project.description:
            changes.append("description updated")
        if changes:
            action = Action.STATUS_CHANGED if before.status != project.status and len(changes) == 1 else Action.UPDATED
            log_activity(project=project, user=request.user, action=action,
                         message=f"{request.user.display_name} updated project ({'; '.join(changes)})")
        return Response(self.get_serializer(self._reload(project.pk)).data)

    # ---- members ---------------------------------------------------------
    @action(detail=True, methods=["get", "post"], url_path="members")
    def members(self, request, pk=None):
        project = self.get_object()
        if request.method == "GET":
            memberships = project.memberships.select_related("user").order_by(
                Case(When(role=Role.OWNER, then=0), When(role=Role.ADMIN, then=1),
                     When(role=Role.MEMBER, then=2), default=3), "joined_at"
            )
            return Response(ProjectMemberSerializer(memberships, many=True).data)

        if get_role(request.user, project) not in CAN_MANAGE_MEMBERS:
            raise PermissionDenied("Only the owner or an admin can add members.")
        serializer = ProjectMemberSerializer(data=request.data, context={"project": project, "request": request})
        serializer.is_valid(raise_exception=True)
        membership = serializer.save(project=project)
        log_activity(project=project, user=request.user, action=Action.MEMBER_ADDED,
                     message=f"{request.user.display_name} added {membership.user.display_name} as {membership.role}")
        notify([membership.user], actor=request.user, kind=Kind.MEMBER_ADDED, project=project,
               message=f'{request.user.display_name} added you to "{project.name}" as {membership.get_role_display()}')
        return Response(ProjectMemberSerializer(membership).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["patch", "delete"], url_path=r"members/(?P<member_id>\d+)")
    def member_detail(self, request, pk=None, member_id=None):
        project = self.get_object()
        membership = get_object_or_404(ProjectMember.objects.select_related("user"), pk=member_id, project=project)
        my_role = get_role(request.user, project)
        is_self = membership.user_id == request.user.id

        if membership.role == Role.OWNER:
            raise PermissionDenied("The project owner cannot be changed or removed.")

        if request.method == "DELETE":
            if not is_self and my_role not in CAN_MANAGE_MEMBERS:
                raise PermissionDenied("Only the owner or an admin can remove members.")
            if my_role == Role.ADMIN and membership.role == Role.ADMIN and not is_self:
                raise PermissionDenied("Admins cannot remove other admins.")
            with transaction.atomic():
                Task.objects.filter(project=project, assignee=membership.user).update(assignee=None)
                membership.delete()
                verb = "left the project" if is_self else f"removed {membership.user.display_name}"
                log_activity(project=project, user=request.user, action=Action.MEMBER_REMOVED,
                             message=f"{request.user.display_name} {verb}")
                if not is_self:
                    # No project link: the user can no longer open it.
                    notify([membership.user], actor=request.user, kind=Kind.MEMBER_REMOVED,
                           message=f'{request.user.display_name} removed you from "{project.name}"')
            return Response(status=status.HTTP_204_NO_CONTENT)

        if my_role not in CAN_MANAGE_MEMBERS:
            raise PermissionDenied("Only the owner or an admin can change roles.")
        if my_role == Role.ADMIN and (membership.role == Role.ADMIN or is_self):
            raise PermissionDenied("Admins cannot change the role of admins.")
        serializer = ProjectMemberSerializer(
            membership, data={"role": request.data.get("role")}, partial=True,
            context={"project": project, "request": request},
        )
        serializer.is_valid(raise_exception=True)
        old_role = membership.role
        serializer.save()
        if old_role != membership.role:
            log_activity(project=project, user=request.user, action=Action.ROLE_CHANGED,
                         message=f"{request.user.display_name} changed {membership.user.display_name}'s role "
                                 f"from {old_role} to {membership.role}")
            notify([membership.user], actor=request.user, kind=Kind.ROLE_CHANGED, project=project,
                   message=f'{request.user.display_name} changed your role in "{project.name}" '
                           f"to {membership.get_role_display()}")
        return Response(ProjectMemberSerializer(membership).data)

    # ---- activity --------------------------------------------------------
    @action(detail=True, methods=["get"], url_path="activity")
    def activity(self, request, pk=None):
        project = self.get_object()
        qs = project.activities.select_related("user", "task", "project")
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(ActivityLogSerializer(page, many=True).data)


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------
TASK_ORDERINGS = {
    "due_date": [F("due_date").asc(nulls_last=True), "-id"],
    "-due_date": [F("due_date").desc(nulls_last=True), "-id"],
    "priority": ["priority_rank", "-id"],
    "-priority": ["-priority_rank", "-id"],
    "created_at": ["created_at", "id"],
    "-created_at": ["-created_at", "-id"],
    "updated_at": ["updated_at", "id"],
    "-updated_at": ["-updated_at", "-id"],
    "title": ["title", "id"],
    "-title": ["-title", "-id"],
    "status": ["status", "-id"],
}


class TaskViewSet(viewsets.ModelViewSet):
    serializer_class = TaskSerializer
    permission_classes = [IsAuthenticated, IsTaskProjectMember]
    filter_backends = [filters.SearchFilter]
    search_fields = ["title", "description", "project__name"]

    def get_queryset(self):
        request = self.request
        qs = (
            Task.objects.filter(project_id__in=user_project_ids(request.user))
            .select_related("project", "assignee", "created_by")
            .prefetch_related("project__memberships")
            .annotate(comment_count=Count("comments", distinct=True), priority_rank=PRIORITY_RANK)
        )
        params = request.query_params
        if project := params.get("project"):
            qs = qs.filter(project_id=project) if project.isdigit() else qs.none()
        if statuses := csv_param(request, "status"):
            qs = qs.filter(status__in=statuses)
        if priorities := csv_param(request, "priority"):
            qs = qs.filter(priority__in=priorities)
        if assignee := params.get("assignee"):
            if assignee == "me":
                qs = qs.filter(assignee=request.user)
            elif assignee == "none":
                qs = qs.filter(assignee__isnull=True)
            elif assignee.isdigit():
                qs = qs.filter(assignee_id=assignee)
        if params.get("overdue") == "true":
            qs = qs.filter(due_date__lt=timezone.localdate()).exclude(status=Task.Status.COMPLETED)
        if due_before := params.get("due_before"):
            qs = qs.filter(due_date__lte=due_before)
        if due_after := params.get("due_after"):
            qs = qs.filter(due_date__gte=due_after)
        ordering = params.get("ordering", "-created_at")
        return qs.order_by(*TASK_ORDERINGS.get(ordering, TASK_ORDERINGS["-created_at"]))

    def _reload(self, pk):
        return self.get_queryset().get(pk=pk)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            task = serializer.save(created_by=request.user)
            msg = f'{request.user.display_name} created task "{task.title}"'
            if task.assignee:
                msg += f" and assigned it to {task.assignee.display_name}"
            log_activity(project=task.project, task=task, user=request.user, action=Action.CREATED, message=msg)
            notify([task.assignee], actor=request.user, kind=Kind.ASSIGNED, project=task.project, task=task,
                   message=f'{request.user.display_name} assigned you "{task.title}" in {task.project.name}')
        return Response(self.get_serializer(self._reload(task.pk)).data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        task = self.get_object()
        before = Task.objects.select_related("assignee", "project").get(pk=task.pk)
        serializer = self.get_serializer(task, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            serializer.save()
            user = request.user
            name = user.display_name
            if before.status != task.status:
                log_activity(project=task.project, task=task, user=user, action=Action.STATUS_CHANGED,
                             message=f'{name} moved "{task.title}" from {before.get_status_display()} '
                                     f'to {task.get_status_display()}')
                # The new assignee gets the "assigned" notice below instead.
                watchers = [task.created_by] + ([task.assignee] if before.assignee_id == task.assignee_id else [])
                notify(watchers, actor=user, kind=Kind.STATUS_CHANGED, project=task.project, task=task,
                       message=f'{name} moved "{task.title}" to {task.get_status_display()}')
            if before.assignee_id != task.assignee_id:
                target = task.assignee.display_name if task.assignee else "nobody"
                log_activity(project=task.project, task=task, user=user, action=Action.ASSIGNED,
                             message=f'{name} assigned "{task.title}" to {target}')
                notify([task.assignee], actor=user, kind=Kind.ASSIGNED, project=task.project, task=task,
                       message=f'{name} assigned you "{task.title}" in {task.project.name}')
            if before.project_id != task.project_id:
                log_activity(project=task.project, task=task, user=user, action=Action.UPDATED,
                             message=f'{name} moved "{task.title}" from project "{before.project.name}"')
            changes = describe_changes(before, task, ["title", "priority", "due_date"])
            if before.description != task.description:
                changes.append("description updated")
            if changes:
                log_activity(project=task.project, task=task, user=user, action=Action.UPDATED,
                             message=f'{name} updated "{task.title}" ({"; ".join(changes)})')
        return Response(self.get_serializer(self._reload(task.pk)).data)

    def perform_destroy(self, instance):
        log_activity(project=instance.project, user=self.request.user, action=Action.DELETED,
                     message=f'{self.request.user.display_name} deleted task "{instance.title}"')
        instance.delete()

    @action(detail=True, methods=["get", "post"], url_path="comments")
    def comments(self, request, pk=None):
        task = self.get_object()
        if request.method == "GET":
            return Response(CommentSerializer(task.comments.select_related("author"), many=True).data)
        if get_role(request.user, task.project) not in CAN_COMMENT:
            raise PermissionDenied("You cannot comment on this task.")
        serializer = CommentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        comment = serializer.save(task=task, author=request.user)
        name = request.user.display_name
        log_activity(project=task.project, task=task, user=request.user, action=Action.COMMENTED,
                     message=f'{name} commented on "{task.title}"')
        mentioned = mentioned_members(comment.body, task.project)
        notify(mentioned, actor=request.user, kind=Kind.MENTION, project=task.project, task=task,
               message=f'{name} mentioned you on "{task.title}": {comment.body[:120]}')
        # Everyone already involved in the task, except those just mentioned.
        mentioned_ids = {u.pk for u in mentioned}
        involved = [task.assignee, task.created_by] + [
            c.author for c in task.comments.select_related("author").exclude(pk=comment.pk)
        ]
        notify([u for u in involved if u and u.pk not in mentioned_ids], actor=request.user, kind=Kind.COMMENT,
               project=task.project, task=task, message=f'{name} commented on "{task.title}": {comment.body[:120]}')
        return Response(CommentSerializer(comment).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get"], url_path="activity")
    def activity(self, request, pk=None):
        task = self.get_object()
        qs = task.activities.select_related("user", "task", "project")[:50]
        return Response(ActivityLogSerializer(qs, many=True).data)


# ---------------------------------------------------------------------------
# Comments (edit / delete)
# ---------------------------------------------------------------------------
class CommentViewSet(mixins.RetrieveModelMixin, mixins.UpdateModelMixin, mixins.DestroyModelMixin,
                     viewsets.GenericViewSet):
    serializer_class = CommentSerializer

    def get_queryset(self):
        return Comment.objects.filter(task__project_id__in=user_project_ids(self.request.user)).select_related(
            "author", "task__project"
        )

    def perform_update(self, serializer):
        if serializer.instance.author_id != self.request.user.id:
            raise PermissionDenied("You can only edit your own comments.")
        serializer.save()

    def perform_destroy(self, instance):
        role = get_role(self.request.user, instance.task.project)
        if instance.author_id != self.request.user.id and role not in CAN_MANAGE_ALL_TASKS:
            raise PermissionDenied("You can only delete your own comments.")
        instance.delete()


# ---------------------------------------------------------------------------
# Activity feed and dashboard
# ---------------------------------------------------------------------------
class ActivityFeedView(APIView):
    def get(self, request):
        qs = ActivityLog.objects.filter(project_id__in=user_project_ids(request.user)).select_related(
            "user", "task", "project"
        )
        try:
            limit = max(1, min(int(request.query_params.get("limit", 20)), 100))
        except ValueError:
            raise ValidationError({"limit": "Must be an integer."})
        return Response(ActivityLogSerializer(qs[:limit], many=True).data)


class DashboardView(APIView):
    def get(self, request):
        user = request.user
        today = timezone.localdate()
        project_ids = user_project_ids(user)
        projects = Project.objects.filter(id__in=project_ids)
        tasks = Task.objects.filter(project_id__in=project_ids)
        open_tasks = tasks.exclude(status=Task.Status.COMPLETED)

        task_totals = tasks.aggregate(
            total=Count("id"),
            todo=Count("id", filter=Q(status=Task.Status.TODO)),
            in_progress=Count("id", filter=Q(status=Task.Status.IN_PROGRESS)),
            completed=Count("id", filter=Q(status=Task.Status.COMPLETED)),
            overdue=Count("id", filter=Q(due_date__lt=today) & ~Q(status=Task.Status.COMPLETED)),
            due_today=Count("id", filter=Q(due_date=today) & ~Q(status=Task.Status.COMPLETED)),
            assigned_to_me=Count("id", filter=Q(assignee=user) & ~Q(status=Task.Status.COMPLETED)),
        )
        task_totals["pending"] = task_totals["todo"] + task_totals["in_progress"]
        total = task_totals["total"]
        task_totals["completion_rate"] = round(task_totals["completed"] * 100 / total) if total else 0

        by_priority = {p: 0 for p, _ in Task._meta.get_field("priority").choices}
        for row in open_tasks.values("priority").annotate(c=Count("id")):
            by_priority[row["priority"]] = row["c"]

        by_project_status = {s: 0 for s, _ in Project.Status.choices}
        for row in projects.values("status").annotate(c=Count("id")):
            by_project_status[row["status"]] = row["c"]

        project_progress = []
        for p in (
            projects.annotate(
                total=Count("tasks", distinct=True),
                done=Count("tasks", filter=Q(tasks__status=Task.Status.COMPLETED), distinct=True),
            )
            .exclude(status=Project.Status.COMPLETED)
            .order_by(F("deadline").asc(nulls_last=True), "-created_at")[:8]
        ):
            project_progress.append({
                "id": p.id, "name": p.name, "status": p.status, "deadline": p.deadline,
                "total_tasks": p.total, "completed_tasks": p.done,
                "progress": round(p.done * 100 / p.total) if p.total else 0,
            })

        week_start = today - timedelta(days=6)
        # Bucket by local date in Python: MySQL on Windows usually has no time
        # zone tables, so DB-side date truncation with USE_TZ returns NULL.
        since = timezone.make_aware(datetime.combine(week_start, time.min))
        completed_by_day = Counter(
            timezone.localtime(ts).date()
            for ts in tasks.filter(completed_at__gte=since).values_list("completed_at", flat=True)
        )
        completion_trend = [
            {"date": week_start + timedelta(days=i), "completed": completed_by_day.get(week_start + timedelta(days=i), 0)}
            for i in range(7)
        ]

        upcoming = (
            open_tasks.filter(due_date__gte=today, due_date__lte=today + timedelta(days=7))
            .select_related("project", "assignee", "created_by")
            .prefetch_related("project__memberships")
            .annotate(comment_count=Count("comments"))
            .order_by("due_date", "-id")[:8]
        )
        overdue_list = (
            open_tasks.filter(due_date__lt=today)
            .select_related("project", "assignee", "created_by")
            .prefetch_related("project__memberships")
            .annotate(comment_count=Count("comments"))
            .order_by("due_date", "-id")[:8]
        )
        recent = ActivityLog.objects.filter(project_id__in=project_ids).select_related("user", "task", "project")[:10]
        ctx = {"request": request}

        return Response({
            "projects": {"total": projects.count(), "by_status": by_project_status},
            "tasks": {**task_totals, "by_priority_open": by_priority},
            "project_progress": project_progress,
            "completion_trend": completion_trend,
            "upcoming_tasks": TaskSerializer(upcoming, many=True, context=ctx).data,
            "overdue_tasks": TaskSerializer(overdue_list, many=True, context=ctx).data,
            "recent_activity": ActivityLogSerializer(recent, many=True).data,
        })


# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------
class NotificationViewSet(mixins.ListModelMixin, mixins.DestroyModelMixin, viewsets.GenericViewSet):
    """The signed-in user's notifications. `?unread=true` lists only unread ones."""

    serializer_class = NotificationSerializer

    def get_queryset(self):
        qs = Notification.objects.filter(recipient=self.request.user).select_related("actor", "project", "task")
        if self.request.query_params.get("unread") == "true":
            qs = qs.filter(is_read=False)
        return qs

    @action(detail=False, methods=["get"], url_path="unread-count")
    def unread_count(self, request):
        return Response({"count": Notification.objects.filter(recipient=request.user, is_read=False).count()})

    @action(detail=True, methods=["post"], url_path="read")
    def mark_read(self, request, pk=None):
        notification = self.get_object()
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=["is_read"])
        return Response(self.get_serializer(notification).data)

    @action(detail=False, methods=["post"], url_path="read-all")
    def mark_all_read(self, request):
        updated = Notification.objects.filter(recipient=request.user, is_read=False).update(is_read=True)
        return Response({"updated": updated})


# ---------------------------------------------------------------------------
# Team: everyone the user shares a project with, and their workload
# ---------------------------------------------------------------------------
class TeamView(APIView):
    def get(self, request):
        today = timezone.localdate()
        my_projects = user_project_ids(request.user)
        open_q = ~Q(assigned_tasks__status=Task.Status.COMPLETED)
        in_mine = Q(assigned_tasks__project__in=my_projects)
        people = (
            User.objects.filter(memberships__project__in=my_projects)
            .distinct()
            .annotate(
                open_tasks=Count("assigned_tasks", filter=in_mine & open_q, distinct=True),
                in_progress_tasks=Count(
                    "assigned_tasks", filter=in_mine & Q(assigned_tasks__status=Task.Status.IN_PROGRESS), distinct=True
                ),
                completed_tasks=Count(
                    "assigned_tasks", filter=in_mine & Q(assigned_tasks__status=Task.Status.COMPLETED), distinct=True
                ),
                overdue_tasks=Count(
                    "assigned_tasks", filter=in_mine & open_q & Q(assigned_tasks__due_date__lt=today), distinct=True
                ),
            )
            .order_by("-open_tasks", "full_name", "username")
        )
        projects_by_user = {}
        for m in ProjectMember.objects.filter(project__in=my_projects).select_related("project").order_by("project__name"):
            projects_by_user.setdefault(m.user_id, []).append(
                {"id": m.project_id, "name": m.project.name, "role": m.role}
            )
        data = []
        for person in people:
            row = UserSummarySerializer(person).data
            row.update({
                "is_me": person.pk == request.user.pk,
                "projects": projects_by_user.get(person.pk, []),
                "open_tasks": person.open_tasks,
                "in_progress_tasks": person.in_progress_tasks,
                "completed_tasks": person.completed_tasks,
                "overdue_tasks": person.overdue_tasks,
            })
            data.append(row)
        return Response(data)
