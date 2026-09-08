import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/database_service.dart';
import '../../../../data/services/server_service.dart';

/// Card showing server status and control dashboard with Public WAN and Cloud Relay support.
class ServerControlCard extends StatefulWidget {
  final bool isWindows;
  final ServerInfo? currentServerInfo;
  final Stream<ServerInfo?>? serverStream;
  final VoidCallback? onToggleServer;
  final String? localDeviceId;
  final User? user;
  final DatabaseService? databaseService;

  const ServerControlCard({
    super.key,
    required this.isWindows,
    this.currentServerInfo,
    this.serverStream,
    this.onToggleServer,
    this.localDeviceId,
    this.user,
    this.databaseService,
  });

  @override
  State<ServerControlCard> createState() => _ServerControlCardState();
}

class _ServerControlCardState extends State<ServerControlCard> {
  bool _isConnecting = false;
  String? _authMessage;
  bool _authSuccess = false;

  Future<void> _handleAndroidConnect(ServerInfo server) async {
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
      user: widget.user,
      databaseService: widget.databaseService,
    );

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _authSuccess = result['success'] == true;
      _authMessage = (result['success'] == true)
          ? 'Connected to ${result['windowsHost'] ?? 'PC'} (${result['connectionMode'] ?? 'Public Network'}) successfully!'
          : (result['error'] ?? 'Authentication failed');
    });


    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_authMessage!),
        backgroundColor: _authSuccess ? AppColors.success : AppColors.error,
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
    final isLive = info?.isLive ?? false;
    final serverUrl = info?.url ?? 'http://127.0.0.1:8088';
    final publicIp = info?.publicIp;
    final publicUrl = info?.publicUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.dns_rounded,
                        size: 18,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'PC SERVER (PUBLIC & LOCAL)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isLive ? AppColors.success : AppColors.textMuted)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isLive ? AppColors.success : AppColors.textMuted)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLive ? AppColors.successLight : AppColors.textMuted,
                          boxShadow: isLive
                              ? [
                                  BoxShadow(
                                    color: AppColors.successLight.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLive ? 'LIVE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isLive ? AppColors.successLight : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'LAN: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          serverUrl,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Copy Local URL',
                        onPressed: () => ClipboardHelper.copy(
                          context,
                          serverUrl,
                          'Local Server URL',
                        ),
                      ),
                    ],
                  ),
                  if (publicIp != null) ...[
                    const Divider(color: AppColors.cardBorder, height: 20),
                    Row(
                      children: [
                        const Text(
                          'Public WAN: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            publicUrl ?? publicIp,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Copy Public URL',
                          onPressed: () => ClipboardHelper.copy(
                            context,
                            publicUrl ?? publicIp,
                            'Public WAN URL',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(color: AppColors.cardBorder, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.public, size: 14, color: AppColors.successLight),
                          SizedBox(width: 7),
                          Text(
                            'Public Network Mode:',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'Global Cloud Relay Active',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.cardBorder, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.secondary),
                          SizedBox(width: 7),
                          Text(
                            'Auth Key (Password):',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      Text(
                        'Android Device ID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  if (info?.connectedClientId != null &&
                      info!.connectedClientId!.isNotEmpty) ...[
                    const Divider(color: AppColors.cardBorder, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.phone_android_rounded, size: 14, color: AppColors.successLight),
                            SizedBox(width: 7),
                            Text(
                              'Connected Client:',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Text(
                            info.connectedClientId!,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w600,
                              color: AppColors.successLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onToggleServer,
                    icon: Icon(
                      isLive ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                      size: 20,
                    ),
                    label: Text(isLive ? 'Stop Server' : 'Start Server'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLive ? AppColors.surface : AppColors.primary,
                      foregroundColor: isLive ? AppColors.error : AppColors.background,
                      side: isLive
                          ? BorderSide(color: AppColors.error.withValues(alpha: 0.4))
                          : null,
                      elevation: isLive ? 0 : 3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidCard() {
    return StreamBuilder<ServerInfo?>(
      stream: widget.serverStream,
      builder: (context, snapshot) {
        final server = snapshot.data;
        final isLive = server != null && server.isLive;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.laptop_windows_rounded,
                            size: 18,
                            color: AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'WINDOWS PC SERVER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isLive ? AppColors.success : AppColors.textMuted)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (isLive ? AppColors.success : AppColors.textMuted)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isLive ? AppColors.successLight : AppColors.textMuted,
                              boxShadow: isLive
                                  ? [
                                      BoxShadow(
                                        color: AppColors.successLight.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isLive ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isLive ? AppColors.successLight : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (isLive) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withValues(alpha: 0.15),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: AppColors.successLight, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'PC Server is Live!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.secondary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.public, size: 11, color: AppColors.secondary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Anywhere / 4G / Wi-Fi',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              'Server: ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                server.publicUrl ?? server.url,
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textMuted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Copy URL',
                              onPressed: () => ClipboardHelper.copy(
                                context,
                                server.publicUrl ?? server.url,
                                'PC Server URL',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_authMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: (_authSuccess ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (_authSuccess ? AppColors.success : AppColors.error)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _authSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                            size: 18,
                            color: _authSuccess ? AppColors.successLight : AppColors.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _authMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _authSuccess ? AppColors.successLight : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isConnecting ? null : () => _handleAndroidConnect(server),
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.background,
                                  ),
                                )
                              : const Icon(Icons.vpn_key_rounded, size: 18),
                          label: Text(_isConnecting
                              ? 'Authenticating...'
                              : 'Authenticate & Connect (Public WAN)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.background,
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Windows PC server is offline. Launch PCLink on your PC to connect over public or local network.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

