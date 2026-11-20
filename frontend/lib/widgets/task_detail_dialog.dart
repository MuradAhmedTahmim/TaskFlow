import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../services/auth_provider.dart';
import 'activity_tile.dart';
import 'common.dart';
import 'form_dialogs.dart';

/// Opens the task detail dialog. Resolves to true if the task was changed.
Future<bool> showTaskDetail(BuildContext context, int taskId) async {
  final width = MediaQuery.sizeOf(context).width;
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: EdgeInsets.all(width < 600 ? 8 : 40),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: _TaskDetail(taskId: taskId),
      ),
    ),
  );
  return changed ?? false;
}

bool canDeleteTask(Task t, int? userId) {
  if (Roles.canManageAllTasks(t.myRole)) return true;
  return Roles.canWriteTasks(t.myRole) && (t.createdBy?.id == userId || t.assignee?.id == userId);
}

class _TaskDetail extends StatefulWidget {
  const _TaskDetail({required this.taskId});
  final int taskId;

  @override
  State<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<_TaskDetail> {
  Task? _task;
  String? _error;
  bool _changed = false;
  int _activityVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await context.read<TaskFlowApi>().task(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = t;
        _error = null;
        _activityVersion++;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _close() => Navigator.pop(context, _changed);

  Future<void> _setStatus(String status) async {
    final t = _task!;
    try {
      final updated = await context.read<TaskFlowApi>().updateTask(t.id, {'status': status});
      setState(() {
        _task = updated;
        _changed = true;
        _activityVersion++;
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _edit() async {
    final updated = await showTaskForm(context, task: _task);
    if (updated != null) {
      setState(() {
        _task = updated;
        _changed = true;
        _activityVersion++;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete task?', message: '"${_task!.title}" and its comments will be permanently deleted.',
        action: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<TaskFlowApi>().deleteTask(_task!.id);
      if (mounted) {
        showSnack(context, 'Task deleted');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.topRight, child: IconButton(onPressed: _close, icon: const Icon(Icons.close))),
        ErrorState(message: _error!, onRetry: _load),
      ]);
    }
    final t = _task;
    if (t == null) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));

    final me = context.read<AuthProvider>().user?.id;
    final canWrite = Roles.canWriteTasks(t.myRole);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () {
                      Navigator.pop(context, _changed);
                      context.go('/projects/${t.projectId}');
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder_outlined, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Flexible(child: Text(t.projectName, style: TextStyle(color: muted), overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(t.title,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                      )),
                ]),
              ),
              if (canWrite) IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
              if (canDeleteTask(t, me))
                IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
              IconButton(tooltip: 'Close', onPressed: _close, icon: const Icon(Icons.close)),
            ]),
          ),
          Flexible(
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (canWrite)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: [
                              for (final s in TaskStatus.all)
                                ButtonSegment(value: s, label: Text(TaskStatus.labels[s]!)),
                            ],
                            selected: {t.status},
                            onSelectionChanged: (s) => _setStatus(s.first),
                          ),
                        )
                      else
                        TaskStatusPill(t.status),
                      const SizedBox(height: 16),
                      Wrap(spacing: 24, runSpacing: 12, children: [
                        _Meta(label: 'Priority', child: PriorityPill(t.priority)),
                        _Meta(label: 'Due date', child: DueDateText(due: t.dueDate, overdue: t.isOverdue, completed: t.isCompleted)),
                        _Meta(
                          label: 'Assignee',
                          child: t.assignee == null
                              ? Text('Unassigned', style: TextStyle(color: muted))
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  UserAvatar(user: t.assignee!, radius: 11),
                                  const SizedBox(width: 6),
                                  Text(t.assignee!.displayName),
                                ]),
                        ),
                        _Meta(label: 'Created by', child: Text(t.createdBy?.displayName ?? '—')),
                        _Meta(label: 'Created', child: Text(formatDate(t.createdAt))),
                        if (t.completedAt != null) _Meta(label: 'Completed', child: Text(formatDate(t.completedAt))),
                      ]),
                      const SizedBox(height: 16),
                      Text('Description', style: text.labelLarge?.copyWith(color: muted)),
                      const SizedBox(height: 6),
                      SelectableText(t.description.isEmpty ? 'No description.' : t.description,
                          style: TextStyle(color: t.description.isEmpty ? muted : null, height: 1.5)),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tabs: [
                      Tab(text: 'Comments (${t.commentCount})'),
                      const Tab(text: 'Activity'),
                    ],
                  ),
                ),
              ],
              body: TabBarView(children: [
                _Comments(
                  task: t,
                  onChanged: (delta) => setState(() {
                    _changed = true;
                    _activityVersion++;
                    _task = t.copyWith(commentCount: t.commentCount + delta);
                  }),
                ),
                _TaskActivity(key: ValueKey(_activityVersion), taskId: t.id),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      child,
    ]);
  }
}

// ---------------------------------------------------------------------------
class _Comments extends StatefulWidget {
  const _Comments({required this.task, required this.onChanged});
  final Task task;
  final ValueChanged<int> onChanged;

  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  final _input = TextEditingController();
  List<Comment>? _comments;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<TaskFlowApi>().comments(widget.task.id);
      if (!mounted) return;
      setState(() {
        _comments = c;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final c = await context.read<TaskFlowApi>().addComment(widget.task.id, body);
      _input.clear();
      setState(() => _comments = [...?_comments, c]);
      widget.onChanged(1);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(Comment c) async {
    final controller = TextEditingController(text: c.body);
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: controller, maxLines: 5, minLines: 2, autofocus: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (body == null || body.isEmpty || !mounted) return;
    try {
      final updated = await context.read<TaskFlowApi>().editComment(c.id, body);
      setState(() => _comments = _comments!.map((x) => x.id == c.id ? updated : x).toList());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(Comment c) async {
    final ok = await confirmDialog(context, title: 'Delete comment?', message: 'This cannot be undone.', action: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<TaskFlowApi>().deleteComment(c.id);
      setState(() => _comments = _comments!.where((x) => x.id != c.id).toList());
      widget.onChanged(-1);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_comments == null) return const Center(child: CircularProgressIndicator());
    final me = context.read<AuthProvider>().user?.id;
    final canModerate = Roles.canManageAllTasks(widget.task.myRole);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(children: [
      Expanded(
        child: _comments!.isEmpty
            ? const EmptyState(icon: Icons.chat_bubble_outline, title: 'No comments yet', message: 'Start the discussion below.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                itemCount: _comments!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final c = _comments![i];
                  final mine = c.author.id == me;
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    UserAvatar(user: c.author, radius: 15),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(c.author.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Text('${relativeTime(c.createdAt)}${c.isEdited ? ' · edited' : ''}',
                              style: TextStyle(fontSize: 12, color: muted)),
                          const Spacer(),
                          if (mine || canModerate)
                            PopupMenuButton<String>(
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                              itemBuilder: (_) => [
                                if (mine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                        ]),
                        const SizedBox(height: 2),
                        SelectableText(c.body, style: const TextStyle(height: 1.4)),
                      ]),
                    ),
                  ]);
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(hintText: 'Write a comment…', counterText: ''),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }
}

class _TaskActivity extends StatelessWidget {
  const _TaskActivity({super.key, required this.taskId});
  final int taskId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Activity>>(
      future: context.read<TaskFlowApi>().taskActivity(taskId),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text(snap.error.toString()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const EmptyState(icon: Icons.history, title: 'No activity yet');
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [for (final a in snap.data!) ActivityTile(activity: a, showProject: false)],
        );
      },
    );
  }
}
