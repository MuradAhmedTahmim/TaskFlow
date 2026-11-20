import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'router.dart';
import 'services/api.dart';
import 'services/api_client.dart';
import 'services/auth_provider.dart';
import 'services/notification_center.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient();
  final auth = AuthProvider(client);
  await auth.init();
  final api = TaskFlowApi(client);
  runApp(TaskFlowApp(auth: auth, api: api, notifications: NotificationCenter(api, auth)));
}

class TaskFlowApp extends StatefulWidget {
  const TaskFlowApp({super.key, required this.auth, required this.api, required this.notifications});
  final AuthProvider auth;
  final TaskFlowApi api;
  final NotificationCenter notifications;

  @override
  State<TaskFlowApp> createState() => _TaskFlowAppState();
}

class _TaskFlowAppState extends State<TaskFlowApp> {
  late final router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        Provider.value(value: widget.api),
        ChangeNotifierProvider.value(value: widget.notifications),
      ],
      child: MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: router,
      ),
    );
  }
}
