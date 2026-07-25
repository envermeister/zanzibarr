import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/settings/indexer_settings.dart';
import 'package:zanzibarr/settings/provider_settings.dart';
import 'package:zanzibarr/settings/settings_screen.dart';
import 'package:zanzibarr/src/rust/api/search.dart';

import 'l10n_test_helper.dart';

/// Secure storage method channel'ını bellek içi haritayla taklit eder;
/// böylece [IndexerSettingsStore] gerçek kod yoluyla sınanır.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final _memoryStorage = <String, String>{};

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return _memoryStorage[key];
          case 'write':
            _memoryStorage[key!] = args['value'] as String;
            return null;
          case 'delete':
            _memoryStorage.remove(key);
            return null;
          case 'deleteAll':
            _memoryStorage.clear();
            return null;
        }
        return null;
      });
}

/// Ayar ekranı testlerinde gerçek secure storage yerine bellek içi sahte depo.
class _FakeIndexerStore extends IndexerSettingsStore {
  IndexerSettings saved = const IndexerSettings();

  @override
  Future<IndexerSettings> load() async => saved;

  @override
  Future<void> save(IndexerSettings settings) async => saved = settings;
}

/// NNTP bölümü de ekran açılışında depo okur; kanala düşmemesi için sahte.
class _FakeProviderStore extends ProviderSettingsStore {
  @override
  Future<ProviderSettings> load() async => const ProviderSettings();
}

/// ListView tembel kurulduğundan alt bölümler ancak kaydırınca ağaca girer;
/// scrollUntilVisible cacheExtent'te durabildiği için ensureVisible ile
/// öğe tamamen görünür alana çekilir ve sonraki tap'in doğru koordinatı
/// görmesi için settle edilir. (Metin alanları da Scrollable taşıdığı için
/// en dıştaki seçilir.)
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IndexerSettingsStore', () {
    setUp(() {
      _memoryStorage.clear();
      _mockSecureStorage();
    });

    test('Boş depoda varsayılan (boş) ayarlar döner', () async {
      final settings = await IndexerSettingsStore().load();
      expect(settings.baseUrl, isEmpty);
      expect(settings.apiKey, isEmpty);
      expect(settings.isComplete, isFalse);
    });

    test('Kaydedilen ayarlar geri okunur', () async {
      final store = IndexerSettingsStore();
      await store.save(
        const IndexerSettings(
          baseUrl: 'https://indexer.example',
          apiKey: 'gizli-anahtar',
        ),
      );
      final settings = await store.load();
      expect(settings.baseUrl, 'https://indexer.example');
      expect(settings.apiKey, 'gizli-anahtar');
      expect(settings.isComplete, isTrue);
    });

    test('clear anahtarları siler', () async {
      final store = IndexerSettingsStore();
      await store.save(
        const IndexerSettings(baseUrl: 'https://indexer.example', apiKey: 'k'),
      );
      await store.clear();
      final settings = await store.load();
      expect(settings.isComplete, isFalse);
    });

    test('isComplete yalnızca iki alan da doluyken true olur', () {
      expect(const IndexerSettings().isComplete, isFalse);
      expect(
        const IndexerSettings(baseUrl: 'https://x.example').isComplete,
        isFalse,
      );
      expect(const IndexerSettings(apiKey: 'k').isComplete, isFalse);
      expect(
        const IndexerSettings(baseUrl: 'https://x.example', apiKey: 'k')
            .isComplete,
        isTrue,
      );
    });
  });

  group('SettingsScreen indexer bölümü', () {
    testWidgets('Indexer bölümü görünür ve sahte depoya kaydeder', (
      tester,
    ) async {
      final store = _FakeIndexerStore();
      await tester.pumpWithL10n(
        SettingsScreen(store: _FakeProviderStore(), indexerStore: store),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.text('Indexer (Newznab)'));
      await tester.pumpAndSettle();
      expect(find.text('Indexer (Newznab)'), findsOneWidget);
      expect(find.text("Indexer URL'si"), findsOneWidget);
      expect(find.text('API anahtarı'), findsOneWidget);

      await _reveal(tester, find.widgetWithText(TextFormField, "Indexer URL'si"));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Indexer URL'si"),
        'https://indexer.example',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'API anahtarı'),
        'cok-gizli',
      );

      await _reveal(tester, find.text("Indexer'ı kaydet"));
      await tester.tap(find.text("Indexer'ı kaydet"));
      await tester.pumpAndSettle();

      expect(store.saved.baseUrl, 'https://indexer.example');
      expect(store.saved.apiKey, 'cok-gizli');
      expect(store.saved.isComplete, isTrue);
      expect(find.text('Ayarlar güvenli depoya kaydedildi.'), findsOneWidget);
    });

    testWidgets('Geçersiz URL kaydı engelliyor', (tester) async {
      final store = _FakeIndexerStore();
      await tester.pumpWithL10n(
        SettingsScreen(store: _FakeProviderStore(), indexerStore: store),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.widgetWithText(TextFormField, "Indexer URL'si"));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Indexer URL'si"),
        'ftp://indexer.example',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'API anahtarı'),
        'anahtar',
      );

      await _reveal(tester, find.text("Indexer'ı kaydet"));
      await tester.tap(find.text("Indexer'ı kaydet"));
      await tester.pumpAndSettle();

      expect(
        find.text('http:// veya https:// ile başlayan geçerli bir URL girin'),
        findsOneWidget,
      );
      expect(store.saved.isComplete, isFalse);
    });

    testWidgets('URL doluyken API anahtarı zorunlu', (tester) async {
      final store = _FakeIndexerStore();
      await tester.pumpWithL10n(
        SettingsScreen(store: _FakeProviderStore(), indexerStore: store),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.widgetWithText(TextFormField, "Indexer URL'si"));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Indexer URL'si"),
        'https://indexer.example',
      );

      await _reveal(tester, find.text("Indexer'ı kaydet"));
      await tester.tap(find.text("Indexer'ı kaydet"));
      await tester.pumpAndSettle();

      expect(find.text('API anahtarı gerekli'), findsOneWidget);
      expect(store.saved.isComplete, isFalse);
    });

    testWidgets('Boş URL geçerli sayılır (indexer kapalı)', (tester) async {
      final store = _FakeIndexerStore();
      await tester.pumpWithL10n(
        SettingsScreen(store: _FakeProviderStore(), indexerStore: store),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.text("Indexer'ı kaydet"));
      await tester.tap(find.text("Indexer'ı kaydet"));
      await tester.pumpAndSettle();

      expect(store.saved.baseUrl, isEmpty);
      expect(store.saved.apiKey, isEmpty);
      expect(find.text('Ayarlar güvenli depoya kaydedildi.'), findsOneWidget);
    });

    testWidgets('Bağlantıyı sına caps sonucunu SnackBar ile gösterir', (
      tester,
    ) async {
      final store = _FakeIndexerStore();
      IndexerConfigDto? capsConfig;
      await tester.pumpWithL10n(
        SettingsScreen(
          store: _FakeProviderStore(),
          indexerStore: store,
          capsFn: (config) async {
            capsConfig = config;
            return const IndexerCapsDto(
              serverTitle: 'Miatrix',
              searchAvailable: true,
              tvSearchAvailable: true,
              movieSearchAvailable: true,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.widgetWithText(TextFormField, "Indexer URL'si"));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Indexer URL'si"),
        'https://indexer.example',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'API anahtarı'),
        'anahtar',
      );

      await _reveal(tester, find.text('Bağlantıyı sına'));
      await tester.tap(find.text('Bağlantıyı sına'));
      await tester.pumpAndSettle();

      expect(capsConfig?.baseUrl, 'https://indexer.example');
      expect(find.text('Bağlandı: Miatrix'), findsOneWidget);
    });
  });
}
