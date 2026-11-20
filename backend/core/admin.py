from django.contrib import admin

from .models import ActivityLog, Comment, Project, ProjectMember, Task


class ProjectMemberInline(admin.TabularInline):
    model = ProjectMember
    extra = 0


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ("name", "owner", "status", "priority", "deadline", "created_at")
    list_filter = ("status", "priority")
    search_fields = ("name", "description")
    inlines = [ProjectMemberInline]


@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display = ("title", "project", "status", "priority", "due_date", "assignee")
    list_filter = ("status", "priority")
    search_fields = ("title", "description")


admin.site.register(Comment)
admin.site.register(ActivityLog)
