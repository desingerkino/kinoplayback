import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../protocol/messages.dart';

KpMessage cmdStatusMessage(
  String cmdId,
  String cmdType,
  CmdStage stage, {
  String? error,
  String? detail,
  Map<String, dynamic>? extra,
  String? sessionId,
}) {
  return KpMessage(
    type: MsgType.cmdStatus,
    sessionId: sessionId,
    payload: {
      'cmd': cmdId,
      'ct': cmdType,
      'stage': stage.wire,
      if (error != null) 'err': error,
      if (detail != null) 'detail': detail,
      ...?extra,
    },
  );
}

// ---------------------------------------------------------------------------
// PLAYBACK side: issue commands and follow them to a confirmed final stage.
// ---------------------------------------------------------------------------

class TrackedCommand {
  TrackedCommand(this.id, this.type, this.createdAt);

  final String id;
  final String type;
  final DateTime createdAt;
  CmdStage stage = CmdStage.sending;
  String? error;
  String? detail;
  int attempts = 0;

  bool get isFinal => stage.isFinal;
}

class CommandTracker extends ChangeNotifier {
  CommandTracker({
    required this.send,
    this.ackTimeout = const Duration(seconds: 2),
    this.finalTimeout = const Duration(seconds: 10),
    this.maxRetries = 2,
    this.onEvent,
  });

  /// Writes a message to the control channel. Must throw if the channel is
  /// not open, so the command fails visibly instead of silently.
  final void Function(KpMessage msg) send;
  final Duration ackTimeout;
  final Duration finalTimeout;
  final int maxRetries;
  final void Function(String text)? onEvent;

  final Map<String, TrackedCommand> _cmds = {};
  final Map<String, Timer> _ackTimers = {};
  final Map<String, Timer> _finalTimers = {};
  final Map<String, KpMessage> _outgoing = {};
  bool _disposed = false;

  /// The command currently in flight (not final), if any.
  TrackedCommand? get active {
    for (final c in _cmds.values) {
      if (!c.isFinal) return c;
    }
    return null;
  }

  /// Most recent command (final or not) — for UI feedback.
  TrackedCommand? get last => _cmds.isEmpty ? null : _cmds.values.last;

  TrackedCommand? byId(String id) => _cmds[id];

  /// Issues [type]. Pressing the same button twice while a command is in
  /// flight returns the in-flight command instead of sending a duplicate
  /// (protection against double REC). A different command while one is in
  /// flight is refused locally.
  TrackedCommand issue(String type, {String? sessionId, Map<String, dynamic>? payload}) {
    final inFlight = active;
    if (inFlight != null) {
      if (inFlight.type == type) return inFlight;
      final refused = TrackedCommand(newId('c'), type, DateTime.now())
        ..stage = CmdStage.rejected
        ..error = CmdError.busy;
      _put(refused);
      notifyListeners();
      return refused;
    }
    final cmd = TrackedCommand(newId('c'), type, DateTime.now());
    _put(cmd);
    final msg = KpMessage(type: type, id: cmd.id, sessionId: sessionId, payload: payload);
    _outgoing[cmd.id] = msg;
    _finalTimers[cmd.id] = Timer(finalTimeout, () => _timeout(cmd.id));
    _transmit(cmd);
    return cmd;
  }

  void _put(TrackedCommand c) {
    _cmds[c.id] = c;
    // keep history short
    while (_cmds.length > 20) {
      final oldest = _cmds.keys.first;
      if (!_cmds[oldest]!.isFinal) break;
      _cmds.remove(oldest);
    }
  }

  void _transmit(TrackedCommand cmd) {
    final msg = _outgoing[cmd.id];
    if (msg == null) return;
    cmd.attempts++;
    try {
      send(msg);
      if (cmd.stage == CmdStage.sending) cmd.stage = CmdStage.sent;
      onEvent?.call('→ ${cmd.type} ${cmd.id} (попытка ${cmd.attempts})');
    } catch (e) {
      _finish(cmd, CmdStage.failed, error: 'channel_closed', detail: '$e');
      return;
    }
    _ackTimers[cmd.id]?.cancel();
    _ackTimers[cmd.id] = Timer(ackTimeout, () => _ackMissing(cmd.id));
    notifyListeners();
  }

  void _ackMissing(String id) {
    final cmd = _cmds[id];
    if (cmd == null || cmd.isFinal) return;
    if (cmd.stage != CmdStage.sent && cmd.stage != CmdStage.sending) return;
    if (cmd.attempts <= maxRetries) {
      // Same id → CAMERA de-duplicates, so a retry can never start twice.
      _transmit(cmd);
    } else {
      _finish(cmd, CmdStage.timedOut, error: 'no_ack');
    }
  }

  void _timeout(String id) {
    final cmd = _cmds[id];
    if (cmd == null || cmd.isFinal) return;
    _finish(cmd, CmdStage.timedOut, error: 'no_result');
  }

  /// Feed every incoming `cmd.status` here.
  void onStatus(KpMessage m) {
    final id = m.payload['cmd'];
    if (id is! String) return;
    final cmd = _cmds[id];
    if (cmd == null || cmd.isFinal) return; // unknown or late duplicate
    final stage = CmdStageX.fromWire(m.payload['stage'] as String?);
    if (stage == null) return;
    if (_rank(stage) <= _rank(cmd.stage)) return; // never go backwards
    if (stage.isFinal) {
      _finish(cmd, stage, error: m.payload['err'] as String?, detail: m.payload['detail'] as String?);
    } else {
      cmd.stage = stage;
      _ackTimers.remove(id)?.cancel();
      onEvent?.call('← ${cmd.type} ${cmd.id}: ${stage.wire}');
      notifyListeners();
    }
  }

  /// Connection lost: anything in flight has an unknown outcome. Mark it
  /// failed; the real state is restored from the CAMERA's snapshot after
  /// reconnect.
  void channelLost() {
    for (final c in _cmds.values.toList()) {
      if (!c.isFinal) _finish(c, CmdStage.failed, error: 'connection_lost');
    }
  }

  int _rank(CmdStage s) => switch (s) {
        CmdStage.sending => 0,
        CmdStage.sent => 1,
        CmdStage.received => 2,
        CmdStage.accepted => 3,
        _ => 4,
      };

  void _finish(TrackedCommand cmd, CmdStage stage, {String? error, String? detail}) {
    cmd.stage = stage;
    cmd.error = error;
    cmd.detail = detail;
    _ackTimers.remove(cmd.id)?.cancel();
    _finalTimers.remove(cmd.id)?.cancel();
    _outgoing.remove(cmd.id);
    onEvent?.call('■ ${cmd.type} ${cmd.id}: ${stage.wire}${error != null ? ' ($error)' : ''}');
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _ackTimers.values) {
      t.cancel();
    }
    for (final t in _finalTimers.values) {
      t.cancel();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// CAMERA side: execute each command at most once and always answer.
// ---------------------------------------------------------------------------

class CommandFailure implements Exception {
  CommandFailure(this.code, [this.detail]);
  final String code;
  final String? detail;
  @override
  String toString() => 'CommandFailure($code${detail != null ? ': $detail' : ''})';
}

class RemoteCommandHandler {
  RemoteCommandHandler({
    required this.isRemoteAllowed,
    required this.execute,
    this.capacity = 128,
  });

  /// Permission check per command type (REC and camera control have
  /// separate switches on the CAMERA).
  final bool Function(String type) isRemoteAllowed;

  /// Runs the command. Completes when the effect is *confirmed* (e.g. the
  /// recorder really started). Throw [CommandFailure] for known errors.
  final Future<Map<String, dynamic>?> Function(KpMessage msg) execute;
  final int capacity;

  final LinkedHashMap<String, KpMessage> _finals = LinkedHashMap();
  final Set<String> _inFlight = {};
  bool _busy = false;

  bool get busy => _busy;

  Future<void> handle(KpMessage msg, void Function(KpMessage reply) reply, {String? sessionId}) async {
    final prior = _finals[msg.id];
    if (prior != null) {
      reply(prior); // duplicate of a finished command → replay the outcome
      return;
    }
    if (_inFlight.contains(msg.id)) {
      reply(cmdStatusMessage(msg.id, msg.type, CmdStage.received, sessionId: sessionId));
      return;
    }
    _inFlight.add(msg.id);
    reply(cmdStatusMessage(msg.id, msg.type, CmdStage.received, sessionId: sessionId));

    KpMessage fin;
    if (!MsgType.commands.contains(msg.type)) {
      fin = cmdStatusMessage(msg.id, msg.type, CmdStage.rejected,
          error: CmdError.unknownCommand, sessionId: sessionId);
    } else if (!isRemoteAllowed(msg.type)) {
      fin = cmdStatusMessage(msg.id, msg.type, CmdStage.rejected,
          error: MsgType.camCommands.contains(msg.type) ? CmdError.remoteCameraDisabled : CmdError.remoteDisabled,
          sessionId: sessionId);
    } else if (_busy) {
      fin = cmdStatusMessage(msg.id, msg.type, CmdStage.rejected, error: CmdError.busy, sessionId: sessionId);
    } else {
      reply(cmdStatusMessage(msg.id, msg.type, CmdStage.accepted, sessionId: sessionId));
      _busy = true;
      try {
        final extra = await execute(msg);
        fin = cmdStatusMessage(msg.id, msg.type, CmdStage.done, extra: extra, sessionId: sessionId);
      } on CommandFailure catch (e) {
        fin = cmdStatusMessage(msg.id, msg.type, CmdStage.failed,
            error: e.code, detail: e.detail, sessionId: sessionId);
      } catch (e) {
        fin = cmdStatusMessage(msg.id, msg.type, CmdStage.failed,
            error: CmdError.recorderError, detail: '$e', sessionId: sessionId);
      } finally {
        _busy = false;
      }
    }
    _inFlight.remove(msg.id);
    _finals[msg.id] = fin;
    while (_finals.length > capacity) {
      _finals.remove(_finals.keys.first);
    }
    reply(fin);
  }
}
