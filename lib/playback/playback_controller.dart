import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gal/gal.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/device_identity.dart';
import '../core/event_log.dart';
import '../network/net_utils.dart';
import '../network/rtc.dart';
import '../network/signaling.dart';
import '../network/stream_stats.dart';
import '../protocol/camera_state.dart';
import '../protocol/messages.dart';
import '../recording/take_recorder.dart';
import '../recording/takes.dart';
import '../session/remote_commands.dart';
import '../settings/app_settings.dart';

enum LinkPhase { connecting, awaitingApproval, negotiating, live, reconnecting, rejected, closed }

extension LinkPhaseX on LinkPhase {
  String get label => switch (this) {
        LinkPhase.connecting => 'Подключение…',
        LinkPhase.awaitingApproval => 'Ожидает подтверждения на камере',
        LinkPhase.negotiating => 'Установка соединения…',
        LinkPhase.live => 'В эфире',
        LinkPhase.reconnecting => 'Связь потеряна — переподключение…',
        LinkPhase.rejected => 'Подключение отклонено',
        LinkPhase.closed => 'Отключено',
      };
}

/// PLAYBACK mode: receives the stream from one CAMERA, shows confirmed
/// state, sends REC commands, records the received stream locally.
class PlaybackController extends ChangeNotifier with WidgetsBindingObserver {
  PlaybackController({
    required this.settings,
    required this.repo,
    required this.identity,
    required this.target,
  });

  final AppSettings settings;
  final TakesRepository repo;
  final DeviceIdentity identity;
  final ConnectTarget target;

  final RTCVideoRenderer renderer = RTCVideoRenderer();
  LinkPhase phase = LinkPhase.connecting;
  String? message;

  String remoteName = '';
  String remotePlatform = '';
  String remoteModel = '';
  String? remoteApp;
  String? sessionId;

  CameraStateSnapshot? camState;
  DateTime? _camRecAnchor;
  DateTime? lastStateAt;
  StreamStats? stats;
  StatsCounters? _counters;
  List<Take>? remoteTakes;
  DateTime? liveSince;

  MediaStream? _remoteStream;
  MediaStreamTrack? remoteVideo;
  bool hasRemoteAudio = false;

  late final CommandTracker tracker = CommandTracker(
    send: (m) {
      final c = _ctl;
      if (c == null) throw StateError('нет канала управления');
      c.send(m);
    },
    onEvent: (t) => logI('rec-remote', t),
  )..addListener(_notify);

  late final TakeRecorder recorder = TakeRecorder(repo: repo, source: TakeSource.monitor)..addListener(_notify);

  SignalingLink? _link;
  StreamSubscription<KpMessage>? _linkSub;
  RTCPeerConnection? _pc;
  ControlChannel? _ctl;
  IceBuffer? _ice;
  bool _userClosed = false;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _retry;
  Timer? _statsTimer;
  Timer? _watchdog;

  bool get isLive => phase == LinkPhase.live;
  bool get controlOpen => _ctl?.isOpen ?? false;

  /// Camera REC is only shown as active from a fresh confirmed snapshot.
  bool? get cameraRecording {
    final s = camState;
    if (s == null || !isLive || stateStale) return null; // unknown
    return s.recording;
  }

  bool get stateStale => lastStateAt == null || DateTime.now().difference(lastStateAt!) > const Duration(seconds: 6);

  DateTime? get cameraRecAnchor => (cameraRecording ?? false) ? _camRecAnchor : null;

  bool get _rotated => renderer.value.rotation == 90 || renderer.value.rotation == 270;

  /// Decoded picture size as displayed (rotation applied).
  int? get videoWidth {
    if (renderer.videoWidth <= 0) return null;
    return _rotated ? renderer.videoHeight : renderer.videoWidth;
  }

  int? get videoHeight {
    if (renderer.videoHeight <= 0) return null;
    return _rotated ? renderer.videoWidth : renderer.videoHeight;
  }

  double get videoAspect {
    final w = videoWidth, h = videoHeight;
    if (w == null || h == null || h == 0) return 16 / 9;
    return w / h;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- start --
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await renderer.initialize();
    renderer.onResize = _notify;
    renderer.onFirstFrameRendered = () {
      logI('play', 'первый кадр: ${renderer.videoWidth}×${renderer.videoHeight}');
      _notify();
    };
    if (settings.keepScreenOn) unawaited(WakelockPlus.enable());
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _userClosed) return;
    await _teardownPeer();
    phase = _attempt == 0 ? LinkPhase.connecting : LinkPhase.reconnecting;
    _notify();
    SignalingLink link;
    try {
      link = await SignalingLink.connect(target.host, target.port);
    } catch (e) {
      _scheduleRetry('Камера ${target.host}:${target.port} недоступна');
      return;
    }
    if (_disposed || _userClosed) {
      await link.close();
      return;
    }
    _link = link;
    _linkSub = link.messages.listen(_onSignal);
    link.done.then((_) {
      if (!_userClosed && identical(_link, link) && phase != LinkPhase.rejected) {
        _lost('Сигнальное соединение закрыто');
      }
    });
    try {
      link.send(KpMessage(type: MsgType.hello, payload: {
        'cid': settings.clientId,
        'name': settings.deviceName,
        'pf': identity.platform,
        'model': identity.model,
        'app': identity.appVersion,
        'role': 'playback',
      }));
    } catch (e) {
      _lost('Ошибка отправки: $e');
    }
  }

  Future<void> _onSignal(KpMessage m) async {
    try {
      switch (m.type) {
        case MsgType.pending:
          phase = LinkPhase.awaitingApproval;
          _notify();
        case MsgType.welcome:
          sessionId = m.payload['sid'] as String?;
          remoteName = (m.payload['name'] as String?) ?? target.name ?? target.host;
          remotePlatform = (m.payload['pf'] as String?) ?? '';
          remoteModel = (m.payload['model'] as String?) ?? '';
          remoteApp = m.payload['app'] as String?;
          phase = LinkPhase.negotiating;
          logI('play', 'принят камерой $remoteName ($remotePlatform $remoteModel), сессия $sessionId');
          settings.rememberRecent(RecentDevice(
            name: remoteName,
            host: target.host,
            port: target.port,
            lastUsed: DateTime.now(),
            platform: remotePlatform,
          ));
          _notify();
        case MsgType.reject:
          message = (m.payload['reason'] as String?) ?? 'Отклонено';
          phase = LinkPhase.rejected;
          _userClosed = true;
          logW('play', 'отклонено: $message');
          await _teardownPeer();
          _notify();
        case MsgType.offer:
          await _answer(m.payload);
        case MsgType.ice:
          final c = candidateFromPayload(m.payload);
          if (c != null) await _ice?.add(c);
        case MsgType.bye:
          _lost('Камера завершила сессию');
        default:
          break;
      }
    } catch (e) {
      logE('play', 'signal ${m.type}: $e');
    }
  }

  Future<void> _answer(Map<String, dynamic> p) async {
    final sdp = p['sdp'];
    if (sdp is! String) return;
    final pc = await createLanPeerConnection();
    _pc = pc;
    _ice = IceBuffer(pc);
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      try {
        _link?.send(KpMessage(type: MsgType.ice, payload: candidateToPayload(c)));
      } catch (_) {}
    };
    pc.onTrack = (RTCTrackEvent e) {
      if (e.track.kind == 'video') {
        remoteVideo = e.track;
        if (e.streams.isNotEmpty) {
          _remoteStream = e.streams.first;
          renderer.srcObject = _remoteStream;
        }
      } else if (e.track.kind == 'audio') {
        hasRemoteAudio = true;
      }
      _notify();
    };
    pc.onDataChannel = (RTCDataChannel dc) {
      if (dc.label != kControlChannelLabel) return;
      _ctl = ControlChannel(
        dc,
        onMessage: _onControl,
        onOpen: () {
          logI('ctl', 'канал управления открыт');
          _requestState();
          _notify();
        },
        onClosed: () {
          tracker.channelLost();
          _notify();
        },
      );
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      logI('rtc', 'монитор: $s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = LinkPhase.live;
        liveSince = DateTime.now();
        _attempt = 0;
        message = null;
        _notify();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _lost('WebRTC: соединение потеряно');
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        message = 'Связь нестабильна…';
        _notify();
      }
    };
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await _ice!.markReady();
    final answer = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(answer);
    _link?.send(KpMessage(type: MsgType.answer, payload: {'sdp': answer.sdp, 'type': answer.type}));
  }

  void _onControl(KpMessage m) {
    switch (m.type) {
      case MsgType.state:
        if (m.sessionId != null && sessionId != null && m.sessionId != sessionId) return;
        final s = CameraStateSnapshot.fromJson(m.payload);
        final prev = camState;
        if (prev != null && s.seq <= prev.seq && lastStateAt != null && !stateStale) return;
        final wasRec = prev?.recording ?? false;
        camState = s;
        lastStateAt = DateTime.now();
        if (s.recording) {
          final anchor = DateTime.now().subtract(Duration(milliseconds: s.elapsedMs));
          // Keep the anchor stable unless it drifts by more than 1 s.
          if (_camRecAnchor == null || !wasRec || (_camRecAnchor!.difference(anchor).inMilliseconds).abs() > 1000) {
            _camRecAnchor = anchor;
          }
        } else {
          _camRecAnchor = null;
        }
        if (wasRec != s.recording) {
          logI('play', 'камера: запись ${s.recording ? 'ИДЁТ (${s.clipName})' : 'остановлена'}');
        }
        _notify();
      case MsgType.cmdStatus:
        tracker.onStatus(m);
      case MsgType.takes:
        final list = m.payload['takes'];
        if (list is List) {
          remoteTakes = list.whereType<Map<String, dynamic>>().map(Take.fromWire).whereType<Take>().toList();
          _notify();
        }
      case MsgType.pong:
        break;
      default:
        break;
    }
  }

  void _requestState() {
    try {
      _ctl?.send(KpMessage(type: MsgType.stateRequest, sessionId: sessionId));
    } catch (_) {}
  }

  void requestRemoteTakes() {
    try {
      _ctl?.send(KpMessage(type: MsgType.takesRequest, sessionId: sessionId));
    } catch (e) {
      message = 'Нет связи с камерой';
      _notify();
    }
  }

  // --------------------------------------------------------- reconnecting --
  void _lost(String reason) {
    if (_userClosed || _disposed) return;
    if (phase == LinkPhase.reconnecting && _retry != null) return;
    logW('play', reason);
    message = reason;
    tracker.channelLost();
    if (recorder.isRecording) {
      logW('play', 'поток потерян во время записи монитора — файл закрывается');
      unawaited(recorder.stop(interrupted: true, saveToGallery: settings.autoSaveToGallery));
    }
    _scheduleRetry(reason);
  }

  void _scheduleRetry(String reason) {
    if (_userClosed || _disposed) return;
    phase = LinkPhase.reconnecting;
    message = reason;
    _attempt++;
    final delay = Duration(seconds: math.min(8, 1 << math.min(3, _attempt - 1)));
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      _connect();
    });
    _notify();
  }

  Future<void> reconnectNow() async {
    _retry?.cancel();
    _retry = null;
    _userClosed = false;
    _attempt = math.max(1, _attempt);
    await _connect();
  }

  Future<void> _teardownPeer() async {
    final ctl = _ctl;
    final pc = _pc;
    final link = _link;
    final sub = _linkSub;
    _ctl = null;
    _pc = null;
    _ice = null;
    _link = null;
    _linkSub = null;
    remoteVideo = null;
    _remoteStream = null;
    hasRemoteAudio = false;
    stats = null;
    _counters = null;
    renderer.srcObject = null;
    await sub?.cancel();
    try {
      await ctl?.close();
    } catch (_) {}
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
    await link?.close();
  }

  // ------------------------------------------------------------- commands --
  /// Toggles REC on the CAMERA. The decision start/stop is based on the last
  /// confirmed camera state, and the UI flips only when a new state arrives.
  TrackedCommand? toggleRemoteRec() {
    if (!isLive || !controlOpen) {
      message = 'Нет соединения с камерой';
      _notify();
      return null;
    }
    final rec = cameraRecording;
    if (rec == null) {
      _requestState();
      message = 'Состояние камеры неизвестно — запрошено обновление';
      _notify();
      return null;
    }
    if (camState?.remoteControlAllowed != true) {
      message = 'На камере не разрешено удалённое управление';
      _notify();
      return null;
    }
    return tracker.issue(rec ? MsgType.recStop : MsgType.recStart, sessionId: sessionId);
  }

  Future<void> toggleLocalRec() async {
    if (recorder.busy) return;
    if (recorder.isRecording) {
      await recorder.stop(saveToGallery: settings.autoSaveToGallery);
      return;
    }
    final v = remoteVideo;
    if (v == null || !isLive) {
      message = 'Нет видеопотока для записи';
      _notify();
      return;
    }
    final camClip = (cameraRecording ?? false) ? camState?.clipName : null;
    final name = camClip != null ? '${camClip}_MON' : '${settings.takeNextClipName()}_MON';
    try {
      await recorder.start(
        videoTrack: v,
        withAudio: hasRemoteAudio,
        clipName: name,
        deviceName: settings.deviceName,
        remoteDevice: remoteName,
      );
    } on CommandFailure catch (e) {
      message = CmdError.describe(e.code) + (e.detail != null ? ': ${e.detail}' : '');
      _notify();
    }
  }

  /// Saves the current received frame (as decoded on this device) to Photos.
  Future<String?> snapshot() async {
    final v = remoteVideo;
    if (v == null) return 'Нет видеопотока';
    try {
      final ByteBuffer buf = await v.captureFrame();
      final ts = DateTime.now();
      final name = 'KP_${ts.year}${_two(ts.month)}${_two(ts.day)}_${_two(ts.hour)}${_two(ts.minute)}${_two(ts.second)}';
      await Gal.putImageBytes(buf.asUint8List(), name: name);
      logI('play', 'кадр сохранён: $name');
      return null;
    } catch (e) {
      logW('play', 'кадр: $e');
      return 'Не удалось сохранить кадр: $e';
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // ---------------------------------------------------------------- stats --
  Future<void> _pollStats() async {
    final pc = _pc;
    if (pc == null || phase != LinkPhase.live) return;
    try {
      final (s, c) = parseInboundStats(toRawStats(await pc.getStats()), _counters);
      stats = s;
      _counters = c;
      _notify();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_userClosed && phase == LinkPhase.reconnecting) {
      unawaited(reconnectNow());
    }
  }

  // ------------------------------------------------------------ teardown --
  Future<void> disconnect() async {
    _userClosed = true;
    _retry?.cancel();
    try {
      _link?.send(KpMessage(type: MsgType.bye));
    } catch (_) {}
    if (recorder.isRecording) {
      await recorder.stop(saveToGallery: settings.autoSaveToGallery);
    }
    await _teardownPeer();
    phase = LinkPhase.closed;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    _notify();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _retry?.cancel();
    _statsTimer?.cancel();
    _watchdog?.cancel();
    tracker.dispose();
    recorder.dispose();
    renderer.dispose();
    super.dispose();
  }
}
