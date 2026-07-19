import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

const _accent = Color(0xFFFF453A);

class GyuniPlayerChrome extends StatelessWidget {
  const GyuniPlayerChrome({
    super.key,
    required this.visible,
    required this.ready,
    required this.playing,
    required this.buffering,
    required this.periodicInfoVisible,
    required this.filename,
    required this.status,
    required this.position,
    required this.duration,
    required this.rate,
    required this.tracks,
    required this.selectedTrack,
    required this.onActivity,
    required this.onVideoTap,
    required this.onTogglePlay,
    required this.onClose,
    required this.onToggleFullscreen,
    required this.onTogglePictureInPicture,
    required this.onToggleCanvas,
    required this.onToggleSubtitleControls,
    required this.onDoubleTapSeek,
    required this.onFrameBackward,
    required this.onFrameForward,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onRateSelected,
    required this.onSubtitleSelected,
    required this.onAudioSelected,
    required this.onShowAdvancedSettings,
    required this.volume,
    required this.onVolumeChanged,
    required this.onToggleMute,
    this.previewImage,
    this.previewPosition,
    this.editorOverlay,
    this.seekFlashDirection,
    this.isPictureInPicture = false,
    this.canvasActive = false,
    this.subtitleControlsActive = false,
    this.pictureInPictureSupported = false,
    this.engineBadge,
    this.onLoadExternalAudio,
    this.onLoadExternalSubtitle,
  });

  final bool visible;
  final bool ready;
  final bool playing;
  final bool buffering;
  final bool periodicInfoVisible;
  final bool isPictureInPicture;
  final bool canvasActive;
  final bool subtitleControlsActive;
  final bool pictureInPictureSupported;
  final String filename;
  final String status;
  final String? engineBadge;
  final Duration position;
  final Duration duration;
  final double rate;
  final Tracks tracks;
  final Track selectedTrack;
  final Uint8List? previewImage;
  final Duration? previewPosition;
  final Widget? editorOverlay;
  final int? seekFlashDirection;
  final double volume;
  final VoidCallback onActivity;
  final VoidCallback onVideoTap;
  final VoidCallback onTogglePlay;
  final VoidCallback onClose;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onTogglePictureInPicture;
  final VoidCallback onToggleCanvas;
  final VoidCallback onToggleSubtitleControls;
  final ValueChanged<int> onDoubleTapSeek;
  final VoidCallback onFrameBackward;
  final VoidCallback onFrameForward;
  final ValueChanged<Duration> onScrubStart;
  final ValueChanged<Duration> onScrubUpdate;
  final ValueChanged<Duration> onScrubEnd;
  final ValueChanged<double> onRateSelected;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  /// Alt çubuktaki "Gelişmiş ayarlar" düğmesinin callback'i. Düğme kendi
  /// ekran konumunu verir; menü o konumdan yukarı açılır. Dokunmatik
  /// ekranlarda ve TV kumandasında sağ tık karşılığı olmadığından menünün
  /// tek giriş noktası bu düğmedir.
  final ValueChanged<Offset> onShowAdvancedSettings;

  /// Kullanıcının kendi diskinden harici ses/altyazı dosyası eklemesi için
  /// parça menülerindeki "Dosyadan yükle…" girişlerinin callback'i.
  /// null bırakılırsa ilgili menüde yükleme girişi gösterilmez.
  final VoidCallback? onLoadExternalAudio;
  final VoidCallback? onLoadExternalSubtitle;

  void _handleVideoDoubleTap(BuildContext context, Offset? position) {
    final size = context.size;
    if (position == null || size == null || size.width <= 0) {
      onToggleFullscreen();
      return;
    }
    final fraction = position.dx / size.width;
    if (fraction < 0.35) {
      onDoubleTapSeek(-1);
    } else if (fraction > 0.65) {
      onDoubleTapSeek(1);
    } else {
      onToggleFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorActive = editorOverlay != null;
    final chromeVisible = !editorActive && (visible || !playing || !ready);
    // onDoubleTapDown ve onDoubleTap aynı jest dizisinde art arda tetiklenir
    // ve aynı build'in closure'ını paylaşır; çift tık konumu state tutmadan
    // güvenle okunur.
    Offset? doubleTapPosition;
    return MouseRegion(
      cursor: editorActive
          ? MouseCursor.defer
          : chromeVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onEnter: (_) => onActivity(),
      onHover: (_) => onActivity(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: editorActive ? null : onVideoTap,
        onDoubleTapDown: editorActive
            ? null
            : (details) => doubleTapPosition = details.localPosition,
        onDoubleTap: editorActive
            ? null
            : () => _handleVideoDoubleTap(context, doubleTapPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!ready) _StartupStatus(status: status, buffering: buffering),
            ?editorOverlay,
            // YouTube tarzı: ara belleğe alma göstergesi videonun ortasında
            // belirir; alt çubuk temiz kalır.
            if (ready && buffering)
              const Center(
                child: SizedBox.square(
                  dimension: 46,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white70,
                  ),
                ),
              ),
            if (seekFlashDirection case final direction?)
              _SeekFlash(direction: direction),
            if (periodicInfoVisible && !chromeVisible)
              _PeriodicPlaybackInfo(position: position, duration: duration),
            IgnorePointer(
              ignoring: !chromeVisible,
              child: ExcludeFocus(
                excluding: !chromeVisible,
                child: ExcludeSemantics(
                  excluding: !chromeVisible,
                  child: AnimatedOpacity(
                    opacity: chromeVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _TopToolbar(
                          filename: filename,
                          engineBadge: engineBadge,
                          ready: ready,
                          canvasActive: canvasActive,
                          subtitleControlsActive: subtitleControlsActive,
                          pictureInPictureSupported: pictureInPictureSupported,
                          isPictureInPicture: isPictureInPicture,
                          onClose: onClose,
                          onToggleCanvas: onToggleCanvas,
                          onToggleSubtitleControls: onToggleSubtitleControls,
                          onTogglePictureInPicture: onTogglePictureInPicture,
                          onToggleFullscreen: onToggleFullscreen,
                        ),
                        _BottomControls(
                          ready: ready,
                          playing: playing,
                          position: position,
                          duration: duration,
                          rate: rate,
                          tracks: tracks,
                          selectedTrack: selectedTrack,
                          previewImage: previewImage,
                          previewPosition: previewPosition,
                          volume: volume,
                          onTogglePlay: onTogglePlay,
                          onToggleMute: onToggleMute,
                          onVolumeChanged: onVolumeChanged,
                          onFrameBackward: onFrameBackward,
                          onFrameForward: onFrameForward,
                          onScrubStart: onScrubStart,
                          onScrubUpdate: onScrubUpdate,
                          onScrubEnd: onScrubEnd,
                          onRateSelected: onRateSelected,
                          onSubtitleSelected: onSubtitleSelected,
                          onAudioSelected: onAudioSelected,
                          onLoadExternalAudio: onLoadExternalAudio,
                          onLoadExternalSubtitle: onLoadExternalSubtitle,
                          onShowAdvancedSettings: onShowAdvancedSettings,
                        ),
                      ],
                    ),
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

class _PeriodicPlaybackInfo extends StatelessWidget {
  const _PeriodicPlaybackInfo({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMicroseconds <= 0
        ? 0.0
        : (position.inMicroseconds / duration.inMicroseconds)
              .clamp(0.0, 1.0)
              .toDouble();
    return IgnorePointer(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment(-1 + progress * 2, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xD91B1B1E),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        formatPlayerDuration(position),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(height: 2, color: Colors.white60),
                      ),
                      Positioned(
                        left: (constraints.maxWidth * progress - 2.5)
                            .clamp(
                              0.0,
                              (constraints.maxWidth - 5).clamp(
                                0.0,
                                double.infinity,
                              ),
                            )
                            .toDouble(),
                        child: Container(
                          width: 5,
                          height: 15,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupStatus extends StatelessWidget {
  const _StartupStatus({required this.status, required this.buffering});

  final String status;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: status,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC17171A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (buffering) ...[
                  const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({
    required this.filename,
    required this.engineBadge,
    required this.ready,
    required this.canvasActive,
    required this.subtitleControlsActive,
    required this.pictureInPictureSupported,
    required this.isPictureInPicture,
    required this.onClose,
    required this.onToggleCanvas,
    required this.onToggleSubtitleControls,
    required this.onTogglePictureInPicture,
    required this.onToggleFullscreen,
  });

  final String filename;
  final String? engineBadge;
  final bool ready;
  final bool canvasActive;
  final bool subtitleControlsActive;
  final bool pictureInPictureSupported;
  final bool isPictureInPicture;
  final VoidCallback onClose;
  final VoidCallback onToggleCanvas;
  final VoidCallback onToggleSubtitleControls;
  final VoidCallback onTogglePictureInPicture;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      top: 12,
      right: 14,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showFilename = constraints.maxWidth >= 520;
            final showEngine = constraints.maxWidth >= 980;
            return Row(
              children: [
                _ToolbarGroup(
                  children: [
                    _CompactIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Oynatıcıyı kapat',
                      onPressed: onClose,
                    ),
                  ],
                ),
                if (showFilename) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: _ToolbarGroup(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Flexible(
                          child: Text(
                            filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (showEngine)
                          if (engineBadge case final badge?) ...[
                            const SizedBox(width: 9),
                            Flexible(
                              child: Text(
                                badge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                ] else
                  const Spacer(),
                _ToolbarGroup(
                  children: [
                    _CompactIconButton(
                      icon: Icons.crop_rounded,
                      tooltip: 'Smart Canvas',
                      selected: canvasActive,
                      onPressed: ready ? onToggleCanvas : null,
                    ),
                    _CompactIconButton(
                      icon: Icons.subtitles_rounded,
                      tooltip: 'Ekran üstü altyazı kontrolleri',
                      selected: subtitleControlsActive,
                      onPressed: ready ? onToggleSubtitleControls : null,
                    ),
                    if (pictureInPictureSupported)
                      _CompactIconButton(
                        icon: isPictureInPicture
                            ? Icons.picture_in_picture_alt_rounded
                            : Icons.picture_in_picture_rounded,
                        tooltip: isPictureInPicture
                            ? 'Mini oynatıcıdan çık'
                            : 'Mini oynatıcı',
                        selected: isPictureInPicture,
                        onPressed: ready ? onTogglePictureInPicture : null,
                      ),
                    _CompactIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: 'Tam ekran',
                      onPressed: ready ? onToggleFullscreen : null,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.ready,
    required this.playing,
    required this.position,
    required this.duration,
    required this.rate,
    required this.tracks,
    required this.selectedTrack,
    required this.previewImage,
    required this.previewPosition,
    required this.volume,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onFrameBackward,
    required this.onFrameForward,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onRateSelected,
    required this.onSubtitleSelected,
    required this.onAudioSelected,
    required this.onShowAdvancedSettings,
    this.onLoadExternalAudio,
    this.onLoadExternalSubtitle,
  });

  final bool ready;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double rate;
  final Tracks tracks;
  final Track selectedTrack;
  final Uint8List? previewImage;
  final Duration? previewPosition;
  final double volume;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onFrameBackward;
  final VoidCallback onFrameForward;
  final ValueChanged<Duration> onScrubStart;
  final ValueChanged<Duration> onScrubUpdate;
  final ValueChanged<Duration> onScrubEnd;
  final ValueChanged<double> onRateSelected;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<Offset> onShowAdvancedSettings;
  final VoidCallback? onLoadExternalAudio;
  final VoidCallback? onLoadExternalSubtitle;

  @override
  Widget build(BuildContext context) {
    final maximum = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds
        .toDouble()
        .clamp(0.0, maximum)
        .toDouble();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xD9000000)],
            stops: [0, 0.72],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          activeTrackColor: Colors.white70,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: _accent,
                          overlayColor: _accent.withValues(alpha: 0.14),
                          thumbShape: const _TimelineThumbShape(),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: maximum,
                          semanticFormatterCallback: (value) =>
                              '${formatPlayerDuration(Duration(milliseconds: value.round()))} / '
                              '${formatPlayerDuration(duration)}',
                          onChangeStart: ready && duration > Duration.zero
                              ? (v) => onScrubStart(
                                  Duration(milliseconds: v.round()),
                                )
                              : null,
                          onChanged: ready && duration > Duration.zero
                              ? (v) => onScrubUpdate(
                                  Duration(milliseconds: v.round()),
                                )
                              : null,
                          onChangeEnd: ready && duration > Duration.zero
                              ? (v) => onScrubEnd(
                                  Duration(milliseconds: v.round()),
                                )
                              : null,
                        ),
                      ),
                      if (previewPosition case final preview?)
                        _TimelinePreview(
                          image: previewImage,
                          position: preview,
                          duration: duration,
                          availableWidth: constraints.maxWidth,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final showAudio = constraints.maxWidth >= 430;
                    final showFrameControls = constraints.maxWidth >= 680;
                    return Row(
                      children: [
                        _CompactIconButton(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: playing ? 'Duraklat' : 'Oynat',
                          onPressed: ready ? onTogglePlay : null,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${formatPlayerDuration(position)} / '
                            '${formatPlayerDuration(duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        if (showAudio) ...[
                          _VolumeControl(
                            volume: volume,
                            onToggleMute: onToggleMute,
                            onChanged: onVolumeChanged,
                          ),
                          _TrackMenu<AudioTrack>(
                            tooltip: 'Ses izi',
                            icon: Icons.graphic_eq_rounded,
                            tracks: tracks.audio,
                            selectedId: selectedTrack.audio.id,
                            label: trackLabel,
                            onSelected: onAudioSelected,
                            onLoadExternal: onLoadExternalAudio,
                          ),
                        ],
                        _TrackMenu<SubtitleTrack>(
                          tooltip: 'Altyazı izi',
                          icon: Icons.subtitles_rounded,
                          tracks: tracks.subtitle,
                          selectedId: selectedTrack.subtitle.id,
                          label: trackLabel,
                          onSelected: onSubtitleSelected,
                          onLoadExternal: onLoadExternalSubtitle,
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Oynatma hızı',
                          color: const Color(0xF2242427),
                          onSelected: onRateSelected,
                          itemBuilder: (context) =>
                              const [
                                    0.5,
                                    0.75,
                                    1.0,
                                    1.25,
                                    1.5,
                                    2.0,
                                    4.0,
                                    8.0,
                                    16.0,
                                  ]
                                  .map(
                                    (value) => PopupMenuItem<double>(
                                      value: value,
                                      child: Text(
                                        '${formatPlayerRate(value)}×',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              '${formatPlayerRate(rate)}×',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (showFrameControls) ...[
                          _CompactIconButton(
                            icon: Icons.skip_previous_rounded,
                            tooltip: 'Önceki kare',
                            onPressed: ready ? onFrameBackward : null,
                          ),
                          _CompactIconButton(
                            icon: Icons.skip_next_rounded,
                            tooltip: 'Sonraki kare',
                            onPressed: ready ? onFrameForward : null,
                          ),
                        ],
                        // Gelişmiş ayarlar menüsünün tek giriş noktası;
                        // dar ekranlarda bile gizlenmez (mobil/TV erişimi).
                        Builder(
                          builder: (buttonContext) => _CompactIconButton(
                            icon: Icons.tune_rounded,
                            tooltip: 'Gelişmiş ayarlar',
                            onPressed: () {
                              final box = buttonContext.findRenderObject();
                              if (box is RenderBox && box.hasSize) {
                                onShowAdvancedSettings(
                                  box.localToGlobal(
                                    box.size.topRight(Offset.zero),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ses düzeyi kontrolü: sessize alma düğmesi + kompakt kaydırıcı.
class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.onToggleMute,
    required this.onChanged,
  });

  final double volume;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CompactIconButton(
          icon: muted
              ? Icons.volume_off_rounded
              : volume < 50
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          tooltip: muted ? 'Sesi aç' : 'Sesi kapat',
          onPressed: onToggleMute,
        ),
        SizedBox(
          width: 76,
          height: 32,
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: (volume / 100).clamp(0.0, 1.0),
              onChanged: (value) => onChanged(value * 100),
            ),
          ),
        ),
      ],
    );
  }
}

/// Çift tık seek'inin YouTube tarzı anlık geri bildirimi.
class _SeekFlash extends StatelessWidget {
  const _SeekFlash({required this.direction});

  final int direction;

  @override
  Widget build(BuildContext context) {
    final forward = direction >= 0;
    return Positioned(
      left: forward ? null : 42,
      right: forward ? 42 : null,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(
              forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelinePreview extends StatelessWidget {
  const _TimelinePreview({
    required this.image,
    required this.position,
    required this.duration,
    required this.availableWidth,
  });

  final Uint8List? image;
  final Duration position;
  final Duration duration;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final width = (availableWidth - 16).clamp(0.0, 224.0).toDouble();
    if (width < 96) return const SizedBox.shrink();
    final height = width * 154 / 224;
    final ratio = duration.inMicroseconds <= 0
        ? 0.0
        : position.inMicroseconds / duration.inMicroseconds;
    final left = (ratio * availableWidth - width / 2)
        .clamp(0.0, (availableWidth - width).clamp(0.0, double.infinity))
        .toDouble();
    return Positioned(
      left: left,
      bottom: 28,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(position.inSeconds),
        tween: Tween(begin: 0.97, end: 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF21A1A1D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: Colors.black,
                      child: image == null
                          ? const Center(
                              child: SizedBox.square(
                                dimension: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: Colors.white38,
                                ),
                              ),
                            )
                          : Image.memory(
                              image!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              cacheWidth: (width * 2).round(),
                              gaplessPlayback: true,
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      formatPlayerDuration(position),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 3),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB31C1C1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: padding,
        child: SizedBox(height: 32, child: Row(children: children)),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        toggled: selected,
        label: tooltip,
        excludeSemantics: true,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 34, height: 32),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: selected ? Colors.white : Colors.white70,
            backgroundColor: selected ? Colors.white12 : Colors.transparent,
            disabledForegroundColor: Colors.white24,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _TrackMenu<T> extends StatelessWidget {
  const _TrackMenu({
    required this.tooltip,
    required this.icon,
    required this.tracks,
    required this.selectedId,
    required this.label,
    required this.onSelected,
    this.onLoadExternal,
  });

  final String tooltip;
  final IconData icon;
  final List<T> tracks;
  final String selectedId;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  /// Verildiğinde listenin altına "Dosyadan yükle…" girişi eklenir. Menü
  /// generic değer taşıdığından bu giriş `onSelected`'ı tetiklemez; menü
  /// kapandıktan sonra bu callback çağrılır.
  final VoidCallback? onLoadExternal;

  @override
  Widget build(BuildContext context) {
    final loadExternal = onLoadExternal;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      color: const Color(0xF2242427),
      onSelected: onSelected,
      itemBuilder: (context) => [
        // Yükleme girişi listenin BAŞINDA durur: popup menüler seçili öğeyi
        // düğmeyle hizalar; sonda kalan bir öğe (özelikle alttaki kontrol
        // çubuğunda) ekran dışına taşabilir.
        if (loadExternal != null) ...[
          PopupMenuItem<T>(
            // null değer menüyü onSelected olmadan kapatır; dosya seçici
            // menü kapanışından sonra açılır.
            value: null,
            onTap: () => WidgetsBinding.instance.addPostFrameCallback(
              (_) => loadExternal(),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Icon(Icons.upload_file_rounded, size: 16),
                ),
                SizedBox(width: 6),
                Flexible(child: Text('Dosyadan yükle…')),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ],
        ...tracks.map(
          (track) => PopupMenuItem<T>(
            value: track,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _trackId(track) == selectedId
                      ? const Icon(Icons.check_rounded, size: 16)
                      : null,
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(label(track))),
              ],
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}

String _trackId(Object? track) => switch (track) {
  AudioTrack value => value.id,
  SubtitleTrack value => value.id,
  _ => '',
};

String trackLabel(Object track) {
  final (id, title, language, codec) = switch (track) {
    AudioTrack value => (value.id, value.title, value.language, value.codec),
    SubtitleTrack value => (value.id, value.title, value.language, value.codec),
    _ => ('', null, null, null),
  };
  if (id == 'auto') return 'Otomatik';
  if (id == 'no') return 'Kapalı';
  return [
    if (title?.trim().isNotEmpty ?? false) title!.trim(),
    if (language?.trim().isNotEmpty ?? false) language!.toUpperCase(),
    if (codec?.trim().isNotEmpty ?? false) codec!.toUpperCase(),
    if ((title?.trim().isEmpty ?? true) &&
        (language?.trim().isEmpty ?? true) &&
        (codec?.trim().isEmpty ?? true))
      '#$id',
  ].join(' · ');
}

String formatPlayerRate(double rate) => rate == rate.roundToDouble()
    ? rate.toStringAsFixed(0)
    : rate.toStringAsFixed(rate * 10 == (rate * 10).roundToDouble() ? 1 : 2);

String formatPlayerDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _TimelineThumbShape extends SliderComponentShape {
  const _TimelineThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(5, 18);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 5, height: 18),
      const Radius.circular(2),
    );
    context.canvas.drawRRect(rect, Paint()..color = _accent);
  }
}
