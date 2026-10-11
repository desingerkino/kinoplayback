/// State snapshot the CAMERA broadcasts on every change and as a 2-second
/// heartbeat. PLAYBACK renders REC / timer / permissions only from this, so
/// after a reconnect the UI is rebuilt from fresh data, never from stale UI.
class CameraStateSnapshot {
  const CameraStateSnapshot({
    required this.seq,
    required this.recording,
    required this.elapsedMs,
    required this.remoteControlAllowed,
    this.clipName,
    this.captureWidth,
    this.captureHeight,
    this.captureFps,
    this.measuredFps,
    this.facing,
    this.audioEnabled = false,
    this.storageFreeBytes,
    this.batteryLevel,
    this.lastSavedClip,
    this.lastSaveOk,
    this.lastSaveError,
    this.cameraReady = true,
    this.recorderNote,
    this.remoteCameraControl = false,
    this.afLocked = false,
    this.aeLocked = false,
    this.zoom,
    this.focusPoint,
    this.exposurePoint,
    this.caps = const CameraCaps(),
    this.externalSource,
    this.mirrorApplied = false,
  });

  /// Monotonic counter; older snapshots are ignored.
  final int seq;
  final bool recording;

  /// How long the current clip has been recording when this snapshot was
  /// sent. PLAYBACK anchors its own timer to `receivedAt - elapsed`, which
  /// needs no clock sync between devices (error ≈ one-way network delay).
  final int elapsedMs;
  final bool remoteControlAllowed;
  final String? clipName;
  final int? captureWidth;
  final int? captureHeight;
  final int? captureFps; // requested
  final double? measuredFps; // from WebRTC media-source stats, if available
  final String? facing; // 'back' | 'front'
  final bool audioEnabled;
  final int? storageFreeBytes;
  final int? batteryLevel;
  final String? lastSavedClip;
  final bool? lastSaveOk;
  final String? lastSaveError;
  final bool cameraReady;
  final String? recorderNote;

  /// PLAYBACK may set focus / exposure / zoom.
  final bool remoteCameraControl;
  final bool afLocked;
  final bool aeLocked;
  final double? zoom;

  /// Last points applied on the camera, normalised (0..1) picture coords.
  final (double, double)? focusPoint;
  final (double, double)? exposurePoint;
  final CameraCaps caps;

  /// Non-null when the CAMERA is serving an external (USB/UVC) source.
  final String? externalSource;

  /// Whether transmitted frames were mirrored by the CAMERA (always false in
  /// this version — mirroring is display-only), so PLAYBACK never mirrors
  /// twice.
  final bool mirrorApplied;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'rec': recording,
        'el': elapsedMs,
        'rc': remoteControlAllowed,
        if (clipName != null) 'clip': clipName,
        if (captureWidth != null) 'w': captureWidth,
        if (captureHeight != null) 'h': captureHeight,
        if (captureFps != null) 'fps': captureFps,
        if (measuredFps != null) 'mfps': measuredFps,
        if (facing != null) 'face': facing,
        'aud': audioEnabled,
        if (storageFreeBytes != null) 'free': storageFreeBytes,
        if (batteryLevel != null) 'bat': batteryLevel,
        if (lastSavedClip != null) 'lsc': lastSavedClip,
        if (lastSaveOk != null) 'lso': lastSaveOk,
        if (lastSaveError != null) 'lse': lastSaveError,
        'ready': cameraReady,
        if (recorderNote != null) 'note': recorderNote,
        'rcc': remoteCameraControl,
        'afl': afLocked,
        'ael': aeLocked,
        if (zoom != null) 'zoom': zoom,
        if (focusPoint != null) 'fp': [focusPoint!.$1, focusPoint!.$2],
        if (exposurePoint != null) 'ep': [exposurePoint!.$1, exposurePoint!.$2],
        'caps': caps.toJson(),
        if (externalSource != null) 'ext': externalSource,
        'mir': mirrorApplied,
      };

  static CameraStateSnapshot fromJson(Map<String, dynamic> j) {
    int? i(String k) {
      final v = j[k];
      return v is num ? v.toInt() : null;
    }

    double? d(String k) {
      final v = j[k];
      return v is num ? v.toDouble() : null;
    }

    String? s(String k) {
      final v = j[k];
      return v is String ? v : null;
    }

    return CameraStateSnapshot(
      seq: i('seq') ?? 0,
      recording: j['rec'] == true,
      elapsedMs: i('el') ?? 0,
      remoteControlAllowed: j['rc'] == true,
      clipName: s('clip'),
      captureWidth: i('w'),
      captureHeight: i('h'),
      captureFps: i('fps'),
      measuredFps: d('mfps'),
      facing: s('face'),
      audioEnabled: j['aud'] == true,
      storageFreeBytes: i('free'),
      batteryLevel: i('bat'),
      lastSavedClip: s('lsc'),
      lastSaveOk: j['lso'] is bool ? j['lso'] as bool : null,
      lastSaveError: s('lse'),
      cameraReady: j['ready'] != false,
      recorderNote: s('note'),
      remoteCameraControl: j['rcc'] == true,
      afLocked: j['afl'] == true,
      aeLocked: j['ael'] == true,
      zoom: d('zoom'),
      focusPoint: _pt(j['fp']),
      exposurePoint: _pt(j['ep']),
      caps: j['caps'] is Map<String, dynamic> ? CameraCaps.fromJson(j['caps'] as Map<String, dynamic>) : const CameraCaps(),
      externalSource: s('ext'),
      mirrorApplied: j['mir'] == true,
    );
  }

  static (double, double)? _pt(Object? v) {
    if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
      return ((v[0] as num).toDouble(), (v[1] as num).toDouble());
    }
    return null;
  }
}

/// What this camera can actually do through the current capture pipeline.
/// Anything false is shown as unavailable — never as a working control.
class CameraCaps {
  const CameraCaps({
    this.focusPoint = false,
    this.exposurePoint = false,
    this.focusLock = false,
    this.exposureLock = false,
    this.zoom = false,
    this.manualFocus = false,
    this.manualExposure = false,
    this.exposureCompensation = false,
    this.whiteBalance = false,
    this.motion = false,
  });

  final bool focusPoint;
  final bool exposurePoint;
  final bool focusLock;
  final bool exposureLock;
  final bool zoom;
  final bool manualFocus;
  final bool manualExposure;
  final bool exposureCompensation;
  final bool whiteBalance;
  final bool motion;

  Map<String, dynamic> toJson() => {
        'fp': focusPoint,
        'ep': exposurePoint,
        'fl': focusLock,
        'el': exposureLock,
        'z': zoom,
        'mf': manualFocus,
        'me': manualExposure,
        'ev': exposureCompensation,
        'wb': whiteBalance,
        'mo': motion,
      };

  static CameraCaps fromJson(Map<String, dynamic> j) => CameraCaps(
        focusPoint: j['fp'] == true,
        exposurePoint: j['ep'] == true,
        focusLock: j['fl'] == true,
        exposureLock: j['el'] == true,
        zoom: j['z'] == true,
        manualFocus: j['mf'] == true,
        manualExposure: j['me'] == true,
        exposureCompensation: j['ev'] == true,
        whiteBalance: j['wb'] == true,
        motion: j['mo'] == true,
      );
}
