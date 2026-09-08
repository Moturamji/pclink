import 'package:flutter/material.dart';

/// Design system color palette and token definitions for PCLink.
abstract final class AppColors {
  // Brand & Accent Colors
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF38BDF8); // Sky Blue
  static const Color accentPurple = Color(0xFFA78BFA);

  // Backgrounds & Surfaces
  static const Color background = Color(0xFF090D16); // Deep slate dark
  static const Color surface = Color(0xFF0F172A); // Slate 900
  static const Color cardSurface = Color(0xFF1E293B); // Slate 800
  static const Color cardBorder = Color(0xFF334155); // Slate 700

  // Status & Utility Colors
  static const Color success = Color(0xFF22C55E); // Green 500
  static const Color successLight = Color(0xFF4ADE80); // Green 400
  static const Color error = Color(0xFFEF4444); // Red 500
  static const Color warning = Color(0xFFFBBF24); // Amber 400

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}
