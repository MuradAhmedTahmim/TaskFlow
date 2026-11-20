import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import 'common.dart';

/// Date picker field that shows the chosen date and a clear button.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.errorText});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 10),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: const Icon(Icons.calendar_today, size: 18),
          suffixIcon: value == null
              ? null
              : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged(null)),
        ),
        child: Text(value == null ? 'Not set' : formatDate(value)),
      ),
    );
  }
}

Widget _dropdown<T>({
  required String label,
  required T value,
  required Map<T, String> items,
  required ValueChanged<T?>? onChanged,
  String? errorText,
}) {
  return DropdownButtonFormField<T>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, errorText: errorText),
    items: items.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
        .toList(),
    onChanged: onChanged,
  );
}

Widget _twoColumns(BuildContext context, Widget a, Widget b) {
  if (MediaQuery.sizeOf(context).width < 520) {
    return Column(children: [a, const SizedBox(height: 16), b]);
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: a),
    const SizedBox(width: 12),
    Expanded(child: b),
  ]);
}

Widget _dialogFrame(BuildContext context, {required String title, required Widget body, required List<Widget> actions}) {
  final width = MediaQuery.sizeOf(context).width;
  return Dialog(
    insetPadding: EdgeInsets.all(width < 600 ? 12 : 40),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
            child: Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), child: body)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ),
        ],
      ),
    ),
  );
}

Widget _saveButton(bool busy, VoidCallback onPressed, String label) => FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );

// ---------------------------------------------------------------------------
// Project form
// ---------------------------------------------------------------------------
Future<Project?> showProjectForm(BuildContext context, {Project? project}) =>
    showDialog<Project>(context: context, builder: (_) => _ProjectFormDialog(project: project));

class _ProjectFormDialog extends StatefulWidget {
  const _ProjectFormDialog({this.project});
  final Project? project;

  @override
  State<_ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<_ProjectFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project?.name);
  late final _description = TextEditingController(text: widget.project?.description);
  late String _status = widget.project?.status ?? 'planning';
  late String _priority = widget.project?.priority ?? 'medium';
  late DateTime? _start = widget.project?.startDate;
  late DateTime? _deadline = widget.project?.deadline;
  bool _busy = false;
  Map<String, String> _errors = {};

  bool get _editing => widget.project != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    if (_start != null && _deadline != null && _deadline!.isBefore(_start!)) {
      setState(() => _errors = {'deadline': 'Deadline cannot be before the start date.'});
      return;
    }
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'status': _status,
      'priority': _priority,
      'start_date': formatApiDate(_start),
      'deadline': formatApiDate(_deadline),
    };
    final api = context.read<TaskFlowApi>();
    try {
      final saved = _editing ? await api.updateProject(widget.project!.id, body) : await api.createProject(body);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      setState(() => _errors = e.fieldErrors);
      if (e.fieldErrors.isEmpty && mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _dialogFrame(
      context,
      title: _editing ? 'Edit project' : 'New project',
      body: Form(
        key: _form,
        child: Column(children: [
          TextFormField(
            controller: _name,
            autofocus: !_editing,
            maxLength: 150,
            decoration: InputDecoration(labelText: 'Project name *', errorText: _errors['name']),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: 'Description', alignLabelWithHint: true, errorText: _errors['description']),
          ),
          const SizedBox(height: 16),
          _twoColumns(
            context,
            _dropdown(label: 'Status', value: _status, items: ProjectStatus.labels, onChanged: (v) => setState(() => _status = v!)),
            _dropdown(label: 'Priority', value: _priority, items: Priority.labels, onChanged: (v) => setState(() => _priority = v!)),
          ),
          const SizedBox(height: 16),
          _twoColumns(
            context,
            DateField(label: 'Start date', value: _start, onChanged: (d) => setState(() => _start = d), errorText: _errors['start_date']),
            DateField(label: 'Deadline', value: _deadline, onChanged: (d) => setState(() => _deadline = d), errorText: _errors['deadline']),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        _saveButton(_busy, _save, _editing ? 'Save changes' : 'Create project'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Task form
// ---------------------------------------------------------------------------
Future<Task?> showTaskForm(BuildContext context, {Task? task, int? projectId}) =>
    showDialog<Task>(context: context, builder: (_) => _TaskFormDialog(task: task, projectId: projectId));

class _TaskFormDialog extends StatefulWidget {
  const _TaskFormDialog({this.task, this.projectId});
  final Task? task;
  final int? projectId;

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(text: widget.task?.description);
  late int? _projectId = widget.task?.projectId ?? widget.projectId;
  late String _status = widget.task?.status ?? TaskStatus.todo;
  late String _priority = widget.task?.priority ?? 'medium';
  late DateTime? _due = widget.task?.dueDate;
  late int? _assigneeId = widget.task?.assignee?.id;

  List<Project> _projects = [];
  List<Member> _members = [];
  bool _loading = true;
  bool _busy = false;
  Map<String, String> _errors = {};

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<TaskFlowApi>();
    try {
      final projects = await api.allProjects();
      _projects = projects.where((p) => Roles.canWriteTasks(p.myRole)).toList();
      if (_projectId == null && _projects.isNotEmpty) _projectId = _projects.first.id;
      await _loadMembers();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMembers() async {
    if (_projectId == null) return;
    final members = await context.read<TaskFlowApi>().members(_projectId!);
    setState(() {
      _members = members.where((m) => m.role != Roles.viewer || m.user.id == _assigneeId).toList();
      if (_assigneeId != null && !_members.any((m) => m.user.id == _assigneeId)) _assigneeId = null;
    });
  }

  Future<void> _save() async {
    setState(() => _errors = {});
    if (!_form.currentState!.validate()) return;
    if (_projectId == null) {
      setState(() => _errors = {'project': 'Choose a project'});
      return;
    }
    setState(() => _busy = true);
    final body = {
      'project': _projectId,
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'status': _status,
      'priority': _priority,
      'due_date': formatApiDate(_due),
      'assignee_id': _assigneeId,
    };
    final api = context.read<TaskFlowApi>();
    try {
      final saved = _editing ? await api.updateTask(widget.task!.id, body) : await api.createTask(body);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      setState(() => _errors = e.fieldErrors);
      if (e.fieldErrors.isEmpty && mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noProjects = !_loading && _projects.isEmpty;
    return _dialogFrame(
      context,
      title: _editing ? 'Edit task' : 'New task',
      body: _loading
          ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          : noProjects
              ? const EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: 'No project to add tasks to',
                  message: 'Create a project first, or ask a project admin to give you the Member role.',
                )
              : Form(
                  key: _form,
                  child: Column(children: [
                    TextFormField(
                      controller: _title,
                      autofocus: !_editing,
                      maxLength: 200,
                      decoration: InputDecoration(labelText: 'Title *', errorText: _errors['title']),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _description,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 16),
                    _dropdown<int?>(
                      label: 'Project *',
                      value: _projectId,
                      errorText: _errors['project'],
                      items: {for (final p in _projects) p.id: p.name},
                      onChanged: widget.projectId != null && !_editing
                          ? null
                          : (v) {
                              setState(() => _projectId = v);
                              _loadMembers();
                            },
                    ),
                    const SizedBox(height: 16),
                    _twoColumns(
                      context,
                      _dropdown(label: 'Status', value: _status, items: TaskStatus.labels, onChanged: (v) => setState(() => _status = v!)),
                      _dropdown(label: 'Priority', value: _priority, items: Priority.labels, onChanged: (v) => setState(() => _priority = v!)),
                    ),
                    const SizedBox(height: 16),
                    _twoColumns(
                      context,
                      DateField(label: 'Due date', value: _due, onChanged: (d) => setState(() => _due = d), errorText: _errors['due_date']),
                      _dropdown<int?>(
                        label: 'Assignee',
                        value: _assigneeId,
                        errorText: _errors['assignee_id'],
                        items: {null: 'Unassigned', for (final m in _members) m.user.id: m.user.displayName},
                        onChanged: (v) => setState(() => _assigneeId = v),
                      ),
                    ),
                  ]),
                ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        if (!noProjects) _saveButton(_busy || _loading, _save, _editing ? 'Save changes' : 'Create task'),
      ],
    );
  }
}
