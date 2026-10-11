import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/kp_colors.dart';
import '../theme/kp_text.dart';

/// Visual state of a REC control. "pending" means a command was sent and we
/// are waiting for the real confirmation — the button never shows
/// "recording" just because it was pressed.
enum RecVisual { idle, pending, recording, disabled }

class RecButton extends StatefulWidget {
  const RecButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 72,
    this.semanticLabel,
  });

  final RecVisual state;
  final VoidCallback? onPressed;
  final double size;
  final String? semanticLabel;

  @override
  State<RecButton> createState() => _RecButtonState();
}

class _RecButtonState extends State<RecButton> with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RecButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.state == RecVisual.recording) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (widget.state == RecVisual.pending) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final disabled = widget.state == RecVisual.disabled || widget.onPressed == null;
    return Semantics(
      button: true,
      label: widget.semanticLabel ??
          (widget.state == RecVisual.recording ? 'Остановить запись' : 'Начать запись'),
      child: GestureDetector(
        onTap: disabled ? null : widget.onPressed,
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _spin]),
            builder: (context, _) {
              return CustomPaint(
                painter: _RecPainter(
                  state: widget.state,
                  disabled: disabled,
                  pulse: _pulse.value,
                  spin: _spin.value,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RecPainter extends CustomPainter {
  _RecPainter({required this.state, required this.disabled, required this.pulse, required this.spin});

  final RecVisual state;
  final bool disabled;
  final double pulse;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final ringW = math.max(2.5, r * 0.08);

    final ringColor = disabled
        ? KpColors.inactive
        : state == RecVisual.recording
            ? KpColors.rec
            : Colors.white;

    // Outer ring
    canvas.drawCircle(
      c,
      r - ringW / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..color = ringColor.withValues(alpha: disabled ? 0.6 : 0.95),
    );

    // Pending: rotating arc over the ring
    if (state == RecVisual.pending) {
      final rect = Rect.fromCircle(center: c, radius: r - ringW / 2);
      canvas.drawArc(
        rect,
        spin * 2 * math.pi,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW
          ..strokeCap = StrokeCap.round
          ..color = KpColors.rec,
      );
    }

    // Recording: soft glow pulse
    if (state == RecVisual.recording) {
      canvas.drawCircle(
        c,
        r - ringW * 2,
        Paint()
          ..color = KpColors.rec.withValues(alpha: 0.25 + 0.25 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Core: circle when idle, rounded square when recording (= "stop").
    final core = Paint()..color = disabled ? KpColors.recDeep.withValues(alpha: 0.6) : KpColors.rec;
    if (state == RecVisual.recording) {
      final side = r * 0.78;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: side, height: side), Radius.circular(r * 0.14)),
        core,
      );
    } else {
      canvas.drawCircle(c, r * (state == RecVisual.pending ? 0.6 : 0.72), core);
    }
  }

  @override
  bool shouldRepaint(covariant _RecPainter old) =>
      old.state != state || old.disabled != disabled || old.pulse != pulse || old.spin != spin;
}

String formatTimecode(Duration d) {
  final neg = d.isNegative;
  final t = neg ? Duration.zero : d;
  final h = t.inHours.toString().padLeft(2, '0');
  final m = (t.inMinutes % 60).toString().padLeft(2, '0');
  final s = (t.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Timecode that ticks by itself from an anchor. [anchor] is the local
/// monotonic-ish time at which the clip started (already compensated for the
/// remote device's elapsed time), so no clock sync between devices is needed.
class KpTimecode extends StatefulWidget {
  const KpTimecode({super.key, required this.anchor, this.style, this.color});

  /// null → shows 00:00:00 static.
  final DateTime? anchor;
  final TextStyle? style;
  final Color? color;

  @override
  State<KpTimecode> createState() => _KpTimecodeState();
}

class _KpTimecodeState extends State<KpTimecode> with SingleTickerProviderStateMixin {
  late final AnimationController _tick =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant KpTimecode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.anchor != null) {
      if (!_tick.isAnimating) _tick.repeat();
    } else {
      _tick.stop();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final d = widget.anchor == null ? Duration.zero : DateTime.now().difference(widget.anchor!);
        return Text(
          formatTimecode(d),
          style: (widget.style ?? KpText.timecode).copyWith(color: widget.color),
        );
      },
    );
  }
}

/// Segmented vertical audio meter. [level] 0..1 linear; null = no audio data.
class KpAudioMeter extends StatelessWidget {
  const KpAudioMeter({super.key, required this.level, this.height = 90, this.width = 6, this.channels = 2});

  final double? level;
  final double height;
  final double width;
  final int channels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(channels, (i) {
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(painter: _MeterPainter(level)),
            ),
          );
        }),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.level);

  final double? level;

  @override
  void paint(Canvas canvas, Size size) {
    const segments = 16;
    final segH = size.height / segments;
    // Convert linear amplitude to a dBFS-ish scale so quiet speech still moves.
    double norm = 0;
    if (level != null && level! > 0) {
      final db = 20 * math.log(level!) / math.ln10; // -inf..0
      norm = ((db + 60) / 60).clamp(0.0, 1.0);
    }
    final lit = (norm * segments).round();
    for (var i = 0; i < segments; i++) {
      final fromBottom = i;
      final y = size.height - (fromBottom + 1) * segH;
      final frac = fromBottom / segments;
      final color = frac > 0.85
          ? KpColors.rec
          : frac > 0.65
              ? KpColors.warn
              : KpColors.live;
      final on = level != null && fromBottom < lit;
      canvas.drawRect(
        Rect.fromLTWH(0, y + 0.75, size.width, segH - 1.5),
        Paint()..color = on ? color : KpColors.inactive.withValues(alpha: level == null ? 0.25 : 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter old) => old.level != level;
}
