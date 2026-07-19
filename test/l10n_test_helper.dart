import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/l10n/app_localizations.dart';
import 'package:zanzibarr/settings/ui_preferences.dart';

/// Widget testlerinde Türkçe arayüz beklentilerini koruyan ortak sarmalayıcı.
///
/// Uygulamanın varsayılan dili İngilizce olduğundan, Türkçe metin arayan
/// testler ağacı bu delegate'ler ve `Locale('tr')` ile kurar.
Widget l10nTestApp(Widget home) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('tr'),
  home: home,
);

extension L10nTestPump on WidgetTester {
  /// [home]'u Türkçe yerelleştirmeyle pompa­lar.
  Future<void> pumpWithL10n(Widget home) => pumpWidget(l10nTestApp(home));
}

/// Kendi MaterialApp'ini kuran [ZanzibarrApp] gibi widget'lar için Türkçe
/// tercih taşıyan controller. Depodan okuma yapılmaz; alan doğrudan verilir.
UiPreferencesController turkishUiPreferences() =>
    UiPreferencesController(UiPreferencesStore())
      ..locale = const Locale('tr');
