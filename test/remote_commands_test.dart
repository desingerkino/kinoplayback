import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/protocol/messages.dart';
import 'package:kinoplayback/session/remote_commands.dart';

/// Wires a PLAYBACK tracker to a CAMERA handler through an in-memory "link"
/// that can drop messages, to exercise retries, de-duplication and timeouts.
class _Link {
  _Link({required this.allowed, required this.exec});

  bool allowed;
  Future<Map<String, dynamic>?> Function(String type) exec;
  bool dropToCamera = false;
  bool dropToPlayback = false;
  bool closed = false;
  int executed = 0;
  final List<KpMessage> toCamera = [];
  late final RemoteCommandHandler handler = RemoteCommandHandler(
    isRemoteAllowed: (_) => allowed,
    execute: (m) {
      executed++;
      return exec(m.type);
    },
  );
  late final CommandTracker tracker = CommandTracker(send: _send);

  void _send(KpMessage m) {
    if (closed) throw StateError('closed');
    toCamera.add(m);
    if (dropToCamera) return;
    // Round-trip through JSON like the real channel.
    final wire = KpMessage.decode(m.encode());
    scheduleMicrotask(() => handler.handle(wire, (reply) {
          if (dropToPlayback) return;
          tracker.onStatus(KpMessage.decode(reply.encode()));
        }));
  }
}

void main() {
  test('happy path: sent → received → accepted → done, executes once', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      final stages = <CmdStage>[];
      link.tracker.addListener(() => stages.add(link.tracker.last!.stage));
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.done);
      expect(link.executed, 1);
      expect(stages, containsAllInOrder([CmdStage.sent, CmdStage.received, CmdStage.accepted, CmdStage.done]));
    });
  });

  test('remote control disabled → rejected, nothing executed', () {
    fakeAsync((fa) {
      final link = _Link(allowed: false, exec: (_) async => null);
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.rejected);
      expect(cmd.error, CmdError.remoteDisabled);
      expect(link.executed, 0);
    });
  });

  test('executor failure is reported as failed with code', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => throw CommandFailure(CmdError.noStorage));
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.failed);
      expect(cmd.error, CmdError.noStorage);
    });
  });

  test('double press while in flight does not send a second command', () {
    fakeAsync((fa) {
      final done = Completer<Map<String, dynamic>?>();
      final link = _Link(allowed: true, exec: (_) => done.future);
      final a = link.tracker.issue(MsgType.recStart);
      final b = link.tracker.issue(MsgType.recStart);
      expect(identical(a, b), isTrue);
      fa.flushMicrotasks();
      expect(a.stage, CmdStage.accepted);
      done.complete(null);
      fa.flushMicrotasks();
      expect(a.stage, CmdStage.done);
      expect(link.executed, 1);
      expect(link.toCamera.length, 1);
    });
  });

  test('different command while one is in flight is refused locally', () {
    fakeAsync((fa) {
      final done = Completer<Map<String, dynamic>?>();
      final link = _Link(allowed: true, exec: (_) => done.future);
      link.tracker.issue(MsgType.recStart);
      final stop = link.tracker.issue(MsgType.recStop);
      expect(stop.stage, CmdStage.rejected);
      expect(stop.error, CmdError.busy);
      done.complete(null);
      fa.flushMicrotasks();
    });
  });

  test('lost reply → retry with same id → CAMERA replays, executes once', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      link.dropToPlayback = true;
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.sent);
      expect(link.executed, 1);
      link.dropToPlayback = false;
      fa.elapse(const Duration(milliseconds: 2100)); // ack timeout → retry
      fa.flushMicrotasks();
      expect(link.toCamera.length, 2);
      expect(link.toCamera.map((m) => m.id).toSet().length, 1, reason: 'retry reuses id');
      expect(cmd.stage, CmdStage.done);
      expect(link.executed, 1, reason: 'duplicate must not run twice');
    });
  });

  test('no answer at all → retries then timedOut', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      link.dropToCamera = true;
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.elapse(const Duration(seconds: 7));
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.timedOut);
      expect(link.toCamera.length, 3); // 1 + 2 retries
    });
  });

  test('accepted but never finished → final timeout', () {
    fakeAsync((fa) {
      final never = Completer<Map<String, dynamic>?>();
      final link = _Link(allowed: true, exec: (_) => never.future);
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.accepted);
      fa.elapse(const Duration(seconds: 11));
      expect(cmd.stage, CmdStage.timedOut);
      expect(link.toCamera.length, 1, reason: 'no retry once received');
    });
  });

  test('channel closed → failed immediately', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      link.closed = true;
      final cmd = link.tracker.issue(MsgType.recStart);
      expect(cmd.stage, CmdStage.failed);
      expect(cmd.error, 'channel_closed');
    });
  });

  test('channelLost fails in-flight commands', () {
    fakeAsync((fa) {
      final never = Completer<Map<String, dynamic>?>();
      final link = _Link(allowed: true, exec: (_) => never.future);
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      link.tracker.channelLost();
      expect(cmd.stage, CmdStage.failed);
      expect(cmd.error, 'connection_lost');
    });
  });

  test('late/backwards status is ignored', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      final cmd = link.tracker.issue(MsgType.recStart);
      fa.flushMicrotasks();
      expect(cmd.stage, CmdStage.done);
      link.tracker.onStatus(cmdStatusMessage(cmd.id, MsgType.recStart, CmdStage.received));
      expect(cmd.stage, CmdStage.done);
    });
  });

  test('handler rejects unknown command types', () async {
    final h = RemoteCommandHandler(isRemoteAllowed: (_) => true, execute: (_) async => null);
    final replies = <KpMessage>[];
    await h.handle(KpMessage(type: 'format.disk'), replies.add);
    expect(replies.last.payload['stage'], 'rejected');
    expect(replies.last.payload['err'], CmdError.unknownCommand);
  });

  test('camera-control commands use their own permission', () async {
    final h = RemoteCommandHandler(
      isRemoteAllowed: (t) => MsgType.recCommands.contains(t),
      execute: (_) async => null,
    );
    final replies = <KpMessage>[];
    await h.handle(KpMessage(type: MsgType.camFocus, payload: {'x': 0.5, 'y': 0.5}), replies.add);
    expect(replies.last.payload['stage'], 'rejected');
    expect(replies.last.payload['err'], CmdError.remoteCameraDisabled);
    await h.handle(KpMessage(type: MsgType.recStart), replies.add);
    expect(replies.last.payload['stage'], 'done');
  });

  test('payload travels with the command', () {
    fakeAsync((fa) {
      final link = _Link(allowed: true, exec: (_) async => null);
      link.tracker.issue(MsgType.camFocus, payload: {'x': 0.25, 'y': 0.75, 'target': 'both'});
      expect(link.toCamera.single.payload['x'], 0.25);
      fa.flushMicrotasks();
    });
  });
}
