import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:usenews/player/gyuni_player_controls.dart';

Widget _buildChrome({
  bool playing = true,
  bool buffering = false,
  double volume = 80,
  VoidCallback? onVideoTap,
  ValueChanged<int>? onDoubleTapSeek,
  VoidCallback? onToggleFullscreen,
  ValueChanged<double>? onVolumeChanged,
  VoidCallback? onToggleMute,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 780,
        height: 500,
        child: GyuniPlayerChrome(
          visible: true,
          ready: true,
          playing: playing,
          buffering: buffering,
          periodicInfoVisible: false,
          filename: 'ornek.mkv',
          status: 'Hazır',
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 90),
          rate: 1.0,
          tracks: const Tracks(),
          selectedTrack: const Track(),
          volume: volume,
          onActivity: () {},
          onVideoTap: onVideoTap ?? () {},
          onTogglePlay: () {},
          onClose: () {},
          onToggleFullscreen: onToggleFullscreen ?? () {},
          onTogglePictureInPicture: () {},
          onToggleCanvas: () {},
          onToggleSubtitleControls: () {},
          onDoubleTapSeek: onDoubleTapSeek ?? (_) {},
          onFrameBackward: () {},
          onFrameForward: () {},
          onScrubStart: (_) {},
          onScrubUpdate: (_) {},
          onScrubEnd: (_) {},
          onRateSelected: (_) {},
          onSubtitleSelected: (_) {},
          onAudioSelected: (_) {},
          onShowContextMenu: (_) {},
          onVolumeChanged: onVolumeChanged ?? (_) {},
          onToggleMute: onToggleMute ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _doubleTapAt(WidgetTester tester, Offset location) async {
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('oynat düğmesi yalnız alt çubukta bir kez bulunur', (
    tester,
  ) async {
    await tester.pumpWidget(_buildChrome(playing: false));

    // Üst araç çubuğundaki yinelenen düğme kaldırıldı; oynat simgesi tekil.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byTooltip('Oynatıcıyı kapat'), findsOneWidget);
  });

  testWidgets('ses kontrolü alt çubukta görünür ve kaydırıcı değeri yansıtır', (
    tester,
  ) async {
    await tester.pumpWidget(_buildChrome());

    expect(find.byTooltip('Sesi kapat'), findsOneWidget);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    // Zaman çizelgesi kaydırıcısının yanında ses kaydırıcısı (0.8) da var.
    expect(sliders.any((slider) => slider.value == 0.8), isTrue);
  });

  testWidgets('tek tık video üzerinde onVideoTap tetikler', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_buildChrome(onVideoTap: () => taps++));

    await tester.tapAt(const Offset(390, 250));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

    expect(taps, 1);
  });

  testWidgets('çift tık sol/sağ bölgede seek, ortada tam ekran tetikler', (
    tester,
  ) async {
    final seeks = <int>[];
    var fullscreenToggles = 0;
    await tester.pumpWidget(
      _buildChrome(
        onDoubleTapSeek: seeks.add,
        onToggleFullscreen: () => fullscreenToggles++,
      ),
    );

    // Sol bölge: -10 sn
    await _doubleTapAt(tester, const Offset(90, 250));
    expect(seeks, [-1]);

    // Sağ bölge: +10 sn
    await _doubleTapAt(tester, const Offset(690, 250));
    expect(seeks, [-1, 1]);

    // Orta bölge: tam ekran
    await _doubleTapAt(tester, const Offset(390, 250));
    expect(fullscreenToggles, 1);
    expect(seeks, [-1, 1]);
  });

  testWidgets('ara belleğe alma göstergesi merkezde tekil görünür', (
    tester,
  ) async {
    await tester.pumpWidget(_buildChrome(buffering: true));

    // Alt çubuktaki küçük gösterge kaldırıldı; yalnız merkezi halka kalır.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
