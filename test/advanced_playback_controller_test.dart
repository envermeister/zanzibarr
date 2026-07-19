import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/advanced_playback_controller.dart';

class _FakeBackend implements PlaybackBackend {
  final calls = <String>[];
  final properties = <String, String>{};
  final readbackOverrides = <String, String>{};
  final unsupportedProperties = <String>{};

  @override
  Future<void> command(List<String> arguments) async {
    calls.add('command:${arguments.join(' ')}');
  }

  @override
  Future<String> getProperty(String name) async {
    calls.add('get:$name');
    return readbackOverrides[name] ?? properties[name] ?? '';
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> setProperty(String name, String value) async {
    calls.add('set:$name=$value');
    if (unsupportedProperties.contains(name)) {
      throw UnsupportedError('$name bu derlemede yok');
    }
    properties[name] = value;
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate:$rate');
  }
}

void main() {
  test('SDR profili HDR içeriği bt.709 hedefine ton eşleyerek doğrulanır', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setHdrEnabled(false);

    expect(controller.hdrEnabled, isFalse);
    expect(backend.calls, [
      'get:tone-mapping',
      'get:hdr-compute-peak',
      'get:gamut-mapping-mode',
      'get:target-trc',
      'get:target-prim',
      'set:tone-mapping=bt.2390',
      'set:hdr-compute-peak=yes',
      'set:gamut-mapping-mode=desaturate',
      'set:target-trc=bt.1886',
      'set:target-prim=bt.709',
      'get:tone-mapping',
      'get:hdr-compute-peak',
      'get:gamut-mapping-mode',
      'get:target-trc',
      'get:target-prim',
      'set:target-colorspace-hint=no',
    ]);
  });

  test(
    'Usenet HTTP profili uzun beklemeyi tolere edip disk cache kapatıyor',
    () async {
      // Test ortamında defaultTargetPlatform Android döner; bu test taşıma
      // profilini platform yan etkilerinden bağımsız doğrular.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final backend = _FakeBackend();
      final controller = AdvancedPlaybackController(backend);

      await controller.applyStreamingTransportProfile();

      expect(backend.calls, [
        'get:network-timeout',
        'get:cache',
        'get:cache-on-disk',
        'set:network-timeout=60',
        'set:cache=yes',
        'set:cache-on-disk=no',
        'get:network-timeout',
        'get:cache',
        'get:cache-on-disk',
      ]);
    },
  );

  test('libmpv sürümü native property üzerinden okunuyor', () async {
    final backend = _FakeBackend()
      ..readbackOverrides['mpv-version'] = 'mpv 0.41.0';
    final controller = AdvancedPlaybackController(backend);

    expect(await controller.engineVersion(), 'mpv 0.41.0');
    expect(backend.calls, ['get:mpv-version']);
  });

  test('oynatma hızı 0.5–16 aralığıyla ve menü listesiyle sınırlı', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setRate(0.5);
    await controller.setRate(16.0);

    expect(controller.rate, 16.0);
    expect(backend.calls, ['rate:0.5', 'rate:16.0']);
    expect(AdvancedPlaybackController.supportedRates, [
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      2.0,
      4.0,
      8.0,
      16.0,
    ]);
    await expectLater(controller.setRate(0.49), throwsRangeError);
    await expectLater(controller.setRate(16.01), throwsRangeError);
    await expectLater(controller.setRate(double.nan), throwsRangeError);
  });

  test(
    'relative seek mpv flaglerini ve mikrosaniyeyi kayıpsız serileştirir',
    () async {
      final backend = _FakeBackend();
      final controller = AdvancedPlaybackController(backend);

      await controller.seekRelative(const Duration(milliseconds: 1250));
      await controller.seekRelative(
        const Duration(milliseconds: -2250),
        exact: true,
      );

      expect(backend.calls, [
        'command:seek 1.250000 relative',
        'command:seek -2.250000 relative+exact',
      ]);
    },
  );

  test('relative seek mutlak en az bir saniye olmalı', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await expectLater(controller.seekRelative(Duration.zero), throwsRangeError);
    await expectLater(
      controller.seekRelative(const Duration(milliseconds: 999)),
      throwsRangeError,
    );
    await expectLater(
      controller.seekRelative(const Duration(milliseconds: -999)),
      throwsRangeError,
    );

    await controller.seekRelative(const Duration(seconds: 1));
    await controller.seekRelative(const Duration(seconds: -1));
    expect(backend.calls, [
      'command:seek 1.000000 relative',
      'command:seek -1.000000 relative',
    ]);
  });

  test('yeni A noktası eski B noktasını temizliyor', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setLoopStart(const Duration(seconds: 10));
    await controller.setLoopEnd(const Duration(seconds: 20));
    await controller.setLoopStart(const Duration(seconds: 30));

    expect(controller.loopStart, const Duration(seconds: 30));
    expect(controller.loopEnd, isNull);
    expect(backend.calls, [
      'set:ab-loop-b=no',
      'set:ab-loop-a=10.000000',
      'set:ab-loop-b=20.000000',
      'set:ab-loop-b=no',
      'set:ab-loop-a=30.000000',
    ]);
  });

  test('B noktası A noktasından sonra olmalı', () async {
    final controller = AdvancedPlaybackController(_FakeBackend());
    await expectLater(
      controller.setLoopEnd(const Duration(seconds: 2)),
      throwsStateError,
    );
    await controller.setLoopStart(const Duration(seconds: 5));
    await expectLater(
      controller.setLoopEnd(const Duration(seconds: 5)),
      throwsArgumentError,
    );
  });

  test('kare adımları önce duraklatıp tek libmpv komutu gönderiyor', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.stepBackward();
    await controller.stepForward();

    expect(backend.calls, [
      'pause',
      'command:frame-back-step',
      'pause',
      'command:frame-step',
    ]);
  });

  test('zoom 1–4x sınırında ve libmpv log2 ölçeğine çevriliyor', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    expect(await controller.setZoom(0.5), 1.0);
    expect(await controller.setZoom(2.0), 2.0);
    expect(await controller.setZoom(8.0), 4.0);

    expect(controller.zoom, 4.0);
    expect(
      AdvancedPlaybackController.mpvZoomForScale(2.0),
      closeTo(math.log(2) / math.ln2, 0.000001),
    );
    expect(backend.calls, [
      'set:video-zoom=0.000000',
      'set:video-zoom=1.000000',
      'set:video-zoom=2.000000',
    ]);
    await expectLater(controller.setZoom(double.infinity), throwsRangeError);
  });

  test(
    'altyazı ölçeği, konumu ve senkronu güvenli aralıklarda tutuluyor',
    () async {
      final backend = _FakeBackend();
      final controller = AdvancedPlaybackController(backend);

      await controller.setSubtitleScale(1.25);
      await controller.setSubtitlePosition(72.5);
      await controller.setSubtitleDelay(const Duration(milliseconds: -1500));

      expect(controller.subtitleScale, 1.25);
      expect(controller.subtitlePosition, 72.5);
      expect(controller.subtitleDelay, const Duration(milliseconds: -1500));
      expect(backend.calls, [
        'set:sub-scale=1.250000',
        'set:sub-pos=73',
        'set:sub-delay=-1.500000',
      ]);

      await expectLater(controller.setSubtitleScale(0.49), throwsRangeError);
      await expectLater(controller.setSubtitleScale(3.01), throwsRangeError);
      await expectLater(
        controller.setSubtitleScale(double.nan),
        throwsRangeError,
      );
      await expectLater(
        controller.setSubtitlePosition(-0.01),
        throwsRangeError,
      );
      await expectLater(
        controller.setSubtitlePosition(100.01),
        throwsRangeError,
      );
      await expectLater(
        controller.setSubtitleDelay(const Duration(seconds: 61)),
        throwsRangeError,
      );
      await expectLater(
        controller.setSubtitleDelay(const Duration(seconds: -61)),
        throwsRangeError,
      );
    },
  );

  test('sub-pos mpv tarafına her zaman tamsayı metniyle gönderilir', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    // Başlangıçta kayıtlı tercih uygulanırken varsayılan 100.0 gönderiliyordu;
    // mpv 0.36 "100.000000" biçimini reddedip akış açılışını düşürüyordu.
    await controller.setSubtitlePosition(100.0);
    await controller.setSubtitlePosition(33.4);

    expect(backend.calls, ['set:sub-pos=100', 'set:sub-pos=33']);
    expect(backend.properties['sub-pos'], '33');
    expect(controller.subtitlePosition, 33.4);
  });

  test('ses senkronu artı eksi beş saniyeyle sınırlı', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setAudioDelay(const Duration(milliseconds: 750));
    await controller.setAudioDelay(const Duration(seconds: -5));

    expect(controller.audioDelay, const Duration(seconds: -5));
    expect(backend.calls, [
      'set:audio-delay=0.750000',
      'set:audio-delay=-5.000000',
    ]);
    await expectLater(
      controller.setAudioDelay(const Duration(microseconds: 5000001)),
      throwsRangeError,
    );
    await expectLater(
      controller.setAudioDelay(const Duration(microseconds: -5000001)),
      throwsRangeError,
    );
  });

  test('video presetleri sabit özellikleri yazar ve readback yapar', () async {
    final backend = _FakeBackend()
      ..readbackOverrides.addAll({
        'brightness': '-2.000000',
        'contrast': '6.000000',
        'saturation': '-4.000000',
        'gamma': '-2.000000',
      });
    final controller = AdvancedPlaybackController(backend);

    await controller.setVideoPreset(VideoPreset.cinema);

    expect(controller.videoPreset, VideoPreset.cinema);
    expect(backend.calls, [
      'get:brightness',
      'get:contrast',
      'get:saturation',
      'get:gamma',
      'set:brightness=-2',
      'set:contrast=6',
      'set:saturation=-4',
      'set:gamma=-2',
      'get:brightness',
      'get:contrast',
      'get:saturation',
      'get:gamma',
    ]);
  });

  test('kritik video preset readback uyuşmazlığı state değiştirmez', () async {
    final backend = _FakeBackend()..readbackOverrides['contrast'] = '99';
    final controller = AdvancedPlaybackController(backend);

    await expectLater(
      controller.setVideoPreset(VideoPreset.vivid),
      throwsUnsupportedError,
    );
    expect(controller.videoPreset, VideoPreset.natural);
  });

  test('upscaling profilleri scaler özelliklerini yazıp doğrular', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setUpscalingPreset(UpscalingPreset.quality);

    expect(controller.upscalingPreset, UpscalingPreset.quality);
    expect(backend.calls, [
      'get:scale',
      'get:cscale',
      'get:dscale',
      'set:scale=ewa_lanczossharp',
      'set:cscale=ewa_lanczossharp',
      'set:dscale=mitchell',
      'get:scale',
      'get:cscale',
      'get:dscale',
    ]);
  });

  test(
    'audio presetleri yalnız sabit ve güvenli af değerleri kullanır',
    () async {
      final backend = _FakeBackend();
      final controller = AdvancedPlaybackController(backend);

      await controller.setAudioPreset(AudioPreset.balanced);
      await controller.setAudioPreset(AudioPreset.dialogue);
      await controller.setAudioPreset(AudioPreset.night);

      expect(controller.audioPreset, AudioPreset.night);
      expect(backend.calls, [
        'set:af=',
        'set:af=lavfi=[highpass=f=100,equalizer=f=2500:t=q:w=1:g=4]',
        'set:af=lavfi=[acompressor=threshold=0.125:ratio=4:attack=20:'
            'release=250:makeup=2]',
      ]);
      expect(backend.calls, everyElement(isNot(contains('\n'))));
      expect(backend.calls, everyElement(isNot(startsWith('command:'))));
    },
  );

  test('video pan değerleri doğrulanıp ayrı eksenlere yazılır', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setVideoPan(x: 0.25, y: -0.5);

    expect(controller.videoPanX, 0.25);
    expect(controller.videoPanY, -0.5);
    expect(backend.calls, [
      'get:video-pan-x',
      'get:video-pan-y',
      'set:video-pan-x=0.250000',
      'set:video-pan-y=-0.500000',
    ]);
    await expectLater(controller.setVideoPan(x: -1.01, y: 0), throwsRangeError);
    await expectLater(controller.setVideoPan(x: 0, y: 1.01), throwsRangeError);
  });

  test(
    'canvas dönüşümü aspect, zoom ve panı birlikte uygular ve sıfırlar',
    () async {
      final backend = _FakeBackend();
      final controller = AdvancedPlaybackController(backend);

      await controller.applyCanvasTransform(
        aspectRatio: 2.39,
        zoom: 2,
        panX: 0.25,
        panY: -0.5,
      );

      expect(controller.aspectRatioOverride, 2.39);
      expect(controller.zoom, 2);
      expect(controller.videoPanX, 0.25);
      expect(controller.videoPanY, -0.5);
      expect(backend.calls, [
        'get:video-aspect-override',
        'get:video-zoom',
        'get:video-pan-x',
        'get:video-pan-y',
        'set:video-aspect-override=2.390000',
        'set:video-zoom=1.000000',
        'set:video-pan-x=0.250000',
        'set:video-pan-y=-0.500000',
      ]);

      backend.calls.clear();
      await controller.resetCanvasTransform();
      expect(controller.aspectRatioOverride, isNull);
      expect(controller.zoom, 1);
      expect(controller.videoPanX, 0);
      expect(controller.videoPanY, 0);
      expect(backend.calls, [
        'get:video-aspect-override',
        'get:video-zoom',
        'get:video-pan-x',
        'get:video-pan-y',
        'set:video-aspect-override=-1',
        'set:video-zoom=0.000000',
        'set:video-pan-x=0.000000',
        'set:video-pan-y=0.000000',
      ]);
    },
  );

  test('geçersiz canvas dönüşümü kısmi mpv yazımı yapmaz', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await expectLater(
      controller.applyCanvasTransform(aspectRatio: 0.24),
      throwsRangeError,
    );
    await expectLater(
      controller.applyCanvasTransform(panX: 1.01),
      throwsRangeError,
    );
    await expectLater(
      controller.applyCanvasTransform(zoom: double.nan),
      throwsRangeError,
    );
    expect(backend.calls, isEmpty);
  });

  test('HDR anahtarı doğal HDR yolunu açıp SDR zorlamasını kaldırır', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setHdrEnabled(true);

    expect(controller.hdrEnabled, isTrue);
    expect(backend.calls, [
      'get:tone-mapping',
      'get:hdr-compute-peak',
      'get:gamut-mapping-mode',
      'get:target-trc',
      'get:target-prim',
      'set:tone-mapping=clip',
      'set:hdr-compute-peak=no',
      'set:gamut-mapping-mode=auto',
      'set:target-trc=auto',
      'set:target-prim=auto',
      'get:tone-mapping',
      'get:hdr-compute-peak',
      'get:gamut-mapping-mode',
      'get:target-trc',
      'get:target-prim',
      'set:target-colorspace-hint=yes',
    ]);
  });

  test('target-colorspace-hint yoksa HDR profili yine de uygulanır', () async {
    final backend = _FakeBackend()
      ..unsupportedProperties.add('target-colorspace-hint');
    final controller = AdvancedPlaybackController(backend);

    await controller.setHdrEnabled(true);

    expect(controller.hdrEnabled, isTrue);
    expect(backend.properties['tone-mapping'], 'clip');
    expect(backend.calls, contains('set:target-colorspace-hint=yes'));
  });

  test('donanım kod çözme anahtarı auto-safe ve yazılım arasında geçer', () async {
    // Android dışı platform beklentisi: test ortamı Android sayıldığından
    // açıkça masaüstü platformu sabitlenir.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setHardwareDecoding(false);
    expect(controller.hardwareDecoding, isFalse);
    await controller.setHardwareDecoding(true);
    expect(controller.hardwareDecoding, isTrue);

    expect(backend.calls, ['set:hwdec=no', 'set:hwdec=auto-safe']);
  });

  test('Android\'de donanım kod çözme auto değeriyle açılır', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setHardwareDecoding(true);

    expect(backend.calls, ['set:hwdec=auto']);
  });

  test('Android\'de HTTP profili çözücü seviyesinde kare düşürmeyi açar', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.applyStreamingTransportProfile();

    expect(backend.calls, contains('set:framedrop=decoder+vo'));
    expect(backend.properties['framedrop'], 'decoder+vo');
  });

  test('Android dışında HTTP profili kare düşürmeye dokunmaz', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.applyStreamingTransportProfile();

    expect(
      backend.calls.where((call) => call.contains('framedrop')),
      isEmpty,
    );
  });

  test('HDR içerik tespiti primaries ve gamma üzerinden yapılır', () async {
    final hdrBackend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.2020'
      ..readbackOverrides['video-params/gamma'] = 'pq';
    expect(
      await AdvancedPlaybackController(hdrBackend).detectHdrContent(),
      isTrue,
    );

    final hlgBackend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.2020'
      ..readbackOverrides['video-params/gamma'] = 'hlg';
    expect(
      await AdvancedPlaybackController(hlgBackend).detectHdrContent(),
      isTrue,
    );

    final sdrBackend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.709'
      ..readbackOverrides['video-params/gamma'] = 'bt.1886';
    expect(
      await AdvancedPlaybackController(sdrBackend).detectHdrContent(),
      isFalse,
    );

    // Başlık henüz açılmadıysa (boş parametreler) SDR kabul edilir.
    expect(await AdvancedPlaybackController(_FakeBackend()).detectHdrContent(),
        isFalse);
  });

  test('HDR yetenekleri HDR10 içerikte sdr/hdr/hdr10 sunar', () async {
    final backend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.2020'
      ..readbackOverrides['video-params/gamma'] = 'pq'
      ..readbackOverrides['video-params/max-luma'] = '4000.000000'
      ..readbackOverrides['track-list/count'] = '2'
      ..readbackOverrides['track-list/0/type'] = 'video'
      ..readbackOverrides['track-list/1/type'] = 'audio';

    final caps =
        await AdvancedPlaybackController(backend).detectHdrCapabilities();

    expect(caps.hdrSignal, isTrue);
    expect(caps.hdr10StaticMetadata, isTrue);
    expect(caps.dolbyVisionProfile, isNull);
    expect(caps.supports(HdrMode.sdr), isTrue);
    expect(caps.supports(HdrMode.hdr), isTrue);
    expect(caps.supports(HdrMode.hdr10), isTrue);
    // HDR10+ dinamik üstverisi libmpv'de algılanamadığı için daima pasif.
    expect(caps.supports(HdrMode.hdr10plus), isFalse);
    expect(caps.supports(HdrMode.dolbyVision), isFalse);
  });

  test('HDR yetenekleri Dolby Vision başlığını track üstverisinden bulur',
      () async {
    final backend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.2020'
      ..readbackOverrides['video-params/gamma'] = 'pq'
      ..readbackOverrides['video-params/max-luma'] = '1000.000000'
      ..readbackOverrides['track-list/count'] = '1'
      ..readbackOverrides['track-list/0/type'] = 'video'
      ..readbackOverrides['track-list/0/dolby-vision-profile'] = '8';

    final caps =
        await AdvancedPlaybackController(backend).detectHdrCapabilities();

    expect(caps.dolbyVisionProfile, 8);
    expect(caps.supports(HdrMode.dolbyVision), isTrue);
    expect(caps.supports(HdrMode.hdr10), isTrue);
    expect(caps.supports(HdrMode.hdr10plus), isFalse);
  });

  test('DV özelliği okuma hatası verirse içerik DV sayılmaz', () async {
    final backend = _ThrowingGetBackend(
      overrides: {
        'video-params/primaries': 'bt.2020',
        'video-params/gamma': 'pq',
        'video-params/max-luma': '1000.000000',
        'track-list/count': '1',
        'track-list/0/type': 'video',
      },
      throwingProperties: {'track-list/0/dolby-vision-profile'},
    );

    final caps =
        await AdvancedPlaybackController(backend).detectHdrCapabilities();

    expect(caps.dolbyVisionProfile, isNull);
    expect(caps.supports(HdrMode.dolbyVision), isFalse);
    expect(caps.supports(HdrMode.hdr10), isTrue);
  });

  test('SDR içerikte yalnız SDR modu desteklenir', () async {
    final backend = _FakeBackend()
      ..readbackOverrides['video-params/primaries'] = 'bt.709'
      ..readbackOverrides['video-params/gamma'] = 'bt.1886';

    final caps =
        await AdvancedPlaybackController(backend).detectHdrCapabilities();

    for (final mode in HdrMode.values) {
      expect(caps.supports(mode), mode == HdrMode.sdr, reason: mode.name);
    }
    // Okuma tamamen başarısız olursa da güvenli varsayılan SDR'dir.
    final empty =
        await AdvancedPlaybackController(_FakeBackend())
            .detectHdrCapabilities();
    expect(empty.supports(HdrMode.sdr), isTrue);
    expect(empty.hdrSignal, isFalse);
  });

  test('HDR modu seçimi doğal yolu açıp SDR zorlamasını kaldırır', () async {
    final backend = _FakeBackend();
    final controller = AdvancedPlaybackController(backend);

    await controller.setHdrMode(HdrMode.dolbyVision);

    expect(controller.hdrMode, HdrMode.dolbyVision);
    expect(controller.hdrEnabled, isTrue);
    expect(backend.properties['tone-mapping'], 'clip');
    expect(backend.properties['target-trc'], 'auto');
    expect(backend.calls, contains('set:target-colorspace-hint=yes'));

    await controller.setHdrMode(HdrMode.sdr);

    expect(controller.hdrMode, HdrMode.sdr);
    expect(controller.hdrEnabled, isFalse);
    expect(backend.properties['tone-mapping'], 'bt.2390');
    expect(backend.properties['target-trc'], 'bt.1886');
    expect(backend.calls, contains('set:target-colorspace-hint=no'));
  });
}

/// DV gibi varlığı içerikle değişen özelliklerde gerçek libmpv davranışını
/// taklit eder: listelenen özellikler okununca hata fırlatır.
class _ThrowingGetBackend extends _FakeBackend {
  _ThrowingGetBackend({
    Map<String, String>? overrides,
    this.throwingProperties = const {},
  }) {
    if (overrides != null) readbackOverrides.addAll(overrides);
  }

  final Set<String> throwingProperties;

  @override
  Future<String> getProperty(String name) async {
    if (throwingProperties.contains(name)) {
      throw StateError('$name bu başlıkta yok');
    }
    return super.getProperty(name);
  }
}
