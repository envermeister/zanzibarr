import 'dart:async';

import 'package:dart_cast/dart_cast.dart';

/// UI katmanının ihtiyaç duyduğu dart_cast tipleri buradan dışa açılır;
/// ekranlar paketi doğrudan içe aktarmaz.
export 'package:dart_cast/dart_cast.dart'
    show CastDevice, CastProtocol, CastSession, SessionState;

/// Motordan gelen `cast_url` zaten LAN'dan erişilebilen, seek destekli bir
/// Range uçudur; dart_cast'in MediaProxy'si (harici servislere başlık
/// enjeksiyonu için tasarlanmış) bizde gereksiz bir çift atlama olurdu.
/// Bu dönüştürücü URL'yi olduğu gibi alıcıya verir — veri yolu Rust'ta kalır,
/// dart_cast yalnızca keşif + kumanda için kullanılır.
class _DirectUrlTransformer implements MediaTransformer {
  const _DirectUrlTransformer();

  @override
  Future<TransformedMedia> transform(CastMedia media, MediaProxy proxy) async {
    return TransformedMedia(proxyUrl: media.url, effectiveType: media.type);
  }
}

/// Dosya adından cast medya türü. Alıcılar (özellikle Chromecast Default
/// Media Receiver) kapsayıcıyı uzantıdan ipucu alır.
CastMediaType castMediaTypeFor(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'mp4':
    case 'm4v':
    case 'mov':
      return CastMediaType.mp4;
    case 'ts':
    case 'm2ts':
    case 'mts':
      return CastMediaType.mpegTs;
    default:
      return CastMediaType.mkv;
  }
}

/// Player ekranının cast servisinden beklediği asgari sözleşme. Testlerde
/// sahte uygulama enjekte edilebilsin diye dart_cast tiplerinden arındırılmış
/// değil, dart_cast tiplerini taşıyan dar bir arayüzdür (CastDevice seçimi
/// kullanıcıya sorulduğundan UI katmanının tipe ihtiyacı var).
abstract class CastController {
  CastSession? get activeSession;
  Stream<List<CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  });
  void stopDiscovery();
  Future<CastSession> startCasting(
    CastDevice device, {
    required String url,
    required String title,
    Duration? startPosition,
    Duration? duration,
  });
  Future<void> stopCasting();

  Future<void> dispose();
}

/// Uygulama seviyesi cast servisi: dart_cast'i zanzibarr'ın ihtiyaçlarına
/// indirger. Chromecast birincil hedef; AirPlay best-effort (alıcı desteği
/// donanıma bağlı). DLNA bu turda kapsam dışı.
class AppCastService implements CastController {
  AppCastService()
    : _service = CastService(
        discoveryProviders: [
          ChromecastDiscoveryProvider(),
          AirPlayDiscoveryProvider(),
        ],
        sessionFactory: _createSession,
      );

  final CastService _service;

  static CastSession _createSession(CastDevice device) {
    switch (device.protocol) {
      case CastProtocol.chromecast:
        return ChromecastSession(
          device: device,
          mediaTransformer: const _DirectUrlTransformer(),
        );
      case CastProtocol.airplay:
        return AirPlaySession(
          device,
          mediaTransformer: const _DirectUrlTransformer(),
        );
      case CastProtocol.dlna:
        throw UnsupportedError('DLNA is not supported yet');
    }
  }

  /// Aktif cast oturumu; bağlı cihaz yoksa null.
  @override
  CastSession? get activeSession => _service.activeSession;

  /// LAN'daki cast cihazlarını keşfeder. Yayın, timeout sonunda kapanır.
  @override
  Stream<List<CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _service.startDiscovery(
      protocols: {CastProtocol.chromecast, CastProtocol.airplay},
      timeout: timeout,
    );
  }

  @override
  void stopDiscovery() => _service.stopDiscovery();

  /// Cihaza bağlanır ve verilen URL'yi yükleyip oynatmaya başlar.
  @override
  Future<CastSession> startCasting(
    CastDevice device, {
    required String url,
    required String title,
    Duration? startPosition,
    Duration? duration,
  }) async {
    final session = await _service.connect(device);
    await session.loadMedia(
      CastMedia(
        url: url,
        type: castMediaTypeFor(title),
        title: title,
        startPosition: startPosition,
        duration: duration,
      ),
    );
    return session;
  }

  @override
  Future<void> stopCasting() async {
    final session = _service.activeSession;
    if (session == null) {
      return;
    }
    try {
      await session.stop();
    } finally {
      await session.disconnect();
    }
  }

  @override
  Future<void> dispose() => _service.dispose();
}
