// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get appSectionTitle => 'App';

  @override
  String get appSectionSubtitle =>
      'Sprach- und Darstellungseinstellungen werden auf diesem Gerät gespeichert.';

  @override
  String get languageLabel => 'Sprache';

  @override
  String get themeLabel => 'Darstellung';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeLight => 'Hell';

  @override
  String get advancedSettings => 'Erweiterte Einstellungen';

  @override
  String get play => 'Abspielen';

  @override
  String get pause => 'Pause';

  @override
  String get selectNzbAndPlay => 'NZB auswählen und abspielen';

  @override
  String get selectNzbHint => 'Eine .nzb-Datei aus dem Dateisystem öffnen';

  @override
  String get engineStarting => 'Lokale Wiedergabe-Engine wird vorbereitet…';

  @override
  String get engineStartFailed =>
      'Die lokale Wiedergabe-Engine konnte nicht gestartet werden';

  @override
  String get engineStartFailedHint =>
      'Überprüfen Sie die Engine-Dateien und die App-Installation und versuchen Sie es erneut.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String errorOpenNzb(String error) {
    return 'Die NZB-Datei konnte nicht geöffnet werden: $error';
  }

  @override
  String get providerSettingsTooltip => 'Anbieter-Einstellungen';

  @override
  String get backTooltip => 'Zurück';

  @override
  String get providerTitle => 'Anbieter';

  @override
  String get nntpSectionTitle => 'NNTP-Verbindung';

  @override
  String get nntpSectionSubtitle =>
      'Die Daten werden nur im sicheren Schlüsselbund dieses Geräts gespeichert.';

  @override
  String get serverAddressLabel => 'Serveradresse';

  @override
  String get portLabel => 'Port';

  @override
  String get connectionLimitLabel => 'Verbindungslimit';

  @override
  String get connectionLimitHint => 'Tariflimit';

  @override
  String get usernameLabel => 'Benutzername';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get passwordShowTooltip => 'Passwort anzeigen';

  @override
  String get passwordHideTooltip => 'Passwort ausblenden';

  @override
  String get saveSecurelyLabel => 'Sicher speichern';

  @override
  String get savingLabel => 'Speichern…';

  @override
  String get settingsSaved => 'Einstellungen wurden sicher gespeichert.';

  @override
  String settingsSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get secureStorageUnavailable =>
      'Auf den sicheren Speicher konnte nicht zugegriffen werden';

  @override
  String get connectionLimitWarning =>
      'Ein Verbindungslimit über dem Tarif Ihres Anbieters kann zu einem Fehler „Zu viele Verbindungen“ führen.';

  @override
  String validationRequired(String field) {
    return '$field ist erforderlich';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field muss zwischen $min und $max liegen';
  }

  @override
  String get validationHostNoProtocol =>
      'Nur den Servernamen eingeben, ohne Protokoll oder Port';

  @override
  String get validationHostInvalid =>
      'Geben Sie einen gültigen Servernamen ein';

  @override
  String get closePlayer => 'Player schließen';

  @override
  String get fullscreen => 'Vollbild';

  @override
  String get subtitleControlsTooltip => 'Bildschirm-Steuerung für Untertitel';

  @override
  String get miniPlayer => 'Mini-Player';

  @override
  String get exitMiniPlayer => 'Mini-Player beenden';

  @override
  String get previousFrame => 'Vorheriges Bild';

  @override
  String get nextFrame => 'Nächstes Bild';

  @override
  String get playbackSpeedTooltip => 'Wiedergabegeschwindigkeit';

  @override
  String get audioTrack => 'Audiospur';

  @override
  String get subtitleTrack => 'Untertitelspur';

  @override
  String get muteTooltip => 'Stumm';

  @override
  String get unmuteTooltip => 'Stummschaltung aufheben';

  @override
  String get loadFromFile => 'Aus Datei laden…';

  @override
  String get auto => 'Automatisch';

  @override
  String get off => 'Aus';

  @override
  String get subtitleDecreaseTooltip => 'Untertitelgröße verkleinern';

  @override
  String get subtitleIncreaseTooltip => 'Untertitelgröße vergrößern';

  @override
  String get subtitleMoveUpTooltip => 'Untertitel nach oben verschieben';

  @override
  String get subtitleMoveDownTooltip => 'Untertitel nach unten verschieben';

  @override
  String get subtitleEarlierTooltip =>
      'Untertitel um 0,1 Sekunden früher anzeigen';

  @override
  String get subtitleLaterTooltip => 'Untertitel um 0,1 Sekunden verzögern';

  @override
  String get closeSubtitleControlsTooltip => 'Untertitel-Steuerung schließen';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas-Zuschneidebereich';

  @override
  String get smartCanvasSemanticsHint =>
      'Zum Anwenden doppeltippen. Zum Abbrechen Escape drücken.';

  @override
  String get smartCanvasHintText => 'Doppeltippen: anwenden · Esc: abbrechen';

  @override
  String get cropHandleTopLeft => 'Zuschneidegriff oben links';

  @override
  String get cropHandleTopRight => 'Zuschneidegriff oben rechts';

  @override
  String get cropHandleBottomLeft => 'Zuschneidegriff unten links';

  @override
  String get cropHandleBottomRight => 'Zuschneidegriff unten rechts';

  @override
  String get statusPreparing => 'Vorbereiten…';

  @override
  String get engineBadgePreparing => 'Native libmpv wird vorbereitet…';

  @override
  String get errorProviderSettingsMissing =>
      'Die Anbieter-Einstellungen sind unvollständig. Geben Sie zuerst Ihre Daten im Einstellungsbildschirm ein.';

  @override
  String get statusConnecting =>
      'Verbindung wird hergestellt und erstes Segment abgerufen (Layout wird erkannt)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Videostruktur wird gelesen: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'Puffern: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Wiedergabe: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Warten auf Videospuren: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent %';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Video wird gestartet$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Der Usenet-Stream konnte nicht innerhalb von $seconds Sekunden gestartet werden. Die Anbieteverbindung, das erste Segment oder der NZB-Inhalt reagiert möglicherweise nicht.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'Das Video konnte nicht innerhalb von $seconds Sekunden erkannt werden. Das NZB enthält möglicherweise ein mehrteiliges Archiv/PAR2 statt eines direkten Videos, ein Segment fehlt oder der Stream ist nicht lesbar.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'Disk-Cache aus';

  @override
  String get engineBadgeSdrSafePath => 'SDR-Sicherheitspfad';

  @override
  String errorControlFailed(String error) {
    return 'Die Steuerung konnte nicht angewendet werden: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Zoom konnte nicht angewendet werden: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture ist auf dieser Plattform nicht verfügbar.';

  @override
  String get fileTypeSubtitles => 'Untertitel';

  @override
  String get fileTypeAudioFiles => 'Audiodateien';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds Sekunden zurück';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds Sekunden vor';
  }

  @override
  String get cancelCanvasEditing => 'Canvas-Bearbeitung abbrechen';

  @override
  String get resetCanvas => 'Canvas zurücksetzen';

  @override
  String get subtitleControls => 'Untertitel-Steuerung';

  @override
  String get loopSetA => 'Punkt A setzen';

  @override
  String get loopSetB => 'Punkt B setzen';

  @override
  String get loopClear => 'A–B-Schleife aufheben';

  @override
  String get tuningMenuItem => 'Video- und Audioeinstellungen…';

  @override
  String get tuningDialogTitle => 'Video und Audio';

  @override
  String get closeTooltip => 'Schließen';

  @override
  String get videoPresetLabel => 'Video-Voreinstellung';

  @override
  String get presetNatural => 'Natürlich';

  @override
  String get presetCinema => 'Kino';

  @override
  String get presetVivid => 'Lebendig';

  @override
  String get gpuScalingLabel => 'GPU-Skalierung';

  @override
  String get presetLowPower => 'Energiesparend';

  @override
  String get presetBalanced => 'Ausgewogen';

  @override
  String get presetQuality => 'Qualität';

  @override
  String get audioPresetLabel => 'Audio-Voreinstellung';

  @override
  String get presetDialogue => 'Dialog';

  @override
  String get presetNight => 'Nacht';

  @override
  String get seekStepLabel => 'Sprungweite';

  @override
  String get periodicInfoLabel => 'Periodische Info';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Audio-Synchronisation';

  @override
  String get audioEarlierTooltip => 'Audio um 0,1 s früher';

  @override
  String get audioLaterTooltip => 'Audio um 0,1 s verzögern';

  @override
  String get decodingLabel => 'Decodierung';

  @override
  String get decodingHardware => 'Hardware';

  @override
  String get decodingSoftware => 'Software';

  @override
  String get dynamicRangeLabel => 'Dynamikumfang';

  @override
  String get hdrInfoText =>
      'Es können nur die vom Inhalt unterstützten Formate ausgewählt werden; die anderen sind deaktiviert. Bei Auswahl von SDR werden HDR-Inhalte per Tone Mapping auf bt.709 abgebildet (BT.2390 + Peak Detect). HDR10+ ist deaktiviert, da libmpv seine dynamischen Metadaten nicht erkennen kann; Dolby Vision wird bei Profilen mit HDR10-Basisebene unterstützt.';

  @override
  String get doneLabel => 'Fertig';

  @override
  String get videoPreparing => 'Video wird vorbereitet…';
}
