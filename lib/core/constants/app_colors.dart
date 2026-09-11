import 'package:flutter/material.dart';

/// Design system color palette: Cute, Premium, Modern, and Cyber-Clean.
/// Styled and harmonious with the official PCLink logo branding in both Dark and Light modes.
abstract final class AppColors {
  // Brand & Cyber Accents (Matching official Logo Electric Cyan/Blue)
  static const Color primary = Color(0xFF0EA5E9); // Electric Cyan Sky
  static const Color primaryLight = Color(0xFF38BDF8); // Luminous Sky Neon
  static const Color primaryDark = Color(0xFF0284C7); // Deep Cyber Blue

  // Secondary Fresh & Vibrant Accents
  static const Color secondary = Color(0xFF10B981); // Emerald Mint
  static const Color secondaryLight = Color(0xFF34D399); // Soft Neo Mint
  static const Color secondaryDark = Color(0xFF059669);

  // Cute Accents & Playful Highlights
  static const Color accentPurple = Color(0xFF8B5CF6); // Cute Electric Violet
  static const Color accentPurpleLight = Color(0xFFA78BFA);
  static const Color accentPink = Color(0xFFEC4899); // Cute Rose Magenta
  static const Color accentCoral = Color(0xFFF43F5E); // Soft Coral Rose
  static const Color accentCoralLight = Color(0xFFFDA4AF);
  static const Color accentWarm = Color(0xFFF59E0B); // Radiant Amber

  // Status & Utility Colors
  static const Color success = Color(0xFF10B981); // Mint Success
  static const Color successLight = Color(0xFF34D399);
  static const Color error = Color(0xFFF43F5E); // Cute Coral Red
  static const Color warning = Color(0xFFF59E0B); // Amber Warning

  // --- Dark Mode Surface & Palette ---
  static const Color darkBackground = Color(0xFF0A0E17); // Deep Midnight Obsidian
  static const Color darkSurface = Color(0xFF101726); // Dark Graphite Slate
  static const Color darkCardSurface = Color(0xFF162032); // Elevated Luminous Card
  static const Color darkCardSurfaceHover = Color(0xFF1D2A42);
  static const Color darkCardBorder = Color(0xFF24334D); // Crisp 1px Border Outline
  static const Color darkCardBorderGlow = Color(0x3338BDF8); // Soft Neon Blue Halo
  static const Color darkTextPrimary = Color(0xFFF8FAFC); // Clean Bright Ivory
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Soft Slate Silver
  static const Color darkTextMuted = Color(0xFF64748B); // Muted Graphite

  // --- Light Mode Surface & Palette (Crisp, Modern, High-Contrast) ---
  static const Color lightBackground = Color(0xFFF8FAFC); // Soft Alabaster Mist
  static const Color lightSurface = Color(0xFFF1F5F9); // Crisp Slate Container
  static const Color lightCardSurface = Color(0xFFFFFFFF); // Pure Crisp White
  static const Color lightCardSurfaceHover = Color(0xFFF8FAFC);
  static const Color lightCardBorder = Color(0xFFE2E8F0); // Delicate Slate 200 outline
  static const Color lightCardBorderGlow = Color(0x1A0EA5E9); // Soft Sky Halo
  static const Color lightTextPrimary = Color(0xFF0F172A); // Deep Slate Charcoal
  static const Color lightTextSecondary = Color(0xFF475569); // Medium Slate
  static const Color lightTextMuted = Color(0xFF94A3B8); // Soft Slate

  // Legacy Default Aliases (Dark Theme by default)
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

/// Immutable collection of theme colors resolved for a specific brightness.
class AppThemeColors {
  final bool isDark;
  final Color background;
  final Color surface;
  final Color cardSurface;
  final Color cardSurfaceHover;
  final Color cardBorder;
  final Color cardBorderGlow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color primaryLight;
  final Color secondary;
  final Color error;
  final Color success;

  const AppThemeColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.cardSurface,
    required this.cardSurfaceHover,
    required this.cardBorder,
    required this.cardBorderGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryLight,
    required this.secondary,
    required this.error,
    required this.success,
  });

  static const AppThemeColors dark = AppThemeColors(
    isDark: true,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    cardSurface: AppColors.darkCardSurface,
    cardSurfaceHover: AppColors.darkCardSurfaceHover,
    cardBorder: AppColors.darkCardBorder,
    cardBorderGlow: AppColors.darkCardBorderGlow,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textMuted: AppColors.darkTextMuted,
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    secondary: AppColors.secondary,
    error: AppColors.error,
    success: AppColors.success,
  );

  static const AppThemeColors light = AppThemeColors(
    isDark: false,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    cardSurface: AppColors.lightCardSurface,
    cardSurfaceHover: AppColors.lightCardSurfaceHover,
    cardBorder: AppColors.lightCardBorder,
    cardBorderGlow: AppColors.lightCardBorderGlow,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textMuted: AppColors.lightTextMuted,
    primary: AppColors.primaryDark,
    primaryLight: AppColors.primary,
    secondary: AppColors.secondaryDark,
    error: AppColors.error,
    success: AppColors.success,
  );
}

/// Handy context extensions for ultra-clean UI theming
extension AppThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  AppThemeColors get colors => AppColors.of(this);
}
