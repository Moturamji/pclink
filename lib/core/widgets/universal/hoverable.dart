import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Desktop hover feedback wrapper that provides clean, professional tactile feedback
/// (calibrated subtle tonal shift, hairline highlight, optional micro-scale)
/// without blurry lighting halos, artificial neon glows, or redundant nested containers.
class Hoverable extends StatefulWidget {
  final Widget? child;
  final Widget Function(BuildContext context, bool isHovered)? builder;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius? borderRadius;
  final Color? hoverBorderColor;
  final Color? hoverColor;
  final bool showShadow;
  final bool enabled;

  const Hoverable({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.scale = 1.0,
    this.borderRadius,
    this.hoverBorderColor,
    this.hoverColor,
    this.showShadow = false,
    this.enabled = true,
  }) : assert(
         child != null || builder != null,
         'Either child or builder must be provided to Hoverable',
       );

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder != null
          ? widget.builder!(context, false)
          : widget.child!;
    }
    final colors = context.colors;
    final br = widget.borderRadius ?? BorderRadius.circular(12);

    final targetBg = widget.hoverColor ??
        colors.surfaceSubtle.withValues(alpha: 0.6);
    final targetBorder = widget.hoverBorderColor;

    final content = widget.builder != null
        ? widget.builder!(context, _isHovered)
        : AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: br,
              color: _isHovered
                  ? targetBg
                  : targetBg.withValues(alpha: 0.0),
              border: targetBorder != null
                  ? Border.all(
                      color: _isHovered
                          ? targetBorder
                          : targetBorder.withValues(alpha: 0.0),
                      width: 0.8,
                    )
                  : null,
              boxShadow: (widget.showShadow && _isHovered)
                  ? [
                      BoxShadow(
                        color: colors.isDark
                            ? Colors.black.withValues(alpha: 0.2)
                            : colors.primary.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: widget.child!,
          );

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        
        onTap: widget.onTap,
        child: widget.scale != 1.0
        
            ? AnimatedScale(
                scale: _isHovered ? widget.scale : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: content,
              )
            : content,
      ),
    );
  }
}
