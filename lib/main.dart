import 'package:flutter/material.dart';

import 'settings/settings_screen.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
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

/// Faz 0 köprü kanıtı: ekrandaki metinler Rust tarafından üretilir.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bridgeMessage = greet(name: 'UseNews');
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
            const Text('🦀', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              bridgeMessage,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Motor: $engine',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
