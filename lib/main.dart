import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app/app_scope.dart';
import 'app/launch_screen.dart';
import 'core/device_identity.dart';
import 'core/event_log.dart';
import 'core/theme/kp_theme.dart';
import 'protocol/messages.dart';
import 'recording/takes.dart';
import 'settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logE('flutter', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logE('dart', '$error');
    return true;
  };

  // All orientations: CAMERA and PLAYBACK are designed landscape-first.
  await SystemChrome.setPreferredOrientations(const []);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF07080A),
  ));

  // CAMERA records a scene, not a phone call: on iOS bypass the voice
  // processing unit (echo cancellation / noise suppression / AGC) so the
  // microphone sounds natural. Must run before any other WebRTC call.
  if (Platform.isIOS) {
    try {
      await WebRTC.initialize(options: {'bypassVoiceProcessing': true});
    } catch (e) {
      logW('app', 'WebRTC init options: $e');
    }
  }

  final settings = await AppSettings.load();
  final takes = await TakesRepository.open();
  final view = PlatformDispatcher.instance.views.first;
  final logical = view.physicalSize / view.devicePixelRatio;
  final identity = await DeviceIdentity.load(isTablet: logical.shortestSide >= 600);

  if (settings.clientId.isEmpty) settings.update((s) => s.clientId = newId('dev'));
  if (settings.deviceName.isEmpty) {
    settings.update((s) => s.deviceName = identity.model == '—' ? 'KINO ${identity.platform}' : identity.model);
  }
  logI('app', 'KINO PLAYBACK ${identity.appVersion} · ${identity.platform} ${identity.osVersion} · ${identity.model}');

  runApp(KinoPlaybackApp(services: AppServices(settings: settings, takes: takes, identity: identity)));
}

class KinoPlaybackApp extends StatelessWidget {
  const KinoPlaybackApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'KINO PLAYBACK',
        debugShowCheckedModeBanner: false,
        theme: buildKpTheme(),
        darkTheme: buildKpTheme(),
        themeMode: ThemeMode.dark,
        home: const LaunchScreen(),
      ),
    );
  }
}
