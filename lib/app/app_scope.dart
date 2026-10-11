import 'package:flutter/widgets.dart';

import '../core/device_identity.dart';
import '../recording/takes.dart';
import '../settings/app_settings.dart';

class AppServices {
  AppServices({required this.settings, required this.takes, required this.identity});
  final AppSettings settings;
  final TakesRepository takes;
  final DeviceIdentity identity;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing');
    return s!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => !identical(services, oldWidget.services);
}
