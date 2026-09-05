// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get appSectionTitle => 'Aplicación';

  @override
  String get appSectionSubtitle =>
      'Las preferencias de idioma y apariencia se guardan en este dispositivo.';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get themeLabel => 'Apariencia';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get advancedSettings => 'Ajustes avanzados';

  @override
  String get play => 'Reproducir';

  @override
  String get pause => 'Pausar';

  @override
  String get selectNzbAndPlay => 'Seleccionar NZB y reproducir';

  @override
  String get selectNzbHint => 'Abrir un .nzb desde el sistema de archivos';

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
  String get engineStarting => 'Preparando el motor de reproducción local…';

  @override
  String get engineStartFailed =>
      'No se pudo iniciar el motor de reproducción local';

  @override
  String get engineStartFailedHint =>
      'Comprueba los archivos del motor y la instalación de la aplicación, e inténtalo de nuevo.';

  @override
  String get retry => 'Reintentar';

  @override
  String errorOpenNzb(String error) {
    return 'No se pudo abrir el archivo NZB: $error';
  }

  @override
  String get providerSettingsTooltip => 'Ajustes del proveedor';

  @override
  String get backTooltip => 'Atrás';

  @override
  String get providerTitle => 'Proveedor';

  @override
  String get nntpSectionTitle => 'Conexión NNTP';

  @override
  String get nntpSectionSubtitle =>
      'Los datos se guardan solo en el llavero seguro de este dispositivo.';

  @override
  String get serverAddressLabel => 'Dirección del servidor';

  @override
  String get portLabel => 'Puerto';

  @override
  String get connectionLimitLabel => 'Límite de conexiones';

  @override
  String get connectionLimitHint => 'Límite del plan';

  @override
  String get usernameLabel => 'Nombre de usuario';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get passwordShowTooltip => 'Mostrar contraseña';

  @override
  String get passwordHideTooltip => 'Ocultar contraseña';

  @override
  String get saveSecurelyLabel => 'Guardar de forma segura';

  @override
  String get savingLabel => 'Guardando…';

  @override
  String get settingsSaved => 'Ajustes guardados en el almacenamiento seguro.';

  @override
  String settingsSaveFailed(String error) {
    return 'No se pudo guardar: $error';
  }

  @override
  String get secureStorageUnavailable =>
      'No se pudo acceder al almacenamiento seguro';

  @override
  String get connectionLimitWarning =>
      'Establecer el límite de conexiones por encima del plan de tu proveedor puede causar un error de «demasiadas conexiones».';

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
    return '$field es obligatorio';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field debe estar entre $min y $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Introduce solo el nombre del servidor, sin protocolo ni puerto';

  @override
  String get validationHostInvalid => 'Introduce un nombre de servidor válido';

  @override
  String get closePlayer => 'Cerrar reproductor';

  @override
  String get fullscreen => 'Pantalla completa';

  @override
  String get subtitleControlsTooltip => 'Controles de subtítulos en pantalla';

  @override
  String get miniPlayer => 'Minirreproductor';

  @override
  String get exitMiniPlayer => 'Salir del minirreproductor';

  @override
  String get previousFrame => 'Fotograma anterior';

  @override
  String get nextFrame => 'Fotograma siguiente';

  @override
  String get playbackSpeedTooltip => 'Velocidad de reproducción';

  @override
  String get audioTrack => 'Pista de audio';

  @override
  String get subtitleTrack => 'Pista de subtítulos';

  @override
  String get muteTooltip => 'Silenciar';

  @override
  String get unmuteTooltip => 'Activar sonido';

  @override
  String get loadFromFile => 'Cargar desde archivo…';

  @override
  String get auto => 'Automático';

  @override
  String get off => 'Desactivado';

  @override
  String get subtitleDecreaseTooltip => 'Reducir tamaño de subtítulos';

  @override
  String get continueWatching => 'Seguir viendo';

  @override
  String get videoFitCover => 'Llenar pantalla';

  @override
  String get videoFitContain => 'Ajustar a la pantalla';

  @override
  String get updateAvailable => 'Actualización disponible';

  @override
  String get updateNow => 'Actualizar ahora';

  @override
  String get updateLater => 'Más tarde';

  @override
  String get updateSkip => 'Omitir esta versión';

  @override
  String get updateDownloading => 'Descargando actualización…';

  @override
  String get updateOpenPage => 'Abrir página de descarga';

  @override
  String updateFailed(String error) {
    return 'Error al actualizar: $error';
  }

  @override
  String get historyRemoveTooltip => 'Quitar del historial';

  @override
  String historyRemaining(String time) {
    return 'Quedan $time';
  }

  @override
  String get subtitleColor => 'Color de los subtítulos';

  @override
  String get subtitleIncreaseTooltip => 'Aumentar tamaño de subtítulos';

  @override
  String get subtitleMoveUpTooltip => 'Subir subtítulos';

  @override
  String get subtitleMoveDownTooltip => 'Bajar subtítulos';

  @override
  String get subtitleEarlierTooltip => 'Adelantar subtítulos 0,1 segundos';

  @override
  String get subtitleLaterTooltip => 'Retrasar subtítulos 0,1 segundos';

  @override
  String get closeSubtitleControlsTooltip => 'Cerrar controles de subtítulos';

  @override
  String get smartCanvasAreaLabel => 'Área de recorte de Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'Doble toque para aplicar. Pulsa Escape para cancelar.';

  @override
  String get smartCanvasHintText => 'Doble toque: aplicar · Esc: cancelar';

  @override
  String get cropHandleTopLeft => 'Control de recorte superior izquierdo';

  @override
  String get cropHandleTopRight => 'Control de recorte superior derecho';

  @override
  String get cropHandleBottomLeft => 'Control de recorte inferior izquierdo';

  @override
  String get cropHandleBottomRight => 'Control de recorte inferior derecho';

  @override
  String get statusPreparing => 'Preparando…';

  @override
  String get engineBadgePreparing => 'Preparando libmpv nativo…';

  @override
  String get errorProviderSettingsMissing =>
      'Los ajustes del proveedor están incompletos. Introduce primero tus datos en la pantalla de ajustes.';

  @override
  String get statusConnecting =>
      'Conectando y obteniendo el primer segmento (aprendiendo la disposición)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Leyendo la estructura del vídeo: $filename';
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
    return 'Almacenando en búfer: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Reproduciendo: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Esperando las pistas de vídeo: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Iniciando vídeo$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'La transmisión de Usenet no pudo iniciarse en $seconds segundos. Es posible que la conexión del proveedor, el primer segmento o el contenido NZB no responda.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'El vídeo no pudo reconocerse en $seconds segundos. Es posible que el NZB contenga un archivo multiparte/PAR2 en lugar de un vídeo directo, que falte un segmento o que la transmisión sea ilegible.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'caché de disco desactivada';

  @override
  String get engineBadgeSdrSafePath => 'ruta segura SDR';

  @override
  String errorControlFailed(String error) {
    return 'No se pudo aplicar el control: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'No se pudo aplicar el zoom: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture no está disponible en esta plataforma.';

  @override
  String get fileTypeSubtitles => 'Subtítulos';

  @override
  String get fileTypeAudioFiles => 'Archivos de audio';

  @override
  String seekBackSeconds(int seconds) {
    return 'Retroceder $seconds segundos';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Adelantar $seconds segundos';
  }

  @override
  String get cancelCanvasEditing => 'Cancelar edición del lienzo';

  @override
  String get resetCanvas => 'Restablecer lienzo';

  @override
  String get subtitleControls => 'Controles de subtítulos';

  @override
  String get loopSetA => 'Establecer punto A';

  @override
  String get loopSetB => 'Establecer punto B';

  @override
  String get loopClear => 'Borrar bucle A–B';

  @override
  String get tuningMenuItem => 'Ajustes de vídeo y audio…';

  @override
  String get tuningDialogTitle => 'Vídeo y audio';

  @override
  String get closeTooltip => 'Cerrar';

  @override
  String get videoPresetLabel => 'Preajuste de vídeo';

  @override
  String get presetNatural => 'Natural';

  @override
  String get presetCinema => 'Cine';

  @override
  String get presetVivid => 'Vivo';

  @override
  String get gpuScalingLabel => 'Escalado de GPU';

  @override
  String get presetLowPower => 'Bajo consumo';

  @override
  String get presetBalanced => 'Equilibrado';

  @override
  String get presetQuality => 'Calidad';

  @override
  String get audioPresetLabel => 'Preajuste de audio';

  @override
  String get presetDialogue => 'Diálogo';

  @override
  String get presetNight => 'Noche';

  @override
  String get seekStepLabel => 'Salto de búsqueda';

  @override
  String get periodicInfoLabel => 'Información periódica';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Sincronización de audio';

  @override
  String get audioEarlierTooltip => 'Adelantar audio 0,1 s';

  @override
  String get audioLaterTooltip => 'Retrasar audio 0,1 s';

  @override
  String get decodingLabel => 'Decodificación';

  @override
  String get decodingHardware => 'Hardware';

  @override
  String get decodingSoftware => 'Software';

  @override
  String get dynamicRangeLabel => 'Rango dinámico';

  @override
  String get hdrInfoText =>
      'Solo se pueden seleccionar los formatos que incluye el contenido; los demás están desactivados. Cuando se selecciona SDR, el contenido HDR se mapea tonalmente a bt.709 (BT.2390 + detección de picos). HDR10+ está desactivado porque libmpv no puede detectar sus metadatos dinámicos; Dolby Vision es compatible con los perfiles que incluyen una capa base HDR10.';

  @override
  String get doneLabel => 'Listo';

  @override
  String get videoPreparing => 'Preparando vídeo…';

  @override
  String get dvReshapeApplying =>
      'Aplicando la corrección de color Dolby Vision…';

  @override
  String get dvReshapeActiveHw =>
      'Corrección de color Dolby Vision activa (decodificación por hardware)';

  @override
  String get dvReshapeActiveSw =>
      'Corrección de color Dolby Vision activa (decodificación por software)';

  @override
  String get dvReshapeFailed =>
      'No se pudo iniciar la corrección de color Dolby Vision en este dispositivo. Toca para ver los detalles.';

  @override
  String get dvReshapeFailedShort =>
      'No se pudo iniciar la corrección de color Dolby Vision — detalles en ajustes avanzados.';

  @override
  String get dvReshapeDiagnosticsTitle => 'Diagnóstico de la corrección DV';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'No se capturaron líneas de registro del motor para el filtro.';

  @override
  String get errFormatNotRecognized =>
      'No se pudo reconocer el formato del medio. El NZB puede contener un archivo o datos de recuperación PAR2 en lugar de un vídeo directo.';

  @override
  String get errLocalStreamUnreadable =>
      'No se pudo leer la transmisión de vídeo local. Puede faltar un segmento de Usenet o se interrumpió la conexión.';

  @override
  String get errDecoderFailed =>
      'El decodificador de vídeo o audio no pudo abrir la transmisión.';

  @override
  String get errPlayerGeneric => 'El reproductor no pudo abrir la transmisión.';

  @override
  String get errNoMpvDetail => 'libmpv no dio detalles.';

  @override
  String get errNoEngineDetail => 'El motor de transmisión no dio detalles.';

  @override
  String technicalDetail(String detail) {
    return 'Detalle técnico: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Se alcanzó el límite de conexiones simultáneas del proveedor de Usenet. Cierra otras sesiones activas o espera un momento y vuelve a intentarlo. Si persiste, reduce el número de conexiones en la app al límite de tu plan.';

  @override
  String get errAuthFailed =>
      'Falló la autenticación de Usenet. Comprueba el nombre de usuario y la contraseña en los ajustes del proveedor.';

  @override
  String get errRarEncrypted =>
      'El archivo RAR está cifrado. Las publicaciones RAR protegidas con contraseña no son compatibles; elige una publicación empaquetada sin cifrar (STORE).';

  @override
  String get err7zPassword =>
      'La contraseña del archivo 7z falta o no es válida. Elige el NZB que lleva la contraseña en sus metadatos.';

  @override
  String get errArchiveCompressed =>
      'Este archivo está comprimido. La reproducción instantánea requiere una publicación empaquetada sin compresión (COPY/STORE, 7z/RAR).';

  @override
  String get errArchiveSolid =>
      'Este archivo es sólido. El avance aleatorio requiere una publicación empaquetada como STORE no sólido.';

  @override
  String get errRar4 =>
      'Este archivo RAR usa el formato antiguo RAR4 (o anterior). Solo se pueden reproducir publicaciones RAR5 STORE.';

  @override
  String get errSplitArchiveBroken =>
      'El archivo multiparte (7z/RAR) está incompleto o dañado. Elige un NZB completo que incluya todos los volúmenes y segmentos.';

  @override
  String get errMissingSegments =>
      'El NZB está incompleto o dañado: no se encuentran todos los segmentos de Usenet necesarios. Elige otro NZB completo para esta publicación.';

  @override
  String get errConnectionFailed =>
      'No se pudo conectar con el proveedor de Usenet. Comprueba tu conexión a internet, la dirección del servidor, el puerto y la accesibilidad del proveedor.';

  @override
  String get errNzbUnreadable =>
      'No se pudo leer el archivo NZB o está dañado. Elige un archivo NZB válido y completo.';

  @override
  String get errArchiveNotPlayable =>
      'El archivo (7z/RAR) dentro del NZB no es reproducible o su estructura está dañada. Elige una publicación STORE completa.';

  @override
  String get errNoPlayableMedia =>
      'No se encontró ninguna transmisión de vídeo compatible en el NZB. Elige una publicación con medios directos o un archivo STORE compatible.';

  @override
  String get errStreamStartupGeneric =>
      'No se pudo iniciar la transmisión. Comprueba el contenido del NZB y la conexión del proveedor.';
}
