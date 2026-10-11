import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kp_colors.dart';
import 'kp_text.dart';

/// Spacing / radius scale. Tight geometry: small radii, 4-pt grid.
abstract final class KpSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class KpRadius {
  static const double s = 6;
  static const double m = 10;
  static const double l = 14;
}

ThemeData buildKpTheme() {
  const scheme = ColorScheme.dark(
    primary: KpColors.text,
    onPrimary: KpColors.bg,
    secondary: KpColors.live,
    onSecondary: KpColors.bg,
    error: KpColors.rec,
    onError: KpColors.text,
    surface: KpColors.surface,
    onSurface: KpColors.text,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: KpText.family,
    scaffoldBackgroundColor: KpColors.bg,
    canvasColor: KpColors.bg,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: KpText.family,
      bodyColor: KpColors.text,
      displayColor: KpColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KpColors.bg,
      foregroundColor: KpColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: KpText.heading,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    dividerTheme: const DividerThemeData(color: KpColors.stroke, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: KpColors.text, size: 22),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : KpColors.textDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? KpColors.live : KpColors.surface3,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KpColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: KpColors.strokeStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KpRadius.l)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: KpColors.surface2,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: KpText.heading,
      contentTextStyle: KpText.bodyDim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(KpRadius.l)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: KpColors.surface3,
      contentTextStyle: KpText.body,
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: KpColors.surface2,
      labelStyle: KpText.bodyDim,
      hintStyle: TextStyle(color: KpColors.textMute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(KpRadius.m)),
        borderSide: BorderSide(color: KpColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(KpRadius.m)),
        borderSide: BorderSide(color: KpColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(KpRadius.m)),
        borderSide: BorderSide(color: KpColors.select),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KpColors.text,
        textStyle: KpText.label,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: KpColors.text),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: KpColors.surface3,
        borderRadius: BorderRadius.all(Radius.circular(KpRadius.s)),
      ),
      textStyle: KpText.caption,
    ),
  );
}
