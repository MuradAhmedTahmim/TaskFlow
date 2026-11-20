import 'package:intl/intl.dart';

DateTime? parseDate(dynamic v) => v == null || v == '' ? null : DateTime.tryParse(v as String)?.toLocal();
String? formatApiDate(DateTime? d) => d == null ? null : DateFormat('yyyy-MM-dd').format(d);

// ---------------------------------------------------------------------------
// Choice values shared with the backend
// ---------------------------------------------------------------------------
class TaskStatus {
  static const todo = 'todo';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const all = [todo, inProgress, completed];
  static const labels = {todo: 'To Do', inProgress: 'In Progress', completed: 'Completed'};
}

class ProjectStatus {
  static const all = ['planning', 'active', 'on_hold', 'completed'];
  static const labels = {
    'planning': 'Planning',
    'active': 'Active',
    'on_hold': 'On Hold',
    'completed': 'Completed',
  };
}

class Priority {
  static const all = ['low', 'medium', 'high', 'urgent'];
  static const labels = {'low': 'Low', 'medium': 'Medium', 'high': 'High', 'urgent': 'Urgent'};
}

class Roles {
  static const owner = 'owner';
  static const admin = 'admin';
  static const member = 'member';
  static const viewer = 'viewer';
  static const assignable = [admin, member, viewer];
  static const labels = {owner: 'Owner', admin: 'Admin', member: 'Member', viewer: 'Viewer'};
  static const descriptions = {
    owner: 'Full control, including deleting the project',
    admin: 'Edit project, manage members and all tasks',
    member: 'Create and edit tasks, comment',
    viewer: 'Read-only access, can comment',
  };

  static bool canEditProject(String? r) => r == owner || r == admin;
  static bool canDeleteProject(String? r) => r == owner;
  static bool canManageMembers(String? r) => r == owner || r == admin;
  static bool canWriteTasks(String? r) => r == owner || r == admin || r == member;
  static bool canManageAllTasks(String? r) => r == owner || r == admin;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class AppUser {
  final int id;
  final String username;
  final String email;
  final String fullName;
  final String displayName;
  final String jobTitle;
  final String bio;
  final DateTime? dateJoined;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.fullName = '',
    String? displayName,
    this.jobTitle = '',
    this.bio = '',
    this.dateJoined,
  }) : displayName = displayName ?? (fullName.isNotEmpty ? fullName : username);

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'],
        username: j['username'] ?? '',
        email: j['email'] ?? '',
        fullName: j['full_name'] ?? '',
        displayName: j['display_name'],
        jobTitle: j['job_title'] ?? '',
        bio: j['bio'] ?? '',
        dateJoined: parseDate(j['date_joined']),
      );

  static AppUser? maybe(dynamic j) => j == null ? null : AppUser.fromJson(j as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'full_name': fullName,
        'display_name': displayName,
        'job_title': jobTitle,
        'bio': bio,
        'date_joined': dateJoined?.toIso8601String(),
      };

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class Project {
  final int id;
  final String name;
  final String description;
  final AppUser? owner;
  final String status;
  final String priority;
  final DateTime? startDate;
  final DateTime? deadline;
  final String? myRole;
  final int taskCount;
  final int completedTaskCount;
  final int overdueTaskCount;
  final int memberCount;
  final int progress;
  final DateTime? createdAt;

  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.owner,
    this.status = 'planning',
    this.priority = 'medium',
    this.startDate,
    this.deadline,
    this.myRole,
    this.taskCount = 0,
    this.completedTaskCount = 0,
    this.overdueTaskCount = 0,
    this.memberCount = 0,
    this.progress = 0,
    this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'],
        name: j['name'] ?? '',
        description: j['description'] ?? '',
        owner: AppUser.maybe(j['owner']),
        status: j['status'] ?? 'planning',
        priority: j['priority'] ?? 'medium',
        startDate: parseDate(j['start_date']),
        deadline: parseDate(j['deadline']),
        myRole: j['my_role'],
        taskCount: j['task_count'] ?? 0,
        completedTaskCount: j['completed_task_count'] ?? 0,
        overdueTaskCount: j['overdue_task_count'] ?? 0,
        memberCount: j['member_count'] ?? 0,
        progress: j['progress'] ?? 0,
        createdAt: parseDate(j['created_at']),
      );

  bool get isPastDeadline {
    if (deadline == null || status == 'completed') return false;
    final now = DateTime.now();
    return deadline!.isBefore(DateTime(now.year, now.month, now.day));
  }
}

class Task {
  final int id;
  final int projectId;
  final String projectName;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final AppUser? assignee;
  final AppUser? createdBy;
  final bool isOverdue;
  final int commentCount;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? myRole;

  Task({
    required this.id,
    required this.projectId,
    this.projectName = '',
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = 'medium',
    this.dueDate,
    this.assignee,
    this.createdBy,
    this.isOverdue = false,
    this.commentCount = 0,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    this.myRole,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'],
        projectId: j['project'],
        projectName: j['project_name'] ?? '',
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        status: j['status'] ?? TaskStatus.todo,
        priority: j['priority'] ?? 'medium',
        dueDate: parseDate(j['due_date']),
        assignee: AppUser.maybe(j['assignee']),
        createdBy: AppUser.maybe(j['created_by']),
        isOverdue: j['is_overdue'] ?? false,
        commentCount: j['comment_count'] ?? 0,
        completedAt: parseDate(j['completed_at']),
        createdAt: parseDate(j['created_at']),
        updatedAt: parseDate(j['updated_at']),
        myRole: j['my_role'],
      );

  bool get isCompleted => status == TaskStatus.completed;

  Task copyWith({int? commentCount}) => Task(
        id: id,
        projectId: projectId,
        projectName: projectName,
        title: title,
        description: description,
        status: status,
        priority: priority,
        dueDate: dueDate,
        assignee: assignee,
        createdBy: createdBy,
        isOverdue: isOverdue,
        commentCount: commentCount ?? this.commentCount,
        completedAt: completedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        myRole: myRole,
      );
}

class Member {
  final int id;
  final AppUser user;
  final String role;
  final DateTime? joinedAt;

  Member({required this.id, required this.user, required this.role, this.joinedAt});

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'],
        user: AppUser.fromJson(j['user']),
        role: j['role'],
        joinedAt: parseDate(j['joined_at']),
      );
}

class Comment {
  final int id;
  final AppUser author;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Comment({required this.id, required this.author, required this.body, this.createdAt, this.updatedAt});

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'],
        author: AppUser.fromJson(j['author']),
        body: j['body'] ?? '',
        createdAt: parseDate(j['created_at']),
        updatedAt: parseDate(j['updated_at']),
      );

  bool get isEdited =>
      createdAt != null && updatedAt != null && updatedAt!.difference(createdAt!).inSeconds > 2;
}

class Activity {
  final int id;
  final int projectId;
  final String projectName;
  final int? taskId;
  final String? taskTitle;
  final AppUser? user;
  final String action;
  final String message;
  final DateTime? createdAt;

  Activity({
    required this.id,
    required this.projectId,
    this.projectName = '',
    this.taskId,
    this.taskTitle,
    this.user,
    required this.action,
    required this.message,
    this.createdAt,
  });

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'],
        projectId: j['project'],
        projectName: j['project_name'] ?? '',
        taskId: j['task'],
        taskTitle: j['task_title'],
        user: AppUser.maybe(j['user']),
        action: j['action'] ?? '',
        message: j['message'] ?? '',
        createdAt: parseDate(j['created_at']),
      );
}

class PageResult<T> {
  final int count;
  final int totalPages;
  final int page;
  final List<T> results;

  PageResult({required this.count, required this.totalPages, required this.page, required this.results});

  factory PageResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => PageResult(
        count: j['count'] ?? 0,
        totalPages: j['total_pages'] ?? 1,
        page: j['page'] ?? 1,
        results: (j['results'] as List).map((e) => parse(e as Map<String, dynamic>)).toList(),
      );
}

class AppNotification {
  final int id;
  final String kind;
  final String message;
  final bool isRead;
  final DateTime? createdAt;
  final AppUser? actor;
  final int? projectId;
  final String? projectName;
  final int? taskId;
  final String? taskTitle;

  AppNotification({
    required this.id,
    required this.kind,
    required this.message,
    this.isRead = false,
    this.createdAt,
    this.actor,
    this.projectId,
    this.projectName,
    this.taskId,
    this.taskTitle,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'],
        kind: j['kind'] ?? '',
        message: j['message'] ?? '',
        isRead: j['is_read'] ?? false,
        createdAt: parseDate(j['created_at']),
        actor: AppUser.maybe(j['actor']),
        projectId: j['project'],
        projectName: j['project_name'],
        taskId: j['task'],
        taskTitle: j['task_title'],
      );

  AppNotification markedRead() => AppNotification(
        id: id,
        kind: kind,
        message: message,
        isRead: true,
        createdAt: createdAt,
        actor: actor,
        projectId: projectId,
        projectName: projectName,
        taskId: taskId,
        taskTitle: taskTitle,
      );
}

class TeamProject {
  final int id;
  final String name;
  final String role;
  TeamProject({required this.id, required this.name, required this.role});
  factory TeamProject.fromJson(Map<String, dynamic> j) => TeamProject(id: j['id'], name: j['name'] ?? '', role: j['role'] ?? '');
}

/// A person the user shares at least one project with, and their workload
/// (counted only inside projects the user can see).
class Teammate {
  final AppUser user;
  final bool isMe;
  final List<TeamProject> projects;
  final int openTasks;
  final int inProgressTasks;
  final int completedTasks;
  final int overdueTasks;

  Teammate({
    required this.user,
    required this.isMe,
    required this.projects,
    required this.openTasks,
    required this.inProgressTasks,
    required this.completedTasks,
    required this.overdueTasks,
  });

  factory Teammate.fromJson(Map<String, dynamic> j) => Teammate(
        user: AppUser.fromJson(j),
        isMe: j['is_me'] ?? false,
        projects: ((j['projects'] ?? []) as List).map((e) => TeamProject.fromJson(e)).toList(),
        openTasks: j['open_tasks'] ?? 0,
        inProgressTasks: j['in_progress_tasks'] ?? 0,
        completedTasks: j['completed_tasks'] ?? 0,
        overdueTasks: j['overdue_tasks'] ?? 0,
      );

  int get totalTasks => openTasks + completedTasks;
}
