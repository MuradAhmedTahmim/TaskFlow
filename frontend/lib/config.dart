/// App-wide configuration.
///
/// Override the API URL at build/run time:
///   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static const String appName = 'TaskFlow';
  static const int pageSize = 10;
}
