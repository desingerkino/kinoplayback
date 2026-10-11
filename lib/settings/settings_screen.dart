import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../network/stream_stats.dart';
import 'app_settings.dart';

enum _Sec { video, audio, connection, ui, storage, about }

extension on _Sec {
  String get title => switch (this) {
        _Sec.video => 'Видео',
        _Sec.audio => 'Аудио',
        _Sec.connection => 'Соединение',
        _Sec.ui => 'Интерфейс',
        _Sec.storage => 'Хранилище',
        _Sec.about => 'О приложении',
      };
  IconData get icon => switch (this) {
        _Sec.video => Icons.videocam_outlined,
        _Sec.audio => Icons.graphic_eq,
        _Sec.connection => Icons.lan_outlined,
        _Sec.ui => Icons.tune,
        _Sec.storage => Icons.sd_storage_outlined,
        _Sec.about => Icons.info_outline,
      };
}

/// App settings (reference screen 10): two-pane on wide screens, list →
/// detail on phones in portrait.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Sec _sel = _Sec.video;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final wide = MediaQuery.sizeOf(context).width >= 640 || formFactorOfContext(context).isLandscape;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  KpSection(children: [
                    for (final s in _Sec.values)
                      KpRow(
                        leading: Icon(s.icon, size: 20, color: KpColors.textDim),
                        label: s.title,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(s.title)),
                            body: SafeArea(child: _SectionBody(section: s)),
                          ),
                        )),
                      ),
                  ]),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: 220,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final s in _Sec.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: _sel == s ? KpColors.surface3 : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: ListTile(
                              dense: true,
                              leading: Icon(s.icon, size: 20, color: _sel == s ? KpColors.text : KpColors.textDim),
                              title: Text(s.title, style: KpText.body),
                              onTap: () => setState(() => _sel = s),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _SectionBody(section: _sel)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.section});
  final _Sec section;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final List<Widget> children = switch (section) {
          _Sec.video => [
              KpSection(
                title: 'Оригинал (CAMERA)',
                footer: 'Это запрос к камере. Фактический формат показывается в режиме CAMERA и в параметрах каждого дубля.',
                children: [
                  for (final p in CapturePreset.all)
                    KpRow(
                      label: p.label,
                      trailing: p.id == s.capturePresetId ? const Icon(Icons.check, color: KpColors.live, size: 18) : null,
                      onTap: () => s.update((x) => x.capturePresetId = p.id),
                    ),
                ],
              ),
              KpSection(
                title: 'Трансляция',
                footer: 'Независимо от оригинала. WebRTC адаптирует битрейт к сети ниже заданного предела.',
                children: [
                  _choice(context, 'Разрешение', '≤ ${s.stream.height}p', StreamQuality.heights, s.stream.height, (v) => '${v}p',
                      (v) => s.update((x) => x.stream = StreamQuality(v, x.stream.fps, x.stream.maxKbps))),
                  _choice(context, 'FPS', '≤ ${s.stream.fps}', StreamQuality.fpsOptions, s.stream.fps, (v) => '$v к/с',
                      (v) => s.update((x) => x.stream = StreamQuality(x.stream.height, v, x.stream.maxKbps))),
                  _choice(context, 'Битрейт', fmtKbps(s.stream.maxKbps.toDouble()), StreamQuality.bitrates, s.stream.maxKbps,
                      (v) => fmtKbps(v.toDouble()), (v) => s.update((x) => x.stream = StreamQuality(x.stream.height, x.stream.fps, v))),
                ],
              ),
            ],
          _Sec.audio => [
              KpSection(
                footer: 'Звук захватывается в CAMERA, записывается в оригинал и передаётся на монитор. '
                    'Многоканальная запись не поддерживается.',
                children: [
                  KpSwitchRow(label: 'Звук в CAMERA', value: s.audioEnabled, onChanged: (v) => s.update((x) => x.audioEnabled = v)),
                ],
              ),
            ],
          _Sec.connection => [
              KpSection(
                title: 'Это устройство',
                children: [
                  KpRow(label: 'Имя в сети', value: s.deviceName, onTap: () => _rename(context, s)),
                  KpRow(label: 'Порт CAMERA', value: '${s.port}', onTap: () => _port(context, s)),
                ],
              ),
              KpSection(
                title: 'Удалённое управление',
                footer: 'Когда включено, подтверждённые мониторы могут запускать и останавливать запись в режиме CAMERA.',
                children: [
                  KpSwitchRow(
                    label: 'Разрешить управление записью',
                    value: s.remoteControlAllowed,
                    onChanged: (v) => s.update((x) => x.remoteControlAllowed = v),
                  ),
                ],
              ),
              KpSection(
                title: 'Безопасность',
                footer: 'Видео, звук и команды идут напрямую между устройствами по Wi-Fi и шифруются WebRTC (DTLS-SRTP). '
                    'Обмен параметрами соединения (сигнализация) по локальной сети не шифруется; '
                    'новое устройство всегда подтверждается на камере. Облако и интернет не используются.',
                children: [
                  KpRow(label: 'Доверенные мониторы', value: '${s.trusted.length}'),
                  if (s.trusted.isNotEmpty)
                    KpRow(
                      label: 'Сбросить доверие',
                      valueColor: KpColors.rec,
                      onTap: () => s.update((x) => x.trusted = {}),
                    ),
                  KpRow(
                    label: 'Очистить недавние',
                    onTap: s.recent.isEmpty ? null : () => s.update((x) => x.recent = []),
                  ),
                ],
              ),
            ],
          _Sec.ui => [
              KpSection(children: [
                KpSwitchRow(
                  label: 'Не гасить экран',
                  subtitle: 'В режимах CAMERA и PLAYBACK',
                  value: s.keepScreenOn,
                  onChanged: (v) => s.update((x) => x.keepScreenOn = v),
                ),
                KpSwitchRow(label: 'Сетка третей', value: s.toolGrid, onChanged: (v) => s.update((x) => x.toolGrid = v)),
                KpSwitchRow(label: 'Центральный крест', value: s.toolCross, onChanged: (v) => s.update((x) => x.toolCross = v)),
                KpSwitchRow(label: 'Безопасные зоны', value: s.toolSafe, onChanged: (v) => s.update((x) => x.toolSafe = v)),
              ]),
            ],
          _Sec.storage => [
              KpSection(
                children: [
                  KpRow(label: 'Свободно', value: formatBytes(freeBytesAt(app.takes.dir.path))),
                  KpRow(label: 'Дублей в приложении', value: '${app.takes.takes.length}'),
                  KpSwitchRow(
                    label: 'Сохранять в Фото / Галерею',
                    value: s.autoSaveToGallery,
                    onChanged: (v) => s.update((x) => x.autoSaveToGallery = v),
                  ),
                  KpRow(label: 'Ролик (reel)', value: s.reel, onTap: () => _reel(context, s)),
                  KpRow(label: 'Следующий дубль', value: 'C${s.nextClip.toString().padLeft(3, '0')}'),
                  KpRow(label: 'Сбросить нумерацию', onTap: () => s.update((x) => x.nextClip = 1)),
                ],
                footer: 'Файлы лежат в папке приложения (на iOS видны в «Файлах») и копируются в медиатеку.',
              ),
            ],
          _Sec.about => [
              KpSection(children: [
                KpRow(label: 'KINO PLAYBACK', value: app.identity.appVersion),
                KpRow(label: 'Устройство', value: '${app.identity.model} · ${app.identity.platform} ${app.identity.osVersion}'),
                KpRow(
                  label: 'Диагностика',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsScreen())),
                ),
              ]),
              Text('Шрифт Inter — SIL Open Font License 1.1.', style: KpText.caption),
            ],
        };
        return ListView(padding: const EdgeInsets.all(16), children: children);
      },
    );
  }

  Widget _choice(BuildContext context, String label, String value, List<int> values, int current, String Function(int) fmt,
      void Function(int) onPick) {
    return KpRow(
      label: label,
      value: value,
      onTap: () async {
        final v = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              for (final x in values)
                ListTile(
                  title: Text(fmt(x)),
                  trailing: x == current ? const Icon(Icons.check, color: KpColors.live) : null,
                  onTap: () => Navigator.pop(context, x),
                ),
            ]),
          ),
        );
        if (v != null) onPick(v);
      },
    );
  }

  Future<void> _rename(BuildContext context, AppSettings s) async {
    final v = await _textDialog(context, 'Имя устройства', s.deviceName, hint: 'iPhone (Актёр)');
    if (v != null && v.trim().isNotEmpty) s.update((x) => x.deviceName = v.trim());
  }

  Future<void> _reel(BuildContext context, AppSettings s) async {
    final v = await _textDialog(context, 'Ролик', s.reel, hint: 'A001');
    if (v != null && RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(v.trim())) {
      s.update((x) {
        x.reel = v.trim().toUpperCase();
        x.nextClip = 1;
      });
    }
  }

  Future<void> _port(BuildContext context, AppSettings s) async {
    final v = await _textDialog(context, 'Порт CAMERA', '${s.port}', number: true);
    final p = int.tryParse(v ?? '');
    if (p != null && p >= 1024 && p <= 65535) s.update((x) => x.port = p);
  }

  Future<String?> _textDialog(BuildContext context, String title, String initial, {String? hint, bool number = false}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Готово')),
        ],
      ),
    ).whenComplete(c.dispose);
  }
}
