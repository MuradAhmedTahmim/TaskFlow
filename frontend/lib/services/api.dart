import '../config.dart';
import '../models/models.dart';
import 'api_client.dart';

/// Typed wrappers around the TaskFlow REST endpoints.
class TaskFlowApi {
  TaskFlowApi(this.client);
  final ApiClient client;

  // ---- projects ----------------------------------------------------------
  Future<PageResult<Project>> projects({
    int page = 1,
    int pageSize = AppConfig.pageSize,
    String? search,
    String? status,
    String? priority,
    String? ordering,
  }) async {
    final data = await client.get('/projects/', query: {
      'page': page,
      'page_size': pageSize,
      'search': search,
      'status': status,
      'priority': priority,
      'ordering': ordering,
    });
    return PageResult.fromJson(data, Project.fromJson);
  }

  /// All projects the user belongs to (for dropdowns).
  Future<List<Project>> allProjects() async => (await projects(pageSize: 100, ordering: 'name')).results;

  Future<Project> project(int id) async => Project.fromJson(await client.get('/projects/$id/'));
  Future<Project> createProject(Map<String, dynamic> body) async =>
      Project.fromJson(await client.post('/projects/', body));
  Future<Project> updateProject(int id, Map<String, dynamic> body) async =>
      Project.fromJson(await client.patch('/projects/$id/', body));
  Future<void> deleteProject(int id) => client.delete('/projects/$id/');

  Future<List<Member>> members(int projectId) async =>
      (await client.get('/projects/$projectId/members/') as List).map((e) => Member.fromJson(e)).toList();
  Future<Member> addMember(int projectId, int userId, String role) async =>
      Member.fromJson(await client.post('/projects/$projectId/members/', {'user_id': userId, 'role': role}));
  Future<Member> updateMember(int projectId, int memberId, String role) async =>
      Member.fromJson(await client.patch('/projects/$projectId/members/$memberId/', {'role': role}));
  Future<void> removeMember(int projectId, int memberId) => client.delete('/projects/$projectId/members/$memberId/');

  Future<PageResult<Activity>> projectActivity(int projectId, {int page = 1}) async =>
      PageResult.fromJson(
          await client.get('/projects/$projectId/activity/', query: {'page': page, 'page_size': 15}),
          Activity.fromJson);

  // ---- tasks -------------------------------------------------------------
  Future<PageResult<Task>> tasks({
    int page = 1,
    int pageSize = AppConfig.pageSize,
    int? project,
    String? search,
    String? status,
    String? priority,
    String? assignee,
    bool overdue = false,
    String? ordering,
  }) async {
    final data = await client.get('/tasks/', query: {
      'page': page,
      'page_size': pageSize,
      'project': project,
      'search': search,
      'status': status,
      'priority': priority,
      'assignee': assignee,
      'overdue': overdue ? 'true' : null,
      'ordering': ordering,
    });
    return PageResult.fromJson(data, Task.fromJson);
  }

  Future<Task> task(int id) async => Task.fromJson(await client.get('/tasks/$id/'));
  Future<Task> createTask(Map<String, dynamic> body) async => Task.fromJson(await client.post('/tasks/', body));
  Future<Task> updateTask(int id, Map<String, dynamic> body) async =>
      Task.fromJson(await client.patch('/tasks/$id/', body));
  Future<void> deleteTask(int id) => client.delete('/tasks/$id/');

  Future<List<Comment>> comments(int taskId) async =>
      (await client.get('/tasks/$taskId/comments/') as List).map((e) => Comment.fromJson(e)).toList();
  Future<Comment> addComment(int taskId, String body) async =>
      Comment.fromJson(await client.post('/tasks/$taskId/comments/', {'body': body}));
  Future<Comment> editComment(int id, String body) async =>
      Comment.fromJson(await client.patch('/comments/$id/', {'body': body}));
  Future<void> deleteComment(int id) => client.delete('/comments/$id/');

  Future<List<Activity>> taskActivity(int taskId) async =>
      (await client.get('/tasks/$taskId/activity/') as List).map((e) => Activity.fromJson(e)).toList();

  // ---- misc --------------------------------------------------------------
  Future<Map<String, dynamic>> dashboard() async => await client.get('/dashboard/') as Map<String, dynamic>;

  Future<List<AppUser>> searchUsers(String query) async =>
      (await client.get('/users/', query: {'search': query}) as List).map((e) => AppUser.fromJson(e)).toList();
}
