import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/player_keyboard_controls.dart';

/// Tuş yönlendirmesini gerçek oynatıcı olmadan doğrulayan sahte handler.
/// Genel alanlar arayüzdeki getter'ları karşılar; çağrılar sayaç/listelerde
/// birikir.
class _FakeHandler implements PlayerKeyboardHandler {
  @override
  bool playbackReady = true;
  @override
  bool playing = true;
  @override
  bool controlsVisible = false;
  @override
  bool canvasEditing = false;
  @override
  bool subtitleControlsVisible = false;
  @override
  bool isPictureInPicture = false;
  @override
  bool isFullscreen = false;
  @override
  bool remoteNavigationMode = true;
  @override
  Duration seekStep = const Duration(seconds: 10);

  int revealCount = 0;
  int hideCount = 0;
  int togglePlayCount = 0;
  int closeCount = 0;
  int focusPlayCount = 0;
  int endFastScanCount = 0;
  int cancelCanvasCount = 0;
  int dismissSubtitleCount = 0;
  int togglePipCount = 0;
  int exitFullscreenCount = 0;
  final seeks = <Duration>[];
  final volumeDeltas = <double>[];
  final fastScans = <int>[];

  /// Gerçek oynatıcıdaki `focusPlayButton` kablolamasının karşılığı: TV'de
  /// OK sonrası odağın düğmelere geçişini testlerde birebir taklit eder.
  FocusNode? playFocusNode;

  @override
  void revealControls() => revealCount++;
  @override
  void hideControls() => hideCount++;
  @override
  void togglePlay() => togglePlayCount++;
  @override
  void seekRelative(Duration offset) => seeks.add(offset);
  @override
  void adjustVolume(double delta) => volumeDeltas.add(delta);
  @override
  void beginFastScan(int direction) => fastScans.add(direction);
  @override
  void endFastScan() => endFastScanCount++;
  @override
  void toggleFullscreen() {}
  @override
  void exitFullscreen() => exitFullscreenCount++;
  @override
  void togglePictureInPicture() => togglePipCount++;
  @override
  void toggleCanvasEditor() {}
  @override
  void cancelCanvasEditing() => cancelCanvasCount++;
  @override
  void toggleSubtitleControls() {}
  @override
  void dismissSubtitleControls() => dismissSubtitleCount++;
  @override
  void stepBackward() {}
  @override
  void stepForward() {}
  @override
  void nudgeSubtitleDelay(Duration delta) {}
  @override
  void closePlayer() => closeCount++;
  @override
  void focusPlayButton() {
    focusPlayCount++;
    playFocusNode?.requestFocus();
  }
}

class _Harness {
  _Harness(this.handler) {
    handler.playFocusNode = playNode;
  }

  final _FakeHandler handler;
  final playNode = FocusNode(debugLabel: 'play');
  final subtitleNode = FocusNode(debugLabel: 'subtitle');
  int playPressCount = 0;
  int subtitlePressCount = 0;
}

Future<_Harness> _pumpPlayer(WidgetTester tester, {_FakeHandler? handler}) {
  final harness = _Harness(handler ?? _FakeHandler());
  return tester
      .pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerKeyboardControls(
              handler: harness.handler,
              child: Column(
                children: [
                  IconButton(
                    focusNode: harness.playNode,
                    onPressed: () => harness.playPressCount++,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    focusNode: harness.subtitleNode,
                    onPressed: () => harness.subtitlePressCount++,
                    icon: const Icon(Icons.subtitles_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
      .then((_) => tester.pump())
      .then((_) => harness);
}

/// Android TV geri tuşu KEYCODE_BACK olarak gelir; fiziksel karşılığı test
/// haritasında olmadığından android scancode haritasında bulunan nötr bir
/// fiziksel tuş verilir (mantıksal tuş yine goBack'tir).
Future<void> _sendGoBack(WidgetTester tester) => tester.sendKeyEvent(
  LogicalKeyboardKey.goBack,
  physicalKey: PhysicalKeyboardKey.escape,
);

void main() {
  testWidgets('sol/sağ ok seek adımıyla seek tetikler', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(handler.seeks, [
      const Duration(seconds: -10),
      const Duration(seconds: 10),
    ]);
  });

  testWidgets('yukarı/aşağı ok sesi değiştirir', (tester) async {
    final harness = await _pumpPlayer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(harness.handler.volumeDeltas, [5.0, -5.0]);
  });

  testWidgets('OK/enter/select/mediaPlayPause oynat-duraklat yapar', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    // Kök odaktayken OK genel oynat/duraklat kısayoludur.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(handler.togglePlayCount, 1);
    expect(handler.focusPlayCount, 1);

    // İlk OK odağı oynat düğmesine taşır; sonraki enter/space o düğmeyi
    // etkinleştirir (üretimde düğme callback'i yine _togglePlay'e bağlıdır).
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(harness.playPressCount, 1);
    expect(handler.togglePlayCount, 1);

    // Medya tuşları odaktan bağımsız genel kısayol olarak kalır.
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    expect(handler.togglePlayCount, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(harness.playPressCount, 2);
  });

  testWidgets('mediaPlay yalnız duraklatılmışken, mediaPause yalnız '
      'oynatılırken etkilidir', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    handler.playing = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    expect(handler.togglePlayCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
    expect(handler.togglePlayCount, 1);

    handler.playing = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    expect(handler.togglePlayCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
    expect(handler.togglePlayCount, 2);
  });

  testWidgets('mediaFastForward/mediaRewind seek ileri/geri yapar', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);

    expect(harness.handler.seeks, [
      const Duration(seconds: 10),
      const Duration(seconds: -10),
    ]);
  });

  testWidgets('geri tuşu kontroller açıkken önce gizler, kapalıyken çıkar', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    handler.controlsVisible = true;
    await _sendGoBack(tester);
    expect(handler.hideCount, 1);
    expect(handler.closeCount, 0);

    handler.controlsVisible = false;
    await _sendGoBack(tester);
    expect(handler.hideCount, 1);
    expect(handler.closeCount, 1);
  });

  testWidgets('escape TV modunda geri ile aynı davranır', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    handler.controlsVisible = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(handler.hideCount, 1);
    expect(handler.closeCount, 0);

    handler.controlsVisible = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(handler.closeCount, 1);
  });

  testWidgets('masaüstünde escape kontrolleri gösterir (mevcut davranış)', (
    tester,
  ) async {
    final handler = _FakeHandler()..remoteNavigationMode = false;
    await _pumpPlayer(tester, handler: handler);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(handler.revealCount, 1);
    expect(handler.hideCount, 0);
    expect(handler.closeCount, 0);
  });

  testWidgets('geri tuşu özel modları öncelikle kapatır', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    handler.canvasEditing = true;
    await _sendGoBack(tester);
    expect(handler.cancelCanvasCount, 1);
    expect(handler.closeCount, 0);

    handler.canvasEditing = false;
    handler.subtitleControlsVisible = true;
    await _sendGoBack(tester);
    expect(handler.dismissSubtitleCount, 1);

    handler.subtitleControlsVisible = false;
    handler.isPictureInPicture = true;
    await _sendGoBack(tester);
    expect(handler.togglePipCount, 1);

    handler.isPictureInPicture = false;
    handler.isFullscreen = true;
    await _sendGoBack(tester);
    expect(handler.exitFullscreenCount, 1);
    expect(handler.closeCount, 0);
  });

  testWidgets('TV: OK odağı oynat düğmesine taşır, D-pad düğmeler arasında '
      'gezinir ve auto-hide sıfırlanır', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    // Başlangıçta kök odak düğümünde (autofocus); düğmeler odaksuz.
    expect(harness.playNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(harness.playNode.hasFocus, isTrue);

    // Odak kontrollerdeyken D-pad ses/seek DEĞİL focus gezintisi yapar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(handler.volumeDeltas, isEmpty);
    expect(handler.seeks, isEmpty);
    expect(harness.subtitleNode.hasFocus, isTrue);
    // Gezinti kontrolleri görünür tutar (auto-hide sayacı sıfırlanır).
    expect(handler.revealCount, greaterThan(0));
  });

  testWidgets('TV: odak düğmedeyken OK o düğmeyi etkinleştirir, genel '
      'oynat/duraklatı değil', (tester) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    harness.subtitleNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(harness.subtitlePressCount, 1);
    expect(handler.togglePlayCount, 0);

    // Space de aynı şekilde odaktaki düğmeye gider.
    harness.playNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(harness.playPressCount, 1);
    expect(handler.togglePlayCount, 0);
  });

  testWidgets('TV: kontroller gizlenirken odak kök düğüme geri verilir', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);
    final handler = harness.handler;

    harness.playNode.requestFocus();
    await tester.pump();
    handler.controlsVisible = true;

    await _sendGoBack(tester);
    await tester.pump();

    expect(handler.hideCount, 1);
    expect(harness.playNode.hasFocus, isFalse);
    // Odak köke döndüğünde sonraki ok tuşu yeniden seek yapar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(handler.seeks, [const Duration(seconds: -10)]);
  });

  testWidgets('masaüstünde odak düğmedeyken bile space/oklar genel kısayol '
      'olarak kalır', (tester) async {
    final handler = _FakeHandler()..remoteNavigationMode = false;
    final harness = await _pumpPlayer(tester, handler: handler);

    harness.subtitleNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(handler.togglePlayCount, 1);
    expect(harness.subtitlePressCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(handler.seeks, [const Duration(seconds: -10)]);
  });

  testWidgets('oynatma hazır değilse D-pad ve medya tuşları yok sayılır', (
    tester,
  ) async {
    final handler = _FakeHandler()..playbackReady = false;
    await _pumpPlayer(tester, handler: handler);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);

    expect(handler.seeks, isEmpty);
    expect(handler.togglePlayCount, 0);
  });
}
