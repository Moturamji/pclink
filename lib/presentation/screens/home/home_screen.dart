import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/universal/app_logo.dart';
import '../../../core/widgets/universal/bounceable.dart';
import '../../../core/widgets/universal/theme_toggle_button.dart';
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
import '../../../features/clipboard/widgets/clipboard_sync_card.dart';
import '../../../features/file_share/widgets/file_share_card.dart';
import '../auth/auth_screen.dart';
import 'widgets/linked_devices_card.dart';
import 'widgets/platform_header.dart';
import 'widgets/security_status_card.dart';
import 'widgets/server_control_card.dart';
import 'widgets/specs_card.dart';
import 'widgets/user_session_card.dart';

/// Main dashboard displaying device identity, active network interfaces, local server, and system parameters.
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
          } else if (_clipboardService.isListening) {
            // Probe immediately only when the PC address/session actually
            // changed; otherwise throttled polling continues.
            _clipboardService.onServerInfoPublished();
          }
        }
      });
    }

    _loadDeviceDetails();
  }

  void _startAndroidServices(DeviceDetails details) {
    if (kIsWeb || Platform.isWindows) return;
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
          // Bind the authorized phone from the DB (device ID) instead of
          // accepting "first caller wins".
          _serverService.setAuthorizedAndroidDeviceId(
            await _databaseService.getAndroidDeviceId(user: user),
          );
          // Prefer a public tunnel URL (ngrok/cloudflared) so the phone can
          // reach the PC even on mobile data / CGNAT networks without ports.
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

        // Configure the file-sharing client with the adaptive server
        // discovery + session password.
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

  /// Fully-automated public tunnel (cloudflared quick tunnel). No user setup:
  /// the app downloads the client on first run, starts it, and publishes the
  /// resulting public HTTPS URL to Firebase so the phone can reach the PC from
  /// any network. Server keeps running on WAN/LAN meanwhile; when the tunnel
  /// URL is ready it quietly upgrades the published address.
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

    // Fire-and-forget so server startup is never blocked by the tunnel setup.
    _tunnelService.start();
  }

  /// Periodically re-checks the tunnel URL and re-publishes to Firebase if it
  /// changed (ngrok/cloudflared rotate addresses). Cheap local HTTP call, so a
  /// 15s timer is safe.
  void _startTunnelWatcher(User user) {
    _tunnelWatcherTimer?.cancel();
    _tunnelWatcherTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        // Prefer the live automated-tunnel URL so a stale override file or
        // dead ngrok entry can never clobber the working public address.
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
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppStrings.cancel,
              style: TextStyle(color: colors.textMuted, fontWeight: FontWeight.w600),
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
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(
              size: 34,
              borderRadius: 10,
              showGlow: true,
              isAnimated: false,
            ),
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  colors.textPrimary,
                  colors.primaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                AppStrings.appName,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  fontSize: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          const ThemeToggleButton(),
          const SizedBox(width: 4),
          Bounceable(
            onTap: _isRefreshing ? null : _refresh,
            child: IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh details',
              onPressed: null, // handled by Bounceable
            ),
          ),
          Bounceable(
            onTap: _confirmSignOut,
            child: const IconButton(
              icon: Icon(Icons.logout_rounded, color: AppColors.error),
              tooltip: AppStrings.signOut,
              onPressed: null, // handled by Bounceable
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<DeviceDetails>(
        future: _deviceDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
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
            );
          }

          if (snapshot.hasError) {
            return Center(
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
            );
          }

          final details = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16.0, vertical: 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (user?.email != null)
                        UserSessionCard(email: user!.email!),
                      const SizedBox(height: 14),

                      PlatformHeader(details: details),
                      const SizedBox(height: 14),

                      // Local/Public Windows Server or Android Server Listener Card
                      ServerControlCard(
                        isWindows: details.isWindows,
                        currentServerInfo: _currentServerInfo ??
                            _serverService.currentServerInfo,
                        serverStream: user != null
                            ? _databaseService.watchUserServer(user)
                            : null,
                        onToggleServer: () => _toggleServer(details),
                        localDeviceId: details.deviceId,
                        user: user,
                        databaseService: _databaseService,
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
                      ),
                      const SizedBox(height: 14),

                      // Real-Time Cross-Platform Clipboard Sync
                      if (user != null) ...[
                        ClipboardSyncCard(
                          isWindows: details.isWindows,
                          user: user,
                          databaseService: _databaseService,
                          clipboardService: _clipboardService,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Direct File Sharing Through the Temporary Server
                      if (user != null) ...[
                        FileShareCard(
                          isWindows: details.isWindows,
                          serverService:
                              details.isWindows ? _serverService : null,
                          fileShareService:
                              details.isWindows ? null : _fileShareService,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Realtime Database Cloud-Linked Devices
                      if (user != null) ...[
                        LinkedDevicesCard(
                          devicesStream:
                              _databaseService.watchUserDevices(user),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Security, Encryption, and Data Privacy Health Card
                      SecurityStatusCard(
                        isConnected: details.isConnected,
                        isWindows: details.isWindows,
                      ),
                      const SizedBox(height: 14),

                      SpecsCard(details: details),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


