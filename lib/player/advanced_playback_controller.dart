import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';

abstract interface class PlaybackBackend {
  Future<void> setRate(double rate);

  Future<void> pause();

  Future<void> setProperty(String name, String value);

  Future<String> getProperty(String name);

  Future<void> command(List<String> arguments);
}

class MediaKitPlaybackBackend implements PlaybackBackend {
  MediaKitPlaybackBackend(this.player);

  final Player player;

  NativePlayer get _nativePlayer {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      throw UnsupportedError('Gelişmiş libmpv kontrolleri bu platformda yok.');
    }
    return platform;
  }

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> setProperty(String name, String value) =>
      _nativePlayer.setProperty(name, value);

  @override
  Future<String> getProperty(String name) => _nativePlayer.getProperty(name);

  @override
  Future<void> command(List<String> arguments) =>
      _nativePlayer.command(arguments);
}

enum VideoPreset { natural, cinema, vivid }

enum UpscalingPreset { balanced, quality, lowPower }

enum AudioPreset { balanced, dialogue, night }

/// Görüntü çıkışı için seçilebilir dinamik aralık modları.
///
/// İçerik hangi formatları taşıyorsa yalnız onlar seçilebilir; SDR her zaman
/// seçilebilir çünkü her HDR sinyali aşağı ton eşlenebilir.
enum HdrMode { sdr, hdr, hdr10, hdr10plus, dolbyVision }

/// Geçerli içeriğin taşıdığı dinamik aralık yetenekleri. libmpv video
/// parametreleri ve başlık (track) üstverisinden okunur.
///
/// HDR10+ için çalışma zamanında algılama YOKTUR: mpv, SMPTE ST 2094-40
/// dinamik üstverisinin varlığını bir özellik olarak sunmaz. Bu yüzden
/// [HdrMode.hdr10plus] hiçbir içerikte etkinleşmez; menüde pasif gösterilir.
class HdrCapabilities {
  const HdrCapabilities({
    this.hdrSignal = false,
    this.hdr10StaticMetadata = false,
    this.dolbyVisionProfile,
  });

  /// PQ/HLG gama veya bt.2020 primaries ile gelen HDR sinyali.
  final bool hdrSignal;

  /// HDR10 statik üstverisi (MaxCLL/MaxFALL -> video-params/max-luma).
  final bool hdr10StaticMetadata;

  /// Video başlığının Dolby Vision profili; DV üstverisi yoksa null.
  final int? dolbyVisionProfile;

  bool supports(HdrMode mode) => switch (mode) {
    HdrMode.sdr => true,
    HdrMode.hdr => hdrSignal || dolbyVisionProfile != null,
    HdrMode.hdr10 => hdr10StaticMetadata,
    HdrMode.hdr10plus => false,
    HdrMode.dolbyVision => dolbyVisionProfile != null,
  };
}

/// libmpv'nin gelişmiş oynatma yüzeyini doğrulanabilir, test edilebilir bir
/// API altında toplar.
class AdvancedPlaybackController {
  AdvancedPlaybackController(this._backend);

  static const double minimumRate = 0.5;
  static const double maximumRate = 16.0;
  static const double minimumZoom = 1.0;
  static const double maximumZoom = 4.0;
  static const double minimumSubtitleScale = 0.5;
  static const double maximumSubtitleScale = 3.0;
  static const double minimumSubtitlePosition = 0.0;
  static const double maximumSubtitlePosition = 100.0;
  static const double minimumPan = -1.0;
  static const double maximumPan = 1.0;
  static const double minimumAspectRatio = 0.25;
  static const double maximumAspectRatio = 4.0;
  static const Duration minimumRelativeSeek = Duration(seconds: 1);
  static const Duration maximumSubtitleDelay = Duration(seconds: 60);
  static const Duration maximumAudioDelay = Duration(seconds: 5);

  static const supportedRates = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    4.0,
    8.0,
    16.0,
  ];

  /// HDR anahtarı kapalıyken HDR/Dolby Vision içerik SDR'e dönüştürülür.
  /// Hedef renk uzayı açıkça bt.709/bt.1886 olarak zorlanır ki dönüşüm her
  /// render yolunda (libmpv render API dahil) gerçekleşsin.
  static const hdrToSdrProfile = <String, String>{
    'tone-mapping': 'bt.2390',
    'hdr-compute-peak': 'yes',
    'gamut-mapping-mode': 'desaturate',
    'target-trc': 'bt.1886',
    'target-prim': 'bt.709',
  };

  /// HDR anahtarı açıkken sinyal ekrana sıkıştırılmadan verilir: ton eşleme
  /// kapanır ve SDR profilinin hedef zorlaması `auto`ya döndürülür.
  /// mpv 0.36'da `tone-mapping=no` seçeneği yoktur (geçersiz değer hatası
  /// verir); ton sıkıştırmayı kapatmanın bu sürümdeki karşılığı `clip`tir.
  static const hdrNativeProfile = <String, String>{
    'tone-mapping': 'clip',
    'hdr-compute-peak': 'no',
    'gamut-mapping-mode': 'auto',
    'target-trc': 'auto',
    'target-prim': 'auto',
  };

  /// localhost HTTP yanıtı bir NNTP segmentini beklerken media_kit'in beş
  /// saniyelik ağ zaman aşımına takılmaz. Cache bellekte kalır; izlenen medya
  /// sessizce diske yazılmaz.
  static const streamingTransportProfile = <String, String>{
    'network-timeout': '60',
    'cache': 'yes',
    'cache-on-disk': 'no',
  };

  static const _videoPresetProperties = <VideoPreset, Map<String, String>>{
    VideoPreset.natural: {
      'brightness': '0',
      'contrast': '0',
      'saturation': '0',
      'gamma': '0',
    },
    VideoPreset.cinema: {
      'brightness': '-2',
      'contrast': '6',
      'saturation': '-4',
      'gamma': '-2',
    },
    VideoPreset.vivid: {
      'brightness': '2',
      'contrast': '10',
      'saturation': '12',
      'gamma': '1',
    },
  };

  // Bu scaler adları mpv 0.36'nın GPU video çıkışıyla uyumludur. Profil,
  // yalnız sabit enum değerlerinden seçilir; kullanıcı metni mpv'ye aktarılmaz.
  static const _upscalingPresetProperties =
      <UpscalingPreset, Map<String, String>>{
        UpscalingPreset.balanced: {
          'scale': 'spline36',
          'cscale': 'spline36',
          'dscale': 'mitchell',
        },
        UpscalingPreset.quality: {
          'scale': 'ewa_lanczossharp',
          'cscale': 'ewa_lanczossharp',
          'dscale': 'mitchell',
        },
        UpscalingPreset.lowPower: {
          'scale': 'bilinear',
          'cscale': 'bilinear',
          'dscale': 'bilinear',
        },
      };

  // `af` yalnız bu derleme-zamanı sabitlerinden beslenir. Böylece gelecekteki
  // menü/shortcut katmanı serbest biçimli bir filter graph enjekte edemez.
  static const _audioPresetFilters = <AudioPreset, String>{
    AudioPreset.balanced: '',
    AudioPreset.dialogue: 'lavfi=[highpass=f=100,equalizer=f=2500:t=q:w=1:g=4]',
    AudioPreset.night:
        'lavfi=[acompressor=threshold=0.125:ratio=4:attack=20:'
        'release=250:makeup=2]',
  };

  final PlaybackBackend _backend;

  double rate = 1.0;
  double zoom = 1.0;
  Duration? loopStart;
  Duration? loopEnd;
  double subtitleScale = 1.0;
  double subtitlePosition = 100.0;
  Duration subtitleDelay = Duration.zero;
  Duration audioDelay = Duration.zero;
  double videoPanX = 0.0;
  double videoPanY = 0.0;
  double? aspectRatioOverride;
  VideoPreset videoPreset = VideoPreset.natural;
  UpscalingPreset upscalingPreset = UpscalingPreset.balanced;
  AudioPreset audioPreset = AudioPreset.balanced;
  HdrMode hdrMode = HdrMode.sdr;
  bool hardwareDecoding = true;

  /// HDR modu seçer: SDR dışındaki modlarda doğal HDR/Dolby Vision sinyali
  /// ekrana işlenmeden verilir, SDR'de içerik bt.709'a ton eşlenir. Her ayarın
  /// libmpv tarafından kabul edildiği geri okunarak doğrulanır.
  ///
  /// `target-colorspace-hint` (mpv 0.37+) HDR sinyalini destekleyen ekrana
  /// doğrudan iletir; eski libmpv'de yoksa atomik profili bozmamak için
  /// doğrulamasız, en iyi çabayla denenir.
  Future<void> setHdrMode(HdrMode mode) async {
    await _applyPropertiesWithReadback(
      mode == HdrMode.sdr ? hdrToSdrProfile : hdrNativeProfile,
    );
    await _trySetProperty(
      'target-colorspace-hint',
      mode == HdrMode.sdr ? 'no' : 'yes',
    );
    hdrMode = mode;
  }

  /// Eski aç/kapa arayüzünün karşılığı: açık = [HdrMode.hdr].
  Future<void> setHdrEnabled(bool enabled) =>
      setHdrMode(enabled ? HdrMode.hdr : HdrMode.sdr);

  bool get hdrEnabled => hdrMode != HdrMode.sdr;

  /// Derlemenin desteklemediği özelliklerde sessizce geçer.
  Future<void> _trySetProperty(String name, String value) async {
    try {
      await _backend.setProperty(name, value);
    } catch (_) {
      // Özellik yoksa profilin geri kalanıyla çalışma sürdürülür.
    }
  }

  /// Donanım kod çözmeyi açar (`auto-safe`) veya kapatır (yazılım). mpv bu
  /// özelliğin çalışma zamanında değişmesini destekler.
  Future<void> setHardwareDecoding(bool enabled) async {
    await _backend.setProperty('hwdec', enabled ? 'auto-safe' : 'no');
    hardwareDecoding = enabled;
  }

  /// Geçerli içeriğin dinamik aralık yeteneklerini libmpv video
  /// parametrelerinden ve başlık üstverisinden okur. Başlık henüz
  /// açılmadıysa veya okuma başarısızsa güvenli tarafta kalıp yalnız
  /// SDR'i destekleyen boş bir sonuç döner.
  Future<HdrCapabilities> detectHdrCapabilities() async {
    try {
      final primaries = (await _backend.getProperty('video-params/primaries'))
          .trim()
          .toLowerCase();
      final gamma = (await _backend.getProperty('video-params/gamma'))
          .trim()
          .toLowerCase();
      final hdrSignal =
          primaries.contains('bt.2020') || gamma == 'pq' || gamma == 'hlg';
      var hdr10StaticMetadata = false;
      if (hdrSignal) {
        // HDR10 statik üstverisi varsa mpv bunu max-luma olarak sunar;
        // üstveri yoksa özellik okuma hatası verir/boş döner.
        final maxLuma = double.tryParse(
          (await _backend.getProperty('video-params/max-luma')).trim(),
        );
        hdr10StaticMetadata = maxLuma != null && maxLuma > 0;
      }
      return HdrCapabilities(
        hdrSignal: hdrSignal,
        hdr10StaticMetadata: hdr10StaticMetadata,
        dolbyVisionProfile: await _detectDolbyVisionProfile(),
      );
    } catch (_) {
      return const HdrCapabilities();
    }
  }

  /// Video başlıklarında Dolby Vision profili arar. mpv 0.40, DV üstverisini
  /// `track-list/<i>/dolby-vision-profile` olarak sunar; DV taşımayan
  /// başlıkta özellik okuma hatası verir.
  Future<int?> _detectDolbyVisionProfile() async {
    try {
      final count =
          int.tryParse(
            (await _backend.getProperty('track-list/count')).trim(),
          ) ??
          0;
      for (var i = 0; i < count; i++) {
        try {
          final type = (await _backend.getProperty('track-list/$i/type'))
              .trim();
          if (type != 'video') continue;
          final raw = (await _backend.getProperty(
                'track-list/$i/dolby-vision-profile',
              ))
              .trim();
          final profile = int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
          if (profile != null && profile > 0) return profile;
        } catch (_) {
          // Bu başlıkta DV üstverisi yok; diğer başlıklar denenir.
        }
      }
    } catch (_) {
      // Başlık listesi okunamadı: DV yok sayılır.
    }
    return null;
  }

  /// Geçerli içeriğin HDR sinyali taşıyıp taşımadığını raporlar.
  Future<bool> detectHdrContent() async {
    final capabilities = await detectHdrCapabilities();
    return capabilities.hdrSignal || capabilities.dolbyVisionProfile != null;
  }

  Future<void> applyStreamingTransportProfile() =>
      _applyPropertiesWithReadback(streamingTransportProfile);

  Future<String> engineVersion() async {
    final value = (await _backend.getProperty('mpv-version')).trim();
    return value.isEmpty ? 'libmpv' : value;
  }

  Future<void> setRate(double value) async {
    _requireFiniteRange(value, minimumRate, maximumRate, 'Oynatma hızı');
    await _backend.setRate(value);
    rate = value;
  }

  /// Geçerli konuma göre seek eder. mpv'de `exact=false` en yakın keyframe'i,
  /// `exact=true` ise mümkün olan kesin zamanı hedefler.
  Future<void> seekRelative(Duration offset, {bool exact = false}) async {
    if (offset.inMicroseconds.abs() < minimumRelativeSeek.inMicroseconds) {
      throw RangeError(
        'Göreli seek en az ${minimumRelativeSeek.inSeconds} saniye olmalı: '
        '$offset',
      );
    }
    await _backend.command([
      'seek',
      _seconds(offset),
      exact ? 'relative+exact' : 'relative',
    ]);
  }

  Future<void> setLoopStart(Duration position) async {
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Negatif olamaz.');
    }
    // Yeni A noktası eski B noktasıyla istemeden döngü başlatmasın.
    await _backend.setProperty('ab-loop-b', 'no');
    await _backend.setProperty('ab-loop-a', _seconds(position));
    loopStart = position;
    loopEnd = null;
  }

  Future<void> setLoopEnd(Duration position) async {
    final start = loopStart;
    if (start == null) {
      throw StateError('Önce A noktası seçilmeli.');
    }
    if (position <= start) {
      throw ArgumentError.value(
        position,
        'position',
        'B noktası A noktasından sonra olmalı.',
      );
    }
    await _backend.setProperty('ab-loop-b', _seconds(position));
    loopEnd = position;
  }

  Future<void> clearLoop() async {
    await _backend.setProperty('ab-loop-a', 'no');
    await _backend.setProperty('ab-loop-b', 'no');
    loopStart = null;
    loopEnd = null;
  }

  Future<void> stepForward() async {
    await _backend.pause();
    await _backend.command(const ['frame-step']);
  }

  Future<void> stepBackward() async {
    await _backend.pause();
    await _backend.command(const ['frame-back-step']);
  }

  Future<double> setZoom(double value) async {
    final clamped = _clampedZoom(value);
    await _backend.setProperty(
      'video-zoom',
      mpvZoomForScale(clamped).toStringAsFixed(6),
    );
    zoom = clamped;
    return clamped;
  }

  Future<void> setSubtitleScale(double value) async {
    _requireFiniteRange(
      value,
      minimumSubtitleScale,
      maximumSubtitleScale,
      'Altyazı ölçeği',
    );
    await _backend.setProperty('sub-scale', _number(value));
    subtitleScale = value;
  }

  Future<void> setSubtitlePosition(double value) async {
    _requireFiniteRange(
      value,
      minimumSubtitlePosition,
      maximumSubtitlePosition,
      'Altyazı konumu',
    );
    // sub-pos mpv'de OPT_INT'tir; ondalık metin ("100.000000") reddedilir.
    await _backend.setProperty('sub-pos', _integer(value));
    subtitlePosition = value;
  }

  Future<void> setSubtitleDelay(Duration value) async {
    _requireDurationRange(value, maximumSubtitleDelay, 'Altyazı gecikmesi');
    await _backend.setProperty('sub-delay', _seconds(value));
    subtitleDelay = value;
  }

  Future<void> setAudioDelay(Duration value) async {
    _requireDurationRange(value, maximumAudioDelay, 'Ses gecikmesi');
    await _backend.setProperty('audio-delay', _seconds(value));
    audioDelay = value;
  }

  Future<void> setVideoPreset(VideoPreset value) async {
    await _applyPropertiesWithReadback(_videoPresetProperties[value]!);
    videoPreset = value;
  }

  Future<void> setUpscalingPreset(UpscalingPreset value) async {
    await _applyPropertiesWithReadback(_upscalingPresetProperties[value]!);
    upscalingPreset = value;
  }

  Future<void> setAudioPreset(AudioPreset value) async {
    // Enum dışından filter graph alınmaması bu API'nin güvenlik sınırıdır.
    await _backend.setProperty('af', _audioPresetFilters[value]!);
    audioPreset = value;
  }

  Future<void> setVideoPan({required double x, required double y}) async {
    _requirePan(x, 'Yatay video konumu');
    _requirePan(y, 'Dikey video konumu');
    await _applyPropertiesAtomically({
      'video-pan-x': _number(x),
      'video-pan-y': _number(y),
    });
    videoPanX = x;
    videoPanY = y;
  }

  /// Smart Canvas tarafından onaylanan tam dönüşümü mpv 0.36 uyumlu
  /// `video-aspect-override`, `video-zoom` ve `video-pan-*` özellikleriyle
  /// uygular. `aspectRatio == null`, kapsayıcının doğal oranına döner.
  Future<void> applyCanvasTransform({
    double? aspectRatio,
    double zoom = 1.0,
    double panX = 0.0,
    double panY = 0.0,
  }) async {
    if (aspectRatio != null) {
      _requireFiniteRange(
        aspectRatio,
        minimumAspectRatio,
        maximumAspectRatio,
        'En-boy oranı',
      );
    }
    final clampedZoom = _clampedZoom(zoom);
    _requirePan(panX, 'Yatay video konumu');
    _requirePan(panY, 'Dikey video konumu');

    await _applyPropertiesAtomically({
      'video-aspect-override':
          // Paketli mpv 0.36'da `no` aspect işlemeyi devre dışı bırakır; `-1`
          // container oranına güvenli dönüş değeridir.
          aspectRatio == null ? '-1' : _number(aspectRatio),
      'video-zoom': mpvZoomForScale(clampedZoom).toStringAsFixed(6),
      'video-pan-x': _number(panX),
      'video-pan-y': _number(panY),
    });

    aspectRatioOverride = aspectRatio;
    this.zoom = clampedZoom;
    videoPanX = panX;
    videoPanY = panY;
  }

  Future<void> resetCanvasTransform() => applyCanvasTransform();

  Future<void> resetForNewMedia() async {
    await clearLoop();
    await setRate(1.0);
    await resetCanvasTransform();
  }

  static double mpvZoomForScale(double scale) => math.log(scale) / math.ln2;

  Future<void> _applyPropertiesWithReadback(Map<String, String> properties) =>
      _applyPropertiesAtomically(properties, verifyReadback: true);

  /// Bir profil birkaç libmpv özelliğinden oluştuğunda tek bir başarısız yazım
  /// oynatıcıyı yarım profilde bırakmamalı. Önce tüm etkin değerleri alır,
  /// ardından profili uygular; yazım veya doğrulama başarısızsa değiştirilmiş
  /// özellikleri ters sırada geri yükler.
  Future<void> _applyPropertiesAtomically(
    Map<String, String> properties, {
    bool verifyReadback = false,
  }) async {
    final originalValues = <String, String>{};
    for (final key in properties.keys) {
      originalValues[key] = await _backend.getProperty(key);
    }

    final changedKeys = <String>[];
    try {
      for (final entry in properties.entries) {
        changedKeys.add(entry.key);
        await _backend.setProperty(entry.key, entry.value);
      }
      if (!verifyReadback) return;

      for (final entry in properties.entries) {
        final effective = await _backend.getProperty(entry.key);
        if (!_propertyMatches(entry.value, effective)) {
          throw UnsupportedError(
            'libmpv ${entry.key}=${entry.value} ayarını uygulamadı '
            '(etkin değer: ${effective.isEmpty ? "yok" : effective}).',
          );
        }
      }
    } catch (error, stackTrace) {
      for (final key in changedKeys.reversed) {
        try {
          await _backend.setProperty(key, originalValues[key]!);
        } catch (_) {
          // İlk hatayı koru; geri alma için yapılabilecek başka bir işlem yok.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static double _clampedZoom(double value) {
    if (!value.isFinite) {
      throw RangeError('Video yakınlaştırması sonlu olmalı: $value');
    }
    return value.clamp(minimumZoom, maximumZoom).toDouble();
  }

  static void _requirePan(double value, String label) =>
      _requireFiniteRange(value, minimumPan, maximumPan, label);

  static void _requireFiniteRange(
    double value,
    double minimum,
    double maximum,
    String label,
  ) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw RangeError(
        '$label $minimum ile $maximum arasında ve sonlu olmalı: $value',
      );
    }
  }

  static void _requireDurationRange(
    Duration value,
    Duration maximum,
    String label,
  ) {
    if (value.inMicroseconds.abs() > maximum.inMicroseconds) {
      throw RangeError(
        '$label ±${maximum.inSeconds} saniye aralığında olmalı: $value',
      );
    }
  }

  static bool _propertyMatches(String expected, String effective) {
    final normalized = effective.trim();
    if (expected == normalized) return true;
    if (expected == 'yes' && normalized == 'true') return true;
    if (expected == 'no' && normalized == 'false') return true;

    final expectedNumber = double.tryParse(expected);
    final effectiveNumber = double.tryParse(normalized);
    return expectedNumber != null &&
        effectiveNumber != null &&
        expectedNumber.isFinite &&
        effectiveNumber.isFinite &&
        (expectedNumber - effectiveNumber).abs() <= 0.000001;
  }

  static String _number(double value) => value.toStringAsFixed(6);

  /// Yalnız tamsayı kabul eden mpv seçeneklerinin (sub-pos gibi) tel biçimi.
  static String _integer(double value) => value.round().toString();

  static String _seconds(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerSecond)
          .toStringAsFixed(6);
}
