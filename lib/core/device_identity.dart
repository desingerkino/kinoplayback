import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Real device facts for the diagnostics screen and the hello handshake.
class DeviceIdentity {
  DeviceIdentity({
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.appVersion,
    required this.isTablet,
    required this.isPhysical,
  });

  final String platform; // 'iOS' | 'Android'
  final String model; // "iPhone 15 Pro" / "Pixel 8"
  final String osVersion; // "18.0" / "14 (API 34)"
  final String appVersion; // "0.1.0 (12)"
  final bool isTablet;
  final bool isPhysical;

  static DeviceIdentity? _cached;
  static DeviceIdentity get current =>
      _cached ??
      DeviceIdentity(
        platform: Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : Platform.operatingSystem),
        model: '—',
        osVersion: Platform.operatingSystemVersion,
        appVersion: '—',
        isTablet: false,
        isPhysical: true,
      );

  static Future<DeviceIdentity> load({required bool isTablet}) async {
    final info = DeviceInfoPlugin();
    String platform;
    String model;
    String os;
    bool physical = true;
    try {
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        platform = i.model.toLowerCase().contains('ipad') ? 'iPadOS' : 'iOS';
        model = i.modelName.isNotEmpty ? i.modelName : i.utsname.machine;
        os = i.systemVersion;
        physical = i.isPhysicalDevice;
      } else if (Platform.isAndroid) {
        final a = await info.androidInfo;
        platform = 'Android';
        final brand = a.manufacturer.isEmpty
            ? ''
            : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
        model = a.model.toLowerCase().startsWith(a.manufacturer.toLowerCase()) ? a.model : '$brand${a.model}';
        os = '${a.version.release} (API ${a.version.sdkInt})';
        physical = a.isPhysicalDevice;
      } else {
        platform = Platform.operatingSystem;
        model = Platform.localHostname;
        os = Platform.operatingSystemVersion;
      }
    } catch (_) {
      platform = Platform.operatingSystem;
      model = '—';
      os = Platform.operatingSystemVersion;
    }
    String app = '—';
    try {
      final p = await PackageInfo.fromPlatform();
      app = '${p.version} (${p.buildNumber})';
    } catch (_) {}
    return _cached = DeviceIdentity(
      platform: platform,
      model: model,
      osVersion: os,
      appVersion: app,
      isTablet: isTablet,
      isPhysical: physical,
    );
  }
}
