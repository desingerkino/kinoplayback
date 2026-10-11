import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/device_identity.dart';
import '../core/event_log.dart';
import '../core/storage_info.dart';
import '../network/discovery.dart';
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

enum CameraPhase { idle, opening, ready, error }

enum PeerPhase { hello, awaitingApproval, negotiating, connected, closed }

enum ApprovalDecision { deny, once, always }

typedef ApprovalCallback = Future<ApprovalDecision> Function(String name, String platform, String address);

/// One connected (or connecting) PLAYBACK device, seen from the CAMERA.
class PeerClient {
  PeerClient(this.link);
  final SignalingLink link;
  String clientId = '';
  String name = '…';
  String platform = '';
  String model = '';
  PeerPhase phase = PeerPhase.hello;
  RTCPeerConnection? pc;
  ControlChannel? ctl;
  IceBuffer? ice;
  RTCRtpSender? videoSender;
  RTCRtpSender? audioSender;
  StreamStats? stats;
  StatsCounters? counters;
  DateTime? connectedAt;
  StreamSubscription<KpMessage>? sub;
}

/// CAMERA mode: capture, original recording, serving the stream to PLAYBACK
/// devices and executing their (permitted) REC commands.
class CameraController extends ChangeNotifier with WidgetsBindingObserver {
  CameraController({required this.settings, required this.repo, required this.identity});

  final AppSettings settings;
  final TakesRepository repo;
  final DeviceIdentity identity;

  /// Set by the UI to show the "allow connection?" dialog.
  ApprovalCallback? approve;

  final RTCVideoRenderer preview = RTCVideoRenderer();
  MediaStream? _stream;
  CameraPhase phase = CameraPhase.idle;
  String? error;
  bool permissionDenied = false;
  String? warning;

  // Real capture format chosen by the platform for our request.
  int? capWidth;
  int? capHeight;
  int? capFps;
  String? facing;
  // Frames actually delivered to the preview.
  int? frameWidth;
  int? frameHeight;

  late final TakeRecorder recorder = TakeRecorder(repo: repo, source: TakeSource.original)
    ..onTakeUpdated = (_) => _broadcastState();
  late final RemoteCommandHandler _handler =
      RemoteCommandHandler(isRemoteAllowed: () => settings.remoteControlAllowed, execute: _execute);

  final List<PeerClient> peers = [];
  final CameraAdvertiser _advertiser = CameraAdvertiser();
  SignalingServer? _server;
  String? lanIp;
  int? port;
  final String sessionId = newId('s');

  int _seq = 0;
  int? battery;
  int? freeBytes;
  StreamStats? senderStats;
  double? audioLevel;

  Timer? _heartbeat;
  Timer? _statsTimer;
  Timer? _sysTimer;
  bool _disposed = false;
  bool _recOpInFlight = false;

  bool get hasAudio => (_stream?.getAudioTracks().isNotEmpty ?? false);
  MediaStreamTrack? get videoTrack {
    final v = _stream?.getVideoTracks();
    return (v == null || v.isEmpty) ? null : v.first;
  }

  List<PeerClient> get connectedPeers => peers.where((p) => p.phase == PeerPhase.connected).toList();

  /// Landscape-normalised capture size: prefers what frames really are.
  (int?, int?) get captureSize {
    final w = frameWidth ?? capWidth;
    final h = frameHeight ?? capHeight;
    if (w == null || h == null) return (null, null);
    return (math.max(w, h), math.min(w, h));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ----------------------------------------------------------------- start --
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await preview.initialize();
    preview.onResize = () {
      frameWidth = preview.videoWidth;
      frameHeight = preview.videoHeight;
      _notify();
      _broadcastState();
    };
    recorder.addListener(_onRecorderChanged);
    settings.addListener(_onSettingsChanged);
    _lastRemoteAllowed = settings.remoteControlAllowed;
    _lastStream = settings.stream;
    await openCamera();
    await _startServer();
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) => _broadcastState());
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
    _sysTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollSystem());
    unawaited(_pollSystem());
    if (settings.keepScreenOn) unawaited(WakelockPlus.enable());
  }

  bool _lastRemoteAllowed = false;
  StreamQuality? _lastStream;

  void _onSettingsChanged() {
    if (settings.remoteControlAllowed != _lastRemoteAllowed) {
      _lastRemoteAllowed = settings.remoteControlAllowed;
      logI('cam', 'удалённое управление: ${_lastRemoteAllowed ? 'разрешено' : 'запрещено'}');
      _broadcastState();
    }
    final sq = settings.stream;
    if (_lastStream == null ||
        sq.height != _lastStream!.height ||
        sq.fps != _lastStream!.fps ||
        sq.maxKbps != _lastStream!.maxKbps) {
      _lastStream = sq;
      for (final p in connectedPeers) {
        unawaited(_applyEncoding(p));
      }
    }
  }

  void _onRecorderChanged() {
    _notify();
    _broadcastState();
  }

  // ---------------------------------------------------------------- camera --
  Future<void> openCamera() async {
    if (recorder.isRecording || recorder.busy) {
      warning = 'Нельзя менять камеру во время записи';
      _notify();
      return;
    }
    phase = CameraPhase.opening;
    error = null;
    warning = null;
    _notify();
    final preset = settings.capturePreset;
    final old = _stream;
    _stream = null;
    if (old != null) {
      for (final t in old.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await old.dispose();
      } catch (_) {}
    }
    final constraints = <String, dynamic>{
      'audio': settings.audioEnabled,
      'video': <String, dynamic>{
        'facingMode': settings.frontCamera ? 'user' : 'environment',
        'width': preset.width,
        'height': preset.height,
        'frameRate': preset.fps,
      },
    };
    try {
      final s = await navigator.mediaDevices.getUserMedia(constraints);
      _stream = s;
      preview.srcObject = s;
      permissionDenied = false;
      final vt = videoTrack;
      if (vt == null) throw StateError('нет видеодорожки');
      final st = vt.getSettings();
      int? n(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
      capWidth = n(st['width']);
      capHeight = n(st['height']);
      capFps = n(st['frameRate']);
      final fm = st['facingMode'];
      facing = fm == 'user' ? 'front' : (fm == 'environment' ? 'back' : null);
      final w = capWidth, h = capHeight;
      if (w != null && h != null) {
        final long = math.max(w, h), short = math.min(w, h);
        if (long != preset.width || short != preset.height || (capFps != null && capFps != preset.fps)) {
          warning = 'Камера выбрала $long×$short · ${capFps ?? '?'} к/с вместо ${preset.width}×${preset.height} · ${preset.fps}';
          logW('cam', warning!);
        }
      }
      phase = CameraPhase.ready;
      logI('cam', 'камера открыта: ${capWidth}x$capHeight@$capFps ${facing ?? ''} audio=${hasAudio ? 'on' : 'off'}');
      // Re-attach to live peers without renegotiation.
      for (final p in connectedPeers) {
        try {
          if (p.videoSender != null) await p.videoSender!.replaceTrack(vt);
          final at = s.getAudioTracks();
          if (p.audioSender != null) await p.audioSender!.replaceTrack(at.isEmpty ? null : at.first);
          await _applyEncoding(p);
        } catch (e) {
          logW('cam', 'replaceTrack ${p.name}: $e');
        }
      }
    } catch (e) {
      phase = CameraPhase.error;
      final camStatus = await Permission.camera.status;
      final micStatus = settings.audioEnabled ? await Permission.microphone.status : PermissionStatus.granted;
      permissionDenied = camStatus.isDenied || camStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied;
      error = permissionDenied
          ? 'Нет доступа к камере или микрофону. Разрешите доступ в настройках системы.'
          : 'Не удалось открыть камеру: $e';
      logE('cam', error!);
    }
    _notify();
    _broadcastState();
  }

  Future<void> switchCamera() async {
    settings.update((s) => s.frontCamera = !s.frontCamera);
    await openCamera();
  }

  Future<void> setAudio(bool on) async {
    settings.update((s) => s.audioEnabled = on);
    await openCamera();
  }

  Future<void> setPreset(String id) async {
    settings.update((s) => s.capturePresetId = id);
    await openCamera();
  }

  // ------------------------------------------------------------- recording --
  Future<void> toggleLocalRec() async {
    if (_recOpInFlight || _handler.busy) return;
    _recOpInFlight = true;
    try {
      if (recorder.isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } on CommandFailure catch (e) {
      warning = CmdError.describe(e.code) + (e.detail != null ? ': ${e.detail}' : '');
      _notify();
    } finally {
      _recOpInFlight = false;
    }
  }

  Future<void> _startRecording() async {
    if (recorder.isRecording) return;
    final vt = videoTrack;
    if (vt == null || phase != CameraPhase.ready) throw CommandFailure(CmdError.cameraUnavailable);
    final clip = settings.takeNextClipName();
    await recorder.start(
      videoTrack: vt,
      withAudio: hasAudio,
      clipName: clip,
      deviceName: settings.deviceName,
    );
    _broadcastState();
  }

  Future<Take?> _stopRecording() async {
    if (!recorder.isRecording) return null;
    final t = await recorder.stop(saveToGallery: settings.autoSaveToGallery);
    _broadcastState();
    return t;
  }

  Future<Map<String, dynamic>?> _execute(String type) async {
    if (_recOpInFlight) throw CommandFailure(CmdError.busy);
    _recOpInFlight = true;
    try {
      if (type == MsgType.recStart) {
        final already = recorder.isRecording;
        await _startRecording();
        return {'clip': recorder.current?.name, if (already) 'already': true};
      }
      if (type == MsgType.recStop) {
        final t = await _stopRecording();
        return {
          if (t != null) 'clip': t.name,
          if (t == null) 'already': true,
          if (t?.finalizeError != null) 'ferr': t!.finalizeError,
        };
      }
      throw CommandFailure(CmdError.unknownCommand);
    } finally {
      _recOpInFlight = false;
    }
  }

  // -------------------------------------------------------------- network --
  Future<void> _startServer() async {
    lanIp = await localLanIPv4();
    final server = SignalingServer(
      onLink: _onLink,
      info: () => {
        'app': 'kinoplayback',
        'v': kProtocolVersion,
        'role': 'camera',
        'name': settings.deviceName,
        'pf': identity.platform,
      },
    );
    _server = server;
    try {
      port = await server.start(settings.port);
      await _advertiser.start(
        name: settings.deviceName,
        port: port!,
        attributes: {
          'name': settings.deviceName,
          'pf': identity.platform,
          'model': identity.model,
          'v': '$kProtocolVersion',
          'role': 'camera',
          if (lanIp != null) 'ip': lanIp!,
        },
      );
    } catch (e) {
      error = 'Сервер не запустился: $e';
      logE('sig', error!);
    }
    _notify();
  }

  String? get connectUri =>
      (lanIp == null || port == null) ? null : buildConnectUri(host: lanIp!, port: port!, name: settings.deviceName);

  void _onLink(SignalingLink link) {
    if (_disposed) {
      link.close();
      return;
    }
    if (peers.where((p) => p.phase != PeerPhase.closed).length >= 3) {
      try {
        link.send(KpMessage(type: MsgType.reject, payload: {'reason': 'Камера уже обслуживает 3 монитора'}));
      } catch (_) {}
      link.close();
      return;
    }
    final p = PeerClient(link);
    peers.add(p);
    logI('sig', 'входящее подключение ${link.remoteAddress}');
    p.sub = link.messages.listen((m) => _onSignal(p, m));
    link.done.then((_) => _dropPeer(p, 'сигнальное соединение закрыто'));
    Timer(const Duration(seconds: 10), () {
      if (p.phase == PeerPhase.hello) _dropPeer(p, 'нет hello');
    });
    _notify();
  }

  Future<void> _onSignal(PeerClient p, KpMessage m) async {
    try {
      switch (m.type) {
        case MsgType.hello:
          if (p.phase != PeerPhase.hello) return;
          p.clientId = (m.payload['cid'] as String?) ?? '';
          p.name = (m.payload['name'] as String?) ?? 'Монитор';
          p.platform = (m.payload['pf'] as String?) ?? '';
          p.model = (m.payload['model'] as String?) ?? '';
          await _admit(p);
        case MsgType.answer:
          final pc = p.pc;
          final sdp = m.payload['sdp'];
          if (pc == null || sdp is! String) return;
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          await p.ice?.markReady();
        case MsgType.ice:
          final c = candidateFromPayload(m.payload);
          if (c != null) await p.ice?.add(c);
        case MsgType.bye:
          await _dropPeer(p, 'монитор отключился');
        default:
          logW('sig', 'unexpected ${m.type} from ${p.name}');
      }
    } catch (e) {
      logE('sig', '${m.type} from ${p.name}: $e');
    }
  }

  Future<void> _admit(PeerClient p) async {
    if (phase != CameraPhase.ready || _stream == null) {
      _rejectPeer(p, 'Камера не готова');
      return;
    }
    final trusted = p.clientId.isNotEmpty && settings.trusted.containsKey(p.clientId);
    if (!trusted) {
      p.phase = PeerPhase.awaitingApproval;
      _notify();
      try {
        p.link.send(KpMessage(type: MsgType.pending));
      } catch (_) {}
      final cb = approve;
      final decision = cb == null
          ? ApprovalDecision.deny
          : await cb(p.name, '${p.platform} ${p.model}'.trim(), p.link.remoteAddress);
      if (p.phase == PeerPhase.closed) return;
      if (decision == ApprovalDecision.deny) {
        _rejectPeer(p, 'Подключение отклонено на камере');
        return;
      }
      if (decision == ApprovalDecision.always && p.clientId.isNotEmpty) {
        settings.update((s) => s.trusted = {...s.trusted, p.clientId: p.name});
      }
    }
    await _negotiate(p);
  }

  void _rejectPeer(PeerClient p, String reason) {
    try {
      p.link.send(KpMessage(type: MsgType.reject, payload: {'reason': reason}));
    } catch (_) {}
    logW('sig', '${p.name}: $reason');
    _dropPeer(p, reason);
  }

  Future<void> _negotiate(PeerClient p) async {
    p.phase = PeerPhase.negotiating;
    _notify();
    p.link.send(KpMessage(type: MsgType.welcome, sessionId: sessionId, payload: {
      'sid': sessionId,
      'name': settings.deviceName,
      'pf': identity.platform,
      'model': identity.model,
      'app': identity.appVersion,
    }));
    final pc = await createLanPeerConnection();
    p.pc = pc;
    p.ice = IceBuffer(pc);
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      try {
        p.link.send(KpMessage(type: MsgType.ice, payload: candidateToPayload(c)));
      } catch (_) {}
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      logI('rtc', '${p.name}: $s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (p.phase != PeerPhase.connected) {
          p.phase = PeerPhase.connected;
          p.connectedAt = DateTime.now();
          unawaited(_applyEncoding(p));
        }
        _notify();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _dropPeer(p, 'WebRTC: $s');
      }
    };
    final stream = _stream!;
    for (final t in stream.getTracks()) {
      final sender = await pc.addTrack(t, stream);
      if (t.kind == 'video') p.videoSender = sender;
      if (t.kind == 'audio') p.audioSender = sender;
    }
    final dc = await pc.createDataChannel(kControlChannelLabel, RTCDataChannelInit()..ordered = true);
    p.ctl = ControlChannel(
      dc,
      onMessage: (m) => _onControl(p, m),
      onOpen: () {
        logI('ctl', '${p.name}: канал управления открыт');
        _sendState(p);
      },
      onClosed: () => logW('ctl', '${p.name}: канал управления закрыт'),
    );
    final offer = await pc.createOffer(<String, dynamic>{});
    await pc.setLocalDescription(offer);
    p.link.send(KpMessage(type: MsgType.offer, payload: {'sdp': offer.sdp, 'type': offer.type}));
  }

  /// Transmission quality is set on the RTP sender only — the capture (and
  /// therefore the original recording) keeps its own resolution.
  Future<void> _applyEncoding(PeerClient p) async {
    final sender = p.videoSender;
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encs = params.encodings;
      if (encs == null || encs.isEmpty) {
        logW('rtc', 'sender has no encodings, quality not applied');
        return;
      }
      final q = settings.stream;
      final (_, short) = captureSize;
      final scale = short == null ? 1.0 : math.max(1.0, short / q.height);
      for (final e in encs) {
        e.active = true;
        e.maxBitrate = q.maxKbps * 1000;
        e.maxFramerate = q.fps;
        e.scaleResolutionDownBy = scale;
      }
      params.degradationPreference = RTCDegradationPreference.BALANCED;
      final ok = await sender.setParameters(params);
      logI('rtc', '${p.name}: поток ≤${q.height}p ${q.fps} к/с ≤${q.maxKbps} kbps (÷${scale.toStringAsFixed(2)}) ${ok ? 'OK' : 'не применено'}');
    } catch (e) {
      logW('rtc', 'setParameters: $e');
    }
  }

  Future<void> _onControl(PeerClient p, KpMessage m) async {
    if (MsgType.commands.contains(m.type)) {
      logI('ctl', '${p.name} → ${m.type} ${m.id}');
      await _handler.handle(m, (reply) {
        try {
          p.ctl?.send(reply);
        } catch (e) {
          logW('ctl', 'reply to ${p.name} failed: $e');
        }
      }, sessionId: sessionId);
      _broadcastState();
      return;
    }
    switch (m.type) {
      case MsgType.stateRequest:
        _sendState(p);
      case MsgType.takesRequest:
        final list = repo.takes.where((t) => t.source == TakeSource.original).take(50).map((t) => t.toWire()).toList();
        try {
          p.ctl?.send(KpMessage(type: MsgType.takes, sessionId: sessionId, payload: {'takes': list}));
        } catch (_) {}
      case MsgType.ping:
        try {
          p.ctl?.send(KpMessage(type: MsgType.pong, payload: {'re': m.id}));
        } catch (_) {}
      default:
        logW('ctl', 'unknown control ${m.type}');
    }
  }

  Future<void> _dropPeer(PeerClient p, String reason) async {
    if (p.phase == PeerPhase.closed) return;
    p.phase = PeerPhase.closed;
    logI('sig', '${p.name} отключён: $reason');
    await p.sub?.cancel();
    try {
      await p.ctl?.close();
    } catch (_) {}
    try {
      await p.pc?.close();
      await p.pc?.dispose();
    } catch (_) {}
    await p.link.close();
    peers.remove(p);
    // The original keeps recording: losing a monitor never stops the take.
    _notify();
  }

  Future<void> disconnectPeer(PeerClient p) async {
    try {
      p.link.send(KpMessage(type: MsgType.bye));
    } catch (_) {}
    await _dropPeer(p, 'отключён на камере');
  }

  // ----------------------------------------------------------------- state --
  CameraStateSnapshot snapshot() {
    final (w, h) = captureSize;
    final last = recorder.lastTake;
    return CameraStateSnapshot(
      seq: ++_seq,
      recording: recorder.isRecording,
      elapsedMs: recorder.elapsed.inMilliseconds,
      remoteControlAllowed: settings.remoteControlAllowed,
      clipName: recorder.current?.name,
      captureWidth: w,
      captureHeight: h,
      captureFps: capFps,
      measuredFps: senderStats?.sourceFps,
      facing: facing,
      audioEnabled: hasAudio,
      storageFreeBytes: freeBytes,
      batteryLevel: battery,
      lastSavedClip: last?.name,
      lastSaveOk: last == null ? null : last.finalizeError == null,
      lastSaveError: last?.finalizeError ?? last?.galleryError,
      cameraReady: phase == CameraPhase.ready,
      recorderNote: recorder.lastError,
    );
  }

  void _sendState(PeerClient p) {
    final ctl = p.ctl;
    if (ctl == null || !ctl.isOpen) return;
    try {
      ctl.send(KpMessage(type: MsgType.state, sessionId: sessionId, payload: snapshot().toJson()));
    } catch (_) {}
  }

  void _broadcastState() {
    if (_disposed) return;
    for (final p in peers) {
      _sendState(p);
    }
  }

  Future<void> _pollStats() async {
    StreamStats? first;
    for (final p in connectedPeers) {
      final pc = p.pc;
      if (pc == null) continue;
      try {
        final (s, c) = parseOutboundStats(toRawStats(await pc.getStats()), p.counters);
        p.stats = s;
        p.counters = c;
        first ??= s;
      } catch (_) {}
    }
    senderStats = first;
    audioLevel = first?.audioLevel;
    _notify();
  }

  Future<void> _pollSystem() async {
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {
      battery = null;
    }
    freeBytes = freeBytesAt(repo.dir.path);
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      logW('app', recorder.isRecording
          ? 'Приложение свёрнуто во время записи: система может приостановить камеру — проверьте дубль'
          : 'Приложение свёрнуто: система приостанавливает камеру');
    } else if (state == AppLifecycleState.resumed) {
      logI('app', 'приложение снова активно');
      if (phase == CameraPhase.error && !recorder.isRecording) unawaited(openCamera());
      unawaited(_pollSystem());
    }
  }

  // ------------------------------------------------------------- teardown --
  Future<void> shutdown() async {
    if (_disposed) return;
    _heartbeat?.cancel();
    _statsTimer?.cancel();
    _sysTimer?.cancel();
    if (recorder.isRecording) {
      await recorder.stop(saveToGallery: settings.autoSaveToGallery);
    }
    for (final p in List<PeerClient>.from(peers)) {
      await disconnectPeer(p);
    }
    await _advertiser.stop();
    await _server?.stop();
    final s = _stream;
    _stream = null;
    if (s != null) {
      for (final t in s.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await s.dispose();
      } catch (_) {}
    }
    preview.srcObject = null;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_onSettingsChanged);
    recorder.removeListener(_onRecorderChanged);
    _disposed = true;
    _heartbeat?.cancel();
    _statsTimer?.cancel();
    _sysTimer?.cancel();
    recorder.dispose();
    preview.dispose();
    super.dispose();
  }

  static bool get supported => Platform.isIOS || Platform.isAndroid;
}
