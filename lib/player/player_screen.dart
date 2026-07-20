import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../settings/provider_settings.dart';
import '../src/rust/api/streaming.dart';
import 'advanced_playback_controller.dart';
import 'gyuni_player_controls.dart';
import 'media_preferences.dart';
import 'picture_in_picture_window.dart';
import 'playback_startup_guard.dart';
import 'player_keyboard_controls.dart';
import 'smart_canvas.dart';
import 'smart_canvas_overlay.dart';
import 'subtitle_controls_overlay.dart';

/// Seçilen NZB'yi Rust localhost server üzerinden media_kit ile oynatır.
///
/// Akış: güvenli depodan sağlayıcı bilgisi → `startStream` (Rust server'ı
/// ayağa kaldırıp URL döndürür) → media_kit `Player.open(url)`. Seek,
/// player'ın kendi kontrolüyle yapılır; server Range isteklerini karşılar.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.nzbPath,
    this.store,
    this.preferenceStore,
    this.pictureInPictureWindow,
    this.startupTimeout = const Duration(seconds: 45),
    this.streamPreparationTimeout = const Duration(seconds: 90),
  });

  final String nzbPath;

  /// Testlerde sahte depo enjekte etmek için; null ise gerçek depo kullanılır.
  final ProviderSettingsStore? store;

  /// Dosyaya özgü, sır içermeyen görüntü ve kontrol tercihleri.
  final MediaPreferencesStore? preferenceStore;

  /// Yerel pencere davranışını testlerde ayırmak için.
  final PictureInPictureWindow? pictureInPictureWindow;

  /// libmpv video izini tanıyamazsa sonsuz spinner yerine hata gösterilir.
  final Duration startupTimeout;

  /// Çok ciltli STORE arşivlerinde cilt boyutlarının tek güvenli NNTP
  /// bağlantısıyla öğrenilmesi için tanınan süre. Demux/video süresi yukarıdaki
  /// daha kısa zaman aşımından ayrı tutulur.
  final Duration streamPreparationTimeout;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver
    implements PlayerKeyboardHandler {
  static const _minimumCanvasExtent =
      1 / AdvancedPlaybackController.maximumZoom;

  late final Player _player;
  late final VideoController _videoController;
  late final AdvancedPlaybackController _playback;
  late final PictureInPictureWindow _pictureInPictureWindow;
  late final PlaybackStartupGuard _startupGuard;
  late final MediaPreferencesStore _preferenceStore;

  final _videoKey = GlobalKey<VideoState>();
  final _playButtonFocusNode = FocusNode(debugLabel: 'Oynat/Duraklat düğmesi');
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _playerErrorSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _bufferingPercentageSubscription;
  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  StreamSubscription<double>? _volumeSubscription;

  // Başlangıç değerleri didChangeDependencies'te yerelleştirilir; alan
  // başlatıcılarında yerelleştirilmiş değere erişilemez.
  String _status = '';
  String _engineStatus = '';
  StreamInfo? _info;
  StreamInfo? _nativeStream;
  BigInt? _pendingSessionId;
  Object? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _seekStep = const Duration(seconds: 1);
  Duration? _previewPosition;
  Uint8List? _previewImage;
  double _rate = 1.0;
  double _zoom = 1.0;
  double _subtitleScale = 1.0;
  double _subtitlePosition = 100.0;
  Duration _subtitleDelay = Duration.zero;
  Duration _audioDelay = Duration.zero;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  bool _controlBusy = false;
  bool _disposing = false;
  bool _isPictureInPicture = false;
  bool _controlsVisible = true;
  bool _playing = false;
  bool _scrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  bool _subtitleControlsVisible = false;
  bool _canvasEditing = false;
  bool _periodicInfoVisible = false;
  CanvasCrop _canvasDraft = const CanvasCrop.full();
  CanvasCrop _canvasCommitted = const CanvasCrop.full();
  bool _startupActive = false;
  bool _startupFailed = false;
  bool _playbackReady = false;
  HdrMode _hdrMode = HdrMode.sdr;
  bool _hardwareDecoding = true;
  bool _buffering = false;
  double _bufferingPercentage = 0.0;
  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;
  int? _seekFlashDirection;

  Timer? _controlsTimer;
  Timer? _seekFlashTimer;
  Timer? _periodicInfoTimer;
  Timer? _periodicInfoHideTimer;
  Timer? _previewDebounce;
  Timer? _previewDismissTimer;
  Timer? _fastScanTimer;
  Timer? _preferencePersistTimer;
  Duration? _queuedPreviewTarget;
  bool _previewCaptureRunning = false;
  int _scrubGeneration = 0;
  Future<void>? _previewDrainFuture;
  CanvasCrop? _queuedCanvasCrop;
  bool _canvasUpdateRunning = false;
  Future<void>? _canvasDrainFuture;
  int _canvasGeneration = 0;
  int _fastScanDirection = 0;
  Future<void>? _fastScanSeekFuture;
  Future<void> _controlTail = Future<void>.value();
  Future<void> _preferenceWriteTail = Future<void>.value();
  int _pendingControlCount = 0;
  bool _preferencePersistPending = false;
  final LinkedHashMap<int, Uint8List> _thumbnailCache =
      LinkedHashMap<int, Uint8List>();
  MediaPreferences _preferences = MediaPreferences.defaults();

  final Map<int, Offset> _touchPoints = <int, Offset>{};
  double? _pinchStartDistance;
  double _pinchStartZoom = 1.0;
  double _trackpadStartZoom = 1.0;
  double? _queuedZoom;
  bool _zoomUpdateRunning = false;
  Future<void>? _zoomDrainFuture;
  bool _canvasOpening = false;
  double? _queuedSubtitleScale;
  double? _queuedSubtitlePosition;
  Duration? _queuedSubtitleDelay;
  bool _subtitleUpdateRunning = false;
  Future<void>? _subtitleDrainFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Zanzibarr',
        // Desteklenen altyazıları libmpv'nin yerel video yüzeyinde işler;
        // Flutter metin katmanına bağımlı kalmaz.
        libass: true,
      ),
    );
    _videoController = VideoController(
      _player,
      // Android'de (TV box'lar) auto-safe'in güvenli listesi bazı cihazlarda
      // donanım çözücüyü devreye almıyor; 4K içerik yazılıma düşünce görüntü
      // sesin gerisinde kalıyor. auto tüm donanım yollarını dener.
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: defaultTargetPlatform == TargetPlatform.android
            ? 'auto'
            : 'auto-safe',
      ),
    );
    _playback = AdvancedPlaybackController(MediaKitPlaybackBackend(_player));
    _pictureInPictureWindow =
        widget.pictureInPictureWindow ?? NativePictureInPictureWindow();
    _preferenceStore = widget.preferenceStore ?? MediaPreferencesStore();
    _startupGuard = PlaybackStartupGuard(widget.startupTimeout);
    _positionSubscription = _player.stream.position.listen((position) {
      if (!mounted || _scrubbing) return;
      setState(() => _position = position);
    });
    _durationSubscription = _player.stream.duration.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _playing = playing);
      _revealControls();
    });
    // open() yalnız libmpv komutunun kabulünü bekler. Demux/decode ve HTTP
    // hataları daha sonra bu stream'lerden gelir; bu nedenle open'dan önce
    // abone olmak zorundayız.
    _playerErrorSubscription = _player.stream.error.listen(_onPlayerError);
    _bufferingSubscription = _player.stream.buffering.listen(_onBuffering);
    _bufferingPercentageSubscription = _player.stream.bufferingPercentage
        .listen(_onBufferingPercentage);
    _widthSubscription = _player.stream.width.listen(_onVideoWidth);
    _tracksSubscription = _player.stream.tracks.listen(_onTracks);
    _trackSubscription = _player.stream.track.listen((track) {
      if (!mounted) return;
      setState(() => _track = track);
    });
    _volumeSubscription = _player.stream.volume.listen((volume) {
      if (!mounted) return;
      setState(() {
        _volume = volume;
        if (volume > 0.5) _lastNonZeroVolume = volume;
      });
    });
    unawaited(_start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Alan başlatıcılarında context yok; ilk yerelleştirilmiş durum metinleri
    // burada, _start'ın ilk await'i tamamlanmadan önce yazılır.
    if (_status.isEmpty) _status = AppLocalizations.of(context).statusPreparing;
    if (_engineStatus.isEmpty) {
      _engineStatus = AppLocalizations.of(context).engineBadgePreparing;
    }
  }

  Future<void> _start() async {
    try {
      await _configureNativeEngine();
      await _loadPreferences();

      final store = widget.store ?? ProviderSettingsStore();
      final settings = await store.load();
      if (!settings.isComplete) {
        if (!mounted) return;
        setState(
          () => _error = AppLocalizations.of(
            context,
          ).errorProviderSettingsMissing,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _startupActive = true;
        _status = AppLocalizations.of(context).statusConnecting;
      });
      _startupGuard.arm(
        _onStartupTimeout,
        after: widget.streamPreparationTimeout,
      );

      final sessionId = await beginStream(
        config: ProviderConfigDto(
          host: settings.host,
          port: settings.port,
          username: settings.username,
          password: settings.password,
          maxConnections: settings.maxConnections,
        ),
        nzbPath: widget.nzbPath,
      );
      _pendingSessionId = sessionId;

      if (!mounted || _startupFailed) {
        await _releaseNativeStream();
        return;
      }

      final info = await awaitStream(sessionId: sessionId);
      _pendingSessionId = null;
      _nativeStream = info;

      if (!mounted || _startupFailed) {
        await _releaseNativeStream();
        return;
      }
      await _playback.resetForNewMedia();
      await _applyPreferencesToPlayer();
      if (!mounted || _startupFailed) return;
      setState(() {
        _info = info;
        _rate = _playback.rate;
        _zoom = _playback.zoom;
        _startupActive = true;
        _status = AppLocalizations.of(
          context,
        ).statusReadingVideoStructure(info.filename);
      });
      _startupGuard.arm(_onStartupTimeout);
      await _player.open(Media(info.url));

      if (!mounted || _startupFailed) return;
      // Stream olayı open() future'undan hemen önce gelmişse state'i de
      // kontrol ederek readiness olayını kaçırmayız.
      _onVideoWidth(_player.state.width);
      _onTracks(_player.state.tracks);
    } catch (error) {
      await _releaseNativeStream();
      if (_startupFailed) return;
      _startupGuard.cancel();
      _startupActive = false;
      _startupFailed = true;
      if (!mounted) return;
      setState(() => _error = describeStreamStartupError(error));
    }
  }

  void _onVideoWidth(int? width) {
    if (width != null && width > 0) _markPlaybackReady();
  }

  void _onTracks(Tracks tracks) {
    if (mounted) setState(() => _tracks = tracks);
    final hasRealVideo = tracks.video.any(
      (track) => track.id != 'auto' && track.id != 'no',
    );
    if (hasRealVideo) {
      _markPlaybackReady();
      unawaited(_applyDolbyVisionReshapingIfNeeded());
    }
  }

  /// Dolby Vision Profile 5 (HDR10 baz katmansız) içerikte pembe/yeşil
  /// bozuk renkleri düzeltmek için paketli FFmpeg'in libplacebo filtresini
  /// devreye alır. HDR10 baz katmanı taşıyan profillerde (P8 gibi) mevcut
  /// render yolu doğru çalıştığından filtre kapalı kalır.
  Future<void> _applyDolbyVisionReshapingIfNeeded() async {
    try {
      final capabilities = await _playback.detectHdrCapabilities();
      await _playback.setDolbyVisionReshaping(
        capabilities.dolbyVisionProfile == 5,
      );
    } catch (_) {
      // Algılama başarısızsa oynatma mevcut davranışla sürer.
    }
  }

  void _markPlaybackReady() {
    if (!_startupActive || _startupFailed || _playbackReady) return;
    _startupGuard.cancel();
    _startupActive = false;
    _playbackReady = true;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _status = _buffering
          ? l10n.statusBuffering(_info?.filename ?? 'video')
          : l10n.statusPlaying(_info?.filename ?? 'video');
    });
    _configurePeriodicInfoTimer();
    _revealControls();
  }

  /// Yalnız entegrasyon testleri içindir: oynatma hazır mı, açılış hatası
  /// neydi ve motor denetçisinin (DV reshape bayrağı, vf okuması) durumu.
  @visibleForTesting
  bool get playbackReadyForTest => _playbackReady;

  @visibleForTesting
  Object? get startupErrorForTest => _error;

  @visibleForTesting
  AdvancedPlaybackController get playbackControllerForTest => _playback;

  /// Entegrasyon testlerinin libmpv günlük akışına (lavfi/Vulkan hataları
  /// gibi çalışma zamanı tanıları) abone olabilmesi için oynatıcıyı verir.
  @visibleForTesting
  Player get playerForTest => _player;

  void _onPlayerError(String message) {
    if (!_startupActive && !_playbackReady) return;
    final description = describePlayerError(message);
    if (!_playbackReady) {
      _failStartup(description);
      return;
    }
    if (!mounted) return;
    setState(() => _status = description);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(description),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _onBuffering(bool buffering) {
    _buffering = buffering;
    if (!mounted || _startupFailed || _info == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      if (_playbackReady) {
        _status = buffering
            ? l10n.statusBuffering(_info!.filename)
            : l10n.statusPlaying(_info!.filename);
      } else if (_startupActive) {
        _status = buffering
            ? _startupBufferingMessage()
            : l10n.statusWaitingTracks(_info!.filename);
      }
    });
  }

  void _onBufferingPercentage(double percentage) {
    _bufferingPercentage = percentage.clamp(0.0, 100.0).toDouble();
    if (!mounted || !_startupActive || _startupFailed || _info == null) return;
    setState(() => _status = _startupBufferingMessage());
  }

  String _startupBufferingMessage() {
    final l10n = AppLocalizations.of(context);
    final progress = _bufferingPercentage > 0 && _bufferingPercentage < 100
        ? l10n.bufferingPercent(_bufferingPercentage.toStringAsFixed(0))
        : '';
    return l10n.statusStartingVideo(progress, _info?.filename ?? 'video');
  }

  void _onStartupTimeout() {
    if (!_startupActive || _startupFailed || _playbackReady) return;
    if (_info == null) {
      _failStartup(
        AppLocalizations.of(
          context,
        ).errorStreamStartTimeout(widget.streamPreparationTimeout.inSeconds),
      );
      return;
    }
    _failStartup(
      AppLocalizations.of(
        context,
      ).errorVideoDetectTimeout(widget.startupTimeout.inSeconds),
    );
  }

  void _failStartup(String message) {
    if (_startupFailed || _playbackReady) return;
    _startupGuard.cancel();
    _startupActive = false;
    _startupFailed = true;
    if (!mounted) return;
    setState(() {
      _status = message;
      _error = message;
    });
    unawaited(_player.stop());
    unawaited(_releaseNativeStream());
  }

  /// Rust tarafındaki localhost server yalnız bu ekranın session kimliğiyle
  /// kapatılır. Böylece eski bir ekranın gecikmiş dispose'u daha yeni bir
  /// oynatıcı oturumunu yanlışlıkla durduramaz.
  Future<void> _releaseNativeStream() async {
    final sessionId = _nativeStream?.sessionId ?? _pendingSessionId;
    _nativeStream = null;
    _pendingSessionId = null;
    if (sessionId == null) return;
    try {
      await stopStream(sessionId: sessionId);
    } catch (_) {
      // Ekran kapanırken temizlik hatası kullanıcı akışını engellememeli.
    }
  }

  Future<void> _configureNativeEngine() async {
    var engineVersion = 'libmpv';
    var streamingReady = false;
    var hdrReady = false;
    var scalerReady = false;
    try {
      engineVersion = await _playback.engineVersion();
    } catch (_) {
      // Sürüm bilgisi görsel bir ayrıntıdır; oynatmayı engellemez.
    }
    try {
      await _playback.applyStreamingTransportProfile();
      streamingReady = true;
    } catch (_) {
      // Eski backend'de profil yoksa açılış yine varsayılanlarla sürebilir.
    }
    try {
      // Varsayılan güvenli yol: HDR içerik SDR'e ton eşlenir; kullanıcı
      // diyalogdan HDR modu seçince doğal sinyale geçilir.
      await _playback.setHdrMode(HdrMode.sdr);
      hdrReady = true;
    } catch (_) {
      // SDR oynatma, HDR profili desteklenmeyen eski libmpv'de sürer.
    }
    try {
      await _playback.setUpscalingPreset(UpscalingPreset.balanced);
      scalerReady = true;
    } catch (_) {
      // Bundled GPU backend scaler readback sunmuyorsa kendi güvenli varsayılanı.
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _hdrMode = HdrMode.sdr;
      _engineStatus = [
        engineVersion,
        'GPU render',
        'HW decode auto-safe',
        if (streamingReady) l10n.engineBadgeDiskCacheOff,
        if (hdrReady) 'BT.2390 + peak detect' else l10n.engineBadgeSdrSafePath,
        if (scalerReady) 'Spline36 upscale',
      ].join(' · ');
    });
  }

  Future<void> _loadPreferences() async {
    final preferences = await _preferenceStore.load(widget.nzbPath);
    _preferences = preferences;
    _canvasCommitted = CanvasCrop(
      left: preferences.crop.left,
      top: preferences.crop.top,
      right: preferences.crop.right,
      bottom: preferences.crop.bottom,
    );
    _canvasDraft = _canvasCommitted;
    _seekStep = Duration(seconds: preferences.seekStepSeconds);
    _subtitleScale = preferences.subtitleScale
        .clamp(
          AdvancedPlaybackController.minimumSubtitleScale,
          AdvancedPlaybackController.maximumSubtitleScale,
        )
        .toDouble();
    _subtitlePosition = preferences.subtitlePosition
        .clamp(
          AdvancedPlaybackController.minimumSubtitlePosition,
          AdvancedPlaybackController.maximumSubtitlePosition,
        )
        .toDouble();
    _subtitleDelay = Duration(
      microseconds:
          (preferences.subtitleDelaySeconds * Duration.microsecondsPerSecond)
              .round(),
    );
    _audioDelay = Duration(
      microseconds:
          (preferences.audioDelaySeconds * Duration.microsecondsPerSecond)
              .round(),
    );
  }

  Future<void> _applyPreferencesToPlayer() async {
    await _tryNativePreference(
      () => _playback.setVideoPreset(
        _videoPresetFromName(_preferences.videoPreset),
      ),
    );
    await _tryNativePreference(
      () => _playback.setUpscalingPreset(
        _upscalingPresetFromName(_preferences.upscalePreset),
      ),
    );
    await _tryNativePreference(
      () => _playback.setAudioPreset(
        _audioPresetFromName(_preferences.audioPreset),
      ),
    );
    await _tryNativePreference(
      () => _playback.setSubtitleScale(_subtitleScale),
    );
    await _tryNativePreference(
      () => _playback.setSubtitlePosition(_subtitlePosition),
    );
    await _tryNativePreference(
      () => _playback.setSubtitleDelay(
        _clampDuration(
          _subtitleDelay,
          AdvancedPlaybackController.maximumSubtitleDelay,
        ),
      ),
    );
    await _tryNativePreference(
      () => _playback.setAudioDelay(
        _clampDuration(
          _audioDelay,
          AdvancedPlaybackController.maximumAudioDelay,
        ),
      ),
    );

    final crop = _preferences.crop;
    final derivedZoom = math
        .max(1 / crop.width, 1 / crop.height)
        .clamp(
          AdvancedPlaybackController.minimumZoom,
          AdvancedPlaybackController.maximumZoom,
        );
    final derivedPanX = _preferences.pan == NormalizedVector2.center
        ? ((0.5 - (crop.left + crop.right) / 2) * 2).clamp(-1.0, 1.0)
        : _preferences.pan.x;
    final derivedPanY = _preferences.pan == NormalizedVector2.center
        ? ((0.5 - (crop.top + crop.bottom) / 2) * 2).clamp(-1.0, 1.0)
        : _preferences.pan.y;
    await _tryNativePreference(
      () => _playback.applyCanvasTransform(
        aspectRatio: _preferences.aspectRatio,
        zoom: derivedZoom.toDouble(),
        panX: derivedPanX.toDouble(),
        panY: derivedPanY.toDouble(),
      ),
    );
    _zoom = _playback.zoom;
  }

  Future<void> _tryNativePreference(Future<void> Function() apply) async {
    try {
      await apply();
    } catch (_) {
      // Tek bir opsiyon desteklenmiyorsa medya açılışını engelleme.
    }
  }

  Future<void> _persistPreferences() async {
    final preferences = MediaPreferences(
      crop: _preferences.crop,
      aspectRatio: _playback.aspectRatioOverride,
      alignment: _preferences.alignment,
      pan: NormalizedVector2(x: _playback.videoPanX, y: _playback.videoPanY),
      seekStepSeconds: _seekStep.inSeconds,
      periodicInfoInterval: _preferences.periodicInfoInterval,
      videoPreset: _playback.videoPreset.name,
      audioPreset: _playback.audioPreset.name,
      upscalePreset: _upscalingPresetStorageName(_playback.upscalingPreset),
      subtitleScale: _subtitleScale,
      subtitlePosition: _subtitlePosition,
      subtitleDelaySeconds:
          _subtitleDelay.inMicroseconds / Duration.microsecondsPerSecond,
      audioDelaySeconds:
          _audioDelay.inMicroseconds / Duration.microsecondsPerSecond,
    );
    _preferences = preferences;
    final write = _preferenceWriteTail.then((_) async {
      try {
        await _preferenceStore.save(widget.nzbPath, preferences);
      } catch (_) {
        // Oynatma tercihi kaydedilemezse medya akışı kesilmemeli.
      }
    });
    _preferenceWriteTail = write;
    await write;
  }

  void _schedulePreferencePersist() {
    _preferencePersistPending = true;
    _preferencePersistTimer?.cancel();
    _preferencePersistTimer = Timer(const Duration(milliseconds: 280), () {
      _preferencePersistPending = false;
      if (!_disposing) unawaited(_persistPreferences());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposing = true;
    _scrubGeneration++;
    _canvasGeneration++;
    _queuedPreviewTarget = null;
    _queuedCanvasCrop = null;
    _queuedZoom = null;
    _queuedSubtitleScale = null;
    _queuedSubtitlePosition = null;
    _queuedSubtitleDelay = null;
    _startupGuard.dispose();
    _playButtonFocusNode.dispose();
    _controlsTimer?.cancel();
    _seekFlashTimer?.cancel();
    _periodicInfoTimer?.cancel();
    _periodicInfoHideTimer?.cancel();
    _previewDebounce?.cancel();
    _previewDismissTimer?.cancel();
    _fastScanTimer?.cancel();
    _preferencePersistTimer?.cancel();
    if (_preferencePersistPending) {
      _preferencePersistPending = false;
      unawaited(_persistPreferences());
    }
    final subscriptions = <StreamSubscription<dynamic>?>[
      _positionSubscription,
      _durationSubscription,
      _playingSubscription,
      _playerErrorSubscription,
      _bufferingSubscription,
      _bufferingPercentageSubscription,
      _widthSubscription,
      _tracksSubscription,
      _trackSubscription,
      _volumeSubscription,
    ];
    unawaited(_disposeResources(subscriptions));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_endFastScan());
      _touchPoints.clear();
      _pinchStartDistance = null;
    }
  }

  Future<void> _disposeResources(
    List<StreamSubscription<dynamic>?> subscriptions,
  ) async {
    await Future.wait([
      for (final subscription in subscriptions)
        if (subscription != null) subscription.cancel(),
    ]);
    try {
      await _controlTail.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Kapanış, kuyruğa alınmış bir görsel ayarı sonsuza kadar beklememeli.
    }
    try {
      await _subtitleDrainFuture?.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Son altyazı sürükleme komutu kapanışı engellememeli.
    }
    try {
      await _zoomDrainFuture?.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Devam eden son pinch yazımı kapanışı engellememeli.
    }
    try {
      await _preferenceWriteTail.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Tercih deposu kapanışı engellememeli.
    }
    if (_isPictureInPicture) await _pictureInPictureWindow.exit();
    try {
      await _player.stop();
    } catch (_) {
      // Player daha açılmadan kapanmış olabilir.
    }
    await _releaseNativeStream();
    await _player.dispose();
  }

  Future<bool> _runControl(
    Future<void> Function() action, {
    VoidCallback? onSuccess,
  }) {
    if (_disposing) return Future<bool>.value(false);
    final result = Completer<bool>();
    _pendingControlCount++;
    if (mounted && !_controlBusy) setState(() => _controlBusy = true);
    _controlTail = _controlTail.then((_) async {
      if (_disposing) {
        _pendingControlCount--;
        result.complete(false);
        return;
      }
      try {
        await action();
        if (mounted && onSuccess != null) setState(onSuccess);
        result.complete(true);
      } catch (error) {
        if (mounted) _showControlError(error);
        result.complete(false);
      } finally {
        _pendingControlCount--;
        if (mounted && _pendingControlCount == 0) {
          setState(() => _controlBusy = false);
        }
      }
    });
    return result.future;
  }

  Future<void> _setRate(double value) async {
    await _runControl(
      () => _playback.setRate(value),
      onSuccess: () => _rate = _playback.rate,
    );
  }

  Future<void> _setLoopStart() async {
    await _runControl(() => _playback.setLoopStart(_position));
  }

  Future<void> _setLoopEnd() async {
    await _runControl(() => _playback.setLoopEnd(_position));
  }

  Future<void> _clearLoop() async {
    await _runControl(_playback.clearLoop);
  }

  Future<void> _stepBackward() async {
    await _runControl(_playback.stepBackward);
  }

  Future<void> _stepForward() async {
    await _runControl(_playback.stepForward);
  }

  Future<void> _togglePlay() async {
    if (!_playbackReady) return;
    _revealControls();
    try {
      await _player.playOrPause();
    } catch (error) {
      _showControlError(error);
    }
  }

  Future<void> _seekRelative(Duration offset, {bool exact = true}) async {
    if (!_playbackReady) return;
    _revealControls();
    try {
      await _playback.seekRelative(offset, exact: exact);
    } catch (error) {
      _showControlError(error);
    }
  }

  void _onVolumeChanged(double value) {
    final clamped = value.clamp(0.0, 100.0);
    if (clamped > 0.5) _lastNonZeroVolume = clamped;
    unawaited(_player.setVolume(clamped));
  }

  void _toggleMute() {
    _revealControls();
    if (_volume > 0.5) {
      _lastNonZeroVolume = _volume;
      unawaited(_player.setVolume(0));
    } else {
      unawaited(_player.setVolume(_lastNonZeroVolume));
    }
  }

  /// YouTube tarzı çift tık bölgesi: sabit ±10 saniye atlama ve kısa bir
  /// ekran geri bildirimi.
  void _flashSeek(int direction) {
    unawaited(_seekRelative(Duration(seconds: 10 * direction)));
    _seekFlashTimer?.cancel();
    setState(() => _seekFlashDirection = direction);
    _seekFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlashDirection = null);
    });
  }

  /// Masaüstünde tek tık oynat/duraklat demektir (YouTube davranışı);
  /// dokunmatik ana platformlarda tek dokunma kontrolleri gösterir/gizler.
  bool get _touchPrimary =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> _selectSubtitle(SubtitleTrack track) async {
    try {
      await _player.setSubtitleTrack(track);
      if (mounted) setState(() => _track = _track.copyWith(subtitle: track));
    } catch (error) {
      _showControlError(error);
    }
  }

  Future<void> _selectAudio(AudioTrack track) async {
    try {
      await _player.setAudioTrack(track);
      if (mounted) setState(() => _track = _track.copyWith(audio: track));
    } catch (error) {
      _showControlError(error);
    }
  }

  /// İçeriğin gömülü altyazılarına ek olarak kullanıcının diskinden altyazı
  /// (srt/ass/vtt…) yükler. libmpv izi mevcut oynatmaya ekler.
  Future<void> _loadExternalSubtitle() async {
    try {
      final typeGroup = XTypeGroup(
        label: AppLocalizations.of(context).fileTypeSubtitles,
        extensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      final path = file?.path;
      if (file == null || path == null || path.isEmpty) return;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(path, title: file.name),
      );
    } catch (error) {
      _showControlError(error);
    }
  }

  /// İçeriğin gömülü ses izlerine ek olarak kullanıcının diskinden harici
  /// ses dosyası (ac3/dts/mka…) yükler.
  Future<void> _loadExternalAudio() async {
    try {
      final typeGroup = XTypeGroup(
        label: AppLocalizations.of(context).fileTypeAudioFiles,
        extensions: const [
          'mp3',
          'aac',
          'ac3',
          'eac3',
          'dts',
          'dtshd',
          'flac',
          'ogg',
          'opus',
          'mka',
          'wav',
          'm4a',
        ],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      final path = file?.path;
      if (file == null || path == null || path.isEmpty) return;
      await _player.setAudioTrack(AudioTrack.uri(path, title: file.name));
    } catch (error) {
      _showControlError(error);
    }
  }

  void _queueSubtitleScale(double value) {
    final clamped = value
        .clamp(
          AdvancedPlaybackController.minimumSubtitleScale,
          AdvancedPlaybackController.maximumSubtitleScale,
        )
        .toDouble();
    _queuedSubtitleScale = clamped;
    if (mounted) setState(() => _subtitleScale = clamped);
    _startSubtitleDrain();
  }

  void _queueSubtitlePosition(double value) {
    final clamped = value
        .clamp(
          AdvancedPlaybackController.minimumSubtitlePosition,
          AdvancedPlaybackController.maximumSubtitlePosition,
        )
        .toDouble();
    _queuedSubtitlePosition = clamped;
    if (mounted) setState(() => _subtitlePosition = clamped);
    _startSubtitleDrain();
  }

  void _queueSubtitleDelay(Duration value) {
    final clamped = _clampDuration(
      value,
      AdvancedPlaybackController.maximumSubtitleDelay,
    );
    _queuedSubtitleDelay = clamped;
    if (mounted) setState(() => _subtitleDelay = clamped);
    _startSubtitleDrain();
  }

  bool get _hasQueuedSubtitleUpdate =>
      _queuedSubtitleScale != null ||
      _queuedSubtitlePosition != null ||
      _queuedSubtitleDelay != null;

  void _startSubtitleDrain() {
    if (_disposing || _subtitleUpdateRunning || !_hasQueuedSubtitleUpdate) {
      return;
    }
    _subtitleUpdateRunning = true;
    final drain = _runControl(_drainSubtitleUpdates);
    _subtitleDrainFuture = drain.then<void>((_) {}).whenComplete(() {
      _subtitleUpdateRunning = false;
      _subtitleDrainFuture = null;
      if (!_disposing && _hasQueuedSubtitleUpdate) _startSubtitleDrain();
    });
  }

  Future<void> _drainSubtitleUpdates() async {
    var applied = false;
    try {
      while (!_disposing && _hasQueuedSubtitleUpdate) {
        final scale = _queuedSubtitleScale;
        if (scale != null) {
          _queuedSubtitleScale = null;
          try {
            await _playback.setSubtitleScale(scale);
            applied = true;
          } catch (_) {
            if (_queuedSubtitleScale == null && mounted) {
              setState(() => _subtitleScale = _playback.subtitleScale);
            }
            rethrow;
          }
          continue;
        }

        final position = _queuedSubtitlePosition;
        if (position != null) {
          _queuedSubtitlePosition = null;
          try {
            await _playback.setSubtitlePosition(position);
            applied = true;
          } catch (_) {
            if (_queuedSubtitlePosition == null && mounted) {
              setState(() => _subtitlePosition = _playback.subtitlePosition);
            }
            rethrow;
          }
          continue;
        }

        final delay = _queuedSubtitleDelay;
        if (delay != null) {
          _queuedSubtitleDelay = null;
          try {
            await _playback.setSubtitleDelay(delay);
            applied = true;
          } catch (_) {
            if (_queuedSubtitleDelay == null && mounted) {
              setState(() => _subtitleDelay = _playback.subtitleDelay);
            }
            rethrow;
          }
        }
      }
    } finally {
      if (applied && !_disposing) _schedulePreferencePersist();
    }
  }

  Future<void> _setAudioDelay(Duration value) async {
    final clamped = _clampDuration(
      value,
      AdvancedPlaybackController.maximumAudioDelay,
    );
    final applied = await _runControl(
      () => _playback.setAudioDelay(clamped),
      onSuccess: () => _audioDelay = _playback.audioDelay,
    );
    if (applied) _schedulePreferencePersist();
  }

  void _toggleSubtitleControls() {
    if (_canvasEditing) {
      unawaited(_cancelCanvasAndOpenSubtitles());
      return;
    }
    setState(() {
      _subtitleControlsVisible = !_subtitleControlsVisible;
    });
    _revealControls();
  }

  Future<void> _cancelCanvasAndOpenSubtitles() async {
    await _cancelCanvasEditing();
    if (!mounted || _disposing) return;
    setState(() => _subtitleControlsVisible = true);
    _revealControls();
  }

  void _toggleCanvasEditor() {
    if (_canvasEditing) {
      unawaited(_cancelCanvasEditing());
      return;
    }
    unawaited(_openCanvasEditor());
  }

  Future<void> _openCanvasEditor() async {
    if (_canvasOpening || _disposing) return;
    _canvasOpening = true;
    _queuedZoom = null;
    final pendingZoom = _zoomDrainFuture;
    if (pendingZoom != null) await pendingZoom;
    if (!mounted || _disposing) {
      _canvasOpening = false;
      return;
    }
    setState(() {
      _canvasDraft = _canvasCommitted;
      _canvasEditing = true;
      _subtitleControlsVisible = false;
    });
    _canvasOpening = false;
    _revealControls();
  }

  void _previewCanvas(CanvasCrop crop) {
    final safe = clampCanvasCrop(crop, minimumExtent: _minimumCanvasExtent);
    setState(() => _canvasDraft = safe);
    _queuedCanvasCrop = safe;
    if (!_canvasUpdateRunning) {
      final drain = _drainCanvasUpdates();
      _canvasDrainFuture = drain;
      unawaited(drain);
    }
  }

  Future<void> _drainCanvasUpdates() async {
    _canvasUpdateRunning = true;
    try {
      while (_queuedCanvasCrop != null && mounted) {
        final crop = _queuedCanvasCrop!;
        _queuedCanvasCrop = null;
        await _applyCanvasCrop(crop);
      }
    } catch (error) {
      _showControlError(error);
    } finally {
      _canvasUpdateRunning = false;
      _canvasDrainFuture = null;
      if (_queuedCanvasCrop != null && mounted) {
        final drain = _drainCanvasUpdates();
        _canvasDrainFuture = drain;
        unawaited(drain);
      }
    }
  }

  Future<void> _applyCanvasCrop(CanvasCrop crop) async {
    final safe = clampCanvasCrop(crop, minimumExtent: _minimumCanvasExtent);
    final sourceAspect = _sourceAspectRatio;
    final ratio = canvasCropAspectRatio(safe, sourceAspectRatio: sourceAspect)
        .clamp(
          AdvancedPlaybackController.minimumAspectRatio,
          AdvancedPlaybackController.maximumAspectRatio,
        );
    final zoom = math
        .max(1 / safe.width, 1 / safe.height)
        .clamp(
          AdvancedPlaybackController.minimumZoom,
          AdvancedPlaybackController.maximumZoom,
        );
    final panX = ((0.5 - safe.center.dx) * 2).clamp(-1.0, 1.0);
    final panY = ((0.5 - safe.center.dy) * 2).clamp(-1.0, 1.0);
    await _playback.applyCanvasTransform(
      aspectRatio: ratio.toDouble(),
      zoom: zoom.toDouble(),
      panX: panX.toDouble(),
      panY: panY.toDouble(),
    );
    if (mounted) setState(() => _zoom = _playback.zoom);
  }

  Future<void> _commitCanvas(CanvasCrop crop) async {
    final generation = ++_canvasGeneration;
    _queuedCanvasCrop = null;
    final pending = _canvasDrainFuture;
    if (pending != null) await pending;
    if (_disposing || generation != _canvasGeneration) return;
    final safe = clampCanvasCrop(crop, minimumExtent: _minimumCanvasExtent);
    try {
      await _applyCanvasCrop(safe);
      final ratio =
          canvasCropAspectRatio(safe, sourceAspectRatio: _sourceAspectRatio)
              .clamp(
                AdvancedPlaybackController.minimumAspectRatio,
                AdvancedPlaybackController.maximumAspectRatio,
              )
              .toDouble();
      _canvasCommitted = safe;
      _canvasDraft = safe;
      _preferences = MediaPreferences(
        crop: NormalizedCropRect(
          left: safe.left,
          top: safe.top,
          right: safe.right,
          bottom: safe.bottom,
        ),
        aspectRatio: ratio,
        alignment: _preferences.alignment,
        pan: NormalizedVector2(x: _playback.videoPanX, y: _playback.videoPanY),
        seekStepSeconds: _seekStep.inSeconds,
        periodicInfoInterval: _preferences.periodicInfoInterval,
        videoPreset: _playback.videoPreset.name,
        audioPreset: _playback.audioPreset.name,
        upscalePreset: _upscalingPresetStorageName(_playback.upscalingPreset),
        subtitleScale: _subtitleScale,
        subtitlePosition: _subtitlePosition,
        subtitleDelaySeconds:
            _subtitleDelay.inMicroseconds / Duration.microsecondsPerSecond,
        audioDelaySeconds:
            _audioDelay.inMicroseconds / Duration.microsecondsPerSecond,
      );
      if (mounted) setState(() => _canvasEditing = false);
      await _persistPreferences();
    } catch (error) {
      _showControlError(error);
    }
    _revealControls();
  }

  Future<void> _cancelCanvasEditing() async {
    final generation = ++_canvasGeneration;
    _queuedCanvasCrop = null;
    if (mounted) {
      setState(() {
        _canvasDraft = _canvasCommitted;
        _canvasEditing = false;
      });
    }
    final pending = _canvasDrainFuture;
    if (pending != null) await pending;
    if (_disposing || generation != _canvasGeneration) return;
    try {
      await _applyCanvasCrop(_canvasCommitted);
    } catch (error) {
      _showControlError(error);
    }
    _revealControls();
  }

  Future<void> _resetCanvas() async {
    if (_canvasOpening || _disposing) return;
    _canvasOpening = true;
    try {
      final generation = ++_canvasGeneration;
      _queuedCanvasCrop = null;
      _queuedZoom = null;
      final pendingZoom = _zoomDrainFuture;
      if (pendingZoom != null) await pendingZoom;
      final pending = _canvasDrainFuture;
      if (pending != null) await pending;
      if (_disposing || generation != _canvasGeneration) return;
      const full = CanvasCrop.full();
      await _playback.resetCanvasTransform();
      _canvasCommitted = full;
      _canvasDraft = full;
      _preferences = MediaPreferences(
        crop: NormalizedCropRect.fullFrame,
        seekStepSeconds: _seekStep.inSeconds,
        periodicInfoInterval: _preferences.periodicInfoInterval,
        videoPreset: _playback.videoPreset.name,
        audioPreset: _playback.audioPreset.name,
        upscalePreset: _upscalingPresetStorageName(_playback.upscalingPreset),
        subtitleScale: _subtitleScale,
        subtitlePosition: _subtitlePosition,
        subtitleDelaySeconds:
            _subtitleDelay.inMicroseconds / Duration.microsecondsPerSecond,
        audioDelaySeconds:
            _audioDelay.inMicroseconds / Duration.microsecondsPerSecond,
      );
      if (mounted) setState(() => _zoom = _playback.zoom);
      await _persistPreferences();
    } catch (error) {
      _showControlError(error);
    } finally {
      _canvasOpening = false;
    }
  }

  double get _sourceAspectRatio {
    final width = _player.state.width ?? 0;
    final height = _player.state.height ?? 0;
    return width > 0 && height > 0 ? width / height : 16 / 9;
  }

  void _revealControls() {
    _controlsTimer?.cancel();
    if (mounted && !_controlsVisible) setState(() => _controlsVisible = true);
    if (_playing &&
        !_scrubbing &&
        !_canvasEditing &&
        !_subtitleControlsVisible) {
      _controlsTimer = Timer(const Duration(milliseconds: 2800), () {
        if (!mounted || !_playing || _scrubbing || _canvasEditing) return;
        setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleControlsVisibility() {
    if (!_controlsVisible) {
      _revealControls();
      return;
    }
    if (_playing && !_canvasEditing && !_subtitleControlsVisible) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    }
  }

  void _configurePeriodicInfoTimer() {
    _periodicInfoTimer?.cancel();
    _periodicInfoHideTimer?.cancel();
    if (mounted && _periodicInfoVisible) {
      setState(() => _periodicInfoVisible = false);
    }
    final interval = _preferences.periodicInfoInterval;
    if (interval == null) return;
    _periodicInfoTimer = Timer.periodic(interval, (_) {
      if (!_playbackReady || !_playing || !mounted) return;
      setState(() => _periodicInfoVisible = true);
      _periodicInfoHideTimer?.cancel();
      _periodicInfoHideTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _periodicInfoVisible = false);
      });
    });
  }

  Future<void> _setSeekStep(int seconds) async {
    if (seconds < 1) return;
    setState(() => _seekStep = Duration(seconds: seconds));
    await _persistPreferences();
  }

  Future<void> _setPeriodicInfoInterval(Duration? interval) async {
    _preferences = MediaPreferences(
      crop: _preferences.crop,
      aspectRatio: _preferences.aspectRatio,
      alignment: _preferences.alignment,
      pan: _preferences.pan,
      seekStepSeconds: _seekStep.inSeconds,
      periodicInfoInterval: interval,
      videoPreset: _playback.videoPreset.name,
      audioPreset: _playback.audioPreset.name,
      upscalePreset: _upscalingPresetStorageName(_playback.upscalingPreset),
      subtitleScale: _subtitleScale,
      subtitlePosition: _subtitlePosition,
      subtitleDelaySeconds:
          _subtitleDelay.inMicroseconds / Duration.microsecondsPerSecond,
      audioDelaySeconds:
          _audioDelay.inMicroseconds / Duration.microsecondsPerSecond,
    );
    _configurePeriodicInfoTimer();
    await _persistPreferences();
  }

  void _onScrubStart(Duration target) {
    if (!_playbackReady) return;
    _scrubGeneration++;
    _scrubbing = true;
    _wasPlayingBeforeScrub = _playing;
    unawaited(_player.pause());
    setState(() {
      _position = target;
      _previewPosition = target;
    });
    _queuePreview(target);
  }

  void _onScrubUpdate(Duration target) {
    if (!_scrubbing) return;
    setState(() {
      _position = target;
      _previewPosition = target;
    });
    _queuePreview(target);
  }

  void _onScrubEnd(Duration target) {
    if (!_scrubbing) return;
    _scrubbing = false;
    final generation = ++_scrubGeneration;
    _previewDebounce?.cancel();
    _queuedPreviewTarget = null;
    setState(() {
      _position = target;
      _previewPosition = target;
    });
    unawaited(_finishScrub(target, generation));
  }

  Future<void> _finishScrub(Duration target, int generation) async {
    try {
      final previewDrain = _previewDrainFuture;
      if (previewDrain != null) await previewDrain;
      if (_disposing || generation != _scrubGeneration) return;
      await _player.seek(target);
      if (_wasPlayingBeforeScrub) await _player.play();
    } catch (error) {
      _showControlError(error);
    } finally {
      _previewDismissTimer?.cancel();
      _previewDismissTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted && !_scrubbing) {
          setState(() {
            _previewPosition = null;
            _previewImage = null;
          });
        }
      });
      _revealControls();
    }
  }

  void _queuePreview(Duration target) {
    _previewDismissTimer?.cancel();
    final bucket = target.inSeconds ~/ 10;
    final cached = _thumbnailCache.remove(bucket);
    if (cached != null) {
      _thumbnailCache[bucket] = cached;
      if (mounted) setState(() => _previewImage = cached);
    } else if (mounted) {
      setState(() => _previewImage = null);
    }
    _queuedPreviewTarget = target;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!_previewCaptureRunning && _scrubbing) {
        final drain = _drainPreviewQueue(_scrubGeneration);
        _previewDrainFuture = drain;
        unawaited(drain);
      }
    });
  }

  Future<void> _drainPreviewQueue(int generation) async {
    _previewCaptureRunning = true;
    try {
      while (_queuedPreviewTarget != null &&
          mounted &&
          _scrubbing &&
          generation == _scrubGeneration) {
        final target = _queuedPreviewTarget!;
        _queuedPreviewTarget = null;
        final bucket = target.inSeconds ~/ 10;
        if (_thumbnailCache.containsKey(bucket)) continue;
        await _player.seek(target);
        try {
          await _player.stream.position
              .firstWhere(
                (value) =>
                    (value.inMilliseconds - target.inMilliseconds).abs() < 750,
              )
              .timeout(const Duration(milliseconds: 700));
        } on TimeoutException {
          // Ağır bir Range seek'te eldeki en yeni decoded frame kullanılır.
        }
        final image = await _player.screenshot(
          format: 'image/jpeg',
          includeLibassSubtitles: true,
        );
        if (!_scrubbing || generation != _scrubGeneration) break;
        if (image == null || image.isEmpty) continue;
        _thumbnailCache[bucket] = image;
        while (_thumbnailCache.length > 12) {
          _thumbnailCache.remove(_thumbnailCache.keys.first);
        }
        if (mounted &&
            _previewPosition != null &&
            _queuedPreviewTarget == null) {
          setState(() => _previewImage = image);
        }
      }
    } catch (_) {
      // Thumbnail başarısızlığı ana oynatmayı etkilemez.
    } finally {
      _previewCaptureRunning = false;
      _previewDrainFuture = null;
      if (_queuedPreviewTarget != null &&
          mounted &&
          _scrubbing &&
          generation == _scrubGeneration) {
        final drain = _drainPreviewQueue(generation);
        _previewDrainFuture = drain;
        unawaited(drain);
      }
    }
  }

  void _beginFastScan(int direction) {
    if (!_playbackReady || direction == 0 || _fastScanDirection != 0) return;
    _fastScanDirection = direction.sign;
    _wasPlayingBeforeScrub = _playing;
    unawaited(_player.pause());
    _revealControls();
    _fastScanTimer = Timer.periodic(const Duration(milliseconds: 170), (_) {
      if (_fastScanSeekFuture != null || _fastScanDirection == 0) return;
      final seek = _performFastScanSeek(_fastScanDirection);
      _fastScanSeekFuture = seek;
      unawaited(seek);
    });
  }

  Future<void> _performFastScanSeek(int direction) async {
    try {
      await _playback.seekRelative(
        Duration(seconds: 3 * direction),
        exact: false,
      );
    } catch (error) {
      _showControlError(error);
    } finally {
      _fastScanSeekFuture = null;
    }
  }

  Future<void> _endFastScan() async {
    if (_fastScanDirection == 0) return;
    _fastScanTimer?.cancel();
    _fastScanDirection = 0;
    final pending = _fastScanSeekFuture;
    if (pending != null) await pending;
    if (_wasPlayingBeforeScrub && !_disposing) await _player.play();
    _revealControls();
  }

  void _showControlError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).errorControlFailed('$error')),
      ),
    );
  }

  // PlayerKeyboardHandler: klavye/TV kumandası yönlendirmesi
  // lib/player/player_keyboard_controls.dart içindedir; tuş eşlemesi ile
  // oynatıcı durumu arasındaki köprü bu üyelerdir.

  @override
  bool get playbackReady => _playbackReady;

  @override
  bool get playing => _playing;

  @override
  bool get controlsVisible => _controlsVisible;

  @override
  bool get canvasEditing => _canvasEditing;

  @override
  bool get subtitleControlsVisible => _subtitleControlsVisible;

  @override
  bool get isPictureInPicture => _isPictureInPicture;

  @override
  bool get isFullscreen => _videoKey.currentState?.isFullscreen() ?? false;

  @override
  bool get remoteNavigationMode => _touchPrimary;

  @override
  Duration get seekStep => _seekStep;

  @override
  void revealControls() => _revealControls();

  /// TV geri tuşunda kontrolleri kapatır; auto-hide sayacı da iptal edilir.
  @override
  void hideControls() {
    _controlsTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() => _controlsVisible = false);
    }
  }

  @override
  void togglePlay() => unawaited(_togglePlay());

  @override
  void seekRelative(Duration offset) => unawaited(_seekRelative(offset));

  /// D-pad yukarı/aşağı: sesi ±5 değiştirir ve kontrolleri (ses OSD'si)
  /// görünür tutar.
  @override
  void adjustVolume(double delta) {
    _revealControls();
    _onVolumeChanged(_volume + delta);
  }

  @override
  void beginFastScan(int direction) => _beginFastScan(direction);

  @override
  void endFastScan() => unawaited(_endFastScan());

  @override
  void toggleFullscreen() => unawaited(_toggleFullscreen());

  @override
  void exitFullscreen() => unawaited(_videoKey.currentState?.exitFullscreen());

  @override
  void togglePictureInPicture() => unawaited(_togglePictureInPicture());

  @override
  void toggleCanvasEditor() => _toggleCanvasEditor();

  @override
  void cancelCanvasEditing() => unawaited(_cancelCanvasEditing());

  @override
  void toggleSubtitleControls() => _toggleSubtitleControls();

  @override
  void dismissSubtitleControls() {
    if (mounted) setState(() => _subtitleControlsVisible = false);
  }

  @override
  void stepBackward() => unawaited(_stepBackward());

  @override
  void stepForward() => unawaited(_stepForward());

  @override
  void nudgeSubtitleDelay(Duration delta) =>
      _queueSubtitleDelay(_subtitleDelay + delta);

  @override
  void closePlayer() => unawaited(_closePlayer());

  /// TV'de OK ile kontroller açıldığında oynat/duraklat düğmesine odak verir;
  /// böylece D-pad gezintisi düğmelerden başlayabilir. Masaüstünde no-op.
  @override
  void focusPlayButton() {
    if (!_touchPrimary) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposing) _playButtonFocusNode.requestFocus();
    });
  }

  Future<void> _toggleFullscreen() async {
    if (_isPictureInPicture) {
      final restored = await _pictureInPictureWindow.exit();
      if (!mounted) return;
      if (!restored) {
        _showPictureInPictureUnavailable();
        return;
      }
      setState(() => _isPictureInPicture = false);
    }
    final state = _videoKey.currentState;
    if (state != null) await state.toggleFullscreen();
    _revealControls();
  }

  Future<void> _closePlayer() async {
    final state = _videoKey.currentState;
    if (state?.isFullscreen() ?? false) {
      await state!.exitFullscreen();
    }
    if (_isPictureInPicture) await _togglePictureInPicture();
    if (mounted) await Navigator.of(context).maybePop();
  }

  Future<void> _togglePictureInPicture() async {
    final enter = !_isPictureInPicture;
    final videoState = _videoKey.currentState;
    if (enter && (videoState?.isFullscreen() ?? false)) {
      await videoState!.exitFullscreen();
      if (!mounted) return;
    }
    final changed = enter
        ? await _pictureInPictureWindow.enter()
        : await _pictureInPictureWindow.exit();
    if (!mounted) return;
    if (!changed) {
      _showPictureInPictureUnavailable();
      return;
    }
    setState(() => _isPictureInPicture = enter);
    _revealControls();
  }

  void _showPictureInPictureUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).errorPipUnavailable),
      ),
    );
  }

  Future<void> _showAdvancedSettings(Offset globalPosition) async {
    _revealControls();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final l10n = AppLocalizations.of(context);
    final local = overlay.globalToLocal(globalPosition);
    final selected = await showMenu<_PlayerContextAction>(
      context: context,
      color: const Color(0xF2242427),
      elevation: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        _contextItem(
          _PlayerContextAction.togglePlay,
          _playing ? l10n.pause : l10n.play,
          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          'Space',
        ),
        _contextItem(
          _PlayerContextAction.seekBack,
          l10n.seekBackSeconds(_seekStep.inSeconds),
          Icons.replay_rounded,
          '←',
        ),
        _contextItem(
          _PlayerContextAction.seekForward,
          l10n.seekForwardSeconds(_seekStep.inSeconds),
          Icons.forward_rounded,
          '→',
        ),
        const PopupMenuDivider(),
        _contextItem(
          _PlayerContextAction.frameBack,
          l10n.previousFrame,
          Icons.skip_previous_rounded,
          ',',
        ),
        _contextItem(
          _PlayerContextAction.frameForward,
          l10n.nextFrame,
          Icons.skip_next_rounded,
          '.',
        ),
        const PopupMenuDivider(),
        _contextItem(
          _PlayerContextAction.canvas,
          _canvasEditing ? l10n.cancelCanvasEditing : 'Smart Canvas',
          Icons.crop_rounded,
          'C',
        ),
        _contextItem(
          _PlayerContextAction.resetCanvas,
          l10n.resetCanvas,
          Icons.crop_original_rounded,
          '',
        ),
        _contextItem(
          _PlayerContextAction.subtitles,
          l10n.subtitleControls,
          Icons.subtitles_rounded,
          'S',
        ),
        _contextItem(
          _PlayerContextAction.loopA,
          l10n.loopSetA,
          Icons.looks_one_outlined,
          '',
        ),
        _contextItem(
          _PlayerContextAction.loopB,
          l10n.loopSetB,
          Icons.looks_two_outlined,
          '',
          enabled: _playback.loopStart != null,
        ),
        if (_playback.loopStart != null)
          _contextItem(
            _PlayerContextAction.clearLoop,
            l10n.loopClear,
            Icons.clear_all_rounded,
            '',
          ),
        const PopupMenuDivider(),
        _contextItem(
          _PlayerContextAction.tuning,
          l10n.tuningMenuItem,
          Icons.tune_rounded,
          '',
        ),
        if (_pictureInPictureWindow.isSupported)
          _contextItem(
            _PlayerContextAction.pictureInPicture,
            _isPictureInPicture ? l10n.exitMiniPlayer : l10n.miniPlayer,
            Icons.picture_in_picture_alt_rounded,
            'P',
          ),
        _contextItem(
          _PlayerContextAction.fullscreen,
          l10n.fullscreen,
          Icons.fullscreen_rounded,
          'F',
        ),
      ],
    );
    if (!mounted) return;
    if (selected != null) await _dispatchContextAction(selected);
    _revealControls();
  }

  PopupMenuItem<_PlayerContextAction> _contextItem(
    _PlayerContextAction value,
    String label,
    IconData icon,
    String shortcut, {
    bool enabled = true,
  }) => PopupMenuItem<_PlayerContextAction>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 17, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        if (shortcut.isNotEmpty)
          Text(
            shortcut,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
      ],
    ),
  );

  Future<void> _dispatchContextAction(_PlayerContextAction action) async {
    switch (action) {
      case _PlayerContextAction.togglePlay:
        await _togglePlay();
        return;
      case _PlayerContextAction.seekBack:
        await _seekRelative(_negateDuration(_seekStep));
        return;
      case _PlayerContextAction.seekForward:
        await _seekRelative(_seekStep);
        return;
      case _PlayerContextAction.frameBack:
        await _stepBackward();
        return;
      case _PlayerContextAction.frameForward:
        await _stepForward();
        return;
      case _PlayerContextAction.canvas:
        _toggleCanvasEditor();
        return;
      case _PlayerContextAction.resetCanvas:
        await _resetCanvas();
        return;
      case _PlayerContextAction.subtitles:
        _toggleSubtitleControls();
        return;
      case _PlayerContextAction.loopA:
        await _setLoopStart();
        return;
      case _PlayerContextAction.loopB:
        await _setLoopEnd();
        return;
      case _PlayerContextAction.clearLoop:
        await _clearLoop();
        return;
      case _PlayerContextAction.tuning:
        await _showTuningDialog();
        return;
      case _PlayerContextAction.pictureInPicture:
        await _togglePictureInPicture();
        return;
      case _PlayerContextAction.fullscreen:
        await _toggleFullscreen();
        return;
    }
  }

  Future<void> _showTuningDialog() async {
    _controlsTimer?.cancel();
    // İçerik hangi dinamik aralık formatlarını taşıyor? Diyalog açılırken
    // libmpv parametrelerinden okunur; desteklenmeyen modlar pasif kalır.
    final hdrCapsFuture = _playback.detectHdrCapabilities();
    // Diyalog başlık çubuğundan sürüklenir; konum diyalog süresince saklanır.
    var dragOffset = Offset.zero;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = AppLocalizations.of(context);
          final seekStepSeconds = _seekStep.inSeconds;
          final seekStepOptions = <int>{1, 5, 10, 30, seekStepSeconds}.toList()
            ..sort();
          final periodicIntervalMilliseconds =
              _preferences.periodicInfoInterval?.inMilliseconds ?? 0;
          final periodicInfoOptions = <int>{
            0,
            15000,
            30000,
            60000,
            periodicIntervalMilliseconds,
          }.toList()..sort();
          final screenSize = MediaQuery.of(context).size;
          final compactSegmentStyle = TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12),
          );

          Future<void> refresh(Future<void> operation) async {
            await operation;
            if (dialogContext.mounted) setDialogState(() {});
          }

          void onDialogDrag(DragUpdateDetails details) {
            setDialogState(() {
              final candidate = dragOffset + details.delta;
              // Diyalog her zaman ekrandan taşmayacak bir bölgede kalır.
              dragOffset = Offset(
                candidate.dx
                    .clamp(
                      120 - screenSize.width / 2,
                      screenSize.width / 2 - 120,
                    )
                    .toDouble(),
                candidate.dy
                    .clamp(
                      80 - screenSize.height / 2,
                      screenSize.height / 2 - 80,
                    )
                    .toDouble(),
              );
            });
          }

          return Transform.translate(
            offset: dragOffset,
            child: AlertDialog(
              backgroundColor: const Color(0xFF202023),
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white12),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              title: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: onDialogDrag,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drag_indicator_rounded,
                        size: 18,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.tuningDialogTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.closeTooltip,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TuningRow(
                        label: l10n.videoPresetLabel,
                        child: SegmentedButton<VideoPreset>(
                          style: compactSegmentStyle,
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: VideoPreset.natural,
                              label: Text(l10n.presetNatural),
                            ),
                            ButtonSegment(
                              value: VideoPreset.cinema,
                              label: Text(l10n.presetCinema),
                            ),
                            ButtonSegment(
                              value: VideoPreset.vivid,
                              label: Text(l10n.presetVivid),
                            ),
                          ],
                          selected: {_playback.videoPreset},
                          onSelectionChanged: (value) =>
                              unawaited(refresh(_setVideoPreset(value.single))),
                        ),
                      ),
                      _TuningRow(
                        label: l10n.gpuScalingLabel,
                        child: SegmentedButton<UpscalingPreset>(
                          style: compactSegmentStyle,
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: UpscalingPreset.lowPower,
                              label: Text(l10n.presetLowPower),
                            ),
                            ButtonSegment(
                              value: UpscalingPreset.balanced,
                              label: Text(l10n.presetBalanced),
                            ),
                            ButtonSegment(
                              value: UpscalingPreset.quality,
                              label: Text(l10n.presetQuality),
                            ),
                          ],
                          selected: {_playback.upscalingPreset},
                          onSelectionChanged: (value) => unawaited(
                            refresh(_setUpscalingPreset(value.single)),
                          ),
                        ),
                      ),
                      _TuningRow(
                        label: l10n.audioPresetLabel,
                        child: SegmentedButton<AudioPreset>(
                          style: compactSegmentStyle,
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: AudioPreset.balanced,
                              label: Text(l10n.presetBalanced),
                            ),
                            ButtonSegment(
                              value: AudioPreset.dialogue,
                              label: Text(l10n.presetDialogue),
                            ),
                            ButtonSegment(
                              value: AudioPreset.night,
                              label: Text(l10n.presetNight),
                            ),
                          ],
                          selected: {_playback.audioPreset},
                          onSelectionChanged: (value) =>
                              unawaited(refresh(_setAudioPreset(value.single))),
                        ),
                      ),
                      _TuningRow(
                        label: l10n.seekStepLabel,
                        child: SegmentedButton<int>(
                          style: compactSegmentStyle,
                          showSelectedIcon: false,
                          segments: [
                            for (final seconds in seekStepOptions)
                              ButtonSegment(
                                value: seconds,
                                label: Text(
                                  '$seconds ${l10n.secondsUnitShort}',
                                ),
                              ),
                          ],
                          selected: {seekStepSeconds},
                          onSelectionChanged: (value) =>
                              unawaited(refresh(_setSeekStep(value.single))),
                        ),
                      ),
                      _TuningRow(
                        label: l10n.periodicInfoLabel,
                        child: SegmentedButton<int>(
                          style: compactSegmentStyle,
                          showSelectedIcon: false,
                          segments: [
                            for (final milliseconds in periodicInfoOptions)
                              ButtonSegment(
                                value: milliseconds,
                                label: Text(
                                  milliseconds == 0
                                      ? l10n.off
                                      : _formatIntervalMilliseconds(
                                          milliseconds,
                                          l10n,
                                        ),
                                ),
                              ),
                          ],
                          selected: {periodicIntervalMilliseconds},
                          onSelectionChanged: (value) => unawaited(
                            refresh(
                              _setPeriodicInfoInterval(
                                value.single == 0
                                    ? null
                                    : Duration(milliseconds: value.single),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _TuningRow(
                        label: l10n.audioSyncLabel,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.audioEarlierTooltip,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => unawaited(
                                refresh(
                                  _setAudioDelay(
                                    _audioDelay -
                                        const Duration(milliseconds: 100),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.remove_rounded, size: 18),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                _formatSignedDuration(
                                  _audioDelay,
                                  l10n.secondsUnitShort,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.audioLaterTooltip,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => unawaited(
                                refresh(
                                  _setAudioDelay(
                                    _audioDelay +
                                        const Duration(milliseconds: 100),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                      _TuningRow(
                        label: l10n.decodingLabel,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _hardwareDecoding
                                  ? l10n.decodingHardware
                                  : l10n.decodingSoftware,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: _hardwareDecoding,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) => unawaited(
                                refresh(_setHardwareDecoding(value)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _TuningRow(
                        label: l10n.dynamicRangeLabel,
                        child: FutureBuilder<HdrCapabilities>(
                          future: hdrCapsFuture,
                          builder: (context, snapshot) {
                            // Algılama sürerken yalnız SDR seçilebilir.
                            final caps =
                                snapshot.data ?? const HdrCapabilities();
                            final selection = caps.supports(_hdrMode)
                                ? _hdrMode
                                : HdrMode.sdr;
                            ButtonSegment<HdrMode> segment(
                              HdrMode mode,
                              String text,
                            ) => ButtonSegment(
                              value: mode,
                              enabled: caps.supports(mode),
                              label: Text(text),
                            );
                            return SegmentedButton<HdrMode>(
                              style: compactSegmentStyle,
                              showSelectedIcon: false,
                              segments: [
                                segment(HdrMode.sdr, 'SDR'),
                                segment(HdrMode.hdr, 'HDR'),
                                segment(HdrMode.hdr10, 'HDR10'),
                                segment(HdrMode.hdr10plus, 'HDR10+'),
                                segment(HdrMode.dolbyVision, 'DV'),
                              ],
                              selected: {selection},
                              onSelectionChanged: (value) =>
                                  unawaited(refresh(_setHdrMode(value.single))),
                            );
                          },
                        ),
                      ),
                      Text(
                        l10n.hdrInfoText,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.doneLabel),
                ),
              ],
            ),
          );
        },
      ),
    );
    _revealControls();
  }

  Future<void> _setHdrMode(HdrMode mode) async {
    await _runControl(
      () => _playback.setHdrMode(mode),
      onSuccess: () => _hdrMode = mode,
    );
  }

  Future<void> _setHardwareDecoding(bool enabled) async {
    await _runControl(
      () => _playback.setHardwareDecoding(enabled),
      onSuccess: () => _hardwareDecoding = enabled,
    );
  }

  Future<void> _setVideoPreset(VideoPreset preset) async {
    final applied = await _runControl(() => _playback.setVideoPreset(preset));
    if (applied) await _persistPreferences();
  }

  Future<void> _setUpscalingPreset(UpscalingPreset preset) async {
    final applied = await _runControl(
      () => _playback.setUpscalingPreset(preset),
    );
    if (applied) await _persistPreferences();
  }

  Future<void> _setAudioPreset(AudioPreset preset) async {
    final applied = await _runControl(() => _playback.setAudioPreset(preset));
    if (applied) await _persistPreferences();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_canvasEditing) return;
    _touchPoints[event.pointer] = event.localPosition;
    if (_touchPoints.length == 2) {
      _pinchStartDistance = _distanceBetweenFirstTwoPointers();
      _pinchStartZoom = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_canvasEditing) return;
    if (!_touchPoints.containsKey(event.pointer)) return;
    _touchPoints[event.pointer] = event.localPosition;
    final startDistance = _pinchStartDistance;
    if (_touchPoints.length < 2 ||
        startDistance == null ||
        startDistance == 0) {
      return;
    }
    final distance = _distanceBetweenFirstTwoPointers();
    _queueZoom(_pinchStartZoom * distance / startDistance);
  }

  void _onPointerUp(PointerEvent event) {
    _touchPoints.remove(event.pointer);
    if (_touchPoints.length < 2) _pinchStartDistance = null;
  }

  double _distanceBetweenFirstTwoPointers() {
    final points = _touchPoints.values.take(2).toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (_canvasEditing) return;
    _trackpadStartZoom = _zoom;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_canvasEditing) return;
    _queueZoom(_trackpadStartZoom * event.scale);
  }

  void _queueZoom(double value) {
    if (_canvasEditing || _canvasOpening || _disposing) return;
    final clamped = value
        .clamp(
          AdvancedPlaybackController.minimumZoom,
          AdvancedPlaybackController.maximumZoom,
        )
        .toDouble();
    if ((clamped - _zoom).abs() < 0.002) return;
    if (mounted) setState(() => _zoom = clamped);
    _queuedZoom = clamped;
    if (!_zoomUpdateRunning) {
      final drain = _drainZoomUpdates();
      _zoomDrainFuture = drain;
      unawaited(drain);
    }
  }

  Future<void> _drainZoomUpdates() async {
    _zoomUpdateRunning = true;
    try {
      while (_queuedZoom != null) {
        final value = _queuedZoom!;
        _queuedZoom = null;
        await _playback.setZoom(value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).errorZoomFailed('$error'),
            ),
          ),
        );
      }
    } finally {
      _zoomUpdateRunning = false;
      _zoomDrainFuture = null;
      if (_queuedZoom != null && !_canvasEditing && !_canvasOpening) {
        final drain = _drainZoomUpdates();
        _zoomDrainFuture = drain;
        unawaited(drain);
      } else if (_canvasEditing || _canvasOpening) {
        _queuedZoom = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _ErrorView(
              message: _error.toString(),
              onClose: () => unawaited(_closePlayer()),
            )
          : _buildVideoSurface(),
    );
  }

  Widget _buildVideoSurface() {
    return ColoredBox(
      color: Colors.black,
      child: Video(
        key: _videoKey,
        controller: _videoController,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        controls: (_) => PlayerKeyboardControls(
          handler: this,
          child: Builder(
            builder: (focusContext) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                Focus.of(focusContext).requestFocus();
                _onPointerDown(event);
              },
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              onPointerPanZoomStart: _onPointerPanZoomStart,
              onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
              child: GyuniPlayerChrome(
                visible: _controlsVisible,
                ready: _playbackReady,
                playing: _playing,
                buffering: _buffering,
                volume: _volume,
                periodicInfoVisible: _periodicInfoVisible,
                filename:
                    _info?.filename ??
                    AppLocalizations.of(context).videoPreparing,
                status: _status,
                engineBadge: _engineStatus,
                position: _position,
                duration: _duration,
                rate: _rate,
                tracks: _tracks,
                selectedTrack: _track,
                previewImage: _previewImage,
                previewPosition: _previewPosition,
                editorOverlay: _buildEditorOverlay(),
                seekFlashDirection: _seekFlashDirection,
                isPictureInPicture: _isPictureInPicture,
                canvasActive: _canvasEditing,
                subtitleControlsActive: _subtitleControlsVisible,
                pictureInPictureSupported: _pictureInPictureWindow.isSupported,
                playButtonFocusNode: _playButtonFocusNode,
                onActivity: _revealControls,
                onVideoTap: _touchPrimary
                    ? _toggleControlsVisibility
                    : () => unawaited(_togglePlay()),
                onTogglePlay: () => unawaited(_togglePlay()),
                onClose: () => unawaited(_closePlayer()),
                onToggleFullscreen: () => unawaited(_toggleFullscreen()),
                onTogglePictureInPicture: () =>
                    unawaited(_togglePictureInPicture()),
                onToggleCanvas: _toggleCanvasEditor,
                onToggleSubtitleControls: _toggleSubtitleControls,
                onDoubleTapSeek: _flashSeek,
                onVolumeChanged: _onVolumeChanged,
                onToggleMute: _toggleMute,
                onFrameBackward: () => unawaited(_stepBackward()),
                onFrameForward: () => unawaited(_stepForward()),
                onScrubStart: _onScrubStart,
                onScrubUpdate: _onScrubUpdate,
                onScrubEnd: _onScrubEnd,
                onRateSelected: (value) => unawaited(_setRate(value)),
                onSubtitleSelected: (track) =>
                    unawaited(_selectSubtitle(track)),
                onAudioSelected: (track) => unawaited(_selectAudio(track)),
                onLoadExternalAudio: () => unawaited(_loadExternalAudio()),
                onLoadExternalSubtitle: () =>
                    unawaited(_loadExternalSubtitle()),
                onShowAdvancedSettings: (position) =>
                    unawaited(_showAdvancedSettings(position)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildEditorOverlay() {
    if (_canvasEditing) {
      return SmartCanvasOverlay(
        crop: _canvasDraft,
        sourceAspectRatio: _sourceAspectRatio,
        onChanged: _previewCanvas,
        onCommit: (crop) => unawaited(_commitCanvas(crop)),
        onCancel: () => unawaited(_cancelCanvasEditing()),
        minimumCropExtent: _minimumCanvasExtent,
      );
    }
    if (_subtitleControlsVisible) {
      return SubtitleControlsOverlay(
        scale: _subtitleScale,
        position: _subtitlePosition,
        delay: _subtitleDelay,
        tracks: _tracks.subtitle,
        selectedTrack: _track.subtitle,
        onScaleChanged: _queueSubtitleScale,
        onPositionChanged: _queueSubtitlePosition,
        onDelayChanged: _queueSubtitleDelay,
        onTrackSelected: (track) => unawaited(_selectSubtitle(track)),
        onClose: _toggleSubtitleControls,
      );
    }
    return null;
  }
}

enum _PlayerContextAction {
  togglePlay,
  seekBack,
  seekForward,
  frameBack,
  frameForward,
  canvas,
  resetCanvas,
  subtitles,
  loopA,
  loopB,
  clearLoop,
  tuning,
  pictureInPicture,
  fullscreen,
}

VideoPreset _videoPresetFromName(String value) => switch (value) {
  'cinema' => VideoPreset.cinema,
  'vivid' => VideoPreset.vivid,
  _ => VideoPreset.natural,
};

UpscalingPreset _upscalingPresetFromName(String value) => switch (value) {
  'quality' => UpscalingPreset.quality,
  'lowPower' || 'low_power' => UpscalingPreset.lowPower,
  _ => UpscalingPreset.balanced,
};

String _upscalingPresetStorageName(UpscalingPreset value) => switch (value) {
  UpscalingPreset.lowPower => 'low_power',
  UpscalingPreset.balanced => 'balanced',
  UpscalingPreset.quality => 'quality',
};

AudioPreset _audioPresetFromName(String value) => switch (value) {
  'dialogue' => AudioPreset.dialogue,
  'night' => AudioPreset.night,
  _ => AudioPreset.balanced,
};

Duration _clampDuration(Duration value, Duration maximum) => Duration(
  microseconds: value.inMicroseconds
      .clamp(-maximum.inMicroseconds, maximum.inMicroseconds)
      .toInt(),
);

Duration _negateDuration(Duration value) =>
    Duration(microseconds: -value.inMicroseconds);

String _formatSignedDuration(Duration value, String unit) {
  final seconds = value.inMicroseconds / Duration.microsecondsPerSecond;
  return '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(2)} $unit';
}

String _formatIntervalMilliseconds(int milliseconds, AppLocalizations l10n) {
  final unit = l10n.secondsUnitShort;
  if (milliseconds % 1000 == 0) {
    return '${milliseconds ~/ 1000} $unit';
  }
  // Ondalık ayracı dile göre: tr'de virgül, diğerlerinde nokta.
  final decimalSeparator = l10n.localeName == 'tr' ? ',' : '.';
  final seconds = (milliseconds / 1000)
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceFirst('.', decimalSeparator);
  return '$seconds $unit';
}

class _TuningRow extends StatelessWidget {
  const _TuningRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF6961)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              label: Text(AppLocalizations.of(context).closePlayer),
            ),
          ],
        ),
      ),
    );
  }
}
