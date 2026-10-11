import 'package:flutter/painting.dart';

import 'kp_colors.dart';

/// Typography: Inter (Cyrillic + Latin) everywhere. Every number on screen
/// uses tabular figures so timers and metrics don't jitter.
abstract final class KpText {
  static const String family = 'Inter';
  static const List<FontFeature> _tab = [FontFeature.tabularFigures()];

  /// Wordmark face (Unbounded, Latin only) — used for KINO / PLAYBACK.
  static const String wordmarkFamily = 'Unbounded';

  static const TextStyle logo = TextStyle(
    fontFamily: wordmarkFamily,
    fontSize: 44,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    height: 1.0,
    color: KpColors.text,
  );

  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: KpColors.text,
  );

  static const TextStyle heading = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: KpColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: KpColors.text,
  );

  static const TextStyle bodyDim = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: KpColors.textDim,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: KpColors.textDim,
  );

  /// Uppercase technical labels: "CAMERA", "LIVE", "4K".
  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: KpColors.text,
  );

  /// Compact metric values in status strips.
  static const TextStyle metric = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFeatures: _tab,
    color: KpColors.text,
  );

  static const TextStyle metricSmall = TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    fontFeatures: _tab,
    color: KpColors.textDim,
  );

  /// Big REC timecode.
  static const TextStyle timecode = TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    fontFeatures: _tab,
    letterSpacing: 0.5,
    color: KpColors.text,
  );
}
