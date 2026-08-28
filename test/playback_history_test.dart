import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/media_preferences.dart';
import 'package:zanzibarr/player/playback_history.dart';

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
  PlaybackHistoryEntry entry(
    String path, {
    double position = 120,
    double duration = 6000,
    int updatedAt = 1000,
  }) => PlaybackHistoryEntry(
    nzbPath: path,
    title: path.split('/').last,
    positionSeconds: position,
    durationSeconds: duration,
    updatedAtMs: updatedAt,
  );

  test('kayıt eklenip okunabiliyor (round-trip)', () async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);

    await store.save(entry('/media/film.nzb', position: 321.5));

    final entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.nzbPath, '/media/film.nzb');
    expect(entries.single.positionSeconds, 321.5);
    expect(entries.single.progress, closeTo(321.5 / 6000, 0.0001));
  });

  test(
    'aynı yol yeniden kaydedilince güncellenir, liste kabarık kalmaz',
    () async {
      final storage = _MemoryPreferenceStorage();
      final store = PlaybackHistoryStore(storage: storage);

      await store.save(entry('/media/film.nzb', position: 100, updatedAt: 1));
      await store.save(entry('/media/film.nzb', position: 250, updatedAt: 2));
      await store.save(entry('/media/diger.nzb', position: 50, updatedAt: 3));

      final entries = await store.load();
      expect(entries, hasLength(2));
      // En güncel kayıt başta.
      expect(entries.first.nzbPath, '/media/diger.nzb');
      expect(entries.last.positionSeconds, 250);
    },
  );

  test('izleme sona erdiyse kayıt tutulmaz', () async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);

    await store.save(entry('/media/film.nzb', position: 5900, duration: 6000));

    expect(await store.load(), isEmpty);
  });

  test('liste en güncel 25 kayıtla sınırlı', () async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);

    for (var i = 0; i < 30; i++) {
      await store.save(entry('/media/film-$i.nzb', updatedAt: i));
    }

    final entries = await store.load();
    expect(entries, hasLength(25));
    expect(entries.first.nzbPath, '/media/film-29.nzb');
    expect(entries.last.nzbPath, '/media/film-5.nzb');
  });

  test('bozuk JSON boş listeye düşer', () async {
    final storage = _MemoryPreferenceStorage()
      ..values[PlaybackHistoryStore.storageKey] = '{bozuk';
    final store = PlaybackHistoryStore(storage: storage);

    expect(await store.load(), isEmpty);
  });

  test('remove yalnız hedef kaydı siler', () async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);

    await store.save(entry('/media/a.nzb', updatedAt: 1));
    await store.save(entry('/media/b.nzb', updatedAt: 2));
    await store.remove('/media/a.nzb');

    final entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.nzbPath, '/media/b.nzb');
  });

  test('entryFor yolu bulur, yoksa null döner', () async {
    final storage = _MemoryPreferenceStorage();
    final store = PlaybackHistoryStore(storage: storage);
    await store.save(entry('/media/film.nzb'));

    expect((await store.entryFor('/media/film.nzb'))?.positionSeconds, 120);
    expect(await store.entryFor('/media/yok.nzb'), isNull);
  });
}
