// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Zanzibarr';

  @override
  String get settingsTitle => '設定';

  @override
  String get appSectionTitle => 'アプリケーション';

  @override
  String get appSectionSubtitle => '言語と外観の設定はこのデバイスに保存されます。';

  @override
  String get languageLabel => '言語';

  @override
  String get themeLabel => '外観';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeLight => 'ライト';

  @override
  String get advancedSettings => '詳細設定';

  @override
  String get play => '再生';

  @override
  String get pause => '一時停止';

  @override
  String get selectNzbAndPlay => 'NZBを選択して再生';

  @override
  String get selectNzbHint => 'ファイルシステムから.nzbを開く';

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
  String get engineStarting => 'ローカル再生エンジンを準備しています…';

  @override
  String get engineStartFailed => 'ローカル再生エンジンを起動できませんでした';

  @override
  String get engineStartFailedHint => 'エンジンファイルとアプリのインストールを確認して、もう一度お試しください。';

  @override
  String get retry => '再試行';

  @override
  String errorOpenNzb(String error) {
    return 'NZBファイルを開けませんでした: $error';
  }

  @override
  String get providerSettingsTooltip => 'プロバイダー設定';

  @override
  String get backTooltip => '戻る';

  @override
  String get providerTitle => 'プロバイダー';

  @override
  String get nntpSectionTitle => 'NNTP接続';

  @override
  String get nntpSectionSubtitle => '情報はこのデバイスのセキュアなキーチェーンにのみ保存されます。';

  @override
  String get serverAddressLabel => 'サーバーアドレス';

  @override
  String get portLabel => 'ポート';

  @override
  String get connectionLimitLabel => '接続数上限';

  @override
  String get connectionLimitHint => 'プランの上限';

  @override
  String get usernameLabel => 'ユーザー名';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get passwordShowTooltip => 'パスワードを表示';

  @override
  String get passwordHideTooltip => 'パスワードを隠す';

  @override
  String get saveSecurelyLabel => '安全に保存';

  @override
  String get savingLabel => '保存中…';

  @override
  String get settingsSaved => '設定をセキュアストレージに保存しました。';

  @override
  String settingsSaveFailed(String error) {
    return '保存できませんでした: $error';
  }

  @override
  String get secureStorageUnavailable => 'セキュアストレージにアクセスできませんでした';

  @override
  String get connectionLimitWarning =>
      '接続数上限をプロバイダーのプランより高く設定すると、「接続数が多すぎます」エラーが発生する場合があります。';

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
    return '$fieldは必須です';
  }

  @override
  String validationIntegerRange(String field, int min, int max) {
    return '$fieldは$minから$maxの間で指定してください';
  }

  @override
  String get validationHostNoProtocol => 'プロトコルやポートを含めず、サーバー名のみを入力してください';

  @override
  String get validationHostInvalid => '有効なサーバー名を入力してください';

  @override
  String get closePlayer => 'プレーヤーを閉じる';

  @override
  String get fullscreen => '全画面';

  @override
  String get subtitleControlsTooltip => '画面上の字幕コントロール';

  @override
  String get miniPlayer => 'ミニプレーヤー';

  @override
  String get exitMiniPlayer => 'ミニプレーヤーを終了';

  @override
  String get previousFrame => '前のフレーム';

  @override
  String get nextFrame => '次のフレーム';

  @override
  String get playbackSpeedTooltip => '再生速度';

  @override
  String get audioTrack => '音声トラック';

  @override
  String get subtitleTrack => '字幕トラック';

  @override
  String get muteTooltip => 'ミュート';

  @override
  String get unmuteTooltip => 'ミュート解除';

  @override
  String get loadFromFile => 'ファイルから読み込む…';

  @override
  String get auto => '自動';

  @override
  String get off => 'オフ';

  @override
  String get subtitleDecreaseTooltip => '字幕サイズを小さく';

  @override
  String get continueWatching => '続きを見る';

  @override
  String get videoFitCover => '画面いっぱいに表示';

  @override
  String get videoFitContain => '画面に合わせる';

  @override
  String get updateAvailable => 'アップデートがあります';

  @override
  String get updateNow => '今すぐ更新';

  @override
  String get updateLater => '後で';

  @override
  String get updateSkip => 'このバージョンをスキップ';

  @override
  String get updateDownloading => 'アップデートをダウンロード中…';

  @override
  String get updateOpenPage => 'ダウンロードページを開く';

  @override
  String updateFailed(String error) {
    return 'アップデートに失敗しました: $error';
  }

  @override
  String get historyRemoveTooltip => '履歴から削除';

  @override
  String historyRemaining(String time) {
    return '残り $time';
  }

  @override
  String get subtitleColor => '字幕の色';

  @override
  String get subtitleIncreaseTooltip => '字幕サイズを大きく';

  @override
  String get subtitleMoveUpTooltip => '字幕を上に移動';

  @override
  String get subtitleMoveDownTooltip => '字幕を下に移動';

  @override
  String get subtitleEarlierTooltip => '字幕を0.1秒早める';

  @override
  String get subtitleLaterTooltip => '字幕を0.1秒遅らせる';

  @override
  String get closeSubtitleControlsTooltip => '字幕コントロールを閉じる';

  @override
  String get smartCanvasAreaLabel => 'Smart Canvas切り抜き範囲';

  @override
  String get smartCanvasSemanticsHint => 'ダブルタップで適用。Escapeキーでキャンセル。';

  @override
  String get smartCanvasHintText => 'ダブルタップ: 適用 · Esc: キャンセル';

  @override
  String get cropHandleTopLeft => '左上の切り抜きハンドル';

  @override
  String get cropHandleTopRight => '右上の切り抜きハンドル';

  @override
  String get cropHandleBottomLeft => '左下の切り抜きハンドル';

  @override
  String get cropHandleBottomRight => '右下の切り抜きハンドル';

  @override
  String get statusPreparing => '準備中…';

  @override
  String get engineBadgePreparing => 'ネイティブlibmpvを準備中…';

  @override
  String get errorProviderSettingsMissing =>
      'プロバイダー設定が不完全です。先に設定画面で情報を入力してください。';

  @override
  String get statusConnecting => '接続して最初のセグメントを取得しています（レイアウトを学習中）…';

  @override
  String statusReadingVideoStructure(String filename) {
    return '動画構造を読み取り中: $filename';
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
    return 'バッファリング中: $filename';
  }

  @override
  String statusPlaying(String filename) {
    return '再生中: $filename';
  }

  @override
  String statusWaitingTracks(String filename) {
    return '動画トラックを待機中: $filename';
  }

  @override
  String bufferingPercent(String percent) {
    return ' $percent%';
  }

  @override
  String statusStartingVideo(String progress, String filename) {
    return '動画を開始しています$progress: $filename';
  }

  @override
  String errorStreamStartTimeout(int seconds) {
    return 'Usenetストリームを$seconds秒以内に開始できませんでした。プロバイダー接続、最初のセグメント、またはNZBコンテンツが応答していない可能性があります。';
  }

  @override
  String errorVideoDetectTimeout(int seconds) {
    return '動画を$seconds秒以内に認識できませんでした。NZBに直接の動画ではなく複数パートのアーカイブ/PAR2が含まれているか、セグメントが欠落しているか、ストリームが読み取れない可能性があります。';
  }

  @override
  String get engineBadgeDiskCacheOff => 'ディスクキャッシュオフ';

  @override
  String get engineBadgeSdrSafePath => 'SDRセーフパス';

  @override
  String errorControlFailed(String error) {
    return 'コントロールを適用できませんでした: $error';
  }

  @override
  String errorZoomFailed(String error) {
    return 'ズームを適用できませんでした: $error';
  }

  @override
  String get errorPipUnavailable => 'Picture-in-Pictureはこのプラットフォームでは利用できません。';

  @override
  String get fileTypeSubtitles => '字幕';

  @override
  String get fileTypeAudioFiles => '音声ファイル';

  @override
  String seekBackSeconds(int seconds) {
    return '$seconds秒戻る';
  }

  @override
  String seekForwardSeconds(int seconds) {
    return '$seconds秒進む';
  }

  @override
  String get cancelCanvasEditing => 'キャンバス編集をキャンセル';

  @override
  String get resetCanvas => 'キャンバスをリセット';

  @override
  String get subtitleControls => '字幕コントロール';

  @override
  String get loopSetA => 'ポイントAを設定';

  @override
  String get loopSetB => 'ポイントBを設定';

  @override
  String get loopClear => 'A–Bループを解除';

  @override
  String get tuningMenuItem => '映像と音声の設定…';

  @override
  String get tuningDialogTitle => '映像と音声';

  @override
  String get closeTooltip => '閉じる';

  @override
  String get videoPresetLabel => '映像プリセット';

  @override
  String get presetNatural => 'ナチュラル';

  @override
  String get presetCinema => 'シネマ';

  @override
  String get presetVivid => 'ビビッド';

  @override
  String get gpuScalingLabel => 'GPUスケーリング';

  @override
  String get presetLowPower => '低消費電力';

  @override
  String get presetBalanced => 'バランス';

  @override
  String get presetQuality => '高画質';

  @override
  String get audioPresetLabel => '音声プリセット';

  @override
  String get presetDialogue => 'ダイアログ';

  @override
  String get presetNight => 'ナイト';

  @override
  String get seekStepLabel => 'シークステップ';

  @override
  String get periodicInfoLabel => '定期情報';

  @override
  String get secondsUnitShort => '秒';

  @override
  String get audioSyncLabel => '音声同期';

  @override
  String get audioEarlierTooltip => '音声を0.1秒早める';

  @override
  String get audioLaterTooltip => '音声を0.1秒遅らせる';

  @override
  String get decodingLabel => 'デコード';

  @override
  String get decodingHardware => 'ハードウェア';

  @override
  String get decodingSoftware => 'ソフトウェア';

  @override
  String get dynamicRangeLabel => 'ダイナミックレンジ';

  @override
  String get hdrInfoText =>
      'コンテンツが保持するフォーマットのみ選択でき、それ以外は無効になります。SDRを選択すると、HDRコンテンツはbt.709にトーンマッピングされます（BT.2390 + ピーク検出）。HDR10+はlibmpvが動的メタデータを検出できないため無効です。Dolby VisionはHDR10ベースレイヤーを含むプロファイルでサポートされます。';

  @override
  String get doneLabel => '完了';

  @override
  String get videoPreparing => '動画を準備中…';

  @override
  String get dvReshapeApplying => 'Dolby Vision カラー補正を適用しています…';

  @override
  String get dvReshapeActiveHw => 'Dolby Vision カラー補正が有効（ハードウェアデコード）';

  @override
  String get dvReshapeActiveSw => 'Dolby Vision カラー補正が有効（ソフトウェアデコード）';

  @override
  String get dvReshapeFailed =>
      'このデバイスで Dolby Vision カラー補正を開始できませんでした。詳細を見るにはタップしてください。';

  @override
  String get dvReshapeFailedShort =>
      'Dolby Vision カラー補正を開始できませんでした — 詳細は詳細設定にあります。';

  @override
  String get dvReshapeDiagnosticsTitle => 'DV 補正の診断';

  @override
  String get dvReshapeDiagnosticsEmpty => 'フィルターのエンジンログは記録されませんでした。';

  @override
  String get errFormatNotRecognized =>
      'メディア形式を認識できませんでした。NZB が直接の動画ではなく、アーカイブや PAR2 復旧データを含んでいる可能性があります。';

  @override
  String get errLocalStreamUnreadable =>
      'ローカル動画ストリームを読み取れませんでした。Usenet セグメントが欠けているか、接続が切れた可能性があります。';

  @override
  String get errDecoderFailed => '映像または音声のデコーダーがストリームを開けませんでした。';

  @override
  String get errPlayerGeneric => 'プレーヤーがストリームを開けませんでした。';

  @override
  String get errNoMpvDetail => 'libmpv から詳細は返されませんでした。';

  @override
  String get errNoEngineDetail => 'ストリーミングエンジンから詳細は返されませんでした。';

  @override
  String technicalDetail(String detail) {
    return '技術的な詳細: $detail';
  }

  @override
  String get errProviderConnectionLimit =>
      'Usenet プロバイダーの同時接続数の上限に達しました。他のアクティブなセッションを閉じるか、しばらくしてから再試行してください。解決しない場合は、アプリの接続数をプランの上限まで下げてください。';

  @override
  String get errAuthFailed => 'Usenet 認証に失敗しました。プロバイダー設定のユーザー名とパスワードを確認してください。';

  @override
  String get errRarEncrypted =>
      'RAR アーカイブは暗号化されています。パスワード保護された RAR リリースはサポートされていません。暗号化せずにパックされたリリース（STORE）を選んでください。';

  @override
  String get err7zPassword =>
      '7z アーカイブのパスワードがないか無効です。メタデータにパスワードを含む NZB を選んでください。';

  @override
  String get errArchiveCompressed =>
      'このアーカイブは圧縮されています。即時再生には非圧縮（COPY/STORE、7z/RAR）でパックされたリリースが必要です。';

  @override
  String get errArchiveSolid =>
      'このアーカイブは solid 構造です。ランダムシークには非 solid の STORE でパックされたリリースが必要です。';

  @override
  String get errRar4 =>
      'この RAR アーカイブは旧形式（RAR4 以前）を使っています。再生できるのは RAR5 STORE リリースのみです。';

  @override
  String get errSplitArchiveBroken =>
      'マルチパートアーカイブ（7z/RAR）が不完全か破損しています。すべてのボリュームとセグメントを含む完全な NZB を選んでください。';

  @override
  String get errMissingSegments =>
      'NZB が不完全か破損しています：必要な Usenet セグメントのすべてが見つかりません。このリリースには別の完全な NZB を選んでください。';

  @override
  String get errConnectionFailed =>
      'Usenet プロバイダーに接続できませんでした。インターネット接続、サーバーアドレス、ポート、プロバイダーの到達可能性を確認してください。';

  @override
  String get errNzbUnreadable =>
      'NZB ファイルを読み取れないか破損しています。有効で完全な NZB ファイルを選んでください。';

  @override
  String get errArchiveNotPlayable =>
      'NZB 内のアーカイブ（7z/RAR）は再生できないか、構造が破損しています。完全な STORE リリースを選んでください。';

  @override
  String get errNoPlayableMedia =>
      'NZB に対応する動画ストリームが見つかりませんでした。直接メディアまたは対応する STORE アーカイブを含むリリースを選んでください。';

  @override
  String get errStreamStartupGeneric =>
      'ストリームを開始できませんでした。NZB の内容とプロバイダー接続を確認してください。';
}
