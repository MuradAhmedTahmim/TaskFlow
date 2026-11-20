from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Application user. Email is required and unique."""

    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=150, blank=True)
    bio = models.TextField(blank=True, max_length=500)
    job_title = models.CharField(max_length=100, blank=True)

    REQUIRED_FIELDS = ["email"]

    class Meta:
        ordering = ["username"]

    @property
    def display_name(self) -> str:
        return self.full_name or self.username

    def __str__(self) -> str:
        return self.display_name
