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

class _SettingsScreenState extends State<SettingsScreen> {
  late final ProviderSettingsStore _store =
      widget.store ?? ProviderSettingsStore();

  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _maxConnectionsController = TextEditingController();

  bool _loading = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _store.save(
      ProviderSettings(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        maxConnections: int.parse(_maxConnectionsController.text.trim()),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ayarlar güvenli depoya kaydedildi.')),
    );
  }

  String? _validatePositiveInt(String? value, String fieldName) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return '$fieldName pozitif bir sayı olmalı';
    }
    return null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _maxConnectionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sağlayıcı Ayarları')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Sunucu adresi',
                      hintText: 'ör. news.example.com',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Sunucu adresi gerekli'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '563 (TLS)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => _validatePositiveInt(v, 'Port'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı adı',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _maxConnectionsController,
                    decoration: const InputDecoration(
                      labelText: 'Eşzamanlı bağlantı limiti',
                      helperText:
                          'Sağlayıcının izin verdiği bağlantı sayısı; '
                          'bağlantı havuzu bu boyutu kullanır.',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        _validatePositiveInt(v, 'Bağlantı limiti'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Kaydet'),
                  ),
                ],
              ),
            ),
    );
  }
}
