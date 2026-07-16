import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player/player_screen.dart';
import 'settings/settings_screen.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  runApp(const UseNewsApp());
}

class UseNewsApp extends StatelessWidget {
  const UseNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UseNews',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickAndPlay(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'NZB', extensions: ['nzb']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(nzbPath: file.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = engineInfo();

    return Scaffold(
      appBar: AppBar(
        title: const Text('UseNews'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Sağlayıcı ayarları',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_outline, size: 72),
            const SizedBox(height: 16),
            Text(
              'Usenet\'ten seek edilebilir oynatma',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pickAndPlay(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('NZB seç ve oynat'),
            ),
            const SizedBox(height: 32),
            Text(
              'Motor: $engine',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
