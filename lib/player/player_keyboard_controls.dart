import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Oynatıcı ekranının klavye ve TV kumandası tuş yönlendirmesi.
///
/// Masaüstü kısayolları (Space/K, J/L, F, P, C, S, , . [ ]) ile Android TV
/// kumandası tuşları (D-pad okları, OK/select/enter, medya tuşları, geri)
/// aynı odak düğümünde birleştirilir. Tuş işlemlerinin uygulanması
/// [PlayerKeyboardHandler] üzerinden yapılır; bu sayede yönlendirme mantığı
/// gerçek oynatıcı olmadan widget testlerinde doğrulanabilir.
abstract interface class PlayerKeyboardHandler {
  bool get playbackReady;
  bool get playing;
  bool get controlsVisible;
  bool get canvasEditing;
  bool get subtitleControlsVisible;
  bool get isPictureInPicture;
  bool get isFullscreen;

  /// Dokunmatik öncelikli platform (Android/iOS; Android TV dahil). Açıkken
  /// odak kontrol düğmelerindeyse D-pad gezintisi ve OK etkinleştirmesi
  /// varsayılan focus traversal'a bırakılır; kapalıyken (masaüstü) ok ve
  /// space/enter tuşları her zaman genel oynatıcı kısayolu olarak çalışır.
  bool get remoteNavigationMode;

  Duration get seekStep;

  void revealControls();
  void hideControls();
  void togglePlay();
  void seekRelative(Duration offset);
  void adjustVolume(double delta);
  void beginFastScan(int direction);
  void endFastScan();
  void toggleFullscreen();
  void exitFullscreen();
  void togglePictureInPicture();
  void toggleCanvasEditor();
  void cancelCanvasEditing();
  void toggleSubtitleControls();
  void dismissSubtitleControls();
  void stepBackward();
  void stepForward();
  void nudgeSubtitleDelay(Duration delta);
  void closePlayer();

  /// TV'de OK ile kontroller açıldığında oynat/duraklat düğmesine odak verir;
  /// masaüstünde no-op olmalıdır.
  void focusPlayButton();
}

/// Oynatıcı video yüzeyini saran ve [handler]'a tuşları ileten odak düğümü.
/// Mevcut davranışla aynı şekilde `autofocus` açıktır ve odak kaybında
/// hızlı tarama (J/L) sonlandırılır.
class PlayerKeyboardControls extends StatelessWidget {
  const PlayerKeyboardControls({
    super.key,
    required this.handler,
    required this.child,
  });

  final PlayerKeyboardHandler handler;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => handlePlayerKeyEvent(node, event, handler),
      onFocusChange: (focused) {
        if (!focused) handler.endFastScan();
      },
      child: child,
    );
  }
}

/// D-pad gezintisi veya düğme etkinleştirmesi olarak varsayılan davranışa
/// bırakılacak tuşlar (yalnız TV modunda, odak kontrollerdeyken).
bool _isTraversalOrActivationKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.arrowLeft ||
    key == LogicalKeyboardKey.arrowRight ||
    key == LogicalKeyboardKey.arrowUp ||
    key == LogicalKeyboardKey.arrowDown ||
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.space ||
    key == LogicalKeyboardKey.gameButtonA;

KeyEventResult handlePlayerKeyEvent(
  FocusNode node,
  KeyEvent event,
  PlayerKeyboardHandler handler,
) {
  final key = event.logicalKey;
  if (event is KeyUpEvent) {
    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyL) {
      handler.endFastScan();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }

  // Geri: özel modları sırayla kapat. TV'de (veya kumandanın goBack tuşunda)
  // kontroller görünüyorsa önce gizlenir, gizliyse oynatıcıdan çıkılır.
  // Masaüstündeki Esc davranışı (kontrolleri göster) korunur.
  if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
    if (handler.canvasEditing) {
      handler.cancelCanvasEditing();
    } else if (handler.subtitleControlsVisible) {
      handler.dismissSubtitleControls();
    } else if (handler.isPictureInPicture) {
      handler.togglePictureInPicture();
    } else if (handler.isFullscreen) {
      handler.exitFullscreen();
    } else if (key == LogicalKeyboardKey.goBack || handler.remoteNavigationMode) {
      if (handler.controlsVisible) {
        handler.hideControls();
        // Odak bir kontrol düğmesinde kaldıysa köke geri ver ki sonraki
        // D-pad basışları yeniden oynatma kısayolu olarak çalışsın.
        node.requestFocus();
      } else {
        handler.closePlayer();
      }
    } else {
      handler.revealControls();
    }
    return KeyEventResult.handled;
  }
  if (!handler.playbackReady) return KeyEventResult.ignored;

  final firstDown = event is KeyDownEvent;
  final focusInControls = node.hasFocus && !node.hasPrimaryFocus;

  // TV'de odak bir kontrol düğmesindeyken D-pad düğmeler arasında gezinir
  // (varsayılan DirectionalFocusIntent) ve OK odaktaki düğmeyi etkinleştirir
  // (ActivateIntent); tuşlar burada genel kısayola dönüştürülmez.
  if (handler.remoteNavigationMode &&
      focusInControls &&
      _isTraversalOrActivationKey(key)) {
    // Gezinti sırasında auto-hide sayacı sıfırlanır; kontroller açık kalır.
    handler.revealControls();
    return KeyEventResult.ignored;
  }

  if (key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.keyK ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.mediaPlayPause) {
    if (firstDown) {
      handler.togglePlay();
      handler.focusPlayButton();
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.mediaPlay) {
    if (firstDown && !handler.playing) handler.togglePlay();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.mediaPause) {
    if (firstDown && handler.playing) handler.togglePlay();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.mediaRewind ||
      key == LogicalKeyboardKey.mediaFastForward) {
    final backward =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind;
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    // Shift+ok masaüstünde 1 sn hassas adım; medya tuşları her zaman ayarlı
    // seek adımını kullanır.
    final step = isArrow && HardwareKeyboard.instance.isShiftPressed
        ? const Duration(seconds: 1)
        : handler.seekStep;
    handler.seekRelative(backward ? _negateDuration(step) : step);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    handler.adjustVolume(key == LogicalKeyboardKey.arrowUp ? 5 : -5);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyL) {
    if (firstDown) {
      handler.beginFastScan(key == LogicalKeyboardKey.keyJ ? -1 : 1);
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyF) {
    if (firstDown) handler.toggleFullscreen();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyP) {
    if (firstDown) handler.togglePictureInPicture();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyC) {
    if (firstDown) handler.toggleCanvasEditor();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyS) {
    if (firstDown) handler.toggleSubtitleControls();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.comma) {
    if (firstDown) handler.stepBackward();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.period) {
    if (firstDown) handler.stepForward();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.bracketLeft) {
    handler.nudgeSubtitleDelay(const Duration(milliseconds: -100));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.bracketRight) {
    handler.nudgeSubtitleDelay(const Duration(milliseconds: 100));
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

Duration _negateDuration(Duration value) =>
    Duration(microseconds: -value.inMicroseconds);
