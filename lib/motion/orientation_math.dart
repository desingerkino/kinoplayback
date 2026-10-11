import 'dart:math' as math;
import 'dart:ui';

/// Pure maths for Camera Motion Sync, tap mapping and rotated display.
/// Kept free of Flutter widgets so every case is unit-tested.

/// Normalises any angle to (-180, 180].
double wrap180(double deg) {
  var a = deg % 360;
  if (a > 180) a -= 360;
  if (a <= -180) a += 360;
  return a;
}

/// Shortest signed difference `to - from`, in (-180, 180].
double angleDelta(double from, double to) => wrap180(to - from);

/// Camera roll around the optical axis from the gravity vector in device
/// coordinates (Android convention, also used by sensors_plus on iOS:
/// x → right edge, y → top edge, upright portrait gives y ≈ +9.8).
///
/// 0° = upright portrait, +90° = device turned counter-clockwise
/// (landscape, top edge pointing left), ±180° = upside down.
/// Returns null when the phone is lying (nearly) flat — roll is undefined
/// there and must not be invented.
double? rollFromGravity(double gx, double gy, {double minPlanar = 3.0}) {
  final planar = math.sqrt(gx * gx + gy * gy);
  if (planar < minPlanar) return null;
  return wrap180(math.atan2(gx, gy) * 180 / math.pi);
}

/// The 90° step a capture pipeline uprights frames to for a given roll
/// (nearest multiple of 90 — what UI/device orientation does).
int quantizedOrientation(double roll) {
  final q = (roll / 90).round() * 90;
  return wrap180(q.toDouble()).round();
}

/// Residual tilt that the 90° frame uprighting does *not* remove.
double residualRoll(double roll, [int? quant]) => wrap180(roll - (quant ?? quantizedOrientation(roll)));

/// 90° quantisation with hysteresis, like device-orientation detection:
/// stays on [current] until the roll is more than [threshold]° away from it.
int quantizeWithHysteresis(double roll, int current, {double threshold = 55}) {
  if (angleDelta(current.toDouble(), roll).abs() <= threshold) return current;
  return quantizedOrientation(roll);
}

/// Exponential low-pass filter for a 3-axis signal (gravity estimate from
/// the accelerometer). Unlike integrating the gyroscope it cannot drift.
class GravityFilter {
  GravityFilter({this.alpha = 0.15});
  final double alpha;
  double? x, y, z;

  void add(double ax, double ay, double az) {
    if (x == null) {
      x = ax;
      y = ay;
      z = az;
      return;
    }
    x = x! + alpha * (ax - x!);
    y = y! + alpha * (ay - y!);
    z = z! + alpha * (az - z!);
  }
}

/// Scale that makes a picture of [aspect] (w/h), rotated by [deg] about its
/// centre, fit entirely inside [box] (contain) — no stretching, no crop.
double rotatedFitScale(Size box, double aspect, double deg) {
  if (box.isEmpty || aspect <= 0) return 1;
  // Picture contain-fitted at 0° first.
  double w, h;
  if (box.width / box.height > aspect) {
    h = box.height;
    w = h * aspect;
  } else {
    w = box.width;
    h = w / aspect;
  }
  final r = deg * math.pi / 180;
  final c = math.cos(r).abs(), s = math.sin(r).abs();
  final bw = w * c + h * s;
  final bh = w * s + h * c;
  return math.min(box.width / bw, box.height / bh).clamp(0.0, 10.0);
}

/// Maps a tap in a monitor widget to normalised coordinates (0..1, origin
/// top-left) of the *picture as delivered by the camera pipeline*, undoing
/// what the display did on top of it:
///  * contain/cover fit ([cover]),
///  * extra display rotation ([rotationDeg], e.g. Follow Camera Roll),
///  * uniform display scale ([scale]),
///  * horizontal mirror ([mirrored]).
/// Returns null when the tap lands outside the picture.
Offset? tapToPicture({
  required Offset tap,
  required Size box,
  required double aspect,
  bool cover = false,
  double rotationDeg = 0,
  double scale = 1,
  bool mirrored = false,
}) {
  if (box.isEmpty || aspect <= 0) return null;
  final c = box.center(Offset.zero);
  // Undo rotation + scale around the widget centre.
  final r = -rotationDeg * math.pi / 180;
  final v = (tap - c) / (scale == 0 ? 1 : scale);
  final unrot = Offset(v.dx * math.cos(r) - v.dy * math.sin(r), v.dx * math.sin(r) + v.dy * math.cos(r)) + c;
  // Picture rect inside the box.
  double w, h;
  final boxAspect = box.width / box.height;
  final widthLimited = cover ? boxAspect < aspect : boxAspect > aspect;
  if (widthLimited) {
    h = box.height;
    w = h * aspect;
  } else {
    w = box.width;
    h = w / aspect;
  }
  final left = (box.width - w) / 2, top = (box.height - h) / 2;
  var nx = (unrot.dx - left) / w;
  final ny = (unrot.dy - top) / h;
  if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return null;
  if (mirrored) nx = 1 - nx;
  return Offset(nx, ny);
}

/// Inverse of [tapToPicture]: where a picture point is drawn in the widget
/// (for focus / exposure reticles).
Offset pictureToWidget({
  required Offset point,
  required Size box,
  required double aspect,
  bool cover = false,
  double rotationDeg = 0,
  double scale = 1,
  bool mirrored = false,
}) {
  double w, h;
  final boxAspect = box.width / box.height;
  final widthLimited = cover ? boxAspect < aspect : boxAspect > aspect;
  if (widthLimited) {
    h = box.height;
    w = h * aspect;
  } else {
    w = box.width;
    h = w / aspect;
  }
  final left = (box.width - w) / 2, top = (box.height - h) / 2;
  final nx = mirrored ? 1 - point.dx : point.dx;
  final p = Offset(left + nx * w, top + point.dy * h);
  final c = box.center(Offset.zero);
  final r = rotationDeg * math.pi / 180;
  final v = p - c;
  final rot = Offset(v.dx * math.cos(r) - v.dy * math.sin(r), v.dx * math.sin(r) + v.dy * math.cos(r));
  return c + rot * scale;
}
