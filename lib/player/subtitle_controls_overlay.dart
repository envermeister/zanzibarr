import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/app_localizations.dart';

class SubtitleControlsOverlay extends StatefulWidget {
  const SubtitleControlsOverlay({
    super.key,
    required this.scale,
    required this.position,
    required this.delay,
    required this.tracks,
    required this.selectedTrack,
    required this.onScaleChanged,
    required this.onPositionChanged,
    required this.onDelayChanged,
    required this.onTrackSelected,
    required this.onClose,
  });

  final double scale;
  final double position;
  final Duration delay;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack selectedTrack;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onPositionChanged;
  final ValueChanged<Duration> onDelayChanged;
  final ValueChanged<SubtitleTrack> onTrackSelected;
  final VoidCallback onClose;

  @override
  State<SubtitleControlsOverlay> createState() =>
      _SubtitleControlsOverlayState();
}

class _SubtitleControlsOverlayState extends State<SubtitleControlsOverlay> {
  late double _scale = widget.scale;
  late double _position = widget.position;
  late Duration _delay = widget.delay;
  bool _draggingPosition = false;
  bool _draggingDelay = false;

  @override
  void didUpdateWidget(covariant SubtitleControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scale != oldWidget.scale) _scale = widget.scale;
    if (!_draggingPosition && widget.position != oldWidget.position) {
      _position = widget.position;
    }
    if (!_draggingDelay && widget.delay != oldWidget.delay) {
      _delay = widget.delay;
    }
  }

  void _changeScale(double value) {
    final next = value.clamp(0.5, 3.0).toDouble();
    setState(() => _scale = next);
    widget.onScaleChanged(next);
  }

  void _changePosition(double value) {
    final next = value.clamp(0.0, 100.0).toDouble();
    setState(() => _position = next);
    widget.onPositionChanged(next);
  }

  void _changeDelay(Duration value) {
    const maximum = Duration(seconds: 60);
    final micros = value.inMicroseconds
        .clamp(-maximum.inMicroseconds, maximum.inMicroseconds)
        .toInt();
    final next = Duration(microseconds: micros);
    setState(() => _delay = next);
    widget.onDelayChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vertical = ((_position.clamp(0, 100).toDouble() / 100) * 1.4 - 0.45)
        .clamp(-0.45, 0.95);
    return SafeArea(
      child: AnimatedAlign(
        alignment: Alignment(0, vertical.toDouble()),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GestureDetector(
              onVerticalDragStart: (_) => _draggingPosition = true,
              onVerticalDragUpdate: (details) {
                final height = MediaQuery.sizeOf(context).height;
                if (height <= 0) return;
                _changePosition(_position + details.delta.dy / height * 100);
              },
              onVerticalDragEnd: (_) {
                _draggingPosition = false;
                widget.onPositionChanged(_position);
              },
              onVerticalDragCancel: () => _draggingPosition = false,
              onHorizontalDragStart: (_) => _draggingDelay = true,
              onHorizontalDragUpdate: (details) {
                final nextMicros =
                    _delay.inMicroseconds + (details.delta.dx * 18000).round();
                _changeDelay(Duration(microseconds: nextMicros));
              },
              onHorizontalDragEnd: (_) {
                _draggingDelay = false;
                widget.onDelayChanged(_delay);
              },
              onHorizontalDragCancel: () => _draggingDelay = false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE61C1C1F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<SubtitleTrack>(
                        tooltip: l10n.subtitleTrack,
                        color: const Color(0xF2242427),
                        onSelected: widget.onTrackSelected,
                        itemBuilder: (context) => widget.tracks
                            .map(
                              (track) => PopupMenuItem<SubtitleTrack>(
                                value: track,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      child: track.id == widget.selectedTrack.id
                                          ? const Icon(Icons.check, size: 16)
                                          : null,
                                    ),
                                    Text(
                                      _subtitleLabel(
                                        track,
                                        auto: l10n.auto,
                                        off: l10n.off,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(
                            Icons.closed_caption_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                      _OverlayButton(
                        icon: Icons.text_decrease_rounded,
                        tooltip: l10n.subtitleDecreaseTooltip,
                        onPressed: () => _changeScale(_scale - 0.1),
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${(_scale * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      _OverlayButton(
                        icon: Icons.text_increase_rounded,
                        tooltip: l10n.subtitleIncreaseTooltip,
                        onPressed: () => _changeScale(_scale + 0.1),
                      ),
                      const _Divider(),
                      _OverlayButton(
                        icon: Icons.keyboard_arrow_up_rounded,
                        tooltip: l10n.subtitleMoveUpTooltip,
                        onPressed: () => _changePosition(_position - 2),
                      ),
                      _OverlayButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        tooltip: l10n.subtitleMoveDownTooltip,
                        onPressed: () => _changePosition(_position + 2),
                      ),
                      const _Divider(),
                      _OverlayButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: l10n.subtitleEarlierTooltip,
                        onPressed: () => _changeDelay(
                          _delay - const Duration(milliseconds: 100),
                        ),
                      ),
                      SizedBox(
                        width: 62,
                        child: Text(
                          _formatDelay(_delay, l10n.secondsUnitShort),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      _OverlayButton(
                        icon: Icons.chevron_right_rounded,
                        tooltip: l10n.subtitleLaterTooltip,
                        onPressed: () => _changeDelay(
                          _delay + const Duration(milliseconds: 100),
                        ),
                      ),
                      const _Divider(),
                      _OverlayButton(
                        icon: Icons.close_rounded,
                        tooltip: l10n.closeSubtitleControlsTooltip,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 30),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: Icon(icon, color: Colors.white70, size: 17),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: Colors.white12,
  );
}

String _subtitleLabel(
  SubtitleTrack track, {
  required String auto,
  required String off,
}) {
  if (track.id == 'auto') return auto;
  if (track.id == 'no') return off;
  return [
    if (track.title?.isNotEmpty ?? false) track.title!,
    if (track.language?.isNotEmpty ?? false) track.language!.toUpperCase(),
    if (track.codec?.isNotEmpty ?? false) track.codec!.toUpperCase(),
  ].join(' · ');
}

String _formatDelay(Duration value, String unit) {
  final seconds = value.inMicroseconds / Duration.microsecondsPerSecond;
  final prefix = seconds > 0 ? '+' : '';
  return '$prefix${seconds.toStringAsFixed(2)} $unit';
}
