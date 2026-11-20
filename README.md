# TaskFlow — Smart Task and Project Management System

Web Technology course project (North East University Bangladesh, CSE).

| Layer | Technology |
|---|---|
| Frontend | Flutter Web (Dart) — `frontend/` |
| Backend | Python, Django, Django REST Framework — `backend/` |
| Database | MySQL (via PyMySQL) |
| Auth | JWT (`djangorestframework-simplejwt`, refresh-token rotation + blacklist on logout) |

## Features

- **User management** — register, login (username *or* email), logout, view/update profile, change password, delete account (password confirmation), protected pages and API endpoints.
- **Projects** — full CRUD; description, status, priority, start date, deadline; progress %, task/overdue counts.
- **Tasks** — full CRUD; status (To Do / In Progress / Completed), priority, due date, assignee; organized by project.
- **Dashboard** — total projects/tasks, completed/pending/overdue, assigned to me, status donut chart, 7‑day completion chart, priority breakdown, project progress, upcoming & overdue tasks, recent activity.
- **Search & filtering** — search projects and tasks, filter by status/priority/project/assignee/overdue, sort by deadline/priority/etc., pagination.
- **Advanced** — project members with roles (Owner / Admin / Member / Viewer), task assignment, task comments, activity history, role-based access control enforced on the backend.
- **Team collaboration** — a Team page lists everyone you share a project with, their shared projects and workload (open / in progress / overdue / done) with a link to their tasks. Comments support `@username` mentions (with a picker), highlighted in the thread.
- **Notifications** — in-app notifications with an unread badge (refreshed every 30 s) when someone assigns you a task, changes the status of a task you created or are assigned, comments on a task you're involved in, @mentions you, adds or removes you from a project or changes your role. Clicking one opens the related project/task; mark one or all as read.

### Roles

| Role | Can do |
|---|---|
| Owner | Everything, including deleting the project |
| Admin | Edit project, manage members, manage all tasks |
| Member | Create/edit tasks, delete own tasks, comment |
| Viewer | Read-only, can comment |

## Database design

`accounts_user` · `core_project` · `core_projectmember` (project ↔ user, role, unique pair) · `core_task` (→ project, assignee, created_by) · `core_comment` (→ task, author) · `core_activitylog` (→ project, task, user) · `core_notification` (→ recipient, actor, project, task).
All relationships use foreign keys with appropriate `CASCADE` / `SET NULL` rules.

---

## Quick start (after setup)

Double-click `start.bat` in the project folder. It opens two server windows (backend on 8000, frontend on 8080) and then opens http://localhost:8080. Close those two windows to stop the app. The MySQL80 service must be running.

## 1. Backend setup

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
copy .env.example .env      # then edit .env
```

### MySQL

Create the database (MySQL Workbench or `mysql -u root -p`):

```sql
CREATE DATABASE taskflow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

In `backend/.env` set:

```
DB_ENGINE=mysql
DB_NAME=taskflow
DB_USER=root
DB_PASSWORD=your-mysql-password
```

(`DB_ENGINE=sqlite` runs without MySQL for quick testing.)

The project pins Django 5.2 LTS, which supports MySQL 8.0+. Django 6.x requires MySQL 8.4.

### Migrate, seed and run

```powershell
.\.venv\Scripts\python manage.py migrate
.\.venv\Scripts\python manage.py seed_demo        # optional demo data
.\.venv\Scripts\python manage.py createsuperuser  # optional, for /admin
.\.venv\Scripts\python manage.py runserver 127.0.0.1:8000
```

Demo accounts created by `seed_demo`: `demo`, `rahim`, `karim`, `nadia` — password `TaskFlow@123`.

Run the API tests:

```powershell
.\.venv\Scripts\python manage.py test
```

## 2. Frontend setup

```powershell
cd frontend
flutter pub get
flutter run -d chrome
```

The API URL defaults to `http://127.0.0.1:8000/api`. Override it with
`--dart-define=API_BASE_URL=https://your-server/api`.

Production build: `flutter build web` → static files in `frontend/build/web`.

---

## API reference (all under `/api/`)

| Method | Endpoint | Description |
|---|---|---|
| POST | `auth/register/` | Create account → tokens + user |
| POST | `auth/login/` | Login (username or email) → tokens + user |
| POST | `auth/refresh/` | Refresh access token |
| POST | `auth/logout/` | Blacklist refresh token |
| GET/PATCH/DELETE | `auth/me/` | View / update profile / delete account (`{"password": ...}`) |
| POST | `auth/change-password/` | Change password |
| GET | `users/?search=` | Find users (to add as members) |
| GET/POST | `projects/` | List (search, status, priority, ordering, page) / create |
| GET/PATCH/DELETE | `projects/{id}/` | Project detail / update / delete |
| GET/POST | `projects/{id}/members/` | List / add members |
| PATCH/DELETE | `projects/{id}/members/{member_id}/` | Change role / remove (or leave) |
| GET | `projects/{id}/activity/` | Project activity (paginated) |
| GET/POST | `tasks/` | List (project, status, priority, assignee=me, overdue, search, ordering, page) / create |
| GET/PATCH/DELETE | `tasks/{id}/` | Task detail / update / delete |
| GET/POST | `tasks/{id}/comments/` | List / add comments |
| GET | `tasks/{id}/activity/` | Task history |
| PATCH/DELETE | `comments/{id}/` | Edit / delete comment |
| GET | `dashboard/` | Dashboard statistics |
| GET | `activity/` | Recent activity feed |
| GET | `team/` | People you share projects with, and their workload |
| GET | `notifications/?unread=true` | Your notifications (paginated) |
| GET | `notifications/unread-count/` | Unread count for the badge |
| POST | `notifications/{id}/read/` | Mark one as read |
| POST | `notifications/read-all/` | Mark all as read |
| DELETE | `notifications/{id}/` | Remove a notification |

Filters accept comma-separated values, e.g. `tasks/?status=todo,in_progress&ordering=due_date`.

## Security

Password hashing (Django PBKDF2) and Django password validators. Every endpoint except register/login needs a JWT. Users can only see projects they belong to. Role checks run on the server. Backend validation is used even where the Flutter forms also validate (blank fields, date ranges, assignee must be a project member, duplicate members, and so on). CORS is restricted to localhost in debug mode.
