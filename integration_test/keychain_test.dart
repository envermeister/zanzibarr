import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zanzibarr/settings/provider_settings.dart';

/// Gerçek OS Keychain'e karşı ProviderSettingsStore doğrulaması.
///
/// Sahte test kimliği kullanır (kullanıcının gerçek parolası DEĞİL) ve
/// sonunda temizler. macOS'ta `usesDataProtectionKeychain: false` düzeltmesi
/// olmadan `save` burada -34018 (errSecMissingEntitlement) ile patlardı.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gerçek Keychain: yaz → oku → temizle', (tester) async {
    final store = ProviderSettingsStore();

    // Önceki koşumdan kalıntı olmasın.
    await store.clear();

    const settings = ProviderSettings(
      host: 'test.example.invalid',
      port: 563,
      username: 'test-user',
      password: 'sahte-test-parolasi',
      maxConnections: 7,
    );

    // -34018 olsaydı burada fırlatırdı.
    await store.save(settings);

    final loaded = await store.load();
    expect(loaded.host, 'test.example.invalid');
    expect(loaded.port, 563);
    expect(loaded.username, 'test-user');
    expect(loaded.password, 'sahte-test-parolasi');
    expect(loaded.maxConnections, 7);
    expect(loaded.isComplete, isTrue);

    // Test kimliğini Keychain'den sil.
    await store.clear();
    final cleared = await store.load();
    expect(cleared.host, isEmpty);
    expect(cleared.password, isEmpty);
  });
}
