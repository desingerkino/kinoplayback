/// Parsed WebRTC statistics. Every field is nullable: if the platform does
/// not report a metric, the UI shows "—" instead of an invented value.
class StreamStats {
  const StreamStats({
    this.width,
    this.height,
    this.fps,
    this.bitrateKbps,
    this.packetsLost,
    this.lossPercent,
    this.jitterMs,
    this.rttMs,
    this.audioLevel,
    this.videoCodec,
    this.framesDropped,
    this.candidateType,
    this.networkType,
    this.qualityLimitation,
    this.sourceWidth,
    this.sourceHeight,
    this.sourceFps,
    this.at,
  });

  final int? width;
  final int? height;
  final double? fps;
  final double? bitrateKbps;
  final int? packetsLost;
  final double? lossPercent;
  final double? jitterMs;
  final double? rttMs; // ICE candidate-pair round trip (network only)
  final double? audioLevel; // 0..1
  final String? videoCodec;
  final int? framesDropped;
  final String? candidateType; // host | srflx | relay
  final String? networkType; // wifi | ethernet | cellular …
  final String? qualityLimitation; // sender: none | bandwidth | cpu
  final int? sourceWidth; // sender: capture (media-source)
  final int? sourceHeight;
  final double? sourceFps;
  final DateTime? at;

  /// Rough 0..4 link quality from loss and RTT; null if neither is known.
  int? get quality {
    if (lossPercent == null && rttMs == null) return null;
    var q = 4;
    final l = lossPercent ?? 0;
    final r = rttMs ?? 0;
    if (l > 0.5 || r > 60) q = 3;
    if (l > 2 || r > 150) q = 2;
    if (l > 8 || r > 400) q = 1;
    return q;
  }
}

/// Counters from the previous sample, used to derive rates.
class StatsCounters {
  StatsCounters({this.bytes, this.timestampMs, this.packetsLost, this.packetsTotal});
  final int? bytes;
  final double? timestampMs;
  final int? packetsLost;
  final int? packetsTotal;
}

num? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

String? _str(Object? v) => v?.toString();

/// One stats report in a platform-neutral shape.
class RawStat {
  RawStat(this.id, this.type, this.timestampMs, this.values);
  final String id;
  final String type;
  final double timestampMs;
  final Map<dynamic, dynamic> values;
}

/// Parses the receiving side (PLAYBACK). Returns the stats and the counters
/// to pass into the next call.
(StreamStats, StatsCounters) parseInboundStats(List<RawStat> reports, StatsCounters? prev) {
  RawStat? video;
  RawStat? audio;
  final codecs = <String, RawStat>{};
  final candidates = <String, RawStat>{};
  RawStat? pair;
  for (final r in reports) {
    switch (r.type) {
      case 'inbound-rtp':
        final kind = _str(r.values['kind'] ?? r.values['mediaType']);
        if (kind == 'video') video ??= r;
        if (kind == 'audio') audio ??= r;
      case 'codec':
        codecs[r.id] = r;
      case 'local-candidate':
        candidates[r.id] = r;
      case 'candidate-pair':
        final st = _str(r.values['state']);
        final nominated = r.values['nominated'] == true || _str(r.values['nominated']) == 'true';
        if (st == 'succeeded' && (nominated || pair == null)) pair = r;
    }
  }

  int? width, height, lost, framesDropped, bytes, received;
  double? fps, kbps, lossPct, jitter, rtt, level;
  String? codec, candType, netType;
  double? ts;

  if (video != null) {
    final v = video.values;
    width = _num(v['frameWidth'])?.toInt();
    height = _num(v['frameHeight'])?.toInt();
    fps = _num(v['framesPerSecond'])?.toDouble();
    lost = _num(v['packetsLost'])?.toInt();
    received = _num(v['packetsReceived'])?.toInt();
    framesDropped = _num(v['framesDropped'])?.toInt();
    jitter = _num(v['jitter'])?.toDouble();
    if (jitter != null) jitter *= 1000;
    bytes = _num(v['bytesReceived'])?.toInt();
    ts = video.timestampMs;
    final cid = _str(v['codecId']);
    if (cid != null && codecs[cid] != null) {
      final mime = _str(codecs[cid]!.values['mimeType']);
      if (mime != null) codec = mime.split('/').last.toUpperCase();
    }
  }
  if (audio != null) {
    level = _num(audio.values['audioLevel'])?.toDouble();
  }
  if (pair != null) {
    final r = _num(pair.values['currentRoundTripTime'])?.toDouble();
    if (r != null) rtt = r * 1000;
    final lc = _str(pair.values['localCandidateId']);
    if (lc != null && candidates[lc] != null) {
      candType = _str(candidates[lc]!.values['candidateType']);
      netType = _str(candidates[lc]!.values['networkType']);
    }
  }

  if (bytes != null && ts != null && prev?.bytes != null && prev?.timestampMs != null) {
    final dt = ts - prev!.timestampMs!;
    // Some platforms report timestamps in µs; normalise to a sane window.
    final dtMs = dt > 100000 ? dt / 1000 : dt;
    if (dtMs > 0 && bytes >= prev.bytes!) {
      kbps = (bytes - prev.bytes!) * 8 / dtMs; // bytes*8 / ms = kbit/s
    }
  }
  if (lost != null && received != null && prev?.packetsLost != null && prev?.packetsTotal != null) {
    final dLost = lost - prev!.packetsLost!;
    final dTotal = (lost + received) - prev.packetsTotal!;
    if (dTotal > 0 && dLost >= 0) lossPct = dLost * 100 / dTotal;
  }

  return (
    StreamStats(
      width: width,
      height: height,
      fps: fps,
      bitrateKbps: kbps,
      packetsLost: lost,
      lossPercent: lossPct,
      jitterMs: jitter,
      rttMs: rtt,
      audioLevel: level,
      videoCodec: codec,
      framesDropped: framesDropped,
      candidateType: candType,
      networkType: netType,
      at: DateTime.now(),
    ),
    StatsCounters(
      bytes: bytes,
      timestampMs: ts,
      packetsLost: lost,
      packetsTotal: (lost != null && received != null) ? lost + received : null,
    ),
  );
}

/// Parses the sending side (CAMERA).
(StreamStats, StatsCounters) parseOutboundStats(List<RawStat> reports, StatsCounters? prev) {
  RawStat? out;
  RawStat? source;
  RawStat? audioSource;
  RawStat? pair;
  final codecs = <String, RawStat>{};
  final candidates = <String, RawStat>{};
  for (final r in reports) {
    final kind = _str(r.values['kind'] ?? r.values['mediaType']);
    switch (r.type) {
      case 'outbound-rtp':
        if (kind == 'video') out ??= r;
      case 'media-source':
        if (kind == 'video') source ??= r;
        if (kind == 'audio') audioSource ??= r;
      case 'codec':
        codecs[r.id] = r;
      case 'local-candidate':
        candidates[r.id] = r;
      case 'candidate-pair':
        final st = _str(r.values['state']);
        final nominated = r.values['nominated'] == true || _str(r.values['nominated']) == 'true';
        if (st == 'succeeded' && (nominated || pair == null)) pair = r;
    }
  }
  int? w, h, sw, sh, bytes;
  double? fps, sfps, kbps, rtt, level, ts;
  String? codec, ql, candType, netType;
  if (out != null) {
    final v = out.values;
    w = _num(v['frameWidth'])?.toInt();
    h = _num(v['frameHeight'])?.toInt();
    fps = _num(v['framesPerSecond'])?.toDouble();
    bytes = _num(v['bytesSent'])?.toInt();
    ql = _str(v['qualityLimitationReason']);
    ts = out.timestampMs;
    final cid = _str(v['codecId']);
    if (cid != null && codecs[cid] != null) {
      final mime = _str(codecs[cid]!.values['mimeType']);
      if (mime != null) codec = mime.split('/').last.toUpperCase();
    }
  }
  if (source != null) {
    sw = _num(source.values['width'])?.toInt();
    sh = _num(source.values['height'])?.toInt();
    sfps = _num(source.values['framesPerSecond'])?.toDouble();
  }
  if (audioSource != null) level = _num(audioSource.values['audioLevel'])?.toDouble();
  if (pair != null) {
    final r = _num(pair.values['currentRoundTripTime'])?.toDouble();
    if (r != null) rtt = r * 1000;
    final lc = _str(pair.values['localCandidateId']);
    if (lc != null && candidates[lc] != null) {
      candType = _str(candidates[lc]!.values['candidateType']);
      netType = _str(candidates[lc]!.values['networkType']);
    }
  }
  if (bytes != null && ts != null && prev?.bytes != null && prev?.timestampMs != null) {
    final dt = ts - prev!.timestampMs!;
    final dtMs = dt > 100000 ? dt / 1000 : dt;
    if (dtMs > 0 && bytes >= prev.bytes!) kbps = (bytes - prev.bytes!) * 8 / dtMs;
  }
  return (
    StreamStats(
      width: w,
      height: h,
      fps: fps,
      bitrateKbps: kbps,
      rttMs: rtt,
      audioLevel: level,
      videoCodec: codec,
      qualityLimitation: ql,
      sourceWidth: sw,
      sourceHeight: sh,
      sourceFps: sfps,
      candidateType: candType,
      networkType: netType,
      at: DateTime.now(),
    ),
    StatsCounters(bytes: bytes, timestampMs: ts),
  );
}

String fmtRes(int? w, int? h) => (w == null || h == null) ? '—' : '$w×$h';

String fmtFps(double? fps) {
  if (fps == null) return '—';
  if ((fps - fps.roundToDouble()).abs() < 0.05) return fps.round().toString();
  return fps.toStringAsFixed(2);
}

String fmtKbps(double? kbps) {
  if (kbps == null) return '—';
  if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
  return '${kbps.round()} kbps';
}

/// Short label like "4K", "1080p", "720p" from real dimensions.
String resLabel(int? w, int? h) {
  if (w == null || h == null) return '—';
  final short = w < h ? w : h;
  final long = w < h ? h : w;
  if (long >= 3800) return '4K';
  if (long >= 2500) return '${short}p';
  return '${short}p';
}
