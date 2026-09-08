import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../data/models/server_info.dart';
import '../../../../data/services/server_service.dart';

/// Card showing server status and control dashboard.
/// On Windows: Displays local HTTP server state, URL, connected client, and toggle controls.
/// On Android: Displays real-time notification of Windows server status with 1-click authentication.
class ServerControlCard extends StatefulWidget {
  final bool isWindows;
  final ServerInfo? currentServerInfo;
  final Stream<ServerInfo?>? serverStream;
  final VoidCallback? onToggleServer;
  final String? localDeviceId;

  const ServerControlCard({
    super.key,
    required this.isWindows,
    this.currentServerInfo,
    this.serverStream,
    this.onToggleServer,
    this.localDeviceId,
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
      androidDeviceId: widget.localDeviceId!,
    );

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _authSuccess = result['success'] == true;
      _authMessage = (result['success'] == true)
          ? 'Connected to ${result['windowsHost'] ?? 'PC'} successfully!'
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, size: 18, color: AppColors.primaryLight),
                    SizedBox(width: 8),
                    Text(
                      'LOCAL PC SERVER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isLive ? AppColors.success : AppColors.textMuted)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (isLive ? AppColors.success : AppColors.textMuted)
                          .withValues(alpha: 0.3),
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
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isLive ? 'LIVE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isLive ? AppColors.successLight : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'URL: ',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      Expanded(
                        child: SelectableText(
                          serverUrl,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14, color: AppColors.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Copy Server URL',
                        onPressed: () => ClipboardHelper.copy(
                          context,
                          serverUrl,
                          'Server URL',
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.cardBorder, height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: AppColors.secondary),
                          SizedBox(width: 6),
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
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  if (info?.connectedClientId != null &&
                      info!.connectedClientId!.isNotEmpty) ...[
                    const Divider(color: AppColors.cardBorder, height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.phone_android, size: 14, color: AppColors.successLight),
                            SizedBox(width: 6),
                            Text(
                              'Authenticated Client:',
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onToggleServer,
                    icon: Icon(
                      isLive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                      size: 18,
                    ),
                    label: Text(isLive ? 'Stop Server' : 'Start Server'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLive ? AppColors.surface : AppColors.primary,
                      foregroundColor: isLive ? AppColors.error : Colors.white,
                      side: isLive ? const BorderSide(color: AppColors.cardBorder) : null,
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
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.laptop_windows, size: 18, color: AppColors.primaryLight),
                        SizedBox(width: 8),
                        Text(
                          'WINDOWS PC SERVER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isLive ? AppColors.success : AppColors.textMuted)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (isLive ? AppColors.success : AppColors.textMuted)
                              .withValues(alpha: 0.3),
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
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isLive ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isLive ? AppColors.successLight : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (isLive) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withValues(alpha: 0.15),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: AppColors.successLight, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'PC Server is Live & Ready!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'URL: ',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                            Expanded(
                              child: SelectableText(
                                server.url,
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14, color: AppColors.textMuted),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Copy URL',
                              onPressed: () => ClipboardHelper.copy(
                                context,
                                server.url,
                                'PC Server URL',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_authMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: (_authSuccess ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _authSuccess ? Icons.check : Icons.error_outline,
                            size: 16,
                            color: _authSuccess ? AppColors.successLight : AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _authMessage!,
                              style: TextStyle(
                                fontSize: 12,
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
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.vpn_key_rounded, size: 18),
                          label: Text(_isConnecting
                              ? 'Authenticating...'
                              : 'Authenticate & Connect'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Windows PC server is offline. Launch PCLink on your PC to automatically broadcast the local server.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
