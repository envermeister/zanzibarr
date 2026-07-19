import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'provider_settings.dart';
import 'ui_preferences.dart';

/// Sağlayıcı (NNTP) kimlik bilgileri için ayar ekranı.
///
/// Değerler OS secure storage'a yazılır; ekran açılışında oradan okunur.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store, this.uiPreferences});

  /// Testlerde sahte depo enjekte edebilmek için; null ise gerçek depo kullanılır.
  final ProviderSettingsStore? store;

  /// Dil/görünüm seçicileri için; null ise "Uygulama" bölümü gösterilmez.
  final UiPreferencesController? uiPreferences;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).settingsSaveFailed('$e')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).settingsSaved)),
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
      return AppLocalizations.of(
        context,
      ).validationIntegerRange(fieldName, minimum, maximum);
    }
    return null;
  }

  String? _required(String? value, String fieldName) =>
      value == null || value.trim().isEmpty
          ? AppLocalizations.of(context).validationRequired(fieldName)
          : null;

  String? _validateHost(String? value) {
    final l10n = AppLocalizations.of(context);
    final host = value?.trim() ?? '';
    if (host.isEmpty) return l10n.validationRequired(l10n.serverAddressLabel);
    if (host.length > 253 ||
        host.contains(RegExp(r'\s')) ||
        host.contains('://') ||
        host.contains(RegExp(r'[/@?#:]'))) {
      return l10n.validationHostNoProtocol;
    }
    final hostname = RegExp(
      r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)'
      r'(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.?$',
    );
    if (!hostname.hasMatch(host)) return l10n.validationHostInvalid;
    return null;
  }

  Widget _portField() => TextFormField(
    controller: _portController,
    decoration: InputDecoration(
      labelText: AppLocalizations.of(context).portLabel,
      hintText: '563',
    ),
    textInputAction: TextInputAction.next,
    keyboardType: TextInputType.number,
    validator: (value) => _validateIntegerRange(
      value,
      AppLocalizations.of(context).portLabel,
      1,
      65535,
    ),
  );

  Widget _connectionField() => TextFormField(
    controller: _maxConnectionsController,
    decoration: InputDecoration(
      labelText: AppLocalizations.of(context).connectionLimitLabel,
      hintText: AppLocalizations.of(context).connectionLimitHint,
    ),
    textInputAction: TextInputAction.next,
    keyboardType: TextInputType.number,
    validator: (value) => _validateIntegerRange(
      value,
      AppLocalizations.of(context).connectionLimitLabel,
      1,
      60,
    ),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          tooltip: l10n.backTooltip,
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          l10n.providerTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                      if (widget.uiPreferences case final prefs?) ...[
                        Text(
                          l10n.appSectionTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.35,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          l10n.appSectionSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.45),
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 24),
                        _SettingsCard(
                          children: [
                            DropdownButtonFormField<Locale>(
                              initialValue: prefs.locale,
                              decoration: InputDecoration(
                                labelText: l10n.languageLabel,
                                prefixIcon: const Icon(
                                  Icons.language_rounded,
                                  size: 19,
                                ),
                              ),
                              items: [
                                for (final (locale, name)
                                    in supportedAppLocales)
                                  DropdownMenuItem(
                                    value: locale,
                                    child: Text(name),
                                  ),
                              ],
                              onChanged: (locale) {
                                if (locale != null) {
                                  prefs.setLocale(locale);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.themeLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.55),
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<ThemeMode>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    icon: const Icon(
                                      Icons.dark_mode_rounded,
                                      size: 17,
                                    ),
                                    label: Text(l10n.themeDark),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    icon: const Icon(
                                      Icons.light_mode_rounded,
                                      size: 17,
                                    ),
                                    label: Text(l10n.themeLight),
                                  ),
                                ],
                                selected: {prefs.themeMode},
                                onSelectionChanged: (selection) =>
                                    prefs.setThemeMode(selection.first),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        l10n.nntpSectionTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        l10n.nntpSectionSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.45),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SettingsCard(
                        children: [
                          TextFormField(
                            controller: _hostController,
                            decoration: InputDecoration(
                              labelText: l10n.serverAddressLabel,
                              hintText: 'news.example.com',
                              prefixIcon: const Icon(Icons.dns_rounded, size: 19),
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
                            decoration: InputDecoration(
                              labelText: l10n.usernameLabel,
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                size: 19,
                              ),
                            ),
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            validator: (value) =>
                                _required(value, l10n.usernameLabel),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _save(),
                            validator: (value) =>
                                _required(value, l10n.passwordLabel),
                            decoration: InputDecoration(
                              labelText: l10n.passwordLabel,
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 19,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? l10n.passwordShowTooltip
                                    : l10n.passwordHideTooltip,
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
                            _saving ? l10n.savingLabel : l10n.saveSecurelyLabel,
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
  Widget build(BuildContext context) {
    final cardForeground = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardForeground.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardForeground.withValues(alpha: 0.075)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: foreground.withValues(alpha: 0.54),
                size: 32,
              ),
              const SizedBox(height: 14),
              Text(
                l10n.secureStorageUnavailable,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '$error',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionHint extends StatelessWidget {
  const _ConnectionHint();

  @override
  Widget build(BuildContext context) {
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: hintColor.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppLocalizations.of(context).connectionLimitWarning,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: hintColor, height: 1.4),
          ),
        ),
      ],
    );
  }
}
