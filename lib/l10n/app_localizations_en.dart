// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appSectionTitle => 'Application';

  @override
  String get appSectionSubtitle =>
      'Language and appearance preferences are stored on this device.';

  @override
  String get languageLabel => 'Language';

  @override
  String get themeLabel => 'Appearance';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get advancedSettings => 'Advanced settings';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get selectNzbAndPlay => 'Select NZB and play';

  @override
  String get selectNzbHint => 'Open a .nzb from the file system';

  @override
  String get engineStarting => 'Preparing the local playback engine…';

  @override
  String get engineStartFailed =>
      'The local playback engine could not be started';

  @override
  String get engineStartFailedHint =>
      'Check the engine files and the app installation, then try again.';

  @override
  String get retry => 'Try again';

  @override
  String errorOpenNzb(String error) {
    return 'Could not open the NZB file: $error';
  }

  @override
  String get providerSettingsTooltip => 'Provider settings';

  @override
  String get backTooltip => 'Back';

  @override
  String get providerTitle => 'Provider';

  @override
  String get nntpSectionTitle => 'NNTP connection';

  @override
  String get nntpSectionSubtitle =>
      'Details are stored only in this device\'s secure keychain.';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get portLabel => 'Port';

  @override
  String get connectionLimitLabel => 'Connection limit';

  @override
  String get connectionLimitHint => 'Plan limit';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordShowTooltip => 'Show password';

  @override
  String get passwordHideTooltip => 'Hide password';

  @override
  String get saveSecurelyLabel => 'Save securely';

  @override
  String get savingLabel => 'Saving…';

  @override
  String get settingsSaved => 'Settings saved to secure storage.';

  @override
  String settingsSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String get secureStorageUnavailable => 'Secure storage could not be accessed';

  @override
  String get connectionLimitWarning =>
      'Setting the connection limit above your provider\'s plan may cause a “too many connections” error.';

  @override
  String validationRequired(String field) {
    return '$field is required';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field must be between $min and $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Enter only the server name, without protocol or port';

  @override
  String get validationHostInvalid => 'Enter a valid server name';

  @override
  String get closePlayer => 'Close player';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get subtitleControlsTooltip => 'On-screen subtitle controls';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get exitMiniPlayer => 'Exit mini player';

  @override
  String get previousFrame => 'Previous frame';

  @override
  String get nextFrame => 'Next frame';

  @override
  String get playbackSpeedTooltip => 'Playback speed';

  @override
  String get audioTrack => 'Audio track';

  @override
  String get subtitleTrack => 'Subtitle track';

  @override
  String get muteTooltip => 'Mute';

  @override
  String get unmuteTooltip => 'Unmute';

  @override
  String get loadFromFile => 'Load from file…';

  @override
  String get auto => 'Auto';

  @override
  String get off => 'Off';

  @override
  String get subtitleDecreaseTooltip => 'Decrease subtitle size';

  @override
  String get subtitleIncreaseTooltip => 'Increase subtitle size';

  @override
  String get subtitleMoveUpTooltip => 'Move subtitle up';

  @override
  String get subtitleMoveDownTooltip => 'Move subtitle down';

  @override
  String get subtitleEarlierTooltip => 'Move subtitle 0.1 seconds earlier';

  @override
  String get subtitleLaterTooltip => 'Delay subtitle by 0.1 seconds';

  @override
  String get closeSubtitleControlsTooltip => 'Close subtitle controls';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas crop area';

  @override
  String get smartCanvasSemanticsHint =>
      'Double-tap to apply. Press Escape to cancel.';

  @override
  String get smartCanvasHintText => 'Double-tap: apply · Esc: cancel';

  @override
  String get cropHandleTopLeft => 'Top-left crop handle';

  @override
  String get cropHandleTopRight => 'Top-right crop handle';

  @override
  String get cropHandleBottomLeft => 'Bottom-left crop handle';

  @override
  String get cropHandleBottomRight => 'Bottom-right crop handle';

  @override
  String get statusPreparing => 'Preparing…';

  @override
  String get engineBadgePreparing => 'Preparing native libmpv…';

  @override
  String get errorProviderSettingsMissing =>
      'Provider settings are incomplete. Enter your details on the settings screen first.';

  @override
  String get statusConnecting =>
      'Connecting and fetching the first segment (learning layout)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Reading video structure: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'Buffering: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Playing: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Waiting for video tracks: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Starting video$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'The Usenet stream could not start within $seconds seconds. The provider connection, the first segment, or the NZB content may not be responding.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'The video could not be recognized within $seconds seconds. The NZB may contain a multi-part archive/PAR2 instead of a direct video, a segment may be missing, or the stream may be unreadable.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'disk cache off';

  @override
  String get engineBadgeSdrSafePath => 'SDR safe path';

  @override
  String errorControlFailed(String error) {
    return 'Could not apply the control: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Could not apply zoom: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture is not available on this platform.';

  @override
  String get fileTypeSubtitles => 'Subtitles';

  @override
  String get fileTypeAudioFiles => 'Audio files';

  @override
  String seekBackSeconds(int seconds) {
    return 'Back $seconds seconds';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Forward $seconds seconds';
  }

  @override
  String get cancelCanvasEditing => 'Cancel canvas editing';

  @override
  String get resetCanvas => 'Reset canvas';

  @override
  String get subtitleControls => 'Subtitle controls';

  @override
  String get loopSetA => 'Set point A';

  @override
  String get loopSetB => 'Set point B';

  @override
  String get loopClear => 'Clear A–B loop';

  @override
  String get tuningMenuItem => 'Video and audio settings…';

  @override
  String get tuningDialogTitle => 'Video and audio';

  @override
  String get closeTooltip => 'Close';

  @override
  String get videoPresetLabel => 'Video preset';

  @override
  String get presetNatural => 'Natural';

  @override
  String get presetCinema => 'Cinema';

  @override
  String get presetVivid => 'Vivid';

  @override
  String get gpuScalingLabel => 'GPU scaling';

  @override
  String get presetLowPower => 'Low power';

  @override
  String get presetBalanced => 'Balanced';

  @override
  String get presetQuality => 'Quality';

  @override
  String get audioPresetLabel => 'Audio preset';

  @override
  String get presetDialogue => 'Dialogue';

  @override
  String get presetNight => 'Night';

  @override
  String get seekStepLabel => 'Seek step';

  @override
  String get periodicInfoLabel => 'Periodic info';

  @override
  String get secondsUnitShort => 's';

  @override
  String get audioSyncLabel => 'Audio sync';

  @override
  String get audioEarlierTooltip => 'Move audio 0.1 s earlier';

  @override
  String get audioLaterTooltip => 'Delay audio by 0.1 s';

  @override
  String get decodingLabel => 'Decoding';

  @override
  String get decodingHardware => 'Hardware';

  @override
  String get decodingSoftware => 'Software';

  @override
  String get dynamicRangeLabel => 'Dynamic range';

  @override
  String get hdrInfoText =>
      'Only the formats carried by the content can be selected; the others are disabled. When SDR is selected, HDR content is tone-mapped to bt.709 (BT.2390 + peak detect). HDR10+ is disabled because libmpv cannot detect its dynamic metadata; Dolby Vision is supported on profiles that include an HDR10 base layer.';

  @override
  String get doneLabel => 'Done';

  @override
  String get videoPreparing => 'Preparing video…';
}
