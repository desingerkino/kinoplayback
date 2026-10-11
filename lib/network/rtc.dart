import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/event_log.dart';
import '../protocol/messages.dart';
import 'stream_stats.dart';

/// LAN-only configuration: no STUN/TURN. Host candidates are enough when
/// both devices are on the same Wi-Fi; nothing leaves the local network.
const Map<String, dynamic> kLanRtcConfig = {
  'iceServers': <Map<String, dynamic>>[],
  'sdpSemantics': 'unified-plan',
  'bundlePolicy': 'max-bundle',
  'rtcpMuxPolicy': 'require',
};

const String kControlChannelLabel = 'kp-control';

Future<RTCPeerConnection> createLanPeerConnection() => createPeerConnection(kLanRtcConfig);

List<RawStat> toRawStats(List<StatsReport> reports) =>
    reports.map((r) => RawStat(r.id, r.type, r.timestamp, r.values)).toList();

Map<String, dynamic> candidateToPayload(RTCIceCandidate c) => {
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    };

RTCIceCandidate? candidateFromPayload(Map<String, dynamic> p) {
  final c = p['candidate'];
  if (c is! String || c.isEmpty) return null;
  final idx = p['sdpMLineIndex'];
  return RTCIceCandidate(c, p['sdpMid'] as String?, idx is num ? idx.toInt() : null);
}

/// Holds remote ICE candidates until the remote description is set.
class IceBuffer {
  IceBuffer(this.pc);
  final RTCPeerConnection pc;
  final List<RTCIceCandidate> _pending = [];
  bool _ready = false;

  Future<void> add(RTCIceCandidate c) async {
    if (!_ready) {
      _pending.add(c);
      return;
    }
    await _safeAdd(c);
  }

  Future<void> markReady() async {
    _ready = true;
    final list = List<RTCIceCandidate>.from(_pending);
    _pending.clear();
    for (final c in list) {
      await _safeAdd(c);
    }
  }

  Future<void> _safeAdd(RTCIceCandidate c) async {
    try {
      await pc.addCandidate(c);
    } catch (e) {
      logW('rtc', 'addCandidate failed: $e');
    }
  }
}

/// Thin wrapper around the control data channel with the shared envelope.
class ControlChannel {
  ControlChannel(this.dc, {required this.onMessage, this.onOpen, this.onClosed}) {
    dc.onMessage = (RTCDataChannelMessage m) {
      if (m.isBinary) return;
      try {
        onMessage(KpMessage.decode(m.text));
      } on FormatException catch (e) {
        logW('ctl', 'drop malformed control message: ${e.message}');
      }
    };
    dc.onDataChannelState = (RTCDataChannelState s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _open = true;
        onOpen?.call();
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        final was = _open;
        _open = false;
        if (was) onClosed?.call();
      }
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      _open = true;
      scheduleMicrotask(() => onOpen?.call());
    }
  }

  final RTCDataChannel dc;
  final void Function(KpMessage m) onMessage;
  final void Function()? onOpen;
  final void Function()? onClosed;
  bool _open = false;

  bool get isOpen => _open;

  /// Synchronous by design: throws if the channel is not open so callers
  /// (e.g. the REC tracker) fail visibly instead of believing it was sent.
  void send(KpMessage m) {
    if (!_open) throw StateError('control channel not open');
    dc.send(RTCDataChannelMessage(m.encode())).catchError((Object e) {
      logW('ctl', 'send failed: $e');
    });
  }

  Future<void> close() async {
    _open = false;
    try {
      await dc.close();
    } catch (_) {}
  }
}
