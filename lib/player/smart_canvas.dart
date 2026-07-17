import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Bir video karesi üzerindeki normalize kırpma alanı.
///
/// Koordinatlar kaynak görüntünün genişlik ve yüksekliğine göre `0..1`
/// aralığındadır. Model bilerek geçersiz/geçici değerleri de taşıyabilir;
/// kullanıcı etkileşiminden önce [clampCanvasCrop] ile güvenli alana alınır.
@immutable
class CanvasCrop {
  const CanvasCrop({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const CanvasCrop.full() : left = 0, top = 0, right = 1, bottom = 1;

  factory CanvasCrop.fromRect(Rect rect) => CanvasCrop(
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  Offset get center => Offset((left + right) / 2, (top + bottom) / 2);
  Rect get rect => Rect.fromLTRB(left, top, right, bottom);

  CanvasCrop copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => CanvasCrop(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasCrop &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'CanvasCrop(left: $left, top: $top, right: $right, bottom: $bottom)';
}

enum CanvasCorner { topLeft, topRight, bottomLeft, bottomRight }

@immutable
class CanvasAspectRatioPreset {
  const CanvasAspectRatioPreset(this.label, this.value);

  final String label;
  final double value;
}

const commonCanvasAspectRatios = <CanvasAspectRatioPreset>[
  CanvasAspectRatioPreset('1:1', 1),
  CanvasAspectRatioPreset('4:3', 4 / 3),
  CanvasAspectRatioPreset('16:10', 16 / 10),
  CanvasAspectRatioPreset('16:9', 16 / 9),
  CanvasAspectRatioPreset('1.85:1', 1.85),
  CanvasAspectRatioPreset('2:1', 2),
  CanvasAspectRatioPreset('2.35:1', 2.35),
  CanvasAspectRatioPreset('2.39:1', 2.39),
];

const double defaultMinimumCanvasCropExtent = 0.08;
const double defaultCanvasRatioSnapTolerance = 0.035;

/// [crop] alanını kaynak görüntünün sınırlarına ve minimum boyuta sıkıştırır.
///
/// Minimum boyut iki eksende de normalize kaynak boyutunun oranıdır. Kenarlar
/// ters verilmişse önce sıralanır; küçük alan merkezinin çevresinde büyütülür.
CanvasCrop clampCanvasCrop(
  CanvasCrop crop, {
  double minimumExtent = defaultMinimumCanvasCropExtent,
}) {
  _validateCrop(crop);
  _validateMinimumExtent(minimumExtent);

  var left = math.min(crop.left, crop.right).clamp(0.0, 1.0).toDouble();
  var right = math.max(crop.left, crop.right).clamp(0.0, 1.0).toDouble();
  var top = math.min(crop.top, crop.bottom).clamp(0.0, 1.0).toDouble();
  var bottom = math.max(crop.top, crop.bottom).clamp(0.0, 1.0).toDouble();

  (left, right) = _expandToMinimum(left, right, minimumExtent);
  (top, bottom) = _expandToMinimum(top, bottom, minimumExtent);

  return CanvasCrop(left: left, top: top, right: right, bottom: bottom);
}

/// Normalize kırpmanın gerçek piksel en-boy oranını döndürür.
double canvasCropAspectRatio(
  CanvasCrop crop, {
  required double sourceAspectRatio,
}) {
  _validateSourceAspectRatio(sourceAspectRatio);
  final safe = clampCanvasCrop(crop, minimumExtent: 0.000001);
  return sourceAspectRatio * safe.width / safe.height;
}

/// Kırpmaya tolerans içinde en yakın yaygın oranı bulur.
///
/// Tolerans oransal/logaritmik farktır; böylece geniş ve dar oranlar aynı
/// göreli hassasiyetle karşılaştırılır.
CanvasAspectRatioPreset? nearestCommonCanvasAspectRatio(
  CanvasCrop crop, {
  required double sourceAspectRatio,
  double tolerance = defaultCanvasRatioSnapTolerance,
}) {
  if (!tolerance.isFinite || tolerance < 0) {
    throw ArgumentError.value(tolerance, 'tolerance', 'Negatif olamaz.');
  }
  final ratio = canvasCropAspectRatio(
    crop,
    sourceAspectRatio: sourceAspectRatio,
  );

  CanvasAspectRatioPreset? nearest;
  var nearestDistance = double.infinity;
  for (final preset in commonCanvasAspectRatios) {
    final distance = (math.log(ratio / preset.value)).abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = preset;
    }
  }
  return nearestDistance <= tolerance ? nearest : null;
}

/// UI'da gösterilecek kısa kırpma oranı etiketi.
String canvasCropRatioLabel(
  CanvasCrop crop, {
  required double sourceAspectRatio,
}) {
  final preset = nearestCommonCanvasAspectRatio(
    crop,
    sourceAspectRatio: sourceAspectRatio,
    tolerance: 0.006,
  );
  if (preset != null) return preset.label;
  final ratio = canvasCropAspectRatio(
    crop,
    sourceAspectRatio: sourceAspectRatio,
  );
  return '${ratio.toStringAsFixed(2)}:1';
}

/// Bir köşeyi normalize [delta] kadar sürükler, sınırlar ve yakın ortak orana
/// yakalar. Karşı köşe sabit kalır.
CanvasCrop dragCanvasCorner({
  required CanvasCrop crop,
  required CanvasCorner corner,
  required Offset delta,
  required double sourceAspectRatio,
  double minimumExtent = defaultMinimumCanvasCropExtent,
  double snapTolerance = defaultCanvasRatioSnapTolerance,
}) {
  _validateSourceAspectRatio(sourceAspectRatio);
  _validateMinimumExtent(minimumExtent);
  if (!delta.dx.isFinite || !delta.dy.isFinite) {
    throw ArgumentError.value(delta, 'delta', 'Sonlu olmalı.');
  }
  if (!snapTolerance.isFinite || snapTolerance < 0) {
    throw ArgumentError.value(
      snapTolerance,
      'snapTolerance',
      'Negatif olamaz.',
    );
  }

  final safe = clampCanvasCrop(crop, minimumExtent: minimumExtent);
  final raw = switch (corner) {
    CanvasCorner.topLeft => safe.copyWith(
      left: (safe.left + delta.dx)
          .clamp(0.0, safe.right - minimumExtent)
          .toDouble(),
      top: (safe.top + delta.dy)
          .clamp(0.0, safe.bottom - minimumExtent)
          .toDouble(),
    ),
    CanvasCorner.topRight => safe.copyWith(
      right: (safe.right + delta.dx)
          .clamp(safe.left + minimumExtent, 1.0)
          .toDouble(),
      top: (safe.top + delta.dy)
          .clamp(0.0, safe.bottom - minimumExtent)
          .toDouble(),
    ),
    CanvasCorner.bottomLeft => safe.copyWith(
      left: (safe.left + delta.dx)
          .clamp(0.0, safe.right - minimumExtent)
          .toDouble(),
      bottom: (safe.bottom + delta.dy)
          .clamp(safe.top + minimumExtent, 1.0)
          .toDouble(),
    ),
    CanvasCorner.bottomRight => safe.copyWith(
      right: (safe.right + delta.dx)
          .clamp(safe.left + minimumExtent, 1.0)
          .toDouble(),
      bottom: (safe.bottom + delta.dy)
          .clamp(safe.top + minimumExtent, 1.0)
          .toDouble(),
    ),
  };

  final preset = nearestCommonCanvasAspectRatio(
    raw,
    sourceAspectRatio: sourceAspectRatio,
    tolerance: snapTolerance,
  );
  if (preset == null) return raw;

  return _snapDraggedCorner(
        raw,
        corner: corner,
        sourceAspectRatio: sourceAspectRatio,
        targetAspectRatio: preset.value,
        minimumExtent: minimumExtent,
      ) ??
      raw;
}

/// Kaynak görüntünün [viewport] içinde `BoxFit.contain` ile kapladığı alan.
Rect fittedCanvasRect(Size viewport, {required double sourceAspectRatio}) {
  _validateSourceAspectRatio(sourceAspectRatio);
  if (viewport.width <= 0 || viewport.height <= 0) return Rect.zero;

  late final Size fitted;
  if (viewport.aspectRatio > sourceAspectRatio) {
    fitted = Size(viewport.height * sourceAspectRatio, viewport.height);
  } else {
    fitted = Size(viewport.width, viewport.width / sourceAspectRatio);
  }
  return Alignment.center.inscribe(fitted, Offset.zero & viewport);
}

/// Normalize [crop] alanını ekrandaki kaynak görüntü alanına dönüştürür.
Rect canvasCropRect(CanvasCrop crop, Rect sourceRect) {
  final safe = clampCanvasCrop(crop, minimumExtent: 0.000001);
  return Rect.fromLTRB(
    sourceRect.left + safe.left * sourceRect.width,
    sourceRect.top + safe.top * sourceRect.height,
    sourceRect.left + safe.right * sourceRect.width,
    sourceRect.top + safe.bottom * sourceRect.height,
  );
}

CanvasCrop? _snapDraggedCorner(
  CanvasCrop crop, {
  required CanvasCorner corner,
  required double sourceAspectRatio,
  required double targetAspectRatio,
  required double minimumExtent,
}) {
  final normalizedTarget = targetAspectRatio / sourceAspectRatio;
  final widthFromHeight = crop.height * normalizedTarget;
  final heightFromWidth = crop.width / normalizedTarget;

  final widthCandidate = _replaceMovingWidth(
    crop,
    corner: corner,
    width: widthFromHeight,
  );
  final heightCandidate = _replaceMovingHeight(
    crop,
    corner: corner,
    height: heightFromWidth,
  );

  final candidates = <CanvasCrop>[
    if (_isValidCandidate(widthCandidate, minimumExtent)) widthCandidate,
    if (_isValidCandidate(heightCandidate, minimumExtent)) heightCandidate,
  ];
  if (candidates.isEmpty) return null;

  CanvasCrop best = candidates.first;
  var bestDistance = _movingCornerDistance(
    crop,
    best,
    corner: corner,
    sourceAspectRatio: sourceAspectRatio,
  );
  for (final candidate in candidates.skip(1)) {
    final distance = _movingCornerDistance(
      crop,
      candidate,
      corner: corner,
      sourceAspectRatio: sourceAspectRatio,
    );
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

CanvasCrop _replaceMovingWidth(
  CanvasCrop crop, {
  required CanvasCorner corner,
  required double width,
}) => switch (corner) {
  CanvasCorner.topLeft ||
  CanvasCorner.bottomLeft => crop.copyWith(left: crop.right - width),
  CanvasCorner.topRight ||
  CanvasCorner.bottomRight => crop.copyWith(right: crop.left + width),
};

CanvasCrop _replaceMovingHeight(
  CanvasCrop crop, {
  required CanvasCorner corner,
  required double height,
}) => switch (corner) {
  CanvasCorner.topLeft ||
  CanvasCorner.topRight => crop.copyWith(top: crop.bottom - height),
  CanvasCorner.bottomLeft ||
  CanvasCorner.bottomRight => crop.copyWith(bottom: crop.top + height),
};

bool _isValidCandidate(CanvasCrop crop, double minimumExtent) =>
    crop.left >= 0 &&
    crop.top >= 0 &&
    crop.right <= 1 &&
    crop.bottom <= 1 &&
    crop.width >= minimumExtent &&
    crop.height >= minimumExtent;

double _movingCornerDistance(
  CanvasCrop before,
  CanvasCrop after, {
  required CanvasCorner corner,
  required double sourceAspectRatio,
}) {
  final beforePoint = _cornerPoint(before, corner);
  final afterPoint = _cornerPoint(after, corner);
  final dx = (afterPoint.dx - beforePoint.dx) * sourceAspectRatio;
  final dy = afterPoint.dy - beforePoint.dy;
  return dx * dx + dy * dy;
}

Offset _cornerPoint(CanvasCrop crop, CanvasCorner corner) => switch (corner) {
  CanvasCorner.topLeft => Offset(crop.left, crop.top),
  CanvasCorner.topRight => Offset(crop.right, crop.top),
  CanvasCorner.bottomLeft => Offset(crop.left, crop.bottom),
  CanvasCorner.bottomRight => Offset(crop.right, crop.bottom),
};

(double, double) _expandToMinimum(
  double lower,
  double upper,
  double minimumExtent,
) {
  if (upper - lower >= minimumExtent) return (lower, upper);
  final center = (lower + upper) / 2;
  lower = center - minimumExtent / 2;
  upper = center + minimumExtent / 2;
  if (lower < 0) {
    upper -= lower;
    lower = 0;
  }
  if (upper > 1) {
    lower -= upper - 1;
    upper = 1;
  }
  return (lower, upper);
}

void _validateCrop(CanvasCrop crop) {
  if (!crop.left.isFinite ||
      !crop.top.isFinite ||
      !crop.right.isFinite ||
      !crop.bottom.isFinite) {
    throw ArgumentError.value(crop, 'crop', 'Koordinatlar sonlu olmalı.');
  }
}

void _validateMinimumExtent(double minimumExtent) {
  if (!minimumExtent.isFinite || minimumExtent <= 0 || minimumExtent > 1) {
    throw ArgumentError.value(
      minimumExtent,
      'minimumExtent',
      '0 ile 1 arasında olmalı.',
    );
  }
}

void _validateSourceAspectRatio(double sourceAspectRatio) {
  if (!sourceAspectRatio.isFinite || sourceAspectRatio <= 0) {
    throw ArgumentError.value(
      sourceAspectRatio,
      'sourceAspectRatio',
      'Pozitif ve sonlu olmalı.',
    );
  }
}
