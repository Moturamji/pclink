import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/copy_action_button.dart';
import '../models/clipboard_item.dart';

/// Renders a single synced clipboard item with platform badge, timestamp, preview, and 1-tap copy action.
/// Redesigned with flat surface elevation and no nested bordered boxes.
class ClipboardItemTile extends StatelessWidget {
  final ClipboardItem item;
  final bool isCurrentPlatform;
  final VoidCallback? onCopied;

  const ClipboardItemTile({
    super.key,
    required this.item,
    required this.isCurrentPlatform,
    this.onCopied,
  });

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isFromWindows = item.isFromWindows;
    final platformColor = isFromWindows ? colors.primaryLight : colors.secondary;
    final platformLabel = isFromWindows ? 'Windows PC' : 'Android Phone';
    final platformIcon =
        isFromWindows ? Icons.laptop_windows_rounded : Icons.phone_android_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.cardBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(platformIcon, size: 12, color: platformColor),
                    const SizedBox(width: 5),
                    Text(
                      platformLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: platformColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTimeAgo(item.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              CopyActionButton(
                textToCopy: item.text,
                label: 'Copy to Device',
                successLabel: 'Copied!',
                onCopied: onCopied,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            item.text,
            maxLines: 4,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Consolas',
              color: colors.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
