import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/theme/kp_theme.dart';
import '../core/widgets/kp_widgets.dart';
import '../network/discovery.dart';
import '../network/net_utils.dart';
import 'playback_screen.dart';
import 'qr_scan_screen.dart';

/// Camera search (reference screen 2): Bonjour/NSD list, recent devices,
/// QR and manual IP.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final CameraBrowser _browser = CameraBrowser();

  @override
  void initState() {
    super.initState();
    unawaited(_browser.start());
  }

  @override
  void dispose() {
    _browser.dispose();
    super.dispose();
  }

  void _open(ConnectTarget t) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaybackScreen(target: t)));
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (raw == null || !mounted) return;
    final t = parseConnectInput(raw);
    if (t == null) {
      showKpToast(context, 'Это не QR-код KINO PLAYBACK', color: KpColors.warn);
      return;
    }
    _open(t);
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    String? error;
    bool checking = false;
    final target = await showDialog<ConnectTarget>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> submit() async {
            final t = parseConnectInput(ctrl.text);
            if (t == null) {
              setLocal(() => error = 'Формат: 192.168.1.20 или 192.168.1.20:47800');
              return;
            }
            setLocal(() {
              checking = true;
              error = null;
            });
            final probe = await _probe(t);
            if (!context.mounted) return;
            if (probe != null) {
              setLocal(() {
                checking = false;
                error = probe;
              });
              return;
            }
            Navigator.pop(context, t);
          }

          return AlertDialog(
            title: const Text('Подключиться по IP-адресу'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: KpText.metric,
                  decoration: InputDecoration(hintText: '192.168.1.20:47800', errorText: error),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 8),
                Text('Адрес показан на камере: ⋯ → Подключение и QR.', style: KpText.caption),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              TextButton(
                onPressed: checking ? null : submit,
                child: checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Подключиться'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (target != null) _open(target);
  }

  /// Checks that a KINO PLAYBACK camera answers at the address. Returns an
  /// error text, or null if OK.
  Future<String?> _probe(ConnectTarget t) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.get(t.host, t.port, '/info').timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      if (j is Map && j['app'] == 'kinoplayback') return null;
      return 'По этому адресу отвечает не KINO PLAYBACK';
    } on TimeoutException {
      return 'Нет ответа. Проверьте адрес и что оба устройства в одной сети.';
    } catch (e) {
      return 'Не удалось подключиться: ${e is SocketException ? e.message : e}';
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final ff = formFactorOfContext(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Доступные камеры'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Обновить поиск', onPressed: _browser.restart),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_browser, settings]),
          builder: (context, _) {
            final found = _browser.cameras;
            final list = ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Row(children: [
                  KpStatusDot(color: _browser.searching ? KpColors.live : KpColors.inactive, pulse: _browser.searching),
                  const SizedBox(width: 8),
                  Text(
                    _browser.searching ? 'Поиск в локальной сети · найдено: ${found.length}' : 'Поиск остановлен',
                    style: KpText.caption,
                  ),
                ]),
                const SizedBox(height: 12),
                if (_browser.error != null) ...[KpBanner(text: _browser.error!), const SizedBox(height: 12)],
                if (found.isEmpty)
                  KpPanel(
                    child: Column(children: [
                      const SizedBox(height: 8),
                      const Icon(Icons.wifi_find, size: 32, color: KpColors.textMute),
                      const SizedBox(height: 8),
                      Text('Камеры не найдены', style: KpText.heading),
                      const SizedBox(height: 4),
                      Text(
                        'Запустите KINO PLAYBACK в режиме CAMERA на другом устройстве в той же Wi-Fi-сети. '
                        'Если роутер блокирует поиск (гостевая сеть, изоляция клиентов) — используйте QR-код или IP-адрес.',
                        textAlign: TextAlign.center,
                        style: KpText.caption,
                      ),
                      const SizedBox(height: 8),
                    ]),
                  )
                else
                  KpSection(
                    children: [
                      for (final cam in found)
                        _DeviceRow(
                          name: cam.displayName,
                          detail: [
                            'CAMERA',
                            if (cam.platform != null) cam.platform!,
                            if (cam.model != null) cam.model!,
                          ].join(' · '),
                          address: cam.key,
                          online: true,
                          onTap: () => _open(ConnectTarget(cam.host, cam.port, name: cam.displayName)),
                        ),
                    ],
                  ),
                if (settings.recent.isNotEmpty)
                  KpSection(
                    title: 'Недавние',
                    children: [
                      for (final r in settings.recent)
                        _DeviceRow(
                          name: r.name,
                          detail: [if (r.platform != null && r.platform!.isNotEmpty) r.platform!, _ago(r.lastUsed)].join(' · '),
                          address: '${r.host}:${r.port}',
                          online: found.any((f) => f.host == r.host && f.port == r.port),
                          onTap: () => _open(ConnectTarget(r.host, r.port, name: r.name)),
                        ),
                    ],
                  ),
              ],
            );
            final actions = Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Expanded(child: KpButton(label: 'Сканировать QR-код', icon: Icons.qr_code_scanner, onPressed: _scan, expand: true)),
                const SizedBox(width: 12),
                Expanded(child: KpButton(label: 'По IP-адресу', icon: Icons.lan_outlined, onPressed: _manual, expand: true)),
              ]),
            );
            if (ff.isLandscape) {
              return Row(children: [
                Expanded(flex: 3, child: list),
                SizedBox(
                  width: ff.isTablet ? 320 : 260,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(KpSpace.l),
                        child: KpButton(label: 'Сканировать QR-код', icon: Icons.qr_code_scanner, onPressed: _scan, expand: true),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: KpSpace.l),
                        child: KpButton(label: 'По IP-адресу', icon: Icons.lan_outlined, onPressed: _manual, expand: true),
                      ),
                    ],
                  ),
                ),
              ]);
            }
            return Column(children: [Expanded(child: list), actions]);
          },
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'только что';
    if (d.inHours < 1) return '${d.inMinutes} мин назад';
    if (d.inDays < 1) return '${d.inHours} ч назад';
    return '${d.inDays} дн назад';
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.detail,
    required this.address,
    required this.online,
    required this.onTap,
  });

  final String name;
  final String detail;
  final String address;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KpRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KpColors.surface3,
          borderRadius: BorderRadius.circular(KpRadius.s),
        ),
        child: const Icon(Icons.videocam_outlined, color: KpColors.text, size: 22),
      ),
      label: name,
      subtitle: '$detail\n$address',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        KpStatusDot(color: online ? KpColors.live : KpColors.inactive),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right, size: 18, color: KpColors.textMute),
      ]),
      onTap: onTap,
    );
  }
}
