import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Central theme management service that handles theme switching and persistence.
class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _fileName = 'pclink_theme_pref.txt';
  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Initializes the service and loads saved theme preference if available.
  Future<void> init() async {
    try {
      final mode = await _loadSavedTheme();
      if (mode != null) {
        themeModeNotifier.value = mode;
      }
    } catch (e) {
      debugPrint('ThemeService: Error loading saved theme: $e');
    }
  }

  /// Current active ThemeMode.
  ThemeMode get currentMode => themeModeNotifier.value;

  /// Sets the theme mode explicitly and saves it.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeModeNotifier.value == mode) return;
    themeModeNotifier.value = mode;
    await _saveTheme(mode);
  }

  /// Toggles between Light and Dark mode based on current effective brightness.
  Future<void> toggleTheme(BuildContext context) async {
    final isDark = isDarkMode(context);
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// Determines if the active theme is dark given the context.
  bool isDarkMode(BuildContext context) {
    if (themeModeNotifier.value == ThemeMode.dark) return true;
    if (themeModeNotifier.value == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  Future<File?> _getPrefFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      try {
        final tempDir = await getTemporaryDirectory();
        return File('${tempDir.path}/$_fileName');
      } catch (e) {
        debugPrint('ThemeService: Could not get storage directory: $e');
        return null;
      }
    }
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final file = await _getPrefFile();
      if (file != null) {
        await file.writeAsString(mode.name);
      }
    } catch (e) {
      debugPrint('ThemeService: Error saving theme: $e');
    }
  }

  Future<ThemeMode?> _loadSavedTheme() async {
    try {
      final file = await _getPrefFile();
      if (file != null && await file.exists()) {
        final content = (await file.readAsString()).trim();
        for (final mode in ThemeMode.values) {
          if (mode.name == content) {
            return mode;
          }
        }
      }
    } catch (e) {
      debugPrint('ThemeService: Error reading saved theme: $e');
    }
    return null;
  }
}
