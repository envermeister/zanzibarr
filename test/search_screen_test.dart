import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/search/search_screen.dart';
import 'package:zanzibarr/settings/indexer_settings.dart';
import 'package:zanzibarr/src/rust/api/search.dart';

import 'l10n_test_helper.dart';

/// Gerçek secure storage yerine sabit ayar döndüren sahte depo.
class _FakeIndexerStore extends IndexerSettingsStore {
  _FakeIndexerStore(this.settings);

  final IndexerSettings settings;

  @override
  Future<IndexerSettings> load() async => settings;
}

final _completeStore = _FakeIndexerStore(
  const IndexerSettings(baseUrl: 'https://indexer.example', apiKey: 'anahtar'),
);

SearchItemDto _movieItem() => SearchItemDto(
  title: 'Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP',
  nzbUrl: 'https://indexer.example/getnzb/1',
  sizeBytes: BigInt.from(6979321856), // 6,5 GB
  publishedEpochSecs:
      DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch ~/
      1000,
  badges: const ['2160p', 'HEVC', 'DV'],
  mediaKind: 'movie',
  year: 2024,
);

SearchItemDto _tvItem() => SearchItemDto(
  title: 'Bir.Dizi.S01E02.1080p.WEB-GRP',
  nzbUrl: 'https://indexer.example/getnzb/2',
  sizeBytes: BigInt.from(734003200), // 700 MB
  badges: const ['1080p'],
  mediaKind: 'tv',
  season: 1,
  episode: 2,
);

/// Sabit iki sonuç döndüren sahte arama.
Future<SearchPageDto> _fakeSearch(
  IndexerConfigDto config,
  String query,
  int limit,
  int offset,
) async => SearchPageDto(total: BigInt.from(2), items: [_movieItem(), _tvItem()]);

Future<void> _enterQueryAndSearch(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.search_rounded));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Arama sonuçları rozet, boyut, yaş ve toplam ile listeleniyor', (
    tester,
  ) async {
    await tester.pumpWithL10n(
      SearchScreen(store: _completeStore, searchFn: _fakeSearch),
    );
    await tester.pumpAndSettle();

    // Henüz arama yapılmadan ipucu görünür.
    expect(
      find.text("Indexer'ınızda aramak için bir sürüm adı yazın."),
      findsOneWidget,
    );

    await _enterQueryAndSearch(tester, 'film');

    expect(
      find.text('Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP'),
      findsOneWidget,
    );
    expect(find.text('Bir.Dizi.S01E02.1080p.WEB-GRP'), findsOneWidget);
    expect(find.text('2160p'), findsOneWidget);
    expect(find.text('HEVC'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('6.5 GB'), findsOneWidget);
    expect(find.text('700 MB'), findsOneWidget);
    expect(find.text('10 g'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2 sonuç'), findsOneWidget);
  });

  testWidgets('Öğeye dokununca downloadFn çağrılır ve onDownloaded tetiklenir', (
    tester,
  ) async {
    IndexerConfigDto? usedConfig;
    String? usedUrl;
    String? usedName;
    String? downloadedPath;
    await tester.pumpWithL10n(
      SearchScreen(
        store: _completeStore,
        searchFn: _fakeSearch,
        downloadFn: (config, nzbUrl, suggestedName) async {
          usedConfig = config;
          usedUrl = nzbUrl;
          usedName = suggestedName;
          return '/tmp/indirilen.nzb';
        },
        onDownloaded: (path) => downloadedPath = path,
      ),
    );
    await tester.pumpAndSettle();
    await _enterQueryAndSearch(tester, 'film');

    await tester.tap(find.text('Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP'));
    await tester.pumpAndSettle();

    expect(usedConfig?.baseUrl, 'https://indexer.example');
    expect(usedConfig?.apiKey, 'anahtar');
    expect(usedUrl, 'https://indexer.example/getnzb/1');
    expect(usedName, 'Bir.Film.2024.2160p.WEB-DL.DV.HEVC-GRP');
    expect(downloadedPath, '/tmp/indirilen.nzb');
  });

  testWidgets('İndirme hatası SnackBar ile gösterilir', (tester) async {
    await tester.pumpWithL10n(
      SearchScreen(
        store: _completeStore,
        searchFn: _fakeSearch,
        downloadFn: (config, nzbUrl, suggestedName) async =>
            throw Exception('disk dolu'),
        onDownloaded: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await _enterQueryAndSearch(tester, 'film');

    await tester.tap(find.text('Bir.Dizi.S01E02.1080p.WEB-GRP'));
    await tester.pumpAndSettle();

    expect(
      find.text('NZB indirilemedi: Exception: disk dolu'),
      findsOneWidget,
    );
  });

  testWidgets('Arama hatası yeniden deneme görünümüne düşer', (tester) async {
    await tester.pumpWithL10n(
      SearchScreen(
        store: _completeStore,
        searchFn: (config, query, limit, offset) async =>
            throw Exception('Indexer yanıt vermiyor'),
      ),
    );
    await tester.pumpAndSettle();
    await _enterQueryAndSearch(tester, 'film');

    expect(find.textContaining('Indexer yanıt vermiyor'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
  });

  testWidgets('Sonuç yoksa bilgi görünümü gösterilir', (tester) async {
    await tester.pumpWithL10n(
      SearchScreen(
        store: _completeStore,
        searchFn: (config, query, limit, offset) async =>
            SearchPageDto(total: BigInt.zero, items: const []),
      ),
    );
    await tester.pumpAndSettle();
    await _enterQueryAndSearch(tester, 'olmayan');

    expect(find.text('Sonuç bulunamadı'), findsOneWidget);
  });

  testWidgets('Indexer ayarları eksikse ayarlara yönlendirme gösterilir', (
    tester,
  ) async {
    await tester.pumpWithL10n(
      SearchScreen(store: _FakeIndexerStore(const IndexerSettings())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Önce ayarlardan indexer URL'sini ve API anahtarını girin."),
      findsOneWidget,
    );
    expect(find.text('Ayarlara git'), findsOneWidget);
  });
}
