import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../settings/app_settings.dart';
import '../theme/kp_colors.dart';
import '../theme/kp_text.dart';

/// Interface orientation lock for CAMERA / PLAYBACK.
///
/// Locks only the *interface*. Capture, recording, the stream and the
/// camera roll data are untouched — rotating the phone while locked keeps
/// REC running and the session connected.
enum OrientationLock { auto, portrait, landscapeLeft, landscapeRight }

extension OrientationLockX on OrientationLock {
  String get label => switch (this) {
        OrientationLock.auto => 'AUTO',
        OrientationLock.portrait => 'LOCK PORTRAIT',
        OrientationLock.landscapeLeft => 'LOCK LANDSCAPE LEFT',
        OrientationLock.landscapeRight => 'LOCK LANDSCAPE RIGHT',
      };

  IconData get icon => switch (this) {
        OrientationLock.auto => Icons.screen_rotation,
        OrientationLock.portrait => Icons.screen_lock_portrait,
        OrientationLock.landscapeLeft => Icons.screen_lock_landscape,
        OrientationLock.landscapeRight => Icons.screen_lock_landscape,
      };

  List<DeviceOrientation> get orientations => switch (this) {
        OrientationLock.auto => const [],
        OrientationLock.portrait => const [DeviceOrientation.portraitUp],
        OrientationLock.landscapeLeft => const [DeviceOrientation.landscapeLeft],
        OrientationLock.landscapeRight => const [DeviceOrientation.landscapeRight],
      };

  static OrientationLock parse(String? s) =>
      OrientationLock.values.firstWhere((e) => e.name == s, orElse: () => OrientationLock.auto);
}

Future<void> applyOrientationLock(OrientationLock lock) =>
    SystemChrome.setPreferredOrientations(lock.orientations);

/// Compact button with a menu of the four modes.
class OrientationLockButton extends StatelessWidget {
  const OrientationLockButton({super.key, required this.settings, this.size = 44});

  final AppSettings settings;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lock = OrientationLockX.parse(settings.orientationLock);
    final active = lock != OrientationLock.auto;
    return PopupMenuButton<OrientationLock>(
      tooltip: 'Ориентация интерфейса: ${lock.label}',
      color: KpColors.surface2,
      onSelected: (v) {
        settings.update((s) => s.orientationLock = v.name);
        applyOrientationLock(v);
      },
      itemBuilder: (_) => [
        for (final v in OrientationLock.values)
          PopupMenuItem(
            value: v,
            child: Row(children: [
              Icon(v.icon, size: 18, color: v == lock ? KpColors.text : KpColors.textDim),
              const SizedBox(width: 10),
              Text(v.label, style: KpText.label.copyWith(fontSize: 12, color: v == lock ? KpColors.text : KpColors.textDim)),
            ]),
          ),
      ],
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? KpColors.text.withValues(alpha: 0.14) : const Color(0x99000000),
          border: Border.all(color: active ? KpColors.text : KpColors.strokeStrong),
        ),
        child: Icon(lock.icon, size: size * 0.45, color: KpColors.text),
      ),
    );
  }
}
