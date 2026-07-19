// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get appSectionTitle => 'Application';

  @override
  String get appSectionSubtitle =>
      'Les préférences de langue et d\'apparence sont enregistrées sur cet appareil.';

  @override
  String get languageLabel => 'Langue';

  @override
  String get themeLabel => 'Apparence';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeLight => 'Clair';

  @override
  String get advancedSettings => 'Paramètres avancés';

  @override
  String get play => 'Lecture';

  @override
  String get pause => 'Pause';

  @override
  String get selectNzbAndPlay => 'Sélectionner un NZB et lire';

  @override
  String get selectNzbHint =>
      'Ouvrir un fichier .nzb depuis le système de fichiers';

  @override
  String get engineStarting => 'Préparation du moteur de lecture local…';

  @override
  String get engineStartFailed =>
      'Impossible de démarrer le moteur de lecture local';

  @override
  String get engineStartFailedHint =>
      'Vérifiez les fichiers du moteur et l\'installation de l\'application, puis réessayez.';

  @override
  String get retry => 'Réessayer';

  @override
  String errorOpenNzb(String error) {
    return 'Impossible d\'ouvrir le fichier NZB : $error';
  }

  @override
  String get providerSettingsTooltip => 'Paramètres du fournisseur';

  @override
  String get backTooltip => 'Retour';

  @override
  String get providerTitle => 'Fournisseur';

  @override
  String get nntpSectionTitle => 'Connexion NNTP';

  @override
  String get nntpSectionSubtitle =>
      'Les informations sont stockées uniquement dans le trousseau sécurisé de cet appareil.';

  @override
  String get serverAddressLabel => 'Adresse du serveur';

  @override
  String get portLabel => 'Port';

  @override
  String get connectionLimitLabel => 'Limite de connexions';

  @override
  String get connectionLimitHint => 'Limite du forfait';

  @override
  String get usernameLabel => 'Nom d\'utilisateur';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get passwordShowTooltip => 'Afficher le mot de passe';

  @override
  String get passwordHideTooltip => 'Masquer le mot de passe';

  @override
  String get saveSecurelyLabel => 'Enregistrer en toute sécurité';

  @override
  String get savingLabel => 'Enregistrement…';

  @override
  String get settingsSaved =>
      'Paramètres enregistrés dans le stockage sécurisé.';

  @override
  String settingsSaveFailed(String error) {
    return 'Impossible d\'enregistrer : $error';
  }

  @override
  String get secureStorageUnavailable =>
      'Impossible d\'accéder au stockage sécurisé';

  @override
  String get connectionLimitWarning =>
      'Définir une limite de connexions supérieure à celle du forfait de votre fournisseur peut provoquer une erreur « trop de connexions ».';

  @override
  String validationRequired(String field) {
    return '$field est obligatoire';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field doit être compris entre $min et $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Saisissez uniquement le nom du serveur, sans protocole ni port';

  @override
  String get validationHostInvalid => 'Saisissez un nom de serveur valide';

  @override
  String get closePlayer => 'Fermer le lecteur';

  @override
  String get fullscreen => 'Plein écran';

  @override
  String get subtitleControlsTooltip => 'Contrôles des sous-titres à l\'écran';

  @override
  String get miniPlayer => 'Mini-lecteur';

  @override
  String get exitMiniPlayer => 'Quitter le mini-lecteur';

  @override
  String get previousFrame => 'Image précédente';

  @override
  String get nextFrame => 'Image suivante';

  @override
  String get playbackSpeedTooltip => 'Vitesse de lecture';

  @override
  String get audioTrack => 'Piste audio';

  @override
  String get subtitleTrack => 'Piste de sous-titres';

  @override
  String get muteTooltip => 'Couper le son';

  @override
  String get unmuteTooltip => 'Rétablir le son';

  @override
  String get loadFromFile => 'Charger depuis un fichier…';

  @override
  String get auto => 'Auto';

  @override
  String get off => 'Désactivé';

  @override
  String get subtitleDecreaseTooltip => 'Réduire la taille des sous-titres';

  @override
  String get subtitleIncreaseTooltip => 'Augmenter la taille des sous-titres';

  @override
  String get subtitleMoveUpTooltip => 'Déplacer les sous-titres vers le haut';

  @override
  String get subtitleMoveDownTooltip => 'Déplacer les sous-titres vers le bas';

  @override
  String get subtitleEarlierTooltip => 'Avancer les sous-titres de 0,1 seconde';

  @override
  String get subtitleLaterTooltip => 'Retarder les sous-titres de 0,1 seconde';

  @override
  String get closeSubtitleControlsTooltip =>
      'Fermer les contrôles des sous-titres';

  @override
  String get smartCanvasAreaLabel => 'Zone de recadrage Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'Double-cliquez pour appliquer. Appuyez sur Échap pour annuler.';

  @override
  String get smartCanvasHintText => 'Double-clic : appliquer · Échap : annuler';

  @override
  String get cropHandleTopLeft => 'Poignée de recadrage en haut à gauche';

  @override
  String get cropHandleTopRight => 'Poignée de recadrage en haut à droite';

  @override
  String get cropHandleBottomLeft => 'Poignée de recadrage en bas à gauche';

  @override
  String get cropHandleBottomRight => 'Poignée de recadrage en bas à droite';

  @override
  String get statusPreparing => 'Préparation…';

  @override
  String get engineBadgePreparing => 'Préparation de libmpv natif…';

  @override
  String get errorProviderSettingsMissing =>
      'Les paramètres du fournisseur sont incomplets. Saisissez d\'abord vos informations dans l\'écran des paramètres.';

  @override
  String get statusConnecting =>
      'Connexion et récupération du premier segment (apprentissage de la structure)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Lecture de la structure de la vidéo : $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'Mise en mémoire tampon : $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Lecture : $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'En attente des pistes vidéo : $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent %';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Démarrage de la vidéo$progress : $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Le flux Usenet n\'a pas pu démarrer dans un délai de $seconds secondes. La connexion au fournisseur, le premier segment ou le contenu du NZB ne répond peut-être pas.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'La vidéo n\'a pas pu être reconnue dans un délai de $seconds secondes. Le NZB contient peut-être une archive en plusieurs parties/PAR2 au lieu d\'une vidéo directe, un segment est peut-être manquant ou le flux est illisible.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'cache disque désactivé';

  @override
  String get engineBadgeSdrSafePath => 'chemin sécurisé SDR';

  @override
  String errorControlFailed(String error) {
    return 'Impossible d\'appliquer le contrôle : $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Impossible d\'appliquer le zoom : $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture n\'est pas disponible sur cette plateforme.';

  @override
  String get fileTypeSubtitles => 'Sous-titres';

  @override
  String get fileTypeAudioFiles => 'Fichiers audio';

  @override
  String seekBackSeconds(int seconds) {
    return 'Reculer de $seconds secondes';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Avancer de $seconds secondes';
  }

  @override
  String get cancelCanvasEditing => 'Annuler la modification du canvas';

  @override
  String get resetCanvas => 'Réinitialiser le canvas';

  @override
  String get subtitleControls => 'Contrôles des sous-titres';

  @override
  String get loopSetA => 'Définir le point A';

  @override
  String get loopSetB => 'Définir le point B';

  @override
  String get loopClear => 'Effacer la boucle A–B';

  @override
  String get tuningMenuItem => 'Réglages vidéo et audio…';

  @override
  String get tuningDialogTitle => 'Vidéo et audio';

  @override
  String get closeTooltip => 'Fermer';

  @override
  String get videoPresetLabel => 'Préréglage vidéo';

  @override
  String get presetNatural => 'Naturel';

  @override
  String get presetCinema => 'Cinéma';

  @override
  String get presetVivid => 'Vif';

  @override
  String get gpuScalingLabel => 'Mise à l\'échelle GPU';

  @override
  String get presetLowPower => 'Économie d\'énergie';

  @override
  String get presetBalanced => 'Équilibré';

  @override
  String get presetQuality => 'Qualité';

  @override
  String get audioPresetLabel => 'Préréglage audio';

  @override
  String get presetDialogue => 'Dialogue';

  @override
  String get presetNight => 'Nuit';

  @override
  String get seekStepLabel => 'Pas de recherche';

  @override
  String get periodicInfoLabel => 'Infos périodiques';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Synchronisation audio';

  @override
  String get audioEarlierTooltip => 'Avancer l\'audio de 0,1 s';

  @override
  String get audioLaterTooltip => 'Retarder l\'audio de 0,1 s';

  @override
  String get decodingLabel => 'Décodage';

  @override
  String get decodingHardware => 'Matériel';

  @override
  String get decodingSoftware => 'Logiciel';

  @override
  String get dynamicRangeLabel => 'Plage dynamique';

  @override
  String get hdrInfoText =>
      'Seuls les formats transportés par le contenu peuvent être sélectionnés ; les autres sont désactivés. Lorsque SDR est sélectionné, le contenu HDR est converti en bt.709 par mappage de tons (BT.2390 + détection des pics). HDR10+ est désactivé car libmpv ne peut pas détecter ses métadonnées dynamiques ; Dolby Vision est pris en charge sur les profils incluant une couche de base HDR10.';

  @override
  String get doneLabel => 'Terminé';

  @override
  String get videoPreparing => 'Préparation de la vidéo…';
}
