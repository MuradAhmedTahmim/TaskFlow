"""Role-based access control helpers for project members."""
from rest_framework import permissions

from .models import ProjectMember

Role = ProjectMember.Role

# Roles allowed to perform each kind of action.
CAN_EDIT_PROJECT = {Role.OWNER, Role.ADMIN}
CAN_MANAGE_MEMBERS = {Role.OWNER, Role.ADMIN}
CAN_DELETE_PROJECT = {Role.OWNER}
CAN_WRITE_TASKS = {Role.OWNER, Role.ADMIN, Role.MEMBER}
CAN_MANAGE_ALL_TASKS = {Role.OWNER, Role.ADMIN}
CAN_COMMENT = {Role.OWNER, Role.ADMIN, Role.MEMBER, Role.VIEWER}

# Custom viewset actions that only require membership at the object level.
MEMBERSHIP_ONLY_ACTIONS = {"members", "member_detail", "activity", "comments"}


def get_role(user, project):
    """Return the user's role in the project, or None if not a member.

    Uses a prefetched `memberships` cache when present to avoid extra queries.
    """
    if not user or not user.is_authenticated:
        return None
    cache = getattr(project, "_prefetched_objects_cache", {}).get("memberships")
    if cache is not None:
        for membership in cache:
            if membership.user_id == user.id:
                return membership.role
        return None
    return (
        ProjectMember.objects.filter(project=project, user=user).values_list("role", flat=True).first()
    )


class IsProjectMember(permissions.BasePermission):
    """Object-level permission for Project objects."""

    message = "You do not have permission to perform this action on this project."

    def has_object_permission(self, request, view, obj):
        role = get_role(request.user, obj)
        if role is None:
            return False
        if request.method in permissions.SAFE_METHODS:
            return True
        if getattr(view, "action", None) in MEMBERSHIP_ONLY_ACTIONS:
            # These actions perform their own finer-grained role checks.
            return True
        if request.method == "DELETE":
            return role in CAN_DELETE_PROJECT
        return role in CAN_EDIT_PROJECT


class IsTaskProjectMember(permissions.BasePermission):
    """Object-level permission for Task objects.

    Members can edit any task in the project but may delete only tasks they
    created or that are assigned to them. Owners/admins can delete any task.
    Viewers are read-only.
    """

    message = "You do not have permission to modify this task."

    def has_object_permission(self, request, view, obj):
        role = get_role(request.user, obj.project)
        if role is None:
            return False
        if request.method in permissions.SAFE_METHODS:
            return True
        if getattr(view, "action", None) in MEMBERSHIP_ONLY_ACTIONS:
            return True
        if role not in CAN_WRITE_TASKS:
            return False
        if request.method == "DELETE" and role not in CAN_MANAGE_ALL_TASKS:
            return request.user.id in (obj.created_by_id, obj.assignee_id)
        return True
