# KINO PLAYBACK — архитектура

## Схема

```
CAMERA (iOS / Android)                                   PLAYBACK (iOS / Android)
┌───────────────────────────────┐                        ┌───────────────────────────────┐
│ getUserMedia (flutter_webrtc) │                        │ RTCVideoView (монитор)        │
│   ├─ превью                   │   WebRTC, DTLS-SRTP    │ FrameAnalyzer (зебра/FC/гисто)│
│   ├─ TakeRecorder → MP4       │ ─────────────────────▶ │ TakeRecorder → MP4 (монитор)  │
│   │   (оригинал, полный кадр) │   видео + звук         │ CommandTracker (REC камеры)   │
│   └─ RTP sender (scaleDownBy, │                        │                               │
│       maxBitrate, maxFps)     │ ◀───── data channel ── │ rec.start / rec.stop          │
│ RemoteCommandHandler          │ ── state / cmd.status ▶│ состояние только из snapshot  │
│ SignalingServer (WS :47800)   │ ◀── hello/offer/ice ── │ SignalingLink (WS)            │
│ Bonjour/NSD _kinoplayback._tcp│ ── mDNS ─────────────▶ │ CameraBrowser / QR / IP       │
└───────────────────────────────┘                        └───────────────────────────────┘
```

* Одно Flutter-приложение, обе роли на обеих платформах (iOS↔iOS, iOS↔Android, Android↔iOS, Android↔Android).
* Только локальная сеть: `iceServers: []`, без STUN/TURN, облака, аккаунтов.
* Протокол один и тот же Dart-код на обеих сторонах (`lib/protocol/`), покрыт тестами.

## Модули

| Папка | Что внутри |
|---|---|
| `lib/core/` | дизайн-система (`theme/`, `widgets/`), адаптивность (`layout/adaptive.dart`), журнал событий, свободное место через libc (FFI), сведения об устройстве |
| `lib/protocol/` | конверт сообщений v1, типы, стадии команд, снапшот состояния камеры |
| `lib/session/` | `CommandTracker` (PLAYBACK) и `RemoteCommandHandler` (CAMERA): идемпотентность, повторы, тайм-ауты |
| `lib/network/` | WebSocket-сигнализация, Bonjour/NSD, WebRTC-обвязка, разбор `getStats`, QR/IP |
| `lib/camera/` | режим CAMERA: контроллер, экран, листы настроек и подключения |
| `lib/playback/` | режим PLAYBACK: поиск камер, QR-сканер, контроллер, экран монитора |
| `lib/monitor/` | монитор: направляющие, кашетирование, Fit/Fill, анализ кадра |
| `lib/recording/` | запись дублей, MP4-инспектор (реальные параметры файла), список дублей, плеер |
| `lib/settings/`, `lib/diagnostics/` | настройки и экран «Сеть и диагностика» |
| `tool/patch_platforms.py` | права, Info.plist, Bonjour, ориентации, minSdk/iOS target для сгенерированных `ios/` и `android/` |

## Протокол v1

Конверт: `{"v":1,"t":"<type>","id":"<uid>","ts":<ms>,"sid":"<session>","p":{…}}`.

Сигнализация (WebSocket `ws://<ip>:<port>/kp`):
`hello` → (`pending`) → `welcome` | `reject` → `offer` ← `answer`, `ice` в обе стороны, `bye`.
Каждое новое устройство подтверждается на камере (диалог «Разрешить / Всегда доверять / Отклонить»).

Управление (data channel `kp-control`, шифруется DTLS):

| Тип | Направление | Смысл |
|---|---|---|
| `rec.start`, `rec.stop` | PLAYBACK → CAMERA | команда, `id` = ключ идемпотентности |
| `cmd.status` | CAMERA → PLAYBACK | `received` → `accepted` → `done` / `rejected` / `failed` |
| `state` | CAMERA → PLAYBACK | снапшот: REC, прошедшее время, клип, формат, разрешение пульта, батарея, место; при каждом изменении и каждые 2 с |
| `state.request` | PLAYBACK → CAMERA | запрос актуального снапшота (после (пере)подключения) |
| `takes.request` / `takes` | ↔ | список дублей камеры (метаданные, без файлов) |

Удалённый REC:
1. PLAYBACK проверяет соединение, наличие свежего снапшота и разрешение пульта.
2. Создаёт команду с уникальным `id`, отправляет; повтор с тем же `id` через 2 с, если нет `received` (максимум 2 повтора).
3. CAMERA отвечает `received`; при запрете — `rejected/remote_disabled`; иначе `accepted`, запускает рекордер и только после подтверждения нативного старта шлёт `done`.
4. Дубликаты `id` не выполняются повторно — CAMERA пересылает сохранённый итог.
5. Индикатор REC на PLAYBACK горит **только по снапшоту `state`**, не по нажатию и не по `done`.
6. Таймер PLAYBACK = `время получения − elapsed`, синхронизация часов устройств не нужна (погрешность ≈ задержка сети в одну сторону).
7. Потеря связи: команды в полёте → `failed/connection_lost`, состояние REC показывается как «неизвестно», запись оригинала на камере **не останавливается**.

## Оригинал и трансляция

Камера открывается в запрошенном формате оригинала. Трансляция уменьшается на RTP-отправителе (`scaleResolutionDownBy`, `maxBitrate`, `maxFramerate`) — разрешение захвата и оригинала от этого не меняется. Оригинал пишется из той же видеодорожки в полном размере кадра.

## v0.2 — новые модули

| Модуль | Файлы | Что делает |
|---|---|---|
| Айдентика | `tool/brand/*`, `assets/brand/*`, `lib/core/brand/*` | Единая геометрия знака K/Play: из неё генерируются SVG, PNG, иконки iOS и Android (adaptive + monochrome), launch screen, brand guide PDF и виджет `KpMark` |
| Блокировка ориентации | `lib/core/layout/orientation_lock.dart` | AUTO / PORTRAIT / LANDSCAPE LEFT / RIGHT в CAMERA и PLAYBACK. Меняется только интерфейс: запись, сессия и данные о наклоне не сбрасываются |
| Camera Motion Sync | `lib/motion/*` | CAMERA вычисляет крен по гравитации (акселерометр через фильтр низких частот, без дрейфа гироскопа) и отправляет по каналу данных `motion` (~15 Гц: seq, t, roll, quant). PLAYBACK (`CameraOrientationSync`) принимает только пакеты своей сессии и по порядку, разворачивает угол через ±180° и сглаживает. Режимы: AUTO SYNC, FOLLOW CAMERA ROLL, LOCK LANDSCAPE, LOCK PORTRAIT, MANUAL. Поворот применяется только при отображении |
| Фокус и экспозиция | `CameraController.setFocusAt/...`, `lib/motion/orientation_math.dart` (`tapToPicture`) | Касание переводится в координаты кадра с учётом fit/fill, зеркала, поворота и масштаба. Точки фокуса и экспозиции независимы. AF LOCK и AE LOCK работают только на iOS: на Android в flutter_webrtc AE LOCK не реализован. Есть pinch-zoom |
| Удалённое управление камерой | `cam.focus`, `cam.lock`, `cam.zoom` | Отдельное разрешение на CAMERA. Уникальный ID, подтверждения, защита от повторов — как у REC |
| Front camera mirror | настройки `frontPreviewMirror` / `recordingMirror` / `playbackMirror` | Три независимых переключателя. Зеркалирование только при отображении; `mir:false` в снапшоте исключает двойное отражение |
| Источник видео | `lib/app/source_screen.dart` | Сетевая камера или внешнее USB/UVC-устройство, которое видит система; CAMERA работает с ним так же: запись и раздача на PLAYBACK |
| Видеопередатчики | `lib/transmitters/*`, `docs/HARDWARE.md` | Каталог VAXIS и Accsoon с источниками, статусами, схемами A/B/C и журналом физических тестов |
| Внешний дисплей | `ios/Runner/AppDelegate.swift`, `MainActivity.kt`, `lib/external_display/*` | iOS: сцена с ролью external display (повтор экрана на Apple TV, HDMI-адаптер) рисует только видеодорожку WebRTC (RTCMTLVideoView), то есть CLEAN FEED. Android: `Presentation` с `SurfaceViewRenderer` на презентационном дисплее |

## Известные ограничения

* Оригинал пишется рекордером flutter_webrtc: H.264 в MP4. На iOS битрейт фиксирован (~6 Мбит/с) — для 4K это заметно ниже штатной «Камеры». HEVC, Log, ProRes не поддерживаются. Следующий шаг — нативный модуль захвата (AVCaptureSession + AVAssetWriter / CameraX + MediaCodec), который отдаёт кадры и в WebRTC, и в высокобитрейтный рекордер.
* На iPhone с несколькими камерами flutter_webrtc выбирает только форматы, совместимые с multi-cam; 4K может быть недоступен — приложение показывает фактически выбранный формат и предупреждение.
* Поворот кадра в файле оригинала не записывается в матрицу MP4 (рекордер flutter_webrtc). Основной сценарий — горизонтальная съёмка.
* Звук: в iOS-рекордере — моно AAC 44.1 кГц; на Android микрофон (оригинал) или принятый звук (монитор).
* В фоне ОС приостанавливает камеру; приложение предупреждает в журнале, восстановление — при возвращении.
* Сигнализация (обмен SDP) по LAN не шифруется; медиа и команды шифруются DTLS. Подмена в той же сети теоретически возможна до подтверждения на камере.
* Зебра / False Color / гистограмма считаются по декодированному кадру ≈2 раза в секунду, это не анализ сигнала сенсора.
* Индикатор горизонта и FOLLOW CAMERA ROLL используют датчик гравитации CAMERA. Направление крена на конкретной паре устройств нужно проверить: для калибровки есть настройка «Инвертировать крен».
* Повтор экрана на Apple TV включается только из Пункта управления: публичного API для запуска нет. Кнопка AirPlay для AVPlayer не подходит для живой камеры. Задержка AirPlay не измеряется.
* Chromecast не поддерживается: для живого потока приложения нужен собственный receiver.
* EV-компенсация, ISO, выдержка, баланс белого и ручная дистанция фокуса через текущий движок камеры недоступны и показаны как NOT AVAILABLE.
* Recording Mirror не поддерживается: рекордер не отражает кадры.

## Сборка

GitHub Actions (`.github/workflows/ci.yml`): analyze → тесты → APK + AAB (Ubuntu) и неподписанный IPA (macOS). Логи каждого прогона публикуются в ветки `ci-logs-*`.
