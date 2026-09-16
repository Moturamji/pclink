import 'package:flutter/material.dart';

/// Design system color palette: Precision Hardware-Link Console meets Friendly Studio Fluidity.
/// Bespoke, accessible (WCAG AA), and harmonious across Dark (Obsidian) and Light (Nordic) modes.
abstract final class AppColors {
  // Brand & Primary Accents (Electric Cyan-Azure)
  static const Color primary = Color(0xFF0284C7); // Electric Cyan-Azure
  static const Color primaryLight = Color(0xFF38BDF8); // Luminous Azure
  static const Color primaryDark = Color(0xFF0369A1); // Deep Cerulean
  static const Color primaryPastel = Color(0xFFE0F2FE); // Delicate Sky Mist

  // Secondary Fresh & Link States (Spring Mint)
  static const Color secondary = Color(0xFF10B981); // Spring Mint
  static const Color secondaryLight = Color(0xFF34D399); // Neo Mint
  static const Color secondaryDark = Color(0xFF059669);
  static const Color secondaryPastel = Color(0xFFD1FAE5);

  // Purposeful Accent Categories
  static const Color accentPurple = Color(0xFF8B5CF6); // Studio Violet (File Studio)
  static const Color accentPurpleLight = Color(0xFFA78BFA);
  static const Color accentPurplePastel = Color(0xFFEDE9FE);

  static const Color accentPink = Color(0xFFF43F5E); // Radiant Coral (Destructive Safety)
  static const Color accentPinkLight = Color(0xFFFDA4AF);
  static const Color accentPinkPastel = Color(0xFFFFE4E6);

  static const Color accentWarm = Color(0xFFF59E0B); // Amber Flame (System Power & Locks)
  static const Color accentWarmLight = Color(0xFFFBBF24);
  static const Color accentWarmPastel = Color(0xFFFEF3C7);

  // Status & Utility Colors
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFF34D399);
  static const Color error = Color(0xFFF43F5E);
  static const Color warning = Color(0xFFF59E0B);

  // --- Dark Mode Surface & Palette (Obsidian Midnight, Precision Slate) ---
  static const Color darkBackground = Color(0xFF0B0F19); // Obsidian Canvas
  static const Color darkSurface = Color(0xFF111827); // Charcoal Slate
  static const Color darkCardSurface = Color(0xFF162032); // Elevated Card Workbench
  static const Color darkCardSurfaceHover = Color(0xFF1E2B42); // Interactive Lift
  static const Color darkSurfaceSubtle = Color(0xFF1E293B); // Input / Chip Container
  static const Color darkCardBorder = Color(0xFF1F293D); // Hairline 1px Rule
  static const Color darkCardBorderGlow = Color(0x2438BDF8); // Subtle Halo Accent
  static const Color darkTextPrimary = Color(0xFFF8FAFC); // Alabaster (14.8:1 contrast)
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Soft Silver (7.1:1 contrast)
  static const Color darkTextMuted = Color(0xFF64748B); // Muted Slate (4.6:1 contrast)

  // --- Light Mode Surface & Palette (Nordic Alabaster, High Contrast) ---
  static const Color lightBackground = Color(0xFFF8FAFC); // Silky Snow Mist
  static const Color lightSurface = Color(0xFFF1F5F9); // Soft Alabaster Container
  static const Color lightCardSurface = Color(0xFFFFFFFF); // Crisp White Sheet
  static const Color lightCardSurfaceHover = Color(0xFFF8FAFC);
  static const Color lightSurfaceSubtle = Color(0xFFEDF2F7);
  static const Color lightCardBorder = Color(0xFFE2E8F0); // Delicate Hairline Rule
  static const Color lightCardBorderGlow = Color(0x180284C7);
  static const Color lightTextPrimary = Color(0xFF0F172A); // Deep Charcoal (15.2:1 contrast)
  static const Color lightTextSecondary = Color(0xFF334155); // Slate Navy (9.4:1 contrast)
  static const Color lightTextMuted = Color(0xFF64748B); // Medium Slate (4.6:1 contrast)

  // Legacy Default Aliases (Dark Theme default)
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

  const AppThemeColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.cardSurface,
    required this.cardSurfaceHover,
    this.surfaceSubtle = const Color(0xFF1E293B),
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
  });

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
    primaryPastel: Color(0x220284C7),
    secondary: AppColors.secondary,
    accentPurple: AppColors.accentPurple,
    accentPink: AppColors.accentPink,
    accentWarm: AppColors.accentWarm,
    error: AppColors.error,
    success: AppColors.success,
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
    primaryLight: AppColors.primary,
    primaryPastel: AppColors.primaryPastel,
    secondary: AppColors.secondaryDark,
    accentPurple: AppColors.accentPurple,
    accentPink: AppColors.accentPink,
    accentWarm: AppColors.accentWarm,
    error: AppColors.error,
    success: AppColors.success,
  );
}

/// Handy context extensions for ultra-clean UI theming
extension AppThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  AppThemeColors get colors => AppColors.of(this);
}
