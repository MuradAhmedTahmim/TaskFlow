"""Create demo users, projects and tasks for trying out TaskFlow.

    python manage.py seed_demo            # adds demo data (skips if it exists)
    python manage.py seed_demo --reset    # deletes demo users' data first
"""
import random
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from core.models import Comment, Project, ProjectMember, Task, log_activity

User = get_user_model()
DEMO_PASSWORD = "TaskFlow@123"
DEMO_USERS = [
    ("demo", "demo@taskflow.local", "Demo User", "Project Lead"),
    ("rahim", "rahim@taskflow.local", "Rahim Uddin", "Backend Developer"),
    ("karim", "karim@taskflow.local", "Karim Hasan", "Flutter Developer"),
    ("nadia", "nadia@taskflow.local", "Nadia Islam", "UI/UX Designer"),
]
PROJECTS = [
    ("TaskFlow Web App", "Course project: Flutter Web frontend with a Django REST backend.", "active", "high", -20, 25),
    ("University Portal Redesign", "Modernise the student portal UI and improve accessibility.", "active", "medium", -10, 40),
    ("Mobile Banking Prototype", "Clickable prototype for a mobile banking concept.", "planning", "low", 5, 60),
    ("Research Paper", "Write and submit the paper on task scheduling heuristics.", "on_hold", "urgent", -30, 10),
    ("Portfolio Website", "Personal portfolio with project showcase and blog.", "completed", "medium", -60, -5),
]
TASK_TITLES = [
    "Design database schema", "Set up Django project", "Implement JWT authentication", "Create project API",
    "Create task API", "Write API tests", "Build login screen", "Build dashboard charts", "Add search and filters",
    "Implement pagination", "Write README", "Deploy to staging", "Collect user feedback", "Fix responsive layout",
    "Prepare presentation slides", "Review pull requests", "Add comments feature", "Improve error messages",
]


class Command(BaseCommand):
    help = "Seed the database with demo users, projects, tasks and comments."

    def add_arguments(self, parser):
        parser.add_argument("--reset", action="store_true", help="Delete existing demo data first.")

    @transaction.atomic
    def handle(self, *args, reset=False, **options):
        usernames = [u[0] for u in DEMO_USERS]
        if reset:
            Project.objects.filter(owner__username__in=usernames).delete()
            User.objects.filter(username__in=usernames).delete()
        elif User.objects.filter(username="demo").exists():
            self.stdout.write(self.style.WARNING("Demo data already exists. Use --reset to recreate it."))
            return

        rng = random.Random(42)
        users = []
        for username, email, name, title in DEMO_USERS:
            user = User.objects.create_user(username=username, email=email, password=DEMO_PASSWORD,
                                            full_name=name, job_title=title)
            users.append(user)
        demo = users[0]
        today = timezone.localdate()

        for name, desc, status, priority, start_off, end_off in PROJECTS:
            project = Project.objects.create(
                name=name, description=desc, owner=demo, status=status, priority=priority,
                start_date=today + timedelta(days=start_off), deadline=today + timedelta(days=end_off),
            )
            ProjectMember.objects.create(project=project, user=demo, role=ProjectMember.Role.OWNER)
            roles = [ProjectMember.Role.ADMIN, ProjectMember.Role.MEMBER, ProjectMember.Role.VIEWER]
            members = [demo]
            for user, role in zip(users[1:], roles):
                if rng.random() < 0.8:
                    ProjectMember.objects.create(project=project, user=user, role=role)
                    if role != ProjectMember.Role.VIEWER:
                        members.append(user)
            log_activity(project=project, user=demo, action="created", message=f'Demo User created project "{name}"')

            for title in rng.sample(TASK_TITLES, rng.randint(5, 9)):
                if status == "completed":
                    task_status = "completed"
                else:
                    task_status = rng.choices(["todo", "in_progress", "completed"], weights=[4, 3, 3])[0]
                task = Task.objects.create(
                    project=project, title=title,
                    description=f"{title} for {name}.",
                    status=task_status,
                    priority=rng.choice(["low", "medium", "high", "urgent"]),
                    due_date=today + timedelta(days=rng.randint(-8, 20)),
                    assignee=rng.choice(members + [None]),
                    created_by=demo,
                )
                if task_status == "completed":
                    task.completed_at = timezone.now() - timedelta(days=rng.randint(0, 6), hours=rng.randint(0, 12))
                    task.save(update_fields=["completed_at"])
                log_activity(project=project, task=task, user=demo, action="created",
                             message=f'Demo User created task "{title}"')
                if rng.random() < 0.4:
                    author = rng.choice(members)
                    Comment.objects.create(task=task, author=author, body="Looks good — I'll take a look at this today.")

        self.stdout.write(self.style.SUCCESS(
            f"Demo data created. Log in as 'demo' (or rahim / karim / nadia) with password {DEMO_PASSWORD}"
        ))
