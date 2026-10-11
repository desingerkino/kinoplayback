import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/layout/orientation_lock.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../core/widgets/rec_widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../external_display/external_display.dart';
import '../external_display/external_display_sheet.dart';
import '../motion/orientation_math.dart';
import '../monitor/monitor_chrome.dart';
import '../monitor/monitor_view.dart';
import '../monitor/overlays.dart';
import '../network/stream_stats.dart';
import '../recording/takes_screen.dart';
import 'camera_controller.dart';
import 'camera_sheets.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.externalDeviceId, this.externalLabel});

  /// External USB/UVC source chosen in "Источник видео" (null = built-in camera).
  final String? externalDeviceId;
  final String? externalLabel;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _ctl;
  bool _locked = false;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctl != null) return;
    final s = AppScope.of(context);
    final ctl = CameraController(
      settings: s.settings,
      repo: s.takes,
      identity: s.identity,
      externalDeviceId: widget.externalDeviceId,
      externalLabel: widget.externalLabel,
    );
    ctl.approve = _approve;
    _ctl = ctl;
    unawaited(ctl.start());
    ctl.addListener(_syncExternalDisplay);
    ExternalDisplay.instance.addListener(_syncExternalDisplay);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    applyOrientationLock(OrientationLockX.parse(s.settings.orientationLock));
  }

  /// CLEAN FEED: whenever an external screen is present, show the live
  /// camera track there (re-attached if the camera is switched).
  void _syncExternalDisplay() {
    final ctl = _ctl;
    final ext = ExternalDisplay.instance;
    final t = ctl?.videoTrack;
    if (ctl == null || t == null || !ext.connected) return;
    if (ext.attachedTrackId != t.id) unawaited(ext.show(t));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    applyOrientationLock(OrientationLock.auto);
    ExternalDisplay.instance.removeListener(_syncExternalDisplay);
    if (ExternalDisplay.instance.attachedTrackId != null && ExternalDisplay.instance.attachedTrackId == _ctl?.videoTrack?.id) {
      unawaited(ExternalDisplay.instance.hide());
    }
    _ctl?.removeListener(_syncExternalDisplay);
    final ctl = _ctl;
    if (ctl != null) {
      unawaited(ctl.shutdown().whenComplete(ctl.dispose));
    }
    super.dispose();
  }

  Future<ApprovalDecision> _approve(String name, String platform, String address) async {
    if (!mounted) return ApprovalDecision.deny;
    final r = await showDialog<ApprovalDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Подключение монитора'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: KpText.heading),
            const SizedBox(height: 4),
            Text([if (platform.isNotEmpty) platform, address].join(' · '), style: KpText.caption),
            const SizedBox(height: 12),
            const Text('Разрешить этому устройству принимать изображение и звук с камеры?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ApprovalDecision.deny),
            child: const Text('Отклонить', style: TextStyle(color: KpColors.rec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ApprovalDecision.once),
            child: const Text('Разрешить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ApprovalDecision.always),
            child: const Text('Всегда доверять'),
          ),
        ],
      ),
    );
    return r ?? ApprovalDecision.deny;
  }

  Future<void> _exit() async {
    final ctl = _ctl!;
    if (_closing) return;
    if (ctl.recorder.isRecording) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Идёт запись'),
          content: const Text('Выйти из режима CAMERA? Запись будет остановлена и файл сохранён.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Остаться')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Остановить и выйти', style: TextStyle(color: KpColors.rec)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _closing = true;
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
            final ff = formFactorOfContext(context);
            return ff.isLandscape ? _landscape(ctl, ff) : _portrait(ctl, ff);
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ pieces --
  RecVisual _recVisual(CameraController c) {
    if (c.phase != CameraPhase.ready) return RecVisual.disabled;
    if (c.recorder.busy) return RecVisual.pending;
    return c.recorder.isRecording ? RecVisual.recording : RecVisual.idle;
  }

  double _previewAspect(CameraController c) {
    final v = c.preview.value;
    if (v.width <= 0 || v.height <= 0) return 16 / 9;
    return v.aspectRatio;
  }

  bool _previewMirrored(CameraController c) =>
      c.facing == 'front' && AppScope.of(context).settings.frontPreviewMirror;

  double _zoomStart = 1;

  Widget _monitor(CameraController c) {
    final settings = AppScope.of(context).settings;
    final aspect = _previewAspect(c);
    final mirrored = _previewMirrored(c);
    final cover = settings.toolFill;
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      Offset? toWidget(Offset? p) => p == null
          ? null
          : pictureToWidget(point: p, box: size, aspect: aspect, cover: cover, mirrored: mirrored);
      final roll = c.motion.roll;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (_locked || c.phase != CameraPhase.ready || c.isExternal)
            ? null
            : (d) {
                // Undo fit / mirror so the point refers to the same object in
                // the camera's own picture coordinates.
                final p = tapToPicture(tap: d.localPosition, box: size, aspect: aspect, cover: cover, mirrored: mirrored);
                if (p != null) c.tapAt(p, settings.tapTarget);
              },
        onScaleStart: c.caps.zoom && !_locked ? (_) => _zoomStart = c.zoom : null,
        onScaleUpdate: c.caps.zoom && !_locked
            ? (d) {
                if (d.pointerCount < 2) return;
                final z = (_zoomStart * d.scale).clamp(1.0, 10.0);
                if ((z - c.zoom).abs() > 0.05) c.zoomTo(z);
              }
            : null,
        child: Stack(fit: StackFit.expand, children: [
          MonitorView(
            renderer: c.preview,
            videoAspect: aspect,
            guides: guidesFrom(settings),
            mirror: mirrored,
            hasVideo: c.phase == CameraPhase.ready,
            placeholder: _placeholder(c),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: ReticlePainter(
                focus: toWidget(c.focusPoint),
                exposure: toWidget(c.exposurePoint),
                afLocked: c.afLocked,
                aeLocked: c.aeLocked,
              ),
            ),
          ),
          if (settings.toolHorizon && roll != null && !c.isExternal)
            IgnorePointer(
              child: CustomPaint(
                painter: HorizonPainter(angleDeg: -residualRoll(roll, c.motion.quant), tiltDeg: residualRoll(roll, c.motion.quant)),
              ),
            ),
        ]),
      );
    });
  }

  /// Focus / exposure / zoom / roll strip over the preview.
  Widget _controlStrip(CameraController c) {
    final settings = AppScope.of(context).settings;
    final caps = c.caps;
    final roll = c.motion.roll;
    final ext = ExternalDisplay.instance;
    return AbsorbPointer(
      absorbing: _locked,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (c.isExternal)
            KpPill(label: 'USB · ${c.externalLabel ?? 'UVC'}', icon: Icons.usb, enabled: true)
          else ...[
            KpPill(
              label: tapTargetLabel(settings.tapTarget),
              enabled: caps.focusPoint,
              onTap: () => settings.update((s) => s.tapTarget = nextTapTarget(s.tapTarget)),
            ),
            KpPill(label: 'AF-L', active: c.afLocked, enabled: caps.focusLock, onTap: c.toggleAfLock),
            KpPill(label: 'AE-L', active: c.aeLocked, enabled: caps.exposureLock, onTap: c.toggleAeLock),
            KpPill(label: '${c.zoom.toStringAsFixed(1)}×', enabled: caps.zoom, onTap: () => c.zoomTo(c.zoom >= 1.9 ? 1.0 : 2.0)),
            if (c.facing == 'front')
              KpPill(
                label: 'MIRROR',
                icon: Icons.flip,
                active: settings.frontPreviewMirror,
                color: KpColors.text,
                onTap: () => settings.update((s) => s.frontPreviewMirror = !s.frontPreviewMirror),
              ),
            if (roll != null)
              KpPill(
                label: 'ROLL ${roll >= 0 ? '+' : ''}${roll.toStringAsFixed(0)}°',
                active: settings.toolHorizon,
                color: KpColors.text,
                onTap: () => settings.update((s) => s.toolHorizon = !s.toolHorizon),
              ),
          ],
          if (ext.connected)
            KpPill(
              label: ext.state == ExternalOutputState.outputActive ? 'TV: CLEAN FEED' : 'TV: ПОДКЛЮЧЁН',
              icon: Icons.connected_tv,
              color: KpColors.live,
              onTap: () => showExternalDisplaySheet(context),
            ),
        ]),
      ),
    );
  }

  Widget _placeholder(CameraController c) {
    if (c.phase == CameraPhase.error) {
      return KpEmptyState(
        icon: Icons.videocam_off_outlined,
        title: 'Камера недоступна',
        message: c.error,
        action: c.permissionDenied
            ? KpButton(label: 'Открыть настройки', icon: Icons.settings, onPressed: openAppSettings)
            : KpButton(label: 'Повторить', icon: Icons.refresh, onPressed: c.openCamera),
      );
    }
    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
  }

  Widget _cameraLabel(CameraController c) {
    final rec = c.recorder.isRecording;
    final color = c.phase == CameraPhase.ready ? (rec ? KpColors.rec : KpColors.live) : KpColors.inactive;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      KpStatusDot(color: color, pulse: rec || c.phase == CameraPhase.opening),
      const SizedBox(width: 6),
      Text(c.isExternal ? 'EXTERNAL' : 'CAMERA', style: KpText.label.copyWith(color: color)),
    ]);
  }

  List<Widget> _formatItems(CameraController c, {bool compact = false}) {
    final (w, h) = c.captureSize;
    return [
      StripItem(resLabel(w, h)),
      StripItem('${c.capFps ?? '—'} fps'),
      if (!compact) const StripItem('H.264', bold: false),
    ];
  }

  Widget _timecode(CameraController c, {double size = 20}) {
    final rec = c.recorder.isRecording;
    return KpTimecode(
      anchor: rec ? c.recorder.startedAt : null,
      style: KpText.timecode.copyWith(fontSize: size),
      color: rec ? KpColors.rec : KpColors.textDim,
    );
  }

  List<Widget> _sysItems(CameraController c) => [
        StripItem(formatBytes(c.freeBytes), icon: Icons.sd_storage_outlined, bold: false),
        StripItem(batteryText(c.battery), icon: batteryIcon(c.battery), bold: false),
      ];

  Widget _menuButton(CameraController c) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: KpColors.text),
        color: KpColors.surface2,
        onSelected: (v) => _menu(c, v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'settings', child: Text('Настройки камеры')),
          PopupMenuItem(value: 'connect', child: Text('Подключение и QR')),
          PopupMenuItem(value: 'takes', child: Text('Дубли')),
          PopupMenuItem(value: 'diag', child: Text('Диагностика')),
        ],
      );

  void _menu(CameraController c, String v) {
    if (_locked) return;
    switch (v) {
      case 'settings':
        showCameraSettings(context, c);
      case 'connect':
        showConnectSheet(context, c);
      case 'takes':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TakesScreen()));
      case 'diag':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagnosticsScreen(camera: c)));
    }
  }

  Widget _rec(CameraController c, {double size = 76}) => RecButton(
        size: size,
        state: _recVisual(c),
        onPressed: _locked ? null : c.toggleLocalRec,
      );

  Widget _lockButton() => KpRoundButton(
        icon: _locked ? Icons.lock : Icons.lock_open,
        tooltip: _locked ? 'Разблокировать экран' : 'Заблокировать касания',
        active: _locked,
        activeColor: KpColors.warn,
        onTap: () => setState(() => _locked = !_locked),
      );

  Widget _connectionLine(CameraController c, {bool expanded = false}) {
    final peers = c.connectedPeers;
    final pending = c.peers.where((p) => p.phase != PeerPhase.connected).length;
    final s = c.senderStats;
    String text;
    Color color;
    if (peers.isEmpty) {
      color = KpColors.textDim;
      text = c.lanIp == null
          ? 'Нет локальной сети'
          : 'Ожидание монитора · ${c.lanIp}:${c.port ?? '—'}${pending > 0 ? ' · подключается: $pending' : ''}';
    } else {
      color = KpColors.live;
      final names = peers.map((p) => p.name).join(', ');
      final q = s == null ? '' : ' · ${fmtRes(s.width, s.height)} ${fmtFps(s.fps)} fps · ${fmtKbps(s.bitrateKbps)}';
      text = 'PLAYBACK: $names$q';
      if (s?.qualityLimitation != null && s!.qualityLimitation != 'none') {
        text += ' · ограничение: ${s.qualityLimitation}';
      }
    }
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(peers.isEmpty ? Icons.wifi_tethering : Icons.cast_connected, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: KpText.metricSmall.copyWith(color: color)),
        ),
      ],
    );
  }

  Widget _remoteChip(CameraController c) {
    final settings = AppScope.of(context).settings;
    final on = settings.remoteControlAllowed;
    return InkWell(
      onTap: _locked ? null : () => settings.update((s) => s.remoteControlAllowed = !s.remoteControlAllowed),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? Icons.settings_remote : Icons.block, size: 14, color: on ? KpColors.live : KpColors.textMute),
          const SizedBox(width: 4),
          Text(on ? 'Удалённый REC: разрешён' : 'Удалённый REC: запрещён',
              style: KpText.metricSmall.copyWith(color: on ? KpColors.live : KpColors.textDim)),
        ]),
      ),
    );
  }

  Widget _warnings(CameraController c) {
    final items = <Widget>[
      if (c.warning != null) KpBanner(text: c.warning!),
      if (c.recorder.lastError != null) KpBanner(text: c.recorder.lastError!, color: KpColors.rec),
      if (c.controlError != null) KpBanner(text: c.controlError!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: w)],
    );
  }

  Widget _lastTakeButton(CameraController c) {
    final t = c.recorder.lastTake;
    return InkWell(
      onTap: _locked ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TakesScreen())),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: KpColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KpColors.strokeStrong),
        ),
        child: t == null
            ? const Icon(Icons.video_library_outlined, size: 20, color: KpColors.textDim)
            : Center(
                child: Text(t.name.split('_').last,
                    style: KpText.metricSmall.copyWith(color: KpColors.text, fontSize: 10))),
      ),
    );
  }

  // ---------------------------------------------------------- landscape --
  Widget _landscape(CameraController c, KpFormFactor ff) {
    final railW = ff.isTablet ? 76.0 : 64.0;
    final recSize = ff.isTablet ? 84.0 : 70.0;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: StatusStrip(
              leading: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _locked ? null : _exit,
                  visualDensity: VisualDensity.compact,
                ),
                _cameraLabel(c),
                ..._formatItems(c),
                _timecode(c),
              ],
              trailing: [..._sysItems(c), _menuButton(c)],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: railW,
                  child: AbsorbPointer(
                    absorbing: _locked,
                    child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!c.isExternal) KpRoundButton(icon: Icons.cameraswitch_outlined, tooltip: 'Сменить камеру', onTap: c.recorder.isRecording ? null : c.switchCamera),
                        const SizedBox(height: 14),
                        KpRoundButton(
                          icon: Icons.grid_on,
                          tooltip: 'Инструменты',
                          onTap: () => showMonitorTools(context, settings: AppScope.of(context).settings),
                        ),
                        const SizedBox(height: 14),
                        KpRoundButton(icon: Icons.qr_code_2, tooltip: 'Подключение', onTap: () => showConnectSheet(context, c)),
                        const SizedBox(height: 14),
                        KpRoundButton(icon: Icons.tune, tooltip: 'Настройки камеры', onTap: () => showCameraSettings(context, c)),
                        const SizedBox(height: 14),
                        KpRoundButton(icon: Icons.connected_tv, tooltip: 'Внешний дисплей / AirPlay', onTap: () => showExternalDisplaySheet(context)),
                      ],
                    ))),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: _monitor(c)),
                      ),
                      Positioned(left: 8, top: 8, right: 8, child: _warnings(c)),
                      Positioned(left: 8, right: 8, bottom: 8, child: _controlStrip(c)),
                      if (_locked)
                        Positioned(
                          left: 8,
                          bottom: 44,
                          child: KpBanner(text: 'Экран заблокирован', color: KpColors.warn, icon: Icons.lock),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: railW + 24,
                  child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KpAudioMeter(level: c.hasAudio ? c.audioLevel : null, height: 80),
                      const SizedBox(height: 18),
                      _rec(c, size: recSize),
                      const SizedBox(height: 18),
                      _lockButton(),
                      const SizedBox(height: 12),
                      OrientationLockButton(settings: AppScope.of(context).settings),
                    ],
                  ))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            child: Row(
              children: [
                Expanded(child: _connectionLine(c, expanded: true)),
                _remoteChip(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- portrait --
  Widget _portrait(CameraController c, KpFormFactor ff) {
    final recSize = ff.isTablet ? 88.0 : 76.0;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: StatusStrip(
              leading: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _locked ? null : _exit),
                _cameraLabel(c),
                ..._formatItems(c, compact: true),
              ],
              trailing: [
                StripItem(batteryText(c.battery), icon: batteryIcon(c.battery), bold: false),
                IconButton(
                  icon: const Icon(Icons.cameraswitch_outlined),
                  onPressed: (_locked || c.recorder.isRecording) ? null : c.switchCamera,
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _monitor(c)),
                Positioned(left: 8, top: 8, right: 8, child: _warnings(c)),
                Positioned(left: 8, right: 8, bottom: 8, child: _controlStrip(c)),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(child: KpAudioMeter(level: c.hasAudio ? c.audioLevel : null, height: 90)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _timecode(c, size: 18),
                      const SizedBox(height: 2),
                      StripItem(formatBytes(c.freeBytes), icon: Icons.sd_storage_outlined, bold: false),
                    ],
                  ),
                ),
                _rec(c, size: recSize),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _lastTakeButton(c),
                      const SizedBox(width: 8),
                      _lockButton(),
                      const SizedBox(width: 8),
                      OrientationLockButton(settings: AppScope.of(context).settings, size: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              _connectionLine(c, expanded: true),
              Align(alignment: Alignment.centerLeft, child: _remoteChip(c)),
            ]),
          ),
          AbsorbPointer(
            absorbing: _locked,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: KpToolButton(
                    icon: Icons.grid_on,
                    label: 'Монитор', width: double.infinity,
                    onTap: () => showMonitorTools(context, settings: AppScope.of(context).settings),
                  )),
                  Expanded(child: KpToolButton(
                    icon: Icons.video_library_outlined,
                    label: 'Дубли', width: double.infinity,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TakesScreen())),
                  )),
                  Expanded(child: KpToolButton(icon: Icons.qr_code_2, label: 'Трансляция', width: double.infinity, onTap: () => showConnectSheet(context, c))),
                  Expanded(child: KpToolButton(icon: Icons.connected_tv, label: 'TV', width: double.infinity, onTap: () => showExternalDisplaySheet(context))),
                  Expanded(child: KpToolButton(icon: Icons.tune, label: 'Настройки', width: double.infinity, onTap: () => showCameraSettings(context, c))),
                  Expanded(child: KpToolButton(
                    icon: Icons.monitor_heart_outlined,
                    label: 'Диагн.', width: double.infinity,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiagnosticsScreen(camera: c))),
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
