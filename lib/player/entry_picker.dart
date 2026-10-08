import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/streaming.dart';

/// Sezon paketi gibi birden çok video içeren NZB'lerde oynatılacak dosyayı
/// seçtiren diyalog (GitHub issue #5).
///
/// Seçilen adayın `key` değerini döndürür; Geri/vazgeç `null` döner.
/// D-pad: ilk öğe otomatik odaklıdır, yukarı/aşağı listede gezer,
/// DPAD_CENTER seçer; Geri diyalogu kapatır (showDialog varsayılanı).
Future<String?> showPlayableEntryPicker(
  BuildContext context,
  List<PlayableEntryDto> entries,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PlayableEntryPickerDialog(entries: entries),
  );
}

class _PlayableEntryPickerDialog extends StatelessWidget {
  const _PlayableEntryPickerDialog({required this.entries});

  final List<PlayableEntryDto> entries;

  static IconData _iconFor(String kind) => switch (kind) {
    'direct' => Icons.movie_outlined,
    _ => Icons.inventory_2_outlined,
  };

  static String _kindLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'direct' => l10n.entryKindDirect,
        'probe' => l10n.entryKindArchive,
        // 7z/RAR marka adları çevrilmez.
        _ => kind.toUpperCase(),
      };

  /// GB/MB biçiminde boyut (arama ekranındakiyle aynı kural).
  static String _formatSize(BigInt sizeBytes) {
    final bytes = sizeBytes.toDouble();
    const giga = 1024 * 1024 * 1024;
    const mega = 1024 * 1024;
    if (bytes >= giga) return '${(bytes / giga).toStringAsFixed(1)} GB';
    if (bytes >= mega) return '${(bytes / mega).round()} MB';
    return '<1 MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.entryPickerTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.entryPickerSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final subtitle = StringBuffer(
                    '${_formatSize(entry.encodedBytes)} · '
                    '${_kindLabel(l10n, entry.kind)}',
                  );
                  if (entry.partCount > 1) {
                    subtitle.write(
                      ' · ${l10n.entryParts(entry.partCount.toInt())}',
                    );
                  }
                  return ListTile(
                    // D-pad gezintisi ilk videodan başlar (issue #4 dersi:
                    // otomatik odak yoksa kumandayla diyalog ölü doğar).
                    autofocus: index == 0,
                    leading: Icon(_iconFor(entry.kind), size: 20),
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      subtitle.toString(),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => Navigator.of(context).pop(entry.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
