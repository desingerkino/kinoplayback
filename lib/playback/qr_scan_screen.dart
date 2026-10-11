import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';

/// Scans the CAMERA's connection QR. Returns the raw string.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.startsWith('kinoplayback://')) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KpColors.monitor,
      appBar: AppBar(backgroundColor: KpColors.monitor, title: const Text('QR-код камеры')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: KpColors.guide, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Наведите на QR-код на экране камеры (⋯ → Подключение и QR). '
              'Код содержит только адрес — подключение всё равно нужно подтвердить на камере.',
              textAlign: TextAlign.center,
              style: KpText.bodyDim,
            ),
          ),
        ],
      ),
    );
  }
}
