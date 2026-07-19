// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get appSectionTitle => 'Applicazione';

  @override
  String get appSectionSubtitle =>
      'Le preferenze di lingua e aspetto vengono salvate su questo dispositivo.';

  @override
  String get languageLabel => 'Lingua';

  @override
  String get themeLabel => 'Aspetto';

  @override
  String get themeDark => 'Scuro';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get advancedSettings => 'Impostazioni avanzate';

  @override
  String get play => 'Riproduci';

  @override
  String get pause => 'Pausa';

  @override
  String get selectNzbAndPlay => 'Seleziona NZB e riproduci';

  @override
  String get selectNzbHint => 'Apri un file .nzb dal file system';

  @override
  String get engineStarting =>
      'Preparazione del motore di riproduzione locale…';

  @override
  String get engineStartFailed =>
      'Impossibile avviare il motore di riproduzione locale';

  @override
  String get engineStartFailedHint =>
      'Controlla i file del motore e l\'installazione dell\'app, quindi riprova.';

  @override
  String get retry => 'Riprova';

  @override
  String errorOpenNzb(String error) {
    return 'Impossibile aprire il file NZB: $error';
  }

  @override
  String get providerSettingsTooltip => 'Impostazioni provider';

  @override
  String get backTooltip => 'Indietro';

  @override
  String get providerTitle => 'Provider';

  @override
  String get nntpSectionTitle => 'Connessione NNTP';

  @override
  String get nntpSectionSubtitle =>
      'I dati vengono salvati solo nel portachiavi sicuro di questo dispositivo.';

  @override
  String get serverAddressLabel => 'Indirizzo del server';

  @override
  String get portLabel => 'Porta';

  @override
  String get connectionLimitLabel => 'Limite di connessioni';

  @override
  String get connectionLimitHint => 'Limite del piano';

  @override
  String get usernameLabel => 'Nome utente';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordShowTooltip => 'Mostra password';

  @override
  String get passwordHideTooltip => 'Nascondi password';

  @override
  String get saveSecurelyLabel => 'Salva in modo sicuro';

  @override
  String get savingLabel => 'Salvataggio…';

  @override
  String get settingsSaved => 'Impostazioni salvate nell\'archivio sicuro.';

  @override
  String settingsSaveFailed(String error) {
    return 'Impossibile salvare: $error';
  }

  @override
  String get secureStorageUnavailable =>
      'Impossibile accedere all\'archivio sicuro';

  @override
  String get connectionLimitWarning =>
      'Impostare un limite di connessioni superiore a quello del piano del provider può causare un errore «troppe connessioni».';

  @override
  String validationRequired(String field) {
    return '$field è obbligatorio';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field deve essere compreso tra $min e $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Inserisci solo il nome del server, senza protocollo né porta';

  @override
  String get validationHostInvalid => 'Inserisci un nome di server valido';

  @override
  String get closePlayer => 'Chiudi lettore';

  @override
  String get fullscreen => 'Schermo intero';

  @override
  String get subtitleControlsTooltip => 'Controlli sottotitoli su schermo';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get exitMiniPlayer => 'Esci dal mini player';

  @override
  String get previousFrame => 'Fotogramma precedente';

  @override
  String get nextFrame => 'Fotogramma successivo';

  @override
  String get playbackSpeedTooltip => 'Velocità di riproduzione';

  @override
  String get audioTrack => 'Traccia audio';

  @override
  String get subtitleTrack => 'Traccia sottotitoli';

  @override
  String get muteTooltip => 'Disattiva audio';

  @override
  String get unmuteTooltip => 'Attiva audio';

  @override
  String get loadFromFile => 'Carica da file…';

  @override
  String get auto => 'Auto';

  @override
  String get off => 'Off';

  @override
  String get subtitleDecreaseTooltip => 'Riduci dimensione sottotitoli';

  @override
  String get subtitleIncreaseTooltip => 'Aumenta dimensione sottotitoli';

  @override
  String get subtitleMoveUpTooltip => 'Sposta i sottotitoli in alto';

  @override
  String get subtitleMoveDownTooltip => 'Sposta i sottotitoli in basso';

  @override
  String get subtitleEarlierTooltip => 'Anticipa i sottotitoli di 0,1 secondi';

  @override
  String get subtitleLaterTooltip => 'Ritarda i sottotitoli di 0,1 secondi';

  @override
  String get closeSubtitleControlsTooltip => 'Chiudi controlli sottotitoli';

  @override
  String get smartCanvasAreaLabel => 'Area di ritaglio Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'Tocca due volte per applicare. Premi Esc per annullare.';

  @override
  String get smartCanvasHintText => 'Doppio tocco: applica · Esc: annulla';

  @override
  String get cropHandleTopLeft => 'Maniglia di ritaglio in alto a sinistra';

  @override
  String get cropHandleTopRight => 'Maniglia di ritaglio in alto a destra';

  @override
  String get cropHandleBottomLeft => 'Maniglia di ritaglio in basso a sinistra';

  @override
  String get cropHandleBottomRight => 'Maniglia di ritaglio in basso a destra';

  @override
  String get statusPreparing => 'Preparazione…';

  @override
  String get engineBadgePreparing => 'Preparazione di libmpv nativo…';

  @override
  String get errorProviderSettingsMissing =>
      'Le impostazioni del provider sono incomplete. Inserisci prima i tuoi dati nella schermata delle impostazioni.';

  @override
  String get statusConnecting =>
      'Connessione e recupero del primo segmento (analisi del layout)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Lettura della struttura del video: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'Buffering: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Riproduzione: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'In attesa delle tracce video: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Avvio del video$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Lo stream Usenet non è stato avviato entro $seconds secondi. La connessione al provider, il primo segmento o il contenuto NZB potrebbero non rispondere.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'Il video non è stato riconosciuto entro $seconds secondi. L\'NZB potrebbe contenere un archivio in più parti/PAR2 invece di un video diretto, un segmento potrebbe mancare o lo stream potrebbe essere illeggibile.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'cache su disco disattivata';

  @override
  String get engineBadgeSdrSafePath => 'percorso sicuro SDR';

  @override
  String errorControlFailed(String error) {
    return 'Impossibile applicare il controllo: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Impossibile applicare lo zoom: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture non è disponibile su questa piattaforma.';

  @override
  String get fileTypeSubtitles => 'Sottotitoli';

  @override
  String get fileTypeAudioFiles => 'File audio';

  @override
  String seekBackSeconds(int seconds) {
    return 'Indietro di $seconds secondi';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Avanti di $seconds secondi';
  }

  @override
  String get cancelCanvasEditing => 'Annulla modifica del canvas';

  @override
  String get resetCanvas => 'Reimposta canvas';

  @override
  String get subtitleControls => 'Controlli sottotitoli';

  @override
  String get loopSetA => 'Imposta punto A';

  @override
  String get loopSetB => 'Imposta punto B';

  @override
  String get loopClear => 'Cancella loop A–B';

  @override
  String get tuningMenuItem => 'Impostazioni video e audio…';

  @override
  String get tuningDialogTitle => 'Video e audio';

  @override
  String get closeTooltip => 'Chiudi';

  @override
  String get videoPresetLabel => 'Preset video';

  @override
  String get presetNatural => 'Naturale';

  @override
  String get presetCinema => 'Cinema';

  @override
  String get presetVivid => 'Vivace';

  @override
  String get gpuScalingLabel => 'Ridimensionamento GPU';

  @override
  String get presetLowPower => 'Risparmio energetico';

  @override
  String get presetBalanced => 'Bilanciato';

  @override
  String get presetQuality => 'Qualità';

  @override
  String get audioPresetLabel => 'Preset audio';

  @override
  String get presetDialogue => 'Dialoghi';

  @override
  String get presetNight => 'Notte';

  @override
  String get seekStepLabel => 'Passo di ricerca';

  @override
  String get periodicInfoLabel => 'Info periodiche';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Sincronizzazione audio';

  @override
  String get audioEarlierTooltip => 'Anticipa l\'audio di 0,1 s';

  @override
  String get audioLaterTooltip => 'Ritarda l\'audio di 0,1 s';

  @override
  String get decodingLabel => 'Decodifica';

  @override
  String get decodingHardware => 'Hardware';

  @override
  String get decodingSoftware => 'Software';

  @override
  String get dynamicRangeLabel => 'Gamma dinamica';

  @override
  String get hdrInfoText =>
      'È possibile selezionare solo i formati presenti nel contenuto; gli altri sono disattivati. Quando è selezionato SDR, ai contenuti HDR viene applicata la mappatura dei toni su bt.709 (BT.2390 + peak detect). HDR10+ è disattivato perché libmpv non riesce a rilevare i suoi metadati dinamici; Dolby Vision è supportato sui profili che includono un livello base HDR10.';

  @override
  String get doneLabel => 'Fine';

  @override
  String get videoPreparing => 'Preparazione del video…';
}
