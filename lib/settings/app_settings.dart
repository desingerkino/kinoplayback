import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Capture presets offered for the original. Whether a preset is actually
/// available is decided by the device: after opening the camera we read the
/// real selected format back and show it (and warn if it differs).
class CapturePreset {
  const CapturePreset(this.id, this.width, this.height, this.fps, this.label);
  final String id;
  final int width;
  final int height;
  final int fps;
  final String label;

  static const all = <CapturePreset>[
    CapturePreset('2160p30', 3840, 2160, 30, '4K (3840×2160) · 30'),
    CapturePreset('2160p25', 3840, 2160, 25, '4K (3840×2160) · 25'),
    CapturePreset('2160p24', 3840, 2160, 24, '4K (3840×2160) · 24'),
    CapturePreset('1080p60', 1920, 1080, 60, '1080p (1920×1080) · 60'),
    CapturePreset('1080p30', 1920, 1080, 30, '1080p (1920×1080) · 30'),
    CapturePreset('1080p25', 1920, 1080, 25, '1080p (1920×1080) · 25'),
    CapturePreset('1080p24', 1920, 1080, 24, '1080p (1920×1080) · 24'),
    CapturePreset('720p30', 1280, 720, 30, '720p (1280×720) · 30'),
  ];

  static CapturePreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.firstWhere((p) => p.id == '1080p30'));
}

/// Quality of the transmitted stream — independent of the original.
class StreamQuality {
  const StreamQuality(this.height, this.fps, this.maxKbps);
  final int height; // target lines of the transmitted picture
  final int fps;
  final int maxKbps;

  static const heights = [1080, 720, 540, 360];
  static const fpsOptions = [60, 30, 25, 24, 15];
  static const bitrates = [12000, 8000, 5000, 3000, 1500, 800];

  Map<String, dynamic> toJson() => {'h': height, 'fps': fps, 'kbps': maxKbps};
  static StreamQuality fromJson(Map<String, dynamic> j) => StreamQuality(
        (j['h'] as num?)?.toInt() ?? 1080,
        (j['fps'] as num?)?.toInt() ?? 30,
        (j['kbps'] as num?)?.toInt() ?? 8000,
      );
}

class RecentDevice {
  RecentDevice({required this.name, required this.host, required this.port, required this.lastUsed, this.platform});
  final String name;
  final String host;
  final int port;
  final DateTime lastUsed;
  final String? platform;

  Map<String, dynamic> toJson() => {
        'n': name,
        'h': host,
        'p': port,
        't': lastUsed.millisecondsSinceEpoch,
        if (platform != null) 'pl': platform,
      };

  static RecentDevice? fromJson(Object? o) {
    if (o is! Map) return null;
    final n = o['n'], h = o['h'], p = o['p'], t = o['t'];
    if (n is! String || h is! String || p is! int || t is! int) return null;
    return RecentDevice(
      name: n,
      host: h,
      port: p,
      lastUsed: DateTime.fromMillisecondsSinceEpoch(t),
      platform: o['pl'] as String?,
    );
  }
}

class TrustedDevice {
  TrustedDevice(this.clientId, this.name);
  final String clientId;
  final String name;
}

/// Persistent app settings. Every field here changes real behaviour.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppSettings._(prefs);
    s._read();
    return s;
  }

  final SharedPreferences _prefs;

  String deviceName = '';
  String clientId = '';
  String capturePresetId = '1080p30';
  bool frontCamera = false;
  bool audioEnabled = true;
  StreamQuality stream = const StreamQuality(1080, 30, 8000);
  bool remoteControlAllowed = false;
  bool autoSaveToGallery = true;
  bool keepScreenOn = true;
  bool showStreamInfo = true;
  int port = 47800;
  String reel = 'A001';
  int nextClip = 1;
  List<RecentDevice> recent = [];
  Map<String, String> trusted = {}; // clientId → name

  // Monitor tools (PLAYBACK and CAMERA preview)
  bool toolGrid = false;
  bool toolCross = false;
  bool toolSafe = false;
  String toolAspect = 'off'; // off | 1:1 | 4:3 | 16:9 | 1.85:1 | 2.39:1
  bool toolFill = false;
  bool toolHorizon = false;

  // Orientation
  String orientationLock = 'auto'; // auto | portrait | landscapeLeft | landscapeRight
  String rotationMode = 'autoSync'; // RotationMode.name (PLAYBACK display)
  double manualRotation = 0;
  bool rollInvert = false;

  // Front camera mirror — three independent switches.
  bool frontPreviewMirror = true;
  bool recordingMirror = false; // not supported by the current recorder
  bool playbackMirror = false;

  // Focus / exposure
  bool remoteCameraControl = false; // PLAYBACK may set focus/exposure
  String tapTarget = 'both'; // both | focus | exposure

  // External display
  String externalOutput = 'clean'; // clean

  void _read() {
    final p = _prefs;
    deviceName = p.getString('deviceName') ?? '';
    clientId = p.getString('clientId') ?? '';
    capturePresetId = p.getString('capturePreset') ?? '1080p30';
    frontCamera = p.getBool('frontCamera') ?? false;
    audioEnabled = p.getBool('audioEnabled') ?? true;
    final sj = p.getString('stream');
    if (sj != null) {
      try {
        stream = StreamQuality.fromJson(jsonDecode(sj) as Map<String, dynamic>);
      } catch (_) {}
    }
    remoteControlAllowed = p.getBool('remoteControlAllowed') ?? false;
    autoSaveToGallery = p.getBool('autoSaveToGallery') ?? true;
    keepScreenOn = p.getBool('keepScreenOn') ?? true;
    showStreamInfo = p.getBool('showStreamInfo') ?? true;
    port = p.getInt('port') ?? 47800;
    reel = p.getString('reel') ?? 'A001';
    nextClip = p.getInt('nextClip') ?? 1;
    toolGrid = p.getBool('toolGrid') ?? false;
    toolCross = p.getBool('toolCross') ?? false;
    toolSafe = p.getBool('toolSafe') ?? false;
    toolAspect = p.getString('toolAspect') ?? 'off';
    toolFill = p.getBool('toolFill') ?? false;
    toolHorizon = p.getBool('toolHorizon') ?? false;
    orientationLock = p.getString('orientationLock') ?? 'auto';
    rotationMode = p.getString('rotationMode') ?? 'autoSync';
    manualRotation = p.getDouble('manualRotation') ?? 0;
    rollInvert = p.getBool('rollInvert') ?? false;
    frontPreviewMirror = p.getBool('frontPreviewMirror') ?? true;
    recordingMirror = p.getBool('recordingMirror') ?? false;
    playbackMirror = p.getBool('playbackMirror') ?? false;
    remoteCameraControl = p.getBool('remoteCameraControl') ?? false;
    tapTarget = p.getString('tapTarget') ?? 'both';
    externalOutput = p.getString('externalOutput') ?? 'clean';
    try {
      final r = jsonDecode(p.getString('recent') ?? '[]') as List;
      recent = r.map(RecentDevice.fromJson).whereType<RecentDevice>().toList();
    } catch (_) {
      recent = [];
    }
    try {
      final t = jsonDecode(p.getString('trusted') ?? '{}') as Map;
      trusted = t.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      trusted = {};
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    await p.setString('deviceName', deviceName);
    await p.setString('clientId', clientId);
    await p.setString('capturePreset', capturePresetId);
    await p.setBool('frontCamera', frontCamera);
    await p.setBool('audioEnabled', audioEnabled);
    await p.setString('stream', jsonEncode(stream.toJson()));
    await p.setBool('remoteControlAllowed', remoteControlAllowed);
    await p.setBool('autoSaveToGallery', autoSaveToGallery);
    await p.setBool('keepScreenOn', keepScreenOn);
    await p.setBool('showStreamInfo', showStreamInfo);
    await p.setInt('port', port);
    await p.setString('reel', reel);
    await p.setInt('nextClip', nextClip);
    await p.setBool('toolGrid', toolGrid);
    await p.setBool('toolCross', toolCross);
    await p.setBool('toolSafe', toolSafe);
    await p.setString('toolAspect', toolAspect);
    await p.setBool('toolFill', toolFill);
    await p.setBool('toolHorizon', toolHorizon);
    await p.setString('orientationLock', orientationLock);
    await p.setString('rotationMode', rotationMode);
    await p.setDouble('manualRotation', manualRotation);
    await p.setBool('rollInvert', rollInvert);
    await p.setBool('frontPreviewMirror', frontPreviewMirror);
    await p.setBool('recordingMirror', recordingMirror);
    await p.setBool('playbackMirror', playbackMirror);
    await p.setBool('remoteCameraControl', remoteCameraControl);
    await p.setString('tapTarget', tapTarget);
    await p.setString('externalOutput', externalOutput);
    await p.setString('recent', jsonEncode(recent.map((e) => e.toJson()).toList()));
    await p.setString('trusted', jsonEncode(trusted));
  }

  /// Apply a change and persist it.
  void update(void Function(AppSettings s) change) {
    change(this);
    notifyListeners();
    _save();
  }

  CapturePreset get capturePreset => CapturePreset.byId(capturePresetId);

  /// Reserves the next clip name (A001_C001, A001_C002 …) and persists the
  /// counter immediately so names never repeat after a crash.
  String takeNextClipName() {
    final name = '${reel}_C${nextClip.toString().padLeft(3, '0')}';
    nextClip++;
    // Write the counter first: SharedPreferences updates its cache
    // synchronously, so the next read can never hand out the same number.
    _prefs.setInt('nextClip', nextClip);
    _save();
    notifyListeners();
    return name;
  }

  void rememberRecent(RecentDevice d) {
    recent.removeWhere((e) => e.host == d.host && e.port == d.port);
    recent.insert(0, d);
    if (recent.length > 8) recent = recent.sublist(0, 8);
    notifyListeners();
    _save();
  }
}

/// Reset only the front-camera mirror preferences to their defaults.
extension MirrorDefaults on AppSettings {
  void resetMirrorDefaults() => update((s) {
        s.frontPreviewMirror = true;
        s.recordingMirror = false;
        s.playbackMirror = false;
      });
}
