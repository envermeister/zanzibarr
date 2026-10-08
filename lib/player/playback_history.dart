import 'dart:convert';

import 'media_preferences.dart';

/// Bir medyanın izleme geçmişi kaydı: son konum ve toplam süre.
///
/// Kayıtlar [PlaybackHistoryStore] içinde JSON listesi olarak saklanır.
/// Kaydın kimliği `(nzbPath, entryKey)` çiftidir: çok parçalı (sezon
/// paketi gibi) NZB'lerde her bölüm kendi kaydını taşır; tek adaylı
/// NZB'lerde `entryKey` null'dır (eski kayıtlarla uyumlu).
class PlaybackHistoryEntry {
  const PlaybackHistoryEntry({
    required this.nzbPath,
    required this.title,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAtMs,
    this.entryKey,
  });

  /// Geçmiş kaydının kimliği: NZB'nin dosya yolu (yerel depoda kalır).
  final String nzbPath;

  /// Çok parçalı NZB'de oynatılan bölümün seçici anahtarı (ör.
  /// `rar:show.s01e02`); tek adaylı NZB'lerde null. Aynı NZB'nin
  /// bölümleri birbirinin konumunu ezmesin diye kimliğin parçasıdır.
  final String? entryKey;

  /// Kartlarda gösterilen ad (video dosya adı).
  final String title;

  final double positionSeconds;
  final double durationSeconds;
  final int updatedAtMs;

  /// İzleme sona erdiyse (son ~%3) kayıt tutulmaz; baştan başlatılır.
  bool get isCompleted =>
      durationSeconds > 0 && positionSeconds >= durationSeconds * 0.97;

  /// 0–1 arası izleme ilerlemesi; süre bilinmiyorsa 0.
  double get progress => durationSeconds > 0
      ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
      : 0;

  Duration get position =>
      Duration(milliseconds: (positionSeconds * 1000).round());

  Map<String, Object> toJson() => <String, Object>{
    'nzbPath': nzbPath,
    'entryKey': ?entryKey,
    'title': title,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'updatedAtMs': updatedAtMs,
  };

  static PlaybackHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['nzbPath'];
    final title = value['title'];
    final position = value['positionSeconds'];
    final duration = value['durationSeconds'];
    final updatedAt = value['updatedAtMs'];
    if (path is! String || path.isEmpty) return null;
    if (title is! String) return null;
    if (position is! num || duration is! num || updatedAt is! num) {
      return null;
    }
    final entryKey = value['entryKey'];
    return PlaybackHistoryEntry(
      nzbPath: path,
      entryKey: entryKey is String && entryKey.isNotEmpty ? entryKey : null,
      title: title,
      positionSeconds: position.toDouble(),
      durationSeconds: duration.toDouble(),
      updatedAtMs: updatedAt.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackHistoryEntry &&
      nzbPath == other.nzbPath &&
      entryKey == other.entryKey &&
      title == other.title &&
      positionSeconds == other.positionSeconds &&
      durationSeconds == other.durationSeconds &&
      updatedAtMs == other.updatedAtMs;

  @override
  int get hashCode => Object.hash(
    nzbPath,
    entryKey,
    title,
    positionSeconds,
    durationSeconds,
    updatedAtMs,
  );
}

/// İzleme geçmişini güvenli depoda (şifreli) tutar; en güncel kayıt başta
/// olacak şekilde sıralıdır ve liste [_maxEntries] ile sınırlanır.
class PlaybackHistoryStore {
  PlaybackHistoryStore({PlayerPreferenceStorage? storage})
    : _storage = storage ?? FlutterSecurePlayerPreferenceStorage();

  final PlayerPreferenceStorage _storage;

  static const storageKey = 'zanzibarr.playback_history.v1';
  static const _maxEntries = 25;

  Future<List<PlaybackHistoryEntry>> load() async {
    final encoded = await _storage.read(storageKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const [];
      final list = decoded['entries'];
      if (list is! List) return const [];
      return [for (final item in list) ?PlaybackHistoryEntry.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }

  Future<PlaybackHistoryEntry?> entryFor(
    String nzbPath, {
    String? entryKey,
  }) async {
    final entries = await load();
    for (final entry in entries) {
      if (entry.nzbPath == nzbPath && entry.entryKey == entryKey) return entry;
    }
    return null;
  }

  /// Kaydı ekler veya günceller; tamamlanmış içerik listeden düşer.
  ///
  /// Bölüm anahtarlı ilk kayıt, aynı NZB'nin anahtarsız (eski sürümden
  /// kalan, tüm paket için tek) kaydını da süpürür — yoksa ana ekranda
  /// hedefi artık bulunamayan hayalet bir kart kalırdı.
  Future<void> save(PlaybackHistoryEntry entry) async {
    final entries = List.of(await load());
    entries.removeWhere(
      (e) =>
          e.nzbPath == entry.nzbPath &&
          (e.entryKey == entry.entryKey ||
              (entry.entryKey != null && e.entryKey == null)),
    );
    if (!entry.isCompleted) entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _storage.write(
      storageKey,
      jsonEncode(<String, Object>{
        'version': 1,
        'entries': [for (final e in entries) e.toJson()],
      }),
    );
  }

  Future<void> remove(String nzbPath, {String? entryKey}) async {
    final entries = List.of(await load());
    entries.removeWhere(
      (e) => e.nzbPath == nzbPath && e.entryKey == entryKey,
    );
    await _storage.write(
      storageKey,
      jsonEncode(<String, Object>{
        'version': 1,
        'entries': [for (final e in entries) e.toJson()],
      }),
    );
  }
}
