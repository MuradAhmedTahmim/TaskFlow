import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'common.dart';
import 'form_dialogs.dart';
import 'task_detail_dialog.dart';

const taskOrderings = {
  '-created_at': 'Newest first',
  'due_date': 'Deadline (soonest)',
  '-due_date': 'Deadline (latest)',
  '-priority': 'Priority (highest)',
  'priority': 'Priority (lowest)',
  'title': 'Title (A–Z)',
  '-updated_at': 'Recently updated',
};

/// Searchable, filterable, paginated list of tasks. When [projectId] is set,
/// only tasks from that project are shown.
class TaskListView extends StatefulWidget {
  const TaskListView({super.key, this.projectId, this.canCreate = true, this.onChanged, this.initialAssignee, this.initialOverdue = false});
  final int? projectId;
  final bool canCreate;
  final VoidCallback? onChanged;
  final String? initialAssignee;
  final bool initialOverdue;

  @override
  State<TaskListView> createState() => TaskListViewState();
}

class TaskListViewState extends State<TaskListView> {
  String _search = '';
  String _status = '';
  String _priority = '';
  String _ordering = 'due_date';
  int? _project;
  late String? _assignee = widget.initialAssignee;
  late bool _overdue = widget.initialOverdue;
  int _page = 1;

  PageResult<Task>? _data;
  List<Project> _projects = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.projectId == null) {
      context.read<TaskFlowApi>().allProjects().then((p) {
        if (mounted) setState(() => _projects = p);
      }).catchError((_) {});
    }
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<TaskFlowApi>().tasks(
            page: _page,
            project: widget.projectId ?? _project,
            search: _search,
            status: _status,
            priority: _priority,
            assignee: _assignee,
            overdue: _overdue,
            ordering: _ordering,
          );
      if (!mounted) return;
      if (data.results.isEmpty && _page > 1 && data.count > 0) {
        _page = data.totalPages;
        await _load();
        return;
      }
      setState(() {
        _data = data;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(VoidCallback change) {
    setState(change);
    _page = 1;
    _load();
  }

  void _changed() {
    _load();
    widget.onChanged?.call();
  }

  Future<void> _create() async {
    final task = await showTaskForm(context, projectId: widget.projectId);
    if (task != null && mounted) {
      showSnack(context, 'Task "${task.title}" created');
      _changed();
    }
  }

  Future<void> _open(Task t) async {
    if (await showTaskDetail(context, t.id)) _changed();
  }

  Future<void> _quickStatus(Task t, String status) async {
    try {
      await context.read<TaskFlowApi>().updateTask(t.id, {'status': status});
      _changed();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  bool get _hasFilters =>
      _search.isNotEmpty || _status.isNotEmpty || _priority.isNotEmpty || _project != null || _assignee != null || _overdue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filters(context),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(child: _body(context)),
        if (_data != null)
          Pager(
            page: _data!.page,
            totalPages: _data!.totalPages,
            count: _data!.count,
            pageSize: AppConfig.pageSize,
            onPage: (p) {
              _page = p;
              _load();
            },
          ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SearchField(hint: 'Search tasks…', onChanged: (v) => _apply(() => _search = v)),
        if (widget.projectId == null)
          FilterDropdown<int?>(
            label: 'Project',
            value: _project,
            width: 200,
            items: {null: 'All projects', for (final p in _projects) p.id: p.name},
            onChanged: (v) => _apply(() => _project = v),
          ),
        FilterDropdown<String>(
          label: 'Status',
          value: _status,
          width: 150,
          items: {'': 'All statuses', ...TaskStatus.labels},
          onChanged: (v) => _apply(() => _status = v ?? ''),
        ),
        FilterDropdown<String>(
          label: 'Priority',
          value: _priority,
          width: 140,
          items: {'': 'All priorities', ...Priority.labels},
          onChanged: (v) => _apply(() => _priority = v ?? ''),
        ),
        FilterDropdown<String>(
          label: 'Sort by',
          value: _ordering,
          width: 190,
          items: taskOrderings,
          onChanged: (v) => _apply(() => _ordering = v ?? 'due_date'),
        ),
        FilterChip(
          label: const Text('Assigned to me'),
          selected: _assignee == 'me',
          onSelected: (v) => _apply(() => _assignee = v ? 'me' : null),
        ),
        FilterChip(
          label: const Text('Overdue'),
          selected: _overdue,
          onSelected: (v) => _apply(() => _overdue = v),
        ),
        if (widget.canCreate)
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New task')),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null && _data == null) return ErrorState(message: _error!, onRetry: _load);
    if (_data == null) return const Center(child: CircularProgressIndicator());
    if (_data!.results.isEmpty) {
      return _hasFilters
          ? const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'No matching tasks', message: 'Try changing the filters.')
          : EmptyState(
              icon: Icons.task_alt,
              title: 'No tasks yet',
              message: widget.canCreate ? 'Create your first task to get started.' : null,
              action: widget.canCreate
                  ? FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New task'))
                  : null,
            );
    }
    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _data!.results.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) {
          final t = _data!.results[i];
          return TaskRow(
            task: t,
            showProject: widget.projectId == null,
            onTap: () => _open(t),
            onStatus: Roles.canWriteTasks(t.myRole) ? (s) => _quickStatus(t, s) : null,
          );
        },
      ),
    );
  }
}

/// A single task line used in lists and on the dashboard.
class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task, required this.onTap, this.onStatus, this.showProject = true, this.dense = false});
  final Task task;
  final VoidCallback onTap;
  final ValueChanged<String>? onStatus;
  final bool showProject;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final wide = MediaQuery.sizeOf(context).width >= 760 && !dense;

    final checkbox = Tooltip(
      message: t.isCompleted ? 'Mark as to do' : 'Mark as completed',
      child: Checkbox(
        value: t.isCompleted,
        shape: const CircleBorder(),
        activeColor: AppColors.completed,
        onChanged: onStatus == null ? null : (v) => onStatus!(v! ? TaskStatus.completed : TaskStatus.todo),
      ),
    );

    final title = Text(
      t.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
        color: t.isCompleted ? muted : null,
      ),
    );

    final sub = Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (showProject)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_outlined, size: 14, color: muted),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(t.projectName, style: TextStyle(fontSize: 12.5, color: muted), overflow: TextOverflow.ellipsis),
          ),
        ]),
      DueDateText(due: t.dueDate, overdue: t.isOverdue, completed: t.isCompleted),
      if (t.commentCount > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, size: 13, color: muted),
          const SizedBox(width: 3),
          Text('${t.commentCount}', style: TextStyle(fontSize: 12.5, color: muted)),
        ]),
    ]);

    final statusWidget = onStatus == null
        ? TaskStatusPill(t.status)
        : PopupMenuButton<String>(
            tooltip: 'Change status',
            onSelected: onStatus,
            itemBuilder: (_) => [
              for (final s in TaskStatus.all)
                PopupMenuItem(value: s, enabled: s != t.status, child: TaskStatusPill(s)),
            ],
            child: TaskStatusPill(t.status),
          );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 4 : 8),
        child: Row(children: [
          checkbox,
          const SizedBox(width: 4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 4),
              sub,
              if (!wide) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [statusWidget, PriorityPill(t.priority)]),
              ],
            ]),
          ),
          if (wide) ...[
            const SizedBox(width: 12),
            SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: statusWidget)),
            SizedBox(width: 100, child: Align(alignment: Alignment.centerLeft, child: PriorityPill(t.priority))),
          ],
          const SizedBox(width: 8),
          if (t.assignee != null)
            UserAvatar(user: t.assignee!, radius: 14)
          else
            Tooltip(
              message: 'Unassigned',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(Icons.person_outline, size: 16, color: muted),
              ),
            ),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }
}
