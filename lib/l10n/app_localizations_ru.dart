// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get appSectionTitle => 'Приложение';

  @override
  String get appSectionSubtitle =>
      'Настройки языка и внешнего вида хранятся на этом устройстве.';

  @override
  String get languageLabel => 'Язык';

  @override
  String get themeLabel => 'Внешний вид';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get advancedSettings => 'Расширенные настройки';

  @override
  String get play => 'Воспроизвести';

  @override
  String get pause => 'Пауза';

  @override
  String get selectNzbAndPlay => 'Выбрать NZB и воспроизвести';

  @override
  String get selectNzbHint => 'Откройте файл .nzb из файловой системы';

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
  String get engineStarting => 'Подготовка локального движка воспроизведения…';

  @override
  String get engineStartFailed =>
      'Не удалось запустить локальный движок воспроизведения';

  @override
  String get engineStartFailedHint =>
      'Проверьте файлы движка и установку приложения, затем повторите попытку.';

  @override
  String get retry => 'Повторить';

  @override
  String errorOpenNzb(String error) {
    return 'Не удалось открыть файл NZB: $error';
  }

  @override
  String get providerSettingsTooltip => 'Настройки провайдера';

  @override
  String get backTooltip => 'Назад';

  @override
  String get providerTitle => 'Провайдер';

  @override
  String get nntpSectionTitle => 'Подключение NNTP';

  @override
  String get nntpSectionSubtitle =>
      'Данные хранятся только в защищённой связке ключей этого устройства.';

  @override
  String get serverAddressLabel => 'Адрес сервера';

  @override
  String get portLabel => 'Порт';

  @override
  String get connectionLimitLabel => 'Лимит соединений';

  @override
  String get connectionLimitHint => 'Лимит тарифа';

  @override
  String get usernameLabel => 'Имя пользователя';

  @override
  String get passwordLabel => 'Пароль';

  @override
  String get passwordShowTooltip => 'Показать пароль';

  @override
  String get passwordHideTooltip => 'Скрыть пароль';

  @override
  String get saveSecurelyLabel => 'Сохранить безопасно';

  @override
  String get savingLabel => 'Сохранение…';

  @override
  String get settingsSaved => 'Настройки сохранены в защищённом хранилище.';

  @override
  String settingsSaveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String get secureStorageUnavailable => 'Нет доступа к защищённому хранилищу';

  @override
  String get connectionLimitWarning =>
      'Установка лимита соединений выше тарифа вашего провайдера может вызвать ошибку «слишком много соединений».';

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
    return 'Заполните поле «$field»';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '«$field»: введите целое число от $min до $max';
  }

  @override
  String get validationHostNoProtocol =>
      'Укажите только имя сервера, без протокола и порта';

  @override
  String get validationHostInvalid => 'Введите допустимое имя сервера';

  @override
  String get closePlayer => 'Закрыть плеер';

  @override
  String get fullscreen => 'Во весь экран';

  @override
  String get subtitleControlsTooltip =>
      'Экранные элементы управления субтитрами';

  @override
  String get miniPlayer => 'Мини-плеер';

  @override
  String get exitMiniPlayer => 'Выйти из мини-плеера';

  @override
  String get previousFrame => 'Предыдущий кадр';

  @override
  String get nextFrame => 'Следующий кадр';

  @override
  String get playbackSpeedTooltip => 'Скорость воспроизведения';

  @override
  String get audioTrack => 'Аудиодорожка';

  @override
  String get subtitleTrack => 'Дорожка субтитров';

  @override
  String get muteTooltip => 'Выключить звук';

  @override
  String get unmuteTooltip => 'Включить звук';

  @override
  String get loadFromFile => 'Загрузить из файла…';

  @override
  String get auto => 'Авто';

  @override
  String get off => 'Выкл.';

  @override
  String get subtitleDecreaseTooltip => 'Уменьшить размер субтитров';

  @override
  String get subtitleColor => 'Цвет субтитров';

  @override
  String get subtitleIncreaseTooltip => 'Увеличить размер субтитров';

  @override
  String get subtitleMoveUpTooltip => 'Поднять субтитры выше';

  @override
  String get subtitleMoveDownTooltip => 'Опустить субтитры ниже';

  @override
  String get subtitleEarlierTooltip => 'Сдвинуть субтитры на 0,1 с раньше';

  @override
  String get subtitleLaterTooltip => 'Задержать субтитры на 0,1 с';

  @override
  String get closeSubtitleControlsTooltip =>
      'Закрыть элементы управления субтитрами';

  @override
  String get smartCanvasAreaLabel => 'Область кадрирования Smart Canvas';

  @override
  String get smartCanvasSemanticsHint =>
      'Дважды коснитесь, чтобы применить. Нажмите Escape для отмены.';

  @override
  String get smartCanvasHintText => 'Двойное касание: применить · Esc: отмена';

  @override
  String get cropHandleTopLeft => 'Верхний левый маркер кадрирования';

  @override
  String get cropHandleTopRight => 'Верхний правый маркер кадрирования';

  @override
  String get cropHandleBottomLeft => 'Нижний левый маркер кадрирования';

  @override
  String get cropHandleBottomRight => 'Нижний правый маркер кадрирования';

  @override
  String get statusPreparing => 'Подготовка…';

  @override
  String get engineBadgePreparing => 'Подготовка нативного libmpv…';

  @override
  String get errorProviderSettingsMissing =>
      'Настройки провайдера не заполнены. Сначала введите данные на экране настроек.';

  @override
  String get statusConnecting =>
      'Подключение и получение первого сегмента (изучение структуры)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return 'Чтение структуры видео: $filename';
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
    return 'Буферизация: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return 'Воспроизведение: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return 'Ожидание видеодорожек: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return 'Запуск видео$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Поток Usenet не удалось запустить за $seconds сек. Соединение с провайдером, первый сегмент или содержимое NZB могут не отвечать.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return 'Не удалось распознать видео за $seconds сек. Возможно, NZB содержит многотомный архив/PAR2 вместо видео, отсутствует сегмент или поток не читается.';
  }

  @override
  String get engineBadgeDiskCacheOff => 'кэш на диске выкл.';

  @override
  String get engineBadgeSdrSafePath => 'безопасный путь SDR';

  @override
  String errorControlFailed(String error) {
    return 'Не удалось применить действие: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'Не удалось применить масштабирование: $error';
  }

  @override
  String get errorPipUnavailable =>
      'Picture-in-Picture недоступен на этой платформе.';

  @override
  String get fileTypeSubtitles => 'Субтитры';

  @override
  String get fileTypeAudioFiles => 'Аудиофайлы';

  @override
  String seekBackSeconds(int seconds) {
    return 'Назад на $seconds с';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return 'Вперёд на $seconds с';
  }

  @override
  String get cancelCanvasEditing => 'Отменить редактирование холста';

  @override
  String get resetCanvas => 'Сбросить холст';

  @override
  String get subtitleControls => 'Управление субтитрами';

  @override
  String get loopSetA => 'Установить точку A';

  @override
  String get loopSetB => 'Установить точку B';

  @override
  String get loopClear => 'Сбросить цикл A–B';

  @override
  String get tuningMenuItem => 'Настройки видео и аудио…';

  @override
  String get tuningDialogTitle => 'Видео и аудио';

  @override
  String get closeTooltip => 'Закрыть';

  @override
  String get videoPresetLabel => 'Пресет видео';

  @override
  String get presetNatural => 'Естественный';

  @override
  String get presetCinema => 'Кино';

  @override
  String get presetVivid => 'Яркий';

  @override
  String get gpuScalingLabel => 'Масштабирование GPU';

  @override
  String get presetLowPower => 'Энергосбережение';

  @override
  String get presetBalanced => 'Сбалансированный';

  @override
  String get presetQuality => 'Качество';

  @override
  String get audioPresetLabel => 'Пресет аудио';

  @override
  String get presetDialogue => 'Диалоги';

  @override
  String get presetNight => 'Ночной';

  @override
  String get seekStepLabel => 'Шаг перемотки';

  @override
  String get periodicInfoLabel => 'Периодическая информация';

  @override
  String get secondsUnitShort => 'с';

  @override
  String get audioSyncLabel => 'Синхронизация аудио';

  @override
  String get audioEarlierTooltip => 'Сдвинуть аудио на 0,1 с раньше';

  @override
  String get audioLaterTooltip => 'Задержать аудио на 0,1 с';

  @override
  String get decodingLabel => 'Декодирование';

  @override
  String get decodingHardware => 'Аппаратное';

  @override
  String get decodingSoftware => 'Программное';

  @override
  String get dynamicRangeLabel => 'Динамический диапазон';

  @override
  String get hdrInfoText =>
      'Можно выбрать только форматы, присутствующие в контенте; остальные недоступны. При выборе SDR HDR-контент тонально отображается в bt.709 (BT.2390 + peak detect). HDR10+ отключён, так как libmpv не может определить его динамические метаданные; Dolby Vision поддерживается в профилях с базовым слоем HDR10.';

  @override
  String get doneLabel => 'Готово';

  @override
  String get videoPreparing => 'Подготовка видео…';

  @override
  String get dvReshapeApplying => 'Применяется цветокоррекция Dolby Vision…';

  @override
  String get dvReshapeActiveHw =>
      'Цветокоррекция Dolby Vision активна (аппаратное декодирование)';

  @override
  String get dvReshapeActiveSw =>
      'Цветокоррекция Dolby Vision активна (программное декодирование)';

  @override
  String get dvReshapeFailed =>
      'Не удалось запустить цветокоррекцию Dolby Vision на этом устройстве. Нажмите для подробностей.';

  @override
  String get dvReshapeFailedShort =>
      'Не удалось запустить цветокоррекцию Dolby Vision — подробности в расширенных настройках.';

  @override
  String get dvReshapeDiagnosticsTitle => 'Диагностика коррекции DV';

  @override
  String get dvReshapeDiagnosticsEmpty =>
      'Строки журнала движка для фильтра не зафиксированы.';

  @override
  String get errFormatNotRecognized =>
      'Не удалось распознать формат медиа. Возможно, NZB содержит архив или данные восстановления PAR2 вместо прямого видео.';

  @override
  String get errLocalStreamUnreadable =>
      'Не удалось прочитать локальный видеопоток. Возможно, отсутствует сегмент Usenet или соединение прервалось.';

  @override
  String get errDecoderFailed =>
      'Видео- или аудиодекодер не смог открыть поток.';

  @override
  String get errPlayerGeneric => 'Плеер не смог открыть поток.';

  @override
  String get errNoMpvDetail => 'libmpv не дал подробностей.';

  @override
  String get errNoEngineDetail => 'Потоковый движок не дал подробностей.';

  @override
  String technicalDetail(String detail) {
    return 'Техническая деталь: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Достигнут лимит одновременных подключений провайдера Usenet. Закройте другие активные сессии или подождите и повторите. Если не поможет, уменьшите число подключений в приложении до лимита вашего тарифа.';

  @override
  String get errAuthFailed =>
      'Ошибка аутентификации Usenet. Проверьте имя пользователя и пароль в настройках провайдера.';

  @override
  String get errRarEncrypted =>
      'RAR-архив зашифрован. Защищённые паролем RAR-релизы не поддерживаются; выберите релиз, упакованный без шифрования (STORE).';

  @override
  String get err7zPassword =>
      'Пароль 7z-архива отсутствует или неверен. Выберите NZB, который несёт пароль в своих метаданных.';

  @override
  String get errArchiveCompressed =>
      'Этот архив сжат. Для мгновенного воспроизведения нужен релиз, упакованный без сжатия (COPY/STORE, 7z/RAR).';

  @override
  String get errArchiveSolid =>
      'Этот архив сплошной (solid). Для произвольного перематывания нужен релиз, упакованный как non-solid STORE.';

  @override
  String get errRar4 =>
      'Этот RAR-архив использует устаревший формат RAR4 (или старше). Воспроизводятся только релизы RAR5 STORE.';

  @override
  String get errSplitArchiveBroken =>
      'Многотомный архив (7z/RAR) неполный или повреждён. Выберите полный NZB, включающий все тома и сегменты.';

  @override
  String get errMissingSegments =>
      'NZB неполный или повреждён: не удаётся найти все нужные сегменты Usenet. Выберите другой, полный NZB для этого релиза.';

  @override
  String get errConnectionFailed =>
      'Не удалось подключиться к провайдеру Usenet. Проверьте интернет-соединение, адрес сервера, порт и доступность провайдера.';

  @override
  String get errNzbUnreadable =>
      'Файл NZB не удалось прочитать или он повреждён. Выберите действительный, полный файл NZB.';

  @override
  String get errArchiveNotPlayable =>
      'Архив (7z/RAR) в NZB не воспроизводится или его структура повреждена. Выберите полный STORE-релиз.';

  @override
  String get errNoPlayableMedia =>
      'В NZB не найден поддерживаемый видеопоток. Выберите релиз с прямым видео или поддерживаемым STORE-архивом.';

  @override
  String get errStreamStartupGeneric =>
      'Не удалось запустить поток. Проверьте содержимое NZB и подключение провайдера.';
}
