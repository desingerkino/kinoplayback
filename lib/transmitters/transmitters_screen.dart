import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../core/layout/adaptive.dart';
import '../core/theme/kp_colors.dart';
import '../core/theme/kp_text.dart';
import '../core/theme/kp_theme.dart';
import '../core/widgets/kp_widgets.dart';
import 'catalog.dart';
import 'schemes_screen.dart';
import 'test_log.dart';

Color statusColor(CompatStatus s) => switch (s) {
      CompatStatus.supportedTested => KpColors.live,
      CompatStatus.documented => KpColors.text,
      CompatStatus.partial => KpColors.warn,
      CompatStatus.sdkRequired => KpColors.warn,
      CompatStatus.hardwareRequired => KpColors.warn,
      CompatStatus.notVerified => KpColors.textDim,
      CompatStatus.notSupported => KpColors.rec,
    };

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.small = false});
  final CompatStatus status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Text(status.label, style: KpText.label.copyWith(fontSize: small ? 9 : 10, color: c, letterSpacing: 0.5)),
    );
  }
}

/// Effective status: a passed physical test upgrades to SUPPORTED & TESTED.
CompatStatus effectiveStatus(TransmitterModel m, Scenario s, TransmitterTestLog? log) {
  if (log != null && log.testedOk(m.id, s.code)) return CompatStatus.supportedTested;
  return m.scenarios[s]?.status ?? CompatStatus.notVerified;
}

class TransmittersScreen extends StatefulWidget {
  const TransmittersScreen({super.key});

  @override
  State<TransmittersScreen> createState() => _TransmittersScreenState();
}

class _TransmittersScreenState extends State<TransmittersScreen> {
  Vendor _vendor = Vendor.vaxis;
  String _q = '';
  final Set<ConnFilter> _conn = {};
  CompatStatus? _status;
  TransmitterTestLog? _log;

  @override
  void initState() {
    super.initState();
    TransmitterTestLog.open().then((l) {
      if (mounted) setState(() => _log = l);
    });
  }

  String _filterLabel(ConnFilter f) => switch (f) {
        ConnFilter.hdmi => 'HDMI',
        ConnFilter.sdi => 'SDI',
        ConnFilter.usbVideo => 'USB-видео',
        ConnFilter.uvc => 'UVC',
        ConnFilter.app => 'Приложение',
      };

  @override
  Widget build(BuildContext context) {
    final list = kTransmitters.where((m) {
      if (m.vendor != _vendor) return false;
      if (_q.isNotEmpty && !m.fullName.toLowerCase().contains(_q.toLowerCase())) return false;
      if (_conn.isNotEmpty && !_conn.every(m.filters.contains)) return false;
      if (_status != null && effectiveStatus(m, Scenario.b, _log) != _status) return false;
      return true;
    }).toList();
    final ff = formFactorOfContext(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Видеопередатчики'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen())),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: const Text('Схемы'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            KpSegmented<Vendor>(
              values: Vendor.values,
              selected: _vendor,
              labelOf: (v) => v == Vendor.vaxis ? 'VAXIS' : 'ACCSOON',
              onChanged: (v) => setState(() => _vendor = v),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Поиск модели', isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in ConnFilter.values)
                FilterChip(
                  label: Text(_filterLabel(f), style: KpText.caption.copyWith(color: KpColors.text)),
                  selected: _conn.contains(f),
                  showCheckmark: false,
                  selectedColor: KpColors.surface3,
                  backgroundColor: KpColors.surface2,
                  side: BorderSide(color: _conn.contains(f) ? KpColors.text : KpColors.stroke),
                  onSelected: (on) => setState(() => on ? _conn.add(f) : _conn.remove(f)),
                ),
              PopupMenuButton<String>(
                color: KpColors.surface2,
                onSelected: (v) => setState(() => _status = v == 'all' ? null : CompatStatus.values.byName(v)),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'all', child: Text('Любой статус')),
                  for (final s in CompatStatus.values) PopupMenuItem(value: s.name, child: Text(s.label)),
                ],
                child: Chip(
                  backgroundColor: KpColors.surface2,
                  side: BorderSide(color: _status == null ? KpColors.stroke : KpColors.text),
                  label: Text(_status == null ? 'Статус: все' : _status!.label, style: KpText.caption.copyWith(color: KpColors.text)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Статус в списке — для сценария B (видео с приёмника прямо в KINO PLAYBACK). '
              'SUPPORTED & TESTED появляется только после записи успешного физического теста.',
              style: KpText.caption,
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const KpEmptyState(icon: Icons.search_off, title: 'Ничего не найдено')
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: ff.isTablet && ff.isLandscape ? 2 : 1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 12,
                childAspectRatio: ff.isTablet && ff.isLandscape ? 5.2 : (MediaQuery.sizeOf(context).width / 84),
                children: [
                  for (final m in list)
                    _ModelRow(
                      model: m,
                      status: effectiveStatus(m, Scenario.b, _log),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransmitterCardScreen(model: m))),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String categoryLabel(DeviceCategory c) => switch (c) {
      DeviceCategory.txrx => 'TX / RX',
      DeviceCategory.transmitter => 'Передатчик',
      DeviceCategory.captureAdapter => 'Видеозахват',
    };

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.status, required this.onTap});
  final TransmitterModel model;
  final CompatStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KpColors.surface2,
      borderRadius: BorderRadius.circular(KpRadius.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(KpRadius.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: KpColors.surface3, borderRadius: BorderRadius.circular(6)),
              child: Icon(
                model.category == DeviceCategory.captureAdapter ? Icons.input : Icons.settings_input_antenna,
                color: KpColors.text,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(model.model, style: KpText.heading.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${categoryLabel(model.category)} · ${[
                    if (model.filters.contains(ConnFilter.hdmi)) 'HDMI',
                    if (model.filters.contains(ConnFilter.sdi)) 'SDI',
                    if (model.filters.contains(ConnFilter.uvc)) 'UVC',
                  ].join('/')}',
                  style: KpText.caption,
                ),
              ]),
            ),
            StatusBadge(status, small: true),
            const Icon(Icons.chevron_right, size: 18, color: KpColors.textMute),
          ]),
        ),
      ),
    );
  }
}

/// Equipment card (reference screen 6).
class TransmitterCardScreen extends StatefulWidget {
  const TransmitterCardScreen({super.key, required this.model});
  final TransmitterModel model;

  @override
  State<TransmitterCardScreen> createState() => _TransmitterCardScreenState();
}

class _TransmitterCardScreenState extends State<TransmitterCardScreen> {
  TransmitterTestLog? _log;

  @override
  void initState() {
    super.initState();
    TransmitterTestLog.open().then((l) {
      if (mounted) setState(() => _log = l);
    });
  }

  KpRow _spec(String label, String? v) => KpRow(
        label: label,
        value: v ?? 'NOT VERIFIED',
        valueColor: v == null ? KpColors.textMute : KpColors.text,
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final log = _log;
    final tests = log?.forModel(m.id) ?? const <TransmitterTest>[];
    return Scaffold(
      appBar: AppBar(title: Text(m.fullName)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: log ?? ValueNotifier(0),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(m.fullName, style: KpText.title),
              const SizedBox(height: 4),
              Text('${categoryLabel(m.category)} · ${m.summary}', style: KpText.bodyDim),
              const SizedBox(height: 14),
              KpSection(
                title: 'Совместимость с KINO PLAYBACK',
                children: [
                  for (final s in Scenario.values)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('Сценарий ${s.code}', style: KpText.label),
                          const SizedBox(width: 8),
                          StatusBadge(effectiveStatus(m, s, log), small: true),
                        ]),
                        const SizedBox(height: 4),
                        Text(s.title, style: KpText.caption.copyWith(color: KpColors.text)),
                        const SizedBox(height: 4),
                        Text(m.scenarios[s]?.note ?? 'Нет данных', style: KpText.caption),
                      ]),
                    ),
                ],
              ),
              KpSection(title: 'Характеристики (по документации)', children: [
                _spec('Входы TX', m.txInputs),
                if (m.txOutputs != null) _spec('Выходы TX', m.txOutputs),
                _spec('Выходы RX', m.rxOutputs),
                _spec('Форматы', m.formats),
                _spec('Задержка', m.latency),
                _spec('Дальность', m.range),
                _spec('Питание', m.power),
                _spec('Приложение', m.mobileApp),
                _spec('USB-видео', m.usbVideo),
                _spec('UVC', m.uvc),
                _spec('SDK / API', m.sdk),
                _spec('iOS / iPadOS', m.ios),
                _spec('Android', m.android),
              ]),
              if (m.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(children: [for (final n in m.notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: KpBanner(text: n, icon: Icons.info_outline))]),
                ),
              KpSection(
                title: 'Источники',
                footer: 'Нажмите, чтобы скопировать ссылку.',
                children: [
                  for (final s in m.sources)
                    KpRow(
                      label: s.title,
                      subtitle: s.url,
                      value: s.official ? 'официальный' : 'дилер',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: s.url));
                        showKpToast(context, 'Ссылка скопирована');
                      },
                    ),
                ],
              ),
              KpSection(
                title: 'Результаты физических тестов',
                footer: tests.isEmpty ? 'Тестов этой модели ещё нет. Статус TESTED появится только после записи успешного теста.' : null,
                children: [
                  for (final t in tests)
                    KpRow(
                      label: '${t.result.label} · сценарий ${t.scenario} · ${t.device}',
                      subtitle: [
                        '${t.platform} ${t.osVersion}',
                        t.connection,
                        if (t.cables.isNotEmpty) 'кабели: ${t.cables}',
                        if (t.signal.isNotEmpty) t.signal,
                        if (t.latencyMs != null) 'задержка ${t.latencyMs} мс (измерено)',
                        if (t.stability.isNotEmpty) t.stability,
                        if (t.notes.isNotEmpty) t.notes,
                        '${t.date.day}.${t.date.month.toString().padLeft(2, '0')}.${t.date.year}',
                      ].join(' · '),
                      valueColor: t.result == TestResult.passed ? KpColors.live : KpColors.warn,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => log?.remove(t.id),
                      ),
                    ),
                  KpRow(
                    label: 'Добавить результат теста',
                    leading: const Icon(Icons.add, size: 18, color: KpColors.text),
                    onTap: log == null ? null : () => _addTest(context, m, log),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addTest(BuildContext context, TransmitterModel m, TransmitterTestLog log) async {
    final id = AppScope.of(context).identity;
    final f = <String, TextEditingController>{
      'device': TextEditingController(text: id.model),
      'os': TextEditingController(text: '${id.platform} ${id.osVersion}'),
      'conn': TextEditingController(),
      'cables': TextEditingController(),
      'signal': TextEditingController(),
      'lat': TextEditingController(),
      'stab': TextEditingController(),
      'notes': TextEditingController(),
    };
    var scenario = 'B';
    var result = TestResult.passed;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Тест: ${m.fullName}', style: KpText.heading),
                const SizedBox(height: 10),
                KpSegmented<String>(
                  values: const ['A', 'B', 'C'],
                  selected: scenario,
                  labelOf: (s) => 'Сценарий $s',
                  onChanged: (s) => setLocal(() => scenario = s),
                ),
                const SizedBox(height: 8),
                KpSegmented<TestResult>(
                  values: TestResult.values,
                  selected: result,
                  labelOf: (r) => r.label,
                  onChanged: (r) => setLocal(() => result = r),
                ),
                const SizedBox(height: 8),
                for (final e in {
                  'device': 'Устройство (телефон / планшет)',
                  'os': 'Платформа и версия ОС',
                  'conn': 'Способ подключения (напр. RX UVC → USB-C → iPad)',
                  'cables': 'Кабели и адаптеры',
                  'signal': 'Формат сигнала, разрешение, FPS',
                  'lat': 'Измеренная задержка, мс (если измеряли)',
                  'stab': 'Стабильность',
                  'notes': 'Ограничения / заметки',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: f[e.key],
                      keyboardType: e.key == 'lat' ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(labelText: e.value, isDense: true),
                    ),
                  ),
                KpButton(label: 'Сохранить', onPressed: () => Navigator.pop(context, true), color: KpColors.surface3, expand: true),
              ]),
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      final parts = f['os']!.text.trim().split(' ');
      await log.add(TransmitterTest(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        modelId: m.id,
        date: DateTime.now(),
        scenario: scenario,
        device: f['device']!.text.trim(),
        platform: parts.isEmpty ? '' : parts.first,
        osVersion: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        connection: f['conn']!.text.trim(),
        cables: f['cables']!.text.trim(),
        signal: f['signal']!.text.trim(),
        result: result,
        latencyMs: int.tryParse(f['lat']!.text.trim()),
        stability: f['stab']!.text.trim(),
        notes: f['notes']!.text.trim(),
      ));
    }
    for (final c in f.values) {
      c.dispose();
    }
  }
}
