import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../core/widgets/rec_widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../monitor/frame_analyzer.dart';
import '../monitor/monitor_chrome.dart';
import '../monitor/monitor_view.dart';
import '../network/net_utils.dart';
import '../network/stream_stats.dart';
import '../protocol/messages.dart';
import '../recording/takes_screen.dart';
import 'playback_controller.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key, required this.target});
  final ConnectTarget target;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  PlaybackController? _ctl;
  final FrameAnalyzer _analyzer = FrameAnalyzer();
  bool _chrome = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctl != null) return;
    final s = AppScope.of(context);
    final ctl = PlaybackController(settings: s.settings, repo: s.takes, identity: s.identity, target: widget.target);
    _ctl = ctl;
    unawaited(ctl.start());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _analyzer.dispose();
    final ctl = _ctl;
    ctl?.closeAndDispose();
    super.dispose();
  }

  Future<void> _exit() async {
    final ctl = _ctl!;
    if (ctl.recorder.isRecording) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Идёт запись монитора'),
          content: const Text('Отключиться? Запись на этом устройстве будет остановлена и сохранена. '
              'Запись на камере продолжится.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Остаться')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отключиться')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl!;
    final settings = AppScope.of(context).settings;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: KpColors.monitor,
        body: ListenableBuilder(
          listenable: Listenable.merge([ctl, settings]),
          builder: (context, _) {
            _analyzer.track = ctl.isLive ? ctl.remoteVideo : null;
            final ff = formFactorOfContext(context);
            return ff.isLandscape ? _landscape(ctl, ff) : _portrait(ctl, ff);
          },
        ),
      ),
    );
  }

  // --------------------------------------------------------------- pieces --
  Widget _monitor(PlaybackController c) {
    final settings = AppScope.of(context).settings;
    return GestureDetector(
      onTap: () => setState(() => _chrome = !_chrome),
      onDoubleTap: () => settings.update((s) => s.toolFill = !s.toolFill),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MonitorView(
            renderer: c.renderer,
            videoAspect: c.videoAspect,
            guides: guidesFrom(settings),
            analyzer: _analyzer,
            hasVideo: c.remoteVideo != null,
            placeholder: const SizedBox.shrink(),
          ),
          if (!c.isLive || c.remoteVideo == null) _linkOverlay(c),
          if (c.isLive && c.stateStale)
            const Positioned(
              top: 8,
              left: 8,
              child: KpBanner(text: 'Нет статуса от камеры — состояние REC неизвестно', color: KpColors.warn),
            ),
          if (_analyzer.isOn(AnalysisTool.histogram))
            Positioned(right: 8, bottom: 8, child: ListenableBuilder(
              listenable: _analyzer,
              builder: (context, _) => HistogramView(bins: _analyzer.histogram),
            )),
        ],
      ),
    );
  }

  Widget _linkOverlay(PlaybackController c) {
    final busy = c.phase == LinkPhase.connecting ||
        c.phase == LinkPhase.negotiating ||
        c.phase == LinkPhase.reconnecting ||
        c.phase == LinkPhase.awaitingApproval ||
        (c.isLive && c.remoteVideo == null);
    return Container(
      color: const Color(0xCC000000),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(c.phase == LinkPhase.rejected ? Icons.block : Icons.link_off, size: 36, color: KpColors.textDim),
          const SizedBox(height: 14),
          Text(c.isLive ? 'Ожидание видео…' : c.phase.label, style: KpText.heading, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            [
              if (c.remoteName.isNotEmpty) c.remoteName else c.target.name ?? '',
              '${c.target.host}:${c.target.port}',
            ].where((e) => e.isNotEmpty).join(' · '),
            style: KpText.caption,
          ),
          if (c.message != null && !c.isLive) ...[
            const SizedBox(height: 8),
            Text(c.message!, style: KpText.bodyDim, textAlign: TextAlign.center),
          ],
          if (c.phase == LinkPhase.awaitingApproval) ...[
            const SizedBox(height: 8),
            Text('Подтвердите подключение на экране камеры', style: KpText.bodyDim),
          ],
          if (c.phase == LinkPhase.reconnecting || c.phase == LinkPhase.rejected) ...[
            const SizedBox(height: 16),
            KpButton(label: 'Переподключиться', icon: Icons.refresh, onPressed: c.reconnectNow),
          ],
        ],
      ),
    );
  }

  Widget _nameAndLive(PlaybackController c) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width < 500 ? 130 : 220),
        child: Text(
          c.remoteName.isEmpty ? (c.target.name ?? c.target.host) : c.remoteName,
          overflow: TextOverflow.ellipsis,
          style: KpText.heading.copyWith(fontSize: 15),
        ),
      ),
      const SizedBox(width: 8),
      KpLiveBadge(active: c.isLive && c.remoteVideo != null),
    ]);
  }

  List<Widget> _streamItems(PlaybackController c, {bool full = true}) {
    final s = c.stats;
    return [
      StripItem(resLabel(c.videoWidth ?? s?.width, c.videoHeight ?? s?.height)),
      StripItem('${fmtFps(s?.fps)} fps'),
      if (full) StripItem(fmtKbps(s?.bitrateKbps), bold: false),
      if (full && s?.videoCodec != null) StripItem(s!.videoCodec!, bold: false),
      StripItem(s?.rttMs == null ? 'RTT —' : 'RTT ${s!.rttMs!.round()} ms', color: _rttColor(s?.rttMs), bold: false),
      if (full && (s?.lossPercent ?? 0) > 0.5)
        StripItem('потери ${s!.lossPercent!.toStringAsFixed(1)}%', color: KpColors.warn, bold: false),
    ];
  }

  Color? _rttColor(double? rtt) {
    if (rtt == null) return null;
    if (rtt > 150) return KpColors.rec;
    if (rtt > 60) return KpColors.warn;
    return KpColors.live;
  }

  List<Widget> _trailingItems(PlaybackController c) => [
        if (c.hasRemoteAudio)
          IconButton(
            tooltip: c.monitorMuted ? 'Включить звук монитора' : 'Выключить звук монитора',
            visualDensity: VisualDensity.compact,
            icon: Icon(c.monitorMuted ? Icons.volume_off : Icons.volume_up,
                size: 20, color: c.monitorMuted ? KpColors.warn : KpColors.text),
            onPressed: c.toggleMonitorAudio,
          ),
        if (c.hasRemoteAudio && !c.monitorMuted)
          KpAudioMeter(level: c.stats?.audioLevel, height: 18, width: 3),
        KpSignalBars(level: c.isLive ? c.stats?.quality : null),
        StripItem(
          batteryText(c.camState?.batteryLevel),
          icon: batteryIcon(c.camState?.batteryLevel),
          bold: false,
        ),
        _menuButton(c),
      ];

  Widget _menuButton(PlaybackController c) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: KpColors.text),
        color: KpColors.surface2,
        onSelected: (v) {
          switch (v) {
            case 'takes':
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => TakesScreen(playback: c)));
            case 'diag':
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagnosticsScreen(playback: c)));
            case 'tools':
              showMonitorTools(context, settings: AppScope.of(context).settings, analyzer: _analyzer);
            case 'reconnect':
              c.reconnectNow();
            case 'exit':
              _exit();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'tools', child: Text('Инструменты монитора')),
          PopupMenuItem(value: 'takes', child: Text('Дубли')),
          PopupMenuItem(value: 'diag', child: Text('Сеть и диагностика')),
          PopupMenuItem(value: 'reconnect', child: Text('Переподключиться')),
          PopupMenuItem(value: 'exit', child: Text('Отключиться')),
        ],
      );

  RecVisual _camRecVisual(PlaybackController c) {
    if (c.tracker.active != null) return RecVisual.pending;
    final rec = c.cameraRecording;
    if (rec == null) return RecVisual.disabled;
    if (c.camState?.remoteControlAllowed != true) return rec ? RecVisual.recording : RecVisual.disabled;
    return rec ? RecVisual.recording : RecVisual.idle;
  }

  void _pressCamRec(PlaybackController c) {
    final cmd = c.toggleRemoteRec();
    if (cmd == null && c.message != null) showKpToast(context, c.message!, color: KpColors.warn);
    if (cmd != null && cmd.stage == CmdStage.rejected) {
      showKpToast(context, CmdError.describe(cmd.error), color: KpColors.warn);
    }
  }

  Widget _camRec(PlaybackController c, {double size = 64}) => RecButton(
        size: size,
        state: _camRecVisual(c),
        semanticLabel: 'REC на камере',
        onPressed: () => _pressCamRec(c),
      );

  /// Camera clip timecode + command feedback.
  Widget _camTimer(PlaybackController c, {double fontSize = 22}) {
    final rec = c.cameraRecording;
    final cmd = c.tracker.last;
    String? cmdText;
    Color cmdColor = KpColors.textDim;
    if (cmd != null && DateTime.now().difference(cmd.createdAt) < const Duration(seconds: 6)) {
      final verb = cmd.type == MsgType.recStart ? 'Старт' : 'Стоп';
      switch (cmd.stage) {
        case CmdStage.sending:
        case CmdStage.sent:
          cmdText = '$verb: отправлено';
        case CmdStage.received:
          cmdText = '$verb: получено камерой';
        case CmdStage.accepted:
          cmdText = '$verb: выполняется…';
        case CmdStage.done:
          cmdText = '$verb: подтверждено';
          cmdColor = KpColors.live;
        case CmdStage.rejected:
          cmdText = '$verb: ${CmdError.describe(cmd.error)}';
          cmdColor = KpColors.warn;
        case CmdStage.failed:
          cmdText = '$verb: ошибка — ${cmd.error == 'connection_lost' ? 'связь потеряна' : CmdError.describe(cmd.error)}';
          cmdColor = KpColors.rec;
        case CmdStage.timedOut:
          cmdText = '$verb: нет ответа от камеры';
          cmdColor = KpColors.rec;
      }
    }
    final label = rec == null
        ? 'REC камеры: неизвестно'
        : c.camState?.remoteControlAllowed == true
            ? (rec ? 'REC камеры · ${c.camState?.clipName ?? ''}' : 'REC камеры')
            : 'Удалённый REC запрещён на камере';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KpTimecode(
          anchor: c.cameraRecAnchor,
          style: KpText.timecode.copyWith(fontSize: fontSize),
          color: (rec ?? false) ? KpColors.rec : KpColors.textDim,
        ),
        Text(cmdText ?? label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KpText.caption.copyWith(color: cmdText != null ? cmdColor : KpColors.textDim)),
      ],
    );
  }

  Widget _localRec(PlaybackController c, {bool compact = false}) {
    final r = c.recorder;
    final rec = r.isRecording;
    final enabled = c.isLive && c.remoteVideo != null && !r.busy;
    return Material(
      color: rec ? KpColors.rec.withValues(alpha: 0.18) : KpColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (enabled || rec) ? c.toggleLocalRec : null,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: rec ? KpColors.rec : KpColors.strokeStrong),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(rec ? Icons.stop_rounded : Icons.fiber_manual_record,
                size: 16, color: (enabled || rec) ? KpColors.rec : KpColors.inactive),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(compact ? 'МОНИТОР' : 'ЗАПИСЬ МОНИТОРА',
                  style: KpText.caption.copyWith(fontSize: 9, letterSpacing: 0.6)),
              KpTimecode(
                anchor: rec ? r.startedAt : null,
                style: KpText.metric.copyWith(fontSize: 13),
                color: rec ? KpColors.rec : KpColors.textDim,
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _snapshot(PlaybackController c) => KpRoundButton(
        icon: Icons.photo_camera_outlined,
        tooltip: 'Сохранить кадр в Фото',
        onTap: c.remoteVideo == null
            ? null
            : () async {
                final err = await c.snapshot();
                if (mounted) showKpToast(context, err ?? 'Кадр сохранён в Фото', color: err == null ? KpColors.live : KpColors.warn);
              },
      );

  Widget _lastInfo(PlaybackController c) {
    final s = c.camState;
    final local = c.recorder.lastTake;
    final lines = <String>[
      if (s?.lastSavedClip != null)
        'Камера: ${s!.lastSavedClip}${s.lastSaveOk == false ? ' — ошибка' : ''}',
      if (local != null) 'Монитор: ${local.name}${local.finalizeError != null ? ' — ошибка' : ''}',
      if (s?.storageFreeBytes != null) 'Свободно на камере: ${formatBytes(s!.storageFreeBytes)}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [for (final l in lines) Text(l, style: KpText.metricSmall, maxLines: 1, overflow: TextOverflow.ellipsis)],
    );
  }

  List<Widget> _toolButtons({bool compact = false}) {
    final settings = AppScope.of(context).settings;
    return [
      KpToolButton(
        icon: Icons.grid_on,
        label: 'Сетка',
        compact: compact,
        selected: settings.toolGrid,
        onTap: () => settings.update((s) => s.toolGrid = !s.toolGrid),
      ),
      KpToolButton(
        icon: Icons.texture,
        label: 'Зебра',
        compact: compact,
        selected: _analyzer.isOn(AnalysisTool.zebra),
        onTap: () => setState(() => _analyzer.toggle(AnalysisTool.zebra)),
      ),
      KpToolButton(
        icon: Icons.palette_outlined,
        label: 'False',
        compact: compact,
        selected: _analyzer.isOn(AnalysisTool.falseColor),
        onTap: () => setState(() => _analyzer.toggle(AnalysisTool.falseColor)),
      ),
      KpToolButton(
        icon: Icons.bar_chart,
        label: 'Гисто',
        compact: compact,
        selected: _analyzer.isOn(AnalysisTool.histogram),
        onTap: () => setState(() => _analyzer.toggle(AnalysisTool.histogram)),
      ),
      KpToolButton(
        icon: Icons.add,
        label: 'Центр',
        compact: compact,
        selected: settings.toolCross,
        onTap: () => settings.update((s) => s.toolCross = !s.toolCross),
      ),
      KpToolButton(
        icon: Icons.more_horiz,
        label: 'Ещё',
        compact: compact,
        onTap: () => showMonitorTools(context, settings: settings, analyzer: _analyzer),
      ),
    ];
  }

  Widget _aspectRail() {
    final settings = AppScope.of(context).settings;
    Widget b(String label, bool sel, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? KpColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sel ? KpColors.select : KpColors.stroke),
              ),
              child: Text(label, style: KpText.metricSmall.copyWith(color: sel ? KpColors.text : KpColors.textDim)),
            ),
          ),
        );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in const ['1:1', '4:3', '16:9', '1.85:1', '2.39:1'])
            b(a, settings.toolAspect == a,
                () => settings.update((s) => s.toolAspect = s.toolAspect == a ? 'off' : a)),
          const SizedBox(height: 6),
          b('Fit', !settings.toolFill, () => settings.update((s) => s.toolFill = false)),
          b('Fill', settings.toolFill, () => settings.update((s) => s.toolFill = true)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ landscape --
  Widget _landscape(PlaybackController c, KpFormFactor ff) {
    final rail = ff.isTablet ? 72.0 : 62.0;
    final monitor = _monitor(c);
    if (!_chrome) {
      return Stack(children: [
        Positioned.fill(child: monitor),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(child: Row(mainAxisSize: MainAxisSize.min, children: [
            _camTimer(c, fontSize: 16),
            const SizedBox(width: 12),
            _camRec(c, size: 52),
          ])),
        ),
      ]);
    }
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: StatusStrip(
              leading: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _exit, visualDensity: VisualDensity.compact),
                _nameAndLive(c),
                ..._streamItems(c, full: ff.isTablet || MediaQuery.sizeOf(context).width > 760),
              ],
              trailing: _trailingItems(c),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: rail,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final w in _toolButtons(compact: !ff.isTablet && MediaQuery.sizeOf(context).height < 500))
                          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: w),
                      ],
                    ),
                  ),
                ),
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: monitor)),
                SizedBox(width: rail, child: Center(child: _aspectRail())),
              ],
            ),
          ),
          SizedBox(
            height: ff.isTablet ? 84 : 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _snapshot(c),
                  const SizedBox(width: 16),
                  _camRec(c, size: ff.isTablet ? 66 : 56),
                  const SizedBox(width: 12),
                  Expanded(child: _camTimer(c, fontSize: ff.isTablet ? 24 : 20)),
                  _localRec(c),
                  const SizedBox(width: 12),
                  if (MediaQuery.sizeOf(context).width > 700) Flexible(child: _lastInfo(c)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- portrait --
  Widget _portrait(PlaybackController c, KpFormFactor ff) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: StatusStrip(
              leading: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _exit),
                _nameAndLive(c),
              ],
              trailing: _trailingItems(c),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StatusStrip(height: 24, leading: _streamItems(c, full: ff.isTablet), trailing: const []),
          ),
          const SizedBox(height: 6),
          Expanded(child: _monitor(c)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _camRec(c, size: ff.isTablet ? 76 : 64),
                const SizedBox(width: 12),
                Expanded(child: _camTimer(c)),
                _localRec(c, compact: !ff.isTablet),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _snapshot(c),
              const SizedBox(width: 12),
              Expanded(child: Align(alignment: Alignment.centerRight, child: _lastInfo(c))),
            ]),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: _toolButtons()),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
