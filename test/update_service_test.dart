import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zanzibarr/player/media_preferences.dart';
import 'package:zanzibarr/update/update_service.dart';

class _MemoryPreferenceStorage implements PlayerPreferenceStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

http.Client _clientWith(Object body, {int status = 200}) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

Map<String, Object> _releaseJson({
  String tag = 'v1.5.0',
  String body = 'notlar',
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/envermeister/zanzibarr/releases/tag/$tag',
  'body': body,
  'assets': [
    {
      'name': 'zanzibarr-android-arm64-v8a.apk',
      'browser_download_url':
          'https://example.com/zanzibarr-android-arm64-v8a.apk',
    },
    {
      'name': 'zanzibarr-windows-x64.zip',
      'browser_download_url': 'https://example.com/zanzibarr-windows-x64.zip',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PackageInfo platform kanalını sabit sürümle taklit eder.
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(packageInfoChannel, (call) async {
        return <String, String>{
          'appName': 'zanzibarr',
          'packageName': 'com.zanzibarr.zanzibarr',
          'version': '1.4.0',
          'buildNumber': '5',
        };
      });
  group('ReleaseInfo sürüm karşılaştırması', () {
    test('semver parçaları sayısal karşılaştırılır', () {
      expect(ReleaseInfo.compareVersions('1.5.0', '1.4.0'), greaterThan(0));
      expect(ReleaseInfo.compareVersions('1.4.0', '1.5.0'), lessThan(0));
      expect(ReleaseInfo.compareVersions('1.4.0', '1.4.0'), 0);
      expect(ReleaseInfo.compareVersions('1.4.10', '1.4.9'), greaterThan(0));
      expect(ReleaseInfo.compareVersions('2.0', '1.9.9'), greaterThan(0));
    });

    test('normalizeVersion v öneki ve +build sonekini siler', () {
      expect(ReleaseInfo.normalizeVersion('v1.4.0'), '1.4.0');
      expect(ReleaseInfo.normalizeVersion('1.4.0+5'), '1.4.0');
      expect(ReleaseInfo.normalizeVersion('V2.0'), '2.0');
    });
  });

  group('UpdateService.checkForUpdate', () {
    test('daha yeni sürüm varsa ReleaseInfo döner', () async {
      final service = UpdateService(
        client: _clientWith(_releaseJson(tag: 'v9.9.9')),
        storage: _MemoryPreferenceStorage(),
      );
      // package_info_plus test ortamında 0.0.1 gibi bir değer döner; tag açıkça
      // daha yeni tutulur.
      final result = await service.checkForUpdate();
      expect(result, isNotNull);
      expect(result!.version, '9.9.9');
      expect(result.assets['zanzibarr-windows-x64.zip'], contains('https://'));
    });

    test('güncel sürümde null döner', () async {
      final service = UpdateService(
        client: _clientWith(_releaseJson(tag: 'v0.0.0')),
        storage: _MemoryPreferenceStorage(),
      );
      expect(await service.checkForUpdate(), isNull);
    });

    test('atlanmış sürüm tekrar gösterilmez', () async {
      final storage = _MemoryPreferenceStorage()
        ..values['zanzibarr.update.skipped_version'] = '9.9.9';
      final service = UpdateService(
        client: _clientWith(_releaseJson(tag: 'v9.9.9')),
        storage: storage,
      );
      expect(await service.checkForUpdate(), isNull);
    });

    test('HTTP hatası sessizce null döner', () async {
      final service = UpdateService(
        client: _clientWith({'error': 'boom'}, status: 500),
        storage: _MemoryPreferenceStorage(),
      );
      expect(await service.checkForUpdate(), isNull);
    });

    test('bozuk JSON sessizce null döner', () async {
      final service = UpdateService(
        client: _clientWith({'unexpected': true}),
        storage: _MemoryPreferenceStorage(),
      );
      expect(await service.checkForUpdate(), isNull);
    });
  });
}
