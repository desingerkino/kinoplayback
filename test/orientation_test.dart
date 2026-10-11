import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/motion/orientation_math.dart';
import 'package:kinoplayback/motion/orientation_sync.dart';

void main() {
  group('angles', () {
    test('wrap180 and shortest delta across 0/360', () {
      expect(wrap180(190), -170);
      expect(wrap180(-190), 170);
      expect(wrap180(540), 180);
      expect(angleDelta(170, -170), 20);
      expect(angleDelta(-170, 170), -20);
      expect(angleDelta(359, 1), 2);
    });

    test('roll from gravity (device frame, Android convention)', () {
      expect(rollFromGravity(0, 9.81), closeTo(0, 1e-9)); // upright portrait
      expect(rollFromGravity(9.81, 0), closeTo(90, 1e-9)); // turned CCW
      expect(rollFromGravity(-9.81, 0), closeTo(-90, 1e-9));
      expect(rollFromGravity(0, -9.81)!.abs(), closeTo(180, 1e-9));
      final g = 9.81;
      expect(rollFromGravity(g * math.sin(30 * math.pi / 180), g * math.cos(30 * math.pi / 180)), closeTo(30, 1e-9));
      expect(rollFromGravity(0.5, 0.5), isNull, reason: 'flat phone: undefined roll, not invented');
    });

    test('quantisation and residual', () {
      expect(quantizedOrientation(30), 0);
      expect(quantizedOrientation(50), 90);
      expect(quantizedOrientation(-130), -90);
      expect(residualRoll(32), 32);
      expect(residualRoll(100), 10);
      expect(residualRoll(-170), 10);
      expect(residualRoll(50, 0), 50, reason: 'explicit quant from the camera wins');
    });

    test('hysteresis keeps the current step near the boundary', () {
      expect(quantizeWithHysteresis(50, 0), 0);
      expect(quantizeWithHysteresis(60, 0), 90);
      expect(quantizeWithHysteresis(40, 90), 90);
      expect(quantizeWithHysteresis(30, 90), 0);
    });

    test('gravity filter converges and smooths', () {
      final f = GravityFilter(alpha: 0.5);
      f.add(0, 10, 0);
      for (var i = 0; i < 20; i++) {
        f.add(10, 0, 0);
      }
      expect(f.x, closeTo(10, 1e-3));
      expect(f.y, closeTo(0, 1e-3));
    });
  });

  group('rotated fit', () {
    test('no rotation fills the contain rect', () {
      expect(rotatedFitScale(const Size(1600, 900), 16 / 9, 0), closeTo(1, 1e-9));
    });
    test('90° on a 16:9 box shrinks so the picture still fits, no stretch', () {
      final s = rotatedFitScale(const Size(1600, 900), 16 / 9, 90);
      expect(s, closeTo(900 / 1600, 1e-9));
    });
    test('small tilt shrinks slightly', () {
      final s = rotatedFitScale(const Size(1600, 900), 16 / 9, 10);
      expect(s, lessThan(1));
      expect(s, greaterThan(0.7));
    });
  });

  group('tap mapping', () {
    const box = Size(400, 300);
    const aspect = 16 / 9; // picture 400×225, top 37.5

    test('centre maps to centre in every transform', () {
      for (final rot in [0.0, 30.0, 90.0, -45.0]) {
        for (final mirrored in [false, true]) {
          final p = tapToPicture(tap: const Offset(200, 150), box: box, aspect: aspect, rotationDeg: rot, mirrored: mirrored);
          expect(p!.dx, closeTo(0.5, 1e-9));
          expect(p.dy, closeTo(0.5, 1e-9));
        }
      }
    });

    test('letterbox area is outside the picture', () {
      expect(tapToPicture(tap: const Offset(200, 10), box: box, aspect: aspect), isNull);
    });

    test('mirror flips x: tapping the left of a mirrored preview hits the right of the sensor', () {
      final p = tapToPicture(tap: const Offset(100, 150), box: box, aspect: aspect, mirrored: true)!;
      expect(p.dx, closeTo(0.75, 1e-9));
    });

    test('round-trip with rotation, scale, mirror and cover', () {
      for (final cover in [false, true]) {
        for (final rot in [0.0, 17.0, 90.0, -120.0]) {
          for (final mirrored in [false, true]) {
            const pt = Offset(0.3, 0.7);
            final w = pictureToWidget(
                point: pt, box: box, aspect: aspect, cover: cover, rotationDeg: rot, scale: 0.8, mirrored: mirrored);
            final back = tapToPicture(
                tap: w, box: box, aspect: aspect, cover: cover, rotationDeg: rot, scale: 0.8, mirrored: mirrored);
            expect(back, isNotNull, reason: 'cover=$cover rot=$rot mirror=$mirrored');
            expect(back!.dx, closeTo(pt.dx, 1e-9));
            expect(back.dy, closeTo(pt.dy, 1e-9));
          }
        }
      }
    });
  });

  group('CameraOrientationSync', () {
    MotionSample s(int seq, double roll, {bool ok = true, String? sid = 's1', int? q}) =>
        MotionSample(sessionId: sid, seq: seq, tMs: seq * 66, roll: roll, valid: ok, quant: q);

    test('auto sync never adds rotation', () {
      final o = CameraOrientationSync()..reset('s1');
      o.ingest(s(1, 30), 0);
      expect(o.displayRotation(100, frameIsPortrait: false), 0);
    });

    test('follow roll converges to the residual tilt', () {
      final o = CameraOrientationSync()
        ..reset('s1')
        ..mode = RotationMode.followRoll;
      o.ingest(s(1, 0, q: 0), 0);
      o.displayRotation(0, frameIsPortrait: false);
      o.ingest(s(2, 32, q: 0), 10);
      var r = 0.0;
      for (var t = 10; t <= 600; t += 16) {
        r = o.displayRotation(t, frameIsPortrait: false);
      }
      expect(r, closeTo(32, 0.5));
    });

    test('crossing ±180 takes the short way (no 360° spin)', () {
      final o = CameraOrientationSync()
        ..reset('s1')
        ..mode = RotationMode.followRoll;
      o.ingest(s(1, 175, q: 180), 0);
      o.displayRotation(0, frameIsPortrait: false);
      o.ingest(s(2, -175, q: 180), 5);
      // halfway through smoothing the residual stays between -5 and +5,
      // never sweeping through 0..350
      for (var t = 5; t <= 400; t += 16) {
        final r = o.displayRotation(t, frameIsPortrait: false);
        expect(r.abs(), lessThanOrEqualTo(5.0001));
      }
    });

    test('late, duplicate and foreign-session samples are ignored', () {
      final o = CameraOrientationSync()..reset('s1');
      expect(o.ingest(s(5, 10), 0), isTrue);
      expect(o.ingest(s(5, 20), 1), isFalse);
      expect(o.ingest(s(4, 20), 2), isFalse);
      expect(o.ingest(s(6, 20, sid: 's-other'), 3), isFalse);
      expect(o.cameraRoll, 10);
    });

    test('stale data → NO DATA, no frozen fake angle', () {
      final o = CameraOrientationSync()
        ..reset('s1')
        ..mode = RotationMode.followRoll;
      o.ingest(s(1, 20, q: 0), 0);
      expect(o.hasFreshData(500), isTrue);
      expect(o.hasFreshData(2000), isFalse);
      expect(o.displayRotation(2000, frameIsPortrait: false), 0);
    });

    test('invalid samples (phone flat) report no roll', () {
      final o = CameraOrientationSync()..reset('s1');
      o.ingest(s(1, 0, ok: false), 0);
      expect(o.cameraRoll, isNull);
    });

    test('reset on new session clears state', () {
      final o = CameraOrientationSync()..reset('s1');
      o.ingest(s(9, 40), 0);
      o.reset('s2');
      expect(o.cameraRoll, isNull);
      expect(o.ingest(s(1, 5, sid: 's2'), 1), isTrue);
    });

    test('lock modes and manual', () {
      final o = CameraOrientationSync();
      o.mode = RotationMode.lockLandscape;
      expect(o.displayRotation(0, frameIsPortrait: true), 90);
      expect(o.displayRotation(0, frameIsPortrait: false), 0);
      o.mode = RotationMode.lockPortrait;
      expect(o.displayRotation(0, frameIsPortrait: false), 90);
      o
        ..mode = RotationMode.manual
        ..manualDeg = 270;
      expect(o.displayRotation(0, frameIsPortrait: false), -90);
    });

    test('invert flips the direction', () {
      final o = CameraOrientationSync()
        ..reset('s1')
        ..invert = true;
      o.ingest(s(1, 25), 0);
      expect(o.cameraRoll, -25);
    });

    test('sample json round-trip', () {
      final m = MotionSample.fromJson(s(3, 12.346, q: 90).toJson(), sessionId: 's1')!;
      expect(m.seq, 3);
      expect(m.roll, closeTo(12.35, 1e-9));
      expect(m.quant, 90);
      expect(m.valid, isTrue);
    });
  });
}
