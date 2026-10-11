import 'package:flutter/material.dart';

import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../settings/app_settings.dart';
import 'frame_analyzer.dart';
import 'monitor_view.dart';

/// Thin strip item: optional icon + tabular value.
class StripItem extends StatelessWidget {
  const StripItem(this.text, {super.key, this.icon, this.color, this.bold = true});

  final String text;
  final IconData? icon;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color ?? KpColors.textDim), const SizedBox(width: 4)],
        Text(
          text,
          maxLines: 1,
          style: (bold ? KpText.metric : KpText.metricSmall).copyWith(color: color),
        ),
      ],
    );
  }
}

/// Horizontal strip that drops low-priority items when space runs out
/// instead of overflowing (small phones in landscape).
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.leading, required this.trailing, this.height = 40});

  final List<Widget> leading;
  final List<Widget> trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    List<Widget> spaced(List<Widget> l) {
      final out = <Widget>[];
      for (var i = 0; i < l.length; i++) {
        if (i > 0) out.add(const SizedBox(width: 14));
        out.add(l[i]);
      }
      return out;
    }

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            // Low-priority items at the end are clipped on narrow screens
            // instead of throwing a layout overflow.
            child: ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(mainAxisSize: MainAxisSize.min, children: spaced(leading)),
              ),
            ),
          ),
          ...spaced(trailing),
        ],
      ),
    );
  }
}

String batteryText(int? level) => level == null ? '—' : '$level%';

IconData batteryIcon(int? level) {
  if (level == null) return Icons.battery_unknown_outlined;
  if (level > 80) return Icons.battery_full;
  if (level > 50) return Icons.battery_5_bar;
  if (level > 25) return Icons.battery_3_bar;
  return Icons.battery_1_bar;
}

MonitorGuides guidesFrom(AppSettings s) => MonitorGuides(
      grid: s.toolGrid,
      cross: s.toolCross,
      safe: s.toolSafe,
      aspect: s.toolAspect,
      fill: s.toolFill,
    );

/// Bottom sheet with all monitor tools (reference screen 9).
Future<void> showMonitorTools(BuildContext context, {required AppSettings settings, FrameAnalyzer? analyzer}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([settings, if (analyzer != null) analyzer]),
      builder: (context, _) {
        Widget tile(IconData icon, String label, bool on, VoidCallback onTap, {String? note}) {
          return SizedBox(
            width: 92,
            child: Column(
              children: [
                KpToolButton(icon: icon, label: label, selected: on, onTap: onTap),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note, textAlign: TextAlign.center, style: KpText.caption.copyWith(fontSize: 9)),
                  ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Инструменты монитора', style: KpText.heading),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    tile(Icons.grid_on, 'Сетка', settings.toolGrid, () => settings.update((s) => s.toolGrid = !s.toolGrid)),
                    tile(Icons.add, 'Центр', settings.toolCross, () => settings.update((s) => s.toolCross = !s.toolCross)),
                    tile(Icons.crop_free, 'Безоп. зоны', settings.toolSafe,
                        () => settings.update((s) => s.toolSafe = !s.toolSafe)),
                    tile(settings.toolFill ? Icons.fit_screen : Icons.fullscreen, settings.toolFill ? 'Fill' : 'Fit',
                        settings.toolFill, () => settings.update((s) => s.toolFill = !s.toolFill)),
                    if (analyzer != null) ...[
                      tile(Icons.texture, 'Зебра', analyzer.isOn(AnalysisTool.zebra),
                          () => analyzer.toggle(AnalysisTool.zebra), note: '≥95% Y′'),
                      tile(Icons.palette_outlined, 'False Color', analyzer.isOn(AnalysisTool.falseColor),
                          () => analyzer.toggle(AnalysisTool.falseColor)),
                      tile(Icons.bar_chart, 'Гистограмма', analyzer.isOn(AnalysisTool.histogram),
                          () => analyzer.toggle(AnalysisTool.histogram)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text('Кашетирование', style: KpText.caption),
                const SizedBox(height: 6),
                KpSegmented<String>(
                  values: MonitorGuides.aspects,
                  selected: settings.toolAspect,
                  labelOf: (a) => a == 'off' ? 'Выкл' : a,
                  onChanged: (a) => settings.update((s) => s.toolAspect = a),
                ),
                if (analyzer != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Зебра, False Color и гистограмма считаются по принятому и декодированному кадру '
                    '(≈2 раза в секунду, уменьшенная копия), а не по сигналу сенсора камеры.',
                    style: KpText.caption,
                  ),
                  if (analyzer.error != null) ...[
                    const SizedBox(height: 8),
                    KpBanner(text: analyzer.error!),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
