import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/src/rust/api/simple.dart';
import 'package:zanzibarr/src/rust/frb_generated.dart';

/// Faz 0 köprü kanıtı: Rust dylib'i host'ta derlenmiş olmalı
/// (`cargo build --manifest-path rust/Cargo.toml`).
String _dylibPath() {
  final name = switch (Platform.operatingSystem) {
    'macos' => 'librust_lib_zanzibarr.dylib',
    'linux' => 'librust_lib_zanzibarr.so',
    'windows' => 'rust_lib_zanzibarr.dll',
    _ => throw UnsupportedError('Desteklenmeyen test platformu'),
  };
  return 'rust/target/debug/$name';
}

void main() {
  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_dylibPath()));
  });

  test('Dart, Rust fonksiyonunu çağırabiliyor (köprü ayakta)', () {
    expect(
      greet(name: 'Zanzibarr'),
      'Merhaba Zanzibarr, Rust çekirdeği ayakta! 🦀',
    );
    expect(engineInfo(), startsWith('rust_lib_zanzibarr v'));
  });

  testWidgets('Ana ekran medya açma akışını sunuyor', (tester) async {
    await tester.pumpWidget(const ZanzibarrApp());
    expect(find.text('NZB seç ve oynat'), findsOneWidget);
  });
}
