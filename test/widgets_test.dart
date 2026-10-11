import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/app/app_scope.dart';
import 'package:kinoplayback/app/launch_screen.dart';
import 'package:kinoplayback/core/device_identity.dart';
import 'package:kinoplayback/core/theme/kp_theme.dart';
import 'package:kinoplayback/core/widgets/kp_widgets.dart';
import 'package:kinoplayback/core/widgets/rec_widgets.dart';
import 'package:kinoplayback/monitor/monitor_chrome.dart';
import 'package:kinoplayback/recording/takes.dart';
import 'package:kinoplayback/recording/takes_screen.dart';
import 'package:kinoplayback/settings/app_settings.dart';
import 'package:kinoplayback/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = <String, Size>{
  'small phone portrait': Size(320, 568),
  'phone portrait': Size(390, 844),
  'phone landscape': Size(844, 390),
  'small phone landscape': Size(568, 320),
  'tablet portrait': Size(820, 1180),
  'tablet landscape': Size(1180, 820),
};

Future<AppServices> services() async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  settings.deviceName = 'Test iPhone';
  final dir = await Directory.systemTemp.createTemp('kp_takes');
  return AppServices(
    settings: settings,
    takes: TakesRepository.forDirectory(dir),
    identity: DeviceIdentity(
      platform: 'iOS',
      model: 'iPhone 15 Pro',
      osVersion: '18.0',
      appVersion: '0.1.0 (1)',
      isTablet: false,
      isPhysical: true,
    ),
  );
}

Widget host(AppServices s, Widget child) => AppScope(
      services: s,
      child: MaterialApp(theme: buildKpTheme(), home: child),
    );

Future<void> setSize(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  for (final e in sizes.entries) {
    testWidgets('launch screen lays out without overflow: ${e.key}', (t) async {
      await setSize(t, e.value);
      final s = await services();
      await t.pumpWidget(host(s, const LaunchScreen()));
      await t.pump();
      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('PLAYBACK'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('settings screen lays out: ${e.key}', (t) async {
      await setSize(t, e.value);
      final s = await services();
      await t.pumpWidget(host(s, const SettingsScreen()));
      await t.pump();
      expect(find.text('Настройки'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('takes screen (empty) lays out: ${e.key}', (t) async {
      await setSize(t, e.value);
      final s = await services();
      await t.pumpWidget(host(s, const TakesScreen()));
      await t.pump();
      expect(find.text('Записей пока нет'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('REC button renders every state', (t) async {
    for (final st in RecVisual.values) {
      await t.pumpWidget(MaterialApp(
        theme: buildKpTheme(),
        home: Scaffold(body: Center(child: RecButton(state: st, onPressed: () {}))),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(RecButton), findsOneWidget);
    }
  });

  testWidgets('REC button: pressing calls back, disabled does not', (t) async {
    var n = 0;
    await t.pumpWidget(MaterialApp(home: Center(child: RecButton(state: RecVisual.idle, onPressed: () => n++))));
    await t.tap(find.byType(RecButton));
    expect(n, 1);
    await t.pumpWidget(MaterialApp(home: Center(child: RecButton(state: RecVisual.disabled, onPressed: () => n++))));
    await t.tap(find.byType(RecButton));
    expect(n, 1);
  });

  test('timecode format', () {
    expect(formatTimecode(const Duration(hours: 1, minutes: 24, seconds: 18)), '01:24:18');
    expect(formatTimecode(Duration.zero), '00:00:00');
    expect(formatTimecode(const Duration(seconds: -3)), '00:00:00');
  });

  testWidgets('status strip clips instead of overflowing on a narrow width', (t) async {
    await setSize(t, const Size(320, 100));
    await t.pumpWidget(MaterialApp(
      theme: buildKpTheme(),
      home: Scaffold(
        body: StatusStrip(
          leading: [for (var i = 0; i < 12; i++) StripItem('ITEM $i')],
          trailing: const [StripItem('99%')],
        ),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('segmented control switches value', (t) async {
    var v = 'a';
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => KpSegmented<String>(
            values: const ['a', 'b'],
            selected: v,
            labelOf: (x) => x.toUpperCase(),
            onChanged: (x) => set(() => v = x),
          ),
        ),
      ),
    ));
    await t.tap(find.text('B'));
    await t.pump();
    expect(v, 'b');
  });

  test('clip names increment and persist', () async {
    final s = await services();
    expect(s.settings.takeNextClipName(), 'A001_C001');
    expect(s.settings.takeNextClipName(), 'A001_C002');
    final reloaded = await AppSettings.load();
    expect(reloaded.nextClip, 3);
  });
}
