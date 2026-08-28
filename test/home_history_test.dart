import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/player/media_preferences.dart';
import 'package:zanzibarr/player/playback_history.dart';

import 'l10n_test_helper.dart';

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

void main() {
  testWidgets('ana ekran izleme geçmişi bölümünü gösterir ve siler', (
    tester,
  ) async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);
    await store.save(
      const PlaybackHistoryEntry(
        nzbPath: '/media/Ornek.Film.2024.nzb',
        title: 'Ornek.Film.2024',
        positionSeconds: 600,
        durationSeconds: 3600,
        updatedAtMs: 1,
      ),
    );

    await tester.pumpWidget(
      l10nTestApp(HomeScreen(historyStore: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('İzlemeye devam et'), findsOneWidget);
    expect(find.text('Ornek.Film.2024'), findsOneWidget);
    // 3600 - 600 = 3000 sn = 50:00 kalan süre.
    expect(find.textContaining('50:00'), findsWidgets);

    await tester.tap(find.byTooltip('Geçmişten kaldır'));
    await tester.pumpAndSettle();

    expect(find.text('İzlemeye devam et'), findsNothing);
    expect(await store.load(), isEmpty);
  });

  testWidgets('geçmiş boşken bölüm gösterilmez', (tester) async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);

    await tester.pumpWidget(
      l10nTestApp(HomeScreen(historyStore: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('İzlemeye devam et'), findsNothing);
    expect(find.text('NZB seç ve oynat'), findsOneWidget);
  });
}
