import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';

/// Focus (square) and exposure (circle + sun) reticles at widget positions.
class ReticlePainter extends CustomPainter {
  ReticlePainter({this.focus, this.exposure, this.afLocked = false, this.aeLocked = false, this.pending = false});

  final Offset? focus;
  final Offset? exposure;
  final bool afLocked;
  final bool aeLocked;
  final bool pending;

  @override
  void paint(Canvas canvas, Size size) {
    final f = focus;
    if (f != null) {
      final c = afLocked ? KpColors.warn : (pending ? KpColors.textDim : KpColors.text);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c;
      const s = 34.0;
      final r = Rect.fromCenter(center: f, width: s, height: s);
      canvas.drawRect(r, p);
      // tick marks
      for (final d in [Offset(0, -s / 2), Offset(0, s / 2), Offset(-s / 2, 0), Offset(s / 2, 0)]) {
        final n = d / (s / 2) * 5;
        canvas.drawLine(f + d, f + d - n, p);
      }
      if (afLocked) _label(canvas, 'AF-L', f + const Offset(-s / 2, -s / 2 - 14), c);
    }
    final e = exposure;
    if (e != null && (f == null || (e - f).distance > 4)) {
      final c = aeLocked ? KpColors.warn : KpColors.text;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = c;
      canvas.drawCircle(e, 14, p);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(e + d * 18, e + d * 22, p);
      }
      if (aeLocked) _label(canvas, 'AE-L', e + const Offset(-14, 26), c);
    } else if (e != null && aeLocked) {
      _label(canvas, 'AE-L', e + const Offset(-14, 22), KpColors.warn);
    }
  }

  void _label(Canvas canvas, String t, Offset at, Color c) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: KpText.label.copyWith(fontSize: 10, color: c)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant ReticlePainter o) =>
      o.focus != focus || o.exposure != exposure || o.afLocked != afLocked || o.aeLocked != aeLocked || o.pending != pending;
}

/// Horizon level: a line along the true horizon (computed from the camera's
/// gravity sensor) with a fixed centre reference. Turns green within ±0.5°.
class HorizonPainter extends CustomPainter {
  HorizonPainter({required this.angleDeg, required this.tiltDeg});

  /// Angle of the true horizon on screen (deg, clockwise).
  final double angleDeg;

  /// Camera tilt to display as the numeric value.
  final double tiltDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final level = tiltDeg.abs() <= 0.5;
    final color = level ? KpColors.live : KpColors.text;
    final len = math.min(size.width, size.height) * 0.42;
    final a = angleDeg * math.pi / 180;
    final d = Offset(math.cos(a), math.sin(a)) * len;
    final p = Paint()
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.85);
    canvas.drawLine(c - d, c - d * 0.15, p);
    canvas.drawLine(c + d * 0.15, c + d, p);
    // fixed reference ticks
    final ref = Paint()
      ..strokeWidth = 1
      ..color = KpColors.guideSoft;
    canvas.drawLine(c + Offset(-len * 1.05, 0), c + Offset(-len * 0.95, 0), ref);
    canvas.drawLine(c + Offset(len * 0.95, 0), c + Offset(len * 1.05, 0), ref);
    final tp = TextPainter(
      text: TextSpan(
        text: '${tiltDeg >= 0 ? '+' : ''}${tiltDeg.toStringAsFixed(1)}°',
        style: KpText.metric.copyWith(fontSize: 11, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c + Offset(-tp.width / 2, 8));
  }

  @override
  bool shouldRepaint(covariant HorizonPainter o) => o.angleDeg != angleDeg || o.tiltDeg != tiltDeg;
}

/// Small pill used in the focus / exposure strip.
class KpPill extends StatelessWidget {
  const KpPill({super.key, required this.label, this.onTap, this.active = false, this.enabled = true, this.icon, this.color});

  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool enabled;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = !enabled ? KpColors.textMute : (color ?? (active ? KpColors.warn : KpColors.text));
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? c.withValues(alpha: 0.16) : const Color(0xB3000000),
        shape: StadiumBorder(side: BorderSide(color: active ? c : KpColors.strokeStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
              Text(label, style: KpText.label.copyWith(fontSize: 11, color: c, letterSpacing: 0.4)),
            ]),
          ),
        ),
      ),
    );
  }
}

String tapTargetLabel(String t) => switch (t) { 'focus' => 'TAP: AF', 'exposure' => 'TAP: AE', _ => 'TAP: AF+AE' };

String nextTapTarget(String t) => switch (t) { 'both' => 'focus', 'focus' => 'exposure', _ => 'both' };
