import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/settings/provider_settings.dart';
import 'package:zanzibarr/settings/settings_screen.dart';

/// Gerçek secure storage yerine bellek içi sahte depo.
class _FakeStore extends ProviderSettingsStore {
  ProviderSettings saved = const ProviderSettings();

  @override
  Future<ProviderSettings> load() async => saved;

  @override
  Future<void> save(ProviderSettings settings) async => saved = settings;
}

void main() {
  testWidgets('Ayarlar formu doldurulup depoya kaydediliyor', (tester) async {
    final store = _FakeStore();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Sunucu adresi'),
      'news.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kullanıcı adı'),
      'kullanici',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Parola'),
      'cok-gizli',
    );

    await tester.tap(find.text('Güvenle kaydet'));
    await tester.pumpAndSettle();

    expect(store.saved.host, 'news.example.com');
    expect(store.saved.port, 563);
    expect(store.saved.username, 'kullanici');
    expect(store.saved.password, 'cok-gizli');
    expect(store.saved.maxConnections, 10);
    expect(store.saved.isComplete, isTrue);
    expect(find.text('Ayarlar güvenli depoya kaydedildi.'), findsOneWidget);
  });

  testWidgets('Boş sunucu adresi kaydı engelliyor', (tester) async {
    final store = _FakeStore();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Güvenle kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Sunucu adresi gerekli'), findsOneWidget);
    expect(store.saved.host, isEmpty);
  });
}
