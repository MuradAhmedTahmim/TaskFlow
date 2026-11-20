import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_dialogs.dart';

const _orderings = {
  '-created_at': 'Newest first',
  'deadline': 'Deadline (soonest)',
  'name': 'Name (A–Z)',
  '-updated_at': 'Recently updated',
};

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _search = '';
  String _status = '';
  String _priority = '';
  String _ordering = '-created_at';
  int _page = 1;
  PageResult<Project>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<TaskFlowApi>().projects(
            page: _page,
            search: _search,
            status: _status,
            priority: _priority,
            ordering: _ordering,
          );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
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

  Future<void> _create() async {
    final project = await showProjectForm(context);
    if (project != null && mounted) {
      showSnack(context, 'Project "${project.name}" created');
      context.go('/projects/${project.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Projects',
            subtitle: _data == null ? null : '${_data!.count} project${_data!.count == 1 ? '' : 's'}',
            actions: [FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New project'))],
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            SearchField(hint: 'Search projects…', onChanged: (v) => _apply(() => _search = v)),
            FilterDropdown<String>(
              label: 'Status',
              value: _status,
              items: {'': 'All statuses', ...ProjectStatus.labels},
              onChanged: (v) => _apply(() => _status = v ?? ''),
            ),
            FilterDropdown<String>(
              label: 'Priority',
              value: _priority,
              width: 150,
              items: {'': 'All priorities', ...Priority.labels},
              onChanged: (v) => _apply(() => _priority = v ?? ''),
            ),
            FilterDropdown<String>(
              label: 'Sort by',
              value: _ordering,
              width: 190,
              items: _orderings,
              onChanged: (v) => _apply(() => _ordering = v ?? '-created_at'),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          const SizedBox(height: 8),
          Expanded(child: _body()),
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
      ),
    );
  }

  Widget _body() {
    if (_error != null && _data == null) return ErrorState(message: _error!, onRetry: _load);
    if (_data == null) return const Center(child: CircularProgressIndicator());
    if (_data!.results.isEmpty) {
      final filtered = _search.isNotEmpty || _status.isNotEmpty || _priority.isNotEmpty;
      return filtered
          ? const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'No matching projects', message: 'Try changing the filters.')
          : EmptyState(
              icon: Icons.folder_open,
              title: 'No projects yet',
              message: 'Create a project to start organizing your tasks.',
              action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New project')),
            );
    }
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 360).floor().clamp(1, 4);
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          mainAxisExtent: 236,
        ),
        itemCount: _data!.results.length,
        itemBuilder: (_, i) => ProjectCard(project: _data!.results[i]),
      );
    });
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/projects/${p.id}'),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.projectStatus(p.status), width: 4))),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (p.myRole != null) RolePill(p.myRole!),
              ]),
              const SizedBox(height: 6),
              Text(
                p.description.isEmpty ? 'No description' : p.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [ProjectStatusPill(p.status), PriorityPill(p.priority)]),
              const Spacer(),
              Row(children: [
                Text('${p.progress}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text('${p.completedTaskCount}/${p.taskCount} tasks', style: TextStyle(color: muted, fontSize: 12.5)),
                const Spacer(),
                if (p.overdueTaskCount > 0)
                  Pill(label: '${p.overdueTaskCount} overdue', color: AppColors.overdue, icon: Icons.warning_amber_rounded),
              ]),
              const SizedBox(height: 6),
              ProgressBar(percent: p.progress),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.group_outlined, size: 16, color: muted),
                const SizedBox(width: 4),
                Text('${p.memberCount}', style: TextStyle(color: muted, fontSize: 12.5)),
                const Spacer(),
                Icon(Icons.flag_outlined, size: 16, color: p.isPastDeadline ? AppColors.overdue : muted),
                const SizedBox(width: 4),
                Text(formatDate(p.deadline, empty: 'No deadline'),
                    style: TextStyle(color: p.isPastDeadline ? AppColors.overdue : muted, fontSize: 12.5)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
