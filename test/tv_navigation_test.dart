import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/player/media_preferences.dart';
import 'package:zanzibarr/player/playback_history.dart';
import 'package:zanzibarr/search/search_screen.dart';
import 'package:zanzibarr/settings/indexer_settings.dart';
import 'package:zanzibarr/settings/provider_settings.dart';
import 'package:zanzibarr/settings/settings_screen.dart';
import 'package:zanzibarr/src/rust/api/search.dart';
import 'package:zanzibarr/update/update_service.dart';

import 'l10n_test_helper.dart';

/// TV kumandası (D-pad) gezinti testleri.
///
/// Android TV'de DPAD_UP/DOWN/LEFT/RIGHT LogicalKeyboardKey.arrow* olarak,
/// DPAD_CENTER LogicalKeyboardKey.select olarak gelir (Flutter Android
/// embedding eşlemesi). Bu testler gerçek tuş olayları göndererek ekranların
/// kumandayla uçtan uca gezilebildiğini kanıtlar.

class _FakeProviderStore extends ProviderSettingsStore {
  ProviderSettings saved = const ProviderSettings(
    host: 'news.example.com',
    username: 'kullanici',
    password: 'TESTPASS123',
  );

  @override
  Future<ProviderSettings> load() async => saved;

  @override
  Future<void> save(ProviderSettings settings) async => saved = settings;
}

class _FakeIndexerStore extends IndexerSettingsStore {
  _FakeIndexerStore(this.settings);

  IndexerSettings settings;

  @override
  Future<IndexerSettings> load() async => settings;

  @override
  Future<void> save(IndexerSettings value) async => settings = value;
}

class _NullUpdateService extends UpdateService {
  @override
  Future<ReleaseInfo?> checkForUpdate() async => null;
}

class _MemoryPreferenceStorage implements PlayerPreferenceStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// Birincil odağın verilen bulucunun alt ağacında olup olmadığı.
/// (Odaktaki Focus öğesi, kartın metninin *atasıdır*; hedefin atalarında
/// odak öğesini ararız.)
bool _focusedWithin(Finder finder) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  final targets = finder.evaluate();
  if (targets.isEmpty) return false;
  Element? current = targets.first;
  while (current != null) {
    if (current == focusContext) return true;
    Element? parent;
    current.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    current = parent;
  }
  return false;
}

/// Odaktaki widget'ı okunabilir bir etikete çevirir (gezinti sırasını
/// doğrulamak için). Liste kaydığında oluşturulan widget'lar değiştiği için
/// metin alanları içerikleriyle, düğmeler etiketleriyle tanımlanır.
/// Türkçe etiketler l10nTestApp ile uyumludur.
String _focusLabel(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'HİÇBİRŞEY';
  W? ancestor<W extends Widget>() =>
      context.findAncestorWidgetOfExactType<W>();
  if (ancestor<DropdownButtonFormField<Locale>>() != null) return 'dil-seçici';
  if (ancestor<SegmentedButton<ThemeMode>>() != null) return 'tema';
  final textForm = ancestor<TextFormField>();
  if (textForm != null) return 'alan:${textForm.controller?.text ?? ''}';
  if (ancestor<TextField>() != null) return 'arama-alanı';
  final iconButton = ancestor<IconButton>();
  if (iconButton != null) return 'simge:${iconButton.tooltip}';
  final outlined = ancestor<OutlinedButton>();
  if (outlined != null) return 'dışçizgili:${_buttonText(tester, outlined)}';
  final filled = ancestor<FilledButton>();
  if (filled != null) return 'dolgun:${_buttonText(tester, filled)}';
  if (ancestor<InkWell>() != null) return 'kart';
  return 'diğer:${context.widget.runtimeType}';
}

String _buttonText(WidgetTester tester, Widget button) {
  final texts = find.descendant(
    of: find.byWidget(button),
    matching: find.byType(Text),
  );
  return tester.widgetList<Text>(texts).map((text) => text.data).join('|');
}

Future<void> _dpadDown(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
}

Future<void> _dpadUp(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await tester.pumpAndSettle();
}

void main() {
  group('Ayarlar ekranı D-pad gezintisi', () {
    testWidgets('açılışta odak dil seçicide başlar ve yukarı geri düğmesine çıkar', (
      tester,
    ) async {
      await tester.pumpWithL10n(
        SettingsScreen(
          store: _FakeProviderStore(),
          uiPreferences: turkishUiPreferences(),
          indexerStore: _FakeIndexerStore(const IndexerSettings()),
        ),
      );
      await tester.pumpAndSettle();

      expect(_focusLabel(tester), 'dil-seçici');

      await _dpadUp(tester);
      expect(_focusLabel(tester), startsWith('simge:'));
    });

    testWidgets('aşağı ok tüm kontrolleri erişilebilir kılar', (tester) async {
      await tester.pumpWithL10n(
        SettingsScreen(
          store: _FakeProviderStore(),
          uiPreferences: turkishUiPreferences(),
          indexerStore: _FakeIndexerStore(const IndexerSettings()),
        ),
      );
      await tester.pumpAndSettle();

      final stops = <String>[_focusLabel(tester)];
      final steps = <String>[stops.first];
      for (var i = 0; i < 16; i++) {
        await _dpadDown(tester);
        final label = _focusLabel(tester);
        steps.add(label);
        if (label != stops.last) stops.add(label);
      }

      // Kusursuz gezinti ölçütü: her kontrol yön tuşlarıyla erişilebilir.
      // Yan yana alan çiftinde (port/bağlantı) aşağı ok birine iner; diğeri
      // yatay okla alınır ve ayrı testte sınanır.
      final expected = <String>{
        'dil-seçici',
        'tema',
        'alan:news.example.com',
        'alan:kullanici',
        'alan:TESTPASS123',
        'dolgun:Güvenle kaydet',
        'dışçizgili:Bağlantıyı sına',
        "dolgun:Indexer'ı kaydet",
      };
      expect(
        stops.toSet(),
        containsAll(expected),
        reason: 'tüm kontroller D-pad ile erişilebilir olmalı: $stops',
      );
      // Yan yana alanlardan en az biri dikey gezintiyle alınmış olmalı.
      expect(
        stops.any((stop) => stop == 'alan:563' || stop == 'alan:10'),
        isTrue,
        reason: 'port/bağlantı sınırı çiftinden biri: $stops',
      );
      // İki boş indexer alanı (URL + API anahtarı) da dolaşılmış olmalı.
      // Ardışık aynı etiketler stops'ta tekilleştiği için ham adımlarda
      // sayılır: zincir "alan: → alan:" diye iniyor.
      expect(steps.where((step) => step == 'alan:').length, 2);
    });

    testWidgets('yan yana alanlar arasında sol/sağ ok gezer', (tester) async {
      await tester.pumpWithL10n(
        SettingsScreen(
          store: _FakeProviderStore(),
          uiPreferences: turkishUiPreferences(),
          indexerStore: _FakeIndexerStore(const IndexerSettings()),
        ),
      );
      await tester.pumpAndSettle();

      // Sunucu adresi alanına in (dil → tema → sunucu).
      for (var i = 0; i < 6 && _focusLabel(tester) != 'alan:news.example.com'; i++) {
        await _dpadDown(tester);
      }
      expect(_focusLabel(tester), 'alan:news.example.com');

      // Aşağı ok port/bağlantı çiftinden birine iner. Yatay çıkış imleç
      // kenarından yapılır: gezintiyle odaklanan alanda imleç sondadır, sol
      // ok önce imleci başa taşır, kenara varınca alandan çıkar.
      await _dpadDown(tester);
      final first = _focusLabel(tester);
      expect(
        first == 'alan:563' || first == 'alan:10',
        isTrue,
        reason: 'aşağı ok port veya bağlantı sınırına inmeli: $first',
      );
      final visited = <String>{first};
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        visited.add(_focusLabel(tester));
        if (visited.containsAll({'alan:563', 'alan:10'})) break;
      }
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        visited.add(_focusLabel(tester));
        if (visited.containsAll({'alan:563', 'alan:10'})) break;
      }
      expect(visited, containsAll({'alan:563', 'alan:10'}));
    });

    testWidgets('parola göz simgesi alandan sağ okla erişilebilir', (
      tester,
    ) async {
      await tester.pumpWithL10n(
        SettingsScreen(
          store: _FakeProviderStore(),
          uiPreferences: turkishUiPreferences(),
          indexerStore: _FakeIndexerStore(const IndexerSettings()),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 16 && _focusLabel(tester) != 'alan:TESTPASS123'; i++) {
        await _dpadDown(tester);
      }
      expect(_focusLabel(tester), 'alan:TESTPASS123');

      // Göz simgesi alanın içindedir; imleç metin sonundayken sağ ok ona
      // geçer (klasik TV metin alanı deseni).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusLabel(tester), 'simge:Parolayı göster');

      // DPAD_CENTER gizliliği açar/kapatır; sol ok alana geri döner.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(_focusLabel(tester), 'simge:Parolayı gizle');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusLabel(tester), 'alan:TESTPASS123');
    });

    testWidgets('DPAD_CENTER (select) odaktaki kaydet düğmesini etkinleştirir', (
      tester,
    ) async {
      final store = _FakeProviderStore();
      await tester.pumpWithL10n(
        SettingsScreen(
          store: store,
          uiPreferences: turkishUiPreferences(),
          indexerStore: _FakeIndexerStore(const IndexerSettings()),
        ),
      );
      await tester.pumpAndSettle();

      // "Güvenle kaydet" düğmesine inene kadar aşağı gez.
      for (var i = 0; i < 16 && _focusLabel(tester) != 'dolgun:Güvenle kaydet'; i++) {
        await _dpadDown(tester);
      }
      expect(_focusLabel(tester), 'dolgun:Güvenle kaydet');

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.text('Ayarlar güvenli depoya kaydedildi.'), findsOneWidget);
      expect(store.saved.host, 'news.example.com');
    });
  });

  group('Arama ekranı D-pad gezintisi', () {
    Future<SearchPageDto> fakeSearch(
      IndexerConfigDto config,
      String query,
      int limit,
      int offset,
    ) async => SearchPageDto(
      total: BigInt.from(1),
      items: [
        SearchItemDto(
          title: 'Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP',
          nzbUrl: 'https://indexer.example/getnzb/1',
          sizeBytes: BigInt.from(1000000),
          badges: const ['2160p'],
          mediaKind: 'movie',
        ),
      ],
    );

    testWidgets('odak arama alanında başlar, sonuç kartına inip select oynatır', (
      tester,
    ) async {
      String? downloadedUrl;
      await tester.pumpWithL10n(
        SearchScreen(
          store: _FakeIndexerStore(
            const IndexerSettings(
              baseUrl: 'https://indexer.example',
              apiKey: 'anahtar',
            ),
          ),
          searchFn: fakeSearch,
          downloadFn: (config, nzbUrl, suggestedName) async {
            downloadedUrl = nzbUrl;
            return '/tmp/indirilen.nzb';
          },
          onDownloaded: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(_focusLabel(tester), 'arama-alanı');

      await tester.enterText(find.byType(TextField), 'film');
      // Klavyeden "ara" eylemi aramayı başlatır.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP'), findsOneWidget);

      // Sonuçlar gelince odak ilk karta taşınır (IME odağı düşürür; D-pad
      // zinciri karttan devam eder).
      expect(_focusLabel(tester), 'kart');

      // DPAD_CENTER kartı etkinleştirir → NZB indirme başlar.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(downloadedUrl, 'https://indexer.example/getnzb/1');
    });
  });

  group('Ana ekran D-pad gezintisi', () {
    testWidgets('ilk kart odaklı başlar, aşağı ok ikinci karta iner', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nTestApp(
          HomeScreen(
            historyStore: PlaybackHistoryStore(
              storage: _MemoryPreferenceStorage(),
            ),
            updateService: _NullUpdateService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _focusedWithin(find.text('NZB seç ve oynat')),
        isTrue,
        reason: 'ilk odak NZB kartında olmalı',
      );

      await _dpadDown(tester);
      expect(_focusedWithin(find.text("Indexer'da ara")), isTrue);

      // İlk karttan yukarı çıkınca ayarlar dişlisine ulaşılmalı.
      await _dpadUp(tester);
      await _dpadUp(tester);
      expect(
        _focusedWithin(find.byIcon(Icons.settings_rounded)),
        isTrue,
        reason: 'yukarı ok ayarlar düğmesine çıkmalı',
      );
    });
  });
}
