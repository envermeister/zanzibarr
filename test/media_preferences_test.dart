import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:usenews/player/media_preferences.dart';

class _MemoryPreferenceStorage implements PlayerPreferenceStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> deletedKeys = <String>[];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    values.remove(key);
  }
}

void main() {
  group('MediaPreferencesStore namespace', () {
    test('uses deterministic FNV-1a 64-bit keys', () {
      const path = '/private/media/Example.Release.nzb';

      final first = MediaPreferencesStore.storageKeyFor(path);
      final second = MediaPreferencesStore.storageKeyFor(path);

      expect(first, second);
      expect(
        first,
        matches(RegExp(r'^usenews\.player_preferences\.[0-9a-f]{16}$')),
      );
      expect(first, isNot(contains(path)));
      expect(
        MediaPreferencesStore.storageKeyFor(''),
        'usenews.player_preferences.cbf29ce484222325',
      );
      expect(
        MediaPreferencesStore.storageKeyFor('a'),
        'usenews.player_preferences.af63dc4c8601ec8c',
      );
      expect(MediaPreferencesStore.storageKeyFor('$path.copy'), isNot(first));
    });
  });

  test('round-trips every preference through an injected storage', () async {
    final storage = _MemoryPreferenceStorage();
    final store = MediaPreferencesStore(storage: storage);
    const path = '/private/media/Round.Trip.nzb';
    final expected = MediaPreferences(
      crop: NormalizedCropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8),
      aspectRatio: 16 / 9,
      alignment: NormalizedVector2(x: -0.5, y: 0.75),
      pan: NormalizedVector2(x: 0.25, y: -0.4),
      seekStepSeconds: 15,
      periodicInfoInterval: const Duration(seconds: 2),
      videoPreset: 'cinema',
      audioPreset: 'dialogue',
      upscalePreset: 'quality',
      subtitleScale: 1.4,
      subtitlePosition: 88,
      subtitleDelaySeconds: -0.35,
      audioDelaySeconds: 0.125,
    );

    await store.save(path, expected);
    final actual = await store.load(path);

    expect(actual, expected);
  });

  test('never persists the raw NZB path in the key or JSON value', () async {
    final storage = _MemoryPreferenceStorage();
    final store = MediaPreferencesStore(storage: storage);
    const path = '/Users/person/Secret.Release.Name.2160p.nzb';

    await store.save(path, MediaPreferences(videoPreset: 'cinema'));

    expect(storage.values, hasLength(1));
    final entry = storage.values.entries.single;
    expect(entry.key, isNot(contains(path)));
    expect(entry.value, isNot(contains(path)));
    expect(jsonDecode(entry.value), isA<Map<String, dynamic>>());
  });

  group('safe decoding', () {
    test('returns defaults for corrupt and deprecated data', () async {
      final storage = _MemoryPreferenceStorage();
      final store = MediaPreferencesStore(storage: storage);
      const corruptPath = '/media/corrupt.nzb';
      const deprecatedPath = '/media/deprecated.nzb';
      storage.values[MediaPreferencesStore.storageKeyFor(corruptPath)] =
          '{not-json';
      storage.values[MediaPreferencesStore.storageKeyFor(
        deprecatedPath,
      )] = jsonEncode(<String, Object>{
        'schemaVersion': 0,
        'videoPreset': 'legacy',
      });

      expect(await store.load(corruptPath), MediaPreferences.defaults());
      expect(await store.load(deprecatedPath), MediaPreferences.defaults());
    });

    test('clamps invalid values and replaces invalid shapes', () {
      final preferences = MediaPreferences(
        crop: NormalizedCropRect(left: 0.8, top: 0.9, right: 0.2, bottom: 0.1),
        aspectRatio: double.nan,
        alignment: NormalizedVector2(x: -4, y: 4),
        pan: NormalizedVector2(x: 2, y: -2),
        seekStepSeconds: 0,
        periodicInfoInterval: const Duration(milliseconds: 1),
        videoPreset: 'INVALID LABEL',
        audioPreset: '',
        upscalePreset: 'x' * 40,
        subtitleScale: -3,
        subtitlePosition: 500,
        subtitleDelaySeconds: -1000,
        audioDelaySeconds: 1000,
      );

      expect(preferences.crop, NormalizedCropRect.fullFrame);
      expect(preferences.aspectRatio, isNull);
      expect(preferences.alignment, NormalizedVector2(x: -1, y: 1));
      expect(preferences.pan, NormalizedVector2(x: 1, y: -1));
      expect(preferences.seekStepSeconds, 1);
      expect(
        preferences.periodicInfoInterval,
        MediaPreferences.minimumPeriodicInfoInterval,
      );
      expect(preferences.videoPreset, MediaPreferences.defaultVideoPreset);
      expect(preferences.audioPreset, MediaPreferences.defaultAudioPreset);
      expect(preferences.upscalePreset, MediaPreferences.defaultUpscalePreset);
      expect(preferences.subtitleScale, 0);
      expect(preferences.subtitlePosition, 150);
      expect(preferences.subtitleDelaySeconds, -600);
      expect(preferences.audioDelaySeconds, 600);
    });
  });

  test('clear deletes only the hashed media key', () async {
    final storage = _MemoryPreferenceStorage();
    final store = MediaPreferencesStore(storage: storage);
    const path = '/media/to-clear.nzb';
    const otherPath = '/media/keep.nzb';
    await store.save(path, MediaPreferences(videoPreset: 'cinema'));
    await store.save(otherPath, MediaPreferences(videoPreset: 'natural'));

    await store.clear(path);

    final expectedKey = MediaPreferencesStore.storageKeyFor(path);
    expect(storage.deletedKeys, <String>[expectedKey]);
    expect(storage.values.containsKey(expectedKey), isFalse);
    expect(
      storage.values.containsKey(
        MediaPreferencesStore.storageKeyFor(otherPath),
      ),
      isTrue,
    );
    expect(await store.load(path), MediaPreferences.defaults());
  });
}
