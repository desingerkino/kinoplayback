import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// The native track id + peer connection id are needed to find the same
// WebRTC track on the native side (flutter_webrtc keeps them there).
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';

import '../core/event_log.dart';

/// State of the external display output, as reported by the OS / native code.
enum ExternalOutputState { notSupported, notConnected, connected, outputActive }

extension ExternalOutputStateX on ExternalOutputState {
  String get label => switch (this) {
        ExternalOutputState.notSupported => 'NOT SUPPORTED',
        ExternalOutputState.notConnected => 'NOT CONNECTED',
        ExternalOutputState.connected => 'CONNECTED',
        ExternalOutputState.outputActive => 'OUTPUT ACTIVE',
      };
}

/// CLEAN FEED on an external screen: AirPlay screen mirroring to Apple TV /
/// AirPlay TV, or a wired HDMI / USB-C display (iOS); an Android
/// "presentation" display (USB-C DisplayPort Alt Mode, HDMI, some wireless
/// displays).
///
/// The OS creates the external screen; the app then draws ONLY the video
/// track there (native WebRTC renderer, no Flutter UI), while the phone
/// keeps the full interface. Recording and the CAMERA → PLAYBACK stream are
/// independent of it.
class ExternalDisplay extends ChangeNotifier {
  ExternalDisplay._() {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      state = ExternalOutputState.notSupported;
      return;
    }
    _events.receiveBroadcastStream().listen(_onEvent, onError: (Object e) {
      state = ExternalOutputState.notSupported;
      error = '$e';
      notifyListeners();
    });
    refresh();
  }

  static final ExternalDisplay instance = ExternalDisplay._();

  static const _ch = MethodChannel('kinoplayback/external_display');
  static const _events = EventChannel('kinoplayback/external_display/events');

  ExternalOutputState state = ExternalOutputState.notConnected;
  String? displayName;
  int? width;
  int? height;
  String? kind; // airplay | wired | presentation | unknown
  String? error;
  String? attachedTrackId;

  bool get connected => state == ExternalOutputState.connected || state == ExternalOutputState.outputActive;

  void _onEvent(dynamic e) {
    if (e is Map) _apply(e);
  }

  void _apply(Map e) {
    final c = e['connected'] == true;
    final active = e['active'] == true;
    final was = state;
    state = !c
        ? ExternalOutputState.notConnected
        : (active ? ExternalOutputState.outputActive : ExternalOutputState.connected);
    displayName = e['name'] as String?;
    width = (e['width'] as num?)?.toInt();
    height = (e['height'] as num?)?.toInt();
    kind = e['kind'] as String?;
    if (!c) attachedTrackId = null;
    if (was != state) logI('tv', 'внешний дисплей: ${state.label}${displayName != null ? ' ($displayName)' : ''}');
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final r = await _ch.invokeMethod<Map>('status');
      if (r != null) _apply(r);
    } on MissingPluginException {
      state = ExternalOutputState.notSupported;
      notifyListeners();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  /// Shows [track] full-screen on the external display (clean feed).
  Future<bool> show(MediaStreamTrack track, {bool mirror = false, double rotation = 0}) async {
    if (!connected) return false;
    final native = track is MediaStreamTrackNative ? track : null;
    try {
      final ok = await _ch.invokeMethod<bool>('attach', {
        'trackId': track.id,
        'peerConnectionId': native?.peerConnectionId,
        'mirror': mirror,
        'rotation': rotation,
      });
      attachedTrackId = ok == true ? track.id : null;
      await refresh();
      return ok == true;
    } catch (e) {
      error = '$e';
      logW('tv', 'вывод не запущен: $e');
      notifyListeners();
      return false;
    }
  }

  /// Updates mirror / rotation of the external picture without re-attaching.
  Future<void> setTransform({bool mirror = false, double rotation = 0}) async {
    if (attachedTrackId == null) return;
    try {
      await _ch.invokeMethod('transform', {'mirror': mirror, 'rotation': rotation});
    } catch (_) {}
  }

  Future<void> hide() async {
    attachedTrackId = null;
    try {
      await _ch.invokeMethod('detach');
    } catch (_) {}
    await refresh();
  }
}
