import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Centralized Material 3 themes for the "Ocean calm" design system.
/// Light and dark are built from one recipe so every component stays in sync:
/// soft tinted surfaces, hairline borders, generous rounding and a calm,
/// clearly tiered type scale.
abstract final class AppTheme {
  static ThemeData get darkTheme => _build(AppThemeColors.dark);
  static ThemeData get lightTheme => _build(AppThemeColors.light);

  static const String _fontFamily = 'Segoe UI';

  static TextTheme _textTheme(AppThemeColors c) {
    TextStyle s(double size, FontWeight w, Color color,
            {double spacing = 0, double height = 1.35}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          color: color,
          letterSpacing: spacing,
          height: height,
        );
    return TextTheme(
      displaySmall: s(34, FontWeight.w700, c.textPrimary, spacing: -0.8, height: 1.15),
      headlineMedium: s(28, FontWeight.w700, c.textPrimary, spacing: -0.6, height: 1.2),
      headlineSmall: s(24, FontWeight.w700, c.textPrimary, spacing: -0.5, height: 1.25),
      titleLarge: s(20, FontWeight.w700, c.textPrimary, spacing: -0.3),
      titleMedium: s(16, FontWeight.w600, c.textPrimary, spacing: -0.2),
      titleSmall: s(14, FontWeight.w600, c.textPrimary, spacing: -0.1),
      bodyLarge: s(15, FontWeight.w400, c.textPrimary, height: 1.55),
      bodyMedium: s(14, FontWeight.w400, c.textSecondary, height: 1.5),
      bodySmall: s(12, FontWeight.w400, c.textMuted, height: 1.45),
      labelLarge: s(14, FontWeight.w600, c.textPrimary, spacing: 0.1),
      labelMedium: s(12, FontWeight.w600, c.textSecondary, spacing: 0.2),
      labelSmall: s(11, FontWeight.w600, c.textMuted, spacing: 0.4),
    );
  }

  static ThemeData _build(AppThemeColors c) {
    final brightness = c.isDark ? Brightness.dark : Brightness.light;
    // Light mode uses the deeper blue for AA contrast with white text.
    final accent = c.primary;
    final onAccent = Colors.white;
    final hairline = BorderSide(color: c.cardBorder, width: 1);
    final textTheme = _textTheme(c);

    OutlineInputBorder field(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _fontFamily,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: c.primaryLight.withValues(alpha: 0.05),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
        surface: c.surface,
        primary: accent,
        onPrimary: onAccent,
        secondary: c.secondary,
        tertiary: c.accentPurple,
        error: c.error,
        outline: c.cardBorder,
        outlineVariant: c.cardBorder,
      ),
      scaffoldBackgroundColor: c.background,
      dividerTheme: DividerThemeData(color: c.cardBorder, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: c.textPrimary, size: 22),
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: hairline,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          side: hairline,
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.cardSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.cardSurface,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.isDark ? AppColors.darkCardSurfaceHover : AppColors.lightTextPrimary,
        contentTextStyle: TextStyle(
          color: c.isDark ? c.textPrimary : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: c.primaryLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.darkCardSurfaceHover : AppColors.lightTextPrimary,
          borderRadius: BorderRadius.circular(AppRadii.xs),
        ),
        textStyle: TextStyle(
          color: c.isDark ? c.textPrimary : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: c.shadowColor,
        textStyle: textTheme.bodyMedium?.copyWith(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: hairline,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        floatingLabelStyle: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
        border: field(Colors.transparent, 1),
        enabledBorder: field(Colors.transparent, 1),
        focusedBorder: field(c.primaryLight, 1.5),
        errorBorder: field(c.error, 1),
        focusedErrorBorder: field(c.error, 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: c.surfaceSubtle,
          disabledForegroundColor: c.textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          backgroundColor: c.cardSurface,
          minimumSize: const Size(88, 48),
          side: hairline,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primaryLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceSubtle,
        selectedColor: c.tint(c.primaryLight),
        side: BorderSide.none,
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(color: c.primaryLight, fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : c.surfaceSubtle,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : c.cardBorder,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        side: BorderSide(color: c.textMuted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primaryLight,
        linearTrackColor: c.surfaceSubtle,
        circularTrackColor: c.surfaceSubtle,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primaryLight,
        inactiveTrackColor: c.surfaceSubtle,
        thumbColor: c.primaryLight,
        overlayColor: c.primaryLight.withValues(alpha: 0.12),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.cardSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.tint(c.primaryLight),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? c.primaryLight : c.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? c.primaryLight : c.textMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.cardSurface,
        indicatorColor: c.tint(c.primaryLight),
        selectedIconTheme: IconThemeData(color: c.primaryLight, size: 22),
        unselectedIconTheme: IconThemeData(color: c.textMuted, size: 22),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.primaryLight,
        unselectedLabelColor: c.textMuted,
        indicatorColor: c.primaryLight,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(c.textMuted.withValues(alpha: 0.35)),
        radius: const Radius.circular(AppRadii.pill),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
