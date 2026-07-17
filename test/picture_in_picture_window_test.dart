import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usenews/player/picture_in_picture_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'desteklenen native masaüstünde PiP kanalına giriş ve çıkış gönderiliyor',
    () async {
      const channel = MethodChannel('com.usenews/test-window');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final window = NativePictureInPictureWindow(
        channel: channel,
        supported: true,
      );

      expect(window.isSupported, isTrue);
      expect(await window.enter(), isTrue);
      expect(await window.exit(), isTrue);
      expect(calls, ['enterPictureInPicture', 'exitPictureInPicture']);
    },
  );

  test(
    'desteklenmeyen platform kanal çağrısı yapmadan false döndürür',
    () async {
      const channel = MethodChannel('com.usenews/test-window-unsupported');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final window = NativePictureInPictureWindow(
        channel: channel,
        supported: false,
      );

      expect(window.isSupported, isFalse);
      expect(await window.enter(), isFalse);
      expect(await window.exit(), isFalse);
      expect(calls, 0);
    },
  );
}
