import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<TaskFlowApi>().dashboard();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openTask(Task t) async {
    if (await showTaskDetail(context, t.id)) _load();
  }

  Future<void> _newTask() async {
    final t = await showTaskForm(context);
    if (t != null && mounted) {
      showSnack(context, 'Task "${t.title}" created');
      _load();
    }
  }

  Future<void> _newProject() async {
    final p = await showProjectForm(context);
    if (p != null && mounted) context.go('/projects/${p.id}');
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (_error != null && _data == null) return ErrorState(message: _error!, onRetry: _load);
    if (_data == null) return const Center(child: CircularProgressIndicator());

    final d = _data!;
    final tasks = d['tasks'] as Map<String, dynamic>;
    final projects = d['projects'] as Map<String, dynamic>;
    final upcoming = (d['upcoming_tasks'] as List).map((e) => Task.fromJson(e)).toList();
    final overdue = (d['overdue_tasks'] as List).map((e) => Task.fromJson(e)).toList();
    final activity = (d['recent_activity'] as List).map((e) => Activity.fromJson(e)).toList();
    final progress = (d['project_progress'] as List).cast<Map<String, dynamic>>();
    final trend = (d['completion_trend'] as List).cast<Map<String, dynamic>>();
    final width = MediaQuery.sizeOf(context).width;
    final twoCol = width >= 1100;

    final stats = [
      _Stat('Projects', projects['total'], Icons.folder_outlined, AppColors.brand, () => context.go('/projects')),
      _Stat('Total tasks', tasks['total'], Icons.list_alt, const Color(0xFF0891B2), () => context.go('/tasks')),
      _Stat('Completed', tasks['completed'], Icons.check_circle_outline, AppColors.completed, () => context.go('/tasks')),
      _Stat('Pending', tasks['pending'], Icons.pending_actions, AppColors.inProgress, () => context.go('/tasks')),
      _Stat('Overdue', tasks['overdue'], Icons.warning_amber_rounded, AppColors.overdue, () => context.go('/tasks?overdue=true')),
      _Stat('Assigned to me', tasks['assigned_to_me'], Icons.person_pin_outlined, const Color(0xFF7C3AED),
          () => context.go('/tasks?assignee=me')),
    ];

    final statusChart = SectionCard(
      title: 'Tasks by status',
      child: _StatusPie(
        todo: tasks['todo'],
        inProgress: tasks['in_progress'],
        completed: tasks['completed'],
        rate: tasks['completion_rate'],
      ),
    );
    final trendChart = SectionCard(title: 'Completed in the last 7 days', child: _TrendBars(trend: trend));
    final priorityCard = SectionCard(
      title: 'Open tasks by priority',
      child: _PriorityBars(counts: (tasks['by_priority_open'] as Map).cast<String, dynamic>()),
    );
    final progressCard = SectionCard(
      title: 'Project progress',
      trailing: TextButton(onPressed: () => context.go('/projects'), child: const Text('View all')),
      child: progress.isEmpty
          ? const EmptyState(icon: Icons.folder_open, title: 'No active projects')
          : Column(children: [
              for (final p in progress)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.go('/projects/${p['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(p['name'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text('${p['completed_tasks']}/${p['total_tasks']}  ',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                        Text('${p['progress']}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 6),
                      ProgressBar(percent: p['progress']),
                      if (p['deadline'] != null) ...[
                        const SizedBox(height: 4),
                        Text('Deadline ${formatDate(parseDate(p['deadline']))}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ]),
                  ),
                ),
            ]),
    );

    Widget taskSection(String title, List<Task> list, String emptyText, IconData emptyIcon) => SectionCard(
          title: title,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: list.isEmpty
              ? EmptyState(icon: emptyIcon, title: emptyText)
              : Column(children: [for (final t in list) TaskRow(task: t, dense: true, onTap: () => _openTask(t))]),
        );

    final upcomingCard = taskSection('Due in the next 7 days', upcoming, 'Nothing due this week', Icons.event_available);
    final overdueCard = taskSection('Overdue', overdue, 'No overdue tasks — great job!', Icons.celebration_outlined);
    final activityCard = SectionCard(
      title: 'Recent activity',
      child: activity.isEmpty
          ? const EmptyState(icon: Icons.history, title: 'No activity yet')
          : Column(children: [for (final a in activity) ActivityTile(activity: a)]),
    );

    Widget row(List<Widget> children) => twoCol
        ? IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                Expanded(child: children[i]),
              ],
            ]),
          )
        : Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              children[i],
            ],
          ]);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: PagePadding(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: '${_greeting()}, ${user?.displayName.split(' ').first ?? ''}',
                  subtitle: DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                  actions: [
                    IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
                    OutlinedButton.icon(onPressed: _newProject, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('New project')),
                    FilledButton.icon(onPressed: _newTask, icon: const Icon(Icons.add), label: const Text('New task')),
                  ],
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 1100 ? 6 : c.maxWidth >= 640 ? 3 : 2;
                  final w = (c.maxWidth - (cols - 1) * 16) / cols;
                  return Wrap(spacing: 16, runSpacing: 16, children: [
                    for (final s in stats) SizedBox(width: w, child: _StatCard(stat: s)),
                  ]);
                }),
                const SizedBox(height: 20),
                row([statusChart, trendChart, priorityCard]),
                const SizedBox(height: 20),
                row([progressCard, overdueCard]),
                const SizedBox(height: 20),
                row([upcomingCard, activityCard]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color, this.onTap);
  final String label;
  final dynamic value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stat.onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: stat.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(stat.icon, color: stat.color, size: 22),
            ),
            const SizedBox(height: 14),
            Text('${stat.value}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(stat.label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 8),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _StatusPie extends StatelessWidget {
  const _StatusPie({required this.todo, required this.inProgress, required this.completed, required this.rate});
  final int todo;
  final int inProgress;
  final int completed;
  final int rate;

  @override
  Widget build(BuildContext context) {
    final total = todo + inProgress + completed;
    if (total == 0) return const SizedBox(height: 180, child: EmptyState(icon: Icons.pie_chart_outline, title: 'No tasks yet'));
    final sections = [
      (todo, AppColors.todo),
      (inProgress, AppColors.inProgress),
      (completed, AppColors.completed),
    ];
    return SizedBox(
      height: 190,
      child: Row(children: [
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (final (v, c) in sections)
                  if (v > 0) PieChartSectionData(value: v.toDouble(), color: c, radius: 22, showTitle: false),
              ],
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$rate%', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('done', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Legend(color: AppColors.todo, label: 'To Do', value: todo),
          _Legend(color: AppColors.inProgress, label: 'In Progress', value: inProgress),
          _Legend(color: AppColors.completed, label: 'Completed', value: completed),
        ]),
      ]),
    );
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.trend});
  final List<Map<String, dynamic>> trend;

  @override
  Widget build(BuildContext context) {
    final values = trend.map((e) => (e['completed'] as num).toDouble()).toList();
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 190,
      child: BarChart(BarChartData(
        maxY: maxY < 4 ? 4 : maxY + 1,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: muted.withValues(alpha: 0.15), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${rod.toY.toInt()} completed',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: TextStyle(fontSize: 11, color: muted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                final date = DateTime.parse(trend[i]['date']);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('E').format(date), style: TextStyle(fontSize: 11, color: muted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: 18,
                color: AppColors.completed,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              ),
            ]),
        ],
      )),
    );
  }
}

class _PriorityBars extends StatelessWidget {
  const _PriorityBars({required this.counts});
  final Map<String, dynamic> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + (b as int));
    return SizedBox(
      height: 190,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final p in Priority.all.reversed)
            Row(children: [
              SizedBox(width: 70, child: Text(Priority.labels[p]!)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (counts[p] ?? 0) / total,
                    minHeight: 14,
                    color: AppColors.priority(p),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(width: 36, child: Text('${counts[p] ?? 0}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
        ],
      ),
    );
  }
}
