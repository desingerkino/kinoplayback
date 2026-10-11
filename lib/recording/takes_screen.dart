import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/storage_info.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/widgets/kp_widgets.dart';
import '../core/widgets/rec_widgets.dart';
import '../network/stream_stats.dart';
import '../playback/playback_controller.dart';
import 'take_recorder.dart';
import 'takes.dart';

/// Takes list (reference screen 8). Metadata comes from the files
/// themselves; the "connected camera" tab asks the camera for its list.
class TakesScreen extends StatefulWidget {
  const TakesScreen({super.key, this.playback});
  final PlaybackController? playback;

  @override
  State<TakesScreen> createState() => _TakesScreenState();
}

class _TakesScreenState extends State<TakesScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.playback?.requestRemoteTakes();
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).takes;
    final pb = widget.playback;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дубли'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              repo.reload();
              pb?.requestRemoteTakes();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (pb != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: KpSegmented<int>(
                  values: const [0, 1],
                  selected: _tab,
                  labelOf: (i) => i == 0 ? 'Это устройство' : 'Подключённая камера',
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
            Expanded(
              child: _tab == 0 || pb == null
                  ? ListenableBuilder(
                      listenable: repo,
                      builder: (context, _) => _TakeList(
                        takes: repo.takes,
                        local: true,
                        onOpen: (t) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TakeDetailScreen(take: t))),
                      ),
                    )
                  : ListenableBuilder(
                      listenable: pb,
                      builder: (context, _) {
                        final list = pb.remoteTakes;
                        if (!pb.isLive) {
                          return const KpEmptyState(icon: Icons.link_off, title: 'Камера не подключена');
                        }
                        if (list == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        return _TakeList(takes: list, local: false, onOpen: null);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TakeList extends StatelessWidget {
  const _TakeList({required this.takes, required this.local, required this.onOpen});
  final List<Take> takes;
  final bool local;
  final void Function(Take t)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (takes.isEmpty) {
      return KpEmptyState(
        icon: Icons.movie_outlined,
        title: 'Записей пока нет',
        message: local
            ? 'Дубли появятся здесь после записи в режиме CAMERA или записи монитора в PLAYBACK.'
            : 'На камере нет записанных дублей.',
      );
    }
    final ff = formFactorOfContext(context);
    final cols = ff.isTablet && ff.isLandscape ? 2 : 1;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisExtent: 84,
        crossAxisSpacing: 12,
        mainAxisSpacing: 8,
      ),
      itemCount: takes.length,
      itemBuilder: (context, i) => _TakeTile(take: takes[i], local: local, onTap: onOpen == null ? null : () => onOpen!(takes[i])),
    );
  }
}

String _fmtDate(DateTime d) {
  const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

class _TakeTile extends StatelessWidget {
  const _TakeTile({required this.take, required this.local, this.onTap});
  final Take take;
  final bool local;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = take.facts;
    final tags = <String>[
      if (f?.durationMs != null) formatTimecode(Duration(milliseconds: f!.durationMs!)),
      if (f?.displayWidth != null) resLabel(f!.displayWidth, f.displayHeight),
      if (f?.fps != null) '${fmtFps(f!.fps)}fps',
      if (f?.videoCodec != null) f!.videoCodec!,
      if (f?.audioCodec != null) f!.audioCodec!,
      if (take.sizeBytes != null) formatBytes(take.sizeBytes),
    ];
    final thumb = take.thumbPath;
    return Material(
      color: KpColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 96,
                  height: 64,
                  child: (local && thumb != null && File(thumb).existsSync())
                      ? Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 192)
                      : const ColoredBox(
                          color: KpColors.surface3,
                          child: Icon(Icons.movie_outlined, color: KpColors.textMute),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Flexible(child: Text(take.name, overflow: TextOverflow.ellipsis, style: KpText.heading.copyWith(fontSize: 14))),
                      const SizedBox(width: 6),
                      KpTag(take.source == TakeSource.original ? 'ОРИГИНАЛ' : 'МОНИТОР',
                          color: take.source == TakeSource.original ? KpColors.live : KpColors.select, filled: true),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtDate(take.createdAt)} · ${take.deviceName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KpText.caption,
                    ),
                    const SizedBox(height: 4),
                    Text(tags.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: KpText.metricSmall),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (take.finalizeError != null || take.interrupted)
                    const Icon(Icons.error_outline, size: 18, color: KpColors.warn)
                  else if (take.savedToGallery)
                    const Icon(Icons.photo_library_outlined, size: 18, color: KpColors.live)
                  else if (take.galleryError != null)
                    const Icon(Icons.photo_library_outlined, size: 18, color: KpColors.warn),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays a local take and shows its real file facts.
class TakeDetailScreen extends StatefulWidget {
  const TakeDetailScreen({super.key, required this.take});
  final Take take;

  @override
  State<TakeDetailScreen> createState() => _TakeDetailScreenState();
}

class _TakeDetailScreenState extends State<TakeDetailScreen> {
  VideoPlayerController? _vp;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vp = VideoPlayerController.file(File(widget.take.videoPath));
    _vp = vp;
    vp.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Не удаётся воспроизвести: $e');
    });
    vp.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _vp?.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить ${widget.take.name}?'),
        content: const Text('Файл будет удалён из приложения. Копия в Фото / Галерее (если была сохранена) останется.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: KpColors.rec)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).takes.delete(widget.take);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveToGallery() async {
    setState(() => _saving = true);
    final repo = AppScope.of(context).takes;
    final ok = await saveTakeToGallery(repo, widget.take);
    if (!mounted) return;
    setState(() => _saving = false);
    showKpToast(context, ok ? 'Сохранено в Фото / Галерею' : (widget.take.galleryError ?? 'Ошибка'),
        color: ok ? KpColors.live : KpColors.warn);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.take;
    final f = t.facts;
    final vp = _vp;
    final ff = formFactorOfContext(context);
    final player = AspectRatio(
      aspectRatio: (vp != null && vp.value.isInitialized) ? vp.value.aspectRatio : 16 / 9,
      child: ColoredBox(
        color: KpColors.monitor,
        child: _error != null
            ? Center(child: Text(_error!, style: KpText.bodyDim, textAlign: TextAlign.center))
            : (vp == null || !vp.value.isInitialized)
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                    onTap: () => vp.value.isPlaying ? vp.pause() : vp.play(),
                    child: Stack(fit: StackFit.expand, children: [
                      VideoPlayer(vp),
                      if (!vp.value.isPlaying)
                        const Center(child: Icon(Icons.play_circle_outline, size: 56, color: Colors.white70)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(vp, allowScrubbing: true, colors: const VideoProgressColors(playedColor: KpColors.rec)),
                      ),
                    ]),
                  ),
      ),
    );
    final info = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (t.finalizeError != null) ...[KpBanner(text: t.finalizeError!, color: KpColors.rec), const SizedBox(height: 8)],
        if (t.interrupted) ...[
          const KpBanner(text: 'Поток прервался во время записи монитора — файл закрыт на моменте обрыва.'),
          const SizedBox(height: 8),
        ],
        KpSection(
          title: 'Файл (фактические параметры)',
          children: [
            KpRow(label: 'Тип', value: t.source == TakeSource.original ? 'Оригинал камеры' : 'Запись принятого потока'),
            KpRow(label: 'Разрешение', value: fmtRes(f?.displayWidth, f?.displayHeight)),
            KpRow(label: 'Частота кадров', value: f?.fps == null ? '—' : '${fmtFps(f!.fps)} к/с (средняя)'),
            KpRow(label: 'Видеокодек', value: f?.videoCodec ?? '—'),
            KpRow(label: 'Аудио', value: f?.audioCodec ?? 'нет'),
            KpRow(label: 'Длительность', value: f?.durationMs == null ? '—' : formatTimecode(Duration(milliseconds: f!.durationMs!))),
            KpRow(label: 'Размер', value: formatBytes(t.sizeBytes)),
            KpRow(label: 'Создан', value: _fmtDate(t.createdAt)),
            KpRow(label: 'Устройство', value: t.deviceName),
            if (t.remoteDevice != null) KpRow(label: 'Источник', value: t.remoteDevice),
          ],
        ),
        KpSection(
          title: 'Медиатека',
          children: [
            KpRow(
              label: t.savedToGallery ? 'Сохранено в Фото / Галерею' : (t.galleryError ?? 'Не сохранено'),
              valueColor: t.savedToGallery ? KpColors.live : KpColors.warn,
              trailing: t.savedToGallery
                  ? const Icon(Icons.check, color: KpColors.live, size: 18)
                  : TextButton(onPressed: _saving ? null : _saveToGallery, child: const Text('Сохранить')),
            ),
          ],
        ),
        KpButton(label: 'Удалить из приложения', icon: Icons.delete_outline, onPressed: _delete, foreground: KpColors.rec),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.name)),
      body: SafeArea(
        child: ff.isLandscape
            ? Row(children: [Expanded(flex: 3, child: Center(child: player)), Expanded(flex: 2, child: info)])
            : Column(children: [player, Expanded(child: info)]),
      ),
    );
  }
}
