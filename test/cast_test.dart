import 'dart:async';
import 'dart:io';

import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/cast/cast_device_picker.dart';
import 'package:zanzibarr/cast/cast_service.dart';
import 'package:zanzibarr/player/gyuni_player_controls.dart';

import 'l10n_test_helper.dart';

void main() {
  group('castMediaTypeFor', () {
    test('uzantıdan medya türü eşlemesi', () {
      expect(castMediaTypeFor('film.mkv'), CastMediaType.mkv);
      expect(castMediaTypeFor('dizi.MP4'), CastMediaType.mp4);
      expect(castMediaTypeFor('kayıt.m4v'), CastMediaType.mp4);
      expect(castMediaTypeFor('yayin.ts'), CastMediaType.mpegTs);
      expect(castMediaTypeFor('kamera.m2ts'), CastMediaType.mpegTs);
      expect(castMediaTypeFor('bilinmeyen.xyz'), CastMediaType.mkv);
    });
  });

  group('CastDevicePicker', () {
    testWidgets('cihaz listelenir ve seçim diyaloğu kapatır', (tester) async {
      final service = FakeCastController([
        CastDevice(
          id: '1',
          name: 'Salon TV',
          protocol: CastProtocol.chromecast,
          address: InternetAddress('192.168.1.20'),
          port: 8009,
        ),
      ]);
      CastDevice? selected;
      await tester.pumpWithL10n(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                selected = await CastDevicePicker.show(
                  context,
                  service: service,
                );
              },
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Salon TV'), findsOneWidget);
      expect(find.text('Chromecast'), findsOneWidget);
      await tester.tap(find.text('Salon TV'));
      await tester.pump();
      expect(selected?.name, 'Salon TV');
    });

    testWidgets('keşif boşken aranıyor, yayın kapanınca bulunamadı metni', (
      tester,
    ) async {
      final controller = StreamController<List<CastDevice>>();
      final service = FakeCastController([], stream: controller.stream);
      await tester.pumpWithL10n(
        Scaffold(body: CastDevicePicker(service: service)),
      );
      await tester.pump();
      expect(find.text('Cihazlar aranıyor…'), findsOneWidget);
      await controller.close();
      await tester.pump();
      expect(find.text('Ağınızda yansıtma cihazı bulunamadı.'), findsOneWidget);
    });
  });

  group('chrome cast düğmesi', () {
    testWidgets('castAvailable=false iken düğme görünmez', (tester) async {
      await tester.pumpWithL10n(buildCastChrome(castAvailable: false));
      expect(find.byIcon(Icons.cast_rounded), findsNothing);
      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
    });

    testWidgets('castAvailable=true iken düğme görünür ve onCast çağrılır', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWithL10n(
        buildCastChrome(castAvailable: true, onCast: () => tapped++),
      );
      expect(find.byIcon(Icons.cast_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('TV\'ye yansıt'));
      // Chrome'un çift-tık (seek/tam ekran) tanıyıcısı arena'yı tuttuğu için
      // tek tık, çift tık zaman aşımı dolunca düğmeye ulaşır.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      expect(tapped, 1);
    });

    testWidgets('casting=true iken bağlı simgesi görünür', (tester) async {
      await tester.pumpWithL10n(
        buildCastChrome(castAvailable: true, casting: true),
      );
      expect(find.byIcon(Icons.cast_connected_rounded), findsOneWidget);
    });
  });

  group('FakeCastSession sözleşmesi', () {
    test('kumanda çağrıları kaydedilir', () async {
      final session = FakeCastSession();
      await session.play();
      await session.seek(const Duration(minutes: 5));
      await session.pause();
      await session.setVolume(0.4);
      expect(session.calls, ['play', 'seek:300', 'pause', 'volume:0.4']);
    });
  });
}

Widget buildCastChrome({
  bool castAvailable = false,
  bool casting = false,
  VoidCallback? onCast,
}) {
  return Scaffold(
    body: SizedBox(
      width: 780,
      height: 500,
      child: GyuniPlayerChrome(
        visible: true,
        ready: true,
        playing: true,
        buffering: false,
        periodicInfoVisible: false,
        filename: 'ornek.mkv',
        status: 'Hazır',
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 90),
        rate: 1.0,
        tracks: const Tracks(),
        selectedTrack: const Track(),
        volume: 80,
        castAvailable: castAvailable,
        casting: casting,
        onCast: onCast,
        onActivity: () {},
        onVideoTap: () {},
        onTogglePlay: () {},
        onClose: () {},
        onToggleFullscreen: () {},
        onTogglePictureInPicture: () {},
        onToggleCanvas: () {},
        onToggleVideoFit: () {},
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
      ),
    ),
  );
}

/// dart_cast'e ağa çıkmadan UI testi için sahte kontrolcü.
class FakeCastController implements CastController {
  FakeCastController(this.devices, {Stream<List<CastDevice>>? stream})
    : _stream = stream ?? Stream.value(devices);

  final List<CastDevice> devices;
  final Stream<List<CastDevice>> _stream;

  @override
  CastSession? get activeSession => null;

  @override
  Stream<List<CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) => _stream;

  @override
  void stopDiscovery() {}

  @override
  Future<CastSession> startCasting(
    CastDevice device, {
    required String url,
    required String title,
    Duration? startPosition,
    Duration? duration,
  }) => Future.value(FakeCastSession());

  @override
  Future<void> stopCasting() async {}

  @override
  Future<void> dispose() async {}
}

/// Kumanda çağrılarını kaydeden sahte oturum.
class FakeCastSession extends CastSession {
  FakeCastSession()
    : super(
        CastDevice(
          id: 'test',
          name: 'Test TV',
          protocol: CastProtocol.chromecast,
          address: InternetAddress('127.0.0.1'),
          port: 8009,
        ),
      );

  final calls = <String>[];

  @override
  Future<void> loadMedia(CastMedia media) async =>
      calls.add('load:${media.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inSeconds}');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setSubtitle(CastSubtitle? subtitle) async {}

  @override
  Future<void> disconnect() async => calls.add('disconnect');
}
