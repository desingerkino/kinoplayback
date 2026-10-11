import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinoplayback/core/layout/adaptive.dart';
import 'package:kinoplayback/core/storage_info.dart';
import 'package:kinoplayback/monitor/analysis.dart';
import 'package:kinoplayback/network/net_utils.dart';
import 'package:kinoplayback/network/stream_stats.dart';

void main() {
  group('connect input / QR', () {
    test('QR uri round-trip', () {
      final uri = buildConnectUri(host: '192.168.1.112', port: 5555, name: 'iPhone (Актёр)');
      final t = parseConnectInput(uri)!;
      expect(t.host, '192.168.1.112');
      expect(t.port, 5555);
      expect(t.name, 'iPhone (Актёр)');
    });

    test('manual ip with and without port', () {
      expect(parseConnectInput('10.0.0.7')!.port, 47800);
      final t = parseConnectInput(' 10.0.0.7:12345 ')!;
      expect(t.host, '10.0.0.7');
      expect(t.port, 12345);
      expect(parseConnectInput('kino.local:47800')!.host, 'kino.local');
    });

    for (final bad in ['', '300.1.1.1', '10.0.0.1:99999', 'http://x', 'kinoplayback://connect?h=1.2.3.4', 'a b']) {
      test('rejects "$bad"', () => expect(parseConnectInput(bad), isNull));
    }

    test('private ranges', () {
      expect(isPrivateIPv4('192.168.0.5'), isTrue);
      expect(isPrivateIPv4('172.20.1.1'), isTrue);
      expect(isPrivateIPv4('10.1.2.3'), isTrue);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
      expect(isPrivateIPv4('172.32.0.1'), isFalse);
    });
  });

  group('videoRectIn', () {
    test('contain letterboxes a 16:9 picture on a 4:3 box', () {
      final r = videoRectIn(const Size(400, 300), 16 / 9);
      expect(r.width, 400);
      expect(r.height, closeTo(225, 1e-9));
      expect(r.top, closeTo(37.5, 1e-9));
    });

    test('cover crops', () {
      final r = videoRectIn(const Size(400, 300), 16 / 9, cover: true);
      expect(r.height, 300);
      expect(r.width, closeTo(533.33, 0.01));
      expect(r.left, lessThan(0));
    });

    test('form factor from size only', () {
      expect(formFactorOf(const Size(390, 844)), KpFormFactor.phonePortrait);
      expect(formFactorOf(const Size(844, 390)), KpFormFactor.phoneLandscape);
      expect(formFactorOf(const Size(820, 1180)), KpFormFactor.tabletPortrait);
      expect(formFactorOf(const Size(1180, 820)), KpFormFactor.tabletLandscape);
    });
  });

  group('stats parsing', () {
    RawStat r(String id, String type, double ts, Map<String, dynamic> v) => RawStat(id, type, ts, v);

    test('inbound: dims, fps, codec, bitrate, loss, rtt (numbers or strings)', () {
      final first = [
        r('IT01V', 'inbound-rtp', 1000, {
          'kind': 'video',
          'frameWidth': 1920,
          'frameHeight': '1080',
          'framesPerSecond': 30,
          'bytesReceived': 1000000,
          'packetsLost': 0,
          'packetsReceived': 1000,
          'codecId': 'C1',
          'jitter': 0.004,
        }),
        r('C1', 'codec', 1000, {'mimeType': 'video/H264'}),
        r('P1', 'candidate-pair', 1000, {'state': 'succeeded', 'nominated': true, 'currentRoundTripTime': 0.012, 'localCandidateId': 'L1'}),
        r('L1', 'local-candidate', 1000, {'candidateType': 'host', 'networkType': 'wifi'}),
        r('IT01A', 'inbound-rtp', 1000, {'kind': 'audio', 'audioLevel': 0.25}),
      ];
      final (s1, c1) = parseInboundStats(first, null);
      expect(s1.width, 1920);
      expect(s1.height, 1080);
      expect(s1.fps, 30);
      expect(s1.videoCodec, 'H264');
      expect(s1.rttMs, closeTo(12, 1e-9));
      expect(s1.jitterMs, closeTo(4, 1e-9));
      expect(s1.audioLevel, 0.25);
      expect(s1.candidateType, 'host');
      expect(s1.networkType, 'wifi');
      expect(s1.bitrateKbps, isNull, reason: 'no previous sample yet');

      final second = [
        r('IT01V', 'inbound-rtp', 2000, {
          'kind': 'video',
          'bytesReceived': 2000000, // +1 MB in 1 s = 8000 kbit/s
          'packetsLost': 10,
          'packetsReceived': 1990, // +990 received, +10 lost
        }),
      ];
      final (s2, _) = parseInboundStats(second, c1);
      expect(s2.bitrateKbps, closeTo(8000, 1e-6));
      expect(s2.lossPercent, closeTo(1.0, 1e-9));
      expect(s2.quality, 3);
    });

    test('missing metrics stay null (no invented values)', () {
      final (s, _) = parseInboundStats([], null);
      expect(s.fps, isNull);
      expect(s.rttMs, isNull);
      expect(s.quality, isNull);
    });

    test('outbound: source vs sent size', () {
      final (s, _) = parseOutboundStats([
        RawStat('O', 'outbound-rtp', 1, {'kind': 'video', 'frameWidth': 1920, 'frameHeight': 1080, 'framesPerSecond': 30, 'qualityLimitationReason': 'bandwidth'}),
        RawStat('S', 'media-source', 1, {'kind': 'video', 'width': 3840, 'height': 2160, 'framesPerSecond': 29.97}),
      ], null);
      expect(s.width, 1920);
      expect(s.sourceWidth, 3840);
      expect(s.sourceFps, closeTo(29.97, 1e-9));
      expect(s.qualityLimitation, 'bandwidth');
    });

    test('labels', () {
      expect(resLabel(3840, 2160), '4K');
      expect(resLabel(1080, 1920), '1080p');
      expect(fmtFps(29.97), '29.97');
      expect(fmtFps(30.01), '30');
      expect(fmtKbps(8000), '8.0 Mbps');
    });
  });

  group('frame analysis', () {
    Uint8List px(List<List<int>> rgb) =>
        Uint8List.fromList([for (final p in rgb) ...[p[0], p[1], p[2], 255]]);

    test('luma and histogram', () {
      expect(luma709(255, 255, 255), 255);
      expect(luma709(0, 0, 0), 0);
      final h = lumaHistogram(px([[0, 0, 0], [255, 255, 255], [255, 255, 255]]), bins: 4);
      expect(h, [1, 0, 0, 2]);
      expect(clippedFraction(h, fromBin: 3), closeTo(2 / 3, 1e-9));
    });

    test('zebra marks only bright pixels', () {
      final rgba = px([[255, 255, 255], [10, 10, 10]]);
      final z = zebraOverlay(rgba, 2, 1);
      expect(z[3], greaterThan(0)); // pixel 0 (x+y=0 → stripe on)
      expect(z[7], 0); // dark pixel untouched
    });

    test('false colour maps black to purple and white to red', () {
      final f = falseColorImage(px([[0, 0, 0], [255, 255, 255]]));
      expect([f[0], f[1], f[2]], [92, 0, 160]);
      expect([f[4], f[5], f[6]], [230, 0, 0]);
    });
  });

  test('free space via libc on the CI host', () {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final b = freeBytesAt(Directory.systemTemp.path);
    expect(b, isNotNull);
    expect(b!, greaterThan(0));
    expect(formatBytes(12 * 1000 * 1000 * 1000), '12.0 GB');
  });
}
