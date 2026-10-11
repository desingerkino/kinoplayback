import 'package:flutter/widgets.dart';

import '../theme/kp_colors.dart';
import '../theme/kp_text.dart';
import 'kp_mark_geometry.dart';

/// The KINO PLAYBACK mark, drawn from the same geometry as the SVG / icons.
class KpMark extends StatelessWidget {
  const KpMark({super.key, this.size = 32, this.mono});

  final double size;

  /// When set, the whole mark is drawn in this colour (monochrome version).
  final Color? mono;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'KINO PLAYBACK',
      image: true,
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: KpMarkPainter(mono: mono))),
    );
  }
}

class KpMarkPainter extends CustomPainter {
  KpMarkPainter({this.mono});
  final Color? mono;

  @override
  void paint(Canvas canvas, Size size) {
    final b = KpMarkGeometry.bounds;
    // Fit the mark's bounding box into the widget, centred.
    final k = (size.shortestSide / (b.width > b.height ? b.width : b.height));
    final dx = (size.width - b.width * k) / 2 - b.left * k;
    final dy = (size.height - b.height * k) / 2 - b.top * k;
    void poly(List<Offset> pts, Color c) {
      final path = Path()..addPolygon([for (final p in pts) Offset(dx + p.dx * k, dy + p.dy * k)], true);
      canvas.drawPath(path, Paint()..color = c..isAntiAlias = true);
    }

    final white = mono ?? KpColors.text;
    final red = mono ?? KpColors.rec;
    poly(KpMarkGeometry.stem, white);
    poly(KpMarkGeometry.arm, white);
    poly(KpMarkGeometry.play, red);
  }

  @override
  bool shouldRepaint(covariant KpMarkPainter old) => old.mono != mono;
}

/// Horizontal or stacked lockup: mark + KINO / PLAYBACK.
class KpLogo extends StatelessWidget {
  const KpLogo({super.key, this.height = 48, this.stacked = false, this.showMark = true});

  final double height;
  final bool stacked;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final kino = Text(
      'KINO',
      style: KpText.logo.copyWith(fontSize: height * (stacked ? 0.62 : 0.72), letterSpacing: height * 0.02, height: 1),
    );
    final playback = Text(
      'PLAYBACK',
      style: KpText.label.copyWith(
        color: KpColors.rec,
        fontSize: height * (stacked ? 0.17 : 0.19),
        letterSpacing: height * (stacked ? 0.09 : 0.08),
        height: 1,
      ),
    );
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [kino, SizedBox(height: height * 0.08), playback],
    );
    if (!showMark) return words;
    if (stacked) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        KpMark(size: height * 1.4),
        SizedBox(height: height * 0.3),
        words,
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      KpMark(size: height),
      SizedBox(width: height * 0.28),
      words,
    ]);
  }
}
