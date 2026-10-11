import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/protocol/camera_state.dart';
import 'package:kinoplayback/transmitters/catalog.dart';

void main() {
  test('required models are present, ATOM A5 is not', () {
    final names = kTransmitters.map((m) => m.fullName).toSet();
    for (final n in [
      'VAXIS ATOM 500 SDI',
      'VAXIS ATOM 500 HDMI',
      'VAXIS ATOM 600 HDMI',
      'VAXIS STORM 1000S',
      'VAXIS STORM 3000',
      'VAXIS STORM 3000 DV',
      'VAXIS STORM 3000 DG',
      'Accsoon CineView SE 4K',
      'Accsoon CineView 2 SDI',
      'Accsoon CineEye 2S Pro',
      'Accsoon CineView QUAD',
      'Accsoon SeeMo Pro',
    ]) {
      expect(names, contains(n));
    }
    expect(names.any((n) => n.contains('A5')), isFalse);
  });

  test('nothing is claimed as tested without a physical test', () {
    for (final m in kTransmitters) {
      for (final s in m.scenarios.values) {
        expect(s.status, isNot(CompatStatus.supportedTested), reason: m.fullName);
      }
    }
  });

  test('every model has a source and all three scenarios', () {
    for (final m in kTransmitters) {
      expect(m.sources, isNotEmpty, reason: m.fullName);
      expect(m.scenarios.keys.toSet(), Scenario.values.toSet(), reason: m.fullName);
      expect(m.sources.every((s) => s.url.startsWith('https://')), isTrue);
    }
  });

  test('SeeMo Pro is a capture adapter, not a transmitter', () {
    final m = kTransmitters.firstWhere((m) => m.id == 'accsoon-seemo-pro');
    expect(m.category, DeviceCategory.captureAdapter);
  });

  test('camera caps travel in the state snapshot', () {
    const st = CameraStateSnapshot(
      seq: 1,
      recording: false,
      elapsedMs: 0,
      remoteControlAllowed: false,
      remoteCameraControl: true,
      afLocked: true,
      focusPoint: (0.25, 0.75),
      caps: CameraCaps(focusPoint: true, focusLock: true, motion: true),
      externalSource: 'USB Video',
    );
    final d = CameraStateSnapshot.fromJson(st.toJson());
    expect(d.remoteCameraControl, isTrue);
    expect(d.afLocked, isTrue);
    expect(d.focusPoint, (0.25, 0.75));
    expect(d.caps.focusPoint, isTrue);
    expect(d.caps.exposureLock, isFalse);
    expect(d.caps.motion, isTrue);
    expect(d.externalSource, 'USB Video');
    expect(d.mirrorApplied, isFalse);
  });
}
