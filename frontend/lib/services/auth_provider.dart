import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Holds the logged-in user and exposes login / register / logout.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this.client) {
    client.onSessionExpired = _onExpired;
  }

  final ApiClient client;
  static const _userKey = 'tf_user';

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  bool get isLoggedIn => status == AuthStatus.authenticated;

  Future<void> init() async {
    await client.loadTokens();
    if (!client.hasSession) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_userKey);
    if (cached != null) user = AppUser.fromJson(jsonDecode(cached));
    try {
      user = AppUser.fromJson(await client.get('/auth/me/'));
      await _cacheUser();
      status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      // Offline but with a stored session: keep the cached user.
      status = e.statusCode == 0 && user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      if (status == AuthStatus.unauthenticated) await client.clearTokens();
    }
    notifyListeners();
  }

  Future<void> login(String usernameOrEmail, String password) async {
    final data = await client.post('/auth/login/', {'username': usernameOrEmail, 'password': password}, false);
    await _startSession(data);
  }

  Future<void> register({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String password2,
  }) async {
    final data = await client.post(
      '/auth/register/',
      {'username': username, 'email': email, 'full_name': fullName, 'password': password, 'password2': password2},
      false,
    );
    await _startSession(data);
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    user = AppUser.fromJson(await client.patch('/auth/me/', fields));
    await _cacheUser();
    notifyListeners();
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await client.post('/auth/change-password/', {'old_password': oldPassword, 'new_password': newPassword});
  }

  /// Permanently deletes the signed-in account (the server checks [password]).
  /// Call [endDeletedSession] afterwards to clear the local session.
  Future<void> deleteAccount(String password) => client.delete('/auth/me/', {'password': password});

  Future<void> endDeletedSession() => _clear();

  Future<void> logout() async {
    final refresh = client.refreshToken;
    if (refresh != null) {
      try {
        await client.post('/auth/logout/', {'refresh': refresh});
      } catch (_) {
        // Token may already be invalid; logging out locally is enough.
      }
    }
    await _clear();
  }

  Future<void> _startSession(dynamic data) async {
    await client.saveTokens(data['access'], data['refresh']);
    user = AppUser.fromJson(data['user']);
    await _cacheUser();
    status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> _cacheUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (user != null) await prefs.setString(_userKey, jsonEncode(user!.toJson()));
  }

  Future<void> _clear() async {
    await client.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _onExpired() {
    if (status == AuthStatus.authenticated) _clear();
  }
}
