import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'auth_provider.dart';

/// Keeps the unread notification count fresh while the user is signed in,
/// so the navigation badge can show it.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter(this.api, this.auth) {
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final TaskFlowApi api;
  final AuthProvider auth;
  static const pollInterval = Duration(seconds: 30);

  int unread = 0;
  Timer? _timer;

  void _onAuthChanged() {
    _timer?.cancel();
    if (auth.isLoggedIn) {
      refresh();
      _timer = Timer.periodic(pollInterval, (_) => refresh());
    } else if (unread != 0) {
      unread = 0;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!auth.isLoggedIn) return;
    try {
      final count = await api.unreadNotificationCount();
      if (count != unread) {
        unread = count;
        notifyListeners();
      }
    } catch (_) {
      // Offline or session ended: keep the last known count.
    }
  }

  /// Local update after the user reads notifications, without waiting for a poll.
  void setUnread(int count) {
    if (count == unread) return;
    unread = count < 0 ? 0 : count;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
