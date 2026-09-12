import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'cast_service.dart';

/// Cast cihazı seçici diyalog. Keşif yayınını dinler; kullanıcı bir cihaza
/// dokununca diyalog o cihazla kapanır, vazgeçerse null döner.
class CastDevicePicker extends StatelessWidget {
  const CastDevicePicker({super.key, required this.service});

  final CastController service;

  /// Diyalogu açar ve seçilen cihazı (veya null) döndürür.
  static Future<CastDevice?> show(
    BuildContext context, {
    required CastController service,
  }) {
    return showDialog<CastDevice>(
      context: context,
      builder: (_) => CastDevicePicker(service: service),
    );
  }

  IconData _iconFor(CastProtocol protocol) {
    switch (protocol) {
      case CastProtocol.chromecast:
        return Icons.cast_rounded;
      case CastProtocol.airplay:
        return Icons.airplay_rounded;
      case CastProtocol.dlna:
        return Icons.tv_rounded;
    }
  }

  String _protocolLabel(CastProtocol protocol) {
    switch (protocol) {
      case CastProtocol.chromecast:
        return 'Chromecast';
      case CastProtocol.airplay:
        return 'AirPlay';
      case CastProtocol.dlna:
        return 'DLNA';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.castDialogTitle),
      content: SizedBox(
        width: 360,
        child: StreamBuilder<List<CastDevice>>(
          stream: service.discoverDevices(),
          builder: (context, snapshot) {
            final devices = snapshot.data ?? const <CastDevice>[];
            final searching = snapshot.connectionState != ConnectionState.done;
            if (devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (searching) ...[
                      const SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 16),
                      Text(l10n.castSearching),
                    ] else
                      Text(l10n.castNoDevices, textAlign: TextAlign.center),
                  ],
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    leading: Icon(_iconFor(device.protocol)),
                    title: Text(device.name),
                    subtitle: Text(_protocolLabel(device.protocol)),
                    onTap: () => Navigator.of(context).pop(device),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
