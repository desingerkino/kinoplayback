import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/event_log.dart';
import 'orientation_math.dart';
import 'orientation_sync.dart';

/// CAMERA-side roll measurement.
///
/// Gravity comes from the accelerometer through a low-pass filter (no gyro
/// integration → no drift). Fast shakes are smoothed out; slow deliberate
/// rolls are tracked within ~100 ms. When the phone lies flat roll is
/// undefined and reported as invalid instead of guessed.
class MotionSource extends ChangeNotifier {
  MotionSource({this.sendHz = 15});

  final int sendHz;
  final GravityFilter _g = GravityFilter(alpha: 0.2);
  StreamSubscription<AccelerometerEvent>? _sub;
  final Stopwatch _clock = Stopwatch();
  int _seq = 0;
  int _lastEmitMs = -1000;
  int _quant = 0;
  bool available = true;
  String? error;

  double? roll;
  int get quant => _quant;

  /// Called at [sendHz] with a ready-to-send sample.
  void Function(MotionSample s)? onSample;

  void start() {
    if (_sub != null) return;
    _clock.start();
    try {
      _sub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).listen(
        _onAccel,
        onError: (Object e) {
          available = false;
          error = 'Датчик ориентации недоступен: $e';
          logW('motion', error!);
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      available = false;
      error = 'Датчик ориентации недоступен: $e';
      logW('motion', error!);
    }
  }

  void _onAccel(AccelerometerEvent e) {
    _g.add(e.x, e.y, e.z);
    final r = rollFromGravity(_g.x!, _g.y!);
    final prev = roll;
    roll = r;
    if (r != null) _quant = quantizeWithHysteresis(r, _quant);
    final now = _clock.elapsedMilliseconds;
    if (now - _lastEmitMs >= 1000 ~/ sendHz) {
      _lastEmitMs = now;
      onSample?.call(MotionSample(
        sessionId: null,
        seq: ++_seq,
        tMs: now,
        roll: r ?? 0,
        valid: r != null,
        quant: _quant,
      ));
      // UI on the camera only needs ~15 Hz too.
      if (prev == null || r == null || (r - prev).abs() > 0.2) notifyListeners();
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _clock.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
