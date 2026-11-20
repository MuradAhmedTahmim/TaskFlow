from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("projects", views.ProjectViewSet, basename="project")
router.register("tasks", views.TaskViewSet, basename="task")
router.register("comments", views.CommentViewSet, basename="comment")

urlpatterns = [
    path("dashboard/", views.DashboardView.as_view(), name="dashboard"),
    path("activity/", views.ActivityFeedView.as_view(), name="activity-feed"),
    path("", include(router.urls)),
]
