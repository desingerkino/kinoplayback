import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/app_scope.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../network/stream_stats.dart';
import '../settings/app_settings.dart';
import 'camera_controller.dart';

/// Camera settings (reference screen 7). Every row changes real behaviour;
/// values shown are what the device actually selected.
Future<void> showCameraSettings(BuildContext context, CameraController c) {
  final settings = AppScope.of(context).settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => ListenableBuilder(
        listenable: Listenable.merge([c, settings]),
        builder: (context, _) {
          final rec = c.recorder.isRecording;
          final (w, h) = c.captureSize;
          final preset = settings.capturePreset;
          final sq = settings.stream;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(children: [
                Text('Настройки камеры', style: KpText.title),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              if (rec)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: KpBanner(text: 'Идёт запись: параметры оригинала можно менять после остановки.'),
                ),
              KpSection(
                title: 'Камера',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: KpSegmented<bool>(
                      values: const [false, true],
                      selected: settings.frontCamera,
                      labelOf: (f) => f ? 'Фронтальная' : 'Основная',
                      onChanged: rec ? null : (f) => f == settings.frontCamera ? null : c.switchCamera(),
                    ),
                  ),
                  KpRow(
                    label: 'Оригинал (запрошено)',
                    value: preset.label,
                    onTap: rec ? null : () => _pickPreset(context, c, settings),
                  ),
                  KpRow(
                    label: 'Фактически выбрано камерой',
                    value: '${fmtRes(w, h)} · ${c.capFps ?? '—'} к/с',
                    valueColor: c.warning != null ? KpColors.warn : KpColors.text,
                  ),
                  const KpRow(
                    label: 'Кодек оригинала',
                    value: 'H.264 (MP4)',
                    subtitle: 'Пишется из видеодорожки камеры; HEVC в этой версии недоступен',
                  ),
                  KpSwitchRow(
                    label: 'Звук',
                    subtitle: 'Микрофон в оригинал и в трансляцию',
                    value: settings.audioEnabled,
                    onChanged: rec ? null : (v) => c.setAudio(v),
                  ),
                ],
              ),
              KpSection(
                title: 'Трансляция на монитор',
                footer: 'Качество трансляции задаётся отдельно и не меняет разрешение оригинала. '
                    'При слабой сети WebRTC сам снижает битрейт ниже заданного предела.',
                children: [
                  KpRow(
                    label: 'Разрешение',
                    value: '≤ ${sq.height}p',
                    onTap: () => _pickInt(context, 'Разрешение трансляции', StreamQuality.heights, sq.height, (v) => '${v}p',
                        (v) => settings.update((s) => s.stream = StreamQuality(v, s.stream.fps, s.stream.maxKbps))),
                  ),
                  KpRow(
                    label: 'Частота кадров',
                    value: '≤ ${sq.fps} к/с',
                    onTap: () => _pickInt(context, 'FPS трансляции', StreamQuality.fpsOptions, sq.fps, (v) => '$v к/с',
                        (v) => settings.update((s) => s.stream = StreamQuality(s.stream.height, v, s.stream.maxKbps))),
                  ),
                  KpRow(
                    label: 'Битрейт, максимум',
                    value: fmtKbps(sq.maxKbps.toDouble()),
                    onTap: () => _pickInt(context, 'Максимальный битрейт', StreamQuality.bitrates, sq.maxKbps,
                        (v) => fmtKbps(v.toDouble()),
                        (v) => settings.update((s) => s.stream = StreamQuality(s.stream.height, s.stream.fps, v))),
                  ),
                  if (c.senderStats != null)
                    KpRow(
                      label: 'Сейчас передаётся',
                      value:
                          '${fmtRes(c.senderStats!.width, c.senderStats!.height)} · ${fmtFps(c.senderStats!.fps)} к/с · ${fmtKbps(c.senderStats!.bitrateKbps)}',
                      valueColor: KpColors.live,
                    ),
                ],
              ),
              KpSection(
                title: 'Удалённое управление',
                footer: 'Монитор сможет запускать и останавливать запись на этой камере. '
                    'Камера и микрофон никогда не включаются скрыто: этот экран всегда открыт во время работы.',
                children: [
                  KpSwitchRow(
                    label: 'Разрешить управление записью',
                    value: settings.remoteControlAllowed,
                    onChanged: (v) => settings.update((s) => s.remoteControlAllowed = v),
                  ),
                ],
              ),
              KpSection(
                title: 'Хранилище',
                children: [
                  KpRow(label: 'Свободно', value: formatBytes(c.freeBytes)),
                  KpSwitchRow(
                    label: 'Сохранять дубли в Фото / Галерею',
                    value: settings.autoSaveToGallery,
                    onChanged: (v) => settings.update((s) => s.autoSaveToGallery = v),
                  ),
                  KpRow(label: 'Следующий дубль', value: '${settings.reel}_C${settings.nextClip.toString().padLeft(3, '0')}'),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> _pickPreset(BuildContext context, CameraController c, AppSettings settings) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Разрешение и частота оригинала', style: KpText.heading),
          const SizedBox(height: 4),
          Text('Камера выберет ближайший доступный формат — фактическое значение покажется после применения.',
              style: KpText.caption),
          const SizedBox(height: 8),
          for (final p in CapturePreset.all)
            ListTile(
              dense: true,
              title: Text(p.label, style: KpText.body),
              trailing: p.id == settings.capturePresetId ? const Icon(Icons.check, color: KpColors.live) : null,
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    ),
  );
  if (id != null && id != settings.capturePresetId) await c.setPreset(id);
}

Future<void> _pickInt(BuildContext context, String title, List<int> values, int current, String Function(int) label,
    void Function(int) onPick) async {
  final v = await showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(title, style: KpText.heading),
          const SizedBox(height: 8),
          for (final x in values)
            ListTile(
              dense: true,
              title: Text(label(x), style: KpText.body),
              trailing: x == current ? const Icon(Icons.check, color: KpColors.live) : null,
              onTap: () => Navigator.pop(context, x),
            ),
        ],
      ),
    ),
  );
  if (v != null) onPick(v);
}

/// Connection info: QR, address, connected monitors (reference screen 12).
Future<void> showConnectSheet(BuildContext context, CameraController c) {
  final settings = AppScope.of(context).settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final uri = c.connectUri;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Подключение монитора', style: KpText.title),
                const SizedBox(height: 4),
                Text('Отсканируйте код на устройстве в режиме PLAYBACK или найдите камеру в списке. '
                    'Каждое новое устройство нужно подтвердить на этой камере.',
                    style: KpText.caption),
                const SizedBox(height: 16),
                Center(
                  child: uri == null
                      ? const KpEmptyState(
                          icon: Icons.wifi_off,
                          title: 'Нет локальной сети',
                          message: 'Подключите устройство к Wi-Fi или включите точку доступа.',
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: QrImageView(data: uri, size: 200, backgroundColor: Colors.white),
                        ),
                ),
                const SizedBox(height: 12),
                Center(child: Text(settings.deviceName, style: KpText.heading)),
                Center(
                  child: SelectableText('IP: ${c.lanIp ?? '—'}:${c.port ?? '—'}', style: KpText.metric.copyWith(color: KpColors.textDim)),
                ),
                const SizedBox(height: 16),
                KpSection(
                  title: 'Мониторы',
                  children: c.peers.isEmpty
                      ? [const KpRow(label: 'Нет подключений')]
                      : [
                          for (final p in c.peers)
                            KpRow(
                              label: p.name,
                              subtitle: '${p.platform} ${p.model}'.trim(),
                              value: switch (p.phase) {
                                PeerPhase.connected => 'в эфире',
                                PeerPhase.awaitingApproval => 'ждёт подтверждения',
                                PeerPhase.negotiating => 'соединение…',
                                PeerPhase.hello => 'приветствие…',
                                PeerPhase.closed => 'закрыто',
                              },
                              valueColor: p.phase == PeerPhase.connected ? KpColors.live : KpColors.textDim,
                              trailing: IconButton(
                                icon: const Icon(Icons.link_off, size: 18),
                                tooltip: 'Отключить',
                                onPressed: () => c.disconnectPeer(p),
                              ),
                            ),
                        ],
                ),
                if (settings.trusted.isNotEmpty)
                  KpSection(
                    title: 'Доверенные устройства',
                    footer: 'Подключаются без подтверждения.',
                    children: [
                      for (final e in settings.trusted.entries)
                        KpRow(
                          label: e.value,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => settings.update((s) => s.trusted = Map.of(s.trusted)..remove(e.key)),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
