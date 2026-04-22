import 'package:ai_accounting_app/services/theme_mode_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeModeService', () {
    Future<ThemeModeService> createService([
      Map<String, Object> initialValues = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initialValues);
      final prefs = await SharedPreferences.getInstance();
      return ThemeModeService(prefs);
    }

    test('defaults to light mode when no preference is stored', () async {
      final service = await createService();

      expect(service.preference, AppThemePreference.light);
      expect(service.themeMode, ThemeMode.light);
    });

    test('persists explicit dark mode selection', () async {
      final service = await createService();

      await service.setPreference(AppThemePreference.dark);

      expect(service.preference, AppThemePreference.dark);
      expect(service.themeMode, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'dark');

      final restored = ThemeModeService(prefs);
      expect(restored.preference, AppThemePreference.dark);
      expect(restored.themeMode, ThemeMode.dark);
    });

    test('unknown stored value falls back to light mode', () async {
      final service = await createService({'app_theme_mode': 'system'});

      expect(service.preference, AppThemePreference.light);
      expect(service.themeMode, ThemeMode.light);
    });
  });
}
