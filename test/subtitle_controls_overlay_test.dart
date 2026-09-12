import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/player/subtitle_controls_overlay.dart';

import 'l10n_test_helper.dart';

Widget buildOverlay({
  String font = 'sans',
  ValueChanged<String>? onFontChanged,
}) {
  return Scaffold(
    body: SubtitleControlsOverlay(
      scale: 1.0,
      position: 100.0,
      delay: Duration.zero,
      color: '#FFFFFF',
      font: font,
      tracks: const [],
      selectedTrack: SubtitleTrack.no(),
      onScaleChanged: (_) {},
      onPositionChanged: (_) {},
      onDelayChanged: (_) {},
      onColorChanged: (_) {},
      onFontChanged: onFontChanged ?? (_) {},
      onTrackSelected: (_) {},
      onClose: () {},
    ),
  );
}

void main() {
  testWidgets('font menüsü katalogdaki fontları kendi aileleriyle listeler', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWithL10n(
      buildOverlay(onFontChanged: (id) => selected = id),
    );
    await tester.tap(find.byTooltip('Altyazı yazı tipi'));
    await tester.pumpAndSettle();

    expect(find.text('Noto Sans'), findsOneWidget);
    expect(find.text('Noto Serif'), findsOneWidget);
    expect(find.text('Noto Sans Mono'), findsOneWidget);

    await tester.tap(find.text('Noto Serif'));
    await tester.pumpAndSettle();
    expect(selected, 'serif');
  });

  testWidgets('seçili font tik ile işaretlenir', (tester) async {
    await tester.pumpWithL10n(buildOverlay(font: 'mono'));
    await tester.tap(find.byTooltip('Altyazı yazı tipi'));
    await tester.pumpAndSettle();

    final monoItem = find.ancestor(
      of: find.text('Noto Sans Mono'),
      matching: find.byType(PopupMenuItem<String>),
    );
    final sansItem = find.ancestor(
      of: find.text('Noto Sans'),
      matching: find.byType(PopupMenuItem<String>),
    );
    expect(
      find.descendant(of: monoItem, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sansItem, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
  });
}
