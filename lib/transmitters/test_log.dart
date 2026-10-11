import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TestResult { passed, partial, failed }

extension TestResultX on TestResult {
  String get label => switch (this) {
        TestResult.passed => 'Работает',
        TestResult.partial => 'Частично',
        TestResult.failed => 'Не работает',
      };
}

/// One physical test of a transmitter combination, entered on set.
/// This log is the ONLY thing that can promote a model to
/// SUPPORTED & TESTED in the catalogue.
class TransmitterTest {
  TransmitterTest({
    required this.id,
    required this.modelId,
    required this.date,
    required this.scenario,
    required this.device,
    required this.platform,
    required this.osVersion,
    required this.connection,
    required this.cables,
    required this.signal,
    required this.result,
    this.latencyMs,
    this.stability = '',
    this.notes = '',
  });

  final String id;
  final String modelId;
  final DateTime date;
  final String scenario; // A | B | C
  final String device; // phone / tablet model
  final String platform; // iOS / iPadOS / Android
  final String osVersion;
  final String connection; // e.g. "RX UVC → USB-C → iPad"
  final String cables;
  final String signal; // e.g. "1080p25 SDI"
  final TestResult result;
  final int? latencyMs; // only if actually measured
  final String stability;
  final String notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'm': modelId,
        'd': date.millisecondsSinceEpoch,
        'sc': scenario,
        'dev': device,
        'pf': platform,
        'os': osVersion,
        'conn': connection,
        'cab': cables,
        'sig': signal,
        'res': result.name,
        if (latencyMs != null) 'lat': latencyMs,
        'stab': stability,
        'notes': notes,
      };

  static TransmitterTest? fromJson(Object? o) {
    if (o is! Map) return null;
    try {
      return TransmitterTest(
        id: o['id'] as String,
        modelId: o['m'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(o['d'] as int),
        scenario: o['sc'] as String? ?? 'B',
        device: o['dev'] as String? ?? '',
        platform: o['pf'] as String? ?? '',
        osVersion: o['os'] as String? ?? '',
        connection: o['conn'] as String? ?? '',
        cables: o['cab'] as String? ?? '',
        signal: o['sig'] as String? ?? '',
        result: TestResult.values.firstWhere((r) => r.name == o['res'], orElse: () => TestResult.failed),
        latencyMs: (o['lat'] as num?)?.toInt(),
        stability: o['stab'] as String? ?? '',
        notes: o['notes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class TransmitterTestLog extends ChangeNotifier {
  TransmitterTestLog._(this._prefs) {
    try {
      final raw = jsonDecode(_prefs.getString(_key) ?? '[]') as List;
      _tests = raw.map(TransmitterTest.fromJson).whereType<TransmitterTest>().toList();
    } catch (_) {
      _tests = [];
    }
  }

  static const _key = 'txTests';
  static TransmitterTestLog? _instance;

  static Future<TransmitterTestLog> open() async =>
      _instance ??= TransmitterTestLog._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  List<TransmitterTest> _tests = [];

  List<TransmitterTest> get all => List.unmodifiable(_tests);
  List<TransmitterTest> forModel(String id) => _tests.where((t) => t.modelId == id).toList();

  /// A model counts as SUPPORTED & TESTED for a scenario only when at least
  /// one physical test of that scenario passed.
  bool testedOk(String modelId, String scenario) =>
      _tests.any((t) => t.modelId == modelId && t.scenario == scenario && t.result == TestResult.passed);

  Future<void> add(TransmitterTest t) async {
    _tests.insert(0, t);
    await _persist();
  }

  Future<void> remove(String id) async {
    _tests.removeWhere((t) => t.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(_key, jsonEncode(_tests.map((t) => t.toJson()).toList()));
    notifyListeners();
  }
}
