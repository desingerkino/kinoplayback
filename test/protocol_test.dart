import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/protocol/camera_state.dart';
import 'package:kinoplayback/protocol/messages.dart';

void main() {
  group('KpMessage envelope', () {
    test('round-trips all fields', () {
      final m = KpMessage(type: MsgType.recStart, sessionId: 's-1', payload: {'a': 1, 'b': 'x'});
      final d = KpMessage.decode(m.encode());
      expect(d.type, MsgType.recStart);
      expect(d.id, m.id);
      expect(d.ts, m.ts);
      expect(d.sessionId, 's-1');
      expect(d.payload, {'a': 1, 'b': 'x'});
      expect(d.version, kProtocolVersion);
    });

    test('ids are unique and prefixed', () {
      final ids = List.generate(500, (_) => newId('c')).toSet();
      expect(ids.length, 500);
      expect(ids.every((e) => e.startsWith('c-') && e.length == 18), isTrue);
    });

    test('wire format uses the documented short keys', () {
      final j = KpMessage(type: 'ping', id: 'm-1', ts: 5).toJson();
      expect(j.keys.toSet(), {'v', 't', 'id', 'ts', 'p'});
    });

    for (final bad in <String>[
      'not json',
      '[]',
      '{"t":"x","id":"a","ts":1,"p":{}}', // no v
      '{"v":1,"id":"a","ts":1,"p":{}}', // no t
      '{"v":1,"t":"x","ts":1,"p":{}}', // no id
      '{"v":1,"t":"x","id":"a","p":{}}', // no ts
      '{"v":1,"t":"x","id":"a","ts":1,"p":[]}', // payload not object
      '{"v":99,"t":"x","id":"a","ts":1,"p":{}}', // future version
      '{"v":1,"t":"x","id":"a","ts":1,"sid":5,"p":{}}', // bad sid
    ]) {
      test('rejects malformed: $bad', () {
        expect(() => KpMessage.decode(bad), throwsFormatException);
      });
    }

    test('missing payload defaults to empty object', () {
      final d = KpMessage.decode('{"v":1,"t":"ping","id":"a","ts":1}');
      expect(d.payload, isEmpty);
    });
  });

  group('CmdStage wire mapping', () {
    test('final stages', () {
      expect(CmdStage.done.isFinal, isTrue);
      expect(CmdStage.rejected.isFinal, isTrue);
      expect(CmdStage.failed.isFinal, isTrue);
      expect(CmdStage.timedOut.isFinal, isTrue);
      expect(CmdStage.accepted.isFinal, isFalse);
      expect(CmdStage.received.isFinal, isFalse);
    });

    test('remote stages round-trip', () {
      for (final s in [CmdStage.received, CmdStage.accepted, CmdStage.rejected, CmdStage.done, CmdStage.failed]) {
        expect(CmdStageX.fromWire(s.wire), s);
      }
      expect(CmdStageX.fromWire('bogus'), isNull);
    });
  });

  group('CameraStateSnapshot', () {
    test('round-trips', () {
      const s = CameraStateSnapshot(
        seq: 7,
        recording: true,
        elapsedMs: 1234,
        remoteControlAllowed: true,
        clipName: 'A001_C003',
        captureWidth: 3840,
        captureHeight: 2160,
        captureFps: 30,
        measuredFps: 29.97,
        facing: 'back',
        audioEnabled: true,
        storageFreeBytes: 12000000000,
        batteryLevel: 80,
        lastSavedClip: 'A001_C002',
        lastSaveOk: true,
      );
      final d = CameraStateSnapshot.fromJson(s.toJson());
      expect(d.seq, 7);
      expect(d.recording, isTrue);
      expect(d.elapsedMs, 1234);
      expect(d.remoteControlAllowed, isTrue);
      expect(d.clipName, 'A001_C003');
      expect(d.captureWidth, 3840);
      expect(d.captureHeight, 2160);
      expect(d.captureFps, 30);
      expect(d.measuredFps, closeTo(29.97, 1e-9));
      expect(d.facing, 'back');
      expect(d.audioEnabled, isTrue);
      expect(d.storageFreeBytes, 12000000000);
      expect(d.batteryLevel, 80);
      expect(d.lastSavedClip, 'A001_C002');
      expect(d.lastSaveOk, isTrue);
      expect(d.cameraReady, isTrue);
    });

    test('tolerates missing/foreign fields', () {
      final d = CameraStateSnapshot.fromJson({'rec': 'yes', 'w': 'big'});
      expect(d.recording, isFalse);
      expect(d.captureWidth, isNull);
      expect(d.remoteControlAllowed, isFalse);
    });
  });
}
