import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/player/gyuni_player_controls.dart';

import 'l10n_test_helper.dart';

Widget _buildChrome({
  bool playing = true,
  bool buffering = false,
  double volume = 80,
  VoidCallback? onVideoTap,
  ValueChanged<int>? onDoubleTapSeek,
  VoidCallback? onToggleFullscreen,
  ValueChanged<double>? onVolumeChanged,
  VoidCallback? onToggleMute,
  VoidCallback? onLoadExternalAudio,
  VoidCallback? onLoadExternalSubtitle,
  ValueChanged<Offset>? onShowAdvancedSettings,
}) {
  return l10nTestApp(
    Scaffold(
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
          onShowAdvancedSettings: onShowAdvancedSettings ?? (_) {},
          onVolumeChanged: onVolumeChanged ?? (_) {},
          onToggleMute: onToggleMute ?? () {},
          onLoadExternalAudio: onLoadExternalAudio,
          onLoadExternalSubtitle: onLoadExternalSubtitle,
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

  testWidgets('parça menülerinde dosyadan yükle girişi callback tetikler', (
    tester,
  ) async {
    var audioLoads = 0;
    var subtitleLoads = 0;
    await tester.pumpWidget(
      _buildChrome(
        onLoadExternalAudio: () => audioLoads++,
        onLoadExternalSubtitle: () => subtitleLoads++,
      ),
    );

    // Popup route'un açılış animasyonu fake-async altında koordinatları
    // kaydırdığından fiziksel dokunma yerine menü öğesinin onTap'i doğrudan
    // çağrılır; öğenin varlığı ve bağlantısı burada doğrulanır.
    Future<void> settleMenu() async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(find.byTooltip('Ses izi'));
    await settleMenu();
    final audioItem = find.widgetWithText(
      PopupMenuItem<AudioTrack>,
      'Dosyadan yükle…',
    );
    expect(audioItem, findsOneWidget);
    tester.widget<PopupMenuItem<AudioTrack>>(audioItem).onTap!();
    // Gerçek kullanımda InkWell dokunması route'u da kapatır; testte menüyü
    // aynı şekilde elle kapatıyoruz ki ikinci menünün bariyeri açık kalmasın.
    Navigator.of(tester.element(audioItem)).pop();
    await settleMenu();
    expect(audioLoads, 1);
    expect(subtitleLoads, 0);

    await tester.tap(find.byTooltip('Altyazı izi'));
    await settleMenu();
    final subtitleItem = find.widgetWithText(
      PopupMenuItem<SubtitleTrack>,
      'Dosyadan yükle…',
    );
    expect(subtitleItem, findsOneWidget);
    tester.widget<PopupMenuItem<SubtitleTrack>>(subtitleItem).onTap!();
    Navigator.of(tester.element(subtitleItem)).pop();
    await settleMenu();
    expect(subtitleLoads, 1);
    expect(audioLoads, 1);
  });

  testWidgets('yükleme callback yoksa menüde dosya girişi gösterilmez', (
    tester,
  ) async {
    await tester.pumpWidget(_buildChrome());

    await tester.tap(find.byTooltip('Altyazı izi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Dosyadan yükle…'), findsNothing);
  });

  testWidgets(
    'gelişmiş ayarlar düğmesi alt çubukta görünür ve konumuyla tetikler',
    (tester) async {
      final positions = <Offset>[];
      await tester.pumpWidget(
        _buildChrome(onShowAdvancedSettings: positions.add),
      );

      final button = find.byTooltip('Gelişmiş ayarlar');
      expect(button, findsOneWidget);

      await tester.tap(button);
      // Dış GestureDetector'da çift tık tanıyıcısı yarıştığından tek tık
      // geri çağrısı arena zaman aşımı sonrası düşer (dosyadaki diğer tık
      // testleriyle aynı desen).
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

      // Menü düğmenin ekran konumundan açılır (orijin değil).
      expect(positions, hasLength(1));
      expect(positions.single.dx, greaterThan(0));
      expect(positions.single.dy, greaterThan(0));
    },
  );

  testWidgets('sağ tık gelişmiş ayarlar menüsünü açmaz', (tester) async {
    final positions = <Offset>[];
    await tester.pumpWidget(_buildChrome(onShowAdvancedSettings: positions.add));

    // Menünün tek girişi alt çubuktaki düğmedir; video üzerinde sağ tık
    // (dokunmatik/TV karşılığı yok) artık bağlı değil.
    await tester.tapAt(
      const Offset(390, 250),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(positions, isEmpty);
  });
}
