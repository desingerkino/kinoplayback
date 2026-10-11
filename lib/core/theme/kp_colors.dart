import 'package:flutter/painting.dart';

/// KINO PLAYBACK colour tokens (brand guide v1).
///
/// Black / graphite surfaces, white text, one red (#FF1E2D) reserved for REC,
/// active commands and critical warnings. Green appears only as a functional
/// "confirmed working" indicator, amber only for non-critical warnings.
/// No orange, blue or purple accents.
abstract final class KpColors {
  // Surfaces
  static const Color monitor = Color(0xFF000000);
  static const Color bg = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF121212);
  static const Color surface2 = Color(0xFF1B1B1B);
  static const Color surface3 = Color(0xFF252525);
  static const Color stroke = Color(0xFF2A2A2A);
  static const Color strokeStrong = Color(0xFF3A3A3A);

  // Text
  static const Color text = Color(0xFFFFFFFF);
  static const Color textDim = Color(0xFFA0A0A0);
  static const Color textMute = Color(0xFF636363);

  // Brand / state
  static const Color rec = Color(0xFFFF1E2D);
  static const Color recDeep = Color(0xFF7A0E16);
  static const Color live = Color(0xFF2FD36B); // functional only
  static const Color liveDeep = Color(0xFF0F3D22);
  static const Color warn = Color(0xFFFFC21A); // functional only
  static const Color alert = rec;
  static const Color inactive = Color(0xFF4A4A4A);

  /// Selection outline for tools / segmented controls (neutral, not a hue).
  static const Color select = Color(0xFFFFFFFF);

  /// Brand accent = brand red.
  static const Color brand = rec;

  // Overlays on top of video
  static const Color scrim = Color(0xB3000000);
  static const Color guide = Color(0xCCFFFFFF);
  static const Color guideSoft = Color(0x66FFFFFF);
}
