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
}
