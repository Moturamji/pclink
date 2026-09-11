import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Premium, Cute & Modern App Logo Widget using the official PCLink logo branding.
/// Features a gentle breathing glow, crisp 1px border, and customizable dimensions.
class AppLogo extends StatefulWidget {
  final double size;
  final bool showGlow;
  final bool isAnimated;
  final double borderRadius;

  const AppLogo({
    super.key,
    this.size = 56,
    this.showGlow = true,
    this.isAnimated = false,
    this.borderRadius = 16,
  });

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.38).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    if (widget.isAnimated) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AppLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimated != oldWidget.isAnimated) {
      if (widget.isAnimated) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget logoBody = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: colors.primary.withValues(alpha: context.isDark ? 0.35 : 0.25),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/logo/IMG_20260911_111434.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Icon(
              Icons.devices_rounded,
              size: widget.size * 0.55,
              color: AppColors.primaryLight,
            ),
          );
        },
      ),
    );

    if (!widget.showGlow) return logoBody;

    if (widget.isAnimated) {
      return AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius + 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _glowAnimation.value),
                  blurRadius: widget.size * 0.45,
                  spreadRadius: widget.size * 0.08,
                ),
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: _glowAnimation.value * 0.5),
                  blurRadius: widget.size * 0.65,
                  spreadRadius: widget.size * 0.04,
                ),
              ],
            ),
            child: child,
          );
        },
        child: logoBody,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius + 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: widget.size * 0.35,
            spreadRadius: 2,
          ),
        ],
      ),
      child: logoBody,
    );
  }
}
