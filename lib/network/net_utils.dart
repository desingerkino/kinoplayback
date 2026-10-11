import 'dart:io';

/// Best guess of this device's LAN IPv4 address (Wi-Fi first).
Future<String?> localLanIPv4() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    String? fallback;
    for (final i in ifaces) {
      final n = i.name.toLowerCase();
      for (final a in i.addresses) {
        if (!isPrivateIPv4(a.address)) continue;
        if (n.startsWith('en') || n.startsWith('wlan') || n.startsWith('wl') || n.startsWith('eth') || n.startsWith('ap')) {
          return a.address;
        }
        fallback ??= a.address;
      }
    }
    return fallback;
  } catch (_) {
    return null;
  }
}

bool isPrivateIPv4(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((e) => e == null || e < 0 || e > 255)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

/// Connection target parsed from manual input or a QR code.
class ConnectTarget {
  const ConnectTarget(this.host, this.port, {this.name});
  final String host;
  final int port;
  final String? name;

  @override
  String toString() => '$host:$port';
}

/// QR payload: `kinoplayback://connect?h=192.168.1.112&p=47800&n=iPhone&v=1`
/// It only says *where* to connect. Approval still happens on the CAMERA.
String buildConnectUri({required String host, required int port, required String name}) {
  return Uri(
    scheme: 'kinoplayback',
    host: 'connect',
    queryParameters: {'h': host, 'p': '$port', 'n': name, 'v': '1'},
  ).toString();
}

ConnectTarget? parseConnectInput(String raw, {int defaultPort = 47800}) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('kinoplayback://')) {
    final u = Uri.tryParse(s);
    if (u == null || u.host != 'connect') return null;
    final h = u.queryParameters['h'];
    final p = int.tryParse(u.queryParameters['p'] ?? '');
    if (h == null || !_validHost(h) || p == null || p <= 0 || p > 65535) return null;
    return ConnectTarget(h, p, name: u.queryParameters['n']);
  }
  // "192.168.1.5" or "192.168.1.5:47800"
  final m = RegExp(r'^([0-9a-zA-Z.\-]+)(?::(\d{1,5}))?$').firstMatch(s);
  if (m == null) return null;
  final host = m.group(1)!;
  if (!_validHost(host)) return null;
  final port = m.group(2) == null ? defaultPort : int.parse(m.group(2)!);
  if (port <= 0 || port > 65535) return null;
  return ConnectTarget(host, port);
}

bool _validHost(String h) {
  if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(h)) {
    return h.split('.').every((e) => (int.tryParse(e) ?? 999) <= 255);
  }
  return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-.]*[a-zA-Z0-9])?$').hasMatch(h);
}
