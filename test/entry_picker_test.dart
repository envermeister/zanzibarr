import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/entry_picker.dart';
import 'package:zanzibarr/src/rust/api/streaming.dart';

import 'l10n_test_helper.dart';

/// Çok parçalı NZB seçici diyaloğu testleri (issue #5).
///
/// Seçici, D-pad ile uçtan uca kullanılabilir olmalı: ilk öğe otomatik
/// odaklı, yukarı/aşağı gezer, DPAD_CENTER seçer, vazgeçme null döndürür
/// (oynatıcı bu durumda hiç başlamaz).
PlayableEntryDto _entry({
  required String key,
  required String name,
  String kind = 'direct',
  int megaBytes = 2048,
  int partCount = 1,
}) => PlayableEntryDto(
  key: key,
  name: name,
  kind: kind,
  encodedBytes: BigInt.from(megaBytes * 1024 * 1024),
  partCount: partCount,
);

/// Diyalogu Türkçe arayüzle açar; sonucu [onDone] ile bildirir.
Future<void> _openPicker(
  WidgetTester tester,
  List<PlayableEntryDto> entries,
  void Function(String?) onDone,
) async {
  await tester.pumpWithL10n(
    Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          onDone(await showPlayableEntryPicker(context, entries));
        });
        return const Scaffold(body: SizedBox());
      },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Çok parçalı NZB seçici diyaloğu', () {
    testWidgets('adayları boyut ve tür rozetleriyle listeler', (tester) async {
      await _openPicker(tester, [
        _entry(key: 'direct:show.e01.mkv', name: 'show.e01.mkv'),
        _entry(
          key: 'rar:show.e02',
          name: 'show.e02',
          kind: 'rar',
          megaBytes: 1024,
          partCount: 12,
        ),
      ], (_) {});

      expect(find.text('Ne oynatılsın?'), findsOneWidget);
      expect(find.text('show.e01.mkv'), findsOneWidget);
      expect(find.text('show.e02'), findsOneWidget);
      expect(find.textContaining('2.0 GB · Video'), findsOneWidget);
      expect(find.textContaining('1.0 GB · RAR · 12 parça'), findsOneWidget);
    });

    testWidgets('ilk öğe otomatik odaklı; select ilk anahtarı döndürür', (
      tester,
    ) async {
      String? result;
      await _openPicker(tester, [
        _entry(key: 'direct:show.e01.mkv', name: 'show.e01.mkv'),
        _entry(key: 'direct:show.e02.mkv', name: 'show.e02.mkv'),
      ], (value) => result = value);

      // Kumandayla hiçbir yere basmadan DPAD_CENTER ilk öğeyi seçmeli.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(result, 'direct:show.e01.mkv');
    });

    testWidgets('aşağı ok + select ikinci öğeyi seçer', (tester) async {
      String? result;
      await _openPicker(tester, [
        _entry(key: 'direct:show.e01.mkv', name: 'show.e01.mkv'),
        _entry(key: 'direct:show.e02.mkv', name: 'show.e02.mkv'),
        _entry(key: 'direct:show.e03.mkv', name: 'show.e03.mkv'),
      ], (value) => result = value);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(result, 'direct:show.e02.mkv');
    });

    testWidgets('vazgeçme null döndürür', (tester) async {
      var completed = false;
      String? result = 'henüz-açık';
      await _openPicker(tester, [
        _entry(key: 'direct:show.e01.mkv', name: 'show.e01.mkv'),
        _entry(key: 'direct:show.e02.mkv', name: 'show.e02.mkv'),
      ], (value) {
        result = value;
        completed = true;
      });

      // Bariere dokunmak (TV'de Geri tuşu karşılığı) diyaloğu seçimsiz
      // kapatır; oynatıcı bu yolda hiç başlatılmaz.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
    });
  });
}
