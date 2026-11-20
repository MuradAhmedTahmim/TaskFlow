import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import 'common.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Dest('/', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Dest('/projects', 'Projects', Icons.folder_outlined, Icons.folder),
  _Dest('/tasks', 'Tasks', Icons.check_circle_outline, Icons.check_circle),
  _Dest('/profile', 'Profile', Icons.person_outline, Icons.person),
];

/// Responsive navigation: side rail on wide screens, drawer on narrow ones.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  int get _index {
    for (var i = _destinations.length - 1; i > 0; i--) {
      if (location.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(selected: _index),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const _Logo(),
        actions: const [_UserMenu(), SizedBox(width: 8)],
      ),
      drawer: Drawer(child: SafeArea(child: _NavList(selected: _index, closeDrawer: true))),
      body: child,
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.task_alt, color: scheme.onPrimary, size: 20),
        ),
        const SizedBox(width: 10),
        Text('TaskFlow', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 24), child: _Logo()),
            Expanded(child: _NavList(selected: selected)),
            const Divider(height: 1),
            const Padding(padding: EdgeInsets.all(12), child: _UserTile()),
          ],
        ),
      ),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.selected, this.closeDrawer = false});
  final int selected;
  final bool closeDrawer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        if (closeDrawer) const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 20), child: _Logo()),
        for (var i = 0; i < _destinations.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              selected: i == selected,
              selectedTileColor: scheme.primaryContainer,
              selectedColor: scheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: Icon(i == selected ? _destinations[i].selectedIcon : _destinations[i].icon),
              title: Text(_destinations[i].label, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                if (closeDrawer) Navigator.of(context).pop();
                context.go(_destinations[i].path);
              },
            ),
          ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    return Row(
      children: [
        UserAvatar(user: user, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('@${user.username}',
                  overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Log out',
          icon: const Icon(Icons.logout),
          onPressed: () => confirmLogout(context),
        ),
      ],
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (v) => v == 'profile' ? context.go('/profile') : confirmLogout(context),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'))),
        PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Log out'))),
      ],
      child: UserAvatar(user: user, radius: 16),
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final ok = await confirmDialog(context, title: 'Log out?', message: 'You will need to sign in again.', action: 'Log out');
  if (ok && context.mounted) await context.read<AuthProvider>().logout();
}
