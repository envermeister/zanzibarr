// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get appSectionTitle => 'Uygulama';

  @override
  String get appSectionSubtitle =>
      'Dil ve görünüm tercihi bu cihazda saklanır.';

  @override
  String get languageLabel => 'Dil';

  @override
  String get themeLabel => 'Görünüm';

  @override
  String get themeDark => 'Koyu';

  @override
  String get themeLight => 'Açık';

  @override
  String get advancedSettings => 'Gelişmiş ayarlar';

  @override
  String get play => 'Oynat';

  @override
  String get pause => 'Duraklat';

  @override
  String get selectNzbAndPlay => 'NZB seç ve oynat';

  @override
  String get selectNzbHint => 'Dosya sisteminden bir .nzb aç';

  @override
  String get searchIndexerCard => 'Indexer\'da ara';

  @override
  String get searchIndexerCardHint => 'Newznab indexer\'ında sürüm bul';

  @override
  String get searchTitle => 'Ara';

  @override
  String get searchHint => 'Sürüm adı…';

  @override
  String get searchTooltip => 'Ara';

  @override
  String get searchClearTooltip => 'Temizle';

  @override
  String get searchNoResults => 'Sonuç bulunamadı';

  @override
  String get searchEmptyHint =>
      'Indexer\'ınızda aramak için bir sürüm adı yazın.';

  @override
  String searchResultsTotal(int count) {
    return '$count sonuç';
  }

  @override
  String searchDownloadFailed(String error) {
    return 'NZB indirilemedi: $error';
  }

  @override
  String get indexerMissingHint =>
      'Önce ayarlardan indexer URL\'sini ve API anahtarını girin.';

  @override
  String get goToIndexerSettings => 'Ayarlara git';

  @override
  String get engineStarting => 'Yerel oynatma motoru hazırlanıyor…';

  @override
  String get engineStartFailed => 'Yerel oynatma motoru başlatılamadı';

  @override
  String get engineStartFailedHint =>
      'Motor dosyalarını ve uygulama kurulumunu kontrol edip yeniden deneyin.';

  @override
  String get retry => 'Yeniden dene';

  @override
  String errorOpenNzb(String error) {
    return 'NZB dosyası açılamadı: $error';
  }

  @override
  String get providerSettingsTooltip => 'Sağlayıcı ayarları';

  @override
  String get backTooltip => 'Geri';

  @override
  String get providerTitle => 'Sağlayıcı';

  @override
  String get nntpSectionTitle => 'NNTP bağlantısı';

  @override
  String get nntpSectionSubtitle =>
      'Bilgiler yalnızca bu cihazın güvenli anahtar zincirinde saklanır.';

  @override
  String get serverAddressLabel => 'Sunucu adresi';

  @override
  String get portLabel => 'Port';

  @override
  String get connectionLimitLabel => 'Bağlantı limiti';

  @override
  String get connectionLimitHint => 'Plan limiti';

  @override
  String get usernameLabel => 'Kullanıcı adı';

  @override
  String get passwordLabel => 'Parola';

  @override
  String get passwordShowTooltip => 'Parolayı göster';

  @override
  String get passwordHideTooltip => 'Parolayı gizle';

  @override
  String get saveSecurelyLabel => 'Güvenle kaydet';

  @override
  String get savingLabel => 'Kaydediliyor…';

  @override
  String get settingsSaved => 'Ayarlar güvenli depoya kaydedildi.';

  @override
  String settingsSaveFailed(String error) {
    return 'Kaydedilemedi: $error';
  }

  @override
  String get secureStorageUnavailable => 'Güvenli depoya erişilemedi';

  @override
  String get connectionLimitWarning =>
      'Bağlantı limitini sağlayıcınızın planından yüksek seçmek, “çok fazla bağlantı” hatasına yol açabilir.';

  @override
  String get indexerSectionTitle => 'Indexer (Newznab)';

  @override
  String get indexerSectionSubtitle =>
      'Newznab uyumlu indexer\'da arama yapın; API anahtarı bu cihazın güvenli anahtar zincirinde saklanır. Indexer\'ı kapatmak için URL\'yi boş bırakın.';

  @override
  String get indexerUrlLabel => 'Indexer URL\'si';

  @override
  String get indexerUrlInvalid =>
      'http:// veya https:// ile başlayan geçerli bir URL girin';

  @override
  String get indexerApiKeyLabel => 'API anahtarı';

  @override
  String get indexerSaveLabel => 'Indexer\'ı kaydet';

  @override
  String get indexerTestButton => 'Bağlantıyı sına';

  @override
  String indexerTestSuccess(String name) {
    return 'Bağlandı: $name';
  }

  @override
  String indexerTestFailed(String error) {
    return 'Bağlantı kurulamadı: $error';
  }

  @override
  String validationRequired(String field) {
    return '$field gerekli';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field $min–$max arasında olmalı';
  }

  @override
  String get validationHostNoProtocol =>
      'Yalnız sunucu adını girin; protokol ve port eklemeyin';

  @override
  String get validationHostInvalid => 'Geçerli bir sunucu adı girin';

  @override
  String get closePlayer => 'Oynatıcıyı kapat';

  @override
  String get fullscreen => 'Tam ekran';

  @override
  String get subtitleControlsTooltip => 'Ekran üstü altyazı kontrolleri';

  @override
  String get miniPlayer => 'Mini oynatıcı';

  @override
  String get exitMiniPlayer => 'Mini oynatıcıdan çık';

  @override
  String get previousFrame => 'Önceki kare';

  @override
  String get nextFrame => 'Sonraki kare';

  @override
  String get playbackSpeedTooltip => 'Oynatma hızı';

  @override
  String get audioTrack => 'Ses izi';

  @override
  String get subtitleTrack => 'Altyazı izi';

  @override
  String get muteTooltip => 'Sesi kapat';

  @override
  String get unmuteTooltip => 'Sesi aç';

  @override
  String get loadFromFile => 'Dosyadan yükle…';

  @override
  String get auto => 'Otomatik';

  @override
  String get off => 'Kapalı';

  @override
  String get subtitleDecreaseTooltip => 'Altyazıyı küçült';

  @override
  String get continueWatching => 'İzlemeye devam et';

  @override
  String get updateAvailable => 'Güncelleme mevcut';

  @override
  String get updateNow => 'Şimdi güncelle';

  @override
  String get updateLater => 'Daha sonra';

  @override
  String get updateSkip => 'Bu sürümü atla';

  @override
  String get updateDownloading => 'Güncelleme indiriliyor…';

  @override
  String get updateOpenPage => 'İndirme sayfasını aç';

  @override
  String updateFailed(String error) {
    return 'Güncelleme başarısız: $error';
  }

  @override
  String get historyRemoveTooltip => 'Geçmişten kaldır';

  @override
  String historyRemaining(String time) {
    return '$time kaldı';
  }

  @override
  String get subtitleColor => 'Altyazı rengi';

  @override
  String get subtitleIncreaseTooltip => 'Altyazıyı büyüt';

  @override
  String get subtitleMoveUpTooltip => 'Altyazıyı yukarı taşı';

  @override
  String get subtitleMoveDownTooltip => 'Altyazıyı aşağı taşı';

  @override
  String get subtitleEarlierTooltip => 'Altyazıyı 0,1 saniye erkene al';

  @override
  String get subtitleLaterTooltip => 'Altyazıyı 0,1 saniye geciktir';

  @override
  String get closeSubtitleControlsTooltip => 'Altyazı kontrollerini kapat';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas kırpma alanı';

  @override
  String get smartCanvasSemanticsHint =>
      'Çift tıklayarak uygula. Escape ile iptal et.';

  @override
  String get smartCanvasHintText => 'Çift tık: uygula · Esc: iptal';

  @override
  String get cropHandleTopLeft => 'Sol üst kırpma tutamacı';

  @override
  String get cropHandleTopRight => 'Sağ üst kırpma tutamacı';

  @override
  String get cropHandleBottomLeft => 'Sol alt kırpma tutamacı';

  @override
  String get cropHandleBottomRight => 'Sağ alt kırpma tutamacı';

  @override
  String get statusPreparing => 'Hazırlanıyor…';

  @override
  String get engineBadgePreparing => 'Native libmpv hazırlanıyor…';

  @override
  String get errorProviderSettingsMissing =>
      'Sağlayıcı ayarları eksik. Önce ayar ekranından bilgileri girin.';

  @override
  String get statusConnecting =>
      'Bağlanılıyor ve ilk segment çekiliyor (yerleşim öğreniliyor)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Video yapısı okunuyor: $filename';
  }

  @override
  String get statusPreparingCompressed =>
      'Sıkıştırılmış arşiv — sırayla çözülüyor, ilk açılış uzun sürebilir…';

  @override
  String get repairButton => 'PAR2 ile onar';

  @override
  String get repairCancelButton => 'Onarımı iptal et';

  @override
  String get repairPhaseLoading => 'PAR2 dizini yükleniyor…';

  @override
  String get repairPhaseVerifying =>
      'Dilimler doğrulanıyor (set üzerinde tam tur)…';

  @override
  String get repairPhaseSolving => 'Kurtarma matrisi çözülüyor…';

  @override
  String get repairPhaseRepairing => 'Hasarlı dilimler yeniden kuruluyor…';

  @override
  String get repairPhaseWriting => 'Onarım katmanı yazılıyor…';

  @override
  String get repairPhaseDone => 'Onarım tamamlandı';

  @override
  String repairSuccess(int count) {
    return 'Onarım tamam: $count dilim yeniden kuruldu. Yeniden açılıyor…';
  }

  @override
  String get repairClean => 'Doğrulama tamam — bu yayında hasar bulunamadı.';

  @override
  String repairFailed(String error) {
    return 'Onarım başarısız: $error';
  }

  @override
  String statusBuffering(String filename) {
    return 'Arabelleğe alınıyor: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Oynatılıyor: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Video izleri bekleniyor: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' %$percent';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Video başlatılıyor$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Usenet akışı $seconds saniye içinde başlatılamadı. Sağlayıcı bağlantısı, ilk segment veya NZB içeriği yanıt vermiyor olabilir.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'Video $seconds saniye içinde tanınamadı. NZB doğrudan video yerine çok parçalı arşiv/PAR2 içeriyor, bir segment eksik veya akış okunamıyor olabilir.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'disk cache kapalı';

  @override
  String get engineBadgeSdrSafePath => 'SDR güvenli yol';

  @override
  String errorControlFailed(String error) {
    return 'Kontrol uygulanamadı: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Zoom uygulanamadı: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture bu platformda kullanılamıyor.';

  @override
  String get fileTypeSubtitles => 'Altyazılar';

  @override
  String get fileTypeAudioFiles => 'Ses dosyaları';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds saniye geri';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds saniye ileri';
  }

  @override
  String get cancelCanvasEditing => 'Canvas düzenlemeyi iptal et';

  @override
  String get resetCanvas => 'Canvas ayarını sıfırla';

  @override
  String get subtitleControls => 'Altyazı kontrolleri';

  @override
  String get loopSetA => 'A noktasını seç';

  @override
  String get loopSetB => 'B noktasını seç';

  @override
  String get loopClear => 'A–B döngüsünü temizle';

  @override
  String get tuningMenuItem => 'Görüntü ve ses ayarları…';

  @override
  String get tuningDialogTitle => 'Görüntü ve ses';

  @override
  String get closeTooltip => 'Kapat';

  @override
  String get videoPresetLabel => 'Video teması';

  @override
  String get presetNatural => 'Doğal';

  @override
  String get presetCinema => 'Sinema';

  @override
  String get presetVivid => 'Canlı';

  @override
  String get gpuScalingLabel => 'GPU ölçekleme';

  @override
  String get presetLowPower => 'Düşük güç';

  @override
  String get presetBalanced => 'Dengeli';

  @override
  String get presetQuality => 'Kalite';

  @override
  String get audioPresetLabel => 'Ses teması';

  @override
  String get presetDialogue => 'Diyalog';

  @override
  String get presetNight => 'Gece';

  @override
  String get seekStepLabel => 'Seek adımı';

  @override
  String get periodicInfoLabel => 'Periyodik bilgi';

  @override
  String get secondsUnitShort => 'sn';

  @override
  String get audioSyncLabel => 'Ses senkronu';

  @override
  String get audioEarlierTooltip => 'Sesi 0,1 sn erkene al';

  @override
  String get audioLaterTooltip => 'Sesi 0,1 sn geciktir';

  @override
  String get decodingLabel => 'Kod çözme';

  @override
  String get decodingHardware => 'Donanım';

  @override
  String get decodingSoftware => 'Yazılım';

  @override
  String get dynamicRangeLabel => 'Dinamik aralık';

  @override
  String get hdrInfoText =>
      'İçeriğin taşıdığı formatlar seçilebilir, diğerleri pasiftir. SDR seçiliyken HDR içerik bt.709\'a ton eşlenir (BT.2390 + peak detect). HDR10+ dinamik üstverisi libmpv tarafından algılanamadığı için pasiftir; Dolby Vision, HDR10 taban katmanı bulunan profillerde desteklenir.';

  @override
  String get doneLabel => 'Bitti';

  @override
  String get videoPreparing => 'Video hazırlanıyor…';

  @override
  String get dvReshapeApplying => 'Dolby Vision renk düzeltmesi uygulanıyor…';

  @override
  String get dvReshapeActiveHw =>
      'Dolby Vision renk düzeltmesi etkin (donanım çözme)';

  @override
  String get dvReshapeActiveSw =>
      'Dolby Vision renk düzeltmesi etkin (yazılım çözme)';

  @override
  String get dvReshapeFailed =>
      'Dolby Vision renk düzeltmesi bu cihazda başlatılamadı. Ayrıntılar için dokunun.';

  @override
  String get dvReshapeFailedShort =>
      'Dolby Vision renk düzeltmesi başlatılamadı — ayrıntılar gelişmiş ayarlarda.';

  @override
  String get dvReshapeDiagnosticsTitle => 'DV düzeltme tanılaması';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'Filtre için motor günlüğü satırı yakalanamadı.';

  @override
  String get errFormatNotRecognized =>
      'Medya biçimi tanınamadı. NZB doğrudan bir video yerine arşiv veya PAR2 kurtarma verisi içeriyor olabilir.';

  @override
  String get errLocalStreamUnreadable =>
      'Yerel video akışı okunamadı. Bir Usenet segmenti eksik olabilir veya bağlantı kesilmiş olabilir.';

  @override
  String get errDecoderFailed => 'Video veya ses çözücüsü akışı açamadı.';

  @override
  String get errPlayerGeneric => 'Oynatıcı akışı açamadı.';

  @override
  String get errNoMpvDetail => 'libmpv ayrıntı vermedi.';

  @override
  String get errNoEngineDetail => 'Akış motoru ayrıntı vermedi.';

  @override
  String technicalDetail(String detail) {
    return 'Teknik ayrıntı: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Usenet sağlayıcısının eşzamanlı bağlantı sınırına ulaşıldı. Diğer aktif oturumları kapatın veya kısa süre bekleyip yeniden deneyin. Sorun sürerse uygulamadaki bağlantı sayısını plan limitinize göre düşürün.';

  @override
  String get errAuthFailed =>
      'Usenet kimlik doğrulaması başarısız. Sağlayıcı ayarlarındaki kullanıcı adı ve parolayı kontrol edin.';

  @override
  String get errRarEncrypted =>
      'RAR arşivi şifreli. Parola korumalı RAR yayınları desteklenmiyor; şifresiz hazırlanmış bir STORE yayını seçin.';

  @override
  String get err7zPassword =>
      '7z arşivinin parolası eksik veya geçersiz. Parola bilgisini metadata içinde taşıyan doğru NZB dosyasını seçin.';

  @override
  String get errArchiveCompressed =>
      'Bu arşiv sıkıştırılmış. Anlık oynatma için sıkıştırmasız COPY/STORE (7z/RAR) biçiminde hazırlanmış bir yayın gerekir.';

  @override
  String get errArchiveSolid =>
      'Bu arşiv solid yapıda. Rastgele ileri-geri sarma için non-solid STORE biçiminde hazırlanmış bir yayın gerekir.';

  @override
  String get errRar4 =>
      'Bu RAR arşivi eski (RAR4 veya öncesi) biçimde. Yalnız RAR5 STORE yayınları oynatılabilir.';

  @override
  String get errSplitArchiveBroken =>
      'Çok parçalı arşiv (7z/RAR) eksik veya bozuk. Tüm ciltleri ve segmentleri içeren eksiksiz bir NZB dosyası seçin.';

  @override
  String get errMissingSegments =>
      'NZB eksik veya bozuk: gerekli Usenet segmentlerinin tamamı bulunamıyor. Bu yayın için eksiksiz başka bir NZB dosyası seçin.';

  @override
  String get errConnectionFailed =>
      'Usenet sağlayıcısına bağlanılamadı. İnternet bağlantısını, sunucu adresini, portu ve sağlayıcının erişilebilirliğini kontrol edin.';

  @override
  String get errNzbUnreadable =>
      'NZB dosyası okunamadı veya yapısı bozuk. Geçerli ve eksiksiz bir NZB dosyası seçin.';

  @override
  String get errArchiveNotPlayable =>
      'NZB içindeki arşiv (7z/RAR) oynatmaya uygun değil veya arşiv yapısı bozuk. Eksiksiz bir STORE yayını seçin.';

  @override
  String get errNoPlayableMedia =>
      'NZB içinde desteklenen bir video akışı bulunamadı. Doğrudan medya veya desteklenen STORE arşivi içeren bir yayın seçin.';

  @override
  String get errStreamStartupGeneric =>
      'Akış başlatılamadı. NZB içeriğini ve sağlayıcı bağlantısını kontrol edin.';
}
