import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/l10n/app_localizations.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/player/gyuni_player_controls.dart';
import 'package:zanzibarr/player/smart_canvas.dart';
import 'package:zanzibarr/player/smart_canvas_overlay.dart';
import 'package:zanzibarr/settings/provider_settings.dart';
import 'package:zanzibarr/settings/settings_screen.dart';
import 'package:zanzibarr/settings/ui_preferences.dart';

/// README için gerçek UI ekran görüntüleri üreten golden-test harness'ı.
///
/// Yalnızca `GENERATE_SCREENSHOTS=1 flutter test test/screenshots_test.dart
/// --update-goldens` ile çalışır; normal test koşusunda atlanır.
/// Golden'lar `docs/screenshots/` altına yazılır (2560×1600 @2x = 1280×800
/// logical).
final _skipScreenshots = Platform.environment['GENERATE_SCREENSHOTS'] != '1';

const _accent = Color(0xFFFF453A);
const _fontFamily = 'AppScreenshotFont';

/// ZanzibarrApp'in private tema builder'larının eşdeğeri; tek farkı tofu'yu
/// önlemek için yüklenen gerçek font ailesi.
ThemeData _screenshotTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: brightness,
    surface: isDark ? const Color(0xFF141416) : const Color(0xFFFFFFFF),
  );
  final foreground = isDark ? Colors.white : Colors.black;
  InputDecorationTheme inputTheme({required Color fill, required Color border}) =>
      InputDecorationTheme(
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.2),
        ),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF09090B)
        : const Color(0xFFF5F5F7),
    canvasColor: isDark ? const Color(0xFF17171A) : Colors.white,
    dividerColor: foreground.withValues(alpha: 0.08),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: inputTheme(
      fill: foreground.withValues(alpha: isDark ? 0.055 : 0.045),
      border: foreground.withValues(alpha: isDark ? 0.1 : 0.14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: foreground,
        foregroundColor: isDark ? Colors.black : Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xF228282C) : const Color(0xF2323236),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF22A2A2D) : const Color(0xF2323236),
        borderRadius: BorderRadius.circular(7),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 11),
      waitDuration: const Duration(milliseconds: 450),
    ),
  );
}

Widget _screenshotApp(Widget home, ThemeMode themeMode) => MaterialApp(
  title: 'Zanzibarr',
  debugShowCheckedModeBanner: false,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  themeMode: themeMode,
  theme: _screenshotTheme(Brightness.light),
  darkTheme: _screenshotTheme(Brightness.dark),
  home: home,
);

/// SDK içindeki MaterialIcons-Regular.otf dosyasını, çalışan Dart
/// yorumlayıcısının dizininden yukarı doğru bularak döndürür.
File _findMaterialIconsFont() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    for (final prefix in ['artifacts/material_fonts', 'material_fonts']) {
      final candidate = File('${dir.path}/$prefix/MaterialIcons-Regular.otf');
      if (candidate.existsSync()) return candidate;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError(
    'MaterialIcons-Regular.otf Flutter SDK içinde bulunamadı '
    '(yorumlayıcı: ${Platform.resolvedExecutable})',
  );
}

/// physicalSize + 2.0 dpr verip test sonunda sıfırlar.
void _useWindow(WidgetTester tester, Size physicalSize) {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Test ortamında defaultTargetPlatform Android döner; chrome'un desktop
/// (macOS) davranışıyla çizilmesi için geçersiz kılınır. Framework'ün
/// foundation-değişken invariant denetimi tearDown'dan önce koştuğundan
/// sıfırlama test gövdesi bitmeden, try/finally ile yapılır.
Future<void> _desktopShot(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Gerçek asset (logo PNG) çözümleme/decode fake-async dışında döner; kısa bir
/// gerçek gecikme + pump ile render ağacına işlenmesi beklenir.
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Bellek içi sahte depo; ekran dolu bir form ile açılsın diye örnek değerli.
class _FakeStore extends ProviderSettingsStore {
  @override
  Future<ProviderSettings> load() async => const ProviderSettings(
    host: 'news.example.com',
    port: 563,
    username: 'usenetfan',
    password: 'hunter2-example',
    maxConnections: 20,
  );

  @override
  Future<void> save(ProviderSettings settings) async {}
}

/// Oyuncu chrome'u için örnek parça listesi.
const _tracks = Tracks(
  audio: [
    AudioTrack('auto', null, null),
    AudioTrack('1', 'English 5.1', 'en', codec: 'ac3'),
    AudioTrack('2', 'Turkish 2.0', 'tr', codec: 'aac'),
  ],
  subtitle: [
    SubtitleTrack('no', null, null),
    SubtitleTrack('1', 'English SDH', 'en', codec: 'srt'),
    SubtitleTrack('2', 'Turkish', 'tr', codec: 'srt'),
  ],
);

const _selectedTrack = Track(
  audio: AudioTrack('auto', null, null),
  subtitle: SubtitleTrack('no', null, null),
);

/// Gerçek video yüzeyi yerine sinematik bir yer tutucu kare.
class _FakeVideoFrame extends StatelessWidget {
  const _FakeVideoFrame({this.containedAspectRatio});

  /// Verilirse kare bu en-boy oranıyla mektup kutusu içinde çizilir
  /// (Smart Canvas'ın BoxFit.contain varsayımıyla hizalı).
  final double? containedAspectRatio;

  @override
  Widget build(BuildContext context) {
    const frame = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.45),
          radius: 1.25,
          colors: [Color(0xFF2B3B5E), Color(0xFF0A0E18)],
        ),
      ),
      child: SizedBox.expand(),
    );
    final ratio = containedAspectRatio;
    if (ratio == null) return frame;
    return Center(child: AspectRatio(aspectRatio: ratio, child: frame));
  }
}

/// Duraklatılmış video hissini veren ortadaki büyük oynat düğmesi.
class _CenterPlayButton extends StatelessWidget {
  const _CenterPlayButton();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 44,
        color: Colors.white70,
      ),
    ),
  );
}

/// Tam pencere oyuncu kompozisyonu: yer tutucu video + gerçek chrome.
Widget _playerComposition({
  Widget? editorOverlay,
  bool canvasActive = false,
  bool showCenterPlay = true,
  double? containedAspectRatio,
}) {
  return Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        _FakeVideoFrame(containedAspectRatio: containedAspectRatio),
        if (showCenterPlay) const _CenterPlayButton(),
        GyuniPlayerChrome(
          visible: true,
          ready: true,
          playing: false,
          buffering: false,
          periodicInfoVisible: false,
          filename: 'Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.mkv',
          status: 'Ready',
          engineBadge: 'libmpv 0.41 · FFmpeg 8.1',
          position: const Duration(minutes: 42, seconds: 37),
          duration: const Duration(hours: 2, minutes: 46, seconds: 4),
          rate: 1.0,
          tracks: _tracks,
          selectedTrack: _selectedTrack,
          volume: 80,
          canvasActive: canvasActive,
          pictureInPictureSupported: true,
          editorOverlay: editorOverlay,
          onActivity: () {},
          onVideoTap: () {},
          onTogglePlay: () {},
          onClose: () {},
          onToggleFullscreen: () {},
          onTogglePictureInPicture: () {},
          onToggleCanvas: () {},
          onToggleSubtitleControls: () {},
          onDoubleTapSeek: (_) {},
          onFrameBackward: () {},
          onFrameForward: () {},
          onScrubStart: (_) {},
          onScrubUpdate: (_) {},
          onScrubEnd: (_) {},
          onRateSelected: (_) {},
          onSubtitleSelected: (_) {},
          onAudioSelected: (_) {},
          onShowAdvancedSettings: (_) {},
          onVolumeChanged: (_) {},
          onToggleMute: () {},
          onLoadExternalAudio: () {},
          onLoadExternalSubtitle: () {},
        ),
      ],
    ),
  );
}

/// player_screen.dart'taki "_TuningRow"un eşdeğeri (private olduğundan
/// burada kopya).
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

/// player_screen.dart'taki "Video and audio" (Görüntü ve ses) ayar diyaloğunun
/// motor gerektirmeyen statik kopyası; seçimler temsili.
class _TuningDialogReplica extends StatelessWidget {
  const _TuningDialogReplica();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compactSegmentStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // styleFrom'un textStyle'ı düğmenin kendi DefaultTextStyle'ını kurar;
      // fontFamily verilmezse test ortamında kutu (Ahem) çizer.
      textStyle: const TextStyle(fontSize: 12, fontFamily: _fontFamily),
    );

    Widget segments(
      List<String> options,
      String selected, [
      Set<String> disabled = const {},
    ]) => SegmentedButton<String>(
      style: compactSegmentStyle,
      showSelectedIcon: false,
      segments: [
        for (final option in options)
          ButtonSegment(
            value: option,
            enabled: !disabled.contains(option),
            label: Text(option),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (_) {},
    );

    return AlertDialog(
      backgroundColor: const Color(0xFF202023),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      title: Row(
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
            onPressed: () {},
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
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
                child: segments(
                  [l10n.presetNatural, l10n.presetCinema, l10n.presetVivid],
                  l10n.presetCinema,
                ),
              ),
              _TuningRow(
                label: l10n.gpuScalingLabel,
                child: segments(
                  [l10n.presetLowPower, l10n.presetBalanced, l10n.presetQuality],
                  l10n.presetQuality,
                ),
              ),
              _TuningRow(
                label: l10n.audioPresetLabel,
                child: segments(
                  [l10n.presetBalanced, l10n.presetDialogue, l10n.presetNight],
                  l10n.presetBalanced,
                ),
              ),
              _TuningRow(
                label: l10n.seekStepLabel,
                child: segments(
                  ['1 ${l10n.secondsUnitShort}', '5 ${l10n.secondsUnitShort}',
                      '10 ${l10n.secondsUnitShort}', '30 ${l10n.secondsUnitShort}'],
                  '10 ${l10n.secondsUnitShort}',
                ),
              ),
              _TuningRow(
                label: l10n.periodicInfoLabel,
                child: segments(
                  [l10n.off, '15 ${l10n.secondsUnitShort}',
                      '30 ${l10n.secondsUnitShort}', '60 ${l10n.secondsUnitShort}'],
                  l10n.off,
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
                      onPressed: () {},
                      icon: const Icon(Icons.remove_rounded, size: 18),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '0.00 ${l10n.secondsUnitShort}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.audioLaterTooltip,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {},
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
                      l10n.decodingHardware,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: true,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
              _TuningRow(
                label: l10n.dynamicRangeLabel,
                child: segments(
                  const ['SDR', 'HDR', 'HDR10', 'HDR10+', 'DV'],
                  'SDR',
                  const {'HDR10+', 'DV'},
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
        TextButton(onPressed: () {}, child: Text(l10n.doneLabel)),
      ],
    );
  }
}

/// İlk kareden sonra gelişmiş ayarlar diyaloğunu açan sarmalayıcı.
class _TuningDialogOpener extends StatefulWidget {
  const _TuningDialogOpener({required this.child});

  final Widget child;

  @override
  State<_TuningDialogOpener> createState() => _TuningDialogOpenerState();
}

class _TuningDialogOpenerState extends State<_TuningDialogOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => const _TuningDialogReplica(),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Golden testlerde varsayılan test fontu kutu (tofu) çizer; sistemdeki
    // gerçek Arial TTF'lerini tek aile altında yükle.
    final loader = FontLoader(_fontFamily)
      ..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Arial.ttf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      )
      ..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await loader.load();
    // Icon fontları golden'larda tofu çizmemesi için SDK'daki gerçek
    // MaterialIcons OTF'sini yükle. Dart yorumlayıcısının konumu SDK
    // kurulumuna göre değişebildiğinden üst dizinlere doğru aranır.
    final materialIcons = _findMaterialIconsFont();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(
        materialIcons.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await iconLoader.load();
  });

  const window = Size(2560, 1600); // 1280×800 logical @2x

  testWidgets('home_dark', (tester) => _desktopShot(() async {
    _useWindow(tester, window);
    await tester.pumpWidget(
      _screenshotApp(const HomeScreen(), ThemeMode.dark),
    );
    await _settleAssets(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/home_dark.png'),
    );
  }), skip: _skipScreenshots);

  testWidgets('home_light', (tester) => _desktopShot(() async {
    _useWindow(tester, window);
    await tester.pumpWidget(
      _screenshotApp(const HomeScreen(), ThemeMode.light),
    );
    await _settleAssets(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/home_light.png'),
    );
  }), skip: _skipScreenshots);

  testWidgets('settings', (tester) => _desktopShot(() async {
    _useWindow(tester, const Size(2560, 2000)); // 1280×1000 logical @2x
    await tester.pumpWidget(
      _screenshotApp(
        SettingsScreen(
          store: _FakeStore(),
          uiPreferences: UiPreferencesController(UiPreferencesStore()),
        ),
        ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/settings.png'),
    );
  }), skip: _skipScreenshots);

  testWidgets('player_controls', (tester) => _desktopShot(() async {
    _useWindow(tester, window);
    await tester.pumpWidget(
      _screenshotApp(_playerComposition(), ThemeMode.dark),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/player_controls.png'),
    );
  }), skip: _skipScreenshots);

  testWidgets('advanced_settings', (tester) => _desktopShot(() async {
    _useWindow(tester, window);
    await tester.pumpWidget(
      _screenshotApp(
        _TuningDialogOpener(child: _playerComposition()),
        ThemeMode.dark,
      ),
    );
    await tester.pump();
    // Diyalog route animasyonu tamamlansın.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/advanced_settings.png'),
    );
  }), skip: _skipScreenshots);

  testWidgets('smart_canvas', (tester) => _desktopShot(() async {
    _useWindow(tester, window);
    await tester.pumpWidget(
      _screenshotApp(
        _playerComposition(
          canvasActive: true,
          showCenterPlay: false,
          containedAspectRatio: 16 / 9,
          editorOverlay: SmartCanvasOverlay(
            crop: const CanvasCrop(
              left: 0.12,
              top: 0.15,
              right: 0.88,
              bottom: 0.85,
            ),
            sourceAspectRatio: 16 / 9,
            onChanged: (_) {},
            onCommit: (_) {},
            onCancel: () {},
          ),
        ),
        ThemeMode.dark,
      ),
    );
    await tester.pump();
    // Overlay'in AnimatedOpacity'si (160 ms) tamamlansın.
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/smart_canvas.png'),
    );
  }), skip: _skipScreenshots);
}
