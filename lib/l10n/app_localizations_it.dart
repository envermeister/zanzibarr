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
  String get continueWatching => 'Continua a guardare';

  @override
  String get updateAvailable => 'Aggiornamento disponibile';

  @override
  String get updateNow => 'Aggiorna ora';

  @override
  String get updateLater => 'Più tardi';

  @override
  String get updateSkip => 'Salta questa versione';

  @override
  String get updateDownloading => 'Download dell\'aggiornamento…';

  @override
  String get updateOpenPage => 'Apri la pagina di download';

  @override
  String updateFailed(String error) {
    return 'Aggiornamento non riuscito: $error';
  }

  @override
  String get historyRemoveTooltip => 'Rimuovi dalla cronologia';

  @override
  String historyRemaining(String time) {
    return 'Mancano $time';
  }

  @override
  String get subtitleColor => 'Colore dei sottotitoli';

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

  @override
  String get dvReshapeApplying =>
      'Applicazione della correzione colore Dolby Vision…';

  @override
  String get dvReshapeActiveHw =>
      'Correzione colore Dolby Vision attiva (decodifica hardware)';

  @override
  String get dvReshapeActiveSw =>
      'Correzione colore Dolby Vision attiva (decodifica software)';

  @override
  String get dvReshapeFailed =>
      'Impossibile avviare la correzione colore Dolby Vision su questo dispositivo. Tocca per i dettagli.';

  @override
  String get dvReshapeFailedShort =>
      'Impossibile avviare la correzione colore Dolby Vision — dettagli nelle impostazioni avanzate.';

  @override
  String get dvReshapeDiagnosticsTitle => 'Diagnostica della correzione DV';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'Nessuna riga di log del motore catturata per il filtro.';

  @override
  String get errFormatNotRecognized =>
      'Impossibile riconoscere il formato del media. L\'NZB potrebbe contenere un archivio o dati di recupero PAR2 anziché un video diretto.';

  @override
  String get errLocalStreamUnreadable =>
      'Impossibile leggere lo stream video locale. Potrebbe mancare un segmento Usenet o la connessione è caduta.';

  @override
  String get errDecoderFailed =>
      'Il decodificatore video o audio non è riuscito ad aprire lo stream.';

  @override
  String get errPlayerGeneric =>
      'Il lettore non è riuscito ad aprire lo stream.';

  @override
  String get errNoMpvDetail => 'libmpv non ha fornito dettagli.';

  @override
  String get errNoEngineDetail =>
      'Il motore di streaming non ha fornito dettagli.';

  @override
  String technicalDetail(String detail) {
    return 'Dettaglio tecnico: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'È stato raggiunto il limite di connessioni simultanee del provider Usenet. Chiudi le altre sessioni attive o attendi un momento e riprova. Se persiste, riduci il numero di connessioni nell\'app al limite del tuo piano.';

  @override
  String get errAuthFailed =>
      'Autenticazione Usenet non riuscita. Controlla nome utente e password nelle impostazioni del provider.';

  @override
  String get errRarEncrypted =>
      'L\'archivio RAR è cifrato. Le release RAR protette da password non sono supportate; scegli una release impacchettata non cifrata (STORE).';

  @override
  String get err7zPassword =>
      'La password dell\'archivio 7z manca o non è valida. Scegli l\'NZB che porta la password nei suoi metadati.';

  @override
  String get errArchiveCompressed =>
      'Questo archivio è compresso. La riproduzione istantanea richiede una release impacchettata non compressa (COPY/STORE, 7z/RAR).';

  @override
  String get errArchiveSolid =>
      'Questo archivio è solido. La ricerca casuale richiede una release impacchettata come STORE non solido.';

  @override
  String get errRar4 =>
      'Questo archivio RAR usa il vecchio formato RAR4 (o precedente). Solo le release RAR5 STORE sono riproducibili.';

  @override
  String get errSplitArchiveBroken =>
      'L\'archivio multiparte (7z/RAR) è incompleto o corrotto. Scegli un NZB completo che includa tutti i volumi e i segmenti.';

  @override
  String get errMissingSegments =>
      'L\'NZB è incompleto o corrotto: non tutti i segmenti Usenet necessari sono stati trovati. Scegli un altro NZB completo per questa release.';

  @override
  String get errConnectionFailed =>
      'Impossibile connettersi al provider Usenet. Controlla la connessione internet, l\'indirizzo del server, la porta e la raggiungibilità del provider.';

  @override
  String get errNzbUnreadable =>
      'Il file NZB non può essere letto o è corrotto. Scegli un file NZB valido e completo.';

  @override
  String get errArchiveNotPlayable =>
      'L\'archivio (7z/RAR) dentro l\'NZB non è riproducibile o la sua struttura è corrotta. Scegli una release STORE completa.';

  @override
  String get errNoPlayableMedia =>
      'Nell\'NZB non è stato trovato alcuno stream video supportato. Scegli una release con media diretti o un archivio STORE supportato.';

  @override
  String get errStreamStartupGeneric =>
      'Impossibile avviare lo stream. Controlla il contenuto dell\'NZB e la connessione del provider.';
}
