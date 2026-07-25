import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/player_screen.dart';
import '../settings/indexer_settings.dart';
import '../settings/settings_screen.dart';
import '../src/rust/api/search.dart';

/// FRB `newznabSearch` imzası; testlerde sahte enjekte edilebilir.
typedef NewznabSearchFn =
    Future<SearchPageDto> Function(
      IndexerConfigDto config,
      String query,
      int limit,
      int offset,
    );

/// FRB `newznabDownloadNzb` imzası; testlerde sahte enjekte edilebilir.
typedef NewznabDownloadFn =
    Future<String> Function(
      IndexerConfigDto config,
      String nzbUrl,
      String suggestedName,
    );

/// Newznab indexer'da arama yapıp sonucu NZB indirmeden oynatıcıya bağlayan
/// ekran.
///
/// Ayarlar OS secure storage'dan okunur; API anahtarı ve `nzbUrl` hiçbir
/// zaman loglanmaz. Varsayılan arama/indirme gerçek FRB köprüsünü çağırır,
/// testler [searchFn]/[downloadFn]/[onDownloaded] ile sahte kurar.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.store,
    this.searchFn,
    this.downloadFn,
    this.onDownloaded,
  });

  /// Testlerde sahte depo enjekte edebilmek için; null ise gerçek depo kullanılır.
  final IndexerSettingsStore? store;

  /// Null ise FRB `newznabSearch` kullanılır.
  final NewznabSearchFn? searchFn;

  /// Null ise FRB `newznabDownloadNzb` kullanılır.
  final NewznabDownloadFn? downloadFn;

  /// İndirme bitince çağrılır; null ise [PlayerScreen]'e push edilir.
  /// Testlerde oynatıcının native çağrılarını atlamak için kullanılır.
  final ValueChanged<String>? onDownloaded;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _pageSize = 50;

  late final IndexerSettingsStore _store =
      widget.store ?? IndexerSettingsStore();
  late final NewznabSearchFn _searchFn = widget.searchFn ?? _defaultSearch;
  late final NewznabDownloadFn _downloadFn =
      widget.downloadFn ?? _defaultDownload;

  final _queryController = TextEditingController();

  IndexerSettings _settings = const IndexerSettings();
  bool _loadingSettings = true;

  List<SearchItemDto>? _items;
  int? _total;
  bool _searching = false;
  Object? _error;

  /// Şu an NZB'si indirilen öğenin listedeki sırası; spinner burada gösterilir.
  int? _busyIndex;

  static Future<SearchPageDto> _defaultSearch(
    IndexerConfigDto config,
    String query,
    int limit,
    int offset,
  ) => newznabSearch(config: config, query: query, limit: limit, offset: offset);

  static Future<String> _defaultDownload(
    IndexerConfigDto config,
    String nzbUrl,
    String suggestedName,
  ) => newznabDownloadNzb(
    config: config,
    nzbUrl: nzbUrl,
    suggestedName: suggestedName,
  );

  @override
  void initState() {
    super.initState();
    // Temizle düğmesi yalnızca metin varken görünsün.
    _queryController.addListener(() => setState(() {}));
    _loadSettings();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _store.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loadingSettings = false;
      });
    } catch (_) {
      // Secure storage okunamazsa indexer yokmuş gibi davran; kullanıcı
      // ayarlardan yeniden girmeyi deneyebilir.
      if (!mounted) return;
      setState(() => _loadingSettings = false);
    }
  }

  IndexerConfigDto get _config => IndexerConfigDto(
    baseUrl: _settings.baseUrl,
    apiKey: _settings.apiKey,
  );

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await _searchFn(_config, query, _pageSize, 0);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total?.toInt();
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _searching = false;
      });
    }
  }

  Future<void> _downloadAndPlay(int index) async {
    if (_busyIndex != null) return;
    final item = _items![index];
    setState(() => _busyIndex = index);
    try {
      final path = await _downloadFn(_config, item.nzbUrl, item.title);
      if (!mounted) return;
      final onDownloaded = widget.onDownloaded;
      if (onDownloaded != null) {
        onDownloaded(path);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PlayerScreen(nzbPath: path)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).searchDownloadFailed('$error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // Ayarlardan dönüldüğünde indexer yeni girilmiş olabilir.
    await _loadSettings();
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
          l10n.searchTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    // TV kumandasında D-pad gezintisi metin alanından başlar.
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: l10n.searchHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _queryController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.searchClearTooltip,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _queryController.clear();
                                setState(() {
                                  _items = null;
                                  _total = null;
                                  _error = null;
                                });
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: l10n.searchTooltip,
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.search_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (_total != null && _items != null && !_searching)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  l10n.searchResultsTotal(_total!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          Expanded(child: _buildBody(context, l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loadingSettings) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!_settings.isComplete) {
      return _IndexerMissing(onOpenSettings: _openSettings);
    }
    if (_searching) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error case final error?) {
      return _SearchError(error: error, onRetry: _search);
    }
    final items = _items;
    if (items == null) {
      return _HintView(
        icon: Icons.travel_explore_rounded,
        message: l10n.searchEmptyHint,
      );
    }
    if (items.isEmpty) {
      return _HintView(
        icon: Icons.search_off_rounded,
        message: l10n.searchNoResults,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _SearchResultCard(
        item: items[index],
        busy: _busyIndex == index,
        enabled: _busyIndex == null,
        onTap: () => _downloadAndPlay(index),
      ),
    );
  }
}

/// Tek arama sonucu kartı: tür simgesi, başlık, rozetler ve sağda boyut/yaş.
class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.item,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final SearchItemDto item;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  static IconData _mediaIcon(String mediaKind) => switch (mediaKind) {
    'movie' => Icons.movie_outlined,
    'tv' => Icons.tv_rounded,
    _ => Icons.insert_drive_file_outlined,
  };

  /// GB/MB biçiminde boyut; `null` ise boş döner (gösterilmez).
  static String _formatSize(BigInt sizeBytes) {
    final bytes = sizeBytes.toInt();
    const giga = 1024 * 1024 * 1024;
    const mega = 1024 * 1024;
    if (bytes >= giga) return '${(bytes / giga).toStringAsFixed(1)} GB';
    if (bytes >= mega) return '${(bytes / mega).round()} MB';
    return '<1 MB';
  }

  /// Yayın yaşını gün/ay/yıl kısaltmasıyla verir; `null` ise boş döner.
  static String _formatAge(int publishedEpochSecs, bool turkish) {
    final published = DateTime.fromMillisecondsSinceEpoch(
      publishedEpochSecs * 1000,
    );
    var days = DateTime.now().difference(published).inDays;
    if (days < 0) days = 0;
    if (days < 31) return turkish ? '$days g' : '${days}d';
    if (days < 365) {
      final months = days ~/ 30;
      return turkish ? '$months ay' : '${months}mo';
    }
    return '${days ~/ 365} y';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    final isTurkish = Localizations.localeOf(context).languageCode == 'tr';
    final sizeText = item.sizeBytes == null ? null : _formatSize(item.sizeBytes!);
    final ageText = item.publishedEpochSecs == null
        ? null
        : _formatAge(item.publishedEpochSecs!.toInt(), isTurkish);
    return Material(
      color: foreground.withValues(alpha: 0.035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: foreground.withValues(alpha: 0.075)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        hoverColor: foreground.withValues(alpha: 0.045),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: foreground.withValues(alpha: 0.7),
                        ),
                      )
                    : Icon(
                        _mediaIcon(item.mediaKind),
                        size: 19,
                        color: foreground.withValues(alpha: 0.7),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (item.badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final badge in item.badges)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: foreground.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: foreground.withValues(alpha: 0.75),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (sizeText != null)
                    Text(
                      sizeText,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (ageText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        ageText,
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.38),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (item.year != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${item.year}',
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.38),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indexer ayarları eksikken gösterilen yönlendirme görünümü.
class _IndexerMissing extends StatelessWidget {
  const _IndexerMissing({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

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
                Icons.travel_explore_rounded,
                size: 32,
                color: foreground.withValues(alpha: 0.54),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.indexerMissingHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(l10n.goToIndexerSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arama hatası; oynatıcıdaki _ErrorView tarzının sade hâli.
class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                '$error',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
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

/// Boş durum ipucu görünümü (henüz arama yapılmadı / sonuç yok).
class _HintView extends StatelessWidget {
  const _HintView({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: foreground.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.38),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
