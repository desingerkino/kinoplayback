import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gal/gal.dart';

import '../core/event_log.dart';
import '../core/storage_info.dart';
import '../protocol/messages.dart';
import '../session/remote_commands.dart';
import 'mp4_inspector.dart';
import 'takes.dart';

enum RecorderPhase { idle, starting, recording, stopping }

/// Records a WebRTC video track (+ audio where the platform supports it) to
/// an MP4 in Documents/Takes, then verifies the file, reads its real
/// parameters, and copies it into Photos / gallery.
///
/// Used for both the CAMERA original (local capture track) and the PLAYBACK
/// monitor recording (received track).
class TakeRecorder extends ChangeNotifier {
  TakeRecorder({required this.repo, required this.source});

  final TakesRepository repo;
  final TakeSource source;

  static const int minFreeBytes = 300 * 1000 * 1000;

  RecorderPhase _phase = RecorderPhase.idle;
  RecorderPhase get phase => _phase;
  bool get isRecording => _phase == RecorderPhase.recording;
  bool get busy => _phase == RecorderPhase.starting || _phase == RecorderPhase.stopping;

  MediaRecorder? _rec;
  Take? _current;
  Take? get current => _current;
  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  Take? lastTake;
  String? lastError;

  /// Called when a take's metadata changes after stop (e.g. gallery save
  /// finished), so state can be re-broadcast.
  void Function(Take take)? onTakeUpdated;

  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  void _set(RecorderPhase p) {
    _phase = p;
    notifyListeners();
  }

  /// Starts recording. Completes only after the native recorder accepted the
  /// start. Throws [CommandFailure] with a protocol error code on failure.
  Future<Take> start({
    required MediaStreamTrack videoTrack,
    required bool withAudio,
    required String clipName,
    required String deviceName,
    String? remoteDevice,
  }) async {
    if (_phase == RecorderPhase.recording && _current != null) return _current!;
    if (_phase != RecorderPhase.idle) throw CommandFailure(CmdError.busy);

    final free = freeBytesAt(repo.dir.path);
    if (free != null && free < minFreeBytes) {
      lastError = 'Недостаточно места: ${formatBytes(free)}';
      notifyListeners();
      throw CommandFailure(CmdError.noStorage, lastError);
    }

    _set(RecorderPhase.starting);
    final base = repo.uniqueBase(clipName);
    final path = repo.pathFor(base, 'mp4');
    final take = Take(
      name: base,
      videoPath: path,
      createdAt: DateTime.now(),
      source: source,
      deviceName: deviceName,
      remoteDevice: remoteDevice,
    );
    final rec = MediaRecorder(albumName: null);
    try {
      await rec.start(
        path,
        videoTrack: videoTrack,
        // Android: INPUT = microphone (original), OUTPUT = received audio
        // (monitor). iOS ignores this and uses the audio track of the same
        // stream as the video track.
        audioChannel: withAudio
            ? (source == TakeSource.original ? RecorderAudioChannel.INPUT : RecorderAudioChannel.OUTPUT)
            : null,
      );
    } catch (e) {
      lastError = 'Не удалось начать запись: $e';
      logE('rec', lastError!);
      _set(RecorderPhase.idle);
      throw CommandFailure(CmdError.recorderError, '$e');
    }
    _rec = rec;
    _current = take;
    _startedAt = DateTime.now();
    lastError = null;
    _set(RecorderPhase.recording);
    logI('rec', '● REC ${take.name} (${source.name}) → $path');
    unawaited(_grabThumb(videoTrack, take));
    return take;
  }

  Future<void> _grabThumb(MediaStreamTrack track, Take take) async {
    // Give the encoder a moment so we capture a real frame, not black.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    try {
      final ByteBuffer buf = await track.captureFrame();
      final thumb = repo.pathFor(take.name, 'png');
      await File(thumb).writeAsBytes(buf.asUint8List(), flush: true);
      take.thumbPath = thumb;
    } catch (e) {
      logW('rec', 'thumbnail: $e');
    }
  }

  /// Stops and finalises. [interrupted] marks takes whose input stream was
  /// lost mid-recording (monitor side).
  Future<Take?> stop({bool interrupted = false, bool saveToGallery = true}) async {
    if (_phase != RecorderPhase.recording) return null;
    final rec = _rec;
    final take = _current;
    if (rec == null || take == null) {
      _set(RecorderPhase.idle);
      return null;
    }
    _set(RecorderPhase.stopping);
    String? finalizeError;
    try {
      // iOS never answers if no frame ever arrived — don't hang forever.
      await rec.stop().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      finalizeError = 'Рекордер не подтвердил завершение файла (таймаут)';
    } catch (e) {
      finalizeError = 'Ошибка завершения файла: $e';
    }
    _rec = null;
    _startedAt = null;
    take.interrupted = interrupted;

    final f = File(take.videoPath);
    final exists = await f.exists();
    final size = exists ? await f.length() : 0;
    if (!exists || size == 0) {
      finalizeError ??= 'Файл не создан или пуст';
    }
    take.sizeBytes = exists ? size : null;
    if (exists && size > 0) {
      try {
        take.facts = await Mp4Inspector.inspectFile(take.videoPath);
        if (take.facts == null) finalizeError ??= 'Файл без индекса MP4 (moov) — вероятно, не завершён';
      } catch (e) {
        logW('rec', 'inspect: $e');
      }
    }
    take.finalizeError = finalizeError;

    if (exists && size > 0) {
      await repo.save(take);
    }
    _current = null;
    lastTake = take;
    lastError = finalizeError;
    _set(RecorderPhase.idle);
    if (finalizeError != null) {
      logE('rec', '${take.name}: $finalizeError');
    } else {
      final fx = take.facts;
      logI('rec', '■ ${take.name}: ${fx?.displayWidth}×${fx?.displayHeight} '
          '${fx?.fps?.toStringAsFixed(2)} fps ${fx?.videoCodec}/${fx?.audioCodec ?? '—'} '
          '${formatBytes(size)}');
    }

    if (saveToGallery && exists && size > 0 && take.facts != null) {
      // Don't block the stop confirmation on the Photos copy (it can take a
      // while for long takes); the result is reported when it completes.
      unawaited(copyToGallery(take).then((_) => onTakeUpdated?.call(take)));
    }
    return take;
  }

  Future<bool> copyToGallery(Take take) async {
    final ok = await saveTakeToGallery(repo, take);
    notifyListeners();
    return ok;
  }

  @override
  void dispose() {
    if (_phase == RecorderPhase.recording) {
      // Best effort; the screen owning the recorder should stop it first.
      _rec?.stop().catchError((_) {});
    }
    super.dispose();
  }
}

class _GalDenied implements Exception {
  const _GalDenied();
}

/// Copies a finished take into Photos / gallery. The original in
/// Documents/Takes is kept regardless of the outcome.
Future<bool> saveTakeToGallery(TakesRepository repo, Take take) async {
  try {
    if (!await Gal.hasAccess()) {
      final ok = await Gal.requestAccess();
      if (!ok) throw const _GalDenied();
    }
    await Gal.putVideo(take.videoPath);
    take.savedToGallery = true;
    take.galleryError = null;
    logI('rec', '${take.name}: сохранено в медиатеку');
  } on _GalDenied {
    take.savedToGallery = false;
    take.galleryError = 'Нет доступа к медиатеке';
  } on GalException catch (e) {
    take.savedToGallery = false;
    take.galleryError = switch (e.type) {
      GalExceptionType.accessDenied => 'Нет доступа к медиатеке',
      GalExceptionType.notEnoughSpace => 'Недостаточно места',
      GalExceptionType.notSupportedFormat => 'Формат не поддерживается медиатекой',
      GalExceptionType.unexpected => 'Ошибка медиатеки',
    };
  } catch (e) {
    take.savedToGallery = false;
    take.galleryError = '$e';
  }
  if (!take.savedToGallery) logW('rec', '${take.name}: медиатека — ${take.galleryError}');
  await repo.save(take);
  return take.savedToGallery;
}
