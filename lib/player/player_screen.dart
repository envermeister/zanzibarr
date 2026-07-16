import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../settings/provider_settings.dart';
import '../src/rust/api/streaming.dart';

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
  });

  final String nzbPath;

  /// Testlerde sahte depo enjekte etmek için; null ise gerçek depo kullanılır.
  final ProviderSettingsStore? store;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  String _status = 'Hazırlanıyor…';
  StreamInfo? _info;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final store = widget.store ?? ProviderSettingsStore();
      final settings = await store.load();
      if (!settings.isComplete) {
        setState(() => _error =
            'Sağlayıcı ayarları eksik. Önce ayar ekranından bilgileri girin.');
        return;
      }

      setState(() => _status =
          'Bağlanılıyor ve ilk segment çekiliyor (yerleşim öğreniliyor)…');

      final info = await startStream(
        config: ProviderConfigDto(
          host: settings.host,
          port: settings.port,
          username: settings.username,
          password: settings.password,
          maxConnections: settings.maxConnections,
        ),
        nzbPath: widget.nzbPath,
      );

      if (!mounted) return;
      setState(() {
        _info = info;
        _status = 'Oynatılıyor: ${info.filename}';
      });

      await _player.open(Media(info.url));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_info?.filename ?? 'Oynatıcı'),
      ),
      body: _error != null
          ? _ErrorView(message: _error.toString())
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: Video(controller: _controller),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_status),
                      if (_info case final info?) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Boyut: ${_humanSize(info.size)} · '
                          '${info.segmentCount} segment · ${info.url}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

String _humanSize(BigInt bytes) {
  final b = bytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = b;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(2)} ${units[unit]}';
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
