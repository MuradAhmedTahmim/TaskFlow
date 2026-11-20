from django.contrib.auth import get_user_model
from rest_framework import serializers

from accounts.serializers import UserSummarySerializer

from .models import ActivityLog, Comment, Project, ProjectMember, Task
from .permissions import CAN_WRITE_TASKS, get_role

User = get_user_model()


class ProjectSerializer(serializers.ModelSerializer):
    owner = UserSummarySerializer(read_only=True)
    my_role = serializers.SerializerMethodField()
    task_count = serializers.IntegerField(read_only=True, default=0)
    completed_task_count = serializers.IntegerField(read_only=True, default=0)
    overdue_task_count = serializers.IntegerField(read_only=True, default=0)
    member_count = serializers.IntegerField(read_only=True, default=0)
    progress = serializers.SerializerMethodField()

    class Meta:
        model = Project
        fields = [
            "id", "name", "description", "owner", "status", "priority", "start_date", "deadline",
            "created_at", "updated_at", "my_role", "task_count", "completed_task_count",
            "overdue_task_count", "member_count", "progress",
        ]
        read_only_fields = ["id", "owner", "created_at", "updated_at"]

    def get_my_role(self, obj):
        request = self.context.get("request")
        return get_role(request.user, obj) if request else None

    def get_progress(self, obj):
        total = getattr(obj, "task_count", 0) or 0
        done = getattr(obj, "completed_task_count", 0) or 0
        return round(done * 100 / total) if total else 0

    def validate_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Project name cannot be blank.")
        return value

    def validate(self, attrs):
        start = attrs.get("start_date", getattr(self.instance, "start_date", None))
        deadline = attrs.get("deadline", getattr(self.instance, "deadline", None))
        if start and deadline and deadline < start:
            raise serializers.ValidationError({"deadline": "Deadline cannot be before the start date."})
        return attrs


class ProjectMemberSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    user_id = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(is_active=True), source="user", write_only=True
    )

    class Meta:
        model = ProjectMember
        fields = ["id", "user", "user_id", "role", "joined_at"]
        read_only_fields = ["id", "joined_at"]

    def validate_role(self, value):
        if value == ProjectMember.Role.OWNER:
            raise serializers.ValidationError("A project can only have one owner.")
        return value

    def validate(self, attrs):
        project = self.context["project"]
        user = attrs.get("user")
        if self.instance is None and user and ProjectMember.objects.filter(project=project, user=user).exists():
            raise serializers.ValidationError({"user_id": "This user is already a member of the project."})
        return attrs


class TaskSerializer(serializers.ModelSerializer):
    project_name = serializers.CharField(source="project.name", read_only=True)
    assignee = UserSummarySerializer(read_only=True)
    assignee_id = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(is_active=True), source="assignee",
        write_only=True, required=False, allow_null=True,
    )
    created_by = UserSummarySerializer(read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)
    comment_count = serializers.IntegerField(read_only=True, default=0)
    my_role = serializers.SerializerMethodField()

    class Meta:
        model = Task
        fields = [
            "id", "project", "project_name", "title", "description", "status", "priority", "due_date",
            "assignee", "assignee_id", "created_by", "is_overdue", "comment_count", "completed_at",
            "created_at", "updated_at", "my_role",
        ]
        read_only_fields = ["id", "created_by", "completed_at", "created_at", "updated_at"]

    def get_my_role(self, obj):
        request = self.context.get("request")
        return get_role(request.user, obj.project) if request else None

    def validate_title(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Task title cannot be blank.")
        return value

    def validate_project(self, project):
        user = self.context["request"].user
        if get_role(user, project) not in CAN_WRITE_TASKS:
            raise serializers.ValidationError("You cannot add tasks to this project.")
        return project

    def validate(self, attrs):
        project = attrs.get("project", getattr(self.instance, "project", None))
        assignee = attrs.get("assignee", getattr(self.instance, "assignee", None))
        if assignee and project and not ProjectMember.objects.filter(project=project, user=assignee).exists():
            raise serializers.ValidationError({"assignee_id": "The assignee must be a member of the project."})
        return attrs


class CommentSerializer(serializers.ModelSerializer):
    author = UserSummarySerializer(read_only=True)

    class Meta:
        model = Comment
        fields = ["id", "task", "author", "body", "created_at", "updated_at"]
        read_only_fields = ["id", "task", "author", "created_at", "updated_at"]

    def validate_body(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Comment cannot be empty.")
        return value


class ActivityLogSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    task_title = serializers.CharField(source="task.title", read_only=True, default=None)
    project_name = serializers.CharField(source="project.name", read_only=True)

    class Meta:
        model = ActivityLog
        fields = ["id", "project", "project_name", "task", "task_title", "user", "action", "message", "created_at"]
