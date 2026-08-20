import 'dart:async';

import 'package:zanzibarr/l10n/app_localizations.dart';

/// Oynatıcının medya yapısını tanımasını sonsuza kadar beklememek için
/// yeniden kurulabilir, dispose-güvenli bir zaman aşımı bekçisi.
class PlaybackStartupGuard {
  PlaybackStartupGuard(this.timeout);

  final Duration timeout;
  Timer? _timer;
  bool _disposed = false;

  bool get isArmed => _timer?.isActive ?? false;

  void arm(void Function() onTimeout, {Duration? after}) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(after ?? timeout, () {
      _timer = null;
      if (!_disposed) onTimeout();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

/// libmpv'nin teknik hata metnini kullanıcıya yol gösteren kısa bir açıklamaya
/// çevirir. Ham ayrıntı tanılama için korunur, fakat arayüzü taşırmaması için
/// sınırlanır. Açıklamalar uygulamanın yerelleştirmesine uyar.
String describePlayerError(String raw, AppLocalizations l10n) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final detail = normalized.isEmpty
      ? l10n.errNoMpvDetail
      : normalized.length > 400
      ? '${normalized.substring(0, 400)}…'
      : normalized;
  final lower = normalized.toLowerCase();

  if (lower.contains('failed to recognize file format') ||
      lower.contains('could not detect file format') ||
      lower.contains('no video or audio streams selected')) {
    return '${l10n.errFormatNotRecognized} ${l10n.technicalDetail(detail)}';
  }
  if (lower.startsWith('tcp:') ||
      lower.contains('http error') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset')) {
    return '${l10n.errLocalStreamUnreadable} ${l10n.technicalDetail(detail)}';
  }
  if (lower.contains('decoder') || lower.contains('codec')) {
    return '${l10n.errDecoderFailed} ${l10n.technicalDetail(detail)}';
  }
  return '${l10n.errPlayerGeneric} ${l10n.technicalDetail(detail)}';
}

/// Rust akış motorunun başlangıç hatasını, kullanıcıya ne yapabileceğini
/// söyleyen güvenli bir açıklamaya dönüştürür. Açıklamalar uygulamanın
/// yerelleştirmesine uyar.
///
/// Köprü katmanının eklediği exception sarmalayıcıları ham ayrıntıda korunur;
/// ancak kimlik bilgileri ayıklanır ve gösterilen teknik metin 400 karakterle
/// sınırlandırılır.
String describeStreamStartupError(Object raw, AppLocalizations l10n) {
  final normalized = _sanitizeStreamError(raw);
  final lower = normalized.toLowerCase();
  final detail = normalized.isEmpty
      ? l10n.errNoEngineDetail
      : normalized.length > 400
      ? '${normalized.substring(0, 400)}…'
      : normalized;

  String explanation;
  // Bazı NNTP sağlayıcıları bağlantı kotasını 502 ile döndürür. Bu yanıt,
  // üst katmanda "kimlik doğrulama başarısız" diye sarılabilse de yanlış
  // kullanıcı adı/parola anlamına gelmez; bu nedenle auth kontrolünden önce
  // sınıflandırılmalıdır.
  if (_isProviderConnectionLimit(lower)) {
    explanation = l10n.errProviderConnectionLimit;
  } else if (_containsAny(lower, const <String>[
    'kimlik doğrulama başarısız',
    'authentication failed',
    'authentication error',
    'authfailed',
    'authinfo',
    'invalid credentials',
  ])) {
    explanation = l10n.errAuthFailed;
  } else if (_containsAny(lower, const <String>[
    'rar arşivi şifreli',
    'rar archive is password-protected',
    'password-protected rar',
  ])) {
    explanation = l10n.errRarEncrypted;
  } else if (_containsAny(lower, const <String>[
    'parola korumalı 7z',
    'password metası yok',
    'password metadata',
    'missing password',
    'wrong password',
    'incorrect password',
    'no password metadata',
    'password-protected 7z',
    'does not match the rar archive',
  ])) {
    explanation = l10n.err7zPassword;
  } else if (_containsAny(lower, const <String>[
    'yalnız copy/store',
    'unsupported compression',
    'unsupportedcompression',
    '7z arşivi sıkıştırılmış',
    'rar arşivi sıkıştırılmış',
    'archive is compressed',
    'only store archives',
  ])) {
    explanation = l10n.errArchiveCompressed;
  } else if (_containsAny(lower, const <String>[
    '7z arşivi solid',
    'solid archive',
    'solidarchive',
    'non-solid store',
  ])) {
    explanation = l10n.errArchiveSolid;
  } else if (_containsAny(lower, const <String>[
    'rar4',
  ])) {
    explanation = l10n.errRar4;
  } else if (_isMissingSplitArchive(lower)) {
    explanation = l10n.errSplitArchiveBroken;
  } else if (_isMissingSegment(lower)) {
    explanation = l10n.errMissingSegments;
  } else if (_containsAny(lower, const <String>[
    'connection refused',
    'connection reset',
    'connection closed',
    'connection timed out',
    'timed out',
    'zaman aşımı',
    'dns',
    'tls',
    'certificate',
    'socket',
    'network is unreachable',
    'sunucu bağlantıyı kapattı',
    'bağlantı reddedildi',
    'bağlantı sıfırlandı',
    'g/ç hatası',
    'server closed the connection',
    'i/o error',
  ])) {
    explanation = l10n.errConnectionFailed;
  } else if (_containsAny(lower, const <String>[
    'nzb okunamadı',
    'bozuk nzb',
    'nzb kök öğesi',
    'malformed nzb',
    'could not read nzb',
    'not a regular file',
    'not valid utf-8',
    'not utf-8',
    'size limit',
  ])) {
    explanation = l10n.errNzbUnreadable;
  } else if (_containsAny(lower, const <String>[
    '7z başlığı okunamadı',
    'geçersiz 7z yerleşimi',
    '7z arşivinde oynatılabilir medya dosyası yok',
    'rar başlığı okunamadı',
    'geçersiz rar yerleşimi',
    'rar arşivinde oynatılabilir medya dosyası yok',
    'doğrudan video veya desteklenen split 7z/rar',
    'doğrudan video veya desteklenen split 7z',
    'could not read 7z header',
    'invalid 7z layout',
    'could not read rar header',
    'invalid rar layout',
    'no direct video or supported split',
  ])) {
    explanation = l10n.errArchiveNotPlayable;
  } else if (_containsAny(lower, const <String>[
    'oynatılabilir medya dosyası yok',
    'no playable media',
  ])) {
    explanation = l10n.errNoPlayableMedia;
  } else {
    explanation = l10n.errStreamStartupGeneric;
  }

  return '$explanation ${l10n.technicalDetail(detail)}';
}

bool _isMissingSplitArchive(String lower) {
  final archiveContext = _containsAny(lower, const <String>[
    'split 7z',
    'bölünmüş 7z',
    '7z cilt',
    '7z volume',
    '.7z.',
    'split rar',
    'bölünmüş rar',
    'rar cilt',
    'rar volume',
    'rar yerleşimi',
    '.rar',
    'invalid rar layout',
    'invalid 7z layout',
  ]);
  final missingOrInvalid = _containsAny(lower, const <String>[
    'eksik',
    'missing',
    'beklenirken',
    'birden fazla',
    'duplicate',
    'segment bildiriyor',
    'segment var',
    'arşiv dışı',
    'incomplete',
    'more than once',
    'expected volume',
    'but found',
    'declares',
  ]);
  return archiveContext && missingOrInvalid;
}

bool _isMissingSegment(String lower) {
  if (_containsAny(lower, const <String>[
    'article bulunamadı',
    'article not found',
    'no such article',
    'unmapped offset',
  ])) {
    return true;
  }
  if (!lower.contains('segment')) return false;
  return _containsAny(lower, const <String>[
    'eksik',
    'yok',
    'bulunamadı',
    'sırası bozuk',
    'missing',
    'not found',
    'out of order',
    'segment bildiriyor',
    'segment var',
    'declares',
  ]);
}

bool _containsAny(String value, List<String> needles) =>
    needles.any(value.contains);

bool _isProviderConnectionLimit(String lower) =>
    _containsAny(lower, const <String>[
      'too many connections',
      'connection limit exceeded',
      'connection limit reached',
      'maximum number of connections',
      'max connections exceeded',
      'concurrent connection limit',
      'eşzamanlı bağlantı sınırı',
      'bağlantı limiti aşıldı',
    ]);

String _sanitizeStreamError(Object raw) {
  var value = raw.toString();

  // URL içindeki `kullanıcı:parola@sunucu` biçimini önce ayıkla.
  value = value.replaceAllMapped(
    RegExp(
      r'([a-z][a-z0-9+.-]*://)([^/@\s:]+):([^/@\s]+)@',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}***:***@',
  );
  value = value.replaceAllMapped(
    RegExp(r'\b(authinfo\s+pass)\s+\S+', caseSensitive: false),
    (match) => '${match.group(1)} ***',
  );
  value = value.replaceAll(
    RegExp(r'\bbearer\s+[a-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer ***',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'\b(password|passwd|passphrase|parola|api[_ -]?key|token|authorization|username|user_name|kullanıcı adı|kullanici adi)\b(\s*[:=]\s*)("[^"]*"|\x27[^\x27]*\x27|[^\s,;)}\]]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}***',
  );

  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
