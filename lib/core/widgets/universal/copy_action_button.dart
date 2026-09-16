import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import 'bounceable.dart';

/// Universal 1-tap copy action button with tactile spring feedback and animated morph.
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

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _justCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = _justCopied
        ? AppColors.success.withValues(alpha: 0.16)
        : colors.surfaceSubtle;
    final activeFg = _justCopied ? AppColors.success : colors.primaryLight;

    return Bounceable(
      onTap: _handleCopy,
      scaleFactor: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                _justCopied ? Icons.check_rounded : Icons.copy_rounded,
                key: ValueKey<bool>(_justCopied),
                size: 13,
                color: activeFg,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _justCopied ? widget.successLabel : widget.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: activeFg,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
