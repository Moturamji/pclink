import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/device_details.dart';
import '../../../data/models/server_info.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/database_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/services/file_share_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/server_service.dart';
import '../../../data/services/tunnel_service.dart';
import '../../../features/clipboard/services/clipboard_service.dart';
import '../auth/auth_screen.dart';
import 'desktop/desktop_dashboard_view.dart';
import 'mobile/mobile_dashboard_view.dart';

/// Main dashboard orchestrator: renders dedicated, distinct UI experiences
/// for Desktop (Windows / wide screens) and Mobile (Android / touch screens).
class HomeScreen extends StatefulWidget {
  final DeviceService? deviceService;
  final AuthService? authService;
  final DatabaseService? databaseService;
  final ServerService? serverService;
  final ClipboardService? clipboardService;

  const HomeScreen({
    super.key,
    this.deviceService,
    this.authService,
    this.databaseService,
    this.serverService,
    this.clipboardService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeviceService _deviceService;
  late final AuthService _authService;
  late final DatabaseService _databaseService;
  late final ServerService _serverService;
  late final ClipboardService _clipboardService;
  late final FileShareService _fileShareService;
  late final TunnelService _tunnelService;

  late Future<DeviceDetails> _deviceDetailsFuture;
  DeviceDetails? _cachedDeviceDetails;
  ServerInfo? _currentServerInfo;
  StreamSubscription<dynamic>? _serverSub;
  StreamSubscription<Map<String, dynamic>?>? _cloudHandshakeSub;
  StreamSubscription<Map<String, dynamic>?>? _notificationSub;
  Timer? _tunnelWatcherTimer;
  StreamSubscription<String?>? _tunnelUrlSub;
  Timer? _serverHeartbeatTimer;
  Timer? _deviceHeartbeatTimer;
  AppLifecycleListener? _lifecycleListener;
  bool _isRefreshing = false;
  bool _wasServerLive = false;
  String? _lastAlertedNotificationId;

  @override
  void initState() {
    super.initState();
    _deviceService = widget.deviceService ?? DeviceService();
    _authService = widget.authService ?? AuthService();
    _databaseService = widget.databaseService ?? DatabaseService();
    _serverService = widget.serverService ?? ServerService();
    _clipboardService = widget.clipboardService ?? ClipboardService();
    _fileShareService = FileShareService();
    _tunnelService = TunnelService();

    final user = _authService.currentUser;

    // Listen for application exit / quit lifecycle events to gracefully mark offline
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        debugPrint('HomeScreen: Application exit requested');
        await _cleanupAndMarkOffline();
        return AppExitResponse.exit;
      },
      onDetach: () {
        debugPrint('HomeScreen: Application detached');
        _cleanupAndMarkOffline();
      },
    );

    // Initialize FCM push notification service on Android
    NotificationService.initialize(
      user: user,
      databaseService: _databaseService,
    );

    if (!kIsWeb && Platform.isWindows) {
      _currentServerInfo = _serverService.currentServerInfo;
      _serverSub = _serverService.serverStateStream.listen((info) {
        if (mounted) {
          setState(() {
            _currentServerInfo = info;
          });
        }
      });

      if (user != null) {
        _cloudHandshakeSub = _databaseService
            .listenCloudHandshakeRequests(user)
            .listen((request) async {
          if (request != null) {
            await _serverService.handleCloudHandshakeRequest(
              request,
              user: user,
              databaseService: _databaseService,
            );
            await _databaseService.updateServerInfo(
              user: user,
              serverInfo: _serverService.currentServerInfo,
            );
          }
        });
      }
    } else if (user != null) {
      // Android: Listen for Windows server host info & trigger professional alert
      _serverSub = _databaseService.watchUserServer(user).listen((info) {
        if (mounted) {
          final isLiveNow = info != null && info.isLive;
          final becameLive = isLiveNow && !_wasServerLive;

          setState(() {
            _currentServerInfo = info;
            _wasServerLive = isLiveNow;
          });

          if (!isLiveNow) {
            _stopAndroidServices();
            NotificationService.cancelServerLiveNotification();
          } else {
            if (becameLive) {
              NotificationService.showServerLiveNotification(
                hostName: 'Windows PC',
                ipAddress: info.url,
                publicUrl: info.publicUrl,
              );
            }

            if (!_clipboardService.isListening && _cachedDeviceDetails != null) {
              _startAndroidServices(_cachedDeviceDetails!);
            } else if (_clipboardService.isListening) {
              _clipboardService.onServerInfoPublished();
            }
          }
        }
      });

      // Android: Also listen for real-time notification events queued by Windows
      _notificationSub = _databaseService.watchLatestNotification(user).listen((notif) {
        if (!mounted || notif == null) return;
        final notifId = notif['id']?.toString();
        final type = notif['type']?.toString();
        if (notifId != null && notifId != _lastAlertedNotificationId) {
          _lastAlertedNotificationId = notifId;
          if (type == 'server_live') {
            final hostName = notif['hostName']?.toString() ?? 'Windows PC';
            final ipAddress = notif['ipAddress']?.toString();
            final publicUrl = notif['publicUrl']?.toString();
            NotificationService.showServerLiveNotification(
              hostName: hostName,
              ipAddress: ipAddress,
              publicUrl: publicUrl,
            );
          }
        }
      });
    }

    _loadDeviceDetails();
  }

  void _startAndroidServices(DeviceDetails details) {
    if (kIsWeb || Platform.isWindows) return;
    _cachedDeviceDetails = details;
    if (_clipboardService.isListening) {
      _clipboardService.onServerInfoPublished();
      return;
    }
    _clipboardService.startListening(
      deviceName: details.deviceName,
      isWindows: false,
      deviceId: details.deviceId,
      getTargetServerUrls: () {
        final info = _currentServerInfo;
        if (info == null) return <String>[];
        return <String>[
          if (info.publicUrl != null && info.publicUrl!.isNotEmpty)
            info.publicUrl!,
          if (info.url.isNotEmpty) info.url,
        ];
      },
      getServerStartTime: () {
        final info = _currentServerInfo;
        return info?.startedAt?.toIso8601String();
      },
      onConnectionLost: () {
        debugPrint('HomeScreen: Connection lost detected by ClipboardService');
        _stopAndroidServices();
      },
    );
  }

  void _stopAndroidServices() {
    if (kIsWeb || Platform.isWindows) return;
    _fileShareService.cancelActiveTransfers();
    _clipboardService.stopListening();
  }

  Future<void> _cleanupAndMarkOffline() async {
    _serverHeartbeatTimer?.cancel();
    _serverHeartbeatTimer = null;
    _deviceHeartbeatTimer?.cancel();
    _deviceHeartbeatTimer = null;

    final user = _authService.currentUser;
    if (user == null) return;

    final isWindows = !kIsWeb && Platform.isWindows;
    final platformKey = isWindows ? 'windows' : 'android';

    final futures = <Future<void>>[
      _databaseService.setDeviceOffline(user: user, platformKey: platformKey),
    ];

    if (isWindows && _serverService.isRunning) {
      futures.add(_databaseService.setServerOffline(user: user));
      futures.add(_serverService.stopServer());
    }

    try {
      await Future.wait(futures).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _startDeviceHeartbeat(User user, String platformKey) {
    _deviceHeartbeatTimer?.cancel();
    _deviceHeartbeatTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _databaseService.updateDeviceHeartbeat(user: user, platformKey: platformKey);
    });
  }

  void _startServerHeartbeat(User user) {
    _serverHeartbeatTimer?.cancel();
    _serverHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_serverService.isRunning) {
        _databaseService.updateServerHeartbeat(user: user);
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _serverHeartbeatTimer?.cancel();
    _deviceHeartbeatTimer?.cancel();
    _serverSub?.cancel();
    _cloudHandshakeSub?.cancel();
    _notificationSub?.cancel();
    _tunnelWatcherTimer?.cancel();
    _tunnelUrlSub?.cancel();
    _tunnelService.dispose();
    _clipboardService.dispose();
    _fileShareService.dispose();
    _cleanupAndMarkOffline();
    if (!kIsWeb && Platform.isWindows) {
      _serverService.dispose();
    }
    super.dispose();
  }

  void _loadDeviceDetails() {
    setState(() {
      _deviceDetailsFuture = _deviceService.getDeviceDetails().then((details) {
        _syncWithCloudAndStartServer(details);
        return details;
      });
    });
  }

  Future<void> _syncWithCloudAndStartServer(DeviceDetails details) async {
    final user = _authService.currentUser;
    if (user != null) {
      try {
        await _databaseService.syncUserAndDevice(
          user: user,
          details: details,
        );

        _startDeviceHeartbeat(user, details.isWindows ? 'windows' : 'android');

        // Windows only: Automatically launch lightweight local server and announce to RTDB
        if (!kIsWeb && details.isWindows) {
          _serverService.setAuthorizedAndroidDeviceId(
            await _databaseService.getAndroidDeviceId(user: user),
          );
          final tunnelUrl = await _deviceService.getTunnelUrl();
          final serverInfo = await _serverService.startServer(
            hostIp: details.primaryIp,
            publicIp: details.publicIp,
            publicUrlOverride: tunnelUrl,
          );
          if (serverInfo != null) {
            await _databaseService.updateServerInfo(
              user: user,
              serverInfo: serverInfo,
            );
            _startServerHeartbeat(user);
            _startTunnelWatcher(user);
            _startAutomatedTunnel(user);
            await _databaseService.queueServerLiveNotification(
              user: user,
              pcHostName: details.deviceName,
              ipAddress: serverInfo.url,
              publicUrl: serverInfo.publicUrl,
            );
          }

          // Windows: Start direct server-routed clipboard handler
          _clipboardService.startListening(
            deviceName: details.deviceName,
            isWindows: true,
            serverService: _serverService,
            deviceId: details.deviceId,
          );
        }

        // Configure the file-sharing client
        _fileShareService.configure(
          getTargetServerUrls: () {
            final info = _currentServerInfo;
            if (info == null) return <String>[];
            return <String>[
              if (info.publicUrl != null && info.publicUrl!.isNotEmpty)
                info.publicUrl!,
              if (info.url.isNotEmpty) info.url,
            ];
          },
          getServerStartTime: () {
            final info = _currentServerInfo;
            return info?.startedAt?.toIso8601String();
          },
          deviceId: details.deviceId,
          deviceName: details.deviceName,
        );

        if (!kIsWeb && !details.isWindows) {
          NotificationService.initialize(
            user: user,
            databaseService: _databaseService,
          );
          if (_currentServerInfo?.isLive ?? false) {
            _startAndroidServices(details);
          }
        }
      } catch (_) {
        // Handled silently for offline scenarios
      }
    }
  }

  Future<void> _toggleServer(DeviceDetails details) async {
    final user = _authService.currentUser;
    if (_serverService.isRunning) {
      _serverHeartbeatTimer?.cancel();
      _serverHeartbeatTimer = null;
      _tunnelWatcherTimer?.cancel();
      _tunnelWatcherTimer = null;
      _tunnelUrlSub?.cancel();
      _tunnelUrlSub = null;
      await _tunnelService.stop();
      await _serverService.stopServer();
      if (user != null) {
        await _databaseService.setServerOffline(user: user);
      }
    } else {
      final tunnelUrl = await _deviceService.getTunnelUrl();
      final serverInfo = await _serverService.startServer(
        hostIp: details.primaryIp,
        publicIp: details.publicIp,
        publicUrlOverride: tunnelUrl,
      );
      if (user != null && serverInfo != null) {
        await _databaseService.updateServerInfo(
          user: user,
          serverInfo: serverInfo,
        );
        _startServerHeartbeat(user);
        _startTunnelWatcher(user);
        _startAutomatedTunnel(user);
        await _databaseService.queueServerLiveNotification(
          user: user,
          pcHostName: details.deviceName,
          ipAddress: serverInfo.url,
          publicUrl: serverInfo.publicUrl,
        );
      }
    }
  }

  void _startAutomatedTunnel(User user) {
    if (kIsWeb || !Platform.isWindows) return;

    _tunnelUrlSub?.cancel();
    _tunnelUrlSub = _tunnelService.urlStream.listen((url) {
      if (!mounted) return;
      if (url == null || url.isEmpty) return;
      _serverService.updatePublicUrl(url);
      _databaseService.updateServerInfo(
        user: user,
        serverInfo: _serverService.currentServerInfo,
      );
      debugPrint('HomeScreen: Published automated tunnel URL: $url');
    });

    _tunnelService.start();
  }

  void _startTunnelWatcher(User user) {
    _tunnelWatcherTimer?.cancel();
    _tunnelWatcherTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        final autoUrl = _tunnelService.currentUrl;
        final url = (autoUrl != null && autoUrl.isNotEmpty)
            ? autoUrl
            : await _deviceService.getTunnelUrl();
        final current = _serverService.currentServerInfo.publicUrl;
        if (url != null && url.isNotEmpty && url != current) {
          _serverService.updatePublicUrl(url);
          await _databaseService.updateServerInfo(
            user: user,
            serverInfo: _serverService.currentServerInfo,
          );
          debugPrint('HomeScreen: Published updated tunnel URL: $url');
        }
      },
    );
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    _loadDeviceDetails();
    await _deviceDetailsFuture;
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _confirmSignOut() {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AppStrings.signOut,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out of PCLink?',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppStrings.cancel,
              style: TextStyle(
                  color: colors.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 2,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _cleanupAndMarkOffline();
              _tunnelWatcherTimer?.cancel();
              _tunnelWatcherTimer = null;
              _tunnelUrlSub?.cancel();
              _tunnelUrlSub = null;
              await _tunnelService.stop();
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text(AppStrings.signOut),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return FutureBuilder<DeviceDetails>(
      future: _deviceDetailsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    AppStrings.detectingDetails,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load details:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final details = snapshot.data!;
        final isDesktop = (!kIsWeb && Platform.isWindows) ||
            MediaQuery.sizeOf(context).width >= 900;

        if (isDesktop) {
          return DesktopDashboardView(
            details: details,
            user: user,
            currentServerInfo:
                _currentServerInfo ?? _serverService.currentServerInfo,
            databaseService: _databaseService,
            serverService: _serverService,
            clipboardService: _clipboardService,
            fileShareService: _fileShareService,
            isRefreshing: _isRefreshing,
            onRefresh: _refresh,
            onSignOut: _confirmSignOut,
            onToggleServer: () => _toggleServer(details),
            onConnectionStateChanged: (isConnected) {
              if (!details.isWindows) {
                if (isConnected) {
                  _startAndroidServices(details);
                } else {
                  _stopAndroidServices();
                }
              }
            },
            onDisconnectRequested: () {
              if (!details.isWindows) {
                _stopAndroidServices();
              }
            },
          );
        }

        return MobileDashboardView(
          details: details,
          user: user,
          currentServerInfo:
              _currentServerInfo ?? _serverService.currentServerInfo,
          databaseService: _databaseService,
          serverService: _serverService,
          clipboardService: _clipboardService,
          fileShareService: _fileShareService,
          isRefreshing: _isRefreshing,
          onRefresh: _refresh,
          onSignOut: _confirmSignOut,
          onToggleServer: () => _toggleServer(details),
          onConnectionStateChanged: (isConnected) {
            if (!details.isWindows) {
              if (isConnected) {
                _startAndroidServices(details);
              } else {
                _stopAndroidServices();
              }
            }
          },
          onDisconnectRequested: () {
            if (!details.isWindows) {
              _stopAndroidServices();
            }
          },
        );
      },
    );
  }
}
