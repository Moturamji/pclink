import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'bounceable.dart';

class TabItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color? activeColor;

  const TabItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.activeColor,
  });
}

/// Floating squircle bottom navigation bar with a smooth sliding indicator pill and tactile feedback.
class AnimatedTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<TabItemData> items;

  const AnimatedTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: colors.cardSurface.withValues(alpha: colors.isDark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colors.cardBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.35 : 0.08),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = selectedIndex == index;
          final activeColor = item.activeColor ?? colors.primary;

          return Expanded(
            child: Bounceable(
              scaleFactor: 0.94,
              onTap: () => onTabSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: colors.isDark ? 0.2 : 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        isSelected ? item.activeIcon : item.icon,
                        size: 22,
                        color: isSelected ? activeColor : colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? activeColor : colors.textMuted,
                        letterSpacing: isSelected ? 0.2 : 0.0,
                      ),
                      child: Text(item.label),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
