from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class TaskFlowUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (("Profile", {"fields": ("full_name", "job_title", "bio")}),)
    list_display = ("username", "email", "full_name", "is_staff", "is_active")
    search_fields = ("username", "email", "full_name")
