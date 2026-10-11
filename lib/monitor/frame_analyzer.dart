import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/event_log.dart';
import 'analysis.dart';

enum AnalysisTool { histogram, zebra, falseColor }

/// Samples the decoded video track a couple of times per second (downscaled)
/// and produces a histogram and zebra / false-colour overlay images.
///
/// This works on the *received/decoded* picture. It is a framing and
/// exposure aid, not a measurement of the camera sensor signal.
class FrameAnalyzer extends ChangeNotifier {
  FrameAnalyzer({this.interval = const Duration(milliseconds: 500), this.sampleWidth = 192});

  final Duration interval;
  final int sampleWidth;

  MediaStreamTrack? _track;
  final Set<AnalysisTool> _enabled = {};
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  List<int>? histogram;
  ui.Image? zebra;
  ui.Image? falseColor;
  String? error;
  int samples = 0;

  Set<AnalysisTool> get enabled => Set.unmodifiable(_enabled);
  bool isOn(AnalysisTool t) => _enabled.contains(t);

  set track(MediaStreamTrack? t) {
    if (identical(t, _track)) return;
    _track = t;
    _clear();
    _sync();
  }

  void toggle(AnalysisTool t) {
    if (!_enabled.remove(t)) _enabled.add(t);
    if (t == AnalysisTool.zebra && !_enabled.contains(t)) {
      zebra?.dispose();
      zebra = null;
    }
    if (t == AnalysisTool.falseColor && !_enabled.contains(t)) {
      falseColor?.dispose();
      falseColor = null;
    }
    if (t == AnalysisTool.histogram && !_enabled.contains(t)) histogram = null;
    _sync();
    notifyListeners();
  }

  void _sync() {
    final want = _enabled.isNotEmpty && _track != null;
    if (want && _timer == null) {
      _timer = Timer.periodic(interval, (_) => _tick());
    } else if (!want) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _clear() {
    histogram = null;
    zebra?.dispose();
    zebra = null;
    falseColor?.dispose();
    falseColor = null;
  }

  Future<void> _tick() async {
    final t = _track;
    if (_busy || t == null || _disposed) return;
    _busy = true;
    try {
      final ByteBuffer png = await t.captureFrame();
      final codec = await ui.instantiateImageCodec(png.asUint8List(), targetWidth: sampleWidth);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width, h = img.height;
      img.dispose();
      codec.dispose();
      if (bd == null || _disposed) return;
      final rgba = bd.buffer.asUint8List();
      if (_enabled.contains(AnalysisTool.histogram)) histogram = lumaHistogram(rgba);
      if (_enabled.contains(AnalysisTool.zebra)) {
        final z = await _toImage(zebraOverlay(rgba, w, h), w, h);
        zebra?.dispose();
        zebra = z;
      }
      if (_enabled.contains(AnalysisTool.falseColor)) {
        final f = await _toImage(falseColorImage(rgba), w, h);
        falseColor?.dispose();
        falseColor = f;
      }
      samples++;
      error = null;
      if (!_disposed) notifyListeners();
    } catch (e) {
      if (error == null) logW('monitor', 'анализ кадра недоступен: $e');
      error = 'Анализ кадра недоступен на этом устройстве';
      if (!_disposed) notifyListeners();
    } finally {
      _busy = false;
    }
  }

  static Future<ui.Image> _toImage(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _clear();
    super.dispose();
  }
}
