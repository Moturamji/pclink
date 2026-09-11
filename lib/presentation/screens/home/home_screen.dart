import 'dart:async';
import 'dart:io';
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
  Timer? _tunnelWatcherTimer;
  StreamSubscription<String?>? _tunnelUrlSub;
  bool _isRefreshing = false;

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
      // Android: Listen for Windows server host info
      _serverSub = _databaseService.watchUserServer(user).listen((info) {
        if (mounted) {
          setState(() {
            _currentServerInfo = info;
          });
          if (info == null || !info.isLive) {
            _stopAndroidServices();
          } else {
            if (!_clipboardService.isListening && _cachedDeviceDetails != null) {
              _startAndroidServices(_cachedDeviceDetails!);
            } else if (_clipboardService.isListening) {
              _clipboardService.onServerInfoPublished();
            }
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

  @override
  void dispose() {
    _serverSub?.cancel();
    _cloudHandshakeSub?.cancel();
    _tunnelWatcherTimer?.cancel();
    _tunnelUrlSub?.cancel();
    _tunnelService.dispose();
    _clipboardService.dispose();
    _fileShareService.dispose();
    if (!kIsWeb && Platform.isWindows) {
      final user = _authService.currentUser;
      if (user != null) {
        _databaseService.setServerOffline(user: user);
      }
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
            _startTunnelWatcher(user);
            _startAutomatedTunnel(user);
            await _databaseService.queueServerLiveNotification(
              user: user,
              pcHostName: details.deviceName,
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

        if (!kIsWeb && !details.isWindows && (_currentServerInfo?.isLive ?? false)) {
          _startAndroidServices(details);
        }
      } catch (_) {
        // Handled silently for offline scenarios
      }
    }
  }

  Future<void> _toggleServer(DeviceDetails details) async {
    final user = _authService.currentUser;
    if (_serverService.isRunning) {
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
        _startTunnelWatcher(user);
        _startAutomatedTunnel(user);
        await _databaseService.queueServerLiveNotification(
          user: user,
          pcHostName: details.deviceName,
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
              if (!kIsWeb && Platform.isWindows) {
                final user = _authService.currentUser;
                if (user != null) {
                  await _databaseService.setServerOffline(user: user);
                }
                _tunnelWatcherTimer?.cancel();
                _tunnelWatcherTimer = null;
                _tunnelUrlSub?.cancel();
                _tunnelUrlSub = null;
                await _tunnelService.stop();
                await _serverService.stopServer();
              }
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
