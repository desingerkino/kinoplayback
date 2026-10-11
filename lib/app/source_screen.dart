import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../camera/camera_screen.dart';
import '../core/event_log.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../playback/devices_screen.dart';
import '../transmitters/schemes_screen.dart';
import '../transmitters/transmitters_screen.dart';

/// Video source selection (reference screen 4).
///
/// Lists what the OS really exposes: the network CAMERA option and every
/// video input reported by the capture system. External USB/UVC devices
/// appear here only if the OS supports them (iPad with iPadOS 17+, Android
/// devices whose Camera2 exposes external cameras). Nothing is simulated.
class SourceScreen extends StatefulWidget {
  const SourceScreen({super.key});

  @override
  State<SourceScreen> createState() => _SourceScreenState();
}

class VideoInput {
  VideoInput(this.id, this.label, this.external);
  final String id;
  final String label;
  final bool external;
}

/// Built-in cameras have recognisable labels; everything else reported as a
/// video input is treated as external.
bool looksExternal(String label) {
  final l = label.toLowerCase();
  if (l.contains('external') || l.contains('usb') || l.contains('uvc')) return true;
  const builtin = ['back', 'front', 'facing back', 'facing front', 'ultra wide', 'telephoto', 'dual', 'triple', 'truedepth', 'lidar'];
  return !builtin.any(l.contains) && !RegExp(r'^camera \d').hasMatch(l);
}

class _SourceScreenState extends State<SourceScreen> {
  List<VideoInput>? _inputs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _inputs = null;
      _error = null;
    });
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final list = devices
          .where((d) => d.kind == 'videoinput')
          .map((d) => VideoInput(d.deviceId, d.label.isEmpty ? d.deviceId : d.label, looksExternal(d.label)))
          .toList();
      logI('source', 'видеовходы: ${list.map((e) => '${e.label}${e.external ? ' [ext]' : ''}').join(', ')}');
      if (mounted) setState(() => _inputs = list);
    } catch (e) {
      if (mounted) {
        setState(() {
          _inputs = [];
          _error = 'Не удалось получить список видеовходов: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs;
    final external = inputs?.where((i) => i.external).toList() ?? const <VideoInput>[];
    final builtin = inputs?.where((i) => !i.external).toList() ?? const <VideoInput>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Источник видео'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _scan, tooltip: 'Обновить')],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KpSection(title: 'Сеть', children: [
              KpRow(
                leading: const Icon(Icons.wifi_tethering, color: KpColors.text),
                label: 'KINO PLAYBACK CAMERA',
                subtitle: 'Камера другого телефона по Wi-Fi',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
              ),
            ]),
            KpSection(
              title: 'Внешние USB / UVC',
              footer: Platform.isIOS
                  ? 'iPadOS 17+ на iPad с USB-C поддерживает внешние UVC-камеры. На iPhone система их не поддерживает.'
                  : 'Работает, если устройство отдаёт внешние USB-камеры через Camera2 (зависит от модели).',
              children: [
                if (inputs == null)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else if (external.isEmpty)
                  const KpRow(label: 'Внешние видеоустройства не обнаружены', subtitle: 'Подключите приёмник с UVC-выходом и обновите список')
                else
                  for (final i in external)
                    KpRow(
                      leading: const Icon(Icons.usb, color: KpColors.text),
                      label: i.label,
                      subtitle: 'Внешнее устройство · смотреть, записывать, передавать на PLAYBACK',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CameraScreen(externalDeviceId: i.id, externalLabel: i.label),
                      )),
                    ),
              ],
            ),
            if (builtin.isNotEmpty)
              KpSection(title: 'Камеры этого устройства', children: [
                for (final i in builtin) KpRow(leading: const Icon(Icons.photo_camera_outlined, color: KpColors.textDim), label: i.label),
              ]),
            if (_error != null) KpBanner(text: _error!),
            KpSection(title: 'Оборудование', children: [
              KpRow(
                leading: const Icon(Icons.settings_input_antenna, color: KpColors.text),
                label: 'Видеопередатчики VAXIS / Accsoon',
                subtitle: 'Каталог, статусы совместимости, журнал тестов',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransmittersScreen())),
              ),
              KpRow(
                leading: const Icon(Icons.account_tree_outlined, color: KpColors.text),
                label: 'Схемы подключения',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
              ),
            ]),
            Text('Список видеовходов получен от системы; внешнее устройство определяется по названию.', style: KpText.caption),
          ],
        ),
      ),
    );
  }
}
