import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/api_client.dart';
import '../services/notification_center.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _items = [];
  bool _unreadOnly = false;
  int _page = 1;
  int _totalPages = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final api = context.read<TaskFlowApi>();
    final center = context.read<NotificationCenter>();
    setState(() {
      _loading = true;
      if (reset) _page = 1;
    });
    try {
      final data = await api.notifications(page: _page, unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(data.results);
        _totalPages = data.totalPages;
        _error = null;
      });
      center.refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    _page++;
    _load();
  }

  void _replace(AppNotification n) {
    final i = _items.indexWhere((x) => x.id == n.id);
    if (i >= 0) setState(() => _items[i] = n);
  }

  Future<void> _open(AppNotification n) async {
    final center = context.read<NotificationCenter>();
    if (!n.isRead) {
      _replace(n.markedRead());
      center.setUnread(center.unread - 1);
      context.read<TaskFlowApi>().markNotificationRead(n.id).catchError((_) {});
    }
    if (n.projectId == null) return;
    context.go(n.taskId != null ? '/projects/${n.projectId}?task=${n.taskId}' : '/projects/${n.projectId}');
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<TaskFlowApi>().markAllNotificationsRead();
      if (!mounted) return;
      context.read<NotificationCenter>().setUnread(0);
      setState(() {
        if (_unreadOnly) {
          _items.clear();
        } else {
          for (var i = 0; i < _items.length; i++) {
            _items[i] = _items[i].markedRead();
          }
        }
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(AppNotification n) async {
    try {
      await context.read<TaskFlowApi>().deleteNotification(n.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.id == n.id));
      if (!n.isRead) {
        final center = context.read<NotificationCenter>();
        center.setUnread(center.unread - 1);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationCenter>().unread;
    return PagePadding(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Notifications',
          subtitle: unread == 0 ? 'You are all caught up' : '$unread unread',
          actions: [
            OutlinedButton.icon(
              onPressed: unread == 0 ? null : _markAllRead,
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all as read'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('All'),
            selected: !_unreadOnly,
            onSelected: (_) {
              setState(() => _unreadOnly = false);
              _load(reset: true);
            },
          ),
          ChoiceChip(
            label: const Text('Unread'),
            selected: _unreadOnly,
            onSelected: (_) {
              setState(() => _unreadOnly = true);
              _load(reset: true);
            },
          ),
        ]),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: () => _load(reset: true));
    if (_items.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : EmptyState(
              icon: Icons.notifications_none,
              title: _unreadOnly ? 'No unread notifications' : 'No notifications yet',
              message: 'You will be notified when teammates assign you tasks, mention you or comment on your work.',
            );
    }
    final hasMore = _page < _totalPages;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _items.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) {
            if (i == _items.length) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: TextButton(onPressed: _loading ? null : _loadMore, child: const Text('Load more')),
                ),
              );
            }
            final n = _items[i];
            return NotificationTile(notification: n, onTap: () => _open(n), onDelete: () => _delete(n));
          },
        ),
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, required this.onTap, required this.onDelete});
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static IconData iconFor(String kind) => switch (kind) {
        'assigned' => Icons.assignment_ind_outlined,
        'status_changed' => Icons.published_with_changes,
        'comment' => Icons.chat_bubble_outline,
        'mention' => Icons.alternate_email,
        'member_added' => Icons.group_add_outlined,
        'member_removed' => Icons.person_remove_outlined,
        'role_changed' => Icons.admin_panel_settings_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Material(
      color: n.isRead ? Colors.transparent : scheme.primaryContainer.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              n.actor != null
                  ? UserAvatar(user: n.actor!, radius: 18)
                  : CircleAvatar(radius: 18, backgroundColor: scheme.surfaceContainerHighest, child: Icon(Icons.person_outline, color: muted)),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                  child: Icon(iconFor(n.kind), size: 13, color: AppColors.inProgress),
                ),
              ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600, height: 1.35)),
                const SizedBox(height: 4),
                Text(
                  [relativeTime(n.createdAt), if (n.projectName != null) n.projectName!].join(' · '),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ]),
            ),
            if (!n.isRead)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 8),
                child: Container(width: 9, height: 9, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              iconSize: 18,
              onSelected: (_) => onDelete(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove'))],
            ),
          ]),
        ),
      ),
    );
  }
}
