from django.conf import settings
from django.db import models
from django.utils import timezone


class Priority(models.TextChoices):
    LOW = "low", "Low"
    MEDIUM = "medium", "Medium"
    HIGH = "high", "High"
    URGENT = "urgent", "Urgent"


class Project(models.Model):
    class Status(models.TextChoices):
        PLANNING = "planning", "Planning"
        ACTIVE = "active", "Active"
        ON_HOLD = "on_hold", "On hold"
        COMPLETED = "completed", "Completed"

    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="owned_projects")
    members = models.ManyToManyField(
        settings.AUTH_USER_MODEL, through="ProjectMember", related_name="projects"
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PLANNING)
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.MEDIUM)
    start_date = models.DateField(null=True, blank=True)
    deadline = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["status"]), models.Index(fields=["deadline"])]

    def __str__(self) -> str:
        return self.name


class ProjectMember(models.Model):
    """Membership of a user in a project, with a role used for access control.

    owner  - full control, including deleting the project
    admin  - edit project, manage members and all tasks
    member - create tasks, edit tasks, comment
    viewer - read-only access, may comment
    """

    class Role(models.TextChoices):
        OWNER = "owner", "Owner"
        ADMIN = "admin", "Admin"
        MEMBER = "member", "Member"
        VIEWER = "viewer", "Viewer"

    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=10, choices=Role.choices, default=Role.MEMBER)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["joined_at"]
        constraints = [models.UniqueConstraint(fields=["project", "user"], name="unique_project_member")]

    def __str__(self) -> str:
        return f"{self.user} in {self.project} ({self.role})"


class Task(models.Model):
    class Status(models.TextChoices):
        TODO = "todo", "To Do"
        IN_PROGRESS = "in_progress", "In Progress"
        COMPLETED = "completed", "Completed"

    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="tasks")
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.TODO)
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.MEDIUM)
    due_date = models.DateField(null=True, blank=True)
    assignee = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="assigned_tasks"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="created_tasks"
    )
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status"]),
            models.Index(fields=["priority"]),
            models.Index(fields=["due_date"]),
        ]

    def __str__(self) -> str:
        return self.title

    @property
    def is_overdue(self) -> bool:
        return bool(self.due_date and self.status != self.Status.COMPLETED and self.due_date < timezone.localdate())

    def save(self, *args, **kwargs):
        if self.status == self.Status.COMPLETED and self.completed_at is None:
            self.completed_at = timezone.now()
        elif self.status != self.Status.COMPLETED:
            self.completed_at = None
        super().save(*args, **kwargs)


class Comment(models.Model):
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name="comments")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="comments")
    body = models.TextField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self) -> str:
        return f"Comment by {self.author} on {self.task}"


class ActivityLog(models.Model):
    class Action(models.TextChoices):
        CREATED = "created", "Created"
        UPDATED = "updated", "Updated"
        DELETED = "deleted", "Deleted"
        STATUS_CHANGED = "status_changed", "Status changed"
        ASSIGNED = "assigned", "Assigned"
        COMMENTED = "commented", "Commented"
        MEMBER_ADDED = "member_added", "Member added"
        MEMBER_REMOVED = "member_removed", "Member removed"
        ROLE_CHANGED = "role_changed", "Role changed"

    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name="activities")
    task = models.ForeignKey(Task, on_delete=models.SET_NULL, null=True, blank=True, related_name="activities")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="activities")
    action = models.CharField(max_length=20, choices=Action.choices)
    message = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self) -> str:
        return self.message


def log_activity(*, project, user, action, message, task=None):
    return ActivityLog.objects.create(project=project, task=task, user=user, action=action, message=message[:255])


class Notification(models.Model):
    """An in-app message for one user about something a teammate did."""

    class Kind(models.TextChoices):
        ASSIGNED = "assigned", "Task assigned"
        STATUS_CHANGED = "status_changed", "Task status changed"
        COMMENT = "comment", "New comment"
        MENTION = "mention", "Mentioned"
        MEMBER_ADDED = "member_added", "Added to project"
        MEMBER_REMOVED = "member_removed", "Removed from project"
        ROLE_CHANGED = "role_changed", "Role changed"

    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="+"
    )
    kind = models.CharField(max_length=20, choices=Kind.choices)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, null=True, blank=True, related_name="+")
    task = models.ForeignKey(Task, on_delete=models.CASCADE, null=True, blank=True, related_name="+")
    message = models.CharField(max_length=255)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["recipient", "is_read"])]

    def __str__(self) -> str:
        return f"To {self.recipient}: {self.message}"


def notify(recipients, *, actor, kind, message, project=None, task=None):
    """Create one notification per recipient, skipping the actor and duplicates."""
    seen = set()
    rows = []
    for user in recipients:
        if user is None or user.pk == getattr(actor, "pk", None) or user.pk in seen:
            continue
        seen.add(user.pk)
        rows.append(Notification(recipient=user, actor=actor, kind=kind, project=project, task=task,
                                 message=message[:255]))
    Notification.objects.bulk_create(rows)
    return rows
