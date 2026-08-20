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
  String get searchIndexerCard => 'Search the indexer';

  @override
  String get searchIndexerCardHint => 'Find releases on a Newznab indexer';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Release name…';

  @override
  String get searchTooltip => 'Search';

  @override
  String get searchClearTooltip => 'Clear';

  @override
  String get searchNoResults => 'No results found';

  @override
  String get searchEmptyHint => 'Type a release name to search your indexer.';

  @override
  String searchResultsTotal(int count) {
    return '$count results';
  }

  @override
  String searchDownloadFailed(String error) {
    return 'Could not download the NZB: $error';
  }

  @override
  String get indexerMissingHint =>
      'Set up the indexer URL and API key in settings first.';

  @override
  String get goToIndexerSettings => 'Open settings';

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
  String get indexerSectionTitle => 'Indexer (Newznab)';

  @override
  String get indexerSectionSubtitle =>
      'Search a Newznab-compatible indexer; the API key is stored in this device\'s secure keychain. Leave the URL empty to disable the indexer.';

  @override
  String get indexerUrlLabel => 'Indexer URL';

  @override
  String get indexerUrlInvalid =>
      'Enter a valid URL starting with http:// or https://';

  @override
  String get indexerApiKeyLabel => 'API key';

  @override
  String get indexerSaveLabel => 'Save indexer';

  @override
  String get indexerTestButton => 'Test connection';

  @override
  String indexerTestSuccess(String name) {
    return 'Connected: $name';
  }

  @override
  String indexerTestFailed(String error) {
    return 'Connection failed: $error';
  }

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
  String get statusPreparingCompressed =>
      'Compressed archive — decoding sequentially, the first open may take a while…';

  @override
  String get repairButton => 'Repair with PAR2';

  @override
  String get repairCancelButton => 'Cancel repair';

  @override
  String get repairPhaseLoading => 'Loading PAR2 index…';

  @override
  String get repairPhaseVerifying =>
      'Verifying slices (full pass over the set)…';

  @override
  String get repairPhaseSolving => 'Solving the recovery matrix…';

  @override
  String get repairPhaseRepairing => 'Rebuilding damaged slices…';

  @override
  String get repairPhaseWriting => 'Writing the repair overlay…';

  @override
  String get repairPhaseDone => 'Repair complete';

  @override
  String repairSuccess(int count) {
    return 'Repair complete: $count slices rebuilt. Reopening…';
  }

  @override
  String get repairClean =>
      'Verification finished — no damage found in this release.';

  @override
  String repairFailed(String error) {
    return 'Repair failed: $error';
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

  @override
  String get dvReshapeApplying => 'Dolby-Vision-Farbkorrektur wird angewendet…';

  @override
  String get dvReshapeActiveHw =>
      'Dolby-Vision-Farbkorrektur aktiv (Hardware-Dekodierung)';

  @override
  String get dvReshapeActiveSw =>
      'Dolby-Vision-Farbkorrektur aktiv (Software-Dekodierung)';

  @override
  String get dvReshapeFailed =>
      'Die Dolby-Vision-Farbkorrektur konnte auf diesem Gerät nicht gestartet werden. Tippe für Details.';

  @override
  String get dvReshapeFailedShort =>
      'Dolby-Vision-Farbkorrektur konnte nicht gestartet werden — Details in den erweiterten Einstellungen.';

  @override
  String get dvReshapeDiagnosticsTitle => 'DV-Korrektur-Diagnose';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'Keine Engine-Logzeilen für den Filter erfasst.';

  @override
  String get errFormatNotRecognized =>
      'Das Medienformat wurde nicht erkannt. Das NZB enthält möglicherweise ein Archiv oder PAR2-Wiederherstellungsdaten statt eines direkten Videos.';

  @override
  String get errLocalStreamUnreadable =>
      'Der lokale Videostream konnte nicht gelesen werden. Möglicherweise fehlt ein Usenet-Segment oder die Verbindung wurde unterbrochen.';

  @override
  String get errDecoderFailed =>
      'Der Video- oder Audio-Decoder konnte den Stream nicht öffnen.';

  @override
  String get errPlayerGeneric => 'Der Player konnte den Stream nicht öffnen.';

  @override
  String get errNoMpvDetail => 'libmpv lieferte keine Details.';

  @override
  String get errNoEngineDetail =>
      'Die Streaming-Engine lieferte keine Details.';

  @override
  String technicalDetail(String detail) {
    return 'Technisches Detail: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Das Limit für gleichzeitige Verbindungen des Usenet-Anbieters wurde erreicht. Schließe andere aktive Sitzungen oder warte kurz und versuche es erneut. Wenn es weiterhin auftritt, senke die Verbindungsanzahl in der App auf das Limit deines Tarifs.';

  @override
  String get errAuthFailed =>
      'Usenet-Authentifizierung fehlgeschlagen. Prüfe Benutzername und Passwort in den Anbieter-Einstellungen.';

  @override
  String get errRarEncrypted =>
      'Das RAR-Archiv ist verschlüsselt. Passwortgeschützte RAR-Releases werden nicht unterstützt; wähle ein unverschlüsselt gepacktes Release (STORE).';

  @override
  String get err7zPassword =>
      'Das Passwort des 7z-Archivs fehlt oder ist ungültig. Wähle das NZB, das das Passwort in seinen Metadaten trägt.';

  @override
  String get errArchiveCompressed =>
      'Dieses Archiv ist komprimiert. Sofortige Wiedergabe erfordert ein unkomprimiert gepacktes Release (COPY/STORE, 7z/RAR).';

  @override
  String get errArchiveSolid =>
      'Dieses Archiv ist solid. Zufälliges Springen erfordert ein als nicht-solid STORE gepacktes Release.';

  @override
  String get errRar4 =>
      'Dieses RAR-Archiv nutzt das alte RAR4-Format (oder älter). Nur RAR5-STORE-Releases sind abspielbar.';

  @override
  String get errSplitArchiveBroken =>
      'Das mehrteilige Archiv (7z/RAR) ist unvollständig oder beschädigt. Wähle ein vollständiges NZB mit allen Volumes und Segmenten.';

  @override
  String get errMissingSegments =>
      'Das NZB ist unvollständig oder beschädigt: nicht alle benötigten Usenet-Segmente können gefunden werden. Wähle ein anderes, vollständiges NZB für dieses Release.';

  @override
  String get errConnectionFailed =>
      'Verbindung zum Usenet-Anbieter fehlgeschlagen. Prüfe deine Internetverbindung, die Serveradresse, den Port und die Erreichbarkeit des Anbieters.';

  @override
  String get errNzbUnreadable =>
      'Die NZB-Datei konnte nicht gelesen werden oder ist beschädigt. Wähle eine gültige, vollständige NZB-Datei.';

  @override
  String get errArchiveNotPlayable =>
      'Das Archiv (7z/RAR) im NZB ist nicht abspielbar oder seine Struktur ist beschädigt. Wähle ein vollständiges STORE-Release.';

  @override
  String get errNoPlayableMedia =>
      'Im NZB wurde kein unterstützter Videostream gefunden. Wähle ein Release mit direkten Medien oder einem unterstützten STORE-Archiv.';

  @override
  String get errStreamStartupGeneric =>
      'Der Stream konnte nicht gestartet werden. Prüfe den NZB-Inhalt und die Anbieterverbindung.';
}
