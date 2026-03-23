// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — LocaleController
// ValueNotifier that persists the selected locale to SharedPreferences and
// propagates it to MaterialApp so the whole app re-renders on language change.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ValueNotifier<Locale> {
  static final LocaleController instance = LocaleController._();
  LocaleController._() : super(const Locale('es'));

  static const _kKey = 'language';

  /// Load the saved language on app start. Falls back to 'es'.
  Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    final code   = prefs.getString(_kKey) ?? 'es';
    value = Locale(code);
  }

  /// Change the app locale and persist it.
  Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, languageCode);
    value = Locale(languageCode);
  }

  String get languageCode => value.languageCode;
}
