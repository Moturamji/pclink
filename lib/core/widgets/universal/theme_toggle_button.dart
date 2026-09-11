import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/theme_service.dart';
import 'bounceable.dart';

/// Cute animated theme toggle button that switches between Light and Dark mode.
class ThemeToggleButton extends StatelessWidget {
  final double size;
  final EdgeInsets padding;

  const ThemeToggleButton({
    super.key,
    this.size = 20,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (context, mode, child) {
        final isDark = ThemeService().isDarkMode(context);
        final colors = context.colors;

        return Bounceable(
          onTap: () => ThemeService().toggleTheme(context),
          child: Tooltip(
            message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: padding,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurface
                    : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.lightCardBorder,
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? AppColors.primaryLight.withValues(alpha: 0.1)
                        : AppColors.accentWarm.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return RotationTransition(
                    turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
                    child: ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                  );
                },
                child: isDark
                    ? Icon(
                        Icons.light_mode_rounded,
                        key: const ValueKey('sun_icon'),
                        size: size,
                        color: AppColors.accentWarm,
                      )
                    : Icon(
                        Icons.dark_mode_rounded,
                        key: const ValueKey('moon_icon'),
                        size: size,
                        color: colors.primary,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
