import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';

/// Universal 1-tap copy action button with haptic feedback and feedback badge.
class CopyActionButton extends StatefulWidget {
  final String textToCopy;
  final String label;
  final String successLabel;
  final VoidCallback? onCopied;

  const CopyActionButton({
    super.key,
    required this.textToCopy,
    this.label = 'Copy',
    this.successLabel = 'Copied!',
    this.onCopied,
  });

  @override
  State<CopyActionButton> createState() => _CopyActionButtonState();
}

class _CopyActionButtonState extends State<CopyActionButton> {
  bool _justCopied = false;

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.textToCopy));
    HapticFeedback.lightImpact();

    if (!mounted) return;
    setState(() => _justCopied = true);
    widget.onCopied?.call();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _justCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleCopy,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _justCopied
                ? AppColors.success.withValues(alpha: 0.18)
                : AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _justCopied
                  ? AppColors.success.withValues(alpha: 0.4)
                  : AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _justCopied ? Icons.check_rounded : Icons.copy_rounded,
                size: 13,
                color: _justCopied ? AppColors.successLight : AppColors.primaryLight,
              ),
              const SizedBox(width: 5),
              Text(
                _justCopied ? widget.successLabel : widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _justCopied ? AppColors.successLight : AppColors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
