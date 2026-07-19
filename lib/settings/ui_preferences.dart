import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Uygulamanın desteklediği arayüz dilleri. İlk öğe varsayılan dildir (en).
///
/// Etiketler bilinçli olarak her dilin kendi adıyla yazılır; böylece dil
/// seçici her yerelleştirmede aynı kalır ve çeviri anahtarı gerekmez.
const supportedAppLocales = <(Locale, String)>[
  (Locale('en'), 'English'),
  (Locale('tr'), 'Türkçe'),
  (Locale('es'), 'Español'),
  (Locale('de'), 'Deutsch'),
  (Locale('fr'), 'Français'),
  (Locale('pt'), 'Português'),
  (Locale('it'), 'Italiano'),
  (Locale('ru'), 'Русский'),
  (Locale('zh'), '中文'),
  (Locale('ja'), '日本語'),
  (Locale('ko'), '한국어'),
  (Locale('hi'), 'हिन्दी'),
  (Locale('ar'), 'العربية'),
  (Locale('fa'), 'فارسی'),
];

/// Arayüz tercihleri: tema modu (varsayılan koyu) ve dil (varsayılan en).
///
/// Değerler OS secure storage'da tutulur; sır içermez, ProviderSettingsStore
/// ile aynı saklama desenini izler.
class UiPreferencesStore {
  UiPreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kThemeMode = 'ui.themeMode';
  static const _kLocale = 'ui.locale';

  Future<(ThemeMode, Locale)> load() async {
    final themeRaw = await _storage.read(key: _kThemeMode);
    final localeRaw = await _storage.read(key: _kLocale);
    return (_parseThemeMode(themeRaw), _parseLocale(localeRaw));
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _storage.write(key: _kThemeMode, value: mode.name);

  Future<void> saveLocale(Locale locale) =>
      _storage.write(key: _kLocale, value: locale.languageCode);

  static ThemeMode _parseThemeMode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    // Varsayılan ve bilinmeyen değerler: koyu.
    _ => ThemeMode.dark,
  };

  static Locale _parseLocale(String? raw) {
    if (raw != null) {
      for (final (locale, _) in supportedAppLocales) {
        if (locale.languageCode == raw) return locale;
      }
    }
    return supportedAppLocales.first.$1;
  }
}

/// Tema/dil tercihini çalışma zamanında taşır ve MaterialApp'i yeniden kurar.
class UiPreferencesController extends ChangeNotifier {
  UiPreferencesController(this._store);

  final UiPreferencesStore _store;

  ThemeMode themeMode = ThemeMode.dark;
  Locale locale = supportedAppLocales.first.$1;

  Future<void> load() async {
    final (mode, savedLocale) = await _store.load();
    themeMode = mode;
    locale = savedLocale;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    await _store.saveThemeMode(mode);
  }

  Future<void> setLocale(Locale next) async {
    if (next == locale) return;
    locale = next;
    notifyListeners();
    await _store.saveLocale(next);
  }
}
