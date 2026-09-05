// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => '设置';

  @override
  String get appSectionTitle => '应用';

  @override
  String get appSectionSubtitle => '语言和外观偏好仅存储在此设备上。';

  @override
  String get languageLabel => '语言';

  @override
  String get themeLabel => '外观';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get advancedSettings => '高级设置';

  @override
  String get play => '播放';

  @override
  String get pause => '暂停';

  @override
  String get selectNzbAndPlay => '选择 NZB 并播放';

  @override
  String get selectNzbHint => '从文件系统打开 .nzb 文件';

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
  String get engineStarting => '正在准备本地播放引擎…';

  @override
  String get engineStartFailed => '无法启动本地播放引擎';

  @override
  String get engineStartFailedHint => '请检查引擎文件和应用安装，然后重试。';

  @override
  String get retry => '重试';

  @override
  String errorOpenNzb(String error) {
    return '无法打开 NZB 文件：$error';
  }

  @override
  String get providerSettingsTooltip => '提供商设置';

  @override
  String get backTooltip => '返回';

  @override
  String get providerTitle => '提供商';

  @override
  String get nntpSectionTitle => 'NNTP 连接';

  @override
  String get nntpSectionSubtitle => '详细信息仅存储在此设备的安全钥匙串中。';

  @override
  String get serverAddressLabel => '服务器地址';

  @override
  String get portLabel => '端口';

  @override
  String get connectionLimitLabel => '连接数限制';

  @override
  String get connectionLimitHint => '套餐限制';

  @override
  String get usernameLabel => '用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get passwordShowTooltip => '显示密码';

  @override
  String get passwordHideTooltip => '隐藏密码';

  @override
  String get saveSecurelyLabel => '安全保存';

  @override
  String get savingLabel => '正在保存…';

  @override
  String get settingsSaved => '设置已保存到安全存储。';

  @override
  String settingsSaveFailed(String error) {
    return '无法保存：$error';
  }

  @override
  String get secureStorageUnavailable => '无法访问安全存储';

  @override
  String get connectionLimitWarning => '将连接数限制设置为高于提供商套餐上限可能会导致“连接过多”错误。';

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
    return '$field为必填项';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field必须在 $min 到 $max 之间';
  }

  @override
  String get validationHostNoProtocol => '请仅输入服务器名称，不要包含协议或端口';

  @override
  String get validationHostInvalid => '请输入有效的服务器名称';

  @override
  String get closePlayer => '关闭播放器';

  @override
  String get fullscreen => '全屏';

  @override
  String get subtitleControlsTooltip => '屏幕字幕控制';

  @override
  String get miniPlayer => '迷你播放器';

  @override
  String get exitMiniPlayer => '退出迷你播放器';

  @override
  String get previousFrame => '上一帧';

  @override
  String get nextFrame => '下一帧';

  @override
  String get playbackSpeedTooltip => '播放速度';

  @override
  String get audioTrack => '音轨';

  @override
  String get subtitleTrack => '字幕轨道';

  @override
  String get muteTooltip => '静音';

  @override
  String get unmuteTooltip => '取消静音';

  @override
  String get loadFromFile => '从文件加载…';

  @override
  String get auto => '自动';

  @override
  String get off => '关闭';

  @override
  String get subtitleDecreaseTooltip => '减小字幕字号';

  @override
  String get continueWatching => '继续观看';

  @override
  String get videoFitCover => '填充屏幕';

  @override
  String get videoFitContain => '适应屏幕';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateLater => '稍后';

  @override
  String get updateSkip => '跳过此版本';

  @override
  String get updateDownloading => '正在下载更新…';

  @override
  String get updateOpenPage => '打开下载页面';

  @override
  String updateFailed(String error) {
    return '更新失败：$error';
  }

  @override
  String get historyRemoveTooltip => '从历史记录中移除';

  @override
  String historyRemaining(String time) {
    return '剩余 $time';
  }

  @override
  String get subtitleColor => '字幕颜色';

  @override
  String get subtitleIncreaseTooltip => '增大字幕字号';

  @override
  String get subtitleMoveUpTooltip => '字幕上移';

  @override
  String get subtitleMoveDownTooltip => '字幕下移';

  @override
  String get subtitleEarlierTooltip => '字幕提前 0.1 秒';

  @override
  String get subtitleLaterTooltip => '字幕延后 0.1 秒';

  @override
  String get closeSubtitleControlsTooltip => '关闭字幕控制';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas 裁剪区域';

  @override
  String get smartCanvasSemanticsHint => '双击以应用。按 Escape 键取消。';

  @override
  String get smartCanvasHintText => '双击：应用 · Esc：取消';

  @override
  String get cropHandleTopLeft => '左上角裁剪手柄';

  @override
  String get cropHandleTopRight => '右上角裁剪手柄';

  @override
  String get cropHandleBottomLeft => '左下角裁剪手柄';

  @override
  String get cropHandleBottomRight => '右下角裁剪手柄';

  @override
  String get statusPreparing => '正在准备…';

  @override
  String get engineBadgePreparing => '正在准备原生 libmpv…';

  @override
  String get errorProviderSettingsMissing => '提供商设置不完整。请先在设置界面输入您的信息。';

  @override
  String get statusConnecting => '正在连接并获取第一个分段（正在学习布局）…';

  @override
  String statusReadingVideoStructure(String filename) {
    return '正在读取视频结构：$filename';
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
    return '正在缓冲：$filename';
  }

  @override
  String statusPlaying(String filename) {
    return '正在播放：$filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return '正在等待视频轨道：$filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return '正在启动视频$progress：$filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Usenet 流未能在 $seconds 秒内启动。提供商连接、第一个分段或 NZB 内容可能没有响应。';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return '未能在 $seconds 秒内识别视频。NZB 可能包含多部分压缩包/PAR2 而非直接视频，可能缺少分段，或者流无法读取。';
  }

  @override
  String get engineBadgeDiskCacheOff => '磁盘缓存已关闭';

  @override
  String get engineBadgeSdrSafePath => 'SDR 安全路径';

  @override
  String errorControlFailed(String error) {
    return '无法应用控制：$error';
  }

  @override
  String errorZoomFailed(String error) {
    return '无法应用缩放：$error';
  }

  @override
  String get errorPipUnavailable => '此平台不支持画中画 (PiP)。';

  @override
  String get fileTypeSubtitles => '字幕';

  @override
  String get fileTypeAudioFiles => '音频文件';

  @override
  String seekBackSeconds(int seconds) {
    return '后退 $seconds 秒';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '前进 $seconds 秒';
  }

  @override
  String get cancelCanvasEditing => '取消画布编辑';

  @override
  String get resetCanvas => '重置画布';

  @override
  String get subtitleControls => '字幕控制';

  @override
  String get loopSetA => '设置 A 点';

  @override
  String get loopSetB => '设置 B 点';

  @override
  String get loopClear => '清除 A–B 循环';

  @override
  String get tuningMenuItem => '视频和音频设置…';

  @override
  String get tuningDialogTitle => '视频和音频';

  @override
  String get closeTooltip => '关闭';

  @override
  String get videoPresetLabel => '视频预设';

  @override
  String get presetNatural => '自然';

  @override
  String get presetCinema => '影院';

  @override
  String get presetVivid => '鲜艳';

  @override
  String get gpuScalingLabel => 'GPU 缩放';

  @override
  String get presetLowPower => '低功耗';

  @override
  String get presetBalanced => '均衡';

  @override
  String get presetQuality => '高质量';

  @override
  String get audioPresetLabel => '音频预设';

  @override
  String get presetDialogue => '对白';

  @override
  String get presetNight => '夜间';

  @override
  String get seekStepLabel => '跳转步长';

  @override
  String get periodicInfoLabel => '定期信息';

  @override
  String get secondsUnitShort => '秒';

  @override
  String get audioSyncLabel => '音频同步';

  @override
  String get audioEarlierTooltip => '音频提前 0.1 秒';

  @override
  String get audioLaterTooltip => '音频延后 0.1 秒';

  @override
  String get decodingLabel => '解码';

  @override
  String get decodingHardware => '硬件';

  @override
  String get decodingSoftware => '软件';

  @override
  String get dynamicRangeLabel => '动态范围';

  @override
  String get hdrInfoText =>
      '只能选择内容所携带的格式，其余格式将被禁用。选择 SDR 时，HDR 内容将通过色调映射转换为 bt.709（BT.2390 + 峰值检测）。HDR10+ 已禁用，因为 libmpv 无法检测其动态元数据；Dolby Vision 在包含 HDR10 基础层的配置文件上受支持。';

  @override
  String get doneLabel => '完成';

  @override
  String get videoPreparing => '正在准备视频…';

  @override
  String get dvReshapeApplying => '正在应用 Dolby Vision 色彩校正…';

  @override
  String get dvReshapeActiveHw => 'Dolby Vision 色彩校正已启用（硬件解码）';

  @override
  String get dvReshapeActiveSw => 'Dolby Vision 色彩校正已启用（软件解码）';

  @override
  String get dvReshapeFailed => '无法在此设备上启用 Dolby Vision 色彩校正。点击查看详情。';

  @override
  String get dvReshapeFailedShort => '无法启用 Dolby Vision 色彩校正——详情请见高级设置。';

  @override
  String get dvReshapeDiagnosticsTitle => 'DV 校正诊断';

  @override
  String get dvReshapeDiagnosticsEmpty => '未捕获到该滤镜的引擎日志。';

  @override
  String get errFormatNotRecognized =>
      '无法识别媒体格式。该 NZB 可能包含压缩包或 PAR2 恢复数据，而不是直接的视频。';

  @override
  String get errLocalStreamUnreadable => '无法读取本地视频流。可能缺少某个 Usenet 分段，或连接已断开。';

  @override
  String get errDecoderFailed => '视频或音频解码器无法打开该流。';

  @override
  String get errPlayerGeneric => '播放器无法打开该流。';

  @override
  String get errNoMpvDetail => 'libmpv 未提供详细信息。';

  @override
  String get errNoEngineDetail => '流媒体引擎未提供详细信息。';

  @override
  String technicalDetail(String detail) {
    return '技术细节：$detail';
  }

  @override
  String get errProviderConnectionLimit =>
      '已达到 Usenet 提供商的并发连接数上限。请关闭其他活动会话或稍等片刻后重试。如果仍然出现，请将应用内的连接数降低到套餐上限。';

  @override
  String get errAuthFailed => 'Usenet 身份验证失败。请检查提供商设置中的用户名和密码。';

  @override
  String get errRarEncrypted =>
      '该 RAR 压缩包已加密。不支持带密码的 RAR 发布；请选择以未加密方式打包的发布（STORE）。';

  @override
  String get err7zPassword => '7z 压缩包的密码缺失或无效。请选择元数据中带有该密码的 NZB。';

  @override
  String get errArchiveCompressed =>
      '此压缩包已压缩。即时播放需要以未压缩方式（COPY/STORE，7z/RAR）打包的发布。';

  @override
  String get errArchiveSolid => '此压缩包为 solid 结构。随机跳转需要以非 solid STORE 方式打包的发布。';

  @override
  String get errRar4 => '该 RAR 压缩包使用旧版 RAR4（或更早）格式。只有 RAR5 STORE 发布可播放。';

  @override
  String get errSplitArchiveBroken =>
      '多卷压缩包（7z/RAR）不完整或已损坏。请选择包含所有卷和分段的完整 NZB。';

  @override
  String get errMissingSegments =>
      'NZB 不完整或已损坏：找不到全部所需的 Usenet 分段。请为该发布选择另一个完整的 NZB。';

  @override
  String get errConnectionFailed =>
      '无法连接到 Usenet 提供商。请检查网络连接、服务器地址、端口以及提供商的可达性。';

  @override
  String get errNzbUnreadable => '无法读取 NZB 文件或文件已损坏。请选择有效、完整的 NZB 文件。';

  @override
  String get errArchiveNotPlayable =>
      'NZB 内的压缩包（7z/RAR）无法播放或其结构已损坏。请选择完整的 STORE 发布。';

  @override
  String get errNoPlayableMedia =>
      '在 NZB 中找不到受支持的视频流。请选择带有直接媒体或受支持 STORE 压缩包的发布。';

  @override
  String get errStreamStartupGeneric => '无法启动该流。请检查 NZB 内容和提供商连接。';
}
