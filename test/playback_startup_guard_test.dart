import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/playback_startup_guard.dart';

void main() {
  testWidgets('startup guard zaman aşımında bir kez çalışır', (tester) async {
    var calls = 0;
    final guard = PlaybackStartupGuard(const Duration(seconds: 5));
    guard.arm(() => calls++);

    await tester.pump(const Duration(seconds: 4));
    expect(calls, 0);
    expect(guard.isArmed, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(guard.isArmed, isFalse);

    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
  });

  testWidgets('cancel ve dispose bekleyen zaman aşımını susturur', (
    tester,
  ) async {
    var calls = 0;
    final cancelled = PlaybackStartupGuard(const Duration(seconds: 5));
    cancelled.arm(() => calls++);
    cancelled.cancel();

    final disposed = PlaybackStartupGuard(const Duration(seconds: 5));
    disposed.arm(() => calls++);
    disposed.dispose();

    await tester.pump(const Duration(seconds: 6));
    expect(calls, 0);
    expect(cancelled.isArmed, isFalse);
    expect(disposed.isArmed, isFalse);
  });

  testWidgets('arm çağrısı tek seferlik farklı süre kullanabilir', (
    tester,
  ) async {
    var calls = 0;
    final guard = PlaybackStartupGuard(const Duration(seconds: 5));
    guard.arm(() => calls++, after: const Duration(seconds: 9));

    await tester.pump(const Duration(seconds: 5));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 1);
  });

  test('libmpv biçim hatasını arşiv/PAR2 ipucuyla açıklar', () {
    final message = describePlayerError('Failed to recognize file format.');

    expect(message, contains('Medya biçimi tanınamadı'));
    expect(message, contains('arşiv veya PAR2'));
    expect(message, contains('Failed to recognize file format'));
  });

  test('bağlantı hatasını segment veya akış sorunu olarak açıklar', () {
    final message = describePlayerError('tcp: Connection reset by peer');

    expect(message, contains('Yerel video akışı okunamadı'));
    expect(message, contains('Usenet segmenti'));
  });

  group('akış başlangıç hatası açıklaması', () {
    test('eksik segmenti bozuk NZB olarak açıklar', () {
      final message = describeStreamStartupError(
        'film.mkv dosyası 100 segment bildiriyor, NZB\x27de 81 segment var',
      );

      expect(message, contains('NZB eksik veya bozuk'));
      expect(message, contains('eksiksiz başka bir NZB'));
    });

    test('eksik split 7z cildini arşiv seti olarak açıklar', () {
      final message = describeStreamStartupError(
        'bölünmüş 7z seti film.7z için volume 002 beklenirken 003 bulundu',
      );

      expect(message, contains('Çok parçalı arşiv (7z/RAR) eksik veya bozuk'));
      expect(message, contains('Tüm ciltleri'));
    });

    test('eksik split RAR cildini arşiv seti olarak açıklar', () {
      final message = describeStreamStartupError(
        'bölünmüş RAR seti movie için volume 2 beklenirken 3 bulundu',
      );

      expect(message, contains('Çok parçalı arşiv (7z/RAR) eksik veya bozuk'));
    });

    test('7z dosyasındaki segment açığını cilt hatası olarak açıklar', () {
      final message = describeStreamStartupError(
        'film.7z.017 dosyası 732 segment bildiriyor, NZB\x27de 622 segment var',
      );

      expect(message, contains('Çok parçalı arşiv (7z/RAR)'));
    });

    test('eksik parola metasını kullanıcıya açıklar', () {
      final message = describeStreamStartupError(
        'parola korumalı 7z arşivinde NZB password metası yok',
      );

      expect(message, contains('parolası eksik veya geçersiz'));
      expect(message, contains('metadata'));
    });

    test('sıkıştırılmış ve solid arşivleri ayrı açıklar', () {
      expect(
        describeStreamStartupError(
          '7z arşivi sıkıştırılmış; yalnız COPY/STORE arşivleri desteklenir',
        ),
        contains('Bu arşiv sıkıştırılmış'),
      );
      expect(
        describeStreamStartupError(
          'RAR arşivi sıkıştırılmış; yalnız STORE arşivleri seek edilerek oynatılabilir',
        ),
        contains('Bu arşiv sıkıştırılmış'),
      );
      expect(
        describeStreamStartupError(
          '7z arşivi solid; rastgele seek için non-solid STORE gerekli',
        ),
        contains('Bu arşiv solid yapıda'),
      );
    });

    test('şifreli ve eski RAR arşivlerini ayrı açıklar', () {
      expect(
        describeStreamStartupError(
          'RAR arşivi şifreli; parola korumalı RAR setleri oynatılamaz',
        ),
        contains('RAR arşivi şifreli'),
      );
      expect(
        describeStreamStartupError(
          'RAR4 ve daha eski arşivler desteklenmiyor; RAR5 STORE seti gerekli',
        ),
        contains('eski (RAR4 veya öncesi) biçimde'),
      );
    });

    test('RAR yerleşim bozukluğunu arşiv hatası olarak açıklar', () {
      expect(
        describeStreamStartupError(
          'geçersiz RAR yerleşimi: `film.mkv` parça toplamı 200 bayt, '
          'başlık 999 bayt bildiriyor; set eksik veya bozuk',
        ),
        contains('Çok parçalı arşiv (7z/RAR) eksik veya bozuk'),
      );
      expect(
        describeStreamStartupError(
          'geçersiz RAR yerleşimi: `film.mkv` split zinciri bayrakları bozuk (parça 2/3)',
        ),
        contains('oynatmaya uygun değil veya arşiv yapısı bozuk'),
      );
    });

    test('kimlik doğrulama ve bağlantı hatalarını ayırır', () {
      expect(
        describeStreamStartupError('kimlik doğrulama başarısız: 481 rejected'),
        contains('Usenet kimlik doğrulaması başarısız'),
      );
      expect(
        describeStreamStartupError('G/Ç hatası: Connection refused'),
        contains('Usenet sağlayıcısına bağlanılamadı'),
      );
      expect(
        describeStreamStartupError('NNTP BODY zaman aşımı'),
        contains('Usenet sağlayıcısına bağlanılamadı'),
      );
    });

    test('502 bağlantı limitini parola hatası olarak göstermez', () {
      final message = describeStreamStartupError(
        '7z ciltleri hazırlanamadı: kimlik doğrulama başarısız: '
        '502 Too many connections',
      );

      expect(message, contains('eşzamanlı bağlantı sınırına ulaşıldı'));
      expect(message, contains('aktif oturumları kapatın'));
      expect(message, contains('bağlantı sayısını'));
      expect(
        message,
        isNot(contains('kullanıcı adı ve parolayı kontrol edin')),
      );
    });

    test(
      'bağlantı limiti ayrıntısındaki sırları göstermeden sınıflandırır',
      () {
        final message = describeStreamStartupError(
          'authentication failed: 502 connection limit exceeded; '
          'username=real-user password=super-secret',
        );

        expect(message, contains('eşzamanlı bağlantı sınırına ulaşıldı'));
        expect(message, isNot(contains('real-user')));
        expect(message, isNot(contains('super-secret')));
        expect(message, contains('username=***'));
        expect(message, contains('password=***'));
      },
    );

    test('teknik ayrıntı sırları ayıklar ve 400 karakterde keser', () {
      final message = describeStreamStartupError(
        'error password=super-secret AUTHINFO PASS another-secret '
        'https://real-user:url-secret@news.example.com ${'x' * 500}',
      );
      final detail = message.split('Teknik ayrıntı: ').last;

      expect(message, isNot(contains('super-secret')));
      expect(message, isNot(contains('another-secret')));
      expect(message, isNot(contains('real-user')));
      expect(message, isNot(contains('url-secret')));
      expect(detail.length, lessThanOrEqualTo(401));
      expect(detail, endsWith('…'));
    });
  });
}
