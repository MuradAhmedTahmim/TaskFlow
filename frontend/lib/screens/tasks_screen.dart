import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common.dart';
import '../widgets/task_list.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final query = uri.queryParameters;
    return PagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Tasks', subtitle: 'All tasks across your projects'),
          const SizedBox(height: 20),
          Expanded(
            child: TaskListView(
              key: ValueKey(uri.toString()),
              initialAssignee: query['assignee'],
              initialOverdue: query['overdue'] == 'true',
            ),
          ),
        ],
      ),
    );
  }
}
