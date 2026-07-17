import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player/player_screen.dart';
import 'settings/settings_screen.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UseNewsBootstrap());
}

Future<void> _initializeNativeEngine() async {
  MediaKit.ensureInitialized();
  await RustLib.init();
}

/// İlk native çağrı hata verse veya takılsa bile boş pencere yerine anlaşılır
/// bir durum ve güvenli yeniden-deneme yolu gösterir.
class UseNewsBootstrap extends StatefulWidget {
  const UseNewsBootstrap({super.key, this.initialize});

  final Future<void> Function()? initialize;

  @override
  State<UseNewsBootstrap> createState() => _UseNewsBootstrapState();
}

class _UseNewsBootstrapState extends State<UseNewsBootstrap> {
  late Future<void> _initialization = _startInitialization();

  Future<void> _startInitialization() => Future<void>.sync(
    widget.initialize ?? _initializeNativeEngine,
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
        return const UseNewsApp();
      }
      return UseNewsApp(
        home: _EngineStartupView(
          failed: snapshot.hasError,
          onRetry: snapshot.hasError ? _retry : null,
        ),
      );
    },
  );
}

class UseNewsApp extends StatelessWidget {
  const UseNewsApp({super.key, this.home = const HomeScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF453A);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF141416),
    );
    return MaterialApp(
      title: 'UseNews',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.055),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 1.2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xF228282C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xF22A2A2D),
            borderRadius: BorderRadius.circular(7),
          ),
          textStyle: const TextStyle(color: Colors.white, fontSize: 11),
          waitDuration: const Duration(milliseconds: 450),
        ),
      ),
      home: home,
    );
  }
}

class _EngineStartupView extends StatelessWidget {
  const _EngineStartupView({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
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
                failed
                    ? 'Yerel oynatma motoru başlatılamadı'
                    : 'Yerel oynatma motoru hazırlanıyor…',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (failed) ...[
                const SizedBox(height: 8),
                const Text(
                  'Motor dosyalarını ve uygulama kurulumunu kontrol edip '
                  'yeniden deneyin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yeniden dene'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _pickingFile = false;

  Future<void> _pickAndPlay(BuildContext context) async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      const typeGroup = XTypeGroup(label: 'NZB', extensions: ['nzb']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null || !context.mounted) return;
      await Navigator.of(
        context,
      ).push(_fadeRoute(PlayerScreen(nzbPath: file.path), opaque: true));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('NZB dosyası açılamadı: $error')));
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(_fadeRoute(const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final engine = engineInfo();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.15,
            colors: [Color(0xFF17191D), Color(0xFF09090B)],
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
                    icon: Icons.tune_rounded,
                    tooltip: 'Sağlayıcı ayarları',
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
                      const _PlayerMark(),
                      const SizedBox(height: 26),
                      Text(
                        'Videoya odaklan.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'NZB içeriğini indirmeden, doğrudan ve seek edilebilir '
                        'olarak oynat.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _OpenMediaCard(
                        busy: _pickingFile,
                        onPressed: () => _pickAndPlay(context),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF30D158),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Yerel motor hazır · $engine',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.32),
                                    fontSize: 11,
                                  ),
                            ),
                          ),
                        ],
                      ),
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

class _PlayerMark extends StatelessWidget {
  const _PlayerMark();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 34,
        color: Colors.white,
      ),
    ),
  );
}

class _OpenMediaCard extends StatelessWidget {
  const _OpenMediaCard({required this.onPressed, required this.busy});

  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.055),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: busy ? null : onPressed,
      hoverColor: Colors.white.withValues(alpha: 0.045),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(
                      Icons.folder_open_rounded,
                      size: 21,
                      color: Colors.white70,
                    ),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NZB seç ve oynat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Dosya sisteminden bir .nzb aç',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (!busy)
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white30,
              ),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      color: Colors.white60,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.055),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
    ),
  );
}
