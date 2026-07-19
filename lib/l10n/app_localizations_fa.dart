// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get appSectionTitle => 'برنامه';

  @override
  String get appSectionSubtitle =>
      'ترجیحات زبان و ظاهر در همین دستگاه ذخیره می‌شود.';

  @override
  String get languageLabel => 'زبان';

  @override
  String get themeLabel => 'ظاهر';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeLight => 'روشن';

  @override
  String get advancedSettings => 'تنظیمات پیشرفته';

  @override
  String get play => 'پخش';

  @override
  String get pause => 'مکث';

  @override
  String get selectNzbAndPlay => 'انتخاب NZB و پخش';

  @override
  String get selectNzbHint => 'باز کردن یک فایل .nzb از سیستم فایل';

  @override
  String get engineStarting => 'در حال آماده‌سازی موتور پخش محلی…';

  @override
  String get engineStartFailed => 'موتور پخش محلی راه‌اندازی نشد';

  @override
  String get engineStartFailedHint =>
      'فایل‌های موتور و نصب برنامه را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get retry => 'تلاش دوباره';

  @override
  String errorOpenNzb(String error) {
    return 'فایل NZB باز نشد: $error';
  }

  @override
  String get providerSettingsTooltip => 'تنظیمات ارائه‌دهنده';

  @override
  String get backTooltip => 'بازگشت';

  @override
  String get providerTitle => 'ارائه‌دهنده';

  @override
  String get nntpSectionTitle => 'اتصال NNTP';

  @override
  String get nntpSectionSubtitle =>
      'جزئیات فقط در کیف‌کلید امن همین دستگاه ذخیره می‌شود.';

  @override
  String get serverAddressLabel => 'آدرس سرور';

  @override
  String get portLabel => 'پورت';

  @override
  String get connectionLimitLabel => 'محدودیت اتصال';

  @override
  String get connectionLimitHint => 'محدودیت طرح';

  @override
  String get usernameLabel => 'نام کاربری';

  @override
  String get passwordLabel => 'رمز عبور';

  @override
  String get passwordShowTooltip => 'نمایش رمز عبور';

  @override
  String get passwordHideTooltip => 'پنهان کردن رمز عبور';

  @override
  String get saveSecurelyLabel => 'ذخیره امن';

  @override
  String get savingLabel => 'در حال ذخیره…';

  @override
  String get settingsSaved => 'تنظیمات در حافظه امن ذخیره شد.';

  @override
  String settingsSaveFailed(String error) {
    return 'ذخیره نشد: $error';
  }

  @override
  String get secureStorageUnavailable => 'دسترسی به حافظه امن ممکن نشد';

  @override
  String get connectionLimitWarning =>
      'تنظیم محدودیت اتصال بالاتر از طرح ارائه‌دهنده شما ممکن است خطای «اتصالات بیش از حد» ایجاد کند.';

  @override
  String validationRequired(String field) {
    return '$field الزامی است';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field باید بین $min و $max باشد';
  }

  @override
  String get validationHostNoProtocol =>
      'فقط نام سرور را وارد کنید، بدون پروتکل یا پورت';

  @override
  String get validationHostInvalid => 'یک نام سرور معتبر وارد کنید';

  @override
  String get closePlayer => 'بستن پخش‌کننده';

  @override
  String get fullscreen => 'تمام‌صفحه';

  @override
  String get subtitleControlsTooltip => 'کنترل‌های زیرنویس روی صفحه';

  @override
  String get miniPlayer => 'پخش‌کننده کوچک';

  @override
  String get exitMiniPlayer => 'خروج از پخش‌کننده کوچک';

  @override
  String get previousFrame => 'فریم قبلی';

  @override
  String get nextFrame => 'فریم بعدی';

  @override
  String get playbackSpeedTooltip => 'سرعت پخش';

  @override
  String get audioTrack => 'تراک صوتی';

  @override
  String get subtitleTrack => 'تراک زیرنویس';

  @override
  String get muteTooltip => 'بی‌صدا کردن';

  @override
  String get unmuteTooltip => 'صدادار کردن';

  @override
  String get loadFromFile => 'بارگذاری از فایل…';

  @override
  String get auto => 'خودکار';

  @override
  String get off => 'خاموش';

  @override
  String get subtitleDecreaseTooltip => 'کوچک‌تر کردن زیرنویس';

  @override
  String get subtitleIncreaseTooltip => 'بزرگ‌تر کردن زیرنویس';

  @override
  String get subtitleMoveUpTooltip => 'انتقال زیرنویس به بالا';

  @override
  String get subtitleMoveDownTooltip => 'انتقال زیرنویس به پایین';

  @override
  String get subtitleEarlierTooltip => 'زیرنویس 0.1 ثانیه زودتر';

  @override
  String get subtitleLaterTooltip => 'زیرنویس 0.1 ثانیه دیرتر';

  @override
  String get closeSubtitleControlsTooltip => 'بستن کنترل‌های زیرنویس';

  @override
  String get smartCanvasAreaLabel => 'ناحیه برش Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'برای اعمال دوبار ضربه بزنید. برای لغو کلید Escape را فشار دهید.';

  @override
  String get smartCanvasHintText => 'دوبار ضربه: اعمال · Esc: لغو';

  @override
  String get cropHandleTopLeft => 'دستگیره برش بالا-چپ';

  @override
  String get cropHandleTopRight => 'دستگیره برش بالا-راست';

  @override
  String get cropHandleBottomLeft => 'دستگیره برش پایین-چپ';

  @override
  String get cropHandleBottomRight => 'دستگیره برش پایین-راست';

  @override
  String get statusPreparing => 'در حال آماده‌سازی…';

  @override
  String get engineBadgePreparing => 'در حال آماده‌سازی libmpv بومی…';

  @override
  String get errorProviderSettingsMissing =>
      'تنظیمات ارائه‌دهنده ناقص است. ابتدا اطلاعات خود را در صفحه تنظیمات وارد کنید.';

  @override
  String get statusConnecting =>
      'در حال اتصال و دریافت اولین قطعه (یادگیری ساختار)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'در حال خواندن ساختار ویدیو: $filename';
  }

  @override
  String statusBuffering(String filename) {
    return 'در حال بافر کردن: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'در حال پخش: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'در انتظار تراک‌های ویدیو: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'شروع ویدیو$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'استریم Usenet ظرف $seconds ثانیه شروع نشد. ممکن است اتصال ارائه‌دهنده، اولین قطعه یا محتوای NZB پاسخ ندهد.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'ویدیو ظرف $seconds ثانیه شناسایی نشد. ممکن است NZB به‌جای ویدیوی مستقیم حاوی آرشیو چندبخشی/PAR2 باشد، یک قطعه گم شده باشد یا استریم خوانا نباشد.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'کش دیسک خاموش';

  @override
  String get engineBadgeSdrSafePath => 'مسیر امن SDR';

  @override
  String errorControlFailed(String error) {
    return 'کنترل اعمال نشد: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'زوم اعمال نشد: $error';
  }

  @override
  String get errorPipUnavailable =>
      'تصویر در تصویر (PiP) در این پلتفرم در دسترس نیست.';

  @override
  String get fileTypeSubtitles => 'زیرنویس‌ها';

  @override
  String get fileTypeAudioFiles => 'فایل‌های صوتی';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds ثانیه به عقب';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds ثانیه به جلو';
  }

  @override
  String get cancelCanvasEditing => 'لغو ویرایش بوم';

  @override
  String get resetCanvas => 'بازنشانی بوم';

  @override
  String get subtitleControls => 'کنترل‌های زیرنویس';

  @override
  String get loopSetA => 'تنظیم نقطه A';

  @override
  String get loopSetB => 'تنظیم نقطه B';

  @override
  String get loopClear => 'پاک کردن حلقه A–B';

  @override
  String get tuningMenuItem => 'تنظیمات ویدیو و صدا…';

  @override
  String get tuningDialogTitle => 'ویدیو و صدا';

  @override
  String get closeTooltip => 'بستن';

  @override
  String get videoPresetLabel => 'پیش‌تنظیم ویدیو';

  @override
  String get presetNatural => 'طبیعی';

  @override
  String get presetCinema => 'سینمایی';

  @override
  String get presetVivid => 'زنده';

  @override
  String get gpuScalingLabel => 'مقیاس‌بندی GPU';

  @override
  String get presetLowPower => 'مصرف کم';

  @override
  String get presetBalanced => 'متعادل';

  @override
  String get presetQuality => 'کیفیت';

  @override
  String get audioPresetLabel => 'پیش‌تنظیم صدا';

  @override
  String get presetDialogue => 'دیالوگ';

  @override
  String get presetNight => 'شب';

  @override
  String get seekStepLabel => 'گام جستجو';

  @override
  String get periodicInfoLabel => 'اطلاعات دوره‌ای';

  @override
  String get secondsUnitShort => 'ث';

  @override
  String get audioSyncLabel => 'همگام‌سازی صدا';

  @override
  String get audioEarlierTooltip => 'صدا 0.1 ثانیه زودتر';

  @override
  String get audioLaterTooltip => 'صدا 0.1 ثانیه دیرتر';

  @override
  String get decodingLabel => 'رمزگشایی';

  @override
  String get decodingHardware => 'سخت‌افزاری';

  @override
  String get decodingSoftware => 'نرم‌افزاری';

  @override
  String get dynamicRangeLabel => 'محدوده دینامیک';

  @override
  String get hdrInfoText =>
      'فقط قالب‌هایی که توسط محتوا ارائه می‌شوند قابل انتخاب هستند؛ بقیه غیرفعال‌اند. هنگام انتخاب SDR، محتوای HDR به bt.709 تون-مپ می‌شود (BT.2390 + تشخیص پیک). HDR10+ غیرفعال است زیرا libmpv نمی‌تواند متادیتای دینامیک آن را تشخیص دهد؛ Dolby Vision در پروفایل‌هایی پشتیبانی می‌شود که شامل لایه پایه HDR10 باشند.';

  @override
  String get doneLabel => 'انجام شد';

  @override
  String get videoPreparing => 'در حال آماده‌سازی ویدیو…';
}
