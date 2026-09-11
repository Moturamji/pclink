import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/universal/copy_action_button.dart';
import '../models/clipboard_item.dart';

/// Renders a single synced clipboard item with platform badge, timestamp, preview, and 1-tap copy action.
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
    final platformIcon = isFromWindows ? Icons.laptop_windows_rounded : Icons.phone_android_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentPlatform
              ? colors.cardBorder
              : platformColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: platformColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(platformIcon, size: 12, color: platformColor),
                    const SizedBox(width: 4),
                    Text(
                      platformLabel,
                      style: TextStyle(
                        fontSize: 10,
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
                  fontSize: 10,
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
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.cardSurface.withValues(alpha: context.isDark ? 0.6 : 0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
            ),
            child: Text(
              item.previewText,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.35,
                color: colors.textPrimary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${item.charCount} chars',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
              if (item.lineCount > 1) ...[
                const SizedBox(width: 8),
                Text(
                  '• ${item.lineCount} lines',
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
