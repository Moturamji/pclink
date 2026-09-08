/// Constants for the local Windows server and client handshake protocol.
abstract final class ServerConstants {
  static const int defaultPort = 8088;
  static const String authHeader = 'X-Device-Id';

  // Endpoints
  static const String healthEndpoint = '/health';
  static const String authEndpoint = '/auth';
  static const String statusEndpoint = '/status';
  static const String pingEndpoint = '/ping';

  // Handshake Messages
  static const String msgServerRunning = 'PCLink Windows Server is live and ready.';
  static const String msgAuthSuccess = 'Authentication successful. Connection established.';
  static const String msgAuthFailed = 'Unauthorized: Invalid Android Device ID.';
}
