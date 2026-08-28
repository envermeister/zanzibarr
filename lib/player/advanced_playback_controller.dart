import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

abstract interface class PlaybackBackend {
  Future<void> setRate(double rate);

  Future<void> pause();

  Future<void> setProperty(String name, String value);

  Future<String> getProperty(String name);

  Future<void> command(List<String> arguments);

  /// libmpv günlük satırları (hata düzeyi). DV reshape filtresinin çalışma
  /// zamanı doğrulaması için kullanılır; desteklenmiyorsa boş akış döner.
  Stream<String> get logLines;
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

  @override
  Stream<String> get logLines => player.stream.log.map(
    (entry) => '[${entry.prefix}] ${entry.text}',
  );
}

enum VideoPreset { natural, cinema, vivid }

enum UpscalingPreset { balanced, quality, lowPower }

enum AudioPreset { balanced, dialogue, night }

/// Görüntü çıkışı için seçilebilir dinamik aralık modları.
///
/// İçerik hangi formatları taşıyorsa yalnız onlar seçilebilir; SDR her zaman
/// seçilebilir çünkü her HDR sinyali aşağı ton eşlenebilir.
enum HdrMode { sdr, hdr, hdr10, hdr10plus, dolbyVision }

/// DV reshape filtresinin çalışma zamanı durumu. `vf` yazımı başarılı olsa
/// bile lavfi grafı kareler akmaya başlayınca sessizce devre dışı kalabilir
/// (Vulkan başlatılamaz, biçim uyuşmaz vb.); bu yüzden filtre, libmpv günlük
/// akışıyla izlenir ve sonuç burada raporlanır.
enum DvReshapeStatus {
  /// Filtre kapalı.
  inactive,

  /// Filtre uygulandı; çalışma zamanı doğrulaması sürüyor.
  applying,

  /// İzleme penceresi hatasız geçti; filtre etkin kabul ediliyor.
  active,

  /// Filtre (yazılım çözme denemesi dahil) başlatılamadı; eski davranışa
  /// dönüldü. Ayrıntılar [AdvancedPlaybackController.dvDiagnostics]'te.
  failed,
}

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

  /// Varsayılan altyazı rengi (beyaz). mpv `sub-color` değeri `#RRGGBB`
  /// biçimindedir; ASS stillerini ezmez, düz metin altyazılara uygulanır.
  static const String defaultSubtitleColor = '#FFFFFF';
  static final RegExp _subtitleColorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

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

  /// Yalnız Android'de uygulanır. Zayıf TV box donanımlarında çözücü sese
  /// yetişemediğinde görüntü geride birikmesin: kare düşürme çözücü
  /// seviyesinde de devreye girer (varsayılan yalnız video çıkışında düşürür).
  static const androidPerformanceProfile = <String, String>{
    'framedrop': 'decoder+vo',
  };

  /// Dolby Vision Profile 5 (HDR10 baz katmansız, yalnız RPU üstverili)
  /// içerikte renk düzeltmesi yapan libavfilter grafı. Paketli mpv'nin
  /// render yolu (legacy libmpv render API) DV reshape yapmadığından
  /// düzeltme render yolundan bağımsız biçimde FFmpeg 8.1'in
  /// `vf_libplacebo` filtresiyle yapılır: filtre RPU üstverisini uygulayıp
  /// kareyi hedef renk uzayına dönüştürür. Filtre Vulkan zorunludur;
  /// macOS çerçevesine MoltenVK gömülüdür.
  ///
  /// `hwdownload,format=p010` öneki yalnız donanım çözmede zorunludur:
  /// donanım çözme açıkken vf zincirine VideoToolbox donanım kareleri
  /// (`videotoolbox_vld`) girer ve libplacebo bunları doğrudan işleyemez;
  /// mpv'nin lavfi köprüsü ffmpeg CLI'nın aksine hwdownload'ı otomatik
  /// eklemez (graf yapılandırması "Impossible to convert" hatasıyla sessizce
  /// devre dışı kalır). Yazılım çözmede ise önek grafiği BOZAR (yazılım
  /// karesi donanım kare bağlamı taşımaz), bu yüzden öneksiz varyantlar
  /// ayrı tutulur ve seçim [hardwareDecoding] bayrağına göre yapılır.
  ///
  /// SDR hedefi bt.709'a ton eşler. HDR hedefi bt.2020/PQ sinyal üretir ki
  /// filtre çıkışı sonraki render yoluna HDR10 içerikle aynı biçimde
  /// girsin (ton eşleme/`target-colorspace-hint` davranışı değişmez).
  static const dvReshapeFilterSdr =
      'lavfi=[hwdownload,format=p010,libplacebo=colorspace=bt709:'
      'color_primaries=bt709:color_trc=bt709]';
  static const dvReshapeFilterHdr =
      'lavfi=[hwdownload,format=p010,libplacebo=colorspace=bt2020nc:'
      'color_primaries=bt2020:color_trc=smpte2084]';

  /// Yazılım kod çözme varyantları (öneksiz); ayrıntı yukarıda.
  static const dvReshapeFilterSdrSoftware =
      'lavfi=[libplacebo=colorspace=bt709:color_primaries=bt709:'
      'color_trc=bt709]';
  static const dvReshapeFilterHdrSoftware =
      'lavfi=[libplacebo=colorspace=bt2020nc:color_primaries=bt2020:'
      'color_trc=smpte2084]';

  /// Android'e özel DV reshape grafiği; üç kuralı vardır:
  ///
  /// 1) Hedef her zaman bt.709/SDR: Android'de video çıkışı (ANGLE üzerinden
  ///    OpenGL ES) ekrana HDR sinyalleyemez; bt.2020/PQ çıkış hem anlamsız
  ///    hem de Xclipse 920 sınıfı sürücülerde sessiz siyah kare ürettiği
  ///    gözlendi. bt.709 hedefi her ekranda doğru görünür.
  /// 2) Girdi `format=yuv420p` ile 8-bit'e indirgenir: libplacebo 10-bit
  ///    girdiyi rg16 dokulara yükler ve reshape shader'ı linear örnekleme
  ///    ister; rg16'da PL_FMT_CAP_LINEAR her sürücüde yok (Xclipse 920'de
  ///    yok — "Failed dispatching scaler"). 8-bit rg8 dokularda linear
  ///    örnekleme Vulkan'da evrenseldir. SDR hedefi zaten 8-bit çıkıyor;
  ///    hassasiyet kaybı ihmal edilebilir.
  /// 3) Çıkış da yuv420p'ye sabitlenir (bağımsız `format` filtresiyle —
  ///    libplacebo'nun kendi format= seçeneği Android derlemesinde graf
  ///    ayrıştırma hatası üretir). Yerel harness ile gerçek P5 içerikte
  ///    doğrulandı: çıkış etiketleri bt.709/bt.1886 (reshape çalışıyor).
  static const dvReshapeFilterAndroid =
      'lavfi=[format=yuv420p,libplacebo=colorspace=bt709:color_primaries=bt709:'
      'color_trc=bt709,format=yuv420p]';

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
  String subtitleColor = defaultSubtitleColor;
  Duration audioDelay = Duration.zero;
  double videoPanX = 0.0;
  double videoPanY = 0.0;
  double? aspectRatioOverride;
  VideoPreset videoPreset = VideoPreset.natural;
  UpscalingPreset upscalingPreset = UpscalingPreset.balanced;
  AudioPreset audioPreset = AudioPreset.balanced;
  HdrMode hdrMode = HdrMode.sdr;
  bool hardwareDecoding = true;

  /// Dolby Vision Profile 5 renk düzeltmesi (libplacebo reshape filtresi)
  /// etkin mi. Yalnız [setDolbyVisionReshaping] ile değişir.
  bool dolbyVisionReshaping = false;

  /// Filtrenin çalışma zamanı durumu; [onDvReshapeStatusChanged] ile izlenir.
  DvReshapeStatus dvReshapeStatus = DvReshapeStatus.inactive;

  /// Durum değişiminde çağrılır (UI katmanı setState bağlar).
  void Function()? onDvReshapeStatusChanged;

  /// İzleme penceresinde yakalanan filtreye ilişkin libmpv günlük satırları
  /// (son 16 satır). Uzaktan hata raporu için UI'da gösterilebilir.
  List<String> get dvDiagnostics => List.unmodifiable(_dvDiagnostics);
  final List<String> _dvDiagnostics = <String>[];

  /// Android'de donanım (mediacodec-copy) denemesi başarısız olup yazılım
  /// çözmeye düşüldüyse true. Yalnız reshape etkinken anlamlıdır.
  bool get dvUsesSoftwareDecoding => _dvSoftwareRetried;
  bool _dvSoftwareRetried = false;

  StreamSubscription<String>? _dvLogSubscription;
  Timer? _dvWatchTimer;
  bool _dvFailureHandling = false;

  /// Filtrenin hatasız sayılması için gereken sükûnet süresi: lavfi graf
  /// yapılandırma hataları (Vulkan init, biçim uyuşmazlığı) ilk karelerde
  /// günlüğe düşer. Testlerde küçültülür.
  @visibleForTesting
  Duration dvWatchWindow = const Duration(seconds: 8);

  /// Bir graf hatası genelde art arda birkaç günlük satırı üretir; ilk hata
  /// satırından sonra bu kadar beklenir ki patlama tek deneme sayılsın.
  @visibleForTesting
  Duration dvFailureSettleWindow = const Duration(milliseconds: 250);

  /// [_verifyDvFilterOutput] sorgusunun üst süresi: kilitli bir oynatma
  /// döngüsüne yapılan özellik sorgusu asla dönmez; zaman aşımı kilitlenme
  /// kanıtı sayılır. Testlerde küçültülür.
  @visibleForTesting
  Duration dvVerifyTimeout = const Duration(seconds: 3);

  /// Bu oturumda filtre motoru kilitlediyse (sürücü düzeyi Vulkan sorunu)
  /// true: yeniden denemek aynı kilitlenmeyi üretir, bu yüzden reshape
  /// istekleri uygulama yeniden başlayana dek yok sayılır.
  bool get dvSessionBlacklisted => _dvSessionBlacklisted;
  bool _dvSessionBlacklisted = false;

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
    // Android'de P5 algısı track üstverisinden çalışır; kullanıcının DV
    // kipini seçmesi de reshape'i aynı yoldan etkinleştirir. Diğer kiplerde
    // filtre temizlenir.
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (mode == HdrMode.dolbyVision) {
        await setDolbyVisionReshaping(true);
      } else if (dolbyVisionReshaping) {
        await setDolbyVisionReshaping(false);
      }
      return;
    }
    // DV reshape filtresi çıkış renk uzayını kendisi sabitler; HDR modu
    // değişince filtre yeni hedefle yeniden uygulanır.
    if (dolbyVisionReshaping) {
      await setDolbyVisionReshaping(true);
    }
  }

  /// Dolby Vision Profile 5 içerikte pembe/yeşil bozuk renkleri düzelten
  /// reshape filtresini açar/kapatır.
  ///
  /// macOS'ta paketli Mpv çerçevesi libplacebo'lu FFmpeg ve MoltenVK ile
  /// derlenmiştir. Windows'ta media-kit'in paketli derlemesi libplacebo +
  /// Vulkan + libdovi içerir; filtre FFmpeg'in `vf_libplacebo`'su üzerinden
  /// çalışır. Android'de media-kit'in stok libmpv'sinde libplacebo yoktur;
  /// bu yüzden uygulama, libplacebo+Vulkan destekli fork derlemesiyle
  /// (vendor/media_kit_libs_android_video) gelir. Diğer platformlarda bayrak
  /// kapalı kalır ve `vf`'ye dokunulmaz.
  ///
  /// `vf` yazımının başarılı olması filtrenin gerçekten çalıştığını
  /// GARANTİLEMEZ: lavfi grafı ilk karelerde (Vulkan init, biçim uyuşmazlığı)
  /// sessizce devre dışı kalabilir. Bu yüzden filtre uygulandıktan sonra
  /// libmpv günlük akışı [dvWatchWindow] süresince izlenir; hata imzası,
  /// boş `video-params` (kare akışı yok) veya sorgu zaman aşımı (playloop
  /// kilitlenmesi) yakalanırsa eski davranışa dönülüp durum
  /// [DvReshapeStatus.failed] yapılır (ayrıntılar [dvDiagnostics]'te).
  /// Sonuç [dvReshapeStatus] ve [onDvReshapeStatusChanged] üzerinden UI'a
  /// yansır.
  ///
  /// Android'de decode her zaman yazılımdır: FFmpeg'de hevc mediacodec
  /// HWACCEL bulunmadığından mpv'nin mediacodec(-copy) yolu bağımsız
  /// `hevc_mediacodec` çözücüsünü kullanır ve bu çözücü dovi side-data
  /// ÜRETMEZ; reshape'in tek doğru kaynağı hevcdec.c yazılım yoludur
  /// (set_side_data her karede DOVI_METADATA iliştirir).
  ///
  /// Açıkken çıkış renk uzayı geçerli [hdrMode]'a göre seçilir; HDR modu
  /// sonradan değişirse [setHdrMode], kod çözme kipi değişirse
  /// [setHardwareDecoding] filtreyi uygun varyantla yeniden uygular.
  Future<void> setDolbyVisionReshaping(bool enabled) async {
    final platformSupported = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows;
    if (!platformSupported) {
      dolbyVisionReshaping = false;
      return;
    }
    if (!enabled) {
      dolbyVisionReshaping = false;
      _cancelDvWatch();
      // Yazılım denemesi yapıldıysa donanım kipi özgün değerine döndürülür
      // (Windows merdiveni); Android'de yüzey karelerine her zaman dönülür.
      final softwareWasForced = _dvSoftwareRetried;
      _dvSoftwareRetried = false;
      _setDvReshapeStatus(DvReshapeStatus.inactive);
      await _trySetProperty('vf', '');
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Mediacodec yüzey karelerine geri dön (sıfır-kopya render yolu).
        await _trySetProperty('hwdec', 'mediacodec');
      } else if (softwareWasForced) {
        await _trySetProperty('hwdec', hwdecEnabledValue);
      }
      return;
    }
    if (_dvSessionBlacklisted) {
      // Motor bu oturumda filtreye kilitlendi; yeniden denemek aynı
      // kilitlenmeyi üretir. Kullanıcı uygulamayı yeniden başlatıncaya dek
      // reshape kapalı tutulur (içerik SDR ton eşliyle izlenebilir).
      dolbyVisionReshaping = false;
      _setDvReshapeStatus(DvReshapeStatus.failed);
      return;
    }
    // Yeni bir kullanıcı denemesi: tanılama ve deneme merdiveni sıfırlanır.
    _dvDiagnostics.clear();
    _dvSoftwareRetried = false;
    await _applyDvReshapeFilter();
  }

  /// Filtreyi geçerli kip ve HDR hedefiyle uygular; çalışma zamanı izleme
  /// penceresini kurar. Özellik yazımı reddedilirse başarısızlık yoluna
  /// ([_handleDvFailure]) düşer.
  ///
  /// [forceSoftware] yalnız Windows merdivenindeki ikinci denemedir:
  /// d3d11va donanım kareleri libplacebo'ya doğrudan giremez ve hwdownload
  /// bazı sürücülerde dovi üstverisini düşürür; yazılım çözme (hevcdec.c
  /// set_side_data) üstveriyi her karede taşır.
  Future<void> _applyDvReshapeFilter({bool forceSoftware = false}) async {
    _setDvReshapeStatus(DvReshapeStatus.applying);
    _armDvWatch();
    try {
      // Android'de tek doğru dovi kaynağı yazılım çözmedir: FFmpeg'de hevc
      // için mediacodec HWACCEL yok; mpv'nin mediacodec(-copy) yolu bağımsız
      // `hevc_mediacodec` çözücüsünü kullanır ve bu çözücü hevcdec.c'nin
      // ortak side_data yolunu (set_side_data → DOVI_METADATA) HİÇ
      // çalıştırmaz. Çıkış karelerinde dovi üstverisi olmayınca filtre
      // reshape uygulayamaz — tüm Android cihazlardaki pembe/yeşilin gerçek
      // kökü budur. hevcdec.c (yazılım çözme) set_side_data'yı her karede
      // çalıştırır; kareler köprüden side-data ile geçer.
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Yedek donanım varyantı yok; merdiven tek denemedir ve etiket de
        // doğru olsun diye yazılım bayrağı baştan kurulur.
        _dvSoftwareRetried = true;
        await _backend.setProperty('hwdec', 'no');
        await _backend.setProperty('vf', dvReshapeFilterAndroid);
      } else if (forceSoftware) {
        await _backend.setProperty('hwdec', 'no');
        await _backend.setProperty(
          'vf',
          _dvReshapeFilterFor(hdrMode, forceSoftware: true),
        );
      } else {
        await _backend.setProperty('vf', _dvReshapeFilterFor(hdrMode));
      }
      dolbyVisionReshaping = true;
      _dvWatchTimer = Timer(dvWatchWindow, () {
        unawaited(_verifyDvFilterOutput());
      });
    } catch (_) {
      // Filtre bu derlemede yoksa/yazım reddedildiyse başarısızlık yolu.
      await _handleDvFailure('vf/hwdec özellik yazımı reddedildi');
    }
  }

  /// İzleme penceresi hata imzası olmadan geçtiğinde çıkış doğrulaması yapar.
  /// İki sessiz arıza biçimi de burada yakalanır: (a) filtre hiç çıkış
  /// üretmediyse `video-out-params` boş kalır, (b) sürücü düzeyinde
  /// kilitlenme (örn. Xclipse 920'de Vulkan init) mpv'nin oynatma döngüsünü
  /// dondurur — bu durumda hata satırı ASLA gelmez ve özellik sorgusu da
  /// yanıt vermez; sorgunun zaman aşımı kilitlenmenin kanıtıdır.
  Future<void> _verifyDvFilterOutput() async {
    if (dvReshapeStatus != DvReshapeStatus.applying) return;
    String fmt;
    try {
      // Giriş tarafı sorğulanır: video-out-params eski bir yapılandırmadan
      // kalma olabilir (yanlış "etkin"); video-params yalnız kare akışı
      // gerçekten varsa dolu olur.
      fmt = await _backend
          .getProperty('video-params/pixelformat')
          .timeout(dvVerifyTimeout);
    } on TimeoutException {
      // Oynatma döngüsü kilitli: uygulama içi merdivenle kurtarılamaz
      // (kilitli motora sonradan yazılan vf/hwdec işlenmez). Bu oturumda
      // filtre kara listeye alınır; kullanıcı içeriği kapatıp açınca
      // düzeltmesiz ama izlenebilir oynatma (SDR ton eşli) elde eder.
      _dvSessionBlacklisted = true;
      _recordDvDiagnostic(
        'motor yanıt vermiyor (filtre kilitlendi) — içeriği kapatıp '
        'yeniden açın; DV düzeltmesi bu oturumda devre dışı bırakıldı',
      );
      await _handleDvFailure('video-params sorgusu zaman aşımı (kilitlenme)');
      return;
    } catch (_) {
      fmt = '';
    }
    if (fmt.trim().isNotEmpty) {
      _setDvReshapeStatus(DvReshapeStatus.active);
      // Doğrulanan biçim zincirini tanılamaya düş: uzaktan kök analizinde
      // "siyah ekran" bildirimi gelirse pazarlık edilmiş zincir belirleyici
      // olur (örn. ES yolunun işleyemediği 10-bit çıkış).
      final hw = await _readPropertySafe('hwdec-current');
      final outFmt = await _readPropertySafe('video-out-params/pixelformat');
      _recordDvDiagnostic(
        'etkin zincir: hwdec=$hw, giris=${fmt.trim()}, cikis=$outFmt',
      );
    } else {
      await _handleDvFailure('video-params boş — kare akışı yok (filtre çıkış üretmedi)');
    }
  }

  /// Sorgulanamazsa '?' döner (tanılama satırı bozulmasın).
  Future<String> _readPropertySafe(String name) async {
    try {
      final value = (await _backend.getProperty(name)).trim();
      return value.isEmpty ? '?' : value;
    } catch (_) {
      return '?';
    }
  }

  /// Çalışma zamanı hatası yakalandığında: donanım denemesi başarısız olan
  /// platformlarda (Android hariç — orada yazılım tek yoldur ve baştan
  /// kurulur; Windows'ta ilk hatada yazılıma düşülür) yazılım çözmeyle bir
  /// kez yeniden dener; son denemede (veya macOS'ta) filtreyi temizleyip
  /// eski davranışa döner ve durumu failed yapar.
  Future<void> _handleDvFailure(String reason) async {
    _dvWatchTimer?.cancel();
    _recordDvDiagnostic(reason);
    final retryWithSoftware = !_dvSoftwareRetried &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows);
    if (retryWithSoftware) {
      _dvSoftwareRetried = true;
      _recordDvDiagnostic(
        'donanım yolu başarısız; yazılım çözme ile yeniden deneniyor',
      );
      await _applyDvReshapeFilter(forceSoftware: true);
      return;
    }
    dolbyVisionReshaping = false;
    await _trySetProperty('vf', '');
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _trySetProperty('hwdec', 'mediacodec');
    } else if (_dvSoftwareRetried) {
      // Yazılım denemesi de başarısız oldu; donanım kipi özgün değerine döner.
      await _trySetProperty('hwdec', hwdecEnabledValue);
    }
    _setDvReshapeStatus(DvReshapeStatus.failed);
  }

  void _armDvWatch() {
    _dvWatchTimer?.cancel();
    _dvLogSubscription ??= _backend.logLines.listen(
      _onDvLogLine,
      onError: (_) {
        // Günlük akışındaki hata tanılamayı engellemez.
      },
    );
  }

  void _cancelDvWatch() {
    _dvWatchTimer?.cancel();
    _dvWatchTimer = null;
    unawaited(_dvLogSubscription?.cancel());
    _dvLogSubscription = null;
  }

  void _onDvLogLine(String line) {
    if (dvReshapeStatus != DvReshapeStatus.applying) return;
    final lower = line.toLowerCase();
    // İzleme penceresinde gelen her hata düzeyi satır tanılamaya girer;
    // kilitlenme kök analizinde filtreye ilişkin görünmeyen satırlar da
    // (örn. son başarılı aşama) belirleyici olabiliyor.
    _recordDvDiagnostic(line.trim());
    if (!_looksLikeDvFailure(lower)) return;
    _dvWatchTimer?.cancel();
    // Aynı graf hatası genelde art arda birkaç günlük satırı üretir; ilk
    // satırda kısa bir sükûnet penceresi başlatılır ve patlama tek deneme
    // sayılır (yeniden giriş koruması).
    if (_dvFailureHandling) return;
    _dvFailureHandling = true;
    unawaited(_handleDvFailureAfterSettle(line.trim()));
  }

  Future<void> _handleDvFailureAfterSettle(String reason) async {
    try {
      // Patlama süresince gelen satırlar yalnız tanılamaya kaydedilir.
      await Future<void>.delayed(dvFailureSettleWindow);
      await _handleDvFailure(reason);
    } finally {
      _dvFailureHandling = false;
    }
  }

  void _recordDvDiagnostic(String line) {
    if (line.isEmpty) return;
    if (_dvDiagnostics.isNotEmpty && _dvDiagnostics.last == line) return;
    _dvDiagnostics.add(line);
    if (_dvDiagnostics.length > 30) _dvDiagnostics.removeAt(0);
  }

  /// lavfi/libplacebo filtresinin çalışma zamanında devre dışı kaldığını
  /// gösteren libmpv günlük imzaları (küçük harfe indirgenmiş satırda aranır).
  static bool _looksLikeDvFailure(String lower) {
    if (lower.contains('disabling filter')) return true;
    if (lower.contains('impossible to convert')) return true;
    if (lower.contains('error configuring filter')) return true;
    if (lower.contains('vulkan') &&
        (lower.contains('failed') ||
            lower.contains('error') ||
            lower.contains('could not') ||
            lower.contains('cannot'))) {
      return true;
    }
    if (lower.contains('libplacebo') &&
        (lower.contains('failed') || lower.contains('error'))) {
      return true;
    }
    if (lower.contains('lavfi') &&
        (lower.contains('failed') || lower.contains('error'))) {
      return true;
    }
    return false;
  }

  void _setDvReshapeStatus(DvReshapeStatus status) {
    if (dvReshapeStatus == status) return;
    dvReshapeStatus = status;
    onDvReshapeStatusChanged?.call();
  }

  /// HDR hedefini ve kare biçimine göre zorunlu `hwdownload` önekini
  /// seçer; önek kuralları [dvReshapeFilterSdr] belgesinde.
  String _dvReshapeFilterFor(HdrMode mode, {bool forceSoftware = false}) {
    final sdr = mode == HdrMode.sdr;
    if (hardwareDecoding && !forceSoftware) {
      return sdr ? dvReshapeFilterSdr : dvReshapeFilterHdr;
    }
    return sdr ? dvReshapeFilterSdrSoftware : dvReshapeFilterHdrSoftware;
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

  /// Donanım kod çözmeyi açar veya kapatır (yazılım). mpv bu özelliğin
  /// çalışma zamanında değişmesini destekler. Açık değer Android'de `auto`
  /// (auto-safe'in güvenli listesi bazı TV box çiplerinde donanım yolunu
  /// kaçırıyor), diğer platformlarda `auto-safe`.
  ///
  /// DV reshape filtresi etkinken kip değişimi kare biçimini değiştirir
  /// (donanım↔yazılım); filtre doğru `hwdownload` varyantıyla yeniden
  /// uygulanır, yoksa lavfi grafı yeni biçimde yapılandırılamaz.
  Future<void> setHardwareDecoding(bool enabled) async {
    await _backend.setProperty('hwdec', enabled ? hwdecEnabledValue : 'no');
    hardwareDecoding = enabled;
    if (dolbyVisionReshaping) {
      await setDolbyVisionReshaping(true);
    }
  }

  /// Donanım kod çözme açıkken kullanılan libmpv `hwdec` değeri.
  static String get hwdecEnabledValue =>
      defaultTargetPlatform == TargetPlatform.android ? 'auto' : 'auto-safe';

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

  Future<void> applyStreamingTransportProfile() async {
    await _applyPropertiesWithReadback(streamingTransportProfile);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _applyPropertiesWithReadback(androidPerformanceProfile);
    }
  }

  Future<String> engineVersion() async {
    final value = (await _backend.getProperty('mpv-version')).trim();
    return value.isEmpty ? 'libmpv' : value;
  }

  /// Yalnız entegrasyon testleri içindir: ham libmpv özellik okuması.
  @visibleForTesting
  Future<String> debugGetProperty(String name) => _backend.getProperty(name);

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

  Future<void> setSubtitleColor(String value) async {
    final normalized = value.trim().toUpperCase();
    if (!_subtitleColorPattern.hasMatch(normalized)) {
      throw ArgumentError.value(value, 'value', 'Altyazı rengi');
    }
    await _backend.setProperty('sub-color', normalized);
    subtitleColor = normalized;
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
    // Önceki içerikten kalan DV filtresi yeni içeriğe taşmasın.
    await setDolbyVisionReshaping(false);
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
