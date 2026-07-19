import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fr'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Zanzibarr'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get appSectionTitle;

  /// No description provided for @appSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language and appearance preferences are stored on this device.'**
  String get appSectionSubtitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeLabel;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @advancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get advancedSettings;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @selectNzbAndPlay.
  ///
  /// In en, this message translates to:
  /// **'Select NZB and play'**
  String get selectNzbAndPlay;

  /// No description provided for @selectNzbHint.
  ///
  /// In en, this message translates to:
  /// **'Open a .nzb from the file system'**
  String get selectNzbHint;

  /// No description provided for @engineStarting.
  ///
  /// In en, this message translates to:
  /// **'Preparing the local playback engine…'**
  String get engineStarting;

  /// No description provided for @engineStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The local playback engine could not be started'**
  String get engineStartFailed;

  /// No description provided for @engineStartFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Check the engine files and the app installation, then try again.'**
  String get engineStartFailedHint;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @errorOpenNzb.
  ///
  /// In en, this message translates to:
  /// **'Could not open the NZB file: {error}'**
  String errorOpenNzb(String error);

  /// No description provided for @providerSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Provider settings'**
  String get providerSettingsTooltip;

  /// No description provided for @backTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backTooltip;

  /// No description provided for @providerTitle.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerTitle;

  /// No description provided for @nntpSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'NNTP connection'**
  String get nntpSectionTitle;

  /// No description provided for @nntpSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Details are stored only in this device\'s secure keychain.'**
  String get nntpSectionSubtitle;

  /// No description provided for @serverAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddressLabel;

  /// No description provided for @portLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// No description provided for @connectionLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection limit'**
  String get connectionLimitLabel;

  /// No description provided for @connectionLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Plan limit'**
  String get connectionLimitHint;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordShowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get passwordShowTooltip;

  /// No description provided for @passwordHideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get passwordHideTooltip;

  /// No description provided for @saveSecurelyLabel.
  ///
  /// In en, this message translates to:
  /// **'Save securely'**
  String get saveSecurelyLabel;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingLabel;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved to secure storage.'**
  String get settingsSaved;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String settingsSaveFailed(String error);

  /// No description provided for @secureStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure storage could not be accessed'**
  String get secureStorageUnavailable;

  /// No description provided for @connectionLimitWarning.
  ///
  /// In en, this message translates to:
  /// **'Setting the connection limit above your provider\'s plan may cause a “too many connections” error.'**
  String get connectionLimitWarning;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String validationRequired(String field);

  /// No description provided for @validationIntegerRange.
  ///
  /// In en, this message translates to:
  /// **'{field} must be between {min} and {max}'**
  String validationIntegerRange(String field, int min, int max);

  /// No description provided for @validationHostNoProtocol.
  ///
  /// In en, this message translates to:
  /// **'Enter only the server name, without protocol or port'**
  String get validationHostNoProtocol;

  /// No description provided for @validationHostInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid server name'**
  String get validationHostInvalid;

  /// No description provided for @closePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get closePlayer;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// No description provided for @subtitleControlsTooltip.
  ///
  /// In en, this message translates to:
  /// **'On-screen subtitle controls'**
  String get subtitleControlsTooltip;

  /// No description provided for @miniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get miniPlayer;

  /// No description provided for @exitMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Exit mini player'**
  String get exitMiniPlayer;

  /// No description provided for @previousFrame.
  ///
  /// In en, this message translates to:
  /// **'Previous frame'**
  String get previousFrame;

  /// No description provided for @nextFrame.
  ///
  /// In en, this message translates to:
  /// **'Next frame'**
  String get nextFrame;

  /// No description provided for @playbackSpeedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeedTooltip;

  /// No description provided for @audioTrack.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get audioTrack;

  /// No description provided for @subtitleTrack.
  ///
  /// In en, this message translates to:
  /// **'Subtitle track'**
  String get subtitleTrack;

  /// No description provided for @muteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteTooltip;

  /// No description provided for @unmuteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmuteTooltip;

  /// No description provided for @loadFromFile.
  ///
  /// In en, this message translates to:
  /// **'Load from file…'**
  String get loadFromFile;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @subtitleDecreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease subtitle size'**
  String get subtitleDecreaseTooltip;

  /// No description provided for @subtitleIncreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase subtitle size'**
  String get subtitleIncreaseTooltip;

  /// No description provided for @subtitleMoveUpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move subtitle up'**
  String get subtitleMoveUpTooltip;

  /// No description provided for @subtitleMoveDownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move subtitle down'**
  String get subtitleMoveDownTooltip;

  /// No description provided for @subtitleEarlierTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move subtitle 0.1 seconds earlier'**
  String get subtitleEarlierTooltip;

  /// No description provided for @subtitleLaterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delay subtitle by 0.1 seconds'**
  String get subtitleLaterTooltip;

  /// No description provided for @closeSubtitleControlsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close subtitle controls'**
  String get closeSubtitleControlsTooltip;

  /// No description provided for @smartCanvasAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Smart Canvas crop area'**
  String get smartCanvasAreaLabel;

  /// No description provided for @smartCanvasSemanticsHint.
  ///
  /// In en, this message translates to:
  /// **'Double-tap to apply. Press Escape to cancel.'**
  String get smartCanvasSemanticsHint;

  /// No description provided for @smartCanvasHintText.
  ///
  /// In en, this message translates to:
  /// **'Double-tap: apply · Esc: cancel'**
  String get smartCanvasHintText;

  /// No description provided for @cropHandleTopLeft.
  ///
  /// In en, this message translates to:
  /// **'Top-left crop handle'**
  String get cropHandleTopLeft;

  /// No description provided for @cropHandleTopRight.
  ///
  /// In en, this message translates to:
  /// **'Top-right crop handle'**
  String get cropHandleTopRight;

  /// No description provided for @cropHandleBottomLeft.
  ///
  /// In en, this message translates to:
  /// **'Bottom-left crop handle'**
  String get cropHandleBottomLeft;

  /// No description provided for @cropHandleBottomRight.
  ///
  /// In en, this message translates to:
  /// **'Bottom-right crop handle'**
  String get cropHandleBottomRight;

  /// No description provided for @statusPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get statusPreparing;

  /// No description provided for @engineBadgePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing native libmpv…'**
  String get engineBadgePreparing;

  /// No description provided for @errorProviderSettingsMissing.
  ///
  /// In en, this message translates to:
  /// **'Provider settings are incomplete. Enter your details on the settings screen first.'**
  String get errorProviderSettingsMissing;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting and fetching the first segment (learning layout)…'**
  String get statusConnecting;

  /// No description provided for @statusReadingVideoStructure.
  ///
  /// In en, this message translates to:
  /// **'Reading video structure: {filename}'**
  String statusReadingVideoStructure(String filename);

  /// No description provided for @statusBuffering.
  ///
  /// In en, this message translates to:
  /// **'Buffering: {filename}'**
  String statusBuffering(String filename);

  /// No description provided for @statusPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing: {filename}'**
  String statusPlaying(String filename);

  /// No description provided for @statusWaitingTracks.
  ///
  /// In en, this message translates to:
  /// **'Waiting for video tracks: {filename}'**
  String statusWaitingTracks(String filename);

  /// No description provided for @bufferingPercent.
  ///
  /// In en, this message translates to:
  /// **' {percent}%'**
  String bufferingPercent(String percent);

  /// No description provided for @statusStartingVideo.
  ///
  /// In en, this message translates to:
  /// **'Starting video{progress}: {filename}'**
  String statusStartingVideo(String progress, String filename);

  /// No description provided for @errorStreamStartTimeout.
  ///
  /// In en, this message translates to:
  /// **'The Usenet stream could not start within {seconds} seconds. The provider connection, the first segment, or the NZB content may not be responding.'**
  String errorStreamStartTimeout(int seconds);

  /// No description provided for @errorVideoDetectTimeout.
  ///
  /// In en, this message translates to:
  /// **'The video could not be recognized within {seconds} seconds. The NZB may contain a multi-part archive/PAR2 instead of a direct video, a segment may be missing, or the stream may be unreadable.'**
  String errorVideoDetectTimeout(int seconds);

  /// No description provided for @engineBadgeDiskCacheOff.
  ///
  /// In en, this message translates to:
  /// **'disk cache off'**
  String get engineBadgeDiskCacheOff;

  /// No description provided for @engineBadgeSdrSafePath.
  ///
  /// In en, this message translates to:
  /// **'SDR safe path'**
  String get engineBadgeSdrSafePath;

  /// No description provided for @errorControlFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply the control: {error}'**
  String errorControlFailed(String error);

  /// No description provided for @errorZoomFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply zoom: {error}'**
  String errorZoomFailed(String error);

  /// No description provided for @errorPipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-Picture is not available on this platform.'**
  String get errorPipUnavailable;

  /// No description provided for @fileTypeSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get fileTypeSubtitles;

  /// No description provided for @fileTypeAudioFiles.
  ///
  /// In en, this message translates to:
  /// **'Audio files'**
  String get fileTypeAudioFiles;

  /// No description provided for @seekBackSeconds.
  ///
  /// In en, this message translates to:
  /// **'Back {seconds} seconds'**
  String seekBackSeconds(int seconds);

  /// No description provided for @seekForwardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Forward {seconds} seconds'**
  String seekForwardSeconds(int seconds);

  /// No description provided for @cancelCanvasEditing.
  ///
  /// In en, this message translates to:
  /// **'Cancel canvas editing'**
  String get cancelCanvasEditing;

  /// No description provided for @resetCanvas.
  ///
  /// In en, this message translates to:
  /// **'Reset canvas'**
  String get resetCanvas;

  /// No description provided for @subtitleControls.
  ///
  /// In en, this message translates to:
  /// **'Subtitle controls'**
  String get subtitleControls;

  /// No description provided for @loopSetA.
  ///
  /// In en, this message translates to:
  /// **'Set point A'**
  String get loopSetA;

  /// No description provided for @loopSetB.
  ///
  /// In en, this message translates to:
  /// **'Set point B'**
  String get loopSetB;

  /// No description provided for @loopClear.
  ///
  /// In en, this message translates to:
  /// **'Clear A–B loop'**
  String get loopClear;

  /// No description provided for @tuningMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Video and audio settings…'**
  String get tuningMenuItem;

  /// No description provided for @tuningDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Video and audio'**
  String get tuningDialogTitle;

  /// No description provided for @closeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTooltip;

  /// No description provided for @videoPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Video preset'**
  String get videoPresetLabel;

  /// No description provided for @presetNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get presetNatural;

  /// No description provided for @presetCinema.
  ///
  /// In en, this message translates to:
  /// **'Cinema'**
  String get presetCinema;

  /// No description provided for @presetVivid.
  ///
  /// In en, this message translates to:
  /// **'Vivid'**
  String get presetVivid;

  /// No description provided for @gpuScalingLabel.
  ///
  /// In en, this message translates to:
  /// **'GPU scaling'**
  String get gpuScalingLabel;

  /// No description provided for @presetLowPower.
  ///
  /// In en, this message translates to:
  /// **'Low power'**
  String get presetLowPower;

  /// No description provided for @presetBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get presetBalanced;

  /// No description provided for @presetQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get presetQuality;

  /// No description provided for @audioPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio preset'**
  String get audioPresetLabel;

  /// No description provided for @presetDialogue.
  ///
  /// In en, this message translates to:
  /// **'Dialogue'**
  String get presetDialogue;

  /// No description provided for @presetNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get presetNight;

  /// No description provided for @seekStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Seek step'**
  String get seekStepLabel;

  /// No description provided for @periodicInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Periodic info'**
  String get periodicInfoLabel;

  /// No description provided for @secondsUnitShort.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get secondsUnitShort;

  /// No description provided for @audioSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio sync'**
  String get audioSyncLabel;

  /// No description provided for @audioEarlierTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move audio 0.1 s earlier'**
  String get audioEarlierTooltip;

  /// No description provided for @audioLaterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delay audio by 0.1 s'**
  String get audioLaterTooltip;

  /// No description provided for @decodingLabel.
  ///
  /// In en, this message translates to:
  /// **'Decoding'**
  String get decodingLabel;

  /// No description provided for @decodingHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get decodingHardware;

  /// No description provided for @decodingSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get decodingSoftware;

  /// No description provided for @dynamicRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Dynamic range'**
  String get dynamicRangeLabel;

  /// No description provided for @hdrInfoText.
  ///
  /// In en, this message translates to:
  /// **'Only the formats carried by the content can be selected; the others are disabled. When SDR is selected, HDR content is tone-mapped to bt.709 (BT.2390 + peak detect). HDR10+ is disabled because libmpv cannot detect its dynamic metadata; Dolby Vision is supported on profiles that include an HDR10 base layer.'**
  String get hdrInfoText;

  /// No description provided for @doneLabel.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneLabel;

  /// No description provided for @videoPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing video…'**
  String get videoPreparing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fa',
    'fr',
    'hi',
    'it',
    'ja',
    'ko',
    'pt',
    'ru',
    'tr',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fa':
      return AppLocalizationsFa();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
