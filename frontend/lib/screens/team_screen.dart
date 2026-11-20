import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Everyone the user collaborates with, with each person's workload.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Teammate>? _team;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final team = await context.read<TaskFlowApi>().team();
      if (mounted) {
        setState(() {
          _team = team;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<Teammate> get _visible {
    final q = _search.toLowerCase();
    if (q.isEmpty) return _team!;
    return _team!
        .where((t) =>
            t.user.displayName.toLowerCase().contains(q) ||
            t.user.username.toLowerCase().contains(q) ||
            t.user.jobTitle.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    final others = team?.where((t) => !t.isMe).length ?? 0;
    return PagePadding(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Team',
          subtitle: team == null ? 'People you work with' : '$others teammate${others == 1 ? '' : 's'} across your projects',
          actions: [SearchField(hint: 'Search people…', onChanged: (v) => setState(() => _search = v))],
        ),
        const SizedBox(height: 20),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error != null && _team == null) return ErrorState(message: _error!, onRetry: _load);
    if (_team == null) return const Center(child: CircularProgressIndicator());
    if (_team!.length <= 1) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: 'No teammates yet',
        message: 'Add members to a project to start collaborating.',
        action: FilledButton.icon(
          onPressed: () => context.go('/projects'),
          icon: const Icon(Icons.folder_outlined),
          label: const Text('Go to projects'),
        ),
      );
    }
    final people = _visible;
    if (people.isEmpty) {
      return const EmptyState(icon: Icons.person_search_outlined, title: 'No matching people');
    }
    // Cards keep their natural height, so long project lists never get cut off.
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        const gap = 16.0;
        final columns = c.maxWidth >= 1200 ? 3 : c.maxWidth >= 760 ? 2 : 1;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Wrap(spacing: gap, runSpacing: gap, children: [
            for (final mate in people) SizedBox(width: width, child: _TeammateCard(mate: mate)),
          ]),
        );
      }),
    );
  }
}

class _TeammateCard extends StatelessWidget {
  const _TeammateCard({required this.mate});
  final Teammate mate;

  @override
  Widget build(BuildContext context) {
    final u = mate.user;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final progress = mate.totalTasks == 0 ? 0 : (mate.completedTasks * 100 / mate.totalTasks).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            UserAvatar(user: u, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mate.isMe ? '${u.displayName} (you)' : u.displayName,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  [ '@${u.username}', if (u.jobTitle.isNotEmpty) u.jobTitle].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _Stat(label: 'Open', value: mate.openTasks, color: AppColors.todo),
            _Stat(label: 'In progress', value: mate.inProgressTasks, color: AppColors.inProgress),
            _Stat(label: 'Overdue', value: mate.overdueTasks, color: AppColors.overdue),
            _Stat(label: 'Done', value: mate.completedTasks, color: AppColors.completed),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ProgressBar(percent: progress, height: 6)),
            const SizedBox(width: 10),
            Text('$progress% done', style: TextStyle(fontSize: 12, color: muted)),
          ]),
          const SizedBox(height: 12),
          Text('Shared projects', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in mate.projects)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.folder_outlined, size: 15),
                label: Text('${p.name} · ${Roles.labels[p.role] ?? p.role}', style: const TextStyle(fontSize: 12)),
                onPressed: () => context.go('/projects/${p.id}'),
              ),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.go(Uri(path: '/tasks', queryParameters: {
                'assignee': mate.isMe ? 'me' : '${u.id}',
                if (!mate.isMe) 'assignee_name': u.displayName,
              }).toString()),
              icon: const Icon(Icons.checklist, size: 18),
              label: Text(mate.isMe ? 'My tasks' : 'View tasks'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Pill(label: '$value $label', color: color);
}
