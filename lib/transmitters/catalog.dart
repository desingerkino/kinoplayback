/// VIDEO TRANSMITTERS catalogue.
///
/// Every value below comes from the cited source (official page first,
/// dealer listing when the manufacturer publishes no spec sheet). Anything
/// not stated in a source is `null` and shown as NOT VERIFIED — never
/// guessed. No model is marked SUPPORTED & TESTED: that status is only
/// possible after a physical test recorded in the test log.
library;

enum Vendor { vaxis, accsoon }

enum DeviceCategory { txrx, transmitter, captureAdapter }

/// Compatibility status for a scenario (brand guide statuses).
enum CompatStatus { supportedTested, documented, partial, sdkRequired, hardwareRequired, notVerified, notSupported }

extension CompatStatusX on CompatStatus {
  String get label => switch (this) {
        CompatStatus.supportedTested => 'SUPPORTED & TESTED',
        CompatStatus.documented => 'DOCUMENTED',
        CompatStatus.partial => 'PARTIALLY SUPPORTED',
        CompatStatus.sdkRequired => 'SDK REQUIRED',
        CompatStatus.hardwareRequired => 'HARDWARE REQUIRED',
        CompatStatus.notVerified => 'NOT VERIFIED',
        CompatStatus.notSupported => 'NOT SUPPORTED',
      };
}

/// The three ways a transmitter relates to KINO PLAYBACK.
enum Scenario { a, b, c }

extension ScenarioX on Scenario {
  String get code => switch (this) { Scenario.a => 'A', Scenario.b => 'B', Scenario.c => 'C' };
  String get title => switch (this) {
        Scenario.a => 'Телефон CAMERA → TX → RX → монитор',
        Scenario.b => 'RX → USB / UVC → KINO PLAYBACK',
        Scenario.c => 'Мониторинг в приложении производителя',
      };
}

enum ConnFilter { hdmi, sdi, usbVideo, uvc, app }

class SourceRef {
  const SourceRef(this.title, this.url, {this.official = false});
  final String title;
  final String url;
  final bool official;
}

class ScenarioStatus {
  const ScenarioStatus(this.status, this.note);
  final CompatStatus status;
  final String note;
}

class TransmitterModel {
  const TransmitterModel({
    required this.id,
    required this.vendor,
    required this.model,
    required this.category,
    required this.summary,
    this.txInputs,
    this.txOutputs,
    this.rxOutputs,
    this.formats,
    this.latency,
    this.range,
    this.power,
    this.mobileApp,
    this.usbVideo,
    this.uvc,
    this.sdk,
    this.ios,
    this.android,
    this.notes = const [],
    required this.scenarios,
    required this.sources,
    this.filters = const {},
  });

  final String id;
  final Vendor vendor;
  final String model;
  final DeviceCategory category;
  final String summary;
  final String? txInputs;
  final String? txOutputs;
  final String? rxOutputs;
  final String? formats;
  final String? latency;
  final String? range;
  final String? power;
  final String? mobileApp;
  final String? usbVideo;
  final String? uvc;
  final String? sdk;
  final String? ios;
  final String? android;
  final List<String> notes;
  final Map<Scenario, ScenarioStatus> scenarios;
  final List<SourceRef> sources;
  final Set<ConnFilter> filters;

  String get vendorName => vendor == Vendor.vaxis ? 'VAXIS' : 'Accsoon';
  String get fullName => '$vendorName $model';

  /// The status shown on the list row: the KINO PLAYBACK input scenario (B).
  CompatStatus get kinoStatus => scenarios[Scenario.b]?.status ?? CompatStatus.notVerified;
}

const _scenarioA = ScenarioStatus(
  CompatStatus.hardwareRequired,
  'TX принимает HDMI/SDI. Телефон должен выдавать видео: iPhone — через адаптер USB-C→HDMI или Lightning Digital AV; '
  'Android — только модели с DisplayPort Alt Mode. KINO PLAYBACK выводит туда чистое изображение камеры (раздел «Внешний дисплей»).',
);

const List<TransmitterModel> kTransmitters = [
  // ------------------------------------------------------------------ VAXIS
  TransmitterModel(
    id: 'vaxis-atom-500-sdi',
    vendor: Vendor.vaxis,
    model: 'ATOM 500 SDI',
    category: DeviceCategory.txrx,
    summary: 'Комплект TX/RX, 3G-SDI и HDMI, мониторинг в ATOM APP.',
    txInputs: '1× BNC 3G-SDI, 1× HDMI 1.4',
    rxOutputs: '1× BNC SDI, 1× HDMI',
    formats: 'SDI: 1080p 25/29.97/30/50/59.94/60, 1080i 50/59.94, 720p60; HDMI: 1080p 24/25/30/50/60, 1080i 50/60, 720p60',
    latency: '< 80 мс',
    range: '500 ft (152 м), прямая видимость',
    power: 'USB-C 5 В на TX и RX; NP-F; TX ≈ 6.5 Вт',
    mobileApp: 'ATOM APP: iPhone (Android — «скоро»), до 3 мобильных устройств',
    usbVideo: 'Нет (USB-C — питание и прошивка)',
    uvc: 'Не указан',
    sdk: 'Не найден',
    ios: 'Только через приложение производителя',
    android: 'Не заявлено',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired,
          'USB-видеовыхода нет. Нужен внешний захват HDMI/SDI → UVC, подключённый к iPad (iPadOS 17+) или Android с поддержкой UVC.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'ATOM APP, до 3 устройств по Wi-Fi от TX.'),
    },
    sources: [
      SourceRef('CineGearPro — ATOM 500 SDI/HDMI', 'https://cinegearpro.co.uk/products/vaxis-atom-500-sdi-hdmi-wireless-video-transmission-system'),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'vaxis-atom-500-hdmi',
    vendor: Vendor.vaxis,
    model: 'ATOM 500 HDMI',
    category: DeviceCategory.txrx,
    summary: 'Комплект TX/RX, HDMI, кодирование H.265, ATOM APP на iOS.',
    txInputs: '1× HDMI',
    rxOutputs: '2× HDMI',
    formats: null,
    latency: null,
    range: '500 ft, прямая видимость',
    power: 'USB-C (можно от powerbank); опциональные площадки под батареи',
    mobileApp: 'ATOM APP (iOS), до 3 iPhone/iPad одновременно',
    usbVideo: 'Нет (USB-C — питание и прошивка)',
    uvc: 'Не указан',
    sdk: 'Не найден',
    ios: 'Только через ATOM APP',
    android: 'Не заявлено',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'ATOM APP (iOS), до 3 устройств.'),
    },
    sources: [
      SourceRef('CineGearPro — ATOM 500 HDMI', 'https://www.cinegearpro.co.uk/products/vaxis-atom-500-hdmi-wireless-video-transmission-system'),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'vaxis-atom-600-hdmi',
    vendor: Vendor.vaxis,
    model: 'ATOM 600 HDMI',
    category: DeviceCategory.txrx,
    summary: 'Комплект TX/RX HDMI, до 2 приёмников + 3 мобильных устройств.',
    txInputs: '1× HDMI, 1× HDMI loop-out',
    rxOutputs: '2× HDMI',
    formats: '1080p до 60, 1080i, 720p',
    latency: '< 80 мс',
    range: '600 ft (183 м), прямая видимость',
    power: 'TX 5 Вт, RX 3 Вт; USB-C 5 В вход/выход',
    mobileApp: 'Приложение Vaxis, до 3 мобильных устройств (платформы на странице не указаны)',
    usbVideo: 'Нет (USB-C — питание и прошивка)',
    uvc: 'Не указан',
    sdk: 'Не найден',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.notVerified, 'Приложение заявлено, платформы не подтверждены.'),
    },
    sources: [SourceRef('Syntex — ATOM 600 HDMI kit', 'https://www.syntex.tv/vaxis-atom-600-hdmi-1tx-1rx-kit')],
    filters: {ConnFilter.hdmi, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'vaxis-storm-1000s',
    vendor: Vendor.vaxis,
    model: 'STORM 1000S',
    category: DeviceCategory.txrx,
    summary: 'Профессиональный TX/RX SDI/HDMI с задержкой < 1 мс.',
    txInputs: '1× 3G-SDI, 1× 3G-SDI loop-out, 1× HDMI',
    rxOutputs: '2× 3G-SDI, 1× HDMI',
    formats: '1080p 23.98–60, 1080i 50–60, 1080PsF 23.98–30, 720p 50–60, 525i/625i',
    latency: '< 1 мс (поддержка ARRI 0S)',
    range: '350 м, прямая видимость; 20 каналов 5.1–5.9 ГГц',
    power: '7–36 В DC (2-pin LEMO) или Micro-USB; RX с площадкой V-Mount',
    mobileApp: 'Не указано',
    usbVideo: 'Нет',
    uvc: 'Не указан',
    sdk: 'Не найден',
    notes: ['Дилер (Syntex) отмечает модель как снятую с производства.'],
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват SDI/HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.notSupported, 'Мобильный мониторинг не заявлен.'),
    },
    sources: [
      SourceRef('Syntex — STORM 1000S', 'https://www.syntex.tv/vaxis-storm-1000s-wireless-kit-v-mount'),
      SourceRef('VAXIS store — STORM 1000S kit',
          'https://store.vaxisglobal.com/Vaxis-Storm-1000s-Kit-Zero-Delay-Wireless-Video-Transmission-p10716507.html',
          official: true),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi},
  ),
  TransmitterModel(
    id: 'vaxis-storm-3000',
    vendor: Vendor.vaxis,
    model: 'STORM 3000',
    category: DeviceCategory.txrx,
    summary: 'TX/RX SDI/HDMI, несжатый 1080p, до 1000 м.',
    txInputs: 'HDMI, 3G-SDI (BNC), SDI loop-out',
    rxOutputs: null,
    formats: '1080p 23.98–60, 1080i 50–60, 1080psf 23.98–30, 720p 50–60, 576p',
    latency: '< 1 мс',
    range: 'до 1000 м (3000 ft) вне помещений',
    power: '6–36 В DC, 2-pin LEMO',
    mobileApp: 'Не указано',
    usbVideo: 'Нет',
    uvc: 'Не указан',
    sdk: 'Не найден',
    notes: ['Adorama отмечает передатчик как недоступный к заказу.'],
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват SDI/HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.notSupported, 'Мобильный мониторинг не заявлен.'),
    },
    sources: [
      SourceRef('Adorama — STORM 3000 TX', 'https://www.adorama.com/la193000t01.html'),
      SourceRef('VAXIS store — STORM 3000 kit',
          'https://store.vaxisglobal.com/Vaxis-Storm-3000-Zero-Delay-Wireless-Video-Transmission-Kit-p3089664.html',
          official: true),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi},
  ),
  TransmitterModel(
    id: 'vaxis-storm-3000-dv',
    vendor: Vendor.vaxis,
    model: 'STORM 3000 DV',
    category: DeviceCategory.txrx,
    summary: 'TX с двойной площадкой V-Mount, совместим со всеми приёмниками Storm.',
    txInputs: '1× SDI, 1× HDMI, SDI loop-out; встроенный конвертер HDMI/SDI',
    rxOutputs: null,
    formats: 'Full HD 1080p без сжатия (полный список не опубликован)',
    latency: '«Zero delay», режим 0s для ARRI Alexa Mini (значение в мс не указано)',
    range: 'до 3000 ft (≈1 км), прямая видимость',
    power: 'Двойная площадка V-Mount с проходным питанием',
    mobileApp: 'Не указано',
    usbVideo: 'Нет (USB — только прошивка)',
    uvc: 'Не указан',
    sdk: 'Не найден',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват SDI/HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.notSupported, 'Мобильный мониторинг не заявлен.'),
    },
    sources: [
      SourceRef('CineGearPro — STORM 3000 DV TX', 'https://cinegearpro.co.uk/products/vaxis-storm-3000-dv-tx'),
      SourceRef('VAXIS store — STORM 3000 DV', 'https://store.vaxisglobal.com/Vaxis-Storm-3000-DV-p2529283.html',
          official: true),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi},
  ),
  TransmitterModel(
    id: 'vaxis-storm-3000-dg',
    vendor: Vendor.vaxis,
    model: 'STORM 3000 DG',
    category: DeviceCategory.txrx,
    summary: 'TX с двойной площадкой Gold Mount, несжатый 1080p60.',
    txInputs: '1× 3G-SDI, 1× HDMI (один вход одновременно), SDI loop-out',
    rxOutputs: null,
    formats: 'Несжатый до 1080p60',
    latency: '«Близко к 0 мс»',
    range: 'до 3000 ft (900 м), прямая видимость; 5 ГГц',
    power: 'Двойная площадка Gold Mount с проходным питанием, вход 2-pin LEMO',
    mobileApp: 'Не указано',
    usbVideo: 'Не указан',
    uvc: 'Не указан',
    sdk: 'Не найден',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.hardwareRequired, 'Нужен захват SDI/HDMI → UVC с выхода RX.'),
      Scenario.c: ScenarioStatus(CompatStatus.notSupported, 'Мобильный мониторинг не заявлен.'),
    },
    sources: [
      SourceRef('Syntex — STORM 3000 DG TX', 'https://www.syntex.tv/vaxis-storm-3000-dg-tx'),
      SourceRef('VAXIS store — STORM 3000 DG', 'https://store.vaxisglobal.com/Vaxis-Storm-3000-DG-p2529632.html',
          official: true),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi},
  ),

  // ---------------------------------------------------------------- ACCSOON
  TransmitterModel(
    id: 'accsoon-cineview-2-sdi',
    vendor: Vendor.accsoon,
    model: 'CineView 2 SDI',
    category: DeviceCategory.txrx,
    summary: 'TX/RX HDMI + 3G-SDI; приёмник имеет выход UVC — основной кандидат для прямого ввода в KINO PLAYBACK.',
    txInputs: 'HDMI, 3G-SDI; HDMI loop-out',
    rxOutputs: 'HDMI, 3G-SDI, UVC',
    formats: 'Вход HDMI до 4096×2160/3840×2160 23.98–60p; SDI 1080p до 60; выход RX: 1080p 24–60, 1080i, 720p',
    latency: '< 50 мс (без учёта задержки камеры)',
    range: '1500 ft / 450 м без препятствий',
    power: 'DC 7.4–16.8 В, NP-F, USB-C 5 В/2 А; TX < 6 Вт, RX < 5 Вт',
    mobileApp: 'Accsoon SEE (iOS/Android); до 4 приёмников/смарт-устройств на TX',
    usbVideo: 'UVC на приёмнике (разрешение/FPS UVC не опубликованы)',
    uvc: 'Да, выход RX (документировано)',
    sdk: 'Accsoon объявляет CineView SDK; доступ по заявке (SDK Launch Request)',
    ios: 'iPad с USB-C и iPadOS 17+ — внешние UVC-камеры поддерживаются системой; iPhone — нет (Apple DTS)',
    android: 'Только устройства, у которых Camera2 отдаёт внешние USB-камеры',
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.documented,
          'UVC-выход RX документирован. В KINO PLAYBACK: «Источник видео» → внешняя USB-камера. Требует физической проверки на iPad/Android.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'Accsoon SEE, iOS и Android.'),
    },
    sources: [
      SourceRef('Accsoon — CineView 2 SDI', 'https://accsoon.com/cineview-2-sdi/', official: true),
      SourceRef('Accsoon — SDK partners', 'https://accsoon.com/accsoon-sdk-partners/', official: true),
      SourceRef('Apple Developer Forums — external cameras on iPhone', 'https://developer.apple.com/forums/thread/775883'),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.uvc, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'accsoon-cineview-se-4k',
    vendor: Vendor.accsoon,
    model: 'CineView SE 4K',
    category: DeviceCategory.txrx,
    summary: 'TX/RX 4K30 HDMI + 3G-SDI, USB-видеовыход на TX и RX, проводной мониторинг смартфона.',
    txInputs: 'HDMI (UHD 4K 23.98–30p, 1080p до 60), 3G-SDI (1080p до 60)',
    rxOutputs: 'HDMI (4K до 30p, 1080p до 60), 3G-SDI (1080p до 60, Level A); USB-C Video',
    formats: 'Кодирование H.264/H.265, до 4K30; RX выдаёт только прогрессив',
    latency: '< 50 мс 1080p; < 100 мс 4K30 (TX→RX и TX→iOS)',
    range: '400 м (1300 ft) без препятствий',
    power: 'DC 7.4–16.8 В, NP-F; ≈ 4.4 Вт (TX)',
    mobileApp: 'Accsoon SEE (iOS/Android); до 5 подключений (1 проводное + 4 беспроводных)',
    usbVideo: 'USB-C Video output на TX и RX',
    uvc: 'Класс UVC на странице не указан',
    sdk: 'Для модели не описан',
    ios: 'Через Accsoon SEE (проводной и Wi-Fi мониторинг)',
    android: 'Через Accsoon SEE',
    notes: ['При 4K-входе HDMI выход SDI недоступен.', 'На странице есть расхождение по дальности: 1500 ft в описании и 1300 ft в таблице.'],
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.notVerified,
          'USB-видеовыход есть, но UVC не подтверждён — возможно, только для Accsoon SEE. Нужна проверка: определяется ли RX как USB-камера на iPad/Android.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'Accsoon SEE, проводной и беспроводной мониторинг.'),
    },
    sources: [SourceRef('Accsoon — CineView SE 4K', 'https://accsoon.com/cineview-se-4k/', official: true)],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.usbVideo, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'accsoon-cineeye-2s-pro',
    vendor: Vendor.accsoon,
    model: 'CineEye 2S Pro',
    category: DeviceCategory.transmitter,
    summary: 'Двухдиапазонный Wi-Fi передатчик SDI/HDMI для мониторинга на смартфонах.',
    txInputs: 'SDI, HDMI',
    mobileApp: 'Accsoon Go (iOS / Android 8.0+)',
    usbVideo: 'Не указан',
    uvc: 'Не указан',
    sdk: 'Для модели не описан',
    notes: ['Выходы, форматы, задержка, дальность и питание на странице поддержки не указаны — см. руководство v3.0 (PDF).'],
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.sdkRequired, 'Поток доступен только приложению производителя; сторонний доступ — только через SDK.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'Accsoon Go.'),
    },
    sources: [SourceRef('Accsoon support — CineEye 2S Pro', 'https://accsoon.com/support-center/cineeye-2s-pro/', official: true)],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'accsoon-cineview-quad',
    vendor: Vendor.accsoon,
    model: 'CineView QUAD',
    category: DeviceCategory.txrx,
    summary: 'Двухдиапазонная система TX/RX SDI/HDMI (2.4/5 ГГц), мониторинг в Accsoon SEE.',
    txInputs: 'SDI, HDMI',
    mobileApp: 'Accsoon SEE (App Store / Google Play), подключение к Wi-Fi «Accsoon ****»',
    usbVideo: 'Не указан',
    uvc: 'Не указан',
    sdk: 'Для модели не описан',
    notes: ['Выходы RX, форматы и задержка на странице поддержки не указаны.'],
    scenarios: {
      Scenario.a: _scenarioA,
      Scenario.b: ScenarioStatus(CompatStatus.notVerified, 'Нет документированного интерфейса для сторонних приложений.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'Accsoon SEE по Wi-Fi.'),
    },
    sources: [SourceRef('Accsoon support — CineView QUAD', 'https://accsoon.com/support-center/cineview-quad/', official: true)],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.app},
  ),
  TransmitterModel(
    id: 'accsoon-seemo-pro',
    vendor: Vendor.accsoon,
    model: 'SeeMo Pro',
    category: DeviceCategory.captureAdapter,
    summary: 'Внешний видеозахват SDI/HDMI → iPhone/iPad (не беспроводной передатчик).',
    txInputs: 'SDI (с loop-out), HDMI',
    txOutputs: 'USB-C OUT к iPhone/iPad (кабели USB-C→Lightning и USB-C→USB-C в комплекте)',
    formats: 'Вход SDI/HDMI 1080p 23.98–60, 720p 50–60; выход 1080p 24–60, 720p 50/60',
    power: 'NP-F, DC 6.4–16.8 В; заряжает iPhone/iPad (USB-C 5 В/3 А); 3.5 Вт',
    mobileApp: 'Работает вместе с Accsoon SEE; запись H.264 HD',
    usbVideo: 'USB-C OUT',
    uvc: 'Не указан',
    sdk: 'Сторонние приложения — партнёры Accsoon SDK (Switcher Studio, Prolycht и др.)',
    ios: 'iOS 12+, iPhone 8 и новее, iPad 6 и новее',
    android: 'Нет (для Android — отдельная модель SeeMo 4K)',
    scenarios: {
      Scenario.a: ScenarioStatus(CompatStatus.notSupported, 'Это захват в телефон, а не передатчик.'),
      Scenario.b: ScenarioStatus(CompatStatus.sdkRequired,
          'Видео в сторонних приложениях доступно через Accsoon SDK (партнёрская программа). Без SDK интеграция невозможна.'),
      Scenario.c: ScenarioStatus(CompatStatus.documented, 'Accsoon SEE.'),
    },
    sources: [
      SourceRef('Accsoon — SeeMo Pro', 'https://accsoon.com/accsoon-seemo-pro/', official: true),
      SourceRef('Accsoon — SDK partners', 'https://accsoon.com/accsoon-sdk-partners/', official: true),
    ],
    filters: {ConnFilter.hdmi, ConnFilter.sdi, ConnFilter.usbVideo, ConnFilter.app},
  ),
];
