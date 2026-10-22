import 'package:flutter/material.dart';

/// Design system palette: "Ocean calm".
/// A soft periwinkle-blue accent over cool, quiet neutrals, with muted mint,
/// violet, amber and rose for meaning. Every pairing is chosen for WCAG AA
/// legibility in both the Dark (deep ink) and Light (mist) modes.
abstract final class AppColors {
  // Brand & Primary Accent (soft ocean blue)
  static const Color primary = Color(0xFF5283E8); // Ocean blue
  static const Color primaryLight = Color(0xFF7BA2F0); // Soft sky
  static const Color primaryDark = Color(0xFF3F6FD8); // Deep ocean (light-mode accent)
  static const Color primaryPastel = Color(0xFFE6EEFD); // Mist blue tint

  // Secondary / connected states (sea mint)
  static const Color secondary = Color(0xFF3FAE8A); // Sea mint
  static const Color secondaryLight = Color(0xFF6CC9A6);
  static const Color secondaryDark = Color(0xFF2E8F70);
  static const Color secondaryPastel = Color(0xFFE3F5EF);

  // Purposeful accent categories
  static const Color accentPurple = Color(0xFF8B80E3); // Soft violet (files)
  static const Color accentPurpleLight = Color(0xFFB2ABF2);
  static const Color accentPurplePastel = Color(0xFFEEECFC);

  static const Color accentPink = Color(0xFFE06C7C); // Soft rose (destructive)
  static const Color accentPinkLight = Color(0xFFF0A6B0);
  static const Color accentPinkPastel = Color(0xFFFBE9EC);

  static const Color accentWarm = Color(0xFFE09E4C); // Soft amber (power & locks)
  static const Color accentWarmLight = Color(0xFFF0C27F);
  static const Color accentWarmPastel = Color(0xFFFBF0DF);

  // Status & utility
  static const Color success = Color(0xFF3FAE8A);
  static const Color successLight = Color(0xFF6CC9A6);
  static const Color error = Color(0xFFE06C7C);
  static const Color warning = Color(0xFFE09E4C);

  // --- Dark mode (deep ink, quiet blue undertone) ---
  static const Color darkBackground = Color(0xFF10141C);
  static const Color darkSurface = Color(0xFF141A24);
  static const Color darkCardSurface = Color(0xFF181E29);
  static const Color darkCardSurfaceHover = Color(0xFF1E2633);
  static const Color darkSurfaceSubtle = Color(0xFF1D2431);
  static const Color darkCardBorder = Color(0xFF253042);
  static const Color darkCardBorderGlow = Colors.transparent;
  static const Color darkTextPrimary = Color(0xFFE8ECF3);
  static const Color darkTextSecondary = Color(0xFFA3ADBE);
  static const Color darkTextMuted = Color(0xFF7D889B);

  // --- Light mode (cool mist, crisp white cards) ---
  static const Color lightBackground = Color(0xFFF4F7FB);
  static const Color lightSurface = Color(0xFFEEF2F8);
  static const Color lightCardSurface = Color(0xFFFFFFFF);
  static const Color lightCardSurfaceHover = Color(0xFFF8FAFD);
  static const Color lightSurfaceSubtle = Color(0xFFEFF3F9);
  static const Color lightCardBorder = Color(0xFFE3E9F2);
  static const Color lightCardBorderGlow = Colors.transparent;
  static const Color lightTextPrimary = Color(0xFF1F2633);
  static const Color lightTextSecondary = Color(0xFF4E5A6D);
  static const Color lightTextMuted = Color(0xFF6E7889);

  // Legacy default aliases (dark theme default)
  static const Color background = darkBackground;
  static const Color surface = darkSurface;
  static const Color cardSurface = darkCardSurface;
  static const Color cardSurfaceHover = darkCardSurfaceHover;
  static const Color cardBorder = darkCardBorder;
  static const Color cardBorderGlow = darkCardBorderGlow;
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color textMuted = darkTextMuted;

  /// Dynamic color resolver for current context brightness
  static AppThemeColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppThemeColors.dark : AppThemeColors.light;
  }
}

/// Corner radii. Larger, consistent rounding is a big part of the soft look.
abstract final class AppRadii {
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 14; // buttons, inputs, tiles
  static const double lg = 18; // inner panels
  static const double card = 22; // cards
  static const double sheet = 28; // dialogs, sheets, hero panels
  static const double pill = 999;
}

/// Immutable collection of theme colors resolved for a specific brightness.
class AppThemeColors {
  final bool isDark;
  final Color background;
  final Color surface;
  final Color cardSurface;
  final Color cardSurfaceHover;
  final Color surfaceSubtle;
  final Color cardBorder;
  final Color cardBorderGlow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color primaryLight;
  final Color primaryPastel;
  final Color secondary;
  final Color accentPurple;
  final Color accentPink;
  final Color accentWarm;
  final Color error;
  final Color success;
  final Color shadowColor;

  const AppThemeColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.cardSurface,
    required this.cardSurfaceHover,
    this.surfaceSubtle = AppColors.darkSurfaceSubtle,
    required this.cardBorder,
    required this.cardBorderGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryLight,
    required this.primaryPastel,
    required this.secondary,
    required this.accentPurple,
    required this.accentPink,
    required this.accentWarm,
    required this.error,
    required this.success,
    required this.shadowColor,
  });

  /// Soft two-layer elevation for cards: a tight contact shadow plus a wide,
  /// faint blue-tinted drop. Reads as depth without hard outlines.
  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: shadowColor,
          blurRadius: 20,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ];

  /// Stronger elevation for floating surfaces (dialogs, sheets, hero panels).
  List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: shadowColor.withValues(alpha: (shadowColor.a * 1.4).clamp(0, 1)),
          blurRadius: 36,
          offset: const Offset(0, 10),
        ),
      ];

  /// Soft tinted background for an accent (icon tiles, chips, badges).
  Color tint(Color accent) => accent.withValues(alpha: isDark ? 0.16 : 0.10);

  static const AppThemeColors dark = AppThemeColors(
    isDark: true,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    cardSurface: AppColors.darkCardSurface,
    cardSurfaceHover: AppColors.darkCardSurfaceHover,
    surfaceSubtle: AppColors.darkSurfaceSubtle,
    cardBorder: AppColors.darkCardBorder,
    cardBorderGlow: AppColors.darkCardBorderGlow,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textMuted: AppColors.darkTextMuted,
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    primaryPastel: Color(0x295283E8),
    secondary: AppColors.secondaryLight,
    accentPurple: AppColors.accentPurpleLight,
    accentPink: AppColors.accentPinkLight,
    accentWarm: AppColors.accentWarmLight,
    error: AppColors.accentPinkLight,
    success: AppColors.successLight,
    shadowColor: Color(0x33000000),
  );

  static const AppThemeColors light = AppThemeColors(
    isDark: false,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    cardSurface: AppColors.lightCardSurface,
    cardSurfaceHover: AppColors.lightCardSurfaceHover,
    surfaceSubtle: AppColors.lightSurfaceSubtle,
    cardBorder: AppColors.lightCardBorder,
    cardBorderGlow: AppColors.lightCardBorderGlow,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textMuted: AppColors.lightTextMuted,
    primary: AppColors.primaryDark,
    // Accent used for text/icons on white: a touch deeper than the brand blue
    // so 12-14px labels keep AA contrast.
    primaryLight: Color(0xFF4A78DD),
    primaryPastel: AppColors.primaryPastel,
    secondary: AppColors.secondaryDark,
    accentPurple: AppColors.accentPurple,
    accentPink: AppColors.accentPink,
    accentWarm: AppColors.accentWarm,
    error: AppColors.error,
    success: AppColors.secondaryDark,
    shadowColor: Color(0x0F2A3F66),
  );
}

/// Handy context extensions for ultra-clean UI theming
extension AppThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  AppThemeColors get colors => AppColors.of(this);
}
