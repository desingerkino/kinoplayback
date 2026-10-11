import 'package:flutter/painting.dart';

/// KINO PLAYBACK colour tokens.
///
/// Graphite surfaces around a pure-black monitor, one saturated red reserved
/// for REC, green for "ready / live", amber/orange for warnings. Accent gold
/// is brand-only (logo, launch screen) and never used for state.
abstract final class KpColors {
  // Surfaces
  static const Color monitor = Color(0xFF000000);
  static const Color bg = Color(0xFF07080A);
  static const Color surface = Color(0xFF101216);
  static const Color surface2 = Color(0xFF171A1F);
  static const Color surface3 = Color(0xFF20242A);
  static const Color stroke = Color(0xFF262A31);
  static const Color strokeStrong = Color(0xFF363C46);

  // Text
  static const Color text = Color(0xFFF2F4F7);
  static const Color textDim = Color(0xFF9BA3AE);
  static const Color textMute = Color(0xFF5E6672);

  // State
  static const Color rec = Color(0xFFE5322D);
  static const Color recDeep = Color(0xFF8E1814);
  static const Color live = Color(0xFF2FD36B);
  static const Color liveDeep = Color(0xFF0F3D22);
  static const Color warn = Color(0xFFF5A524);
  static const Color alert = Color(0xFFFF7A1A);
  static const Color inactive = Color(0xFF4A515C);

  /// Selection outline for tools / segmented controls.
  static const Color select = Color(0xFF4C8DFF);

  /// Brand accent (logo tagline only).
  static const Color brand = Color(0xFFE3A53B);

  // Overlays on top of video
  static const Color scrim = Color(0xB3000000);
  static const Color guide = Color(0xCCFFFFFF);
  static const Color guideSoft = Color(0x66FFFFFF);
}
