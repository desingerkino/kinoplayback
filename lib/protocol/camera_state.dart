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
    );
  }
}
