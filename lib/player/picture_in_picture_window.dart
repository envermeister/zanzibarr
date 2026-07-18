import 'dart:io';

import 'package:flutter/services.dart';

/// Oynatıcı penceresini kompakt, diğer pencerelerin üstünde kalan moda alır.
///
/// Yerel pencere uygulaması macOS ve Windows'tadır. Desteklenmeyen
/// platformlarda çağrılar güvenli biçimde `false` döndürür.
abstract interface class PictureInPictureWindow {
  bool get isSupported;

  Future<bool> enter();

  Future<bool> exit();
}

class NativePictureInPictureWindow implements PictureInPictureWindow {
  NativePictureInPictureWindow({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('com.zanzibarr/window'),
      _supported = supported ?? (Platform.isMacOS || Platform.isWindows);

  final MethodChannel _channel;
  final bool _supported;

  @override
  bool get isSupported => _supported;

  @override
  Future<bool> enter() => _invoke('enterPictureInPicture');

  @override
  Future<bool> exit() => _invoke('exitPictureInPicture');

  Future<bool> _invoke(String method) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
