import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../player/media_preferences.dart';

/// GitHub Releases üzerinden yayımlanan bir sürümün bilgisi.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  /// "v1.4" biçimindeki tag.
  final String tag;

  /// Karşılaştırılabilir sürüm metni ("1.4.0").
  final String version;

  /// Markdown sürüm notları (GitHub body).
  final String notes;

  /// Release sayfasının tarayıcı adresi.
  final String pageUrl;

  /// Asset adı → indirme adresi.
  final Map<String, String> assets;

  static ReleaseInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    final tag = value['tag_name'];
    final pageUrl = value['html_url'];
    final body = value['body'];
    final assets = value['assets'];
    if (tag is! String || pageUrl is! String) return null;
    final map = <String, String>{};
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map) {
          final name = asset['name'];
          final url = asset['browser_download_url'];
          if (name is String && url is String) map[name] = url;
        }
      }
    }
    return ReleaseInfo(
      tag: tag,
      version: normalizeVersion(tag),
      notes: body is String ? body : '',
      pageUrl: pageUrl,
      assets: map,
    );
  }

  /// "v1.4.0" / "1.4.0+5" gibi metni "1.4.0" biçimine indirger.
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    return v;
  }

  /// `a` daha yeni ise pozitif döner; semver parçaları sayısal karşılaştırılır.
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pb = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// Güncelleme kontrolü ve indirme/kurulum akışı.
///
/// Android'de APK indirilip sistem paket yükleyicisiyle kurulur; diğer
/// platformlarda release sayfası tarayıcıda açılır (iOS sideload zorunlu).
class UpdateService {
  UpdateService({http.Client? client, PlayerPreferenceStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? FlutterSecurePlayerPreferenceStorage();

  final http.Client _client;
  final PlayerPreferenceStorage _storage;

  static const releasesApiUrl =
      'https://api.github.com/repos/envermeister/zanzibarr/releases/latest';
  static const _skippedVersionKey = 'zanzibarr.update.skipped_version';
  static const _installChannel = MethodChannel('zanzibarr/updater');

  /// Uygulamanın çalışan sürümü (pubspec version).
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return ReleaseInfo.normalizeVersion(info.version);
  }

  /// Yeni sürüm varsa ve kullanıcı onu atlamadıysa bilgisini döndürür.
  Future<ReleaseInfo?> checkForUpdate() async {
    final current = await currentVersion();
    final response = await _client
        .get(Uri.parse(releasesApiUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final latest = ReleaseInfo.fromJson(jsonDecode(response.body));
    if (latest == null) return null;
    if (ReleaseInfo.compareVersions(latest.version, current) <= 0) {
      return null;
    }
    final skipped = await _storage.read(_skippedVersionKey);
    if (skipped == latest.version) return null;
    return latest;
  }

  Future<void> skipVersion(String version) =>
      _storage.write(_skippedVersionKey, version);

  /// Bu platform için indirilecek asset'i seçer; yoksa null.
  String? assetUrlForCurrentPlatform(ReleaseInfo release) {
    const byPlatform = {
      'android-arm64': 'zanzibarr-android-arm64-v8a.apk',
      'windows': 'zanzibarr-windows-x64.zip',
      'macos': 'zanzibarr-macos-arm64.zip',
      'linux': 'zanzibarr-linux-x64.tar.gz',
      'ios': 'zanzibarr-ios-unsigned.ipa',
    };
    final key = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android-arm64',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.iOS => 'ios',
      _ => '',
    };
    final name = byPlatform[key];
    return name == null ? null : release.assets[name];
  }

  bool get canAutoInstall => defaultTargetPlatform == TargetPlatform.android;

  /// Güncellemeyi indirir ve (Android) kurulum ekranını açar. Masaüstü ve
  /// iOS'ta release sayfasını tarayıcıda açar.
  ///
  /// [onProgress] 0..1 arası indirme ilerlemesiyle çağrılır.
  Future<void> install(
    ReleaseInfo release, {
    ValueChanged<double>? onProgress,
  }) async {
    final url = assetUrlForCurrentPlatform(release) ?? release.pageUrl;
    if (!canAutoInstall || !url.endsWith('.apk')) {
      await launchUrl(Uri.parse(release.pageUrl));
      return;
    }
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 10));
    if (response.statusCode != 200) {
      throw StateError('İndirme başarısız: HTTP ${response.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/zanzibarr-update.apk');
    final sink = file.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;
    try {
      await response.stream
          .map((chunk) {
            received += chunk.length;
            if (total > 0) onProgress?.call(received / total);
            return chunk;
          })
          .pipe(sink);
    } finally {
      await sink.close();
    }
    await _installChannel.invokeMethod<void>('installApk', {'path': file.path});
  }
}
