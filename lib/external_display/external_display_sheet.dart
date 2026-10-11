import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import 'external_display.dart';

/// EXTERNAL DISPLAY panel: real status from the OS, how to connect, the
/// clean-feed behaviour and honest latency notes.
Future<void> showExternalDisplaySheet(BuildContext context) {
  final ext = ExternalDisplay.instance;
  ext.refresh();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: ext,
      builder: (context, _) {
        final s = ext.state;
        final color = switch (s) {
          ExternalOutputState.outputActive => KpColors.live,
          ExternalOutputState.connected => KpColors.text,
          ExternalOutputState.notConnected => KpColors.textDim,
          ExternalOutputState.notSupported => KpColors.rec,
        };
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.connected_tv, color: KpColors.text),
                const SizedBox(width: 10),
                Text('Внешний дисплей', style: KpText.title),
              ]),
              const SizedBox(height: 12),
              KpSection(children: [
                KpRow(
                  label: 'Статус',
                  value: s.label,
                  valueColor: color,
                  leading: KpStatusDot(color: color, pulse: s == ExternalOutputState.connected),
                ),
                KpRow(label: 'Экран', value: ext.displayName ?? '—'),
                KpRow(label: 'Разрешение экрана', value: ext.width == null ? '—' : '${ext.width}×${ext.height}'),
                KpRow(label: 'Режим', value: 'CLEAN FEED', subtitle: 'Только изображение камеры, без кнопок и панелей'),
                if (ext.attachedTrackId != null)
                  KpRow(
                    label: 'Остановить вывод',
                    valueColor: KpColors.rec,
                    onTap: ext.hide,
                  ),
              ]),
              if (Platform.isIOS) ...[
                Text('Apple TV / AirPlay', style: KpText.heading),
                const SizedBox(height: 6),
                Text(
                  '1. iPhone и Apple TV в одной сети.\n'
                  '2. Откройте Пункт управления → «Повтор экрана» → выберите Apple TV.\n'
                  '3. KINO PLAYBACK сам переключит телевизор на чистое изображение камеры (CLEAN FEED), '
                  'интерфейс останется только на iPhone.\n'
                  'Проводное подключение (адаптер USB-C → HDMI или Lightning Digital AV) работает так же.',
                  style: KpText.bodyDim,
                ),
                const SizedBox(height: 8),
                Text(
                  'iOS не даёт приложениям открывать «Повтор экрана» программно, поэтому выбор Apple TV — в Пункте управления. '
                  'Кнопка AirPlay для видеоплеера здесь не подходит: она передаёт файлы, а не живую камеру.',
                  style: KpText.caption,
                ),
              ] else ...[
                Text('Android', style: KpText.heading),
                const SizedBox(height: 6),
                Text(
                  'Вывод работает, когда Android создаёт отдельный «презентационный» экран: адаптер USB-C → HDMI на телефонах '
                  'с DisplayPort Alt Mode, HDMI или беспроводной дисплей, если устройство подключает его как второй экран.\n'
                  'Обычное зеркалирование экрана и Chromecast в этом режиме не используются: Chromecast не принимает '
                  'произвольный живой поток приложения без отдельного приложения-приёмника.',
                  style: KpText.bodyDim,
                ),
              ],
              const SizedBox(height: 12),
              const KpBanner(
                text: 'Задержка AirPlay / беспроводного дисплея не измеряется приложением и может быть заметной. '
                    'Подходит для режиссёрского просмотра, но не для точного контроля фокуса.',
              ),
              const SizedBox(height: 8),
              Text(
                'Запись, поток на PLAYBACK, фокус и экспозиция не зависят от внешнего дисплея: '
                'подключение и отключение телевизора их не перезапускает.',
                style: KpText.caption,
              ),
              if (ext.error != null) ...[const SizedBox(height: 8), KpBanner(text: ext.error!, color: KpColors.rec)],
            ]),
          ),
        );
      },
    ),
  );
}
