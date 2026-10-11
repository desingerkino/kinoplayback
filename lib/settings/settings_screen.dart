import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_scope.dart';
import '../core/brand/kp_logo.dart';
import '../core/layout/orientation_lock.dart';
import '../external_display/external_display_sheet.dart';
import '../motion/orientation_sync.dart';
import '../transmitters/schemes_screen.dart';
import '../transmitters/transmitters_screen.dart';
import '../core/layout/adaptive.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../network/stream_stats.dart';
import 'app_settings.dart';

enum _Sec { video, camera, rotation, audio, connection, transmitters, display, permissions, ui, storage, about }

extension on _Sec {
  String get title => switch (this) {
        _Sec.video => 'Видео',
        _Sec.camera => 'Камера',
        _Sec.rotation => 'Ориентация',
        _Sec.transmitters => 'Внешние видеолинки',
        _Sec.display => 'Внешний дисплей',
        _Sec.permissions => 'Разрешения и безопасность',
        _Sec.audio => 'Аудио',
        _Sec.connection => 'Соединение',
        _Sec.ui => 'Интерфейс',
        _Sec.storage => 'Хранилище',
        _Sec.about => 'О приложении',
      };
  IconData get icon => switch (this) {
        _Sec.video => Icons.videocam_outlined,
        _Sec.camera => Icons.camera_outlined,
        _Sec.rotation => Icons.screen_rotation_alt,
        _Sec.transmitters => Icons.settings_input_antenna,
        _Sec.display => Icons.connected_tv,
        _Sec.permissions => Icons.verified_user_outlined,
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
          _Sec.camera => [
              KpSection(
                title: 'FRONT CAMERA',
                footer: 'Три независимые настройки. Зеркалирование применяется только к фронтальной камере и только к изображению на экране; '
                    'файл и поток на монитор не отражаются.',
                children: [
                  KpSwitchRow(
                    label: 'Preview Mirror',
                    subtitle: 'Зеркальный предпросмотр в CAMERA (можно менять во время записи)',
                    value: s.frontPreviewMirror,
                    onChanged: (v) => s.update((x) => x.frontPreviewMirror = v),
                  ),
                  const KpSwitchRow(
                    label: 'Recording Mirror',
                    subtitle: 'Не поддерживается текущим рекордером: файл всегда пишется без отражения',
                    value: false,
                    onChanged: null,
                  ),
                  KpSwitchRow(
                    label: 'Playback Mirror',
                    subtitle: 'Отражение на этом устройстве в режиме PLAYBACK (локально, файл камеры не меняется)',
                    value: s.playbackMirror,
                    onChanged: (v) => s.update((x) => x.playbackMirror = v),
                  ),
                  KpRow(label: 'Reset to Default', onTap: s.resetMirrorDefaults),
                ],
              ),
              KpSection(
                title: 'Фокус и экспозиция',
                footer: 'Касание в CAMERA ставит точку фокуса и/или экспозамера. Через текущий движок камеры доступны: точка фокуса, '
                    'точка экспозиции, AF LOCK, AE LOCK (только iOS), зум. Ручной фокус, ISO, выдержка, баланс белого и EV — недоступны.',
                children: [
                  KpRow(
                    label: 'Касание по изображению',
                    value: switch (s.tapTarget) { 'focus' => 'Фокус', 'exposure' => 'Экспозиция', _ => 'Фокус + экспозиция' },
                    onTap: () => s.update((x) => x.tapTarget = switch (x.tapTarget) { 'both' => 'focus', 'focus' => 'exposure', _ => 'both' }),
                  ),
                  KpSwitchRow(
                    label: 'Управление фокусом/экспозицией с монитора',
                    subtitle: 'PLAYBACK сможет ставить точки и AE/AF LOCK; каждое действие подтверждается камерой',
                    value: s.remoteCameraControl,
                    onChanged: (v) => s.update((x) => x.remoteCameraControl = v),
                  ),
                ],
              ),
            ],
          _Sec.rotation => [
              KpSection(
                title: 'Блокировка ориентации интерфейса',
                footer: 'Работает в CAMERA и PLAYBACK. Запись, соединение и данные о наклоне камеры при этом не сбрасываются. '
                    'На iPad для блокировки приложение работает в полноэкранном режиме (без Split View).',
                children: [
                  for (final o in OrientationLock.values)
                    KpRow(
                      leading: Icon(o.icon, size: 18, color: KpColors.textDim),
                      label: o.label,
                      trailing: s.orientationLock == o.name ? const Icon(Icons.check, color: KpColors.text, size: 18) : null,
                      onTap: () => s.update((x) => x.orientationLock = o.name),
                    ),
                ],
              ),
              KpSection(
                title: 'Camera Motion Sync (PLAYBACK)',
                footer: 'Наклон камеры измеряется её датчиком гравитации (без интегрирования гироскопа — без дрейфа) и передаётся '
                    '15 раз в секунду по каналу данных сессии. Влияет только на отображение монитора.',
                children: [
                  for (final m in RotationMode.values)
                    KpRow(
                      label: m.label,
                      subtitle: m.hint,
                      trailing: s.rotationMode == m.name ? const Icon(Icons.check, color: KpColors.text, size: 18) : null,
                      onTap: () => s.update((x) => x.rotationMode = m.name),
                    ),
                  KpSwitchRow(label: 'Индикатор горизонта', value: s.toolHorizon, onChanged: (v) => s.update((x) => x.toolHorizon = v)),
                  KpSwitchRow(
                    label: 'Инвертировать крен',
                    subtitle: 'Если на конкретной паре устройств наклон показывается в обратную сторону',
                    value: s.rollInvert,
                    onChanged: (v) => s.update((x) => x.rollInvert = v),
                  ),
                ],
              ),
            ],
          _Sec.transmitters => [
              KpSection(children: [
                KpRow(
                  label: 'Каталог VAXIS / Accsoon',
                  subtitle: 'Модели, статусы совместимости, источники, журнал тестов',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransmittersScreen())),
                ),
                KpRow(
                  label: 'Схемы подключения',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
                ),
              ]),
            ],
          _Sec.display => [
              KpSection(
                footer: 'CLEAN FEED: на внешний экран выводится только изображение. Подключение — через Пункт управления → '
                    '«Повтор экрана» (Apple TV / AirPlay) или проводной адаптер; на Android — презентационный дисплей.',
                children: [
                  const KpRow(label: 'Режим вывода', value: 'CLEAN FEED'),
                  KpRow(label: 'Статус и подключение', onTap: () => showExternalDisplaySheet(context)),
                ],
              ),
            ],
          _Sec.permissions => [const _PermissionsSection()],
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
                footer: 'Файлы лежат в папке приложения (на iOS видны в «Файлах») и копируются в медиатеку.',
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
              ),
            ],
          _Sec.about => [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: KpLogo(height: 44)),
              ),
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

/// Real permission states from the OS, with a way to the system settings.
class _PermissionsSection extends StatefulWidget {
  const _PermissionsSection();

  @override
  State<_PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<_PermissionsSection> {
  final Map<String, PermissionStatus?> _st = {};

  static final _perms = <String, Permission>{
    'Камера': Permission.camera,
    'Микрофон': Permission.microphone,
    'Фото (добавление)': Permission.photosAddOnly,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final e in _perms.entries) {
      try {
        _st[e.key] = await e.value.status;
      } catch (_) {
        _st[e.key] = null;
      }
    }
    if (mounted) setState(() {});
  }

  String _label(PermissionStatus? s) => switch (s) {
        PermissionStatus.granted => 'разрешено',
        PermissionStatus.limited => 'ограничено',
        PermissionStatus.denied => 'не запрошено / отклонено',
        PermissionStatus.permanentlyDenied => 'запрещено',
        PermissionStatus.restricted => 'ограничено системой',
        PermissionStatus.provisional => 'временно',
        null => 'NO DATA',
      };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return Column(children: [
      KpSection(
        title: 'Системные разрешения',
        footer: 'Локальная сеть (iOS) запрашивается при первом поиске камер; её состояние приложение прочитать не может.',
        children: [
          for (final e in _perms.entries)
            KpRow(
              label: e.key,
              value: _label(_st[e.key]),
              valueColor: _st[e.key] == PermissionStatus.granted ? KpColors.live : KpColors.warn,
            ),
          KpRow(label: 'Открыть настройки системы', onTap: () => openAppSettings()),
        ],
      ),
      KpSection(
        title: 'Безопасность сессий',
        footer: 'Видео, звук и команды идут напрямую между устройствами и шифруются WebRTC (DTLS-SRTP). Каждое новое устройство '
            'подтверждается на камере; команды имеют уникальные ID и подтверждение выполнения. Сигнализация по LAN не шифруется.',
        children: [
          KpSwitchRow(
            label: 'Удалённый REC',
            value: s.remoteControlAllowed,
            onChanged: (v) => s.update((x) => x.remoteControlAllowed = v),
          ),
          KpSwitchRow(
            label: 'Удалённый фокус / экспозиция',
            value: s.remoteCameraControl,
            onChanged: (v) => s.update((x) => x.remoteCameraControl = v),
          ),
          KpRow(label: 'Доверенные мониторы', value: '${s.trusted.length}'),
          if (s.trusted.isNotEmpty)
            KpRow(label: 'Сбросить доверие', valueColor: KpColors.rec, onTap: () => s.update((x) => x.trusted = {})),
        ],
      ),
    ]);
  }
}
