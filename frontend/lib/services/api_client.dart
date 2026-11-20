import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Error returned by the API. [fieldErrors] holds per-field validation
/// messages from Django REST Framework.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, String> fieldErrors;

  ApiException(this.statusCode, this.message, [this.fieldErrors = const {}]);

  @override
  String toString() => message;
}

/// Thin HTTP client that adds the JWT header and refreshes the access token
/// transparently when it expires.
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _accessKey = 'tf_access';
  static const _refreshKey = 'tf_refresh';

  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be refreshed (forces logout).
  void Function()? onSessionExpired;

  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _access = prefs.getString(_accessKey);
    _refresh = prefs.getString(_refreshKey);
  }

  Future<void> saveTokens(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body, bool auth = true]) => _send('POST', path, body: body, auth: auth);
  Future<dynamic> patch(String path, Object? body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? query, Object? body, bool auth = true, bool retried = false}) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth && _access != null) request.headers['Authorization'] = 'Bearer $_access';

    http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request)).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond.');
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server. Is the backend running at ${AppConfig.apiBaseUrl}?');
    }

    if (response.statusCode == 401 && auth && !retried && _refresh != null) {
      if (await _refreshAccess()) {
        return _send(method, path, query: query, body: body, auth: auth, retried: true);
      }
      await clearTokens();
      onSessionExpired?.call();
      throw ApiException(401, 'Your session has expired. Please log in again.');
    }

    final text = utf8.decode(response.bodyBytes);
    final data = text.isEmpty ? null : _tryDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw _toException(response.statusCode, data);
  }

  Future<bool> _refreshAccess() {
    return _refreshing ??= () async {
      try {
        final res = await _http.post(
          _uri('/auth/refresh/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': _refresh}),
        );
        if (res.statusCode != 200) return false;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await saveTokens(data['access'], data['refresh'] ?? _refresh!);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  static dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  static ApiException _toException(int status, dynamic data) {
    final fields = <String, String>{};
    String? message;
    if (data is Map) {
      data.forEach((key, value) {
        final msg = value is List ? value.join(' ') : value.toString();
        if (key == 'detail' || key == 'non_field_errors') {
          message = msg;
        } else {
          fields[key.toString()] = msg;
        }
      });
    }
    message ??= fields.isNotEmpty
        ? fields.values.first
        : switch (status) {
            403 => 'You do not have permission to do that.',
            404 => 'Not found.',
            >= 500 => 'Server error. Please try again later.',
            _ => 'Request failed ($status).',
          };
    return ApiException(status, message!, fields);
  }
}
