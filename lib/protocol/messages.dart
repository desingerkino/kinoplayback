import 'dart:convert';
import 'dart:math';

/// KINO PLAYBACK wire protocol, v1.
///
/// One JSON envelope for everything that travels between devices — both on
/// the signaling WebSocket (hello/offer/answer/ice) and on the WebRTC data
/// channel (REC commands, state). The same Dart code runs on iOS and Android,
/// so both platforms speak exactly the same format.
///
/// {
///   "v": 1,                 protocol version
///   "t": "rec.start",       message type
///   "id": "c-…",            unique message id (commands: idempotency key)
///   "ts": 1728640000000,    sender wall clock, ms (informational only)
///   "sid": "s-…",           session id (null before welcome)
///   "p": { … }              payload
/// }
const int kProtocolVersion = 1;
const String kBonjourType = '_kinoplayback._tcp';
const int kDefaultPort = 47800;
const String kWsPath = '/kp';

abstract final class MsgType {
  // Signaling (WebSocket)
  static const hello = 'hello';
  static const welcome = 'welcome';
  static const reject = 'reject';
  static const pending = 'pending'; // waiting for user approval on CAMERA
  static const offer = 'offer';
  static const answer = 'answer';
  static const ice = 'ice';
  static const bye = 'bye';

  // Control (data channel)
  static const recStart = 'rec.start';
  static const recStop = 'rec.stop';
  static const cmdStatus = 'cmd.status';
  static const state = 'state';
  static const stateRequest = 'state.request';
  static const takesRequest = 'takes.request';
  static const takes = 'takes';
  static const ping = 'ping';
  static const pong = 'pong';

  static const commands = {recStart, recStop};
}

class KpMessage {
  KpMessage({
    required this.type,
    String? id,
    int? ts,
    this.sessionId,
    Map<String, dynamic>? payload,
    this.version = kProtocolVersion,
  })  : id = id ?? newId('m'),
        ts = ts ?? DateTime.now().millisecondsSinceEpoch,
        payload = payload ?? const {};

  final int version;
  final String type;
  final String id;
  final int ts;
  final String? sessionId;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'v': version,
        't': type,
        'id': id,
        'ts': ts,
        if (sessionId != null) 'sid': sessionId,
        'p': payload,
      };

  String encode() => jsonEncode(toJson());

  /// Strict decoding: throws [FormatException] for anything malformed so the
  /// caller can log and drop it instead of acting on garbage.
  static KpMessage decode(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('not json');
    }
    if (j is! Map<String, dynamic>) throw const FormatException('not an object');
    final v = j['v'];
    final t = j['t'];
    final id = j['id'];
    final ts = j['ts'];
    final p = j['p'] ?? const <String, dynamic>{};
    final sid = j['sid'];
    if (v is! int) throw const FormatException('missing v');
    if (v > kProtocolVersion) throw FormatException('unsupported protocol v$v');
    if (t is! String || t.isEmpty) throw const FormatException('missing t');
    if (id is! String || id.isEmpty) throw const FormatException('missing id');
    if (ts is! int) throw const FormatException('missing ts');
    if (p is! Map<String, dynamic>) throw const FormatException('payload must be an object');
    if (sid != null && sid is! String) throw const FormatException('bad sid');
    return KpMessage(type: t, id: id, ts: ts, sessionId: sid as String?, payload: p, version: v);
  }

  @override
  String toString() => 'KpMessage($type, $id)';
}

final Random _rnd = Random.secure();

String newId(String prefix) {
  final b = List<int>.generate(8, (_) => _rnd.nextInt(256));
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-$hex';
}

/// Stages a remote command goes through. Only [done] for rec.start means the
/// CAMERA has *actually* started recording (it reports that after the
/// recorder confirmed), and the REC indicator on PLAYBACK is driven by the
/// separate `state` message, never by the button press.
enum CmdStage {
  sending, // local: queued / being written to the channel
  sent, // local: written to the channel
  received, // remote: message arrived and parsed
  accepted, // remote: permission + preconditions OK, executing
  rejected, // remote: refused (no permission, busy, …)
  done, // remote: executed, result confirmed
  failed, // remote: tried and failed
  timedOut, // local: no final answer in time
}

extension CmdStageX on CmdStage {
  bool get isFinal =>
      this == CmdStage.rejected ||
      this == CmdStage.done ||
      this == CmdStage.failed ||
      this == CmdStage.timedOut;

  String get wire => switch (this) {
        CmdStage.received => 'received',
        CmdStage.accepted => 'accepted',
        CmdStage.rejected => 'rejected',
        CmdStage.done => 'done',
        CmdStage.failed => 'failed',
        _ => name,
      };

  static CmdStage? fromWire(String? s) => switch (s) {
        'received' => CmdStage.received,
        'accepted' => CmdStage.accepted,
        'rejected' => CmdStage.rejected,
        'done' => CmdStage.done,
        'failed' => CmdStage.failed,
        _ => null,
      };
}

/// Error codes carried in cmd.status for rejected/failed commands.
abstract final class CmdError {
  static const remoteDisabled = 'remote_disabled';
  static const cameraUnavailable = 'camera_unavailable';
  static const noStorage = 'no_storage';
  static const recorderError = 'recorder_error';
  static const busy = 'busy';
  static const unknownCommand = 'unknown_command';

  static String describe(String? code) => switch (code) {
        remoteDisabled => 'Удалённое управление запрещено на камере',
        cameraUnavailable => 'Камера недоступна',
        noStorage => 'Недостаточно места на камере',
        recorderError => 'Ошибка записи на камере',
        busy => 'Камера занята предыдущей командой',
        unknownCommand => 'Неизвестная команда',
        null => 'Неизвестная ошибка',
        _ => code,
      };
}
