import 'dart:io';

// Tanı amaçlı ilerleme çıktıları test loguna yazılır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/player/player_screen.dart';
import 'package:zanzibarr/settings/ui_preferences.dart';
import 'package:zanzibarr/src/rust/frb_generated.dart';

/// The Runner NZB için teşhis: görüntü oranı (pillarbox raporu) ve çift
/// sesli içerikte otomatik ses seçimi. Yalnız geliştirici makinesinde anlamlı
/// (gerçek Keychain kimliği + NZB gerekir); CI'da koşmaz.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
    MediaKit.ensureInitialized();
  });

  testWidgets('The Runner: video oranı + ses izleri teşhisi', (tester) async {
    final nzbPath =
        '${Platform.environment['HOME']}/nzb-test/'
        'The.Runner.2026.1080p.AMZN.WEB-DL.DUAL.DDP5.1.Atmos.H.264-TURG.nzb';
    expect(File(nzbPath).existsSync(), isTrue);

    final uiPreferences = UiPreferencesController(UiPreferencesStore())
      ..locale = const Locale('tr');
    await tester.pumpWidget(
      ZanzibarrApp(
        uiPreferences: uiPreferences,
        home: PlayerScreen(nzbPath: nzbPath),
      ),
    );
    await tester.pump();

    // Oynatma hazır olana kadar bekle (gerçek zamanlı; ağ koşuluna bağlı).
    var ready = false;
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final states = tester.stateList(find.byType(PlayerScreen)).toList();
      if (states.isEmpty) continue;
      final state = states.first as dynamic;
      if (state.startupErrorForTest != null) {
        fail('açılış hatası: ${state.startupErrorForTest}');
      }
      if (state.playbackReadyForTest == true) {
        ready = true;
        break;
      }
    }
    expect(ready, isTrue, reason: 'oynatma süresinde hazır olmadı');

    final state = tester.state(find.byType(PlayerScreen)) as dynamic;
    final controller = state.playbackControllerForTest;

    Future<String> prop(String name) async =>
        ((await controller.debugGetProperty(name)) as String).trim();

    print('=== VIDEO PARAMS ===');
    for (final p in [
      'video-params/w',
      'video-params/h',
      'video-params/aspect',
      'video-params/sar',
      'video-params/dar',
      'video-params/pixelformat',
      'video-out-params/w',
      'video-out-params/h',
      'video-out-params/aspect',
      'dwidth',
      'dheight',
    ]) {
      try {
        print('$p = ${await prop(p)}');
      } catch (e) {
        print('$p = <hata: $e>');
      }
    }

    print('=== SES İZLERİ ===');
    try {
      final count = await prop('track-list/count');
      print('track-list/count = $count');
      final n = int.tryParse(count) ?? 0;
      for (var i = 0; i < n; i++) {
        final type = await prop('track-list/$i/type');
        if (type != 'audio') continue;
        final id = await prop('track-list/$i/id');
        final lang = await prop('track-list/$i/lang');
        final codec = await prop('track-list/$i/codec');
        final title = await prop('track-list/$i/title');
        final selected = await prop('track-list/$i/selected');
        print('audio[$i]: id=$id lang=$lang codec=$codec title=$title selected=$selected');
      }
    } catch (e) {
      print('track-list hatası: $e');
    }
    print('aid (seçili) = ${await prop('aid')}');
    print('current-tracks/audio = ${await prop('current-tracks/audio/id')}');
    print('ao = ${await prop('current-ao')}');
    print('audio-params = ${await prop('audio-params')}');

    // Kapanış akışı.
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
