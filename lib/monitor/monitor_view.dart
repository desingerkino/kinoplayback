import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/layout/adaptive.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import 'analysis.dart';
import 'frame_analyzer.dart';

class MonitorGuides {
  const MonitorGuides({
    this.grid = false,
    this.cross = false,
    this.safe = false,
    this.aspect = 'off',
    this.fill = false,
  });

  final bool grid;
  final bool cross;
  final bool safe;
  final String aspect; // off | 1:1 | 4:3 | 16:9 | 1.85:1 | 2.39:1
  final bool fill;

  static const aspects = ['off', '1:1', '4:3', '16:9', '1.85:1', '2.39:1'];

  static double? aspectValue(String a) => switch (a) {
        '1:1' => 1.0,
        '4:3' => 4 / 3,
        '16:9' => 16 / 9,
        '1.85:1' => 1.85,
        '2.39:1' => 2.39,
        _ => null,
      };
}

/// The video picture plus everything drawn on top of it, all aligned to the
/// actual picture rect (not the widget box), in any orientation.
class MonitorView extends StatelessWidget {
  const MonitorView({
    super.key,
    required this.renderer,
    required this.videoAspect,
    required this.guides,
    this.analyzer,
    this.mirror = false,
    this.hasVideo = true,
    this.placeholder,
  });

  final RTCVideoRenderer renderer;
  final double videoAspect;
  final MonitorGuides guides;
  final FrameAnalyzer? analyzer;
  final bool mirror;
  final bool hasVideo;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColoredBox(
        color: KpColors.monitor,
        child: LayoutBuilder(
          builder: (context, c) {
            final box = Size(c.maxWidth, c.maxHeight);
            final rect = videoRectIn(box, videoAspect, cover: guides.fill);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (hasVideo)
                  RTCVideoView(
                    renderer,
                    mirror: mirror,
                    objectFit: guides.fill
                        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                        : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                if (!hasVideo && placeholder != null) placeholder!,
                if (analyzer != null)
                  ListenableBuilder(
                    listenable: analyzer!,
                    builder: (context, _) {
                      final a = analyzer!;
                      return Stack(children: [
                        if (a.falseColor != null)
                          Positioned.fromRect(
                            rect: rect,
                            child: RawImage(image: a.falseColor, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                          ),
                        if (a.zebra != null)
                          Positioned.fromRect(
                            rect: rect,
                            child: RawImage(image: a.zebra, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                          ),
                      ]);
                    },
                  ),
                IgnorePointer(child: CustomPaint(painter: GuidesPainter(rect: rect, guides: guides))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class GuidesPainter extends CustomPainter {
  GuidesPainter({required this.rect, required this.guides});

  final Rect rect;
  final MonitorGuides guides;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = rect.intersect(Offset.zero & size);
    if (visible.isEmpty) return;
    var frame = rect;

    // Aspect mask: darken outside the target frame line.
    final target = MonitorGuides.aspectValue(guides.aspect);
    if (target != null) {
      final inner = videoRectIn(rect.size, target).shift(rect.topLeft);
      final mask = Paint()..color = const Color(0xB0000000);
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addRect(inner);
      canvas.drawPath(path, mask);
      canvas.drawRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = KpColors.guideSoft,
      );
      frame = inner;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = KpColors.guideSoft;

    if (guides.grid) {
      for (var i = 1; i < 3; i++) {
        final x = frame.left + frame.width * i / 3;
        final y = frame.top + frame.height * i / 3;
        canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), line);
        canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), line);
      }
    }

    if (guides.safe) {
      final action = Rect.fromCenter(center: frame.center, width: frame.width * 0.93, height: frame.height * 0.93);
      final title = Rect.fromCenter(center: frame.center, width: frame.width * 0.9, height: frame.height * 0.9);
      canvas.drawRect(action, line..color = KpColors.guideSoft);
      _dashedRect(canvas, title, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = KpColors.warn.withValues(alpha: 0.7));
    }

    if (guides.cross) {
      final c = frame.center;
      final len = math.min(frame.width, frame.height) * 0.05;
      final p = Paint()
        ..strokeWidth = 1.5
        ..color = KpColors.guide;
      canvas.drawLine(c.translate(-len, 0), c.translate(len, 0), p);
      canvas.drawLine(c.translate(0, -len), c.translate(0, len), p);
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 6.0, gap = 4.0;
    void dashed(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var t = 0.0;
      while (t < total) {
        final e = math.min(t + dash, total);
        canvas.drawLine(a + dir * t, a + dir * e, p);
        t = e + gap;
      }
    }

    dashed(r.topLeft, r.topRight);
    dashed(r.topRight, r.bottomRight);
    dashed(r.bottomRight, r.bottomLeft);
    dashed(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant GuidesPainter old) =>
      old.rect != rect ||
      old.guides.grid != guides.grid ||
      old.guides.cross != guides.cross ||
      old.guides.safe != guides.safe ||
      old.guides.aspect != guides.aspect ||
      old.guides.fill != guides.fill;
}

/// Compact luma histogram panel (from the decoded picture).
class HistogramView extends StatelessWidget {
  const HistogramView({super.key, required this.bins, this.width = 150, this.height = 64});

  final List<int>? bins;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final b = bins;
    final clip = b == null ? 0.0 : clippedFraction(b);
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KpColors.stroke),
      ),
      child: Column(
        children: [
          Expanded(child: CustomPaint(size: Size.infinite, painter: _HistPainter(b))),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('Y′ (поток)', style: KpText.caption.copyWith(fontSize: 9)),
              const Spacer(),
              if (clip > 0.005)
                Text('клип ${(clip * 100).toStringAsFixed(1)}%',
                    style: KpText.caption.copyWith(fontSize: 9, color: KpColors.rec)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistPainter extends CustomPainter {
  _HistPainter(this.bins);
  final List<int>? bins;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = KpColors.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final b = bins;
    if (b == null || b.isEmpty) return;
    final peak = b.reduce(math.max).toDouble();
    if (peak <= 0) return;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < b.length; i++) {
      final x = size.width * i / (b.length - 1);
      // sqrt scale keeps shadows visible next to a big peak
      final y = size.height - size.height * math.sqrt(b[i] / peak);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant _HistPainter old) => old.bins != bins;
}
