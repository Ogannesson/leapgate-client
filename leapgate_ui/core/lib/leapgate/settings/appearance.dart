// The appearance section (02 §1.5.1) and what the main window and the CM read from it: the theme
// and the language, both LocalConfig keys shared with the old UI.
import 'package:flutter/material.dart' show Locale, ThemeMode;

import '../../consts.dart';
import '../../models/platform_model.dart';
import '../bridge.dart';
import '../options.dart';
import 'settings_api.dart';

/// Config: the language the new UI shows, `zh-cn` or `en`, for the few texts the service
/// writes itself (S11, the Telegram code message). Written by the main window.
const kOptionLeapgateUiLang = 'leapgate-ui-lang';

/// What the theme key holds for "跟随系统"; upstream writes it for a custom client
/// (`common.dart:3988`). Anything but `light` and `dark` follows the system.
const kThemeSystem = 'system';

/// The languages the new UI has (03 IQ10), as Rust names them.
const kUiLangs = ['zh-cn', 'en'];

ThemeMode themeModeOf(String theme) => switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// The stored language when the new UI has it; empty ("跟随系统") for any other, which the old UI
/// may have stored and which is left as it is (09 §4.8).
String uiLangChoice(String stored) => kUiLangs.contains(stored) ? stored : '';

/// The language shown: the chosen one, or the system's when it is Chinese, else English (02
/// §1.5.1, 2026-10-30). Only the system's first language counts, as in Rust's `resolve_lang`.
String resolveUiLang(String stored, Locale system) {
  final choice = uiLangChoice(stored);
  if (choice.isNotEmpty) return choice;
  return system.languageCode == 'zh' ? 'zh-cn' : 'en';
}

Locale localeOfUiLang(String lang) =>
    lang == 'zh-cn' ? const Locale('zh') : const Locale('en');

/// Writes the theme and tells the other windows and the CM, as upstream's `changeDarkMode`.
Future<bool> setTheme(OptionScope local, String theme) async {
  final saved = await local.set(kCommConfKeyTheme, theme);
  await bind.mainChangeTheme(dark: theme);
  return saved;
}

/// Writes the language ('' follows the system), tells the CM the language shown, and keeps
/// [kOptionLeapgateUiLang] in step.
Future<bool> setUiLang(OptionScope local, OptionScope config, String lang,
    Locale system) async {
  final saved = await local.set(kCommConfKeyLang, lang);
  // Not upstream's `mainChangeLanguage`: it makes the CM store its whole LocalConfig, read when
  // it started, over the main window's later changes. The CM gets the language shown instead.
  await lgBind.leapgateLangChanged(lang: resolveUiLang(lang, system));
  await syncUiLang(local, config, system);
  return saved;
}

/// At startup and after a change of language: the language shown, through S9, when it differs
/// from what the service has. A failure is only logged: the next start finds the value still
/// different and writes it again.
Future<void> syncUiLang(
    OptionScope local, OptionScope config, Locale system) async {
  final lang = resolveUiLang(local.get(kCommConfKeyLang), system);
  if (config.get(kOptionLeapgateUiLang) == lang) return;
  try {
    await settingsApi.setOptions({kOptionLeapgateUiLang: lang});
  } catch (e) {
    lgBind.leapgateLog(
        level: 2, msg: 'leapgate ui: $kOptionLeapgateUiLang not written: $e');
  }
}
