import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesState {
  const AppPreferencesState({
    required this.locale,
    required this.themeMode,
  });

  final Locale locale;
  final ThemeMode themeMode;

  AppPreferencesState copyWith({
    Locale? locale,
    ThemeMode? themeMode,
  }) {
    return AppPreferencesState(
      locale: locale ?? this.locale,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class AppPreferencesNotifier extends Notifier<AppPreferencesState> {
  static const _langKey = 'app_lang_code';
  static const _themeKey = 'app_theme_mode';

  @override
  AppPreferencesState build() {
    _loadSaved();
    return const AppPreferencesState(
      locale: Locale('ar'),
      themeMode: ThemeMode.system,
    );
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_langKey) ?? 'ar';
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.system.index;
    final mode = ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    state = AppPreferencesState(locale: Locale(lang), themeMode: mode);
  }

  Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
    state = state.copyWith(locale: Locale(code));
  }

  Future<void> toggleLanguage() async {
    final next = state.locale.languageCode == 'ar' ? 'en' : 'ar';
    await setLanguage(next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    state = state.copyWith(themeMode: mode);
  }
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferencesState>(
  AppPreferencesNotifier.new,
);
