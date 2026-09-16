import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/app_card_header.dart';
import '../../../core/widgets/universal/bounceable.dart';
import '../../../core/widgets/universal/status_badge.dart';
import '../../../data/services/database_service.dart';
import '../models/clipboard_item.dart';
import '../services/clipboard_service.dart';
import 'clipboard_item_tile.dart';

/// Card managing bidirectional real-time clipboard sync between Windows PC and Android phone.
/// Redesigned with flat surface depth, seamless filter tabs, and responsive empty states.
class ClipboardSyncCard extends StatefulWidget {
  final bool isWindows;
  final User user;
  final DatabaseService databaseService;
  final ClipboardService clipboardService;

  const ClipboardSyncCard({
    super.key,
    required this.isWindows,
    required this.user,
    required this.databaseService,
    required this.clipboardService,
  });

  @override
  State<ClipboardSyncCard> createState() => _ClipboardSyncCardState();
}

class _ClipboardSyncCardState extends State<ClipboardSyncCard> {
  bool _autoSync = true;
  String _filter = 'all'; // 'all', 'peer', 'local'
  StreamSubscription<String?>? _errorSub;
  String? _syncError;
  bool _serverReachable = true;

  @override
  void initState() {
    super.initState();
    _autoSync = widget.clipboardService.isAutoSyncEnabled;
    _serverReachable = widget.clipboardService.isServerReachable;
    _syncError = widget.clipboardService.lastError;
    _errorSub = widget.clipboardService.errorStream.listen((error) {
      if (mounted) {
        setState(() {
          _serverReachable = error == null;
          _syncError = error;
        });
      }
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  void _toggleAutoSync(bool value) {
    setState(() {
      _autoSync = value;
      widget.clipboardService.isAutoSyncEnabled = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Auto-Sync enabled: Copied items transfer automatically to system clipboard.'
              : 'Auto-Sync paused: Tap copy on individual clips to transfer.',
        ),
        backgroundColor: value ? AppColors.success : context.colors.surface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Clipboard History?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'This will clear the synced clipboard history for both devices.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.clipboardService.clearHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard history cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final currentPlatform = widget.isWindows ? 'windows' : 'android';
    final peerPlatformLabel = widget.isWindows ? 'Android Phone' : 'Windows PC';

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
            icon: Icons.content_paste_rounded,
            iconColor: colors.primaryLight,
            title: 'LIVE CLIPBOARD STREAM',
            subtitle: 'Real-time peer clipboard synchronization',
            trailing: StatusBadge(
              label: (widget.isWindows || widget.clipboardService.isListening)
                  ? 'BACKGROUND SYNC'
                  : 'STANDBY',
              isActive: widget.isWindows ||
                  (widget.clipboardService.isListening && _serverReachable),
              activeColor: colors.success,
            ),
          ),
          const SizedBox(height: 16),

          // Live connection status (Android banner)
          if (!widget.isWindows) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (!widget.clipboardService.isListening
                        ? colors.textMuted
                        : (_serverReachable
                            ? colors.success
                            : AppColors.error))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    !widget.clipboardService.isListening
                        ? Icons.pause_circle_outline_rounded
                        : (_serverReachable
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded),
                    size: 16,
                    color: !widget.clipboardService.isListening
                        ? colors.textMuted
                        : (_serverReachable
                            ? colors.success
                            : AppColors.error),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      !widget.clipboardService.isListening
                          ? 'Standby: Tap "Connect to Windows PC" above to activate live clipboard sync.'
                          : (_serverReachable
                              ? 'Connected to your PC. Copies sync in real time.'
                              : (_syncError ??
                                  'PC server is not reachable. Make sure PCLink is running on the PC.')),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: _serverReachable && widget.clipboardService.isListening
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: !widget.clipboardService.isListening
                            ? colors.textMuted
                            : (_serverReachable
                                ? colors.success
                                : colors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Controls Row (Auto Sync Toggle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 18, color: colors.primaryLight),
                    const SizedBox(width: 10),
                    Text(
                      'Auto-Transfer to Clipboard',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _autoSync ? colors.textPrimary : colors.textMuted,
                      ),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: _autoSync,
                    activeThumbColor: colors.primaryLight,
                    activeTrackColor: colors.primary.withValues(alpha: 0.35),
                    onChanged: _toggleAutoSync,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stream of clips from direct local server route
          StreamBuilder<List<ClipboardItem>>(
            stream: widget.clipboardService.clipboardHistoryStream,
            initialData: widget.clipboardService.currentHistory,
            builder: (context, snapshot) {
              final allClips = snapshot.data ?? widget.clipboardService.currentHistory;
              final peerClips = allClips.where((c) => c.sourcePlatform != currentPlatform).toList();
              final localClips = allClips.where((c) => c.sourcePlatform == currentPlatform).toList();

              final List<ClipboardItem> displayClips;
              if (_filter == 'peer') {
                displayClips = peerClips;
              } else if (_filter == 'local') {
                displayClips = localClips;
              } else {
                displayClips = allClips;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Pills Row
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterPill(
                                colors: colors,
                                label: 'All (${allClips.length})',
                                keyName: 'all',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterPill(
                                colors: colors,
                                label: 'Peer (${peerClips.length})',
                                keyName: 'peer',
                              ),
                              const SizedBox(width: 6),
                              _buildFilterPill(
                                colors: colors,
                                label: 'Mine (${localClips.length})',
                                keyName: 'local',
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, size: 18, color: colors.textMuted),
                        tooltip: 'Clear history',
                        onPressed: allClips.isEmpty ? null : _confirmClear,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (displayClips.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                      decoration: BoxDecoration(
                        color: colors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.content_paste_go_rounded,
                              size: 22,
                              color: colors.primaryLight,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filter == 'peer'
                                ? 'No clips received from $peerPlatformLabel yet.'
                                : _filter == 'local'
                                    ? 'No clips copied on this device yet.'
                                    : 'No clipboard history yet.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _filter == 'peer'
                                ? 'Copy text on $peerPlatformLabel and it will appear here instantly.'
                                : 'Copy any text on either device and it will sync automatically.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: displayClips.take(15).map((clip) {
                        return ClipboardItemTile(
                          item: clip,
                          isCurrentPlatform: clip.sourcePlatform == currentPlatform,
                          onCopied: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to system clipboard!'),
                                duration: Duration(seconds: 1),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required AppThemeColors colors,
    required String label,
    required String keyName,
  }) {
    final isSelected = _filter == keyName;

    return Bounceable(
      onTap: () => setState(() => _filter = keyName),
      scaleFactor: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? colors.primaryLight : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
