import 'dart:io';

// Tanı amaçlı ilerleme çıktıları test loguna yazılır.
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zanzibarr/main.dart';
import 'package:zanzibarr/player/advanced_playback_controller.dart';
import 'package:zanzibarr/player/player_screen.dart';
import 'package:zanzibarr/settings/ui_preferences.dart';
import 'package:zanzibarr/src/rust/frb_generated.dart';

/// Gerçek NZB + gerçek Keychain kimliğiyle uçtan uca oynatma doğrulaması.
///
/// Bu test yalnız geliştirici makinesinde anlamlıdır: Easynews kimliği
/// Keychain'de kayıtlı olmalı ve NZB dosyaları diskte bulunmalı. CI'da
/// koşmaz (`flutter test` integration_test/ dizinini taramaz).
///
/// Doğrulananlar:
/// - Dolby Vision Profile 5 (HDR10 baz katmansız) içerikte libplacebo
///   reshape filtresi otomatik devreye girer ve renkler doğru çıkar
///   (ekran görüntüsü elle/gözle denetlenir).
/// - HDR modu değişiminde filtre hedefi çalışma zamanında güncellenir.
/// - DV Profile 8 (HDR10 baz katmanlı) ve DV'siz HDR10 içerikte filtre
///   DEVREYE GİRMEZ; mevcut render yolu aynen korunur.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // RustLib.init() üretilen kodda executeRustInitializers üzerinden
    // init_app'i (MoltenVK ICD tanıtımı dahil) kendisi çağırır.
    await RustLib.init();
    MediaKit.ensureInitialized();
  });

  testWidgets('DV Profile 5 içerik reshape filtresiyle oynatılır', (
    tester,
  ) async {
    await _verifyPlayback(
      tester,
      nzbFileName:
          'Heartstopper.Forever.2026.DV.2160p.WEB.h265-ETHEL.nzb',
      expectDolbyVisionReshaping: true,
    );
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('DV olmayan HDR10 içerikte reshape filtresi kapalı kalır', (
    tester,
  ) async {
    await _verifyPlayback(
      tester,
      nzbFileName:
          'A.Very.Harold.And.Kumar.Christmas.2011.UNRATED.1080p.BluRay.'
          'HEVC.x265.5.1-BONE.nzb',
      expectDolbyVisionReshaping: false,
    );
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('DV Profile 8 içerikte reshape filtresi kapalı kalır', (
    tester,
  ) async {
    await _verifyPlayback(
      tester,
      nzbFileName:
          'Coming.to.America.1988.2160p.UHD.BluRay.Remux.HDR.DV.HEVC.'
          'DTS-HD.MA.5.1-PmP.nzb',
      expectDolbyVisionReshaping: false,
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// Sandbox'lı uygulama yalnız kendi konteynerini okuyabilir; test NZB'leri
/// koşudan önce kabuk tarafından konteynerin `Data/nzb-test` dizinine
/// kopyalanır (sandbox'ta HOME konteynerin Data dizinine yönlendirilir).
String _testMediaPath(String fileName) =>
    '${Platform.environment['HOME']}/nzb-test/$fileName';

Future<void> _verifyPlayback(
  WidgetTester tester, {
  required String nzbFileName,
  required bool expectDolbyVisionReshaping,
}) async {
  final nzbPath = _testMediaPath(nzbFileName);
  expect(
    File(nzbPath).existsSync(),
    isTrue,
    reason:
        'test NZB konteynerde yok: önce NZB dosyasını '
        '~/Library/Containers/com.zanzibarr.zanzibarr/Data/nzb-test altına '
        'kopyalayın',
  );

  final uiPreferences = UiPreferencesController(UiPreferencesStore())
    ..locale = const Locale('tr');
  // Not: rota itme (Navigator.push) yerine PlayerScreen doğrudan home olarak
  // verilir. Entegrasyon ortamında pencere ön plana alınamadığında rota
  // geçiş animasyonu ortasında kare akışı durabiliyor; gelen sayfa o zaman
  // overlay'de offstage takılı kalıyor ve finder onu göremiyordu.
  await tester.pumpWidget(
    ZanzibarrApp(
      uiPreferences: uiPreferences,
      home: PlayerScreen(nzbPath: nzbPath),
    ),
  );
  await tester.pump();

  // libmpv günlüklerini yakala: lavfi graf hataları ve Vulkan tanıları
  // yalnız burada görünür (mpv `set vf` graf hatasında bile başarı döner).
  (tester.state(find.byType(PlayerScreen)) as dynamic)
      .playerForTest
      .stream
      .log
      .listen((log) => print('mpv[${log.prefix}] ${log.text}'));

  // Oynatma hazır olana ya da açılış hatası görülene kadar bekle. İlk
  // segmentlerin Usenet'ten çekilmesi ağ koşuluna göre ~1-3 dakika sürer.
  // Not: canlı videoyla pump() döngüsü kare üretimine takılabildiğinden
  // beklemeler gerçek zamanlı gecikmeyle yapılır; durum sorguları pump
  // gerektirmez.
  Object? startupError;
  var ready = false;
  var sawPlayerScreen = false;
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  var tick = 0;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 1));
    tick++;
    final states = tester.stateList(find.byType(PlayerScreen)).toList();
    if (tick == 5) {
      final all = find
          .byElementPredicate((e) => true, skipOffstage: false)
          .evaluate()
          .toList();
      final playerLike = all
          .where(
            (e) => e.widget.runtimeType.toString().contains('PlayerScreen'),
          )
          .toList();
      print('tanı: toplamElement=${all.length} playerLike=${playerLike.length}');
      for (final e in playerLike) {
        print(
          '  ${e.widget.runtimeType} ayniTip='
          '${identical(e.widget.runtimeType, PlayerScreen)} depth=${e.depth}',
        );
      }
      print(
        '  türler: ${all.map((e) => e.widget.runtimeType.toString()).toSet().take(25).toList()}',
      );
    }
    if (states.isEmpty) {
      // Rota geçişi veya derleme hatası: ilk 15 saniye ekranın ağaca
      // girmesini bekle, sonra tanı için döngüden çık.
      if (tick > 15) break;
      continue;
    }
    sawPlayerScreen = true;
    final state = states.first as dynamic;
    startupError = state.startupErrorForTest;
    if (startupError != null) break;
    if (state.playbackReadyForTest == true) {
      ready = true;
      break;
    }
    if (tick % 20 == 0) print('oynatma bekleniyor... ${tick}s');
  }
  expect(sawPlayerScreen, isTrue, reason: 'PlayerScreen ağaca hiç girmedi');
  expect(startupError, isNull, reason: 'oynatıcı açılışı başarısız');
  expect(ready, isTrue, reason: 'oynatma süresinde hazır olmadı');

  final state = tester.state(find.byType(PlayerScreen)) as dynamic;
  final controller = state.playbackControllerForTest;

  // DV algılama hook'u başlıklar geldiğinde asenkron çalışır; kararın
  // yerleşmesi için kısa bir süre daha bekle.
  for (var i = 0; i < 20; i++) {
    if (controller.dolbyVisionReshaping == expectDolbyVisionReshaping) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  expect(controller.dolbyVisionReshaping, expectDolbyVisionReshaping);

  final vf = ((await controller.debugGetProperty('vf')) as String).trim();
  if (expectDolbyVisionReshaping) {
    expect(vf, contains('libplacebo='));
    // Varsayılan SDR modunda filtre bt.709 hedefler; donanım çözmede
    // VideoToolbox kareleri için hwdownload öneki zorunlu.
    expect(vf, contains('hwdownload'));
    expect(vf, contains('color_trc=bt709'));

    // Filtrenin GERÇEKTEN çalıştığının kanıtı: mpv `set vf` başarısız
    // filter grafta bile başarı döndürür, bu yüzden yalnız vf geri okuması
    // kanıt değildir. video-out-params vf zinciri SONRASI değerleri
    // yansıtır; filtre devredeyse gamma artık pq olamaz (C harness kanıtı:
    // bt.709/bt.1886, kare doğal renkte). İlk graf kurulumunda Vulkan
    // cihazı ve shader derlemesi zaman aldığından gamma yoklanır.
    final gammaSdr = await _pollGamma(
      controller,
      (g) => g.isNotEmpty && g != 'pq',
      timeout: const Duration(seconds: 45),
    );
    print('video-out-params/gamma (SDR, reshape açık): $gammaSdr');
    expect(gammaSdr, isNotEmpty);
    expect(
      gammaSdr,
      isNot('pq'),
      reason: 'reshape filtresi çalışmadı: çıkış hâlâ PQ baz katman',
    );

    // HDR moduna geçişte filtre hedefi çalışma zamanında PQ'ya döner ve
    // SDR'e dönüşte geri gelir (kullanıcının HDR anahtarı akışı).
    await controller.setHdrMode(HdrMode.dolbyVision);
    expect(
      ((await controller.debugGetProperty('vf')) as String).trim(),
      contains('color_trc=smpte2084'),
    );
    await controller.setHdrMode(HdrMode.sdr);
    expect(
      ((await controller.debugGetProperty('vf')) as String).trim(),
      contains('color_trc=bt709'),
    );
    // Graf yeniden kurulurken uçuşan kareler eski hedefi taşıyabilir;
    // gamma'nın yerleşmesi yoklanır.
    final gammaBack = await _pollGamma(
      controller,
      (g) => g.isNotEmpty && g != 'pq',
      timeout: const Duration(seconds: 20),
    );
    print('video-out-params/gamma (SDR\'e dönüş): $gammaBack');
    expect(gammaBack, isNot('pq'));
  } else {
    expect(vf, isNot(contains('libplacebo=')));
    // Tanı çıktısı: doğal yol korunuyor (P8/HDR10'da pq beklenir).
    final gamma =
        ((await controller.debugGetProperty('video-out-params/gamma'))
                as String)
            .trim();
    print('video-out-params/gamma (reshape kapalı): $gamma');
  }

  // Elle görsel doğrulama kancası: DV_TEST_HOLD_SECONDS ortam değişkeniyle
  // çağrılırsa tüm denetimler geçtikten sonra video bu süre ekranda tutulur;
  // bu sırada pencere dışarıdan (screencapture) görüntülenebilir. Normal
  // koşuda değişken yoktur ve bekleme yapılmaz.
  final holdSeconds = int.tryParse(
    Platform.environment['DV_TEST_HOLD_SECONDS'] ?? '',
  );
  if (holdSeconds != null) {
    print('görsel doğrulama için ${holdSeconds}s ekranda tutuluyor...');
    await Future<void>.delayed(Duration(seconds: holdSeconds));
  }

  // PlayerScreen'in dispose akışını (oynatıcı + akış oturumu kapanışı)
  // çalıştırmak için ağacı boşalt.
  await tester.pumpWidget(const SizedBox());
  await Future<void>.delayed(const Duration(seconds: 2));
}

/// `video-out-params/gamma` değerini koşul sağlanana ya da süre dolana
/// kadar saniyede bir okur; son gözlenen değeri (boş olabilir) döndürür.
/// Filtre grafının yeniden kurulması ve ilk karenin işlenmesi zaman
/// aldığından tek anlık okuma yarış durumu yaratır.
Future<String> _pollGamma(
  dynamic controller,
  bool Function(String gamma) condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  var gamma = '';
  while (DateTime.now().isBefore(deadline)) {
    gamma = ((await controller.debugGetProperty('video-out-params/gamma'))
            as String)
        .trim();
    if (condition(gamma)) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return gamma;
}
