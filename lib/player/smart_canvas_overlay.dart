import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_canvas.dart';

/// Smart Canvas kırpmasını video yüzeyi üzerinde düzenleyen hafif katman.
///
/// Katman kontrollü kullanıma uygundur: her köşe hareketinde [onChanged]
/// çağrılır, çift tık o anki alanı [onCommit] ile uygular. Kaynak görüntü
/// `BoxFit.contain` ile yerleştirilmiş kabul edilir.
class SmartCanvasOverlay extends StatefulWidget {
  const SmartCanvasOverlay({
    super.key,
    required this.crop,
    required this.sourceAspectRatio,
    required this.onChanged,
    required this.onCommit,
    this.onCancel,
    this.visible = true,
    this.minimumCropExtent = defaultMinimumCanvasCropExtent,
    this.snapTolerance = defaultCanvasRatioSnapTolerance,
    this.fadeDuration = const Duration(milliseconds: 160),
  });

  static const surfaceKey = Key('smart_canvas_surface');
  static const topLeftHandleKey = Key('smart_canvas_handle_top_left');
  static const topRightHandleKey = Key('smart_canvas_handle_top_right');
  static const bottomLeftHandleKey = Key('smart_canvas_handle_bottom_left');
  static const bottomRightHandleKey = Key('smart_canvas_handle_bottom_right');
  static const ratioLabelKey = Key('smart_canvas_ratio_label');
  static const hintKey = Key('smart_canvas_hint');

  final CanvasCrop crop;
  final double sourceAspectRatio;
  final ValueChanged<CanvasCrop> onChanged;
  final ValueChanged<CanvasCrop> onCommit;
  final VoidCallback? onCancel;
  final bool visible;
  final double minimumCropExtent;
  final double snapTolerance;
  final Duration fadeDuration;

  @override
  State<SmartCanvasOverlay> createState() => _SmartCanvasOverlayState();
}

class _SmartCanvasOverlayState extends State<SmartCanvasOverlay> {
  static const _handleExtent = 36.0;

  final FocusNode _focusNode = FocusNode(debugLabel: 'Smart Canvas overlay');

  late CanvasCrop _crop;
  CanvasCrop? _dragStartCrop;
  Offset _dragStartPosition = Offset.zero;
  Size _dragCanvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _crop = clampCanvasCrop(
      widget.crop,
      minimumExtent: widget.minimumCropExtent,
    );
  }

  @override
  void didUpdateWidget(covariant SmartCanvasOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.crop != oldWidget.crop ||
        widget.minimumCropExtent != oldWidget.minimumCropExtent) {
      final next = clampCanvasCrop(
        widget.crop,
        minimumExtent: widget.minimumCropExtent,
      );
      if (next != _crop) _crop = next;
    }
    if (!widget.visible && oldWidget.visible) _focusNode.unfocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startDrag(Size canvasSize, Offset localPosition) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    _focusNode.requestFocus();
    _dragStartCrop = _crop;
    _dragStartPosition = localPosition;
    _dragCanvasSize = canvasSize;
  }

  void _updateDrag(CanvasCorner corner, DragUpdateDetails details) {
    final start = _dragStartCrop;
    if (start == null || _dragCanvasSize.isEmpty) return;
    final dragDelta = details.localPosition - _dragStartPosition;
    final next = dragCanvasCorner(
      crop: start,
      corner: corner,
      delta: Offset(
        dragDelta.dx / _dragCanvasSize.width,
        dragDelta.dy / _dragCanvasSize.height,
      ),
      sourceAspectRatio: widget.sourceAspectRatio,
      minimumExtent: widget.minimumCropExtent,
      snapTolerance: widget.snapTolerance,
    );
    if (next == _crop) return;
    setState(() => _crop = next);
    widget.onChanged(next);
  }

  void _endDrag() {
    _dragStartCrop = null;
    _dragStartPosition = Offset.zero;
    _dragCanvasSize = Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: widget.fadeDuration,
        curve: Curves.easeOutCubic,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape):
                widget.onCancel ?? () {},
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: widget.visible,
            canRequestFocus: widget.visible,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.biggest;
                final sourceRect = fittedCanvasRect(
                  viewport,
                  sourceAspectRatio: widget.sourceAspectRatio,
                );
                final cropRect = canvasCropRect(_crop, sourceRect);
                final ratioLabel = canvasCropRatioLabel(
                  _crop,
                  sourceAspectRatio: widget.sourceAspectRatio,
                );

                return Semantics(
                  container: true,
                  label: 'Smart Canvas kırpma alanı',
                  value: ratioLabel,
                  hint: 'Çift tıklayarak uygula. Escape ile iptal et.',
                  child: GestureDetector(
                    key: SmartCanvasOverlay.surfaceKey,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _focusNode.requestFocus(),
                    onDoubleTap: () => widget.onCommit(_crop),
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        CustomPaint(
                          painter: _CanvasMaskPainter(
                            sourceRect: sourceRect,
                            cropRect: cropRect,
                          ),
                        ),
                        _buildHandle(
                          corner: CanvasCorner.topLeft,
                          key: SmartCanvasOverlay.topLeftHandleKey,
                          label: 'Sol üst kırpma tutamacı',
                          left: cropRect.left,
                          top: cropRect.top,
                          canvasSize: sourceRect.size,
                        ),
                        _buildHandle(
                          corner: CanvasCorner.topRight,
                          key: SmartCanvasOverlay.topRightHandleKey,
                          label: 'Sağ üst kırpma tutamacı',
                          left: cropRect.right - _handleExtent,
                          top: cropRect.top,
                          canvasSize: sourceRect.size,
                        ),
                        _buildHandle(
                          corner: CanvasCorner.bottomLeft,
                          key: SmartCanvasOverlay.bottomLeftHandleKey,
                          label: 'Sol alt kırpma tutamacı',
                          left: cropRect.left,
                          top: cropRect.bottom - _handleExtent,
                          canvasSize: sourceRect.size,
                        ),
                        _buildHandle(
                          corner: CanvasCorner.bottomRight,
                          key: SmartCanvasOverlay.bottomRightHandleKey,
                          label: 'Sağ alt kırpma tutamacı',
                          left: cropRect.right - _handleExtent,
                          top: cropRect.bottom - _handleExtent,
                          canvasSize: sourceRect.size,
                        ),
                        Positioned(
                          left: cropRect.left,
                          top: cropRect.top + 9,
                          width: cropRect.width,
                          child: IgnorePointer(
                            child: Center(
                              child: UnconstrainedBox(
                                child: _OverlayPill(
                                  key: SmartCanvasOverlay.ratioLabelKey,
                                  text: ratioLabel,
                                  strong: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: sourceRect.left,
                          right: viewport.width - sourceRect.right,
                          bottom: viewport.height - sourceRect.bottom + 12,
                          child: const IgnorePointer(
                            child: Center(
                              child: _OverlayPill(
                                key: SmartCanvasOverlay.hintKey,
                                text: 'Çift tık: uygula · Esc: iptal',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle({
    required CanvasCorner corner,
    required Key key,
    required String label,
    required double left,
    required double top,
    required Size canvasSize,
  }) {
    final cursor = switch (corner) {
      CanvasCorner.topLeft ||
      CanvasCorner.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      CanvasCorner.topRight ||
      CanvasCorner.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    };
    return Positioned(
      left: left,
      top: top,
      width: _handleExtent,
      height: _handleExtent,
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) =>
                _startDrag(canvasSize, details.localPosition),
            onPanUpdate: (details) => _updateDrag(corner, details),
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            child: CustomPaint(painter: _CanvasHandlePainter(corner)),
          ),
        ),
      ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({super.key, required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB8141518),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: strong ? 8 : 10,
          vertical: strong ? 4 : 5,
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: const Color(0xF2FFFFFF),
            fontSize: strong ? 12 : 11,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: 0.1,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _CanvasMaskPainter extends CustomPainter {
  const _CanvasMaskPainter({required this.sourceRect, required this.cropRect});

  final Rect sourceRect;
  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xA6000000);
    canvas.drawRect(
      Rect.fromLTRB(
        sourceRect.left,
        sourceRect.top,
        sourceRect.right,
        cropRect.top,
      ),
      mask,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        sourceRect.left,
        cropRect.bottom,
        sourceRect.right,
        sourceRect.bottom,
      ),
      mask,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        sourceRect.left,
        cropRect.top,
        cropRect.left,
        cropRect.bottom,
      ),
      mask,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        cropRect.right,
        cropRect.top,
        sourceRect.right,
        cropRect.bottom,
      ),
      mask,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xE6FFFFFF);
    _drawDashedLine(canvas, cropRect.topLeft, cropRect.topRight, border);
    _drawDashedLine(canvas, cropRect.topRight, cropRect.bottomRight, border);
    _drawDashedLine(canvas, cropRect.bottomRight, cropRect.bottomLeft, border);
    _drawDashedLine(canvas, cropRect.bottomLeft, cropRect.topLeft, border);
  }

  @override
  bool shouldRepaint(covariant _CanvasMaskPainter oldDelegate) =>
      oldDelegate.sourceRect != sourceRect || oldDelegate.cropRect != cropRect;
}

class _CanvasHandlePainter extends CustomPainter {
  const _CanvasHandlePainter(this.corner);

  final CanvasCorner corner;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 4.0;
    const length = 17.0;
    final origin = switch (corner) {
      CanvasCorner.topLeft => const Offset(inset, inset),
      CanvasCorner.topRight => Offset(size.width - inset, inset),
      CanvasCorner.bottomLeft => Offset(inset, size.height - inset),
      CanvasCorner.bottomRight => Offset(
        size.width - inset,
        size.height - inset,
      ),
    };
    final horizontalDirection = switch (corner) {
      CanvasCorner.topLeft || CanvasCorner.bottomLeft => 1.0,
      CanvasCorner.topRight || CanvasCorner.bottomRight => -1.0,
    };
    final verticalDirection = switch (corner) {
      CanvasCorner.topLeft || CanvasCorner.topRight => 1.0,
      CanvasCorner.bottomLeft || CanvasCorner.bottomRight => -1.0,
    };

    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x66000000);
    final foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    final horizontalEnd = origin.translate(horizontalDirection * length, 0);
    final verticalEnd = origin.translate(0, verticalDirection * length);
    canvas.drawLine(origin, horizontalEnd, shadow);
    canvas.drawLine(origin, verticalEnd, shadow);
    canvas.drawLine(origin, horizontalEnd, foreground);
    canvas.drawLine(origin, verticalEnd, foreground);
  }

  @override
  bool shouldRepaint(covariant _CanvasHandlePainter oldDelegate) =>
      oldDelegate.corner != corner;
}

void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
  const dash = 6.0;
  const gap = 4.0;
  final vector = end - start;
  final length = vector.distance;
  if (length == 0) return;
  final direction = vector / length;
  var travelled = 0.0;
  while (travelled < length) {
    final dashEnd = _minDouble(travelled + dash, length);
    canvas.drawLine(
      start + direction * travelled,
      start + direction * dashEnd,
      paint,
    );
    travelled += dash + gap;
  }
}

double _minDouble(double a, double b) => a < b ? a : b;
