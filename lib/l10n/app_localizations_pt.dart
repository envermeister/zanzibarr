// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get appSectionTitle => 'Aplicativo';

  @override
  String get appSectionSubtitle =>
      'As preferências de idioma e aparência são armazenadas neste dispositivo.';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get themeLabel => 'Aparência';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeLight => 'Claro';

  @override
  String get advancedSettings => 'Configurações avançadas';

  @override
  String get play => 'Reproduzir';

  @override
  String get pause => 'Pausar';

  @override
  String get selectNzbAndPlay => 'Selecionar NZB e reproduzir';

  @override
  String get selectNzbHint => 'Abrir um .nzb do sistema de arquivos';

  @override
  String get engineStarting => 'Preparando o mecanismo de reprodução local…';

  @override
  String get engineStartFailed =>
      'Não foi possível iniciar o mecanismo de reprodução local';

  @override
  String get engineStartFailedHint =>
      'Verifique os arquivos do mecanismo e a instalação do aplicativo e tente novamente.';

  @override
  String get retry => 'Tentar novamente';

  @override
  String errorOpenNzb(String error) {
    return 'Não foi possível abrir o arquivo NZB: $error';
  }

  @override
  String get providerSettingsTooltip => 'Configurações do provedor';

  @override
  String get backTooltip => 'Voltar';

  @override
  String get providerTitle => 'Provedor';

  @override
  String get nntpSectionTitle => 'Conexão NNTP';

  @override
  String get nntpSectionSubtitle =>
      'Os dados são armazenados apenas no chaveiro seguro deste dispositivo.';

  @override
  String get serverAddressLabel => 'Endereço do servidor';

  @override
  String get portLabel => 'Porta';

  @override
  String get connectionLimitLabel => 'Limite de conexões';

  @override
  String get connectionLimitHint => 'Limite do plano';

  @override
  String get usernameLabel => 'Nome de usuário';

  @override
  String get passwordLabel => 'Senha';

  @override
  String get passwordShowTooltip => 'Mostrar senha';

  @override
  String get passwordHideTooltip => 'Ocultar senha';

  @override
  String get saveSecurelyLabel => 'Salvar com segurança';

  @override
  String get savingLabel => 'Salvando…';

  @override
  String get settingsSaved => 'Configurações salvas no armazenamento seguro.';

  @override
  String settingsSaveFailed(String error) {
    return 'Não foi possível salvar: $error';
  }

  @override
  String get secureStorageUnavailable =>
      'Não foi possível acessar o armazenamento seguro';

  @override
  String get connectionLimitWarning =>
      'Definir o limite de conexões acima do plano do seu provedor pode causar um erro de “conexões em excesso”.';

  @override
  String validationRequired(String field) {
    return '$field é obrigatório';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field deve estar entre $min e $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Digite apenas o nome do servidor, sem protocolo nem porta';

  @override
  String get validationHostInvalid => 'Digite um nome de servidor válido';

  @override
  String get closePlayer => 'Fechar player';

  @override
  String get fullscreen => 'Tela cheia';

  @override
  String get subtitleControlsTooltip => 'Controles de legenda na tela';

  @override
  String get miniPlayer => 'Miniplayer';

  @override
  String get exitMiniPlayer => 'Sair do miniplayer';

  @override
  String get previousFrame => 'Quadro anterior';

  @override
  String get nextFrame => 'Próximo quadro';

  @override
  String get playbackSpeedTooltip => 'Velocidade de reprodução';

  @override
  String get audioTrack => 'Faixa de áudio';

  @override
  String get subtitleTrack => 'Faixa de legenda';

  @override
  String get muteTooltip => 'Silenciar';

  @override
  String get unmuteTooltip => 'Ativar som';

  @override
  String get loadFromFile => 'Carregar de arquivo…';

  @override
  String get auto => 'Automático';

  @override
  String get off => 'Desativado';

  @override
  String get subtitleDecreaseTooltip => 'Diminuir tamanho da legenda';

  @override
  String get subtitleIncreaseTooltip => 'Aumentar tamanho da legenda';

  @override
  String get subtitleMoveUpTooltip => 'Mover legenda para cima';

  @override
  String get subtitleMoveDownTooltip => 'Mover legenda para baixo';

  @override
  String get subtitleEarlierTooltip => 'Adiantar legenda em 0,1 segundos';

  @override
  String get subtitleLaterTooltip => 'Atrasar legenda em 0,1 segundos';

  @override
  String get closeSubtitleControlsTooltip => 'Fechar controles de legenda';

  @override
  String get smartCanvasAreaLabel => 'Área de corte do Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'Toque duas vezes para aplicar. Pressione Esc para cancelar.';

  @override
  String get smartCanvasHintText => 'Toque duplo: aplicar · Esc: cancelar';

  @override
  String get cropHandleTopLeft => 'Alça de corte superior esquerda';

  @override
  String get cropHandleTopRight => 'Alça de corte superior direita';

  @override
  String get cropHandleBottomLeft => 'Alça de corte inferior esquerda';

  @override
  String get cropHandleBottomRight => 'Alça de corte inferior direita';

  @override
  String get statusPreparing => 'Preparando…';

  @override
  String get engineBadgePreparing => 'Preparando libmpv nativo…';

  @override
  String get errorProviderSettingsMissing =>
      'As configurações do provedor estão incompletas. Insira seus dados primeiro na tela de configurações.';

  @override
  String get statusConnecting =>
      'Conectando e buscando o primeiro segmento (aprendendo o layout)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Lendo a estrutura do vídeo: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'Armazenando em buffer: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Reproduzindo: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Aguardando as faixas de vídeo: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Iniciando o vídeo$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'O stream do Usenet não pôde ser iniciado em $seconds segundos. A conexão com o provedor, o primeiro segmento ou o conteúdo do NZB pode não estar respondendo.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'O vídeo não pôde ser reconhecido em $seconds segundos. O NZB pode conter um arquivo/PAR2 multipartes em vez de um vídeo direto, um segmento pode estar faltando ou o stream pode estar ilegível.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'cache de disco desativado';

  @override
  String get engineBadgeSdrSafePath => 'caminho seguro SDR';

  @override
  String errorControlFailed(String error) {
    return 'Não foi possível aplicar o controle: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Não foi possível aplicar o zoom: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture não está disponível nesta plataforma.';

  @override
  String get fileTypeSubtitles => 'Legendas';

  @override
  String get fileTypeAudioFiles => 'Arquivos de áudio';

  @override
  String seekBackSeconds(int seconds) {
    return 'Voltar $seconds segundos';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Avançar $seconds segundos';
  }

  @override
  String get cancelCanvasEditing => 'Cancelar edição do canvas';

  @override
  String get resetCanvas => 'Redefinir canvas';

  @override
  String get subtitleControls => 'Controles de legenda';

  @override
  String get loopSetA => 'Definir ponto A';

  @override
  String get loopSetB => 'Definir ponto B';

  @override
  String get loopClear => 'Limpar loop A–B';

  @override
  String get tuningMenuItem => 'Configurações de vídeo e áudio…';

  @override
  String get tuningDialogTitle => 'Vídeo e áudio';

  @override
  String get closeTooltip => 'Fechar';

  @override
  String get videoPresetLabel => 'Predefinição de vídeo';

  @override
  String get presetNatural => 'Natural';

  @override
  String get presetCinema => 'Cinema';

  @override
  String get presetVivid => 'Vívido';

  @override
  String get gpuScalingLabel => 'Escalonamento de GPU';

  @override
  String get presetLowPower => 'Baixo consumo';

  @override
  String get presetBalanced => 'Equilibrado';

  @override
  String get presetQuality => 'Qualidade';

  @override
  String get audioPresetLabel => 'Predefinição de áudio';

  @override
  String get presetDialogue => 'Diálogo';

  @override
  String get presetNight => 'Noite';

  @override
  String get seekStepLabel => 'Passo de busca';

  @override
  String get periodicInfoLabel => 'Informações periódicas';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Sincronização de áudio';

  @override
  String get audioEarlierTooltip => 'Adiantar áudio em 0,1 s';

  @override
  String get audioLaterTooltip => 'Atrasar áudio em 0,1 s';

  @override
  String get decodingLabel => 'Decodificação';

  @override
  String get decodingHardware => 'Hardware';

  @override
  String get decodingSoftware => 'Software';

  @override
  String get dynamicRangeLabel => 'Faixa dinâmica';

  @override
  String get hdrInfoText =>
      'Somente os formatos presentes no conteúdo podem ser selecionados; os demais ficam desativados. Quando SDR está selecionado, o conteúdo HDR é mapeado em tom para bt.709 (BT.2390 + peak detect). HDR10+ está desativado porque o libmpv não consegue detectar seus metadados dinâmicos; Dolby Vision é suportado em perfis que incluem uma camada base HDR10.';

  @override
  String get doneLabel => 'Concluído';

  @override
  String get videoPreparing => 'Preparando o vídeo…';
}
