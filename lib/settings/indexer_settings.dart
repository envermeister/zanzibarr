import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Newznab indexer ayarları.
///
/// API anahtarı yalnızca OS secure storage'da (Keychain/Keystore) tutulur;
/// hiçbir sır kaynak koda veya düz metin dosyaya yazılmaz.
class IndexerSettings {
  const IndexerSettings({this.baseUrl = '', this.apiKey = ''});

  /// Indexer'ın kök adresi (ör. `https://indexer.example`; sonunda `/api`
  /// olabilir ya da olmayabilir, Rust tarafı normalize eder).
  final String baseUrl;

  /// Newznab API anahtarı.
  final String apiKey;

  /// İki alan da doluysa indexer kullanılabilir kabul edilir; boş URL
  /// "indexer kapalı" demektir.
  bool get isComplete => baseUrl.isNotEmpty && apiKey.isNotEmpty;
}

/// [IndexerSettings] için OS secure storage üzerinde kalıcı depo.
class IndexerSettingsStore {
  IndexerSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kBaseUrl = 'indexer.baseUrl';
  static const _kApiKey = 'indexer.apiKey';

  Future<IndexerSettings> load() async {
    const defaults = IndexerSettings();
    return IndexerSettings(
      baseUrl: await _storage.read(key: _kBaseUrl) ?? defaults.baseUrl,
      apiKey: await _storage.read(key: _kApiKey) ?? defaults.apiKey,
    );
  }

  Future<void> save(IndexerSettings settings) async {
    await _storage.write(key: _kBaseUrl, value: settings.baseUrl);
    await _storage.write(key: _kApiKey, value: settings.apiKey);
  }

  Future<void> clear() async {
    for (final key in [_kBaseUrl, _kApiKey]) {
      await _storage.delete(key: key);
    }
  }
}
