import 'dart:io';
import 'dart:typed_data';

/// Facts read from the actual file — what the take list shows. Nothing here
/// is taken from settings: if the recorder wrote 1920×1080, that's what we
/// report even if 4K was requested.
class MediaFacts {
  const MediaFacts({
    this.width,
    this.height,
    this.fps,
    this.durationMs,
    this.videoCodec,
    this.audioCodec,
    this.rotation = 0,
    this.frameCount,
  });

  final int? width;
  final int? height;
  final double? fps;
  final int? durationMs;
  final String? videoCodec; // 'H.264' | 'HEVC' | fourcc
  final String? audioCodec; // 'AAC' | fourcc
  final int rotation;
  final int? frameCount;

  /// Display dimensions after applying the track rotation.
  int? get displayWidth => rotation % 180 == 0 ? width : height;
  int? get displayHeight => rotation % 180 == 0 ? height : width;

  Map<String, dynamic> toJson() => {
        if (width != null) 'w': width,
        if (height != null) 'h': height,
        if (fps != null) 'fps': fps,
        if (durationMs != null) 'dur': durationMs,
        if (videoCodec != null) 'vc': videoCodec,
        if (audioCodec != null) 'ac': audioCodec,
        'rot': rotation,
        if (frameCount != null) 'frames': frameCount,
      };

  static MediaFacts fromJson(Map<String, dynamic> j) => MediaFacts(
        width: (j['w'] as num?)?.toInt(),
        height: (j['h'] as num?)?.toInt(),
        fps: (j['fps'] as num?)?.toDouble(),
        durationMs: (j['dur'] as num?)?.toInt(),
        videoCodec: j['vc'] as String?,
        audioCodec: j['ac'] as String?,
        rotation: (j['rot'] as num?)?.toInt() ?? 0,
        frameCount: (j['frames'] as num?)?.toInt(),
      );
}

class Mp4Inspector {
  /// Reads only the box headers and the `moov` box from disk.
  static Future<MediaFacts?> inspectFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    final raf = await f.open();
    try {
      final len = await raf.length();
      var pos = 0;
      while (pos + 8 <= len) {
        await raf.setPosition(pos);
        final h = await raf.read(16);
        if (h.length < 8) break;
        final bd = ByteData.sublistView(Uint8List.fromList(h));
        var size = bd.getUint32(0);
        final type = String.fromCharCodes(h.sublist(4, 8));
        var header = 8;
        if (size == 1) {
          if (h.length < 16) break;
          size = bd.getUint64(8);
          header = 16;
        } else if (size == 0) {
          size = len - pos;
        }
        if (size < header) break;
        if (type == 'moov') {
          if (size > 64 * 1024 * 1024) return null; // implausible
          await raf.setPosition(pos + header);
          final body = await raf.read(size - header);
          return parseMoov(Uint8List.fromList(body));
        }
        pos += size;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Parses the payload of a `moov` box.
  static MediaFacts parseMoov(Uint8List moov) {
    int? movieTimescale;
    int? movieDuration;
    _Track? video;
    _Track? audio;

    for (final b in _boxes(moov, 0, moov.length)) {
      if (b.type == 'mvhd') {
        final r = _readTimes(moov, b.start);
        movieTimescale = r.$1;
        movieDuration = r.$2;
      } else if (b.type == 'trak') {
        final t = _parseTrak(moov, b.start, b.end);
        if (t.handler == 'vide' && video == null) video = t;
        if (t.handler == 'soun' && audio == null) audio = t;
      }
    }

    int? durationMs;
    if (video?.timescale != null && video?.duration != null && video!.timescale! > 0) {
      durationMs = (video.duration! * 1000 / video.timescale!).round();
    } else if (movieTimescale != null && movieDuration != null && movieTimescale > 0) {
      durationMs = (movieDuration * 1000 / movieTimescale).round();
    }

    double? fps;
    if (video?.sampleCount != null && video!.duration != null && video.timescale != null && video.duration! > 0) {
      final seconds = video.duration! / video.timescale!;
      if (seconds > 0) fps = video.sampleCount! / seconds;
    }

    return MediaFacts(
      width: video?.width,
      height: video?.height,
      fps: fps,
      durationMs: durationMs,
      videoCodec: _codecName(video?.format),
      audioCodec: _codecName(audio?.format),
      rotation: video?.rotation ?? 0,
      frameCount: video?.sampleCount,
    );
  }

  static String? _codecName(String? fourcc) => switch (fourcc) {
        null => null,
        'avc1' || 'avc3' => 'H.264',
        'hvc1' || 'hev1' => 'HEVC',
        'mp4a' => 'AAC',
        'apcn' || 'apch' || 'apcs' || 'apco' || 'ap4h' => 'ProRes',
        'Opus' => 'Opus',
        _ => fourcc,
      };

  static _Track _parseTrak(Uint8List d, int start, int end) {
    final t = _Track();
    for (final b in _boxes(d, start, end)) {
      if (b.type == 'tkhd') {
        final v = d[b.start];
        final base = b.start + (v == 1 ? 88 : 76);
        final mBase = b.start + (v == 1 ? 52 : 40);
        if (base + 8 <= b.end) {
          final bd = ByteData.sublistView(d);
          t.width = bd.getUint32(base) >> 16;
          t.height = bd.getUint32(base + 4) >> 16;
          final a = bd.getInt32(mBase);
          final bb = bd.getInt32(mBase + 4);
          if (a == 0 && bb == 65536) {
            t.rotation = 90;
          } else if (a == 0 && bb == -65536) {
            t.rotation = 270;
          } else if (a == -65536 && bb == 0) {
            t.rotation = 180;
          }
        }
      } else if (b.type == 'mdia') {
        for (final m in _boxes(d, b.start, b.end)) {
          if (m.type == 'mdhd') {
            final r = _readTimes(d, m.start);
            t.timescale = r.$1;
            t.duration = r.$2;
          } else if (m.type == 'hdlr' && m.start + 12 <= m.end) {
            t.handler = String.fromCharCodes(d.sublist(m.start + 8, m.start + 12));
          } else if (m.type == 'minf') {
            for (final s in _boxes(d, m.start, m.end)) {
              if (s.type != 'stbl') continue;
              for (final x in _boxes(d, s.start, s.end)) {
                final bd = ByteData.sublistView(d);
                if (x.type == 'stsd' && x.start + 16 <= x.end) {
                  t.format = String.fromCharCodes(d.sublist(x.start + 12, x.start + 16));
                } else if (x.type == 'stts' && x.start + 8 <= x.end) {
                  final n = bd.getUint32(x.start + 4);
                  var total = 0;
                  for (var i = 0; i < n; i++) {
                    final o = x.start + 8 + i * 8;
                    if (o + 8 > x.end) break;
                    total += bd.getUint32(o);
                  }
                  t.sampleCount = total;
                }
              }
            }
          }
        }
      }
    }
    return t;
  }

  /// (timescale, duration) from mvhd/mdhd payload.
  static (int?, int?) _readTimes(Uint8List d, int start) {
    final bd = ByteData.sublistView(d);
    final v = d[start];
    if (v == 1) {
      if (start + 32 > d.length) return (null, null);
      return (bd.getUint32(start + 20), bd.getUint64(start + 24));
    }
    if (start + 20 > d.length) return (null, null);
    return (bd.getUint32(start + 12), bd.getUint32(start + 16));
  }

  static Iterable<_Box> _boxes(Uint8List d, int start, int end) sync* {
    final bd = ByteData.sublistView(d);
    var pos = start;
    while (pos + 8 <= end) {
      var size = bd.getUint32(pos);
      final type = String.fromCharCodes(d.sublist(pos + 4, pos + 8));
      var header = 8;
      if (size == 1) {
        if (pos + 16 > end) return;
        size = bd.getUint64(pos + 8);
        header = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) return;
      yield _Box(type, pos + header, pos + size);
      pos += size;
    }
  }
}

class _Box {
  _Box(this.type, this.start, this.end);
  final String type;
  final int start; // payload start
  final int end; // exclusive
}

class _Track {
  String? handler;
  int? width;
  int? height;
  int rotation = 0;
  int? timescale;
  int? duration;
  String? format;
  int? sampleCount;
}
