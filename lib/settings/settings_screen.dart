import 'package:flutter/material.dart';

import 'provider_settings.dart';

/// Sağlayıcı (NNTP) kimlik bilgileri için ayar ekranı.
///
/// Değerler OS secure storage'a yazılır; ekran açılışında oradan okunur.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store});

  /// Testlerde sahte depo enjekte edebilmek için; null ise gerçek depo kullanılır.
  final ProviderSettingsStore? store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final ProviderSettingsStore _store =
      widget.store ?? ProviderSettingsStore();

  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _maxConnectionsController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _obscurePassword = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_obscurePassword && mounted) {
      setState(() => _obscurePassword = true);
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final settings = await _store.load();
      if (!mounted) return;
      setState(() {
        _hostController.text = settings.host;
        _portController.text = settings.port.toString();
        _usernameController.text = settings.username;
        _passwordController.text = settings.password;
        _maxConnectionsController.text = settings.maxConnections.toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _obscurePassword = true;
    });
    var saved = false;
    try {
      await _store.save(
        ProviderSettings(
          host: _hostController.text.trim(),
          port: int.parse(_portController.text.trim()),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          maxConnections: int.parse(_maxConnectionsController.text.trim()),
        ),
      );
      saved = true;
    } catch (e) {
      // Keychain yazımı başarısızsa (ör. entitlement eksik) uygulamayı
      // düşürmeden kullanıcıya bildir.
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ayarlar güvenli depoya kaydedildi.')),
    );
  }

  String? _validateIntegerRange(
    String? value,
    String fieldName,
    int minimum,
    int maximum,
  ) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < minimum || parsed > maximum) {
      return '$fieldName $minimum–$maximum arasında olmalı';
    }
    return null;
  }

  String? _required(String? value, String fieldName) =>
      value == null || value.trim().isEmpty ? '$fieldName gerekli' : null;

  String? _validateHost(String? value) {
    final host = value?.trim() ?? '';
    if (host.isEmpty) return 'Sunucu adresi gerekli';
    if (host.length > 253 ||
        host.contains(RegExp(r'\s')) ||
        host.contains('://') ||
        host.contains(RegExp(r'[/@?#:]'))) {
      return 'Yalnız sunucu adını girin; protokol ve port eklemeyin';
    }
    final hostname = RegExp(
      r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)'
      r'(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.?$',
    );
    if (!hostname.hasMatch(host)) return 'Geçerli bir sunucu adı girin';
    return null;
  }

  Widget _portField() => TextFormField(
    controller: _portController,
    decoration: const InputDecoration(labelText: 'Port', hintText: '563'),
    textInputAction: TextInputAction.next,
    keyboardType: TextInputType.number,
    validator: (value) => _validateIntegerRange(value, 'Port', 1, 65535),
  );

  Widget _connectionField() => TextFormField(
    controller: _maxConnectionsController,
    decoration: const InputDecoration(
      labelText: 'Bağlantı limiti',
      hintText: 'Plan limiti',
    ),
    textInputAction: TextInputAction.next,
    keyboardType: TextInputType.number,
    validator: (value) =>
        _validateIntegerRange(value, 'Bağlantı limiti', 1, 60),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController
      ..clear()
      ..dispose();
    _maxConnectionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          tooltip: 'Geri',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Sağlayıcı',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _loadError != null
          ? _SettingsLoadError(error: _loadError!, onRetry: _load)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                    children: [
                      Text(
                        'NNTP bağlantısı',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Bilgiler yalnızca bu cihazın güvenli anahtar '
                        'zincirinde saklanır.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white38,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SettingsCard(
                        children: [
                          TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Sunucu adresi',
                              hintText: 'news.example.com',
                              prefixIcon: Icon(Icons.dns_rounded, size: 19),
                            ),
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            validator: _validateHost,
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 440) {
                                return Column(
                                  children: [
                                    _portField(),
                                    const SizedBox(height: 12),
                                    _connectionField(),
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _portField()),
                                  const SizedBox(width: 12),
                                  Expanded(child: _connectionField()),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SettingsCard(
                        children: [
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Kullanıcı adı',
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                size: 19,
                              ),
                            ),
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            validator: (value) =>
                                _required(value, 'Kullanıcı adı'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _save(),
                            validator: (value) => _required(value, 'Parola'),
                            decoration: InputDecoration(
                              labelText: 'Parola',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 19,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Parolayı göster'
                                    : 'Parolayı gizle',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 18,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _ConnectionHint(),
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            _saving ? 'Kaydediliyor…' : 'Güvenle kaydet',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: children),
    ),
  );
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: Colors.white54,
              size: 32,
            ),
            const SizedBox(height: 14),
            const Text(
              'Güvenli depoya erişilemedi',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '$error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Yeniden dene'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConnectionHint extends StatelessWidget {
  const _ConnectionHint();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Colors.white30,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Bağlantı limitini sağlayıcınızın planından yüksek seçmek, “çok '
          'fazla bağlantı” hatasına yol açabilir.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white38, height: 1.4),
        ),
      ),
    ],
  );
}
