import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/clipboard_helper.dart';
import '../../../data/models/device_details.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/database_service.dart';
import '../../../data/services/device_service.dart';
import '../auth/auth_screen.dart';
import 'widgets/interfaces_card.dart';
import 'widgets/linked_devices_card.dart';
import 'widgets/metric_card.dart';
import 'widgets/platform_header.dart';
import 'widgets/specs_card.dart';
import 'widgets/user_session_card.dart';

/// Main dashboard displaying device identity, active network interfaces, and system parameters.
class HomeScreen extends StatefulWidget {
  final DeviceService? deviceService;
  final AuthService? authService;
  final DatabaseService? databaseService;

  const HomeScreen({
    super.key,
    this.deviceService,
    this.authService,
    this.databaseService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeviceService _deviceService;
  late final AuthService _authService;
  late final DatabaseService _databaseService;

  late Future<DeviceDetails> _deviceDetailsFuture;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _deviceService = widget.deviceService ?? DeviceService();
    _authService = widget.authService ?? AuthService();
    _databaseService = widget.databaseService ?? DatabaseService();
    _loadDeviceDetails();
  }

  void _loadDeviceDetails() {
    setState(() {
      _deviceDetailsFuture = _deviceService.getDeviceDetails().then((details) {
        _syncWithCloud(details);
        return details;
      });
    });
  }

  Future<void> _syncWithCloud(DeviceDetails details) async {
    final user = _authService.currentUser;
    if (user != null) {
      try {
        await _databaseService.syncUserAndDevice(
          user: user,
          details: details,
        );
      } catch (_) {
        // Handled silently for offline scenarios
      }
    }
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.error),
            SizedBox(width: 8),
            Text(
              AppStrings.signOut,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out of PCLink?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
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

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: AppColors.primaryLight),
            SizedBox(width: 10),
            Text(
              AppStrings.appName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh details',
            onPressed: _isRefreshing ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.error),
            tooltip: AppStrings.signOut,
            onPressed: _confirmSignOut,
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
                  horizontal: 20.0, vertical: 24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (user?.email != null)
                        UserSessionCard(email: user!.email!),
                      const SizedBox(height: 16),

                      PlatformHeader(details: details),
                      const SizedBox(height: 20),

                      // Realtime Database Cloud-Linked Devices
                      if (user != null) ...[
                        LinkedDevicesCard(
                          devicesStream:
                              _databaseService.watchUserDevices(user),
                        ),
                        const SizedBox(height: 20),
                      ],

                      MetricCard(
                        title: AppStrings.deviceIdTitle,
                        value: details.deviceId,
                        icon: Icons.fingerprint,
                        accentColor: AppColors.primaryLight,
                        badgeText: details.isWindows
                            ? 'Machine GUID'
                            : 'Android Hardware ID',
                        onCopy: () => ClipboardHelper.copy(
                            context, details.deviceId, 'Device ID'),
                      ),
                      const SizedBox(height: 16),

                      MetricCard(
                        title: AppStrings.primaryIpTitle,
                        value: details.primaryIp,
                        icon: Icons.wifi,
                        accentColor: AppColors.secondary,
                        badgeText:
                            details.isConnected ? 'Connected' : 'Offline',
                        badgeColor: details.isConnected
                            ? AppColors.success
                            : AppColors.error,
                        onCopy: () => ClipboardHelper.copy(
                            context, details.primaryIp, 'IP Address'),
                      ),
                      const SizedBox(height: 20),

                      if (details.interfaces.isNotEmpty)
                        InterfacesCard(interfaces: details.interfaces),
                      const SizedBox(height: 20),

                      SpecsCard(details: details),
                      const SizedBox(height: 24),
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
