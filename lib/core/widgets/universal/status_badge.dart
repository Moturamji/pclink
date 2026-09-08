import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Universal status badge with a glowing indicator dot.
class StatusBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;

  const StatusBadge({
    super.key,
    required this.label,
    this.isActive = true,
    this.activeColor = AppColors.successLight,
    this.inactiveColor = AppColors.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : inactiveColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
