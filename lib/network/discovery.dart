import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/event_log.dart';
import '../protocol/messages.dart';

/// A CAMERA found on the LAN via Bonjour / NSD.
class DiscoveredCamera {
  DiscoveredCamera({
    required this.serviceName,
    required this.host,
    required this.port,
    required this.attributes,
    required this.lastSeen,
  });

  final String serviceName;
  final String host;
  final int port;
  final Map<String, String> attributes;
  final DateTime lastSeen;

  String get displayName => attributes['name'] ?? serviceName;
  String? get platform => attributes['pf'];
  String? get model => attributes['model'];
  String get key => '$host:$port';
}

/// Advertises this device as a CAMERA.
class CameraAdvertiser {
  BonsoirBroadcast? _broadcast;

  Future<void> start({required String name, required int port, required Map<String, String> attributes}) async {
    await stop();
    // Bonjour instance names are limited to 63 bytes.
    var instance = name.isEmpty ? 'KINO PLAYBACK' : name;
    while (instance.codeUnits.length > 60) {
      instance = instance.substring(0, instance.length - 1);
    }
    final service = BonsoirService(name: instance, type: kBonjourType, port: port, attributes: attributes);
    final b = BonsoirBroadcast(service: service);
    try {
      await b.ready;
      await b.start();
      _broadcast = b;
      logI('mdns', 'advertising "$instance" $kBonjourType :$port');
    } catch (e) {
      logE('mdns', 'advertise failed: $e');
    }
  }

  Future<void> stop() async {
    final b = _broadcast;
    _broadcast = null;
    if (b != null) {
      try {
        await b.stop();
      } catch (_) {}
    }
  }
}

/// Browses for CAMERAs.
class CameraBrowser extends ChangeNotifier {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final Map<String, DiscoveredCamera> _found = {};
  bool _searching = false;
  String? error;

  bool get searching => _searching;
  List<DiscoveredCamera> get cameras {
    final l = _found.values.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    return l;
  }

  Future<void> start() async {
    if (_searching) return;
    _searching = true;
    error = null;
    notifyListeners();
    try {
      final d = BonsoirDiscovery(type: kBonjourType);
      _discovery = d;
      await d.ready;
      _sub = d.eventStream?.listen(_onEvent);
      await d.start();
      logI('mdns', 'browsing $kBonjourType');
    } catch (e) {
      error = 'Поиск в сети недоступен: $e';
      logE('mdns', error!);
      _searching = false;
      notifyListeners();
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    final s = event.service;
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        if (s != null && _discovery != null) {
          s.resolve(_discovery!.serviceResolver);
        }
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        if (s is ResolvedBonsoirService) {
          // Prefer the IPv4 address the camera announced in TXT (Android's
          // resolver cannot resolve *.local names); fall back to host.
          final ip = s.attributes['ip'];
          final host = (ip != null && ip.isNotEmpty) ? ip : (s.host ?? '');
          if (host.isEmpty) return;
          final cam = DiscoveredCamera(
            serviceName: s.name,
            host: host.endsWith('.') ? host.substring(0, host.length - 1) : host,
            port: s.port,
            attributes: s.attributes,
            lastSeen: DateTime.now(),
          );
          _found[s.name] = cam;
          logI('mdns', 'found ${cam.displayName} @ ${cam.key}');
          notifyListeners();
        }
      case BonsoirDiscoveryEventType.discoveryServiceResolveFailed:
        logW('mdns', 'resolve failed: ${s?.name}');
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        if (s != null && _found.remove(s.name) != null) {
          logI('mdns', 'lost ${s.name}');
          notifyListeners();
        }
      default:
        break;
    }
  }

  Future<void> stop() async {
    _searching = false;
    await _sub?.cancel();
    _sub = null;
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await d.stop();
      } catch (_) {}
    }
  }

  Future<void> restart() async {
    await stop();
    _found.clear();
    notifyListeners();
    await start();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
