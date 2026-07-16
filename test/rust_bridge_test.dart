import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usenews/main.dart';
import 'package:usenews/src/rust/api/simple.dart';
import 'package:usenews/src/rust/frb_generated.dart';

/// Faz 0 köprü kanıtı: Rust dylib'i host'ta derlenmiş olmalı
/// (`cargo build --manifest-path rust/Cargo.toml`).
String _dylibPath() {
  final name = switch (Platform.operatingSystem) {
    'macos' => 'librust_lib_usenews.dylib',
    'linux' => 'librust_lib_usenews.so',
    'windows' => 'rust_lib_usenews.dll',
    _ => throw UnsupportedError('Desteklenmeyen test platformu'),
  };
  return 'rust/target/debug/$name';
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_dylibPath()),
    );
  });

  test('Dart, Rust fonksiyonunu çağırabiliyor (köprü ayakta)', () {
    expect(greet(name: 'UseNews'), 'Merhaba UseNews, Rust çekirdeği ayakta! 🦀');
    expect(engineInfo(), startsWith('rust_lib_usenews v'));
  });

  testWidgets('Rust sonucu ekranda görünüyor', (tester) async {
    await tester.pumpWidget(const UseNewsApp());
    expect(
      find.textContaining('Rust çekirdeği ayakta'),
      findsOneWidget,
    );
    expect(find.textContaining('Motor: rust_lib_usenews'), findsOneWidget);
  });
}
