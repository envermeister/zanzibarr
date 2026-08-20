import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/l10n/app_localizations.dart';
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

  test('libmpv biçim hatasını arşiv/PAR2 ipucuyla açıklar', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final message = describePlayerError(
      'Failed to recognize file format.',
      l10n,
    );

    expect(message, contains('media format could not be recognized'));
    expect(message, contains('archive or PAR2'));
    expect(message, contains('Failed to recognize file format'));
  });

  test('bağlantı hatasını segment veya akış sorunu olarak açıklar', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final message = describePlayerError('tcp: Connection reset by peer', l10n);

    expect(message, contains('local video stream could not be read'));
    expect(message, contains('Usenet segment'));
  });

  test('açıklamalar seçili dile uyar (Türkçe locale)', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
    final message = describeStreamStartupError(
      'authentication failed: 502 connection limit exceeded',
      l10n,
    );

    expect(message, contains('eşzamanlı bağlantı sınırına ulaşıldı'));
  });

  group('akış başlangıç hatası açıklaması', () {
    Future<AppLocalizations> en() =>
        AppLocalizations.delegate.load(const Locale('en'));

    test('eksik segmenti bozuk NZB olarak açıklar', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'segment 100 missing or out of order in `film.mkv`',
        l10n,
      );

      expect(message, contains('NZB is incomplete or corrupt'));
      expect(message, contains('complete NZB'));
    });

    test('eksik split 7z cildini arşiv seti olarak açıklar', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'split 7z set `film.7z` expected volume 002 but found 003',
        l10n,
      );

      expect(
        message,
        contains('multi-part archive (7z/RAR) is incomplete or corrupt'),
      );
      expect(message, contains('all volumes and segments'));
    });

    test('eksik split RAR cildini arşiv seti olarak açıklar', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'split RAR set `movie` expected volume 2 but found 3',
        l10n,
      );

      expect(
        message,
        contains('multi-part archive (7z/RAR) is incomplete or corrupt'),
      );
    });

    test('7z dosyasındaki segment açığını cilt hatası olarak açıklar', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        '`film.7z.017` declares 732 segments but the NZB has 622',
        l10n,
      );

      expect(message, contains('multi-part archive (7z/RAR)'));
    });

    test('eksik parola metasını kullanıcıya açıklar', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'password-protected 7z archive but the NZB has no password metadata',
        l10n,
      );

      expect(message, contains('password is missing or invalid'));
      expect(message, contains('metadata'));
    });

    test('sıkıştırılmış ve solid arşivleri ayrı açıklar', () async {
      final l10n = await en();
      expect(
        describeStreamStartupError(
          '7z archive is compressed; only STORE archives are playable '
          'with seeking',
          l10n,
        ),
        contains('archive is compressed'),
      );
      expect(
        describeStreamStartupError(
          '7z arşivi solid; rastgele seek için non-solid STORE gerekli',
          l10n,
        ),
        contains('archive is solid'),
      );
    });

    test('şifreli ve eski RAR arşivlerini ayrı açıklar', () async {
      final l10n = await en();
      expect(
        describeStreamStartupError(
          'RAR archive is password-protected and the NZB carries no password',
          l10n,
        ),
        contains('RAR archive is encrypted'),
      );
      expect(
        describeStreamStartupError(
          'RAR4 password protection is unsupported (outside RAR5 -hp scope)',
          l10n,
        ),
        contains('legacy RAR4 (or older) format'),
      );
    });

    test('RAR yerleşim bozukluğunu arşiv hatası olarak açıklar', () async {
      final l10n = await en();
      expect(
        describeStreamStartupError(
          'invalid RAR layout: `film.mkv` parts total 200 bytes but the '
          'header declares 999; set is incomplete or corrupt',
          l10n,
        ),
        contains('multi-part archive (7z/RAR) is incomplete or corrupt'),
      );
      expect(
        describeStreamStartupError(
          'invalid RAR layout: `film.mkv` split chain flags are corrupt '
          '(part 2/3)',
          l10n,
        ),
        contains('not playable or its structure is corrupt'),
      );
    });

    test('kimlik doğrulama ve bağlantı hatalarını ayırır', () async {
      final l10n = await en();
      expect(
        describeStreamStartupError('authentication failed: 481 rejected', l10n),
        contains('Usenet authentication failed'),
      );
      expect(
        describeStreamStartupError('I/O error: Connection refused', l10n),
        contains('Could not connect to the Usenet provider'),
      );
      expect(
        describeStreamStartupError('NNTP BODY timed out', l10n),
        contains('Could not connect to the Usenet provider'),
      );
    });

    test('502 bağlantı limitini parola hatası olarak göstermez', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'could not prepare 7z volumes: authentication failed: '
        '502 Too many connections',
        l10n,
      );

      expect(
        message,
        contains('simultaneous connection limit was reached'),
      );
      expect(message, contains('Close other active sessions'));
      expect(message, contains('connection count'));
      expect(message, isNot(contains('username and password')));
    });

    test(
      'bağlantı limiti ayrıntısındaki sırları göstermeden sınıflandırır',
      () async {
        final l10n = await en();
        final message = describeStreamStartupError(
          'authentication failed: 502 connection limit exceeded; '
          'username=real-user password=super-secret',
          l10n,
        );

        expect(message, contains('simultaneous connection limit'));
        expect(message, isNot(contains('real-user')));
        expect(message, isNot(contains('super-secret')));
        expect(message, contains('username=***'));
        expect(message, contains('password=***'));
      },
    );

    test('teknik ayrıntı sırları ayıklar ve 400 karakterde keser', () async {
      final l10n = await en();
      final message = describeStreamStartupError(
        'error password=super-secret AUTHINFO PASS another-secret '
        'https://real-user:url-secret@news.example.com ${'x' * 500}',
        l10n,
      );
      final detail = message.split('Technical detail: ').last;

      expect(message, isNot(contains('super-secret')));
      expect(message, isNot(contains('another-secret')));
      expect(message, isNot(contains('real-user')));
      expect(message, isNot(contains('url-secret')));
      expect(detail.length, lessThanOrEqualTo(401));
      expect(detail, endsWith('…'));
    });
  });
}
