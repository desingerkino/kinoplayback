# VAXIS и Accsoon: совместимость с KINO PLAYBACK

Данные взяты только из указанных источников (дата проверки: 11.10.2026). Если параметра в источнике нет, он помечен как **NOT VERIFIED**. Ни одна модель не проверена на физическом оборудовании, поэтому статуса SUPPORTED & TESTED нет ни у одной. Он появляется в приложении только после записи успешного теста в карточке модели («Добавить результат теста»).

## Сценарии

* **A — телефон CAMERA → TX → RX → монитор.** Передатчику нужен HDMI/SDI. У iPhone видеовыход есть только через адаптер (USB-C → HDMI или Lightning Digital AV), у Android — только на моделях с DisplayPort Alt Mode. KINO PLAYBACK выводит на внешний экран чистое изображение камеры (CLEAN FEED). Статус для всех моделей: HARDWARE REQUIRED.
* **B — RX → USB/UVC → KINO PLAYBACK.** Работает только с приёмником, у которого есть UVC-выход, и только на устройстве, которое система умеет подключать как внешнюю камеру:
  * iPad с USB-C и iPadOS 17+ — да.
  * iPhone — нет (подтверждено Apple DTS).
  * Android — зависит от модели: устройство должно отдавать внешние камеры через Camera2.
* **C — фирменное приложение производителя.** Видеопоток виден только в Accsoon SEE, Accsoon Go или ATOM APP. Стороннему приложению он доступен только через официальный SDK.

## Сводка

| Модель | Тип | Входы TX | Выходы RX | USB / UVC | Сценарий B | Источник |
|---|---|---|---|---|---|---|
| VAXIS ATOM 500 SDI | TX/RX | 3G-SDI, HDMI 1.4 | SDI, HDMI | нет (USB-C — питание) | HARDWARE REQUIRED | [CineGearPro](https://cinegearpro.co.uk/products/vaxis-atom-500-sdi-hdmi-wireless-video-transmission-system) |
| VAXIS ATOM 500 HDMI | TX/RX | HDMI | 2× HDMI | нет | HARDWARE REQUIRED | [CineGearPro](https://www.cinegearpro.co.uk/products/vaxis-atom-500-hdmi-wireless-video-transmission-system) |
| VAXIS ATOM 600 HDMI | TX/RX | HDMI + loop | 2× HDMI | нет | HARDWARE REQUIRED | [Syntex](https://www.syntex.tv/vaxis-atom-600-hdmi-1tx-1rx-kit) |
| VAXIS STORM 1000S | TX/RX | 3G-SDI + loop, HDMI | 2× SDI, HDMI | нет | HARDWARE REQUIRED | [Syntex](https://www.syntex.tv/vaxis-storm-1000s-wireless-kit-v-mount) |
| VAXIS STORM 3000 | TX/RX | HDMI, SDI + loop | NOT VERIFIED | нет | HARDWARE REQUIRED | [Adorama](https://www.adorama.com/la193000t01.html) |
| VAXIS STORM 3000 DV | TX/RX | SDI, HDMI, SDI loop | NOT VERIFIED | нет | HARDWARE REQUIRED | [CineGearPro](https://cinegearpro.co.uk/products/vaxis-storm-3000-dv-tx) |
| VAXIS STORM 3000 DG | TX/RX | 3G-SDI / HDMI, SDI loop | NOT VERIFIED | NOT VERIFIED | HARDWARE REQUIRED | [Syntex](https://www.syntex.tv/vaxis-storm-3000-dg-tx) |
| Accsoon CineView 2 SDI | TX/RX | HDMI, 3G-SDI | HDMI, 3G-SDI, **UVC** | UVC на RX | **DOCUMENTED** | [accsoon.com](https://accsoon.com/cineview-2-sdi/) |
| Accsoon CineView SE 4K | TX/RX | HDMI 4K30, 3G-SDI | HDMI, SDI, USB-C Video | USB-видео есть, UVC не указан | NOT VERIFIED | [accsoon.com](https://accsoon.com/cineview-se-4k/) |
| Accsoon CineEye 2S Pro | TX | SDI, HDMI | — | NOT VERIFIED | SDK REQUIRED | [accsoon.com](https://accsoon.com/support-center/cineeye-2s-pro/) |
| Accsoon CineView QUAD | TX/RX | SDI, HDMI | NOT VERIFIED | NOT VERIFIED | NOT VERIFIED | [accsoon.com](https://accsoon.com/support-center/cineview-quad/) |
| Accsoon SeeMo Pro | видеозахват | SDI + loop, HDMI | USB-C OUT → iPhone/iPad | UVC не указан | SDK REQUIRED | [accsoon.com](https://accsoon.com/accsoon-seemo-pro/) |

Полные характеристики (форматы, задержка, дальность, питание, приложения), а также дилерские и официальные ссылки собраны в приложении: раздел «Сендеры», карточка модели. Тот же набор данных лежит в `lib/transmitters/catalog.dart`.

SDK: Accsoon принимает заявки на SDK через [партнёрскую программу](https://accsoon.com/accsoon-sdk-partners/). Публичный SDK VAXIS не найден.

## Что нужно для физической проверки сценария B

1. Accsoon CineView 2 SDI (TX + RX) и камера с выходом HDMI или SDI.
2. iPad с USB-C и iPadOS 17 или новее, кабель USB-C ↔ USB-C с передачей данных и питание для RX (NP-F или DC).
3. Android-устройство, которое поддерживает внешние USB-камеры: проверьте, появляется ли RX в разделе «Источник видео».
4. Для CineView SE 4K — та же проверка: определяется ли USB-видеовыход как камера.
5. Для VAXIS — внешний захват HDMI/SDI → UVC (любой UVC-совместимый) на выходе RX.

Каждую проверенную комбинацию запишите в журнал тестов приложения: устройство, ОС, кабели, формат, задержку (если измеряли), стабильность.
