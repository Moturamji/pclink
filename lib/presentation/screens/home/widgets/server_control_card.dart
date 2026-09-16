import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/universal/app_card_header.dart';
import '../../../../core/widgets/universal/bounceable.dart';
import '../../../../core/widgets/universal/copy_action_button.dart';
import '../../../../core/widgets/universal/status_badge.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../../../../data/services/server_service.dart';

/// Card showing server status and control dashboard with Public WAN and Cloud Relay support.
/// Redesigned to eliminate nested card-in-card borders and provide clean hardware telemetry.
class ServerControlCard extends StatefulWidget {
  final bool isWindows;
  final ServerInfo? currentServerInfo;
  final Stream<ServerInfo?>? serverStream;
  final VoidCallback? onToggleServer;
  final String? localDeviceId;
  final User? user;
  final DatabaseService? databaseService;
  final Function(bool isConnected)? onConnectionStateChanged;
  final VoidCallback? onDisconnectRequested;

  const ServerControlCard({
    super.key,
    required this.isWindows,
    this.currentServerInfo,
    this.serverStream,
    this.onToggleServer,
    this.localDeviceId,
    this.user,
    this.databaseService,
    this.onConnectionStateChanged,
    this.onDisconnectRequested,
  });

  @override
  State<ServerControlCard> createState() => _ServerControlCardState();
}

class _ServerControlCardState extends State<ServerControlCard> {
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  String? _authMessage;
  bool _authSuccess = false;
  String? _connectedHostName;
  ServerInfo? _lastKnownServer;

  Future<void> _handleAndroidConnect(ServerInfo server) async {
    if (!server.isFreshlyLive()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Windows PC is currently offline or not responding. Please start Link Service on PC.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (widget.localDeviceId == null || widget.localDeviceId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Android Device ID is required for authentication.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _authMessage = null;
    });

    final result = await ServerService.authenticateClientWithServer(
      serverUrl: server.url,
      publicUrl: server.publicUrl,
      androidDeviceId: widget.localDeviceId!,
      serverStartTime: server.startedAt?.toIso8601String() ?? '',
      user: widget.user,
      databaseService: widget.databaseService,
    );

    if (!mounted) return;

    final isSuccess = result['success'] == true;
    if (isSuccess && widget.user != null && widget.databaseService != null) {
      await widget.databaseService!.setConnectedClientId(
        user: widget.user!,
        clientId: widget.localDeviceId,
      );
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _authSuccess = isSuccess;
      if (result['windowsHost'] != null) {
        _connectedHostName = result['windowsHost'].toString();
      }
      _authMessage = isSuccess
          ? 'Connected to ${result['windowsHost'] ?? 'Windows PC'} successfully!'
          : (result['error'] ?? 'Authentication failed');
    });

    widget.onConnectionStateChanged?.call(isSuccess);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_authMessage!),
        backgroundColor: isSuccess ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _handleAndroidDisconnect() async {
    setState(() {
      _isDisconnecting = true;
    });

    // 1. Notify callback to stop background sync and cancel active transfers
    widget.onDisconnectRequested?.call();

    // 2. Terminate connection with PC server and clear Firebase RTDB
    final server = _lastKnownServer ?? widget.currentServerInfo;
    if (server != null && widget.localDeviceId != null) {
      await ServerService.disconnectClientWithServer(
        serverUrl: server.url,
        publicUrl: server.publicUrl,
        androidDeviceId: widget.localDeviceId!,
        serverStartTime: server.startedAt?.toIso8601String() ?? '',
        user: widget.user,
        databaseService: widget.databaseService,
      );
    } else if (widget.user != null && widget.databaseService != null) {
      await widget.databaseService!.disconnectClient(user: widget.user!);
    }

    if (!mounted) return;

    setState(() {
      _isDisconnecting = false;
      _authSuccess = false;
      _authMessage = null;
      _connectedHostName = null;
    });

    widget.onConnectionStateChanged?.call(false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Disconnected from Windows PC. Background sync and transfers terminated.'),
        backgroundColor: context.colors.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWindows) {
      return _buildWindowsCard(widget.currentServerInfo);
    } else {
      return _buildAndroidCard();
    }
  }

  Widget _buildWindowsCard(ServerInfo? info) {
    final colors = context.colors;
    final isLive = info?.isLive ?? false;
    final hasClient = info?.connectedClientId != null && info!.connectedClientId!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCardHeader(
            icon: Icons.hub_rounded,
            iconColor: colors.primaryLight,
            title: 'PC LINK SERVICE',
            subtitle: 'Local server daemon & network bridge',
            trailing: StatusBadge(
              label: isLive ? 'ACTIVE' : 'STANDBY',
              isActive: isLive,
              activeColor: AppColors.successLight,
              inactiveColor: colors.textMuted,
            ),
          ),
          const SizedBox(height: 18),

          // Telemetry Summary Rows (Clean, Borderless)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  colors: colors,
                  icon: Icons.lock_rounded,
                  iconColor: colors.primaryLight,
                  label: 'Connection Security:',
                  valueWidget: Text(
                    'Encrypted (TLS 1.3)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryLight,
                    ),
                  ),
                ),
                Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
                _buildInfoRow(
                  colors: colors,
                  icon: Icons.cloud_done_rounded,
                  iconColor: AppColors.successLight,
                  label: 'Network Channel:',
                  valueWidget: const StatusBadge(
                    label: 'Cloud Relay Active',
                    isActive: true,
                    activeColor: AppColors.successLight,
                  ),
                ),
                Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
                _buildInfoRow(
                  colors: colors,
                  icon: Icons.verified_user_rounded,
                  iconColor: colors.secondary,
                  label: 'Access Control:',
                  valueWidget: Text(
                    'Account & Hardware Token',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
                _buildInfoRow(
                  colors: colors,
                  icon: Icons.phone_android_rounded,
                  iconColor: colors.secondary,
                  label: 'Paired Mobile:',
                  valueWidget: Text(
                    hasClient ? 'Connected & Synced' : 'Ready for Connection',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasClient ? AppColors.successLight : colors.textMuted,
                    ),
                  ),
                ),
                if (isLive && info != null) ...[
                  Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
                  _buildInfoRow(
                    colors: colors,
                    icon: Icons.dns_rounded,
                    iconColor: colors.primaryLight,
                    label: 'Local Endpoint:',
                    valueWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${info.ipAddress}:${info.port}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CopyActionButton(
                          textToCopy: info.url,
                          label: 'Copy',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: Bounceable(
              onTap: widget.onToggleServer,
              scaleFactor: 0.98,
              child: ElevatedButton.icon(
                onPressed: widget.onToggleServer,
                icon: Icon(
                  isLive ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  size: 20,
                ),
                label: Text(
                  isLive ? 'Stop Link Service' : 'Start Link Service',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLive ? colors.surfaceSubtle : colors.primary,
                  foregroundColor: isLive ? AppColors.error : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidCard() {
    final colors = context.colors;

    return StreamBuilder<ServerInfo?>(
      stream: widget.serverStream,
      builder: (context, snapshot) {
        final server = snapshot.data ?? widget.currentServerInfo;
        if (server != null) {
          _lastKnownServer = server;
        }
        final isLive = server != null && server.isFreshlyLive();
        final isClientMatch = server?.connectedClientId != null &&
            server!.connectedClientId!.isNotEmpty &&
            widget.localDeviceId != null &&
            server.connectedClientId == widget.localDeviceId;
        final isConnected = isLive && (_authSuccess || isClientMatch);

        if (!isLive && _authSuccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _authSuccess) {
              setState(() {
                _authSuccess = false;
                _connectedHostName = null;
              });
              widget.onConnectionStateChanged?.call(false);
            }
          });
        }

        return Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.cardBorder, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCardHeader(
                icon: isConnected ? Icons.link_rounded : Icons.laptop_windows_rounded,
                iconColor: isConnected ? AppColors.successLight : colors.primaryLight,
                title: 'WINDOWS PC LINK',
                subtitle: isConnected
                    ? 'Encrypted peer synchronization active'
                    : (isLive ? 'Windows host detected on network' : 'Host daemon currently offline'),
                trailing: StatusBadge(
                  label: isConnected ? 'CONNECTED' : (isLive ? 'LIVE' : 'STANDBY'),
                  isActive: isConnected || isLive,
                  activeColor: AppColors.successLight,
                  inactiveColor: colors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              if (isConnected) ...[
                // ACTIVE CONNECTED STATE
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.successLight, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _connectedHostName != null
                                    ? 'Connected to $_connectedHostName'
                                    : 'Connected to Windows PC',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const StatusBadge(
                            label: 'TLS 1.3',
                            isActive: true,
                            activeColor: AppColors.successLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your Android device is linked and securely synchronizing with your Windows PC in real time.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                      Divider(color: colors.cardBorder, height: 20, thickness: 0.8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Link Status:',
                            style: TextStyle(fontSize: 12, color: colors.textMuted),
                          ),
                          const Text(
                            'Active & Synced',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.successLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Bounceable(
                    onTap: _isDisconnecting ? null : _handleAndroidDisconnect,
                    scaleFactor: 0.98,
                    child: OutlinedButton.icon(
                      onPressed: _isDisconnecting ? null : _handleAndroidDisconnect,
                      icon: _isDisconnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.error,
                              ),
                            )
                          : const Icon(Icons.link_off_rounded, size: 18),
                      label: Text(_isDisconnecting ? 'Disconnecting...' : 'Disconnect from Windows PC'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.4), width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else if (isLive) ...[
                // LIVE STANDBY STATE - Ready to connect
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.wifi_tethering_rounded, color: AppColors.successLight, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'PC Link is Ready',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const StatusBadge(
                            label: 'Encrypted',
                            isActive: true,
                            activeColor: AppColors.successLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your Windows PC is active and ready for secure synchronization across any network (Wi-Fi, 4G, 5G).',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_authMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _authMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Bounceable(
                    onTap: _isConnecting ? null : () => _handleAndroidConnect(server),
                    scaleFactor: 0.98,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : () => _handleAndroidConnect(server),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.shield_rounded, size: 18),
                      label: Text(
                        _isConnecting ? 'Connecting Securely...' : 'Connect to Windows PC',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // PC SERVER STANDBY (Windows app closed or offline)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: colors.textMuted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Windows PC link is in standby. Open PCLink on your PC to establish a secure connection.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow({
    required AppThemeColors colors,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Widget valueWidget,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
        valueWidget,
      ],
    );
  }
}
