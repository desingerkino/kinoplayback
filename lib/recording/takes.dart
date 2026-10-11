import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/event_log.dart';
import 'mp4_inspector.dart';

enum TakeSource { original, monitor }

/// One recorded file plus its sidecar metadata (`<name>.json`). Metadata is
/// filled from the real file (MP4 boxes, file size) after recording stops.
class Take {
  Take({
    required this.name,
    required this.videoPath,
    required this.createdAt,
    required this.source,
    required this.deviceName,
    this.remoteDevice,
    this.facts,
    this.sizeBytes,
    this.thumbPath,
    this.savedToGallery = false,
    this.galleryError,
    this.finalizeError,
    this.interrupted = false,
  });

  final String name;
  final String videoPath;
  final DateTime createdAt;
  final TakeSource source;
  final String deviceName; // device the file lives on
  final String? remoteDevice; // for monitor recordings: camera it came from
  MediaFacts? facts;
  int? sizeBytes;
  String? thumbPath;
  bool savedToGallery;
  String? galleryError;
  String? finalizeError;
  bool interrupted; // stream dropped while recording

  String get sidecarPath => videoPath.replaceAll(RegExp(r'\.mp4$'), '.json');

  Map<String, dynamic> toJson() => {
        'name': name,
        'video': videoPath.split(Platform.pathSeparator).last,
        'created': createdAt.millisecondsSinceEpoch,
        'src': source.name,
        'dev': deviceName,
        if (remoteDevice != null) 'rdev': remoteDevice,
        if (facts != null) 'facts': facts!.toJson(),
        if (sizeBytes != null) 'size': sizeBytes,
        if (thumbPath != null) 'thumb': thumbPath!.split(Platform.pathSeparator).last,
        'gallery': savedToGallery,
        if (galleryError != null) 'gerr': galleryError,
        if (finalizeError != null) 'ferr': finalizeError,
        'interrupted': interrupted,
      };

  /// Compact form sent to PLAYBACK in `takes` (no paths).
  Map<String, dynamic> toWire() => {
        'name': name,
        'created': createdAt.millisecondsSinceEpoch,
        'src': source.name,
        'dev': deviceName,
        if (facts != null) 'facts': facts!.toJson(),
        if (sizeBytes != null) 'size': sizeBytes,
        'gallery': savedToGallery,
        if (finalizeError != null) 'ferr': finalizeError,
      };

  static Take? fromJson(Map<String, dynamic> j, String dir) {
    final name = j['name'];
    final video = j['video'];
    final created = j['created'];
    if (name is! String || video is! String || created is! int) return null;
    return Take(
      name: name,
      videoPath: '$dir${Platform.pathSeparator}$video',
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      source: j['src'] == 'monitor' ? TakeSource.monitor : TakeSource.original,
      deviceName: (j['dev'] as String?) ?? '',
      remoteDevice: j['rdev'] as String?,
      facts: j['facts'] is Map<String, dynamic> ? MediaFacts.fromJson(j['facts'] as Map<String, dynamic>) : null,
      sizeBytes: (j['size'] as num?)?.toInt(),
      thumbPath: j['thumb'] is String ? '$dir${Platform.pathSeparator}${j['thumb']}' : null,
      savedToGallery: j['gallery'] == true,
      galleryError: j['gerr'] as String?,
      finalizeError: j['ferr'] as String?,
      interrupted: j['interrupted'] == true,
    );
  }

  static Take? fromWire(Map<String, dynamic> j) {
    final name = j['name'];
    final created = j['created'];
    if (name is! String || created is! int) return null;
    return Take(
      name: name,
      videoPath: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      source: j['src'] == 'monitor' ? TakeSource.monitor : TakeSource.original,
      deviceName: (j['dev'] as String?) ?? '',
      facts: j['facts'] is Map<String, dynamic> ? MediaFacts.fromJson(j['facts'] as Map<String, dynamic>) : null,
      sizeBytes: (j['size'] as num?)?.toInt(),
      savedToGallery: j['gallery'] == true,
      finalizeError: j['ferr'] as String?,
    );
  }
}

/// Takes stored in the app's Documents/Takes folder (visible in the iOS
/// Files app; copies also go to Photos / gallery).
class TakesRepository extends ChangeNotifier {
  TakesRepository._(this.dir);

  /// For tests and tools: a repository over an arbitrary folder.
  TakesRepository.forDirectory(this.dir);

  static Future<TakesRepository> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}Takes');
    if (!await d.exists()) await d.create(recursive: true);
    final repo = TakesRepository._(d);
    await repo.reload();
    return repo;
  }

  final Directory dir;
  List<Take> _takes = [];
  List<Take> get takes => List.unmodifiable(_takes);

  Future<void> reload() async {
    final list = <Take>[];
    try {
      await for (final e in dir.list()) {
        if (e is! File || !e.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(await e.readAsString());
          if (j is Map<String, dynamic>) {
            final t = Take.fromJson(j, dir.path);
            if (t != null && await File(t.videoPath).exists()) list.add(t);
          }
        } catch (err) {
          logW('takes', 'bad sidecar ${e.path}: $err');
        }
      }
    } catch (err) {
      logE('takes', 'list failed: $err');
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _takes = list;
    notifyListeners();
  }

  String pathFor(String name, String ext) => '${dir.path}${Platform.pathSeparator}$name.$ext';

  /// Avoids overwriting: A001_C003.mp4 exists → A001_C003_2.mp4.
  String uniqueBase(String name) {
    var base = name;
    var i = 2;
    while (File(pathFor(base, 'mp4')).existsSync()) {
      base = '${name}_$i';
      i++;
    }
    return base;
  }

  Future<void> save(Take t) async {
    await File(t.sidecarPath).writeAsString(jsonEncode(t.toJson()), flush: true);
    final i = _takes.indexWhere((e) => e.videoPath == t.videoPath);
    if (i >= 0) {
      _takes[i] = t;
    } else {
      _takes.insert(0, t);
    }
    notifyListeners();
  }

  Future<void> delete(Take t) async {
    for (final p in [t.videoPath, t.sidecarPath, if (t.thumbPath != null) t.thumbPath!]) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (e) {
        logW('takes', 'delete $p: $e');
      }
    }
    _takes.removeWhere((e) => e.videoPath == t.videoPath);
    notifyListeners();
  }
}
