"""Сцены для видео: экраны CAMERA и PLAYBACK с подставленной картинкой города.

Экраны взяты из настоящих снимков интерфейса приложения (tool/presentation/assets,
их рисует test/screens_golden_test.dart). Чёрная область под видео заменяется
процедурной «съёмкой» из city.py, а поверх остаются все настоящие элементы
интерфейса. Служебные подписи, которые в снимках-заглушках говорят «нет сети»
или «подключение», закрашены, чтобы не противоречить картинке.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import city  # noqa: E402

FONTS = HERE.parents[1] / "assets" / "fonts"
W, H = 1920, 1080
BG = (10, 10, 10)
RED = (255, 30, 45)
GREEN = (47, 211, 107)
GREY = (154, 154, 154)

# область видео 16:9 внутри снимков (в пикселях исходных PNG)
CAM_VIDEO = (257, 80, 1398, 722)
PLAY_VIDEO = (143, 194, 2216, 1358)
# закрашиваемые заглушки: баннер формата, «нет локальной сети» / спиннер, чип, «REC неизвестно»
CAM_PATCH = [(140, 92, 922, 168), (24, 730, 330, 778)]
PLAY_PATCH = [(960, 670, 1400, 880), (360, 14, 580, 66), (290, 1568, 600, 1612)]


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


class UiLayer:
    """Снимок интерфейса, готовый к подстановке кадров видео."""

    def __init__(self, png: str, video_rect, patches, width: int):
        im = Image.open(HERE / "assets" / png).convert("RGB")
        d = ImageDraw.Draw(im)
        for r in patches:
            d.rectangle(r, fill=(0, 0, 0))
        k = width / im.width
        self.w, self.h = width, round(im.height * k)
        im = im.resize((self.w, self.h), Image.LANCZOS)
        self.ui = np.asarray(im, np.float32)
        self.cov = np.clip(self.ui.max(axis=2, keepdims=True) / 200.0, 0, 1)
        x0, y0, x1, y1 = video_rect
        self.rect = (round(x0 * k), round(y0 * k), round(x1 * k), round(y1 * k))
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        r = self.rect
        self.mask = ((xx >= r[0]) & (xx < r[2]) & (yy >= r[1]) & (yy < r[3]))[:, :, None].astype(np.float32)

    def render(self, video: Image.Image) -> Image.Image:
        x0, y0, x1, y1 = self.rect
        vid = np.zeros((self.h, self.w, 3), np.float32)
        v = video.resize((x1 - x0, y1 - y0), Image.BILINEAR)
        vid[y0:y1, x0:x1] = np.asarray(v, np.float32) * 0.92
        out = self.ui + vid * (1.0 - self.cov)
        return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def rounded_mask(size, radius) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def paste_device(canvas: Image.Image, screen: Image.Image, x: int, y: int, bezel: int, radius: int) -> None:
    """Экран в корпусе с тенью. (x, y) - левый верхний угол корпуса."""
    w, h = screen.width + 2 * bezel, screen.height + 2 * bezel
    shadow = Image.new("RGBA", (w + 80, h + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([40, 52, 40 + w, 52 + h], radius=radius + bezel, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas.paste(shadow, (x - 40, y - 40), shadow)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([x, y, x + w, y + h], radius=radius + bezel, fill=(28, 28, 32), outline=(74, 74, 82), width=2)
    canvas.paste(screen, (x + bezel, y + bezel), rounded_mask(screen.size, radius))


def text_c(d: ImageDraw.ImageDraw, xy, text, fnt, fill, anchor="mm") -> None:
    d.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def pill(canvas: Image.Image, cx: int, y: int, text: str, color, fnt) -> None:
    d = ImageDraw.Draw(canvas, "RGBA")
    tw = d.textlength(text, font=fnt)
    d.rounded_rectangle([cx - tw / 2 - 22, y, cx + tw / 2 + 22, y + 48], radius=24, fill=(28, 28, 32, 255),
                        outline=color, width=2)
    d.text((cx, y + 24), text, font=fnt, fill=color, anchor="mm")


# ------------------------------------------------------------------ актёр
def actor_panel(t: float, video: Image.Image, rec: bool, size=(400, 700)) -> Image.Image:
    w, h = size
    x0 = (video.width - 377) // 2
    bg = video.crop((x0, 30, x0 + 377, 690)).resize(size, Image.BICUBIC)
    bg = Image.eval(bg, lambda v: int(v * 0.8))
    d = ImageDraw.Draw(bg, "RGBA")
    ph = 2 * math.pi * 0.9 * t
    gy = 650
    bob = 5 * abs(math.sin(ph))
    hip = (170, 452 + bob)
    neck = (186, 318 + bob)
    jacket, pants, skin = (66, 70, 98), (28, 28, 38), (214, 168, 140)

    def limb(p0, p1, wd, col):
        d.line([p0, p1], fill=col, width=wd)
        d.ellipse([p1[0] - wd / 2, p1[1] - wd / 2, p1[0] + wd / 2, p1[1] + wd / 2], fill=col)

    for sgn, back in ((1, True), (-1, False)):
        th = 0.55 * math.sin(ph) * sgn
        bend = 0.7 * max(0.0, -math.sin(ph + (0.0 if sgn > 0 else math.pi)) * 0.9)
        knee = (hip[0] + 98 * math.sin(th), hip[1] + 98 * math.cos(th))
        foot = (knee[0] + 98 * math.sin(th - bend), knee[1] + 98 * math.cos(th - bend))
        foot = (foot[0], min(foot[1], gy))
        limb(hip, knee, 30, pants)
        limb(knee, foot, 26, pants)
        d.rounded_rectangle([foot[0] - 14, foot[1] - 6, foot[0] + 34, foot[1] + 12], radius=7, fill=(14, 14, 18))
    limb(hip, neck, 54, jacket)
    d.ellipse([neck[0] - 25, neck[1] - 66, neck[0] + 31, neck[1] - 10], fill=skin)
    d.pieslice([neck[0] - 27, neck[1] - 70, neck[0] + 33, neck[1] - 14], 180, 360, fill=(40, 30, 28))
    sh = (neck[0] + 4, neck[1] + 14)
    el = (sh[0] + 46, sh[1] + 34)
    hand = (sh[0] + 112, sh[1] - 10)
    limb(sh, el, 20, jacket)
    limb(el, hand, 18, jacket)
    d.ellipse([hand[0] - 9, hand[1] - 9, hand[0] + 9, hand[1] + 9], fill=skin)
    # телефон в руках: горизонтально, экраном к актёру, камерой вперёд
    px, py = hand[0] + 6, hand[1] - 2
    d.rounded_rectangle([px - 12, py - 40, px + 8, py + 40], radius=5, fill=(20, 20, 24), outline=(110, 110, 120))
    d.rounded_rectangle([px - 8, py - 35, px + 4, py + 35], radius=3, fill=(120, 170, 220))
    if rec and int(t * 2) % 2 == 0:
        d.ellipse([px - 6, py - 33, px, py - 27], fill=RED)
    d.line([(px + 8, py - 12), (px + 78, py - 28)], fill=(255, 255, 255, 40), width=2)
    d.line([(px + 8, py + 12), (px + 78, py + 28)], fill=(255, 255, 255, 40), width=2)
    out = Image.new("RGB", size, BG)
    out.paste(bg, (0, 0), rounded_mask(size, 28))
    return out


# --------------------------------------------------------------- связь по Wi-Fi
def bezier(p0, p1, p2, u):
    a = (1 - u) ** 2
    b = 2 * (1 - u) * u
    c = u**2
    return (a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1])


def draw_link(canvas: Image.Image, p0, p2, lift: int, t: float) -> None:
    d = ImageDraw.Draw(canvas, "RGBA")
    p1 = ((p0[0] + p2[0]) / 2, min(p0[1], p2[1]) - lift)
    for i in range(0, 61):
        x, y = bezier(p0, p1, p2, i / 60)
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(154, 154, 154, 110))
    for i in range(5):
        u = (t * 0.45 + i / 5) % 1.0
        x, y = bezier(p0, p1, p2, u)
        d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(255, 255, 255, 230))
        d.ellipse([x - 12, y - 12, x + 12, y + 12], outline=(255, 30, 45, 140), width=2)
    mx, my = bezier(p0, p1, p2, 0.5)
    for r in (16, 30, 44):
        d.arc([mx - r, my - r + 12, mx + r, my + r + 12], 225, 315, fill=(255, 255, 255, 235), width=5)
    d.ellipse([mx - 5, my + 4, mx + 5, my + 14], fill=(255, 255, 255, 235))


# ------------------------------------------------------------------ сцены
_cache: dict = {}


def _ui(name: str, **kw) -> UiLayer:
    key = (name, tuple(sorted(kw.items())))
    if key not in _cache:
        if name == "camera":
            _cache[key] = UiLayer("camera_phone_landscape.png", CAM_VIDEO, CAM_PATCH, kw["w"])
        else:
            _cache[key] = UiLayer("playback_tablet_landscape.png", PLAY_VIDEO, PLAY_PATCH, kw["w"])
    return _cache[key]


def header(canvas: Image.Image, text: str, sub: str = "") -> None:
    d = ImageDraw.Draw(canvas)
    d.rectangle([96, 64, 96 + 90, 70], fill=RED)
    d.text((96, 84), text, font=font("Inter-Bold.ttf", 44), fill=(255, 255, 255))
    if sub:
        d.text((W - 96, 96), sub, font=font("Inter-Medium.ttf", 28), fill=GREY, anchor="ra")


def footer_note(canvas: Image.Image) -> None:
    d = ImageDraw.Draw(canvas)
    d.text((W // 2, 872), "Интерфейс приложения; изображение города — иллюстрация, не реальная съёмка",
           font=font("Inter-Medium.ttf", 24), fill=(120, 120, 120), anchor="mm")


def scene_frame(kind: str, t: float, walk: float = 0.0, rec_at: float | None = None) -> Image.Image:
    video = city.city_frame(t, walk)
    canvas = Image.new("RGB", (W, H), BG)
    rec = rec_at is not None and t >= rec_at
    if kind == "camera":
        scr = _ui("camera", w=1400).render(video)
        paste_device(canvas, scr, (W - scr.width) // 2 - 16, 160, 16, 32)
        header(canvas, "Режим CAMERA", "телефон актёра")
    elif kind == "playback":
        scr = _ui("playback", w=900).render(video)
        paste_device(canvas, scr, (W - scr.width) // 2 - 16, 156, 16, 26)
        header(canvas, "Режим PLAYBACK", "планшет режиссёра")
    else:  # split: оба экрана и актёр
        header(canvas, "CAMERA и PLAYBACK вместе", "один и тот же кадр")
        d0 = ImageDraw.Draw(canvas)
        canvas.paste(actor_panel(t, video, rec, size=(400, 640)), (60, 160))
        cam = _ui("camera", w=560).render(video)
        play = _ui("playback", w=600).render(video)
        cx0, cy0 = 540, 420
        px0, py0 = 1210, 330
        paste_device(canvas, cam, cx0, cy0, 12, 18)
        paste_device(canvas, play, px0, py0, 14, 18)
        cam_mid = cx0 + (cam.width + 24) // 2
        play_mid = px0 + (play.width + 28) // 2
        draw_link(canvas, (cam_mid, cy0 - 40), (play_mid, py0 - 40), 150, t)
        f = font("Inter-SemiBold.ttf", 30)
        text_c(d0, (cam_mid, cy0 - 20), "CAMERA · телефон актёра", f, (255, 255, 255))
        text_c(d0, (play_mid, py0 - 20), "PLAYBACK · планшет режиссёра", f, (255, 255, 255))
        text_c(d0, (260, 832), "актёр снимает на телефон", font("Inter-Medium.ttf", 26), GREY)
        text_c(d0, ((cam_mid + play_mid) // 2, 168), "Wi-Fi, локальная сеть", font("Inter-SemiBold.ttf", 30), (255, 255, 255))
        if rec:
            fs = font("Inter-Bold.ttf", 26)
            pill(canvas, cam_mid, cy0 + cam.height + 24 + 18, "● REC на камере", RED, fs)
            if t >= rec_at + 1.0:
                pill(canvas, play_mid, py0 + play.height + 28 + 18, "● REC подтверждён камерой", RED, fs)
    footer_note(canvas)
    return canvas


if __name__ == "__main__":
    import sys
    k = sys.argv[1]
    scene_frame(k, float(sys.argv[2]), float(sys.argv[3]),
                float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] != "-" else None).save(sys.argv[5] if len(sys.argv) > 5 else f"{k}.png")
