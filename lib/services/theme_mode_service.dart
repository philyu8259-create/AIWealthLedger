import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { light, dark }

class ThemeModeService extends ChangeNotifier {
  ThemeModeService(this._prefs)
    : _preference = _parsePreference(_prefs.getString(_prefsKey));

  static const String _prefsKey = 'app_theme_mode';

  final SharedPreferences _prefs;
  AppThemePreference _preference;

  AppThemePreference get preference => _preference;

  ThemeMode get themeMode {
    switch (_preference) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference) return;
    _preference = preference;

    await _prefs.setString(_prefsKey, preference.name);

    notifyListeners();
  }

  static AppThemePreference _parsePreference(String? raw) {
    switch (raw) {
      case 'light':
        return AppThemePreference.light;
      case 'dark':
        return AppThemePreference.dark;
      default:
        return AppThemePreference.light;
    }
  }
}
