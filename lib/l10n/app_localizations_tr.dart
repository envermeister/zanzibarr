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
}
