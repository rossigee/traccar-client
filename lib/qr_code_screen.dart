import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'configuration_service.dart';
import 'l10n/app_localizations.dart';

class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({super.key});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null) return;

    final uri = Uri.tryParse(rawValue);
    if (uri == null) {
      _showError('Invalid QR code format');
      return;
    }

    if (!uri.scheme.startsWith('http') && !uri.scheme.startsWith('traccar')) {
      _showError('QR code must contain a valid URL');
      return;
    }

    _scanned = true;
    try {
      await ConfigurationService.applyUri(uri);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settings applied successfully')),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      _scanned = false; // Allow retry on error
      _showError('Failed to apply settings: ${error.toString()}');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settingsTitle),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              return IconButton(
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                onPressed: state.torchState == TorchState.unavailable
                    ? null
                    : () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        fit: BoxFit.cover,
        onDetect: _onDetect,
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_outlined, size: 120),
                  Text(AppLocalizations.of(context)!.disabledValue),
                  SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => AppSettings.openAppSettings(
                      type: AppSettingsType.settings,
                    ),
                    child: Text(AppLocalizations.of(context)!.settingsTitle),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
