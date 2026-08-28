// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => '설정';

  @override
  String get appSectionTitle => '애플리케이션';

  @override
  String get appSectionSubtitle => '언어 및 테마 설정은 이 기기에 저장됩니다.';

  @override
  String get languageLabel => '언어';

  @override
  String get themeLabel => '테마';

  @override
  String get themeDark => '다크';

  @override
  String get themeLight => '라이트';

  @override
  String get advancedSettings => '고급 설정';

  @override
  String get play => '재생';

  @override
  String get pause => '일시정지';

  @override
  String get selectNzbAndPlay => 'NZB 선택 후 재생';

  @override
  String get selectNzbHint => '파일 시스템에서 .nzb 열기';

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
  String get engineStarting => '로컬 재생 엔진 준비 중…';

  @override
  String get engineStartFailed => '로컬 재생 엔진을 시작할 수 없습니다';

  @override
  String get engineStartFailedHint => '엔진 파일과 앱 설치 상태를 확인한 후 다시 시도하세요.';

  @override
  String get retry => '다시 시도';

  @override
  String errorOpenNzb(String error) {
    return 'NZB 파일을 열 수 없습니다: $error';
  }

  @override
  String get providerSettingsTooltip => '제공자 설정';

  @override
  String get backTooltip => '뒤로';

  @override
  String get providerTitle => '제공자';

  @override
  String get nntpSectionTitle => 'NNTP 연결';

  @override
  String get nntpSectionSubtitle => '정보는 이 기기의 보안 키체인에만 저장됩니다.';

  @override
  String get serverAddressLabel => '서버 주소';

  @override
  String get portLabel => '포트';

  @override
  String get connectionLimitLabel => '연결 제한';

  @override
  String get connectionLimitHint => '요금제 제한';

  @override
  String get usernameLabel => '사용자 이름';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get passwordShowTooltip => '비밀번호 표시';

  @override
  String get passwordHideTooltip => '비밀번호 숨기기';

  @override
  String get saveSecurelyLabel => '안전하게 저장';

  @override
  String get savingLabel => '저장 중…';

  @override
  String get settingsSaved => '설정이 보안 저장소에 저장되었습니다.';

  @override
  String settingsSaveFailed(String error) {
    return '저장할 수 없습니다: $error';
  }

  @override
  String get secureStorageUnavailable => '보안 저장소에 접근할 수 없습니다';

  @override
  String get connectionLimitWarning =>
      '연결 제한을 제공자 요금제보다 높게 설정하면 “too many connections” 오류가 발생할 수 있습니다.';

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
    return '$field은(는) 필수 항목입니다';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$field은(는) $min에서 $max 사이여야 합니다';
  }

  @override
  String get validationHostNoProtocol => '프로토콜이나 포트 없이 서버 이름만 입력하세요';

  @override
  String get validationHostInvalid => '올바른 서버 이름을 입력하세요';

  @override
  String get closePlayer => '플레이어 닫기';

  @override
  String get fullscreen => '전체 화면';

  @override
  String get subtitleControlsTooltip => '화면 내 자막 컨트롤';

  @override
  String get miniPlayer => '미니 플레이어';

  @override
  String get exitMiniPlayer => '미니 플레이어 종료';

  @override
  String get previousFrame => '이전 프레임';

  @override
  String get nextFrame => '다음 프레임';

  @override
  String get playbackSpeedTooltip => '재생 속도';

  @override
  String get audioTrack => '오디오 트랙';

  @override
  String get subtitleTrack => '자막 트랙';

  @override
  String get muteTooltip => '음소거';

  @override
  String get unmuteTooltip => '음소거 해제';

  @override
  String get loadFromFile => '파일에서 불러오기…';

  @override
  String get auto => '자동';

  @override
  String get off => '끄기';

  @override
  String get subtitleDecreaseTooltip => '자막 크기 줄이기';

  @override
  String get continueWatching => '이어보기';

  @override
  String get updateAvailable => '새 버전이 있습니다';

  @override
  String get updateNow => '지금 업데이트';

  @override
  String get updateLater => '나중에';

  @override
  String get updateSkip => '이 버전 건너뛰기';

  @override
  String get updateDownloading => '업데이트 다운로드 중…';

  @override
  String get updateOpenPage => '다운로드 페이지 열기';

  @override
  String updateFailed(String error) {
    return '업데이트 실패: $error';
  }

  @override
  String get historyRemoveTooltip => '기록에서 삭제';

  @override
  String historyRemaining(String time) {
    return '$time 남음';
  }

  @override
  String get subtitleColor => '자막 색상';

  @override
  String get subtitleIncreaseTooltip => '자막 크기 키우기';

  @override
  String get subtitleMoveUpTooltip => '자막 위로 이동';

  @override
  String get subtitleMoveDownTooltip => '자막 아래로 이동';

  @override
  String get subtitleEarlierTooltip => '자막을 0.1초 앞당기기';

  @override
  String get subtitleLaterTooltip => '자막을 0.1초 늦추기';

  @override
  String get closeSubtitleControlsTooltip => '자막 컨트롤 닫기';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas 자르기 영역';

  @override
  String get smartCanvasSemanticsHint => '더블 탭하면 적용됩니다. Esc 키를 누르면 취소됩니다.';

  @override
  String get smartCanvasHintText => '더블 탭: 적용 · Esc: 취소';

  @override
  String get cropHandleTopLeft => '왼쪽 위 자르기 핸들';

  @override
  String get cropHandleTopRight => '오른쪽 위 자르기 핸들';

  @override
  String get cropHandleBottomLeft => '왼쪽 아래 자르기 핸들';

  @override
  String get cropHandleBottomRight => '오른쪽 아래 자르기 핸들';

  @override
  String get statusPreparing => '준비 중…';

  @override
  String get engineBadgePreparing => '네이티브 libmpv 준비 중…';

  @override
  String get errorProviderSettingsMissing =>
      '제공자 설정이 완전하지 않습니다. 먼저 설정 화면에서 정보를 입력하세요.';

  @override
  String get statusConnecting => '연결하고 첫 번째 세그먼트를 가져오는 중(레이아웃 학습 중)…';

  @override
  String statusReadingVideoStructure(String filename) {
    return '비디오 구조 읽는 중: $filename';
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
    return '버퍼링 중: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return '재생 중: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return '비디오 트랙 대기 중: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return '비디오 시작 중$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Usenet 스트림이 $seconds초 이내에 시작되지 않았습니다. 제공자 연결, 첫 번째 세그먼트 또는 NZB 콘텐츠가 응답하지 않을 수 있습니다.';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return '$seconds초 이내에 비디오를 인식할 수 없었습니다. NZB에 직접 비디오 대신 멀티파트 아카이브/PAR2가 포함되어 있거나, 세그먼트가 누락되었거나, 스트림을 읽을 수 없을 수 있습니다.';
  }

  @override
  String get engineBadgeDiskCacheOff => '디스크 캐시 끔';

  @override
  String get engineBadgeSdrSafePath => 'SDR 안전 경로';

  @override
  String errorControlFailed(String error) {
    return '컨트롤을 적용할 수 없습니다: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return '줌을 적용할 수 없습니다: $error';
  }

  @override
  String get errorPipUnavailable => '이 플랫폼에서는 PiP를 사용할 수 없습니다.';

  @override
  String get fileTypeSubtitles => '자막';

  @override
  String get fileTypeAudioFiles => '오디오 파일';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds초 뒤로';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds초 앞으로';
  }

  @override
  String get cancelCanvasEditing => '캔버스 편집 취소';

  @override
  String get resetCanvas => '캔버스 초기화';

  @override
  String get subtitleControls => '자막 컨트롤';

  @override
  String get loopSetA => 'A 지점 설정';

  @override
  String get loopSetB => 'B 지점 설정';

  @override
  String get loopClear => 'A–B 반복 해제';

  @override
  String get tuningMenuItem => '비디오 및 오디오 설정…';

  @override
  String get tuningDialogTitle => '비디오 및 오디오';

  @override
  String get closeTooltip => '닫기';

  @override
  String get videoPresetLabel => '비디오 프리셋';

  @override
  String get presetNatural => '자연';

  @override
  String get presetCinema => '시네마';

  @override
  String get presetVivid => '선명';

  @override
  String get gpuScalingLabel => 'GPU 스케일링';

  @override
  String get presetLowPower => '저전력';

  @override
  String get presetBalanced => '균형';

  @override
  String get presetQuality => '품질';

  @override
  String get audioPresetLabel => '오디오 프리셋';

  @override
  String get presetDialogue => '대화';

  @override
  String get presetNight => '야간';

  @override
  String get seekStepLabel => '탐색 단위';

  @override
  String get periodicInfoLabel => '주기적 정보';

  @override
  String get secondsUnitShort => '초';

  @override
  String get audioSyncLabel => '오디오 동기화';

  @override
  String get audioEarlierTooltip => '오디오를 0.1초 앞당기기';

  @override
  String get audioLaterTooltip => '오디오를 0.1초 늦추기';

  @override
  String get decodingLabel => '디코딩';

  @override
  String get decodingHardware => '하드웨어';

  @override
  String get decodingSoftware => '소프트웨어';

  @override
  String get dynamicRangeLabel => '다이내믹 레인지';

  @override
  String get hdrInfoText =>
      '콘텐츠에 포함된 형식만 선택할 수 있으며 나머지는 비활성화됩니다. SDR을 선택하면 HDR 콘텐츠가 bt.709로 톤 매핑됩니다(BT.2390 + peak detect). HDR10+는 libmpv가 동적 메타데이터를 감지할 수 없어 비활성화되며, Dolby Vision은 HDR10 베이스 레이어를 포함하는 프로필에서 지원됩니다.';

  @override
  String get doneLabel => '완료';

  @override
  String get videoPreparing => '비디오 준비 중…';

  @override
  String get dvReshapeApplying => 'Dolby Vision 색 보정을 적용하는 중…';

  @override
  String get dvReshapeActiveHw => 'Dolby Vision 색 보정 활성화됨 (하드웨어 디코딩)';

  @override
  String get dvReshapeActiveSw => 'Dolby Vision 색 보정 활성화됨 (소프트웨어 디코딩)';

  @override
  String get dvReshapeFailed =>
      '이 기기에서 Dolby Vision 색 보정을 시작할 수 없습니다. 자세히 보려면 탭하세요.';

  @override
  String get dvReshapeFailedShort =>
      'Dolby Vision 색 보정을 시작할 수 없습니다 — 자세한 내용은 고급 설정에서 확인하세요.';

  @override
  String get dvReshapeDiagnosticsTitle => 'DV 보정 진단';

  @override
  String get dvReshapeDiagnosticsEmpty => '필터에 대한 엔진 로그가 캡처되지 않았습니다.';

  @override
  String get errFormatNotRecognized =>
      '미디어 형식을 인식할 수 없습니다. NZB가 직접 비디오 대신 아카이브나 PAR2 복구 데이터를 포함하고 있을 수 있습니다.';

  @override
  String get errLocalStreamUnreadable =>
      '로컬 비디오 스트림을 읽을 수 없습니다. Usenet 세그먼트가 누락되었거나 연결이 끊어졌을 수 있습니다.';

  @override
  String get errDecoderFailed => '비디오 또는 오디오 디코더가 스트림을 열 수 없습니다.';

  @override
  String get errPlayerGeneric => '플레이어가 스트림을 열 수 없습니다.';

  @override
  String get errNoMpvDetail => 'libmpv가 세부 정보를 제공하지 않았습니다.';

  @override
  String get errNoEngineDetail => '스트리밍 엔진이 세부 정보를 제공하지 않았습니다.';

  @override
  String technicalDetail(String detail) {
    return '기술 세부 정보: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Usenet 제공업체의 동시 연결 한도에 도달했습니다. 다른 활성 세션을 닫거나 잠시 후 다시 시도하세요. 계속되면 앱의 연결 수를 요금제 한도로 줄이세요.';

  @override
  String get errAuthFailed =>
      'Usenet 인증에 실패했습니다. 제공업체 설정의 사용자 이름과 비밀번호를 확인하세요.';

  @override
  String get errRarEncrypted =>
      'RAR 아카이브가 암호화되어 있습니다. 비밀번호로 보호된 RAR 릴리스는 지원되지 않습니다. 암호화 없이 패키징된 릴리스(STORE)를 선택하세요.';

  @override
  String get err7zPassword =>
      '7z 아카이브의 비밀번호가 없거나 유효하지 않습니다. 메타데이터에 비밀번호가 포함된 NZB를 선택하세요.';

  @override
  String get errArchiveCompressed =>
      '이 아카이브는 압축되어 있습니다. 즉시 재생하려면 비압축(COPY/STORE, 7z/RAR)으로 패키징된 릴리스가 필요합니다.';

  @override
  String get errArchiveSolid =>
      '이 아카이브는 솔리드 구조입니다. 임의 탐색에는 비솔리드 STORE로 패키징된 릴리스가 필요합니다.';

  @override
  String get errRar4 =>
      '이 RAR 아카이브는 구형(RAR4 이하) 형식을 사용합니다. RAR5 STORE 릴리스만 재생할 수 있습니다.';

  @override
  String get errSplitArchiveBroken =>
      '멀티파트 아카이브(7z/RAR)가 불완전하거나 손상되었습니다. 모든 볼륨과 세그먼트를 포함하는 완전한 NZB를 선택하세요.';

  @override
  String get errMissingSegments =>
      'NZB가 불완전하거나 손상되었습니다: 필요한 Usenet 세그먼트를 모두 찾을 수 없습니다. 이 릴리스에는 완전한 다른 NZB를 선택하세요.';

  @override
  String get errConnectionFailed =>
      'Usenet 제공업체에 연결할 수 없습니다. 인터넷 연결, 서버 주소, 포트 및 제공업체 도달 가능성을 확인하세요.';

  @override
  String get errNzbUnreadable =>
      'NZB 파일을 읽을 수 없거나 손상되었습니다. 유효하고 완전한 NZB 파일을 선택하세요.';

  @override
  String get errArchiveNotPlayable =>
      'NZB 내부의 아카이브(7z/RAR)를 재생할 수 없거나 구조가 손상되었습니다. 완전한 STORE 릴리스를 선택하세요.';

  @override
  String get errNoPlayableMedia =>
      'NZB에서 지원되는 비디오 스트림을 찾을 수 없습니다. 직접 미디어 또는 지원되는 STORE 아카이브가 포함된 릴리스를 선택하세요.';

  @override
  String get errStreamStartupGeneric =>
      '스트림을 시작할 수 없습니다. NZB 내용과 제공업체 연결을 확인하세요.';
}
