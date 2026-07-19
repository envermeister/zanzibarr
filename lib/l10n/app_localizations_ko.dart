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
}
