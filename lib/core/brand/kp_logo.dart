import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/kp_colors.dart';
import '../theme/kp_text.dart';
import 'kp_mark_geometry.dart';

/// The KINO PLAYBACK mark (K block + red play triangle + lens), drawn from the
/// same geometry as the SVG / app icons (tool/brand/generate.py).
class KpMark extends StatelessWidget {
  const KpMark({super.key, this.size = 32, this.mono, this.rich = false, this.glow = false});

  /// Width of the mark; the height follows the mark's proportions.
  final double size;

  /// When set, the whole mark is drawn in this colour (monochrome version).
  final Color? mono;

  /// Glossy gradients of the app icon instead of flat colours.
  final bool rich;

  /// Soft red glow behind the play triangle and lens.
  final bool glow;

  static double get aspect => KpMarkGeometry.bounds.height / KpMarkGeometry.bounds.width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'KINO PLAYBACK',
      image: true,
      child: SizedBox(
        width: size,
        height: size * aspect,
        child: CustomPaint(painter: KpMarkPainter(mono: mono, rich: rich, glow: glow)),
      ),
    );
  }
}

class KpMarkPainter extends CustomPainter {
  KpMarkPainter({this.mono, this.rich = false, this.glow = false});
  final Color? mono;
  final bool rich;
  final bool glow;

  static const Map<KpMarkRole, List<Color>> _gradients = {
    KpMarkRole.white: [Color(0xFFFFFFFF), Color(0xFFC9C9C9)],
    KpMarkRole.graphite: [Color(0xFF3A3A3A), Color(0xFF101010)],
    KpMarkRole.red: [Color(0xFFFF3B30), Color(0xFFB0141C)],
  };

  Color _flat(KpMarkRole r) =>
      mono ??
      switch (r) {
        KpMarkRole.white => KpColors.text,
        KpMarkRole.graphite => const Color(0xFF2A2A2A),
        KpMarkRole.red => KpColors.rec,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final b = KpMarkGeometry.bounds;
    // Fit the mark's bounding box into the widget, centred.
    final k = math.min(size.width / b.width, size.height / b.height);
    final dx = (size.width - b.width * k) / 2 - b.left * k;
    final dy = (size.height - b.height * k) / 2 - b.top * k;
    Path pathOf(KpMarkPart part) =>
        Path()..addPolygon([for (final p in part.points) Offset(dx + p.dx * k, dy + p.dy * k)], true);

    if (glow && mono == null) {
      final g = Paint()
        ..color = KpColors.rec.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05);
      for (final part in KpMarkGeometry.parts) {
        if (part.role == KpMarkRole.red) canvas.drawPath(pathOf(part), g);
      }
    }
    for (final part in KpMarkGeometry.parts) {
      final path = pathOf(part);
      final paint = Paint()..isAntiAlias = true;
      if (rich && mono == null) {
        final r = path.getBounds();
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _gradients[part.role]!,
        ).createShader(r);
      } else {
        paint.color = _flat(part.role);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant KpMarkPainter old) => old.mono != mono || old.rich != rich || old.glow != glow;
}

/// Text letter-spaced so that it spans exactly [width] (first letter to last).
class KpSpreadText extends StatelessWidget {
  const KpSpreadText(this.text, {super.key, required this.width, required this.style});

  final String text;
  final double width;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(letterSpacing: 0)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final n = text.characters.length;
    final spacing = n > 1 ? math.max(0.0, (width - tp.width) / (n - 1)) : 0.0;
    tp.dispose();
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        textScaler: TextScaler.noScaling,
        style: style.copyWith(letterSpacing: spacing),
      ),
    );
  }
}

/// Horizontal or stacked lockup: mark + KINO / PLAYBACK.
class KpLogo extends StatelessWidget {
  const KpLogo({super.key, this.height = 48, this.stacked = false, this.showMark = true});

  final double height;
  final bool stacked;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final kinoSize = height * (stacked ? 0.5 : 0.56);
    final kino = Text(
      'KINO',
      textScaler: TextScaler.noScaling,
      style: KpText.logo.copyWith(fontSize: kinoSize, height: 1),
    );
    // KINO width in the wordmark face: PLAYBACK is spread to the same width.
    final tp = TextPainter(
      text: TextSpan(text: 'KINO', style: KpText.logo.copyWith(fontSize: kinoSize, height: 1)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final kinoWidth = tp.width;
    tp.dispose();
    final playback = KpSpreadText(
      'PLAYBACK',
      width: kinoWidth,
      style: KpText.logo.copyWith(
        fontWeight: FontWeight.w400,
        color: KpColors.rec,
        fontSize: kinoSize * 0.3,
        height: 1,
      ),
    );
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [kino, SizedBox(height: height * 0.1), playback],
    );
    if (!showMark) return words;
    if (stacked) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        KpMark(size: height * 1.6, rich: true),
        SizedBox(height: height * 0.3),
        words,
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      KpMark(size: height * 1.15, rich: true),
      SizedBox(width: height * 0.28),
      words,
    ]);
  }
}

/// Home-screen lockup (approved reference): the mark inside red viewfinder
/// corners with a soft red glow, KINO, letter-spaced PLAYBACK and the
/// CAMERA · MONITOR · PLAYBACK line, all exactly [width] wide.
class KpHomeLockup extends StatelessWidget {
  const KpHomeLockup({super.key, required this.width});

  final double width;

  static const String tagline = 'CAMERA · MONITOR · PLAYBACK';

  @override
  Widget build(BuildContext context) {
    final w = width;
    final markW = w * 0.53;
    final frameH = w * 0.05 + markW * KpMark.aspect + w * 0.03;
    final textW = w * 0.84;
    // Font size at which KINO spans textW (no FittedBox: keeps intrinsics exact).
    final probe = TextPainter(
      text: TextSpan(text: 'KINO', style: KpText.logo.copyWith(fontSize: 100, height: 1)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final kinoSize = 100 * textW / probe.width;
    probe.dispose();
    return Semantics(
      label: 'KINO PLAYBACK — $tagline',
      container: true,
      excludeSemantics: true,
      child: SizedBox(
        width: w,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: w,
            height: frameH,
            child: CustomPaint(
              painter: _ViewfinderPainter(inset: w * 0.09, arm: w * 0.06, stroke: math.max(1.5, w * 0.006)),
              child: Padding(
                padding: EdgeInsets.only(top: w * 0.05, left: w * 0.01),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: KpMark(size: markW, rich: true, glow: true),
                ),
              ),
            ),
          ),
          SizedBox(height: w * 0.045),
          Text('KINO', textScaler: TextScaler.noScaling, style: KpText.logo.copyWith(fontSize: kinoSize, height: 1)),
          SizedBox(height: w * 0.035),
          KpSpreadText(
            'PLAYBACK',
            width: textW,
            style: KpText.logo.copyWith(
              fontWeight: FontWeight.w400,
              fontSize: w * 0.07,
              color: KpColors.rec,
              height: 1,
            ),
          ),
          SizedBox(height: w * 0.04),
          KpSpreadText(
            tagline,
            width: textW,
            style: TextStyle(
              fontFamily: KpText.family,
              fontWeight: FontWeight.w400,
              fontSize: w * 0.036,
              color: KpColors.textDim,
              height: 1,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.inset, required this.arm, required this.stroke});
  final double inset;
  final double arm;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = KpColors.rec
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    final h = stroke / 2;
    final l = inset, r = size.width - inset, t = h, b = size.height - h;
    for (final (x, y, sx, sy) in [(l, t, 1.0, 1.0), (r, t, -1.0, 1.0), (l, b, 1.0, -1.0), (r, b, -1.0, -1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + sy * arm)
          ..lineTo(x, y)
          ..lineTo(x + sx * arm, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter o) => o.inset != inset || o.arm != arm || o.stroke != stroke;
}
