import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/app_card_header.dart';
import '../../../core/widgets/universal/status_badge.dart';
import '../../../data/services/database_service.dart';
import '../models/clipboard_item.dart';
import '../services/clipboard_service.dart';
import 'clipboard_item_tile.dart';

/// Card managing bidirectional real-time clipboard sync between Windows PC and Android phone.
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

  @override
  void initState() {
    super.initState();
    _autoSync = widget.clipboardService.isAutoSyncEnabled;
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
            ? 'Auto-Sync enabled: Copied items from other device transfer directly to your clipboard.'
            : 'Auto-Sync paused: Tap copy on individual clips to transfer.',
        ),
        backgroundColor: value ? AppColors.success : AppColors.surface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Clipboard History?'),
        content: const Text('This will clear the synced clipboard history for both devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
    final currentPlatform = widget.isWindows ? 'windows' : 'android';
    final peerPlatformLabel = widget.isWindows ? 'Android Phone' : 'Windows PC';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCardHeader(
              icon: Icons.content_paste_rounded,
              iconColor: AppColors.primaryLight,
              title: 'LIVE CLIPBOARD SYNC',
              trailing: const StatusBadge(
                label: 'BACKGROUND SYNC',
                isActive: true,
                activeColor: AppColors.successLight,
              ),
            ),
            const SizedBox(height: 14),

            // Controls Row (Auto Sync Toggle + Clear History)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_rounded, size: 16, color: AppColors.primaryLight),
                      const SizedBox(width: 8),
                      Text(
                        'Auto-Transfer to Clipboard',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _autoSync ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _autoSync,
                      activeThumbColor: AppColors.primaryLight,
                      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                      onChanged: _toggleAutoSync,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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
                    // Filter Pills
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterPill(
                                  label: 'All (${allClips.length})',
                                  keyName: 'all',
                                ),
                                const SizedBox(width: 6),
                                _buildFilterPill(
                                  label: 'Peer (${peerClips.length})',
                                  keyName: 'peer',
                                ),
                                const SizedBox(width: 6),
                                _buildFilterPill(
                                  label: 'Mine (${localClips.length})',
                                  keyName: 'local',
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                          tooltip: 'Clear history',
                          onPressed: allClips.isEmpty ? null : _confirmClear,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (displayClips.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.content_paste_go_rounded,
                              size: 32,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _filter == 'peer'
                                  ? 'No clips received from $peerPlatformLabel yet.'
                                  : _filter == 'local'
                                      ? 'No clips copied on this device yet.'
                                      : 'No clipboard history yet.',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _filter == 'peer'
                                  ? 'Copy text on $peerPlatformLabel and it will appear here instantly.'
                                  : 'Copy any text on either device and it will sync automatically.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
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
      ),
    );
  }

  Widget _buildFilterPill({required String label, required String keyName}) {
    final isSelected = _filter == keyName;

    return GestureDetector(
      onTap: () => setState(() => _filter = keyName),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
