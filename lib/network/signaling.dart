import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/event_log.dart';
import '../protocol/messages.dart';

/// One WebSocket link (either side). Malformed frames are logged and dropped.
class SignalingLink {
  SignalingLink(this._ws, this.remoteAddress) {
    _ws.pingInterval = const Duration(seconds: 2);
    _sub = _ws.listen(
      (data) {
        if (data is! String) return;
        try {
          _ctrl.add(KpMessage.decode(data));
        } on FormatException catch (e) {
          logW('sig', 'drop malformed from $remoteAddress: ${e.message}');
        }
      },
      onDone: _closed,
      onError: (Object e) {
        logW('sig', 'socket error $remoteAddress: $e');
        _closed();
      },
      cancelOnError: true,
    );
  }

  final WebSocket _ws;
  final String remoteAddress;
  late final StreamSubscription<dynamic> _sub;
  final _ctrl = StreamController<KpMessage>.broadcast();
  final _done = Completer<void>();
  bool _isClosed = false;

  Stream<KpMessage> get messages => _ctrl.stream;
  Future<void> get done => _done.future;
  bool get isClosed => _isClosed;

  void send(KpMessage m) {
    if (_isClosed) throw StateError('signaling closed');
    _ws.add(m.encode());
  }

  void _closed() {
    if (_isClosed) return;
    _isClosed = true;
    if (!_done.isCompleted) _done.complete();
    _ctrl.close();
  }

  Future<void> close([String reason = 'bye']) async {
    if (_isClosed) return;
    try {
      await _ws.close(WebSocketStatus.normalClosure, reason);
    } catch (_) {}
    await _sub.cancel();
    _closed();
  }

  static Future<SignalingLink> connect(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    final uri = 'ws://$host:$port$kWsPath';
    final ws = await WebSocket.connect(uri).timeout(timeout);
    return SignalingLink(ws, '$host:$port');
  }
}

/// CAMERA-side server: WebSocket signaling at /kp and a tiny JSON /info
/// endpoint used to validate manual IP connections.
class SignalingServer {
  SignalingServer({required this.onLink, required this.info});

  final void Function(SignalingLink link) onLink;
  final Map<String, dynamic> Function() info;
  HttpServer? _server;
  int? get port => _server?.port;
  bool get running => _server != null;

  Future<int> start(int preferredPort) async {
    if (_server != null) return _server!.port;
    HttpServer s;
    try {
      s = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort, shared: false);
    } on SocketException {
      s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      logW('sig', 'port $preferredPort busy, using ${s.port}');
    }
    _server = s;
    s.listen(_handle, onError: (Object e) => logE('sig', 'server error: $e'));
    logI('sig', 'listening on :${s.port}');
    return s.port;
  }

  Future<void> _handle(HttpRequest req) async {
    final remote = '${req.connectionInfo?.remoteAddress.address}:${req.connectionInfo?.remotePort}';
    try {
      if (req.uri.path == kWsPath && WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        onLink(SignalingLink(ws, remote));
        return;
      }
      if (req.uri.path == '/info' && req.method == 'GET') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(info()));
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      logW('sig', 'request from $remote failed: $e');
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }
}
