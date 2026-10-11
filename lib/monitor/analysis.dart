import 'dart:typed_data';

/// Pixel analysis of a *decoded* frame (what PLAYBACK received, or what the
/// preview shows) — not of the camera sensor signal. Values are 8-bit
/// Rec.709 luma of the delivered picture, so they reflect the stream after
/// compression and the device's own processing.

/// Rec.709 luma 0..255 for one RGBA pixel.
int luma709(int r, int g, int b) => ((r * 2126 + g * 7152 + b * 722) / 10000).round().clamp(0, 255);

/// Luma histogram with [bins] buckets from an RGBA buffer.
List<int> lumaHistogram(Uint8List rgba, {int bins = 64}) {
  final h = List<int>.filled(bins, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final y = luma709(rgba[i], rgba[i + 1], rgba[i + 2]);
    h[(y * bins) >> 8]++;
  }
  return h;
}

/// Zebra overlay: diagonal stripes on pixels with luma ≥ [threshold]
/// (0..255; 242 ≈ 95 %). Returns RGBA with transparent background.
Uint8List zebraOverlay(Uint8List rgba, int width, int height, {int threshold = 242}) {
  final out = Uint8List(rgba.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (i + 3 >= rgba.length) break;
      final l = luma709(rgba[i], rgba[i + 1], rgba[i + 2]);
      if (l >= threshold && ((x + y) ~/ 3) % 2 == 0) {
        out[i] = 255;
        out[i + 1] = 255;
        out[i + 2] = 255;
        out[i + 3] = 200;
      }
    }
  }
  return out;
}

/// False-colour bands (8-bit luma of the decoded picture). Similar layout to
/// common monitor false colour, but calibrated to display-referred luma.
const List<(int, int, int, int)> falseColorBands = [
  // (maxLuma, r, g, b)
  (6, 92, 0, 160), // purple — crushed blacks
  (26, 0, 72, 230), // blue — near black
  (64, 40, 110, 140), // teal — shadows
  (102, 105, 105, 105), // dark grey
  (118, 0, 190, 70), // green — ~18 % grey
  (153, 140, 140, 140), // light grey
  (166, 255, 150, 180), // pink — skin highlight (~one stop over)
  (204, 190, 190, 190), // light
  (242, 255, 220, 0), // yellow — near clip
  (255, 230, 0, 0), // red — clipped
];

Uint8List falseColorImage(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final l = luma709(rgba[i], rgba[i + 1], rgba[i + 2]);
    var c = falseColorBands.last;
    for (final b in falseColorBands) {
      if (l <= b.$1) {
        c = b;
        break;
      }
    }
    out[i] = c.$2;
    out[i + 1] = c.$3;
    out[i + 2] = c.$4;
    out[i + 3] = 255;
  }
  return out;
}

/// Fraction (0..1) of pixels at or above [threshold] — "clipping" readout.
double clippedFraction(List<int> histogram, {int fromBin = 62}) {
  final total = histogram.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 0;
  var c = 0;
  for (var i = fromBin; i < histogram.length; i++) {
    c += histogram[i];
  }
  return c / total;
}
