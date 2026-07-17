import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usenews/player/smart_canvas.dart';
import 'package:usenews/player/smart_canvas_overlay.dart';

void main() {
  group('Smart Canvas geometry', () {
    test('crop sınırlar içinde kalır ve minimum boyuta büyütülür', () {
      const crop = CanvasCrop(left: -0.2, top: 0.95, right: 0.03, bottom: 1.4);

      final result = clampCanvasCrop(crop, minimumExtent: 0.1);

      expect(result.left, 0);
      expect(result.right, closeTo(0.1, 0.000001));
      expect(result.top, closeTo(0.9, 0.000001));
      expect(result.bottom, 1);
    });

    test('kaynak aspect normalize crop oranına katılır', () {
      const normalizedSquare = CanvasCrop(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );

      expect(
        canvasCropAspectRatio(normalizedSquare, sourceAspectRatio: 16 / 9),
        closeTo(16 / 9, 0.000001),
      );
      expect(
        nearestCommonCanvasAspectRatio(
          normalizedSquare,
          sourceAspectRatio: 16 / 9,
        )?.label,
        '16:9',
      );
    });

    test('yakın oran köşe sabitlenerek common ratio değerine snap olur', () {
      const crop = CanvasCrop(left: 0.1, top: 0.1, right: 0.8, bottom: 0.88);

      final result = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.bottomRight,
        delta: Offset.zero,
        sourceAspectRatio: 2,
      );

      expect(result.left, crop.left);
      expect(result.top, crop.top);
      expect(
        canvasCropAspectRatio(result, sourceAspectRatio: 2),
        closeTo(16 / 9, 0.000001),
      );
      expect(canvasCropRatioLabel(result, sourceAspectRatio: 2), '16:9');
    });

    test('köşe sürükleme minimum crop alanını geçemez', () {
      const crop = CanvasCrop(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);

      final result = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.topLeft,
        delta: const Offset(0.9, 0.9),
        sourceAspectRatio: 1,
        minimumExtent: 0.1,
        snapTolerance: 0,
      );

      expect(result.left, closeTo(0.7, 0.000001));
      expect(result.top, closeTo(0.7, 0.000001));
      expect(result.right, 0.8);
      expect(result.bottom, 0.8);
      expect(result.width, closeTo(0.1, 0.000001));
      expect(result.height, closeTo(0.1, 0.000001));
    });

    test('dört köşenin her biri karşı köşeyi sabit tutar', () {
      const crop = CanvasCrop(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
      const delta = Offset(0.05, 0.04);

      final topLeft = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.topLeft,
        delta: delta,
        sourceAspectRatio: 1.7,
        snapTolerance: 0,
      );
      final topRight = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.topRight,
        delta: delta,
        sourceAspectRatio: 1.7,
        snapTolerance: 0,
      );
      final bottomLeft = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.bottomLeft,
        delta: delta,
        sourceAspectRatio: 1.7,
        snapTolerance: 0,
      );
      final bottomRight = dragCanvasCorner(
        crop: crop,
        corner: CanvasCorner.bottomRight,
        delta: delta,
        sourceAspectRatio: 1.7,
        snapTolerance: 0,
      );

      expect(topLeft.bottomRight, crop.rect.bottomRight);
      expect(topRight.bottomLeft, crop.rect.bottomLeft);
      expect(bottomLeft.topRight, crop.rect.topRight);
      expect(bottomRight.topLeft, crop.rect.topLeft);
    });

    test('contain yerleşimi kaynak aspect oranını korur', () {
      final result = fittedCanvasRect(
        const Size(400, 400),
        sourceAspectRatio: 16 / 9,
      );

      expect(result.width, 400);
      expect(result.height, closeTo(225, 0.000001));
      expect(result.center, const Offset(200, 200));
    });
  });

  group('SmartCanvasOverlay', () {
    testWidgets('köşe sürüklerken onChanged gerçek zamanlı çağrılır', (
      tester,
    ) async {
      final changes = <CanvasCrop>[];
      await tester.pumpWidget(
        _testApp(
          SmartCanvasOverlay(
            crop: const CanvasCrop(
              left: 0.2,
              top: 0.2,
              right: 0.8,
              bottom: 0.8,
            ),
            sourceAspectRatio: 4 / 3,
            onChanged: changes.add,
            onCommit: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(SmartCanvasOverlay.bottomRightHandleKey),
        const Offset(40, 30),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(changes, isNotEmpty);
      expect(changes.last.right, closeTo(0.9, 0.01));
      expect(changes.last.bottom, closeTo(0.9, 0.01));
    });

    testWidgets('çift tık güncel crop alanını commit eder', (tester) async {
      const crop = CanvasCrop(left: 0.15, top: 0.2, right: 0.85, bottom: 0.8);
      CanvasCrop? committed;
      await tester.pumpWidget(
        _testApp(
          SmartCanvasOverlay(
            crop: crop,
            sourceAspectRatio: 16 / 9,
            onChanged: (_) {},
            onCommit: (value) => committed = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = find.byKey(SmartCanvasOverlay.surfaceKey);
      await tester.tap(surface);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(surface);
      await tester.pump(const Duration(milliseconds: 400));

      expect(committed, crop);
    });

    testWidgets('Escape iptal callback çağrısını gönderir', (tester) async {
      var cancellations = 0;
      await tester.pumpWidget(
        _testApp(
          SmartCanvasOverlay(
            crop: const CanvasCrop.full(),
            sourceAspectRatio: 16 / 9,
            onChanged: (_) {},
            onCommit: (_) {},
            onCancel: () => cancellations++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cancellations, 1);
      expect(find.text('Çift tık: uygula · Esc: iptal'), findsOneWidget);
    });
  });
}

Widget _testApp(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: SizedBox(width: 400, height: 300, child: child)),
  ),
);

extension on CanvasCrop {
  Offset get topLeft => Offset(left, top);
  Offset get topRight => Offset(right, top);
  Offset get bottomLeft => Offset(left, bottom);
  Offset get bottomRight => Offset(right, bottom);
}
