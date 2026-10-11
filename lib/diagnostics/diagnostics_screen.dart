import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../camera/camera_controller.dart';
import '../core/brand/kp_logo.dart';
import '../core/event_log.dart';
import '../external_display/external_display.dart';
import '../core/layout/adaptive.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../network/stream_stats.dart';
import '../playback/playback_controller.dart';

/// Network & diagnostics (reference screen 11). Shows only measured values;
/// anything the platform doesn't report is "—".
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, this.camera, this.playback});

  final CameraController? camera;
  final PlaybackController? playback;

  String _dump(BuildContext context) {
    final s = AppScope.of(context);
    final id = s.identity;
    final b = StringBuffer()
      ..writeln('KINO PLAYBACK diagnostics ${DateTime.now().toIso8601String()}')
      ..writeln('App ${id.appVersion} · ${id.platform} ${id.osVersion} · ${id.model} · physical=${id.isPhysical}')
      ..writeln('Device name: ${s.settings.deviceName}');
    final c = camera;
    if (c != null) {
      final (w, h) = c.captureSize;
      b
        ..writeln('Mode: CAMERA · phase=${c.phase.name} · capture=${fmtRes(w, h)}@${c.capFps} · facing=${c.facing}')
        ..writeln('LAN ${c.lanIp}:${c.port} · peers=${c.peers.map((p) => '${p.name}/${p.phase.name}').join(', ')}')
        ..writeln('Recording=${c.recorder.isRecording} clip=${c.recorder.current?.name} last=${c.recorder.lastTake?.name}')
        ..writeln('Remote REC allowed=${s.settings.remoteControlAllowed}');
      final st = c.senderStats;
      if (st != null) {
        b.writeln('Sending ${fmtRes(st.width, st.height)} ${fmtFps(st.fps)}fps ${fmtKbps(st.bitrateKbps)} '
            'src ${fmtRes(st.sourceWidth, st.sourceHeight)} ${fmtFps(st.sourceFps)}fps '
            'rtt=${st.rttMs?.round()}ms limit=${st.qualityLimitation} cand=${st.candidateType}/${st.networkType}');
      }
    }
    final p = playback;
    if (p != null) {
      final st = p.stats;
      b
        ..writeln('Mode: PLAYBACK · ${p.phase.name} · camera ${p.remoteName} (${p.remotePlatform} ${p.remoteModel}) '
            '${p.target.host}:${p.target.port} session=${p.sessionId}')
        ..writeln('Recv ${fmtRes(st?.width, st?.height)} ${fmtFps(st?.fps)}fps ${fmtKbps(st?.bitrateKbps)} '
            'codec=${st?.videoCodec} rtt=${st?.rttMs?.round()}ms loss=${st?.lossPercent?.toStringAsFixed(2)}% '
            'lost=${st?.packetsLost} jitter=${st?.jitterMs?.toStringAsFixed(1)}ms dropped=${st?.framesDropped} '
            'cand=${st?.candidateType}/${st?.networkType}')
        ..writeln('Camera state: rec=${p.camState?.recording} clip=${p.camState?.clipName} '
            'remote=${p.camState?.remoteControlAllowed} seq=${p.camState?.seq} stale=${p.stateStale}');
    }
    b
      ..writeln('--- events ---')
      ..writeln(EventLog.instance.dump());
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ff = formFactorOfContext(context);
    final listenables = <Listenable>[EventLog.instance, if (camera != null) camera!, if (playback != null) playback!];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сеть и диагностика'),
        actions: [
          IconButton(
            tooltip: 'Скопировать отчёт',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _dump(context)));
              if (context.mounted) showKpToast(context, 'Диагностика скопирована', color: KpColors.live);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(listenables),
          builder: (context, _) {
            final left = <Widget>[
              if (playback != null) _playbackSection(playback!),
              if (camera != null) _cameraSection(camera!, s.settings.remoteControlAllowed),
              const Padding(padding: EdgeInsets.only(bottom: 12), child: KpLogo(height: 28)),
              KpSection(title: 'Внешний дисплей', children: [
                KpRow(label: 'Статус', value: ExternalDisplay.instance.state.label),
                KpRow(
                  label: 'Экран',
                  value: ExternalDisplay.instance.width == null
                      ? '—'
                      : '${ExternalDisplay.instance.width}×${ExternalDisplay.instance.height}',
                ),
              ]),
              KpSection(title: 'Устройство', children: [
                KpRow(label: 'Модель', value: s.identity.model),
                KpRow(label: s.identity.platform, value: s.identity.osVersion),
                KpRow(label: 'Имя', value: s.settings.deviceName),
                KpRow(label: 'Версия приложения', value: s.identity.appVersion),
                KpRow(label: 'Свободно', value: formatBytes(freeBytesAt(s.takes.dir.path))),
                if (!s.identity.isPhysical) const KpRow(label: 'Эмулятор / симулятор', value: 'да', valueColor: KpColors.warn),
              ]),
            ];
            final events = EventLog.instance.entries.reversed.take(150).toList();
            final log = KpSection(
              title: 'Последние события',
              children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.time.toIso8601String().substring(11, 19), style: KpText.metricSmall),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '[${e.tag}] ${e.message}',
                          style: KpText.caption.copyWith(
                            color: switch (e.level) {
                              LogLevel.error => KpColors.rec,
                              LogLevel.warn => KpColors.warn,
                              LogLevel.info => KpColors.textDim,
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (events.isEmpty) const KpRow(label: 'Событий нет'),
              ],
            );
            if (ff.isLandscape && ff.isTablet || MediaQuery.sizeOf(context).width > 900) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ListView(padding: const EdgeInsets.all(16), children: left)),
                Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [log])),
              ]);
            }
            return ListView(padding: const EdgeInsets.all(16), children: [...left, log]);
          },
        ),
      ),
    );
  }

  Widget _playbackSection(PlaybackController p) {
    final st = p.stats;
    return KpSection(
      title: 'Соединение',
      children: [
        KpRow(
          label: 'Статус',
          value: p.phase.label,
          valueColor: p.isLive ? KpColors.live : KpColors.warn,
          leading: KpStatusDot(color: p.isLive ? KpColors.live : KpColors.warn, pulse: !p.isLive),
        ),
        KpRow(label: 'Камера', value: '${p.remoteName} · ${p.remotePlatform} ${p.remoteModel}'.trim()),
        KpRow(label: 'Адрес', value: '${p.target.host}:${p.target.port}'),
        KpRow(
          label: 'Тип соединения',
          value: 'WebRTC (DTLS-SRTP) · ${st?.candidateType ?? '—'}${st?.networkType != null ? ' · ${st!.networkType}' : ''}',
        ),
        if (p.liveSince != null) KpRow(label: 'В эфире с', value: p.liveSince!.toIso8601String().substring(11, 19)),
        KpRow(label: 'Разрешение (принято)', value: fmtRes(st?.width ?? p.videoWidth, st?.height ?? p.videoHeight)),
        KpRow(label: 'FPS (декодировано)', value: fmtFps(st?.fps)),
        KpRow(label: 'Битрейт', value: fmtKbps(st?.bitrateKbps)),
        KpRow(label: 'Кодек', value: st?.videoCodec ?? '—'),
        KpRow(label: 'RTT сети (ICE)', value: st?.rttMs == null ? '—' : '${st!.rttMs!.round()} ms',
            subtitle: 'Сетевая задержка туда-обратно, не задержка «стекло-стекло»'),
        KpRow(label: 'Джиттер', value: st?.jitterMs == null ? '—' : '${st!.jitterMs!.toStringAsFixed(1)} ms'),
        KpRow(label: 'Потеря пакетов', value: st?.lossPercent == null ? '—' : '${st!.lossPercent!.toStringAsFixed(2)} %'),
        KpRow(label: 'Потеряно всего', value: st?.packetsLost?.toString() ?? '—'),
        KpRow(label: 'Отброшено кадров', value: st?.framesDropped?.toString() ?? '—'),
        KpRow(label: 'Аудио', value: p.hasRemoteAudio ? 'принимается' : 'нет'),
        KpRow(label: 'Поворот изображения', value: p.orientation.mode.name),
        KpRow(
          label: 'Наклон камеры (roll)',
          value: p.orientation.cameraRoll == null || !p.orientation.hasFreshData(p.nowMs)
              ? 'NO DATA'
              : '${p.orientation.cameraRoll!.toStringAsFixed(1)}°',
        ),
        KpRow(
          label: 'Состояние камеры',
          value: p.camState == null
              ? '—'
              : '${p.camState!.recording ? 'REC' : 'STBY'} · удалённое упр. ${p.camState!.remoteControlAllowed ? 'да' : 'нет'}'
                  '${p.stateStale ? ' · устарело' : ''}',
        ),
      ],
    );
  }

  Widget _cameraSection(CameraController c, bool remoteAllowed) {
    final (w, h) = c.captureSize;
    final st = c.senderStats;
    return KpSection(
      title: 'Камера и трансляция',
      children: [
        KpRow(label: 'Режим', value: 'CAMERA'),
        KpRow(label: 'Захват', value: '${fmtRes(w, h)} · ${c.capFps ?? '—'} к/с (выбрано камерой)'),
        KpRow(label: 'FPS источника (измерено)', value: fmtFps(st?.sourceFps)),
        KpRow(label: 'Адрес', value: '${c.lanIp ?? '—'}:${c.port ?? '—'}'),
        KpRow(label: 'Мониторы', value: c.connectedPeers.isEmpty ? 'нет' : c.connectedPeers.map((p) => p.name).join(', ')),
        KpRow(label: 'Передаётся', value: '${fmtRes(st?.width, st?.height)} · ${fmtFps(st?.fps)} к/с · ${fmtKbps(st?.bitrateKbps)}'),
        KpRow(label: 'Ограничение качества', value: st?.qualityLimitation ?? '—'),
        KpRow(label: 'RTT сети (ICE)', value: st?.rttMs == null ? '—' : '${st!.rttMs!.round()} ms'),
        KpRow(label: 'Запись', value: c.recorder.isRecording ? 'REC · ${c.recorder.current?.name}' : 'нет'),
        KpRow(label: 'Удалённый REC', value: remoteAllowed ? 'разрешён' : 'запрещён'),
        KpRow(label: 'Аудио', value: c.hasAudio ? 'включено' : 'выключено'),
        KpRow(label: 'Источник', value: c.isExternal ? 'внешний: ${c.externalLabel}' : 'камера устройства'),
        KpRow(label: 'Датчик наклона', value: c.motion.available ? (c.motion.roll == null ? 'лежит горизонтально / нет данных' : '${c.motion.roll!.toStringAsFixed(1)}°') : 'NOT AVAILABLE'),
        KpRow(label: 'Пакетов ориентации отправлено', value: '${c.motionSamplesSent}'),
        KpRow(label: 'Фокус / экспозиция', value: '${c.afLocked ? 'AF-L' : 'AF'} · ${c.aeLocked ? 'AE-L' : 'AE'} · ${c.zoom.toStringAsFixed(1)}×'),
      ],
    );
  }
}
