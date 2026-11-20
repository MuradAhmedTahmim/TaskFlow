from datetime import timedelta

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from core.models import ActivityLog, Notification, Project, ProjectMember, Task

User = get_user_model()
PASSWORD = "Str0ng-Pass!word"


class BaseAPITest(APITestCase):
    def make_user(self, username):
        return User.objects.create_user(username=username, email=f"{username}@example.com", password=PASSWORD)

    def login(self, user):
        self.client.force_authenticate(user=user)

    def make_project(self, owner, **kwargs):
        self.login(owner)
        res = self.client.post("/api/projects/", {"name": "Proj", "priority": "high", **kwargs}, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        return Project.objects.get(pk=res.data["id"])

    def add_member(self, project, user, role):
        return ProjectMember.objects.create(project=project, user=user, role=role)


class AuthTests(BaseAPITest):
    def test_register_login_me_logout(self):
        self.client.force_authenticate(None)
        res = self.client.post("/api/auth/register/", {
            "username": "alice", "email": "Alice@Example.com", "full_name": "Alice",
            "password": PASSWORD, "password2": PASSWORD,
        }, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        self.assertIn("access", res.data)
        self.assertEqual(res.data["user"]["email"], "alice@example.com")
        self.assertNotEqual(User.objects.get(username="alice").password, PASSWORD)  # hashed

        res = self.client.post("/api/auth/login/", {"username": "alice@example.com", "password": PASSWORD})
        self.assertEqual(res.status_code, 200, res.data)
        access, refresh = res.data["access"], res.data["refresh"]

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        res = self.client.get("/api/auth/me/")
        self.assertEqual(res.data["username"], "alice")
        res = self.client.patch("/api/auth/me/", {"full_name": "Alice B", "job_title": "Dev"}, format="json")
        self.assertEqual(res.data["full_name"], "Alice B")

        res = self.client.post("/api/auth/logout/", {"refresh": refresh})
        self.assertEqual(res.status_code, 205)
        res = self.client.post("/api/auth/refresh/", {"refresh": refresh})
        self.assertEqual(res.status_code, 401)

    def test_register_validation(self):
        self.make_user("bob")
        res = self.client.post("/api/auth/register/", {
            "username": "bob", "email": "bob@example.com", "password": "123", "password2": "456",
        }, format="json")
        self.assertEqual(res.status_code, 400)
        self.assertIn("username", res.data)
        self.assertIn("email", res.data)

    def test_protected_endpoints_require_auth(self):
        for url in ["/api/projects/", "/api/tasks/", "/api/dashboard/", "/api/auth/me/"]:
            self.assertEqual(self.client.get(url).status_code, 401, url)

    def test_change_password(self):
        user = self.make_user("carol")
        self.login(user)
        res = self.client.post("/api/auth/change-password/", {"old_password": "wrong", "new_password": "N3w-Pass!word"})
        self.assertEqual(res.status_code, 400)
        res = self.client.post("/api/auth/change-password/", {"old_password": PASSWORD, "new_password": "N3w-Pass!word"})
        self.assertEqual(res.status_code, 200)
        user.refresh_from_db()
        self.assertTrue(user.check_password("N3w-Pass!word"))

    def test_delete_account(self):
        dave, erin = self.make_user("dave"), self.make_user("erin")
        own = self.make_project(dave, name="Dave's")
        shared = self.make_project(erin, name="Erin's")
        self.add_member(shared, dave, ProjectMember.Role.MEMBER)
        task = Task.objects.create(project=shared, title="T", assignee=dave, created_by=erin)

        self.login(dave)
        res = self.client.delete("/api/auth/me/", {}, format="json")
        self.assertEqual(res.status_code, 400)
        res = self.client.delete("/api/auth/me/", {"password": "wrong"}, format="json")
        self.assertEqual(res.status_code, 400)
        self.assertTrue(User.objects.filter(username="dave").exists())

        res = self.client.delete("/api/auth/me/", {"password": PASSWORD}, format="json")
        self.assertEqual(res.status_code, 204)
        self.assertFalse(User.objects.filter(username="dave").exists())
        self.assertFalse(Project.objects.filter(pk=own.pk).exists())  # owned project removed
        self.assertTrue(Project.objects.filter(pk=shared.pk).exists())  # others' project kept
        task.refresh_from_db()
        self.assertIsNone(task.assignee)
        self.assertEqual(shared.memberships.count(), 1)


class ProjectTests(BaseAPITest):
    def setUp(self):
        self.owner = self.make_user("owner")
        self.other = self.make_user("other")

    def test_crud_and_isolation(self):
        project = self.make_project(self.owner, description="d")
        self.assertEqual(project.memberships.get().role, "owner")
        res = self.client.get("/api/projects/")
        self.assertEqual(res.data["count"], 1)
        self.assertEqual(res.data["results"][0]["my_role"], "owner")

        res = self.client.patch(f"/api/projects/{project.id}/", {"status": "active"}, format="json")
        self.assertEqual(res.data["status"], "active")
        self.assertTrue(ActivityLog.objects.filter(project=project, action="status_changed").exists())

        self.login(self.other)
        self.assertEqual(self.client.get("/api/projects/").data["count"], 0)
        self.assertEqual(self.client.get(f"/api/projects/{project.id}/").status_code, 404)

        self.login(self.owner)
        self.assertEqual(self.client.delete(f"/api/projects/{project.id}/").status_code, 204)
        self.assertFalse(Project.objects.exists())

    def test_deadline_validation(self):
        self.login(self.owner)
        res = self.client.post("/api/projects/", {"name": "X", "start_date": "2026-05-10", "deadline": "2026-05-01"})
        self.assertEqual(res.status_code, 400)
        self.assertIn("deadline", res.data)

    def test_role_permissions(self):
        project = self.make_project(self.owner)
        admin, member, viewer = self.make_user("adm"), self.make_user("mem"), self.make_user("view")
        self.client.post(f"/api/projects/{project.id}/members/", {"user_id": admin.id, "role": "admin"})
        self.client.post(f"/api/projects/{project.id}/members/", {"user_id": member.id, "role": "member"})
        res = self.client.post(f"/api/projects/{project.id}/members/", {"user_id": viewer.id, "role": "viewer"})
        self.assertEqual(res.status_code, 201)
        res = self.client.post(f"/api/projects/{project.id}/members/", {"user_id": viewer.id, "role": "member"})
        self.assertEqual(res.status_code, 400)  # duplicate

        # member cannot edit project or add members
        self.login(member)
        self.assertEqual(self.client.patch(f"/api/projects/{project.id}/", {"name": "Y"}).status_code, 403)
        self.assertEqual(
            self.client.post(f"/api/projects/{project.id}/members/", {"user_id": self.other.id}).status_code, 403
        )
        # admin can edit project but not delete it
        self.login(admin)
        self.assertEqual(self.client.patch(f"/api/projects/{project.id}/", {"name": "Y"}).status_code, 200)
        self.assertEqual(self.client.delete(f"/api/projects/{project.id}/").status_code, 403)
        # nobody can change owner role
        owner_m = project.memberships.get(role="owner")
        self.assertEqual(
            self.client.patch(f"/api/projects/{project.id}/members/{owner_m.id}/", {"role": "viewer"}).status_code, 403
        )
        # viewer cannot create tasks but can comment
        self.login(self.owner)
        task = self.client.post("/api/tasks/", {"project": project.id, "title": "T"}).data
        self.login(viewer)
        self.assertEqual(self.client.post("/api/tasks/", {"project": project.id, "title": "V"}).status_code, 400)
        self.assertEqual(self.client.patch(f"/api/tasks/{task['id']}/", {"status": "completed"}).status_code, 403)
        self.assertEqual(self.client.post(f"/api/tasks/{task['id']}/comments/", {"body": "hi"}).status_code, 201)
        # member can leave the project
        self.login(member)
        mem_m = project.memberships.get(user=member)
        self.assertEqual(self.client.delete(f"/api/projects/{project.id}/members/{mem_m.id}/").status_code, 204)


class TaskTests(BaseAPITest):
    def setUp(self):
        self.owner = self.make_user("owner")
        self.project = self.make_project(self.owner)

    def create_task(self, **kwargs):
        res = self.client.post("/api/tasks/", {"project": self.project.id, "title": "Task", **kwargs}, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        return res.data

    def test_task_crud_and_progress(self):
        t1 = self.create_task(title="One", priority="high")
        self.create_task(title="Two")
        res = self.client.patch(f"/api/tasks/{t1['id']}/", {"status": "completed"}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertIsNotNone(res.data["completed_at"])
        project = self.client.get(f"/api/projects/{self.project.id}/").data
        self.assertEqual(project["task_count"], 2)
        self.assertEqual(project["progress"], 50)
        self.assertEqual(self.client.delete(f"/api/tasks/{t1['id']}/").status_code, 204)
        self.assertEqual(self.client.get("/api/tasks/").data["count"], 1)

    def test_assignee_must_be_member(self):
        stranger = self.make_user("stranger")
        self.login(self.owner)
        res = self.client.post("/api/tasks/", {"project": self.project.id, "title": "X", "assignee_id": stranger.id})
        self.assertEqual(res.status_code, 400)
        self.assertIn("assignee_id", res.data)

    def test_filters_search_sort_pagination(self):
        today = timezone.localdate()
        self.create_task(title="Alpha bug", status="todo", priority="low", due_date=str(today - timedelta(days=2)))
        self.create_task(title="Beta feature", status="in_progress", priority="urgent", due_date=str(today + timedelta(days=3)))
        self.create_task(title="Gamma docs", status="completed", priority="medium", due_date=str(today - timedelta(days=5)))
        self.create_task(title="No date", status="todo", priority="high")

        q = lambda params: self.client.get("/api/tasks/", params).data  # noqa: E731
        self.assertEqual(q({"status": "todo"})["count"], 2)
        self.assertEqual(q({"status": "todo,in_progress"})["count"], 3)
        self.assertEqual(q({"priority": "urgent"})["count"], 1)
        self.assertEqual(q({"search": "beta"})["results"][0]["title"], "Beta feature")
        overdue = q({"overdue": "true"})
        self.assertEqual([t["title"] for t in overdue["results"]], ["Alpha bug"])
        self.assertTrue(overdue["results"][0]["is_overdue"])
        titles = [t["title"] for t in q({"ordering": "due_date"})["results"]]
        self.assertEqual(titles, ["Gamma docs", "Alpha bug", "Beta feature", "No date"])
        self.assertEqual(q({"ordering": "-priority"})["results"][0]["title"], "Beta feature")
        page = q({"page_size": 2, "page": 2})
        self.assertEqual((page["count"], page["total_pages"], len(page["results"])), (4, 2, 2))

    def test_comments_and_activity(self):
        task = self.create_task()
        res = self.client.post(f"/api/tasks/{task['id']}/comments/", {"body": "  "})
        self.assertEqual(res.status_code, 400)
        comment = self.client.post(f"/api/tasks/{task['id']}/comments/", {"body": "Nice"}).data
        self.assertEqual(self.client.get(f"/api/tasks/{task['id']}/comments/").data[0]["body"], "Nice")
        self.assertEqual(self.client.patch(f"/api/comments/{comment['id']}/", {"body": "Edited"}).data["body"], "Edited")
        activity = self.client.get(f"/api/tasks/{task['id']}/activity/").data
        self.assertEqual({a["action"] for a in activity}, {"created", "commented"})
        self.assertEqual(self.client.get(f"/api/projects/{self.project.id}/activity/").data["count"], 3)

    def test_dashboard(self):
        today = timezone.localdate()
        self.create_task(status="completed")
        self.create_task(status="todo", due_date=str(today - timedelta(days=1)))
        self.create_task(status="in_progress", due_date=str(today + timedelta(days=2)), assignee_id=self.owner.id)
        data = self.client.get("/api/dashboard/").data
        self.assertEqual(data["projects"]["total"], 1)
        t = data["tasks"]
        self.assertEqual((t["total"], t["completed"], t["pending"], t["overdue"], t["assigned_to_me"]), (3, 1, 2, 1, 1))
        self.assertEqual(t["completion_rate"], 33)
        self.assertEqual(len(data["upcoming_tasks"]), 1)
        self.assertEqual(len(data["completion_trend"]), 7)
        self.assertEqual(data["completion_trend"][-1]["completed"], 1)
        self.assertEqual(data["project_progress"][0]["progress"], 33)


class CollaborationTests(BaseAPITest):
    def setUp(self):
        self.owner, self.alice, self.bob = self.make_user("owner"), self.make_user("alice"), self.make_user("bob")
        self.project = self.make_project(self.owner, name="Team")
        self.outsider = self.make_user("outsider")

    def kinds(self, user):
        return list(Notification.objects.filter(recipient=user).values_list("kind", flat=True))

    def test_member_and_role_notifications(self):
        self.login(self.owner)
        res = self.client.post(f"/api/projects/{self.project.id}/members/", {"user_id": self.alice.id, "role": "member"}, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        self.client.patch(f"/api/projects/{self.project.id}/members/{res.data['id']}/", {"role": "admin"}, format="json")
        self.assertEqual(self.kinds(self.alice), ["role_changed", "member_added"])
        self.client.delete(f"/api/projects/{self.project.id}/members/{res.data['id']}/")
        self.assertEqual(self.kinds(self.alice)[0], "member_removed")
        self.assertEqual(self.kinds(self.owner), [])  # never notified about own actions

    def test_task_assignment_status_comment_and_mention(self):
        self.add_member(self.project, self.alice, "member")
        self.add_member(self.project, self.bob, "member")
        self.login(self.owner)
        res = self.client.post("/api/tasks/", {"project": self.project.id, "title": "Spec", "assignee_id": self.alice.id}, format="json")
        task_id = res.data["id"]
        self.assertEqual(self.kinds(self.alice), ["assigned"])

        self.login(self.alice)
        self.client.patch(f"/api/tasks/{task_id}/", {"status": "in_progress"}, format="json")
        self.assertEqual(self.kinds(self.owner), ["status_changed"])
        self.assertEqual(self.kinds(self.alice), ["assigned"])  # actor not notified

        # Mention bob (member) and outsider (not a member): only bob gets a mention.
        self.client.post(f"/api/tasks/{task_id}/comments/", {"body": "@bob can you review? cc @outsider"}, format="json")
        self.assertEqual(self.kinds(self.bob), ["mention"])
        self.assertEqual(self.kinds(self.outsider), [])
        self.assertEqual(self.kinds(self.owner)[0], "comment")  # creator gets a comment notice

        # Bob replies: alice (assignee) and owner (creator) get comment notices, bob does not.
        self.login(self.bob)
        self.client.post(f"/api/tasks/{task_id}/comments/", {"body": "Looks good"}, format="json")
        self.assertEqual(self.kinds(self.alice)[0], "comment")
        self.assertEqual(self.kinds(self.bob), ["mention"])

    def test_notification_endpoints(self):
        self.add_member(self.project, self.alice, "member")
        self.login(self.owner)
        for i in range(3):
            self.client.post("/api/tasks/", {"project": self.project.id, "title": f"T{i}", "assignee_id": self.alice.id}, format="json")

        self.login(self.bob)
        self.assertEqual(self.client.get("/api/notifications/").data["count"], 0)  # only own notifications

        self.login(self.alice)
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data["count"], 3)
        first = self.client.get("/api/notifications/").data["results"][0]
        self.assertEqual(first["actor"]["username"], "owner")
        self.assertEqual(first["project"], self.project.id)
        res = self.client.post(f"/api/notifications/{first['id']}/read/")
        self.assertTrue(res.data["is_read"])
        self.assertEqual(self.client.get("/api/notifications/?unread=true").data["count"], 2)
        self.assertEqual(self.client.post("/api/notifications/read-all/").data["updated"], 2)
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data["count"], 0)
        self.assertEqual(self.client.delete(f"/api/notifications/{first['id']}/").status_code, 204)

        self.login(self.bob)
        other = Notification.objects.filter(recipient=self.alice).first()
        self.assertEqual(self.client.post(f"/api/notifications/{other.id}/read/").status_code, 404)

    def test_team_workload(self):
        self.add_member(self.project, self.alice, "member")
        other = self.make_project(self.outsider, name="Hidden")
        Task.objects.create(project=self.project, title="A", assignee=self.alice, created_by=self.owner)
        Task.objects.create(project=self.project, title="B", assignee=self.alice, created_by=self.owner,
                            status="completed")
        Task.objects.create(project=self.project, title="C", assignee=self.alice, created_by=self.owner,
                            due_date=timezone.localdate() - timedelta(days=1))
        Task.objects.create(project=other, title="Hidden", assignee=self.outsider, created_by=self.outsider)

        self.login(self.owner)
        team = {p["username"]: p for p in self.client.get("/api/team/").data}
        self.assertEqual(set(team), {"owner", "alice"})  # outsider shares no project
        self.assertTrue(team["owner"]["is_me"])
        alice = team["alice"]
        self.assertEqual((alice["open_tasks"], alice["completed_tasks"], alice["overdue_tasks"]), (2, 1, 1))
        self.assertEqual(alice["projects"], [{"id": self.project.id, "name": "Team", "role": "member"}])
