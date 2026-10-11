import 'dart:math' as math;

import 'orientation_math.dart';

/// How PLAYBACK orients the received picture.
enum RotationMode { autoSync, followRoll, lockLandscape, lockPortrait, manual }

extension RotationModeX on RotationMode {
  String get label => switch (this) {
        RotationMode.autoSync => 'AUTO SYNC',
        RotationMode.followRoll => 'FOLLOW CAMERA ROLL',
        RotationMode.lockLandscape => 'LOCK LANDSCAPE',
        RotationMode.lockPortrait => 'LOCK PORTRAIT',
        RotationMode.manual => 'MANUAL ROTATION',
      };

  String get hint => switch (this) {
        RotationMode.autoSync => 'Кадр поворачивается шагами 90° вместе с камерой (метаданные видеопотока)',
        RotationMode.followRoll => 'Кадр плавно повторяет наклон камеры по данным её датчиков',
        RotationMode.lockLandscape => 'Кадр всегда горизонтальный',
        RotationMode.lockPortrait => 'Кадр всегда вертикальный',
        RotationMode.manual => 'Поворот задаётся вручную',
      };

  static RotationMode parse(String? s) =>
      RotationMode.values.firstWhere((m) => m.name == s, orElse: () => RotationMode.autoSync);
}

/// One orientation sample from the CAMERA (data channel `motion`).
class MotionSample {
  const MotionSample({
    required this.sessionId,
    required this.seq,
    required this.tMs,
    required this.roll,
    required this.valid,
    this.quant,
  });

  final String? sessionId;
  final int seq;

  /// CAMERA monotonic clock, ms since the motion stream started.
  final int tMs;

  /// Roll in degrees (-180, 180]; meaningless when [valid] is false.
  final double roll;
  final bool valid;

  /// 90° step the CAMERA considers its frames uprighted to (hysteresis).
  final int? quant;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        't': tMs,
        'roll': double.parse(roll.toStringAsFixed(2)),
        'ok': valid,
        if (quant != null) 'q': quant,
      };

  static MotionSample? fromJson(Map<String, dynamic> j, {String? sessionId}) {
    final seq = j['seq'], t = j['t'], roll = j['roll'];
    if (seq is! int || t is! int || roll is! num) return null;
    final q = j['q'];
    return MotionSample(
      sessionId: sessionId,
      seq: seq,
      tMs: t,
      roll: roll.toDouble(),
      valid: j['ok'] == true,
      quant: q is num ? q.toInt() : null,
    );
  }
}

/// PLAYBACK-side Camera Orientation Sync.
///
/// * accepts samples only for the current session and in sequence order,
/// * unwraps across ±180° so interpolation takes the short way,
/// * smooths with a time-based exponential filter (no fixed frame rate),
/// * reports "no data" when samples stop, instead of freezing a fake angle.
class CameraOrientationSync {
  CameraOrientationSync({this.timeConstantMs = 70, this.staleAfterMs = 1000});

  /// Smoothing time constant. ~70 ms hides sensor noise but follows a
  /// handheld roll without visible lag at 15–30 Hz updates.
  final double timeConstantMs;
  final int staleAfterMs;

  String? _session;
  int _lastSeq = -1;
  double? _target; // unwrapped
  double? _shown; // unwrapped, smoothed
  int? _lastSampleAtMs; // local clock
  int? _lastStepAtMs;
  bool _valid = false;
  int? _quant;

  RotationMode mode = RotationMode.autoSync;
  double manualDeg = 0;
  bool invert = false;

  /// Raw latest camera roll (deg, wrapped), or null if unknown.
  double? get cameraRoll => (_target == null || !_valid) ? null : wrap180(_target!);

  bool hasFreshData(int nowMs) =>
      _valid && _lastSampleAtMs != null && nowMs - _lastSampleAtMs! <= staleAfterMs;

  /// Starts a new session: all previous state is discarded.
  void reset([String? sessionId]) {
    _session = sessionId;
    _lastSeq = -1;
    _target = null;
    _shown = null;
    _lastSampleAtMs = null;
    _lastStepAtMs = null;
    _valid = false;
    _quant = null;
  }

  /// Returns true if the sample was accepted.
  bool ingest(MotionSample s, int nowMs) {
    if (_session != null && s.sessionId != null && s.sessionId != _session) return false;
    if (s.seq <= _lastSeq) return false; // late / duplicate
    _lastSeq = s.seq;
    _lastSampleAtMs = nowMs;
    _valid = s.valid;
    if (!s.valid) return true;
    _quant = s.quant == null ? null : (invert ? -s.quant! : s.quant!);
    final r = invert ? -s.roll : s.roll;
    if (_target == null) {
      _target = r;
      _shown ??= r;
    } else {
      // keep the unwrapped value continuous
      _target = _target! + angleDelta(_target!, r);
    }
    return true;
  }

  /// Display rotation (deg, clockwise on screen) for the current mode.
  /// [frameIsPortrait] tells whether the decoded picture is taller than wide.
  double displayRotation(int nowMs, {required bool frameIsPortrait}) {
    switch (mode) {
      case RotationMode.autoSync:
        return 0;
      case RotationMode.lockLandscape:
        return frameIsPortrait ? 90 : 0;
      case RotationMode.lockPortrait:
        return frameIsPortrait ? 0 : 90;
      case RotationMode.manual:
        return wrap180(manualDeg);
      case RotationMode.followRoll:
        _step(nowMs);
        if (_shown == null || !hasFreshData(nowMs)) return 0;
        // Frames already arrive uprighted in 90° steps; follow only the
        // remaining tilt so the picture never rotates twice.
        return residualRoll(wrap180(_shown!), _quant);
    }
  }

  void _step(int nowMs) {
    final t = _target;
    if (t == null) return;
    final last = _lastStepAtMs ?? nowMs;
    final dt = (nowMs - last).clamp(0, 500).toDouble();
    _lastStepAtMs = nowMs;
    final s = _shown ?? t;
    // unwrap shown toward target
    final target = s + angleDelta(s, t);
    final k = 1 - math.exp(-dt / timeConstantMs);
    _shown = s + (target - s) * k;
  }
}
