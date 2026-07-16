import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// NNTP sağlayıcı ayarları.
///
/// Kimlik bilgileri yalnızca OS secure storage'da (Keychain/Keystore) tutulur;
/// hiçbir sır kaynak koda veya düz metin dosyaya yazılmaz.
class ProviderSettings {
  const ProviderSettings({
    this.host = '',
    this.port = 563,
    this.username = '',
    this.password = '',
    this.maxConnections = 10,
  });

  /// NNTP sunucu adresi (ör. sağlayıcının TLS host'u).
  final String host;

  /// NNTPS portu; 563 = TLS.
  final int port;

  final String username;
  final String password;

  /// Sağlayıcının izin verdiği eşzamanlı bağlantı sayısı.
  /// Faz 1'deki bağlantı havuzunun boyutu buradan gelir.
  final int maxConnections;

  bool get isComplete =>
      host.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

/// [ProviderSettings] için OS secure storage üzerinde kalıcı depo.
class ProviderSettingsStore {
  ProviderSettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kHost = 'provider.host';
  static const _kPort = 'provider.port';
  static const _kUsername = 'provider.username';
  static const _kPassword = 'provider.password';
  static const _kMaxConnections = 'provider.maxConnections';

  Future<ProviderSettings> load() async {
    const defaults = ProviderSettings();
    return ProviderSettings(
      host: await _storage.read(key: _kHost) ?? defaults.host,
      port: int.tryParse(await _storage.read(key: _kPort) ?? '') ??
          defaults.port,
      username: await _storage.read(key: _kUsername) ?? defaults.username,
      password: await _storage.read(key: _kPassword) ?? defaults.password,
      maxConnections:
          int.tryParse(await _storage.read(key: _kMaxConnections) ?? '') ??
              defaults.maxConnections,
    );
  }

  Future<void> save(ProviderSettings settings) async {
    await _storage.write(key: _kHost, value: settings.host);
    await _storage.write(key: _kPort, value: settings.port.toString());
    await _storage.write(key: _kUsername, value: settings.username);
    await _storage.write(key: _kPassword, value: settings.password);
    await _storage.write(
      key: _kMaxConnections,
      value: settings.maxConnections.toString(),
    );
  }

  Future<void> clear() async {
    for (final key in [_kHost, _kPort, _kUsername, _kPassword, _kMaxConnections]) {
      await _storage.delete(key: key);
    }
  }
}
