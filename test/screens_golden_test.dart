@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/app/app_scope.dart';
import 'package:kinoplayback/app/launch_screen.dart';
import 'package:kinoplayback/camera/camera_screen.dart';
import 'package:kinoplayback/core/device_identity.dart';
import 'package:kinoplayback/core/theme/kp_theme.dart';
import 'package:kinoplayback/network/net_utils.dart';
import 'package:kinoplayback/playback/playback_screen.dart';
import 'package:kinoplayback/recording/takes.dart';
import 'package:kinoplayback/settings/app_settings.dart';
import 'package:kinoplayback/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the real screens at phone / tablet sizes in both orientations
/// with the real font, checks for layout exceptions, and writes PNGs
/// (run with --update-goldens) so the layouts can be reviewed without a
/// device. Platform plugins are replaced by channel mocks: the camera
/// "opens" a 4K/30 track with no frames, so the video area is black.
const sizes = <String, Size>{
  'phone_portrait': Size(393, 852),
  'phone_landscape': Size(852, 393),
  'small_landscape': Size(667, 375),
  'tablet_landscape': Size(1180, 820),
  'tablet_portrait': Size(820, 1180),
};

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await icons.load();
    }
  }
}

void _mockPlugins() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('FlutterWebRTC.Method'), (call) async {
    switch (call.method) {
      case 'createVideoRenderer':
        return {'textureId': 1};
      case 'getUserMedia':
        return {
          'streamId': 's1',
          'audioTracks': [
            {'id': 'a1', 'label': 'a1', 'kind': 'audio', 'enabled': true, 'settings': {}},
          ],
          'videoTracks': [
            {
              'id': 'v1',
              'label': 'v1',
              'kind': 'video',
              'enabled': true,
              'settings': {'width': 3840, 'height': 2160, 'frameRate': 30, 'facingMode': 'environment'},
            },
          ],
        };
      default:
        return null;
    }
  });
  for (final name in ['FlutterWebRTC/Texture1', 'FlutterWebRTC.Event']) {
    m.setMockStreamHandler(EventChannel(name), MockStreamHandler.inline(onListen: (args, sink) {}));
  }
  m.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/battery'), (call) async => 82);
  m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async => 1);
}

late AppSettings _preloaded;

AppServices _services() => AppServices(
      settings: _preloaded,
      takes: TakesRepository.forDirectory(Directory.systemTemp.createTempSync('kp_g')),
      identity: DeviceIdentity(
        platform: 'iOS',
        model: 'iPhone 15 Pro',
        osVersion: '18.0',
        appVersion: '0.1.0 (1)',
        isTablet: false,
        isPhysical: true,
      ),
    );

Widget _host(AppServices s, Widget child) => AppScope(
      services: s,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildKpTheme(), home: child),
    );

Future<void> _shot(WidgetTester t, String name, Size size, Widget Function() screen) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final s = _services();
  await t.pumpWidget(_host(s, screen()));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.takeException(), isNull, reason: '$name: layout exception');
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  // Tear down so controllers stop their timers.
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
  await t.pump(const Duration(seconds: 6));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    _mockPlugins();
    SharedPreferences.setMockInitialValues({
      'deviceName': 'iPhone (Актёр)',
      'keepScreenOn': false,
      'toolGrid': true,
      'remoteControlAllowed': true,
    });
    _preloaded = await AppSettings.load();
  });

  for (final e in sizes.entries) {
    testWidgets('launch ${e.key}', (t) => _shot(t, 'launch_${e.key}', e.value, () => const LaunchScreen()));
    testWidgets('camera ${e.key}', (t) => _shot(t, 'camera_${e.key}', e.value, () => const CameraScreen()));
    testWidgets('playback ${e.key}', (t) => _shot(t, 'playback_${e.key}', e.value,
        () => const PlaybackScreen(target: ConnectTarget('192.168.1.112', 47800, name: 'iPhone (Актёр)'))));
    testWidgets('settings ${e.key}', (t) => _shot(t, 'settings_${e.key}', e.value, () => const SettingsScreen()));
  }
}
