import 'dart:async';

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
/// sınırlanır.
String describePlayerError(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final detail = normalized.isEmpty
      ? 'libmpv ayrıntı vermedi.'
      : normalized.length > 400
      ? '${normalized.substring(0, 400)}…'
      : normalized;
  final lower = normalized.toLowerCase();

  if (lower.contains('failed to recognize file format') ||
      lower.contains('could not detect file format') ||
      lower.contains('no video or audio streams selected')) {
    return 'Medya biçimi tanınamadı. NZB doğrudan bir video yerine arşiv veya '
        'PAR2 kurtarma verisi içeriyor olabilir. Teknik ayrıntı: $detail';
  }
  if (lower.startsWith('tcp:') ||
      lower.contains('http error') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset')) {
    return 'Yerel video akışı okunamadı. Bir Usenet segmenti eksik olabilir '
        'veya bağlantı kesilmiş olabilir. Teknik ayrıntı: $detail';
  }
  if (lower.contains('decoder') || lower.contains('codec')) {
    return 'Video veya ses çözücüsü akışı açamadı. Teknik ayrıntı: $detail';
  }
  return 'Oynatıcı akışı açamadı. Teknik ayrıntı: $detail';
}

/// Rust akış motorunun başlangıç hatasını, kullanıcıya ne yapabileceğini
/// söyleyen güvenli bir Türkçe açıklamaya dönüştürür.
///
/// Köprü katmanının eklediği exception sarmalayıcıları ham ayrıntıda korunur;
/// ancak kimlik bilgileri ayıklanır ve gösterilen teknik metin 400 karakterle
/// sınırlandırılır.
String describeStreamStartupError(Object raw) {
  final normalized = _sanitizeStreamError(raw);
  final lower = normalized.toLowerCase();
  final detail = normalized.isEmpty
      ? 'Akış motoru ayrıntı vermedi.'
      : normalized.length > 400
      ? '${normalized.substring(0, 400)}…'
      : normalized;

  String explanation;
  // Bazı NNTP sağlayıcıları bağlantı kotasını 502 ile döndürür. Bu yanıt,
  // üst katmanda "kimlik doğrulama başarısız" diye sarılabilse de yanlış
  // kullanıcı adı/parola anlamına gelmez; bu nedenle auth kontrolünden önce
  // sınıflandırılmalıdır.
  if (_isProviderConnectionLimit(lower)) {
    explanation =
        'Usenet sağlayıcısının eşzamanlı bağlantı sınırına ulaşıldı. Diğer '
        'aktif oturumları kapatın veya kısa süre bekleyip yeniden deneyin. '
        'Sorun sürerse uygulamadaki bağlantı sayısını plan limitinize göre '
        'düşürün.';
  } else if (_containsAny(lower, const <String>[
    'kimlik doğrulama başarısız',
    'authentication failed',
    'authentication error',
    'authfailed',
    'authinfo',
    'invalid credentials',
  ])) {
    explanation =
        'Usenet kimlik doğrulaması başarısız. Sağlayıcı ayarlarındaki '
        'kullanıcı adı ve parolayı kontrol edin.';
  } else if (_containsAny(lower, const <String>[
    'rar arşivi şifreli',
  ])) {
    explanation =
        'RAR arşivi şifreli. Parola korumalı RAR yayınları desteklenmiyor; '
        'şifresiz hazırlanmış bir STORE yayını seçin.';
  } else if (_containsAny(lower, const <String>[
    'parola korumalı 7z',
    'password metası yok',
    'password metadata',
    'missing password',
    'wrong password',
    'incorrect password',
  ])) {
    explanation =
        '7z arşivinin parolası eksik veya geçersiz. Parola bilgisini '
        'metadata içinde taşıyan doğru NZB dosyasını seçin.';
  } else if (_containsAny(lower, const <String>[
    'yalnız copy/store',
    'unsupported compression',
    'unsupportedcompression',
    '7z arşivi sıkıştırılmış',
    'rar arşivi sıkıştırılmış',
  ])) {
    explanation =
        'Bu arşiv sıkıştırılmış. Anlık oynatma için sıkıştırmasız '
        'COPY/STORE (7z/RAR) biçiminde hazırlanmış bir yayın gerekir.';
  } else if (_containsAny(lower, const <String>[
    '7z arşivi solid',
    'solid archive',
    'solidarchive',
    'non-solid store',
  ])) {
    explanation =
        'Bu arşiv solid yapıda. Rastgele ileri-geri sarma için '
        'non-solid STORE biçiminde hazırlanmış bir yayın gerekir.';
  } else if (_containsAny(lower, const <String>[
    'rar4',
  ])) {
    explanation =
        'Bu RAR arşivi eski (RAR4 veya öncesi) biçimde. Yalnız RAR5 STORE '
        'yayınları oynatılabilir.';
  } else if (_isMissingSplitArchive(lower)) {
    explanation =
        'Çok parçalı arşiv (7z/RAR) eksik veya bozuk. Tüm ciltleri ve '
        'segmentleri içeren eksiksiz bir NZB dosyası seçin.';
  } else if (_isMissingSegment(lower)) {
    explanation =
        'NZB eksik veya bozuk: gerekli Usenet segmentlerinin tamamı '
        'bulunamıyor. Bu yayın için eksiksiz başka bir NZB dosyası seçin.';
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
  ])) {
    explanation =
        'Usenet sağlayıcısına bağlanılamadı. İnternet bağlantısını, sunucu '
        'adresini, portu ve sağlayıcının erişilebilirliğini kontrol edin.';
  } else if (_containsAny(lower, const <String>[
    'nzb okunamadı',
    'bozuk nzb',
    'nzb kök öğesi',
    'malformed nzb',
  ])) {
    explanation =
        'NZB dosyası okunamadı veya yapısı bozuk. Geçerli ve eksiksiz bir '
        'NZB dosyası seçin.';
  } else if (_containsAny(lower, const <String>[
    '7z başlığı okunamadı',
    'geçersiz 7z yerleşimi',
    '7z arşivinde oynatılabilir medya dosyası yok',
    'rar başlığı okunamadı',
    'geçersiz rar yerleşimi',
    'rar arşivinde oynatılabilir medya dosyası yok',
    'doğrudan video veya desteklenen split 7z/rar',
    'doğrudan video veya desteklenen split 7z',
  ])) {
    explanation =
        'NZB içindeki arşiv (7z/RAR) oynatmaya uygun değil veya arşiv yapısı '
        'bozuk. Eksiksiz bir STORE yayını seçin.';
  } else if (_containsAny(lower, const <String>[
    'oynatılabilir medya dosyası yok',
    'no playable media',
  ])) {
    explanation =
        'NZB içinde desteklenen bir video akışı bulunamadı. Doğrudan medya '
        'veya desteklenen STORE arşivi içeren bir yayın seçin.';
  } else {
    explanation =
        'Akış başlatılamadı. NZB içeriğini ve sağlayıcı bağlantısını kontrol '
        'edin.';
  }

  return '$explanation Teknik ayrıntı: $detail';
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
  ]);
  return archiveContext && missingOrInvalid;
}

bool _isMissingSegment(String lower) {
  if (_containsAny(lower, const <String>[
    'article bulunamadı',
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
    'segment bildiriyor',
    'segment var',
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
