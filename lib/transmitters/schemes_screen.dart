import 'package:flutter/material.dart';

import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import 'catalog.dart';

/// Connection schemes (reference screen 9): the three scenarios with a
/// drawn signal chain and honest step-by-step notes.
class SchemesScreen extends StatefulWidget {
  const SchemesScreen({super.key, this.initial = Scenario.b});
  final Scenario initial;

  @override
  State<SchemesScreen> createState() => _SchemesScreenState();
}

class _SchemesScreenState extends State<SchemesScreen> {
  late Scenario _s = widget.initial;

  static const _chains = {
    Scenario.a: ['iPhone / Android\nCAMERA', 'USB-C/Lightning\n→ HDMI', 'TX', 'RX', 'Монитор'],
    Scenario.b: ['Камера', 'TX', 'RX (UVC)', 'USB-C', 'iPad / Android\nPLAYBACK'],
    Scenario.c: ['Камера', 'TX', 'Wi-Fi TX', 'Приложение\nпроизводителя'],
  };

  static const _steps = {
    Scenario.a: [
      'Откройте KINO PLAYBACK в режиме CAMERA.',
      'Подключите адаптер: iPhone с USB-C — USB-C → HDMI (DisplayPort); iPhone с Lightning — Lightning Digital AV; '
          'Android — только модели с DisplayPort Alt Mode (уточните в характеристиках телефона).',
      'HDMI с адаптера — во вход HDMI передатчика (TX). Для SDI-передатчиков нужен конвертер HDMI → SDI.',
      'Как только система увидит внешний экран, KINO PLAYBACK выводит на него чистое изображение камеры без интерфейса '
          '(статус — «Внешний дисплей» на экране CAMERA). Запись на телефоне не прерывается.',
      'Приёмник (RX) — в монитор по HDMI/SDI.',
    ],
    Scenario.b: [
      'Нужен приёмник с UVC-выходом (документировано у Accsoon CineView 2 SDI) или внешний захват HDMI/SDI → UVC.',
      'iPad с USB-C и iPadOS 17+: система поддерживает внешние USB-камеры (UVC). iPhone: внешние UVC-камеры системой не поддерживаются.',
      'Android: работает, только если устройство отдаёт внешние USB-камеры через Camera2 — зависит от модели.',
      'Учитывайте питание: приёмник и iPad могут требовать отдельного питания; используйте кабель USB-C с передачей данных.',
      'В KINO PLAYBACK: главный экран → «Источник видео» → найденное внешнее устройство. Его можно смотреть с инструментами монитора, '
          'записывать и раздавать другим устройствам PLAYBACK по Wi-Fi.',
      'Результат проверки запишите в карточку модели («Добавить результат теста»).',
    ],
    Scenario.c: [
      'Многие передатчики (CineEye, CineView QUAD, ATOM) отдают изображение на телефон только в собственное приложение '
          '(Accsoon SEE / Accsoon Go / ATOM APP).',
      'Это не универсальный сетевой поток: KINO PLAYBACK не может его принять без официального SDK производителя.',
      'Accsoon предлагает SDK по партнёрской заявке (accsoon.com/sdk-launch-request). У VAXIS публичный SDK не найден.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Схемы подключения')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KpSegmented<Scenario>(
              values: Scenario.values,
              selected: _s,
              labelOf: (s) => 'Сценарий ${s.code}',
              onChanged: (s) => setState(() => _s = s),
            ),
            const SizedBox(height: 14),
            Text(_s.title, style: KpText.heading),
            const SizedBox(height: 14),
            SizedBox(height: 120, child: CustomPaint(painter: _ChainPainter(_chains[_s]!))),
            const SizedBox(height: 18),
            for (final (i, step) in _steps[_s]!.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: KpColors.rec, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: KpText.label.copyWith(fontSize: 11)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step, style: KpText.body)),
                ]),
              ),
            const SizedBox(height: 8),
            const KpBanner(
              text: 'Схемы описывают документированные возможности. Совместимость конкретного комплекта, кабелей и телефона '
                  'подтверждается только физическим тестом.',
              icon: Icons.info_outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainPainter extends CustomPainter {
  _ChainPainter(this.nodes);
  final List<String> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final n = nodes.length;
    const gap = 18.0;
    final w = (size.width - gap * (n - 1)) / n;
    final h = size.height * 0.62;
    final top = (size.height - h) / 2;
    final box = Paint()..color = KpColors.surface2;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = KpColors.strokeStrong;
    final arrow = Paint()
      ..color = KpColors.rec
      ..strokeWidth = 2;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, top, w, h), const Radius.circular(8));
      canvas.drawRRect(r, box);
      canvas.drawRRect(r, border);
      final tp = TextPainter(
        text: TextSpan(text: nodes[i], style: KpText.caption.copyWith(color: KpColors.text, fontSize: 10)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: w - 6);
      tp.paint(canvas, Offset(x + (w - tp.width) / 2, top + (h - tp.height) / 2));
      if (i < n - 1) {
        final y = top + h / 2;
        final x1 = x + w + 3, x2 = x + w + gap - 3;
        canvas.drawLine(Offset(x1, y), Offset(x2, y), arrow);
        canvas.drawPath(
          Path()
            ..moveTo(x2, y)
            ..lineTo(x2 - 5, y - 4)
            ..lineTo(x2 - 5, y + 4)
            ..close(),
          Paint()..color = KpColors.rec,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChainPainter old) => old.nodes != nodes;
}
