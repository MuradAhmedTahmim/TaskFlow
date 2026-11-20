import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------
String formatDate(DateTime? d, {String empty = '—'}) => d == null ? empty : DateFormat('d MMM yyyy').format(d);

String relativeTime(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM yyyy').format(d);
}

String dueLabel(DateTime? due, {bool completed = false}) {
  if (due == null) return 'No due date';
  if (completed) return formatDate(due);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(due.year, due.month, due.day).difference(today).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days == -1) return 'Overdue by 1 day';
  if (days < 0) return 'Overdue by ${-days} days';
  if (days < 7) return 'Due in $days days';
  return 'Due ${formatDate(due)}';
}

// ---------------------------------------------------------------------------
// Feedback helpers
// ---------------------------------------------------------------------------
void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? scheme.error : null,
      width: MediaQuery.sizeOf(context).width > 600 ? 420 : null,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Small visual components
// ---------------------------------------------------------------------------
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 14});
  final AppUser user;
  final double radius;

  static const _palette = [
    Color(0xFF4F46E5), Color(0xFF0891B2), Color(0xFF059669), Color(0xFFD97706),
    Color(0xFFDB2777), Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFFDC2626),
  ];

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: user.displayName,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _palette[user.id % _palette.length],
        child: Text(user.initials,
            style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      'in_progress' => Icons.timelapse,
      'completed' => Icons.check_circle,
      _ => Icons.radio_button_unchecked,
    };
    return Pill(label: TaskStatus.labels[status] ?? status, color: AppColors.taskStatus(status), icon: icon);
  }
}

class ProjectStatusPill extends StatelessWidget {
  const ProjectStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) =>
      Pill(label: ProjectStatus.labels[status] ?? status, color: AppColors.projectStatus(status));
}

class PriorityPill extends StatelessWidget {
  const PriorityPill(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) =>
      Pill(label: Priority.labels[priority] ?? priority, color: AppColors.priority(priority), icon: Icons.flag);
}

class RolePill extends StatelessWidget {
  const RolePill(this.role, {super.key});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      Roles.owner => const Color(0xFF7C3AED),
      Roles.admin => AppColors.inProgress,
      Roles.member => AppColors.completed,
      _ => AppColors.todo,
    };
    return Pill(label: Roles.labels[role] ?? role, color: color);
  }
}

class DueDateText extends StatelessWidget {
  const DueDateText({super.key, required this.due, this.completed = false, this.overdue = false});
  final DateTime? due;
  final bool completed;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = overdue ? AppColors.overdue : muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(overdue ? Icons.warning_amber_rounded : Icons.event, size: 15, color: color),
        const SizedBox(width: 4),
        Text(dueLabel(due, completed: completed),
            style: TextStyle(fontSize: 12.5, color: color, fontWeight: overdue ? FontWeight.w600 : null)),
      ],
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.percent, this.height = 8});
  final int percent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 100
        ? AppColors.completed
        : percent >= 50
            ? AppColors.inProgress
            : AppColors.warning;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: height,
        color: color,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

class PagePadding extends StatelessWidget {
  const PagePadding({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 600 ? 16.0 : 28.0;
    return Padding(padding: EdgeInsets.fromLTRB(pad, pad, pad, 0), child: child);
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.padding});
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: TextStyle(color: muted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off,
        title: 'Something went wrong',
        message: message,
        action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      );
}

/// Pagination control: "Showing 11–20 of 42"  ‹ 2 / 5 ›
class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.totalPages, required this.count, required this.pageSize, required this.onPage});
  final int page;
  final int totalPages;
  final int count;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final from = (page - 1) * pageSize + 1;
    final to = (page * pageSize).clamp(0, count);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text('Showing $from–$to of $count',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('$page / $totalPages'),
          IconButton(
            tooltip: 'Next page',
            onPressed: page < totalPages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Search box that reports changes after the user stops typing.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search…', this.width = 260});
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => widget.onChanged(v.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        onChanged: _changed,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _changed('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Compact labelled dropdown used in filter bars.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 170,
  });
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
