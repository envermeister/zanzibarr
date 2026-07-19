// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get appSectionTitle => 'ऐप्लिकेशन';

  @override
  String get appSectionSubtitle =>
      'भाषा और रूप-रंग की प्राथमिकताएँ इस डिवाइस पर सहेजी जाती हैं।';

  @override
  String get languageLabel => 'भाषा';

  @override
  String get themeLabel => 'थीम';

  @override
  String get themeDark => 'डार्क';

  @override
  String get themeLight => 'लाइट';

  @override
  String get advancedSettings => 'उन्नत सेटिंग्स';

  @override
  String get play => 'चलाएँ';

  @override
  String get pause => 'रोकें';

  @override
  String get selectNzbAndPlay => 'NZB चुनें और चलाएँ';

  @override
  String get selectNzbHint => 'फ़ाइल सिस्टम से .nzb खोलें';

  @override
  String get engineStarting => 'लोकल प्लेबैक इंजन तैयार हो रहा है…';

  @override
  String get engineStartFailed => 'लोकल प्लेबैक इंजन शुरू नहीं हो सका';

  @override
  String get engineStartFailedHint =>
      'इंजन फ़ाइलें और ऐप इंस्टॉलेशन जाँचें, फिर दोबारा कोशिश करें।';

  @override
  String get retry => 'फिर कोशिश करें';

  @override
  String errorOpenNzb(String error) {
    return 'NZB फ़ाइल नहीं खोली जा सकी: $error';
  }

  @override
  String get providerSettingsTooltip => 'प्रोवाइडर सेटिंग्स';

  @override
  String get backTooltip => 'वापस';

  @override
  String get providerTitle => 'प्रोवाइडर';

  @override
  String get nntpSectionTitle => 'NNTP कनेक्शन';

  @override
  String get nntpSectionSubtitle =>
      'विवरण केवल इस डिवाइस के सुरक्षित कीचेन में सहेजे जाते हैं।';

  @override
  String get serverAddressLabel => 'सर्वर का पता';

  @override
  String get portLabel => 'पोर्ट';

  @override
  String get connectionLimitLabel => 'कनेक्शन सीमा';

  @override
  String get connectionLimitHint => 'प्लान सीमा';

  @override
  String get usernameLabel => 'उपयोगकर्ता नाम';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get passwordShowTooltip => 'पासवर्ड दिखाएँ';

  @override
  String get passwordHideTooltip => 'पासवर्ड छिपाएँ';

  @override
  String get saveSecurelyLabel => 'सुरक्षित रूप से सहेजें';

  @override
  String get savingLabel => 'सहेजा जा रहा है…';

  @override
  String get settingsSaved => 'सेटिंग्स सुरक्षित स्टोरेज में सहेजी गईं।';

  @override
  String settingsSaveFailed(String error) {
    return 'सहेजा नहीं जा सका: $error';
  }

  @override
  String get secureStorageUnavailable =>
      'सुरक्षित स्टोरेज तक पहुँचा नहीं जा सका';

  @override
  String get connectionLimitWarning =>
      'कनेक्शन सीमा को प्रोवाइडर के प्लान से अधिक रखने पर “बहुत अधिक कनेक्शन” त्रुटि हो सकती है।';

  @override
  String validationRequired(String field) {
    return '$field आवश्यक है';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field, $min और $max के बीच होना चाहिए';
  }

  @override
  String get validationHostNoProtocol =>
      'केवल सर्वर का नाम दर्ज करें, प्रोटोकॉल या पोर्ट के बिना';

  @override
  String get validationHostInvalid => 'मान्य सर्वर नाम दर्ज करें';

  @override
  String get closePlayer => 'प्लेयर बंद करें';

  @override
  String get fullscreen => 'फ़ुल स्क्रीन';

  @override
  String get subtitleControlsTooltip => 'स्क्रीन पर सबटाइटल नियंत्रण';

  @override
  String get miniPlayer => 'मिनी प्लेयर';

  @override
  String get exitMiniPlayer => 'मिनी प्लेयर से बाहर निकलें';

  @override
  String get previousFrame => 'पिछला फ़्रेम';

  @override
  String get nextFrame => 'अगला फ़्रेम';

  @override
  String get playbackSpeedTooltip => 'प्लेबैक गति';

  @override
  String get audioTrack => 'ऑडियो ट्रैक';

  @override
  String get subtitleTrack => 'सबटाइटल ट्रैक';

  @override
  String get muteTooltip => 'म्यूट';

  @override
  String get unmuteTooltip => 'अनम्यूट';

  @override
  String get loadFromFile => 'फ़ाइल से लोड करें…';

  @override
  String get auto => 'ऑटो';

  @override
  String get off => 'बंद';

  @override
  String get subtitleDecreaseTooltip => 'सबटाइटल आकार घटाएँ';

  @override
  String get subtitleIncreaseTooltip => 'सबटाइटल आकार बढ़ाएँ';

  @override
  String get subtitleMoveUpTooltip => 'सबटाइटल ऊपर ले जाएँ';

  @override
  String get subtitleMoveDownTooltip => 'सबटाइटल नीचे ले जाएँ';

  @override
  String get subtitleEarlierTooltip => 'सबटाइटल को 0.1 सेकंड पहले करें';

  @override
  String get subtitleLaterTooltip => 'सबटाइटल को 0.1 सेकंड देर से करें';

  @override
  String get closeSubtitleControlsTooltip => 'सबटाइटल नियंत्रण बंद करें';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas क्रॉप क्षेत्र';

  @override
  String get smartCanvasSemanticsHint =>
      'लागू करने के लिए डबल-टैप करें। रद्द करने के लिए Escape दबाएँ।';

  @override
  String get smartCanvasHintText => 'डबल-टैप: लागू करें · Esc: रद्द करें';

  @override
  String get cropHandleTopLeft => 'ऊपर-बायाँ क्रॉप हैंडल';

  @override
  String get cropHandleTopRight => 'ऊपर-दायाँ क्रॉप हैंडल';

  @override
  String get cropHandleBottomLeft => 'नीचे-बायाँ क्रॉप हैंडल';

  @override
  String get cropHandleBottomRight => 'नीचे-दायाँ क्रॉप हैंडल';

  @override
  String get statusPreparing => 'तैयार हो रहा है…';

  @override
  String get engineBadgePreparing => 'नेटिव libmpv तैयार हो रहा है…';

  @override
  String get errorProviderSettingsMissing =>
      'प्रोवाइडर सेटिंग्स अधूरी हैं। पहले सेटिंग स्क्रीन पर अपना विवरण दर्ज करें।';

  @override
  String get statusConnecting =>
      'कनेक्ट हो रहा है और पहला सेगमेंट लाया जा रहा है (लेआउट सीखा जा रहा है)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'वीडियो संरचना पढ़ी जा रही है: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'बफ़र हो रहा है: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'चल रहा है: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'वीडियो ट्रैक की प्रतीक्षा: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'वीडियो शुरू हो रहा है$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Usenet स्ट्रीम $seconds सेकंड में शुरू नहीं हो सकी। प्रोवाइडर कनेक्शन, पहला सेगमेंट या NZB सामग्री जवाब नहीं दे रही हो सकती है।';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'वीडियो $seconds सेकंड में पहचाना नहीं जा सका। NZB में सीधे वीडियो के बजाय मल्टी-पार्ट आर्काइव/PAR2 हो सकता है, कोई सेगमेंट गायब हो सकता है, या स्ट्रीम पठनीय नहीं हो सकती है।';
  }

  @override
  String get engineBadgeDiskCacheOff => 'डिस्क कैश बंद';

  @override
  String get engineBadgeSdrSafePath => 'SDR सुरक्षित पथ';

  @override
  String errorControlFailed(String error) {
    return 'नियंत्रण लागू नहीं किया जा सका: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'ज़ूम लागू नहीं किया जा सका: $error';
  }

  @override
  String get errorPipUnavailable =>
      'इस प्लेटफ़ॉर्म पर Picture-in-Picture उपलब्ध नहीं है।';

  @override
  String get fileTypeSubtitles => 'सबटाइटल';

  @override
  String get fileTypeAudioFiles => 'ऑडियो फ़ाइलें';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds सेकंड पीछे';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds सेकंड आगे';
  }

  @override
  String get cancelCanvasEditing => 'कैनवास एडिटिंग रद्द करें';

  @override
  String get resetCanvas => 'कैनवास रीसेट करें';

  @override
  String get subtitleControls => 'सबटाइटल नियंत्रण';

  @override
  String get loopSetA => 'बिंदु A सेट करें';

  @override
  String get loopSetB => 'बिंदु B सेट करें';

  @override
  String get loopClear => 'A–B लूप हटाएँ';

  @override
  String get tuningMenuItem => 'वीडियो और ऑडियो सेटिंग्स…';

  @override
  String get tuningDialogTitle => 'वीडियो और ऑडियो';

  @override
  String get closeTooltip => 'बंद करें';

  @override
  String get videoPresetLabel => 'वीडियो प्रीसेट';

  @override
  String get presetNatural => 'प्राकृतिक';

  @override
  String get presetCinema => 'सिनेमा';

  @override
  String get presetVivid => 'विविड';

  @override
  String get gpuScalingLabel => 'GPU स्केलिंग';

  @override
  String get presetLowPower => 'कम पावर';

  @override
  String get presetBalanced => 'संतुलित';

  @override
  String get presetQuality => 'क्वालिटी';

  @override
  String get audioPresetLabel => 'ऑडियो प्रीसेट';

  @override
  String get presetDialogue => 'संवाद';

  @override
  String get presetNight => 'नाइट';

  @override
  String get seekStepLabel => 'सीक स्टेप';

  @override
  String get periodicInfoLabel => 'आवधिक जानकारी';

  @override
  String get secondsUnitShort => 'सेकंड';

  @override
  String get audioSyncLabel => 'ऑडियो सिंक';

  @override
  String get audioEarlierTooltip => 'ऑडियो को 0.1 सेकंड पहले करें';

  @override
  String get audioLaterTooltip => 'ऑडियो को 0.1 सेकंड देर से करें';

  @override
  String get decodingLabel => 'डिकोडिंग';

  @override
  String get decodingHardware => 'हार्डवेयर';

  @override
  String get decodingSoftware => 'सॉफ़्टवेयर';

  @override
  String get dynamicRangeLabel => 'डायनामिक रेंज';

  @override
  String get hdrInfoText =>
      'केवल वही फ़ॉर्मैट चुने जा सकते हैं जो कंटेंट में मौजूद हैं; बाकी अक्षम रहते हैं। SDR चुनने पर HDR कंटेंट को bt.709 पर टोन-मैप किया जाता है (BT.2390 + पीक डिटेक्ट)। HDR10+ अक्षम है क्योंकि libmpv उसका डायनामिक मेटाडेटा पहचान नहीं सकता; Dolby Vision उन प्रोफ़ाइलों पर समर्थित है जिनमें HDR10 बेस लेयर होती है।';

  @override
  String get doneLabel => 'हो गया';

  @override
  String get videoPreparing => 'वीडियो तैयार हो रहा है…';
}
