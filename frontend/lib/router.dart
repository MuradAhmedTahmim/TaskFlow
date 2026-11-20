import 'package:go_router/go_router.dart';

import 'screens/auth_screens.dart';
import 'screens/dashboard_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/project_detail_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/team_screen.dart';
import 'services/auth_provider.dart';
import 'widgets/app_shell.dart';

const _publicRoutes = {'/login', '/register'};

GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final isPublic = _publicRoutes.contains(state.matchedLocation);
      if (!loggedIn && !isPublic) {
        final from = state.uri.toString();
        return from == '/' ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
      }
      if (loggedIn && isPublic) return state.uri.queryParameters['from'] ?? '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (_, _) => const NoTransitionPage(child: DashboardScreen())),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, _) => const NoTransitionPage(child: ProjectsScreen()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: ProjectDetailScreen(
                    projectId: int.tryParse(state.pathParameters['id']!) ?? 0,
                    openTaskId: int.tryParse(state.uri.queryParameters['task'] ?? ''),
                  ),
                ),
              ),
            ],
          ),
          GoRoute(path: '/tasks', pageBuilder: (_, _) => const NoTransitionPage(child: TasksScreen())),
          GoRoute(path: '/team', pageBuilder: (_, _) => const NoTransitionPage(child: TeamScreen())),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, _) => const NoTransitionPage(child: NotificationsScreen()),
          ),
          GoRoute(path: '/profile', pageBuilder: (_, _) => const NoTransitionPage(child: ProfileScreen())),
        ],
      ),
    ],
  );
}
