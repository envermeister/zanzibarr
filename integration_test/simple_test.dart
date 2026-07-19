import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/settings/ui_preferences.dart';
import 'package:zanzibarr/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Can call rust function', (WidgetTester tester) async {
    // Türkçe beklentiyi korumak için tercih doğrudan verilir; depo okunmaz.
    final uiPreferences = UiPreferencesController(UiPreferencesStore())
      ..locale = const Locale('tr');
    await tester.pumpWidget(ZanzibarrApp(uiPreferences: uiPreferences));
    expect(find.text('NZB seç ve oynat'), findsOneWidget);
  });
}
