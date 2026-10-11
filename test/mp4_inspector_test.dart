import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/recording/mp4_inspector.dart';

/// Minimal MP4 box builder for tests.
Uint8List box(String type, List<int> payload) {
  final size = 8 + payload.length;
  final b = BytesBuilder();
  b.add(_u32(size));
  b.add(type.codeUnits);
  b.add(payload);
  return b.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
List<int> _u16(int v) => [(v >> 8) & 255, v & 255];
List<int> _zeros(int n) => List<int>.filled(n, 0);

List<int> tkhdV0({required int w, required int h, int a = 65536, int b = 0}) {
  return [
    0, 0, 0, 3, // version 0 + flags
    ..._zeros(4), ..._zeros(4), // creation, modification
    ..._u32(1), ..._zeros(4), // track id, reserved
    ..._u32(0), // duration
    ..._zeros(8), // reserved
    ..._u16(0), ..._u16(0), ..._u16(0), ..._u16(0), // layer, alt group, volume, reserved
    ..._u32(a), ..._u32(b), ..._u32(0), // matrix row 1
    ..._u32(b == 0 ? 0 : (-b) & 0xFFFFFFFF), ..._u32(a & 0xFFFFFFFF), ..._u32(0), // row 2
    ..._u32(0), ..._u32(0), ..._u32(0x40000000), // row 3
    ..._u32(w << 16), ..._u32(h << 16),
  ];
}

List<int> mdhdV0({required int timescale, required int duration}) =>
    [0, 0, 0, 0, ..._zeros(8), ..._u32(timescale), ..._u32(duration), ..._zeros(4)];

List<int> hdlr(String type) => [0, 0, 0, 0, ..._zeros(4), ...type.codeUnits, ..._zeros(12), 0];

List<int> stsd(String fourcc) => [0, 0, 0, 0, ..._u32(1), ..._u32(16), ...fourcc.codeUnits, ..._zeros(8)];

List<int> stts(List<(int, int)> entries) => [
      0, 0, 0, 0,
      ..._u32(entries.length),
      for (final e in entries) ...[..._u32(e.$1), ..._u32(e.$2)],
    ];

Uint8List trak({
  required String handler,
  required String fourcc,
  required int timescale,
  required int duration,
  int w = 0,
  int h = 0,
  List<(int, int)> samples = const [],
  int a = 65536,
  int b = 0,
}) {
  final stbl = box('stbl', [...box('stsd', stsd(fourcc)), ...box('stts', stts(samples))]);
  final minf = box('minf', stbl);
  final mdia = box('mdia', [
    ...box('mdhd', mdhdV0(timescale: timescale, duration: duration)),
    ...box('hdlr', hdlr(handler)),
    ...minf,
  ]);
  return box('trak', [...box('tkhd', tkhdV0(w: w, h: h, a: a, b: b)), ...mdia]);
}

Uint8List moovPayload({int a = 65536, int b = 0}) {
  final mvhd = box('mvhd', [0, 0, 0, 0, ..._zeros(8), ..._u32(1000), ..._u32(10000), ..._zeros(80)]);
  final video = trak(
    handler: 'vide',
    fourcc: 'avc1',
    timescale: 90000,
    duration: 900000, // 10 s
    w: 3840,
    h: 2160,
    samples: [(250, 3600), (50, 3600)], // 300 frames
    a: a,
    b: b,
  );
  final audio = trak(handler: 'soun', fourcc: 'mp4a', timescale: 48000, duration: 480000);
  return Uint8List.fromList([...mvhd, ...video, ...audio]);
}

void main() {
  test('reads real dimensions, fps, duration and codecs from moov', () {
    final f = Mp4Inspector.parseMoov(moovPayload());
    expect(f.width, 3840);
    expect(f.height, 2160);
    expect(f.durationMs, 10000);
    expect(f.frameCount, 300);
    expect(f.fps, closeTo(30.0, 1e-9));
    expect(f.videoCodec, 'H.264');
    expect(f.audioCodec, 'AAC');
    expect(f.rotation, 0);
    expect(f.displayWidth, 3840);
  });

  test('detects 90° rotation and swaps display size', () {
    final f = Mp4Inspector.parseMoov(moovPayload(a: 0, b: 65536));
    expect(f.rotation, 90);
    expect(f.displayWidth, 2160);
    expect(f.displayHeight, 3840);
  });

  test('inspectFile finds moov after mdat (Android MediaMuxer layout)', () async {
    final dir = await Directory.systemTemp.createTemp('kp_mp4');
    final file = File('${dir.path}/t.mp4');
    final ftyp = box('ftyp', [...'isom'.codeUnits, ..._u32(512), ...'isomavc1'.codeUnits]);
    final mdat = box('mdat', _zeros(4096));
    final moov = box('moov', moovPayload());
    await file.writeAsBytes([...ftyp, ...mdat, ...moov]);
    final f = await Mp4Inspector.inspectFile(file.path);
    expect(f, isNotNull);
    expect(f!.width, 3840);
    expect(f.fps, closeTo(30, 1e-9));
    await dir.delete(recursive: true);
  });

  test('file without moov (unfinished recording) → null', () async {
    final dir = await Directory.systemTemp.createTemp('kp_mp4');
    final file = File('${dir.path}/broken.mp4');
    await file.writeAsBytes([...box('ftyp', 'isom'.codeUnits), ...box('mdat', _zeros(100))]);
    expect(await Mp4Inspector.inspectFile(file.path), isNull);
    await dir.delete(recursive: true);
  });

  test('truncated garbage does not throw', () {
    final f = Mp4Inspector.parseMoov(Uint8List.fromList([0, 0, 0, 50, 116, 114, 97, 107, 1, 2]));
    expect(f.width, isNull);
  });

  test('MediaFacts json round-trip', () {
    final f = Mp4Inspector.parseMoov(moovPayload());
    final g = MediaFacts.fromJson(f.toJson());
    expect(g.width, f.width);
    expect(g.fps, f.fps);
    expect(g.videoCodec, f.videoCodec);
    expect(g.durationMs, f.durationMs);
  });
}
