// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get appSectionTitle => 'التطبيق';

  @override
  String get appSectionSubtitle =>
      'تُحفَظ تفضيلات اللغة والمظهر على هذا الجهاز.';

  @override
  String get languageLabel => 'اللغة';

  @override
  String get themeLabel => 'المظهر';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get advancedSettings => 'إعدادات متقدمة';

  @override
  String get play => 'تشغيل';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get selectNzbAndPlay => 'اختر NZB وشغّل';

  @override
  String get selectNzbHint => 'افتح ملف .nzb من نظام الملفات';

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
  String get engineStarting => 'جارٍ تجهيز محرك التشغيل المحلي…';

  @override
  String get engineStartFailed => 'تعذّر تشغيل محرك التشغيل المحلي';

  @override
  String get engineStartFailedHint =>
      'تحقّق من ملفات المحرك وتثبيت التطبيق، ثم حاول مرة أخرى.';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String errorOpenNzb(String error) {
    return 'تعذّر فتح ملف NZB: $error';
  }

  @override
  String get providerSettingsTooltip => 'إعدادات المزوّد';

  @override
  String get backTooltip => 'رجوع';

  @override
  String get providerTitle => 'المزوّد';

  @override
  String get nntpSectionTitle => 'اتصال NNTP';

  @override
  String get nntpSectionSubtitle =>
      'تُحفَظ التفاصيل فقط في سلسلة المفاتيح الآمنة لهذا الجهاز.';

  @override
  String get serverAddressLabel => 'عنوان الخادم';

  @override
  String get portLabel => 'المنفذ';

  @override
  String get connectionLimitLabel => 'حد الاتصالات';

  @override
  String get connectionLimitHint => 'حد الخطة';

  @override
  String get usernameLabel => 'اسم المستخدم';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get passwordShowTooltip => 'إظهار كلمة المرور';

  @override
  String get passwordHideTooltip => 'إخفاء كلمة المرور';

  @override
  String get saveSecurelyLabel => 'حفظ بأمان';

  @override
  String get savingLabel => 'جارٍ الحفظ…';

  @override
  String get settingsSaved => 'تم حفظ الإعدادات في التخزين الآمن.';

  @override
  String settingsSaveFailed(String error) {
    return 'تعذّر الحفظ: $error';
  }

  @override
  String get secureStorageUnavailable => 'تعذّر الوصول إلى التخزين الآمن';

  @override
  String get connectionLimitWarning =>
      'قد يؤدي ضبط حد الاتصالات فوق خطة مزوّدك إلى خطأ «عدد كبير جدًا من الاتصالات».';

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
    return '$field مطلوب';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return 'يجب أن يكون $field بين $min و$max';
  }

  @override
  String get validationHostNoProtocol =>
      'أدخل اسم الخادم فقط، دون بروتوكول أو منفذ';

  @override
  String get validationHostInvalid => 'أدخل اسم خادم صالحًا';

  @override
  String get closePlayer => 'إغلاق المشغّل';

  @override
  String get fullscreen => 'ملء الشاشة';

  @override
  String get subtitleControlsTooltip => 'أدوات الترجمة على الشاشة';

  @override
  String get miniPlayer => 'المشغّل المصغّر';

  @override
  String get exitMiniPlayer => 'الخروج من المشغّل المصغّر';

  @override
  String get previousFrame => 'الإطار السابق';

  @override
  String get nextFrame => 'الإطار التالي';

  @override
  String get playbackSpeedTooltip => 'سرعة التشغيل';

  @override
  String get audioTrack => 'المسار الصوتي';

  @override
  String get subtitleTrack => 'مسار الترجمة';

  @override
  String get muteTooltip => 'كتم الصوت';

  @override
  String get unmuteTooltip => 'إلغاء كتم الصوت';

  @override
  String get loadFromFile => 'تحميل من ملف…';

  @override
  String get auto => 'تلقائي';

  @override
  String get off => 'إيقاف';

  @override
  String get subtitleDecreaseTooltip => 'تصغير حجم الترجمة';

  @override
  String get subtitleColor => 'لون الترجمة';

  @override
  String get subtitleIncreaseTooltip => 'تكبير حجم الترجمة';

  @override
  String get subtitleMoveUpTooltip => 'تحريك الترجمة لأعلى';

  @override
  String get subtitleMoveDownTooltip => 'تحريك الترجمة لأسفل';

  @override
  String get subtitleEarlierTooltip => 'تقديم الترجمة 0.1 ثانية';

  @override
  String get subtitleLaterTooltip => 'تأخير الترجمة 0.1 ثانية';

  @override
  String get closeSubtitleControlsTooltip => 'إغلاق أدوات الترجمة';

  @override
  String get smartCanvasAreaLabel => 'منطقة اقتصاص Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'انقر نقرًا مزدوجًا للتطبيق. اضغط Escape للإلغاء.';

  @override
  String get smartCanvasHintText => 'نقر مزدوج: تطبيق · Esc: إلغاء';

  @override
  String get cropHandleTopLeft => 'مقبض الاقتصاص العلوي الأيسر';

  @override
  String get cropHandleTopRight => 'مقبض الاقتصاص العلوي الأيمن';

  @override
  String get cropHandleBottomLeft => 'مقبض الاقتصاص السفلي الأيسر';

  @override
  String get cropHandleBottomRight => 'مقبض الاقتصاص السفلي الأيمن';

  @override
  String get statusPreparing => 'جارٍ التجهيز…';

  @override
  String get engineBadgePreparing => 'جارٍ تجهيز libmpv الأصلي…';

  @override
  String get errorProviderSettingsMissing =>
      'إعدادات المزوّد غير مكتملة. أدخل بياناتك في شاشة الإعدادات أولًا.';

  @override
  String get statusConnecting =>
      'جارٍ الاتصال وجلب المقطع الأول (تعلّم البنية)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'جارٍ قراءة بنية الفيديو: $filename';
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
    return 'جارٍ التخزين المؤقت: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'قيد التشغيل: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'في انتظار مسارات الفيديو: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'جارٍ بدء الفيديو$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'تعذّر بدء بث Usenet خلال $seconds ثانية. قد لا يستجيب اتصال المزوّد أو المقطع الأول أو محتوى NZB.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'تعذّر التعرّف على الفيديو خلال $seconds ثانية. قد يحتوي NZB على أرشيف متعدد الأجزاء/PAR2 بدلًا من فيديو مباشر، أو قد يكون أحد المقاطع مفقودًا، أو قد يكون البث غير قابل للقراءة.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'ذاكرة التخزين المؤقت للقرص متوقفة';

  @override
  String get engineBadgeSdrSafePath => 'مسار SDR الآمن';

  @override
  String errorControlFailed(String error) {
    return 'تعذّر تطبيق عنصر التحكم: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'تعذّر تطبيق التكبير: $error';
  }

  @override
  String get errorPipUnavailable => 'ميزة PiP غير متوفرة على هذه المنصة.';

  @override
  String get fileTypeSubtitles => 'ترجمات';

  @override
  String get fileTypeAudioFiles => 'ملفات صوتية';

  @override
  String seekBackSeconds(int seconds) {
    return 'رجوع $seconds ثانية';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'تقديم $seconds ثانية';
  }

  @override
  String get cancelCanvasEditing => 'إلغاء تحرير اللوحة';

  @override
  String get resetCanvas => 'إعادة تعيين اللوحة';

  @override
  String get subtitleControls => 'أدوات الترجمة';

  @override
  String get loopSetA => 'تعيين النقطة A';

  @override
  String get loopSetB => 'تعيين النقطة B';

  @override
  String get loopClear => 'مسح حلقة A–B';

  @override
  String get tuningMenuItem => 'إعدادات الفيديو والصوت…';

  @override
  String get tuningDialogTitle => 'الفيديو والصوت';

  @override
  String get closeTooltip => 'إغلاق';

  @override
  String get videoPresetLabel => 'إعداد الفيديو المسبق';

  @override
  String get presetNatural => 'طبيعي';

  @override
  String get presetCinema => 'سينمائي';

  @override
  String get presetVivid => 'نابض';

  @override
  String get gpuScalingLabel => 'تحجيم GPU';

  @override
  String get presetLowPower => 'طاقة منخفضة';

  @override
  String get presetBalanced => 'متوازن';

  @override
  String get presetQuality => 'جودة';

  @override
  String get audioPresetLabel => 'إعداد الصوت المسبق';

  @override
  String get presetDialogue => 'حوار';

  @override
  String get presetNight => 'ليلي';

  @override
  String get seekStepLabel => 'خطوة التنقل';

  @override
  String get periodicInfoLabel => 'معلومات دورية';

  @override
  String get secondsUnitShort => 'ث';

  @override
  String get audioSyncLabel => 'مزامنة الصوت';

  @override
  String get audioEarlierTooltip => 'تقديم الصوت 0.1 ثانية';

  @override
  String get audioLaterTooltip => 'تأخير الصوت 0.1 ثانية';

  @override
  String get decodingLabel => 'فك الترميز';

  @override
  String get decodingHardware => 'عتاد';

  @override
  String get decodingSoftware => 'برمجي';

  @override
  String get dynamicRangeLabel => 'النطاق الديناميكي';

  @override
  String get hdrInfoText =>
      'يمكن اختيار الصيغ التي يحملها المحتوى فقط؛ أما الأخرى فهي معطّلة. عند اختيار SDR، يُعاد تعيين ألوان محتوى HDR إلى bt.709 (BT.2390 + كشف الذروة). HDR10+ معطّل لأن libmpv لا يستطيع اكتشاف بياناته الوصفية الديناميكية؛ أما Dolby Vision فمدعوم على الملفات التعريفية التي تتضمن طبقة أساس HDR10.';

  @override
  String get doneLabel => 'تم';

  @override
  String get videoPreparing => 'جارٍ تجهيز الفيديو…';

  @override
  String get dvReshapeApplying => 'جارٍ تطبيق تصحيح ألوان Dolby Vision…';

  @override
  String get dvReshapeActiveHw =>
      'تصحيح ألوان Dolby Vision مفعّل (فك ترميز بالأجهزة)';

  @override
  String get dvReshapeActiveSw =>
      'تصحيح ألوان Dolby Vision مفعّل (فك ترميز بالبرمجيات)';

  @override
  String get dvReshapeFailed =>
      'تعذّر بدء تصحيح ألوان Dolby Vision على هذا الجهاز. اضغط للاطلاع على التفاصيل.';

  @override
  String get dvReshapeFailedShort =>
      'تعذّر بدء تصحيح ألوان Dolby Vision — التفاصيل في الإعدادات المتقدمة.';

  @override
  String get dvReshapeDiagnosticsTitle => 'تشخيص تصحيح DV';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'لم يتم التقاط أي سطور من سجل المحرك للمرشح.';

  @override
  String get errFormatNotRecognized =>
      'تعذّر التعرف على تنسيق الوسائط. قد يحتوي ملف NZB على أرشيف أو بيانات استرداد PAR2 بدلاً من فيديو مباشر.';

  @override
  String get errLocalStreamUnreadable =>
      'تعذّرت قراءة بث الفيديو المحلي. ربما يكون أحد مقاطع Usenet مفقودًا أو انقطع الاتصال.';

  @override
  String get errDecoderFailed =>
      'تعذّر على مفكّك ترميز الفيديو أو الصوت فتح البث.';

  @override
  String get errPlayerGeneric => 'تعذّر على المشغّل فتح البث.';

  @override
  String get errNoMpvDetail => 'لم يقدّم libmpv أي تفاصيل.';

  @override
  String get errNoEngineDetail => 'لم يقدّم محرك البث أي تفاصيل.';

  @override
  String technicalDetail(String detail) {
    return 'تفصيل تقني: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'تم بلوغ حد الاتصالات المتزامنة لمزوّد Usenet. أغلق الجلسات النشطة الأخرى أو انتظر قليلاً وأعد المحاولة. إن استمرت المشكلة، فخفّض عدد الاتصالات في التطبيق إلى حد باقتك.';

  @override
  String get errAuthFailed =>
      'فشلت مصادقة Usenet. تحقق من اسم المستخدم وكلمة المرور في إعدادات المزوّد.';

  @override
  String get errRarEncrypted =>
      'أرشيف RAR مشفّر. الإصدارات المحمية بكلمة مرور غير مدعومة؛ اختر إصدارًا مُحزمًا بدون تشفير (STORE).';

  @override
  String get err7zPassword =>
      'كلمة مرور أرشيف 7z مفقودة أو غير صالحة. اختر ملف NZB الذي يحمل كلمة المرور في بياناته الوصفية.';

  @override
  String get errArchiveCompressed =>
      'هذا الأرشيف مضغوط. التشغيل الفوري يتطلب إصدارًا مُحزمًا بدون ضغط (COPY/STORE، 7z/RAR).';

  @override
  String get errArchiveSolid =>
      'هذا الأرشيف ذو بنية صلبة (solid). التنقل العشوائي يتطلب إصدارًا مُحزمًا بصيغة STORE غير صلبة.';

  @override
  String get errRar4 =>
      'يستخدم أرشيف RAR هذا التنسيق القديم (RAR4 أو أقدم). لا يمكن تشغيل سوى إصدارات RAR5 STORE.';

  @override
  String get errSplitArchiveBroken =>
      'الأرشيف متعدد الأجزاء (7z/RAR) غير مكتمل أو تالف. اختر ملف NZB كاملًا يتضمن جميع المجلدات والمقاطع.';

  @override
  String get errMissingSegments =>
      'ملف NZB غير مكتمل أو تالف: لا يمكن العثور على جميع مقاطع Usenet المطلوبة. اختر ملف NZB كاملًا آخر لهذا الإصدار.';

  @override
  String get errConnectionFailed =>
      'تعذّر الاتصال بمزوّد Usenet. تحقق من اتصال الإنترنت وعنوان الخادم والمنفذ وإمكانية الوصول إلى المزوّد.';

  @override
  String get errNzbUnreadable =>
      'تعذّرت قراءة ملف NZB أو أنه تالف. اختر ملف NZB صالحًا وكاملًا.';

  @override
  String get errArchiveNotPlayable =>
      'الأرشيف (7z/RAR) داخل NZB غير قابل للتشغيل أو بنيته تالفة. اختر إصدار STORE كاملًا.';

  @override
  String get errNoPlayableMedia =>
      'لم يُعثر على بث فيديو مدعوم في NZB. اختر إصدارًا يتضمن وسائط مباشرة أو أرشيف STORE مدعومًا.';

  @override
  String get errStreamStartupGeneric =>
      'تعذّر بدء البث. تحقق من محتوى NZB واتصال المزوّد.';
}
