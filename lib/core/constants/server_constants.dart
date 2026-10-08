/// Constants for the Windows server and client handshake protocol.
abstract final class ServerConstants {
  static const int defaultPort = 8088;
  static const String authHeader = 'X-Device-Id';
  static const String startTimeHeader = 'X-Start-Time';

  // Endpoints
  static const String healthEndpoint = '/health';
  static const String authEndpoint = '/auth';
  static const String disconnectEndpoint = '/disconnect';
  static const String statusEndpoint = '/status';
  static const String pingEndpoint = '/ping';
  static const String clipboardEndpoint = '/api/clipboard';
  static const String clipboardLatestEndpoint = '/api/clipboard/latest';
  static const String filesEndpoint = '/api/files';
  static const String filesUploadEndpoint = '/api/files/upload';
  static const String filesDownloadEndpoint = '/api/files/download';
  static const String transfersEndpoint = '/api/transfers';
  static const String screenShareStartEndpoint = '/api/screen-share/start';
  static const String screenShareStopEndpoint = '/api/screen-share/stop';
  static const String screenShareStatusEndpoint = '/api/screen-share/status';
  static const String screenShareFrameEndpoint = '/api/screen-share/frame';
  static const String screenShareLiveWsEndpoint = '/api/screen-share/live';
  static const String powerEndpoint = '/api/system/power';

  // System Power Actions
  static const String actionSleep = 'sleep';
  static const String actionShutdown = 'shutdown';
  static const String actionRestart = 'restart';
  static const String actionLock = 'lock';
  static const String actionAbort = 'abort';

  // Handshake Messages
  static const String msgServerRunning =
      'DeskPocket Windows Server is live and ready.';
  static const String msgAuthSuccess =
      'Authentication successful. Connection established.';
  static const String msgAuthFailed =
      'Unauthorized: Invalid Android Device ID.';
  static const String msgStartTimeMismatch =
      'Unauthorized: Invalid server start time (password). Restart DeskPocket on the PC and reconnect.';
}
