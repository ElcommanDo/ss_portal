/// Servers taken from ALLOWED_HOSTS in ss_portal/config/settings.py.
class ServerOption {
  final String label;
  final String baseUrl;
  const ServerOption(this.label, this.baseUrl);
}

class AppConfig {
  static const String appName = 'Smart System Timesheet';
  static const String apiPrefix = '/api/v1';

  /// Default server. Can be overridden at build time:
  /// flutter build apk --dart-define=SS_BASE_URL=https://example.com
  static const String defaultBaseUrl = String.fromEnvironment(
    'SS_BASE_URL',
    defaultValue: 'https://selfservice.smartsystemme.com',
  );

  static const List<ServerOption> servers = [
    ServerOption('Smart System (selfservice)', 'https://selfservice.smartsystemme.com'),
    ServerOption('PythonAnywhere', 'https://smartsystem.pythonanywhere.com'),
    ServerOption('Server IP (145.241.111.52)', 'http://145.241.111.52'),
  ];

  static const Duration requestTimeout = Duration(seconds: 30);
}
