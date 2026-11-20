import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../services/auth_provider.dart';
import '../theme.dart';
import '../widgets/activity_tile.dart';
import '../widgets/common.dart';
import '../widgets/form_dialogs.dart';
import '../widgets/task_detail_dialog.dart';
import '../widgets/task_list.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId, this.openTaskId});
  final int projectId;

  /// When set (e.g. from a notification), this task's details open after loading.
  final int? openTaskId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Project? _project;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<TaskFlowApi>().project(widget.projectId);
      if (mounted) {
        setState(() {
          _project = p;
          _error = null;
        });
        _openLinkedTask();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? 'Project not found or you are not a member.' : e.message);
    }
  }

  bool _openedLinkedTask = false;

  void _openLinkedTask() {
    final id = widget.openTaskId;
    if (id == null || _openedLinkedTask) return;
    _openedLinkedTask = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await showTaskDetail(context, id)) _load();
    });
  }

  Future<void> _edit() async {
    final updated = await showProjectForm(context, project: _project);
    if (updated != null && mounted) {
      setState(() => _project = updated);
      showSnack(context, 'Project updated');
    }
  }

  Future<void> _delete() async {
    final p = _project!;
    final ok = await confirmDialog(context,
        title: 'Delete project?',
        message: '"${p.name}" and all of its ${p.taskCount} ${p.taskCount == 1 ? 'task' : 'tasks'}, comments and history will be permanently deleted.',
        action: 'Delete',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<TaskFlowApi>().deleteProject(p.id);
      if (mounted) {
        showSnack(context, 'Project deleted');
        context.go('/projects');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return PagePadding(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => context.go('/projects'), icon: const Icon(Icons.arrow_back), label: const Text('Projects')),
          ),
          Expanded(child: ErrorState(message: _error!, onRetry: _load)),
        ]),
      );
    }
    final p = _project;
    if (p == null) return const Center(child: CircularProgressIndicator());
    final narrow = MediaQuery.sizeOf(context).width < 700;

    final header = _Header(
      project: p,
      onEdit: Roles.canEditProject(p.myRole) ? _edit : null,
      onDelete: Roles.canDeleteProject(p.myRole) ? _delete : null,
    );
    final tabs = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(text: 'Tasks (${p.taskCount})'),
        Tab(text: 'Members (${p.memberCount})'),
        const Tab(text: 'Activity'),
      ],
    );
    final views = TabBarView(children: [
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TaskListView(projectId: p.id, canCreate: Roles.canWriteTasks(p.myRole), onChanged: _load),
      ),
      _MembersTab(project: p, onChanged: _load),
      _ActivityTab(projectId: p.id),
    ]);

    return DefaultTabController(
      length: 3,
      child: PagePadding(
        child: narrow
            // On phones, let the header scroll away so the tab content has room.
            ? NestedScrollView(
                headerSliverBuilder: (_, _) => [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(child: tabs),
                ],
                body: views,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, tabs, Expanded(child: views)],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project, this.onEdit, this.onDelete});
  final Project project;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget stat(IconData icon, String label, String value, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color ?? muted),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(color: muted)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => context.go('/projects'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All projects'),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      ProjectStatusPill(p.status),
                      PriorityPill(p.priority),
                      if (p.myRole != null) RolePill(p.myRole!),
                    ]),
                  ]),
                ),
                if (onEdit != null) IconButton(tooltip: 'Edit project', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                if (onDelete != null)
                  IconButton(tooltip: 'Delete project', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
              ]),
              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.description, style: TextStyle(color: muted, height: 1.5)),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 24, runSpacing: 8, children: [
                stat(Icons.person_outline, 'Owner', p.owner?.displayName ?? '—'),
                stat(Icons.play_arrow_outlined, 'Start', formatDate(p.startDate)),
                stat(Icons.flag_outlined, 'Deadline', formatDate(p.deadline),
                    color: p.isPastDeadline ? AppColors.overdue : null),
                if (p.overdueTaskCount > 0)
                  stat(Icons.warning_amber_rounded, 'Overdue tasks', '${p.overdueTaskCount}', color: AppColors.overdue),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ProgressBar(percent: p.progress, height: 10)),
                const SizedBox(width: 12),
                Text('${p.progress}% complete', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('  (${p.completedTaskCount}/${p.taskCount})', style: TextStyle(color: muted)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Members
// ---------------------------------------------------------------------------
class _MembersTab extends StatefulWidget {
  const _MembersTab({required this.project, required this.onChanged});
  final Project project;
  final VoidCallback onChanged;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  List<Member>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await context.read<TaskFlowApi>().members(widget.project.id);
      if (mounted) {
        setState(() {
          _members = m;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final added = await showDialog<Member>(
      context: context,
      builder: (_) => _AddMemberDialog(projectId: widget.project.id, existing: _members!.map((m) => m.user.id).toSet()),
    );
    if (added != null && mounted) {
      showSnack(context, '${added.user.displayName} added as ${Roles.labels[added.role]}');
      _load();
      widget.onChanged();
    }
  }

  Future<void> _changeRole(Member m, String role) async {
    try {
      await context.read<TaskFlowApi>().updateMember(widget.project.id, m.id, role);
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _remove(Member m, {required bool self}) async {
    final ok = await confirmDialog(
      context,
      title: self ? 'Leave project?' : 'Remove member?',
      message: self
          ? 'You will lose access to "${widget.project.name}". Your assigned tasks will become unassigned.'
          : '${m.user.displayName} will lose access to this project. Their tasks will become unassigned.',
      action: self ? 'Leave' : 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<TaskFlowApi>().removeMember(widget.project.id, m.id);
      if (!mounted) return;
      if (self) {
        showSnack(context, 'You left the project');
        context.go('/projects');
      } else {
        _load();
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_members == null) return const Center(child: CircularProgressIndicator());
    final me = context.read<AuthProvider>().user?.id;
    final myRole = widget.project.myRole;
    final canManage = Roles.canManageMembers(myRole);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    bool canEdit(Member m) =>
        canManage && m.role != Roles.owner && !(myRole == Roles.admin && (m.role == Roles.admin || m.user.id == me));

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        Row(children: [
          Expanded(child: Text('Roles control what each member can do.', style: TextStyle(color: muted))),
          if (canManage) FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt), label: const Text('Add member')),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            for (final m in _members!) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: UserAvatar(user: m.user, radius: 18),
                title: Text(m.user.id == me ? '${m.user.displayName} (you)' : m.user.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('@${m.user.username} · ${m.user.email}', overflow: TextOverflow.ellipsis),
                trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  if (canEdit(m))
                    PopupMenuButton<String>(
                      tooltip: 'Change role',
                      onSelected: (r) => _changeRole(m, r),
                      itemBuilder: (_) => [
                        for (final r in Roles.assignable)
                          if (myRole == Roles.owner || r != Roles.admin)
                            PopupMenuItem(
                              value: r,
                              enabled: r != m.role,
                              child: ListTile(
                                title: Text(Roles.labels[r]!),
                                subtitle: Text(Roles.descriptions[r]!),
                                dense: true,
                              ),
                            ),
                      ],
                      child: Row(mainAxisSize: MainAxisSize.min, children: [RolePill(m.role), const Icon(Icons.arrow_drop_down)]),
                    )
                  else
                    RolePill(m.role),
                  if (m.role != Roles.owner && (canEdit(m) || m.user.id == me))
                    IconButton(
                      tooltip: m.user.id == me ? 'Leave project' : 'Remove',
                      icon: Icon(m.user.id == me ? Icons.logout : Icons.person_remove_outlined),
                      onPressed: () => _remove(m, self: m.user.id == me),
                    ),
                ]),
              ),
              if (m != _members!.last) const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final r in Roles.labels.keys)
            Row(mainAxisSize: MainAxisSize.min, children: [
              RolePill(r),
              const SizedBox(width: 6),
              Text(Roles.descriptions[r]!, style: TextStyle(fontSize: 12.5, color: muted)),
            ]),
        ]),
      ],
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.projectId, required this.existing});
  final int projectId;
  final Set<int> existing;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  Timer? _debounce;
  List<AppUser> _results = [];
  AppUser? _selected;
  String _role = Roles.member;
  bool _searching = false;
  bool _busy = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _query = q.trim();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (_query.length < 2) {
        setState(() => _results = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final users = await context.read<TaskFlowApi>().searchUsers(_query);
        if (mounted) setState(() => _results = users.where((u) => !widget.existing.contains(u.id)).toList());
      } on ApiException catch (e) {
        if (mounted) showSnack(context, e.message, error: true);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    try {
      final m = await context.read<TaskFlowApi>().addMember(widget.projectId, _selected!.id, _role);
      if (mounted) Navigator.pop(context, m);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text('Add member'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_selected == null) ...[
            TextField(
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                labelText: 'Search by name, username or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_query.length < 2 ? 'Type at least 2 characters.' : 'No users found.',
                          style: TextStyle(color: muted), textAlign: TextAlign.center),
                    )
                  : ListView(shrinkWrap: true, children: [
                      for (final u in _results)
                        ListTile(
                          leading: UserAvatar(user: u),
                          title: Text(u.displayName),
                          subtitle: Text('@${u.username} · ${u.email}', overflow: TextOverflow.ellipsis),
                          onTap: () => setState(() => _selected = u),
                        ),
                    ]),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(user: _selected!, radius: 18),
              title: Text(_selected!.displayName),
              subtitle: Text('@${_selected!.username}'),
              trailing: TextButton(onPressed: () => setState(() => _selected = null), child: const Text('Change')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final r in Roles.assignable)
                  DropdownMenuItem(value: r, child: Text('${Roles.labels[r]} — ${Roles.descriptions[r]}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _role = v!),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _selected == null || _busy ? null : _submit, child: const Text('Add')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------
class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.projectId});
  final int projectId;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  final List<Activity> _items = [];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await context.read<TaskFlowApi>().projectActivity(widget.projectId, page: _page + 1);
      if (mounted) {
        setState(() {
          _items.addAll(res.results);
          _page = res.page;
          _totalPages = res.totalPages;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _more);
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const EmptyState(icon: Icons.history, title: 'No activity yet');
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [for (final a in _items) ActivityTile(activity: a, showProject: false)]),
          ),
        ),
        if (_page < _totalPages)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton(onPressed: _loading ? null : _more, child: Text(_loading ? 'Loading…' : 'Load more')),
            ),
          ),
      ],
    );
  }
}
