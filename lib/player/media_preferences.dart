import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal persistence surface used by [MediaPreferencesStore].
///
/// Keeping this interface independent from the platform storage makes the
/// preference rules testable without touching Keychain or Keystore.
abstract interface class PlayerPreferenceStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [PlayerPreferenceStorage] backed by the application's secure key-value
/// storage.
///
/// These preferences do not contain credentials. The existing secure storage
/// is reused only as a cross-platform persistence backend.
class FlutterSecurePlayerPreferenceStorage implements PlayerPreferenceStorage {
  FlutterSecurePlayerPreferenceStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A crop rectangle expressed in normalized video coordinates.
///
/// Every edge is in the inclusive 0–1 range. Invalid or empty rectangles are
/// replaced with [fullFrame].
class NormalizedCropRect {
  const NormalizedCropRect._({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory NormalizedCropRect({
    double left = 0,
    double top = 0,
    double right = 1,
    double bottom = 1,
  }) {
    final safeLeft = _finiteOr(left, 0).clamp(0.0, 1.0).toDouble();
    final safeTop = _finiteOr(top, 0).clamp(0.0, 1.0).toDouble();
    final safeRight = _finiteOr(right, 1).clamp(0.0, 1.0).toDouble();
    final safeBottom = _finiteOr(bottom, 1).clamp(0.0, 1.0).toDouble();

    if (safeLeft >= safeRight || safeTop >= safeBottom) {
      return fullFrame;
    }
    return NormalizedCropRect._(
      left: safeLeft,
      top: safeTop,
      right: safeRight,
      bottom: safeBottom,
    );
  }

  static const fullFrame = NormalizedCropRect._(
    left: 0,
    top: 0,
    right: 1,
    bottom: 1,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  Map<String, Object> toJson() => <String, Object>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  static NormalizedCropRect fromJson(Object? value) {
    if (value is! Map) return fullFrame;
    final left = _finiteNumber(value['left']);
    final top = _finiteNumber(value['top']);
    final right = _finiteNumber(value['right']);
    final bottom = _finiteNumber(value['bottom']);
    if (left == null || top == null || right == null || bottom == null) {
      return fullFrame;
    }
    return NormalizedCropRect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedCropRect &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// A normalized two-dimensional value used for canvas alignment and pan.
class NormalizedVector2 {
  const NormalizedVector2._(this.x, this.y);

  factory NormalizedVector2({double x = 0, double y = 0}) =>
      NormalizedVector2._(
        _finiteOr(x, 0).clamp(-1.0, 1.0).toDouble(),
        _finiteOr(y, 0).clamp(-1.0, 1.0).toDouble(),
      );

  static const center = NormalizedVector2._(0, 0);

  final double x;
  final double y;

  Map<String, Object> toJson() => <String, Object>{'x': x, 'y': y};

  static NormalizedVector2 fromJson(Object? value) {
    if (value is! Map) return center;
    final x = _finiteNumber(value['x']);
    final y = _finiteNumber(value['y']);
    if (x == null || y == null) return center;
    return NormalizedVector2(x: x, y: y);
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedVector2 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Non-secret, per-media playback preferences.
///
/// The public constructor sanitizes every value before it can be persisted.
/// Preset strings are stable identifiers rather than user-facing labels.
class MediaPreferences {
  factory MediaPreferences({
    NormalizedCropRect crop = NormalizedCropRect.fullFrame,
    double? aspectRatio,
    NormalizedVector2 alignment = NormalizedVector2.center,
    NormalizedVector2 pan = NormalizedVector2.center,
    int seekStepSeconds = defaultSeekStepSeconds,
    Duration? periodicInfoInterval,
    String videoPreset = defaultVideoPreset,
    String audioPreset = defaultAudioPreset,
    String upscalePreset = defaultUpscalePreset,
    double subtitleScale = defaultSubtitleScale,
    double subtitlePosition = defaultSubtitlePosition,
    double subtitleDelaySeconds = 0,
    double audioDelaySeconds = 0,
  }) => MediaPreferences._(
    crop: crop,
    aspectRatio: _sanitizeAspectRatio(aspectRatio),
    alignment: alignment,
    pan: pan,
    seekStepSeconds: seekStepSeconds
        .clamp(minimumSeekStepSeconds, maximumSeekStepSeconds)
        .toInt(),
    periodicInfoInterval: _sanitizeInfoInterval(periodicInfoInterval),
    videoPreset: _sanitizePreset(videoPreset, defaultVideoPreset),
    audioPreset: _sanitizePreset(audioPreset, defaultAudioPreset),
    upscalePreset: _sanitizePreset(upscalePreset, defaultUpscalePreset),
    subtitleScale: _finiteOr(
      subtitleScale,
      defaultSubtitleScale,
    ).clamp(minimumSubtitleScale, maximumSubtitleScale).toDouble(),
    subtitlePosition: _finiteOr(
      subtitlePosition,
      defaultSubtitlePosition,
    ).clamp(minimumSubtitlePosition, maximumSubtitlePosition).toDouble(),
    subtitleDelaySeconds: _finiteOr(
      subtitleDelaySeconds,
      0,
    ).clamp(-maximumDelaySeconds, maximumDelaySeconds).toDouble(),
    audioDelaySeconds: _finiteOr(
      audioDelaySeconds,
      0,
    ).clamp(-maximumDelaySeconds, maximumDelaySeconds).toDouble(),
  );

  const MediaPreferences._({
    required this.crop,
    required this.aspectRatio,
    required this.alignment,
    required this.pan,
    required this.seekStepSeconds,
    required this.periodicInfoInterval,
    required this.videoPreset,
    required this.audioPreset,
    required this.upscalePreset,
    required this.subtitleScale,
    required this.subtitlePosition,
    required this.subtitleDelaySeconds,
    required this.audioDelaySeconds,
  });

  static const schemaVersion = 1;
  static const minimumSeekStepSeconds = 1;
  static const maximumSeekStepSeconds = 600;
  static const defaultSeekStepSeconds = 1;
  static const minimumPeriodicInfoInterval = Duration(milliseconds: 250);
  static const maximumPeriodicInfoInterval = Duration(minutes: 1);
  static const defaultVideoPreset = 'auto';
  static const defaultAudioPreset = 'auto';
  static const defaultUpscalePreset = 'off';
  static const minimumSubtitleScale = 0.0;
  static const maximumSubtitleScale = 100.0;
  static const defaultSubtitleScale = 1.0;
  static const minimumSubtitlePosition = 0.0;
  static const maximumSubtitlePosition = 150.0;
  static const defaultSubtitlePosition = 100.0;
  static const maximumDelaySeconds = 600.0;

  static final RegExp _presetPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$');

  final NormalizedCropRect crop;
  final double? aspectRatio;
  final NormalizedVector2 alignment;
  final NormalizedVector2 pan;
  final int seekStepSeconds;

  /// `null` means that periodic playback information is disabled.
  final Duration? periodicInfoInterval;

  final String videoPreset;
  final String audioPreset;
  final String upscalePreset;
  final double subtitleScale;
  final double subtitlePosition;
  final double subtitleDelaySeconds;
  final double audioDelaySeconds;

  bool get periodicInfoEnabled => periodicInfoInterval != null;

  static MediaPreferences defaults() => MediaPreferences();

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'crop': crop.toJson(),
    'aspectRatio': aspectRatio,
    'alignment': alignment.toJson(),
    'pan': pan.toJson(),
    'seekStepSeconds': seekStepSeconds,
    'periodicInfoIntervalMs': periodicInfoInterval?.inMilliseconds,
    'videoPreset': videoPreset,
    'audioPreset': audioPreset,
    'upscalePreset': upscalePreset,
    'subtitleScale': subtitleScale,
    'subtitlePosition': subtitlePosition,
    'subtitleDelaySeconds': subtitleDelaySeconds,
    'audioDelaySeconds': audioDelaySeconds,
  };

  String encode() => jsonEncode(toJson());

  /// Returns defaults for malformed JSON, unsupported schema versions or
  /// structurally invalid values. Individual numeric values are sanitized by
  /// the public constructor.
  static MediaPreferences decodeOrDefault(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map || value['schemaVersion'] != schemaVersion) {
        return defaults();
      }

      final intervalValue = value['periodicInfoIntervalMs'];
      Duration? interval;
      if (intervalValue != null) {
        if (intervalValue is! num || !intervalValue.toDouble().isFinite) {
          return defaults();
        }
        interval = Duration(milliseconds: intervalValue.toInt());
      }

      return MediaPreferences(
        crop: NormalizedCropRect.fromJson(value['crop']),
        aspectRatio: _finiteNumber(value['aspectRatio']),
        alignment: NormalizedVector2.fromJson(value['alignment']),
        pan: NormalizedVector2.fromJson(value['pan']),
        seekStepSeconds: _integerOr(
          value['seekStepSeconds'],
          defaultSeekStepSeconds,
        ),
        periodicInfoInterval: interval,
        videoPreset: _stringOr(value['videoPreset'], defaultVideoPreset),
        audioPreset: _stringOr(value['audioPreset'], defaultAudioPreset),
        upscalePreset: _stringOr(value['upscalePreset'], defaultUpscalePreset),
        subtitleScale: _numberOr(value['subtitleScale'], defaultSubtitleScale),
        subtitlePosition: _numberOr(
          value['subtitlePosition'],
          defaultSubtitlePosition,
        ),
        subtitleDelaySeconds: _numberOr(value['subtitleDelaySeconds'], 0),
        audioDelaySeconds: _numberOr(value['audioDelaySeconds'], 0),
      );
    } on FormatException {
      return defaults();
    } on TypeError {
      return defaults();
    }
  }

  static double? _sanitizeAspectRatio(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    return value.clamp(0.1, 10.0).toDouble();
  }

  static Duration? _sanitizeInfoInterval(Duration? value) {
    if (value == null) return null;
    final milliseconds = value.inMilliseconds.clamp(
      minimumPeriodicInfoInterval.inMilliseconds,
      maximumPeriodicInfoInterval.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds.toInt());
  }

  static String _sanitizePreset(String value, String fallback) =>
      _presetPattern.hasMatch(value) ? value : fallback;

  @override
  bool operator ==(Object other) =>
      other is MediaPreferences &&
      crop == other.crop &&
      aspectRatio == other.aspectRatio &&
      alignment == other.alignment &&
      pan == other.pan &&
      seekStepSeconds == other.seekStepSeconds &&
      periodicInfoInterval == other.periodicInfoInterval &&
      videoPreset == other.videoPreset &&
      audioPreset == other.audioPreset &&
      upscalePreset == other.upscalePreset &&
      subtitleScale == other.subtitleScale &&
      subtitlePosition == other.subtitlePosition &&
      subtitleDelaySeconds == other.subtitleDelaySeconds &&
      audioDelaySeconds == other.audioDelaySeconds;

  @override
  int get hashCode => Object.hash(
    crop,
    aspectRatio,
    alignment,
    pan,
    seekStepSeconds,
    periodicInfoInterval,
    videoPreset,
    audioPreset,
    upscalePreset,
    subtitleScale,
    subtitlePosition,
    subtitleDelaySeconds,
    audioDelaySeconds,
  );
}

/// Persists [MediaPreferences] under a path-free per-media namespace.
class MediaPreferencesStore {
  MediaPreferencesStore({PlayerPreferenceStorage? storage})
    : _storage = storage ?? FlutterSecurePlayerPreferenceStorage();

  final PlayerPreferenceStorage _storage;

  static const storageKeyPrefix = 'usenews.player_preferences.';
  static final BigInt _fnvOffsetBasis64 = BigInt.parse(
    'cbf29ce484222325',
    radix: 16,
  );
  static final BigInt _fnvPrime64 = BigInt.parse('100000001b3', radix: 16);
  static final BigInt _uint64Mask = BigInt.parse('ffffffffffffffff', radix: 16);

  /// Builds a deterministic namespace without embedding the NZB path in it.
  static String storageKeyFor(String nzbPath) {
    var hash = _fnvOffsetBasis64;
    for (final byte in utf8.encode(nzbPath)) {
      hash ^= BigInt.from(byte);
      hash = (hash * _fnvPrime64) & _uint64Mask;
    }
    final digest = hash.toRadixString(16).padLeft(16, '0');
    return '$storageKeyPrefix$digest';
  }

  Future<MediaPreferences> load(String nzbPath) async {
    final encoded = await _storage.read(storageKeyFor(nzbPath));
    if (encoded == null) return MediaPreferences.defaults();
    return MediaPreferences.decodeOrDefault(encoded);
  }

  Future<void> save(String nzbPath, MediaPreferences preferences) =>
      _storage.write(storageKeyFor(nzbPath), preferences.encode());

  Future<void> clear(String nzbPath) => _storage.delete(storageKeyFor(nzbPath));
}

double _finiteOr(double value, double fallback) =>
    value.isFinite ? value : fallback;

double? _finiteNumber(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

double _numberOr(Object? value, double fallback) =>
    _finiteNumber(value) ?? fallback;

int _integerOr(Object? value, int fallback) {
  if (value is! num || !value.toDouble().isFinite) return fallback;
  return value.toInt();
}

String _stringOr(Object? value, String fallback) =>
    value is String ? value : fallback;
