import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'common.dart';

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.activity, this.showProject = true});
  final Activity activity;
  final bool showProject;

  static (IconData, Color) _style(String action) => switch (action) {
        'created' => (Icons.add_circle_outline, AppColors.completed),
        'deleted' => (Icons.delete_outline, AppColors.overdue),
        'status_changed' => (Icons.swap_horiz, AppColors.inProgress),
        'assigned' => (Icons.person_add_alt, const Color(0xFF7C3AED)),
        'commented' => (Icons.chat_bubble_outline, const Color(0xFF0891B2)),
        'member_added' => (Icons.group_add_outlined, AppColors.completed),
        'member_removed' => (Icons.person_remove_outlined, AppColors.warning),
        'role_changed' => (Icons.admin_panel_settings_outlined, AppColors.warning),
        _ => (Icons.edit_outlined, AppColors.todo),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(activity.action);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(activity.message, style: const TextStyle(height: 1.35)),
            const SizedBox(height: 2),
            Text(
              [relativeTime(activity.createdAt), if (showProject) activity.projectName].join(' · '),
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ]),
        ),
      ]),
    );
  }
}
