import 'package:flutter/material.dart';

import '../camera/camera_screen.dart';
import '../core/layout/adaptive.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/theme/kp_theme.dart';
import '../playback/devices_screen.dart';
import '../recording/takes_screen.dart';
import '../settings/settings_screen.dart';

/// Launch + mode selection. Two big targets: CAMERA and PLAYBACK.
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ff = formFactorOfContext(context);
    final logo = const _Logo();
    final cards = _ModeCards(vertical: !ff.isLandscape && ff.isPhone);
    final footer = _Footer();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KpSpace.l, vertical: KpSpace.m),
          child: ff.isLandscape
              ? Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [logo, const SizedBox(height: KpSpace.xl), footer],
                      ),
                    ),
                    const SizedBox(width: KpSpace.xl),
                    Expanded(flex: 6, child: Center(child: cards)),
                  ],
                )
              : Column(
                  children: [
                    const Spacer(flex: 3),
                    logo,
                    const Spacer(flex: 2),
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: cards),
                    const Spacer(flex: 2),
                    footer,
                  ],
                ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'KINO PLAYBACK',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('KINO', style: KpText.logo.copyWith(fontSize: 52, letterSpacing: 4)),
          const SizedBox(height: 2),
          Text('PLAYBACK', style: KpText.logo.copyWith(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 6)),
          const SizedBox(height: KpSpace.m),
          Text('PROFESSIONAL CINEMA MONITOR',
              textAlign: TextAlign.center,
              style: KpText.label.copyWith(color: KpColors.brand, fontSize: 11, letterSpacing: 2)),
        ],
      ),
    );
  }
}

class _ModeCards extends StatelessWidget {
  const _ModeCards({required this.vertical});
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final camera = _ModeCard(
      icon: Icons.photo_camera_outlined,
      title: 'CAMERA',
      subtitle: 'Снимать и передавать',
      detail: 'Оригинал пишется на этом устройстве',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CameraScreen())),
    );
    final playback = _ModeCard(
      icon: Icons.connected_tv_outlined,
      title: 'PLAYBACK',
      subtitle: 'Смотреть и управлять',
      detail: 'Монитор режиссёра, удалённый REC',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
    );
    return Row(
      children: [
        Expanded(child: camera),
        const SizedBox(width: KpSpace.m),
        Expanded(child: playback),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KpColors.surface,
      borderRadius: BorderRadius.circular(KpRadius.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(KpRadius.l),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: KpSpace.m, vertical: KpSpace.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KpRadius.l),
            border: Border.all(color: KpColors.strokeStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: KpColors.text),
              const SizedBox(height: KpSpace.m),
              Text(title, style: KpText.heading.copyWith(letterSpacing: 1.5)),
              const SizedBox(height: KpSpace.xs),
              Text(subtitle, style: KpText.bodyDim, textAlign: TextAlign.center),
              const SizedBox(height: KpSpace.s),
              Text(detail, style: KpText.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: KpSpace.s,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TakesScreen())),
          icon: const Icon(Icons.video_library_outlined, size: 18),
          label: const Text('Дубли'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Настройки'),
        ),
      ],
    );
  }
}
