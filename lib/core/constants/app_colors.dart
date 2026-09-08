import 'package:flutter/material.dart';

/// Design system color palette: Cute, Premium, Modern & Organic (Non-AI).
abstract final class AppColors {
  // Brand & Warm Accents (Non-AI organic tones)
  static const Color primary = Color(0xFFEAB308); // Warm Honey Amber
  static const Color primaryLight = Color(0xFFFDE047); // Radiant Soft Gold
  static const Color primaryDark = Color(0xFFCA8A04); // Deep Honey

  static const Color secondary = Color(0xFF14B8A6); // Fresh Matcha Teal
  static const Color secondaryLight = Color(0xFF5EEAD4); // Soft Mint Sage
  
  static const Color accentCoral = Color(0xFFF43F5E); // Cute Soft Coral Rose
  static const Color accentCoralLight = Color(0xFFFDA4AF);
  static const Color accentWarm = Color(0xFFFB923C); // Warm Tangerine

  // Backgrounds & Warm Obsidian Surfaces
  static const Color background = Color(0xFF0F1015); // Deep Velvety Warm Obsidian
  static const Color surface = Color(0xFF16171F); // Dark Graphite Slate
  static const Color cardSurface = Color(0xFF1D1F2B); // Elevated Card Surface
  static const Color cardSurfaceHover = Color(0xFF242736);
  static const Color cardBorder = Color(0xFF2C3042); // Soft Defined Border

  // Status & Utility Colors
  static const Color success = Color(0xFF10B981); // Emerald Matcha
  static const Color successLight = Color(0xFF34D399); // Soft Mint Green
  static const Color error = Color(0xFFF43F5E); // Coral Red
  static const Color warning = Color(0xFFF59E0B); // Amber

  // Typography Colors
  static const Color textPrimary = Color(0xFFF8FAFC); // Clean Bright Ivory
  static const Color textSecondary = Color(0xFFA1A7BC); // Soft Silver Slate
  static const Color textMuted = Color(0xFF676E85); // Muted Graphite
}

