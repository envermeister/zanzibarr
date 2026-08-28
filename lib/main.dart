import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'l10n/app_localizations.dart';
import 'player/gyuni_player_controls.dart' show formatPlayerDuration;
import 'player/playback_history.dart';
import 'player/player_screen.dart';
import 'update/update_service.dart';
import 'search/search_screen.dart';
import 'settings/indexer_settings.dart';
import 'settings/settings_screen.dart';
import 'settings/ui_preferences.dart';
import 'src/rust/frb_generated.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ZanzibarrBootstrap(
      uiPreferences: UiPreferencesController(UiPreferencesStore()),
    ),
  );
}

Future<void> _initializeNativeEngine(
  UiPreferencesController uiPreferences,
) async {
  MediaKit.ensureInitialized();
  // Tercih deposu hatası (ör. Android Keystore anahtarı yeniden kurulumda
  // geçersizleşti) motorun açılmasını engellemez; varsayılanlarla devam edilir.
  final preferencesLoaded = uiPreferences.load().catchError((Object error) {
    debugPrint('uiPreferences yüklenemedi, varsayılanlarla devam: $error');
  });
  await Future.wait([RustLib.init(), preferencesLoaded]);
}

/// İlk native çağrı hata verse veya takılsa bile boş pencere yerine anlaşılır
/// bir durum ve güvenli yeniden-deneme yolu gösterir.
class ZanzibarrBootstrap extends StatefulWidget {
  const ZanzibarrBootstrap({super.key, this.initialize, this.uiPreferences});

  final Future<void> Function()? initialize;
  final UiPreferencesController? uiPreferences;

  @override
  State<ZanzibarrBootstrap> createState() => _ZanzibarrBootstrapState();
}

class _ZanzibarrBootstrapState extends State<ZanzibarrBootstrap> {
  late Future<void> _initialization = _startInitialization();

  Future<void> _startInitialization() => Future<void>.sync(
    widget.initialize ??
        () => _initializeNativeEngine(
          widget.uiPreferences ?? UiPreferencesController(UiPreferencesStore()),
        ),
  ).timeout(const Duration(seconds: 25));

  void _retry() {
    setState(() => _initialization = _startInitialization());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return ZanzibarrApp(uiPreferences: widget.uiPreferences);
      }
      return ZanzibarrApp(
        uiPreferences: widget.uiPreferences,
        home: _EngineStartupView(
          failed: snapshot.hasError,
          error: snapshot.hasError ? snapshot.error : null,
          onRetry: snapshot.hasError ? _retry : null,
        ),
      );
    },
  );
}

class ZanzibarrApp extends StatelessWidget {
  const ZanzibarrApp({super.key, this.home, this.uiPreferences});

  final Widget? home;
  final UiPreferencesController? uiPreferences;

  static const _accent = Color(0xFFFF453A);

  @override
  Widget build(BuildContext context) {
    final controller = uiPreferences;
    return ListenableBuilder(
      listenable: controller ?? UiPreferencesController(UiPreferencesStore()),
      builder: (context, _) => MaterialApp(
        title: 'Zanzibarr',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          for (final (locale, _) in supportedAppLocales) locale,
        ],
        locale: controller?.locale,
        themeMode: controller?.themeMode ?? ThemeMode.dark,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        home: home ?? HomeScreen(uiPreferences: controller),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF141416),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF09090B),
      canvasColor: const Color(0xFF17171A),
      dividerColor: Colors.white.withValues(alpha: 0.08),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: _inputTheme(
        fill: Colors.white.withValues(alpha: 0.055),
        border: Colors.white.withValues(alpha: 0.1),
      ),
      filledButtonTheme: _filledButtonTheme(
        background: Colors.white,
        foreground: Colors.black,
      ),
      snackBarTheme: _snackBarTheme(const Color(0xF228282C)),
      tooltipTheme: _tooltipTheme(const Color(0xF22A2A2D), Colors.white),
    );
  }

  ThemeData _buildLightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.light,
      surface: const Color(0xFFFFFFFF),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      canvasColor: Colors.white,
      dividerColor: Colors.black.withValues(alpha: 0.08),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: _inputTheme(
        fill: Colors.black.withValues(alpha: 0.045),
        border: Colors.black.withValues(alpha: 0.14),
      ),
      filledButtonTheme: _filledButtonTheme(
        background: Colors.black,
        foreground: Colors.white,
      ),
      snackBarTheme: _snackBarTheme(const Color(0xF2323236)),
      tooltipTheme: _tooltipTheme(const Color(0xF2323236), Colors.white),
    );
  }

  InputDecorationTheme _inputTheme({
    required Color fill,
    required Color border,
  }) => InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
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

  FilledButtonThemeData _filledButtonTheme({
    required Color background,
    required Color foreground,
  }) => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
  );

  SnackBarThemeData _snackBarTheme(Color background) => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  TooltipThemeData _tooltipTheme(Color background, Color foreground) =>
      TooltipThemeData(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
        ),
        textStyle: TextStyle(color: foreground, fontSize: 11),
        waitDuration: const Duration(milliseconds: 450),
      );
}

class _EngineStartupView extends StatelessWidget {
  const _EngineStartupView({
    required this.failed,
    required this.onRetry,
    this.error,
  });

  final bool failed;
  final VoidCallback? onRetry;

  /// Başlatma hatasının teknik ayrıntısı; tanı için ekranda gösterilir.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [Color(0xFF17191D), Color(0xFF09090B)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed)
                  const Icon(
                    Icons.memory_rounded,
                    size: 34,
                    color: Colors.white54,
                  )
                else
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  failed ? l10n.engineStartFailed : l10n.engineStarting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.engineStartFailedHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        '$error',
                        textAlign: TextAlign.center,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF9F0A),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.retry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.uiPreferences,
    this.historyStore,
    this.updateService,
  });

  final UiPreferencesController? uiPreferences;

  /// Testlerde sahte depo enjekte etmek için; null ise gerçek depo kullanılır.
  final PlaybackHistoryStore? historyStore;

  /// Testlerde sahte güncelleme servisi enjekte etmek için.
  final UpdateService? updateService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _pickingFile = false;
  bool _openingIndexer = false;
  late final PlaybackHistoryStore _historyStore =
      widget.historyStore ?? PlaybackHistoryStore();
  late final UpdateService _updateService =
      widget.updateService ?? UpdateService();
  List<PlaybackHistoryEntry> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Açılışta yeni sürüm kontrolü; bulunursa diyalog gösterilir.
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final latest = await _updateService.checkForUpdate();
      if (!mounted || latest == null) return;
      await _showUpdateDialog(latest);
    } catch (_) {
      // Güncelleme kontrolü (ağ hatası vb.) uygulama açılışını engellemez.
    }
  }

  Future<void> _showUpdateDialog(ReleaseInfo release) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _UpdateDialog(release: release, service: _updateService, l10n: l10n),
    );
  }

  Future<void> _loadHistory() async {
    List<PlaybackHistoryEntry> entries;
    try {
      entries = await _historyStore.load();
    } catch (_) {
      // Geçmiş okunamazsa bölüm gizli kalır.
      return;
    }
    if (mounted) setState(() => _history = entries);
  }

  Future<void> _removeHistoryEntry(PlaybackHistoryEntry entry) async {
    try {
      await _historyStore.remove(entry.nzbPath);
    } catch (_) {
      // Silme başarısızsa liste eski hâliyle kalır.
      return;
    }
    await _loadHistory();
  }

  Future<void> _openPath(String path) async {
    await Navigator.of(
      context,
    ).push(_fadeRoute(PlayerScreen(nzbPath: path), opaque: true));
    // Oynatıcıdan dönüşte izleme ilerlemesi tazelenir.
    await _loadHistory();
  }

  Future<void> _pickAndPlay(BuildContext context) async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      const typeGroup = XTypeGroup(label: 'NZB', extensions: ['nzb']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null || !context.mounted) return;
      await _openPath(file.path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).errorOpenNzb('$error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  /// Indexer ayarları tamamsa arama ekranını açar; eksikse önce bilgilendirip
  /// ayarlar ekranına götürür.
  Future<void> _openIndexerSearch(BuildContext context) async {
    if (_openingIndexer) return;
    setState(() => _openingIndexer = true);
    try {
      IndexerSettings settings;
      try {
        settings = await IndexerSettingsStore().load();
      } catch (_) {
        // Secure storage okunamazsa ayarları yeniden girmeye yönlendir.
        settings = const IndexerSettings();
      }
      if (!context.mounted) return;
      if (settings.isComplete) {
        await Navigator.of(context).push(_fadeRoute(const SearchScreen()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).indexerMissingHint),
          ),
        );
        await Navigator.of(
          context,
        ).push(_fadeRoute(SettingsScreen(uiPreferences: widget.uiPreferences)));
      }
    } finally {
      if (mounted) setState(() => _openingIndexer = false);
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(_fadeRoute(SettingsScreen(uiPreferences: widget.uiPreferences)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          // Koyu modda logo zeminiyle aynı lacivert aile (logo: #0B0E17);
          // açık modda aynı ailenin aydınlık karşılığı.
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.15,
            colors: isDark
                ? const [Color(0xFF161D33), Color(0xFF05070D)]
                : const [Color(0xFFFFFFFF), Color(0xFFDDE3F2)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _GlassIconButton(
                    icon: Icons.settings_rounded,
                    tooltip: AppLocalizations.of(
                      context,
                    ).providerSettingsTooltip,
                    onPressed: () => _openSettings(context),
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 72, 28, 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AppLogoMark(),
                      const SizedBox(height: 20),
                      Text(
                        'zanzibarr',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground.withValues(
                                alpha: isDark ? 0.9 : 0.75,
                              ),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 5.2,
                            ),
                      ),
                      const SizedBox(height: 34),
                      _OpenMediaCard(
                        busy: _pickingFile,
                        icon: Icons.folder_open_rounded,
                        title: l10n.selectNzbAndPlay,
                        subtitle: l10n.selectNzbHint,
                        // TV kumandasında D-pad gezintisinin başlayabilmesi
                        // için ilk odak bu kartta kalır.
                        autofocus: true,
                        onPressed: () => _pickAndPlay(context),
                      ),
                      const SizedBox(height: 12),
                      _OpenMediaCard(
                        busy: _openingIndexer,
                        icon: Icons.travel_explore_rounded,
                        title: l10n.searchIndexerCard,
                        subtitle: l10n.searchIndexerCardHint,
                        onPressed: () => _openIndexerSearch(context),
                      ),
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _ContinueWatchingSection(
                          entries: _history,
                          onOpen: (entry) => _openPath(entry.nzbPath),
                          onRemove: _removeHistoryEntry,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Route<T> _fadeRoute<T>(Widget page, {bool opaque = true}) =>
    PageRouteBuilder<T>(
      opaque: opaque,
      transitionDuration: const Duration(milliseconds: 190),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, animation, _) => page,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );

class _AppLogoMark extends StatelessWidget {
  const _AppLogoMark();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset('assets/zanzibarr-logo.png', width: 92, height: 92),
      ),
    ),
  );
}

class _OpenMediaCard extends StatelessWidget {
  const _OpenMediaCard({
    required this.onPressed,
    required this.busy,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.autofocus = false,
  });

  final VoidCallback onPressed;
  final bool busy;
  final IconData icon;
  final String title;
  final String subtitle;

  /// TV kumandasında D-pad gezintisinin başlayabilmesi için ilk odağın bir
  /// kartta olması gerekir; yalnızca ilk kartta true olmalı.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    return Material(
      color: foreground.withValues(alpha: isDark ? 0.055 : 0.045),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: foreground.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onPressed,
        hoverColor: foreground.withValues(alpha: 0.045),
        autofocus: autofocus,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: foreground.withValues(alpha: 0.7),
                        ),
                      )
                    : Icon(
                        icon,
                        size: 21,
                        color: foreground.withValues(alpha: 0.7),
                      ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.38),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!busy)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: foreground.withValues(alpha: 0.3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        color: foreground.withValues(alpha: 0.6),
        style: IconButton.styleFrom(
          backgroundColor: foreground.withValues(alpha: 0.055),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: foreground.withValues(alpha: 0.08)),
          ),
        ),
      ),
    );
  }
}

/// Ana ekrandaki "izlemeye devam et" bölümü: son oynatılan içeriklerin
/// ilerleme çubuklu listesi; dokunulunca kaldığı yerden açılır.
class _ContinueWatchingSection extends StatelessWidget {
  const _ContinueWatchingSection({
    required this.entries,
    required this.onOpen,
    required this.onRemove,
  });

  final List<PlaybackHistoryEntry> entries;
  final ValueChanged<PlaybackHistoryEntry> onOpen;
  final ValueChanged<PlaybackHistoryEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            l10n.continueWatching,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HistoryCard(
              entry: entry,
              onOpen: () => onOpen(entry),
              onRemove: () => onRemove(entry),
            ),
          ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  final PlaybackHistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    final remaining = Duration(
      milliseconds: ((entry.durationSeconds - entry.positionSeconds) * 1000)
          .round(),
    );
    return Material(
      color: foreground.withValues(alpha: isDark ? 0.045 : 0.035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: foreground.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        hoverColor: foreground.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.durationSeconds > 0
                        ? '${formatPlayerDuration(entry.position)} / '
                              '${formatPlayerDuration(Duration(milliseconds: (entry.durationSeconds * 1000).round()))}'
                        : formatPlayerDuration(entry.position),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.45),
                      fontSize: 10.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      tooltip: l10n.historyRemoveTooltip,
                      padding: EdgeInsets.zero,
                      iconSize: 15,
                      icon: Icon(
                        Icons.close_rounded,
                        color: foreground.withValues(alpha: 0.4),
                      ),
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: entry.progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: foreground.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (entry.durationSeconds > 0 && remaining > Duration.zero) ...[
                const SizedBox(height: 5),
                Text(
                  l10n.historyRemaining(formatPlayerDuration(remaining)),
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.38),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Yeni sürüm bildirimi diyaloğu: notlar + atla/sonra/güncelle seçenekleri.
/// Android'de güncelleme APK'sı indirilip sistem yükleyicisine verilir;
/// diğer platformlarda release sayfası tarayıcıda açılır.
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.release,
    required this.service,
    required this.l10n,
  });

  final ReleaseInfo release;
  final UpdateService service;
  final AppLocalizations l10n;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _install() async {
    final l10n = widget.l10n;
    setState(() => _downloading = true);
    try {
      await widget.service.install(
        widget.release,
        onProgress: (value) => setState(() => _progress = value),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.updateFailed('$error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final release = widget.release;
    return AlertDialog(
      title: Text(l10n.updateAvailable),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Text(
            release.notes.trim(),
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
      ),
      actions: [
        if (_downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              semanticsLabel: l10n.updateDownloading,
            ),
          )
        else ...[
          TextButton(
            onPressed: () {
              widget.service.skipVersion(release.version);
              Navigator.of(context).pop();
            },
            child: Text(l10n.updateSkip),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.updateLater),
          ),
          FilledButton(
            onPressed: _install,
            child: Text(
              widget.service.canAutoInstall
                  ? l10n.updateNow
                  : l10n.updateOpenPage,
            ),
          ),
        ],
      ],
    );
  }
}
