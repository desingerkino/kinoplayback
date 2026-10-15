"""Процедурная «съёмка»: проход по московской улице к Красной площади.

Это иллюстрация, нарисованная кодом (Pillow + numpy), а не настоящая видеозапись.
city_frame(t, walk) -> PIL.Image 1280x720, где t - время сцены, walk - сколько
секунд «прогулки» прошло до начала сцены (чтобы движение было непрерывным).
"""
from __future__ import annotations

import math
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

W, H = 1280, 720
CX, HY = W / 2, 330.0
F = 560.0          # фокус в пикселях
EYE = 1.6          # высота глаз, м
SPEED = 1.25       # скорость ходьбы, м/с
HAZE = np.array((244, 186, 140), dtype=np.float32)


def proj(x: float, y: float, z: float) -> tuple[float, float]:
    return CX + F * x / z, HY - F * (y - EYE) / z


def _hash(n: int) -> float:
    n = (n * 374761393 + 668265263) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n & 0xFFFF) / 65535.0


# ---------------------------------------------------------------- небо и город
@lru_cache(maxsize=1)
def _sky() -> Image.Image:
    h = int(HY) + 1
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    top = np.array((34, 50, 104), np.float32)
    mid = np.array((132, 112, 152), np.float32)
    hor = np.array((252, 184, 130), np.float32)
    a = np.clip(y / 0.62, 0, 1)
    b = np.clip((y - 0.62) / 0.38, 0, 1)
    col = np.where(y < 0.62, top + (mid - top) * a, mid + (hor - mid) * b)
    col = np.broadcast_to(col, (h, W, 3)).copy()
    xx = np.arange(W, dtype=np.float32)[None, :]
    yy = np.arange(h, dtype=np.float32)[:, None]
    d2 = (xx - (CX + 150)) ** 2 + (yy - (HY - 6)) ** 2
    glow = np.exp(-d2 / (2 * 230.0**2))[:, :, None]
    col = col + glow * np.array((120, 70, 20), np.float32)
    return Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB")


@lru_cache(maxsize=1)
def _skyline() -> Image.Image:
    """Силуэт «Москва-Сити» справа у горизонта (RGBA)."""
    img = Image.new("RGBA", (W + 200, int(HY) + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = int(HY)
    towers = [(760, 46, 120), (812, 38, 168), (856, 52, 205), (914, 40, 150), (960, 58, 118),
              (1024, 36, 140), (1066, 44, 98), (1114, 50, 126), (1170, 34, 90), (700, 40, 88),
              (640, 36, 70), (1220, 40, 76)]
    for i, (x, w, h) in enumerate(towers):
        c = (96, 98, 140, 255) if i % 2 else (88, 92, 134, 255)
        d.rectangle([x, base - h, x + w, base], fill=c)
        if h > 150:  # шпиль
            d.polygon([(x + w // 2 - 3, base - h), (x + w // 2 + 3, base - h),
                       (x + w // 2, base - h - 36)], fill=c)
        for wy in range(base - h + 8, base - 6, 9):
            for wx in range(x + 5, x + w - 4, 8):
                if _hash(wx * 31 + wy * 7 + i) > 0.72:
                    d.rectangle([wx, wy, wx + 2, wy + 3], fill=(255, 214, 150, 255))
    return img


def _onion(d: ImageDraw.ImageDraw, P, cx, by, r, h, c1, c2, drum=26, stripes=7):
    """Луковичная глава. P(x, y) - локальные координаты -> экран."""
    # барабан
    d.rectangle([*P(cx - r * 0.55, by + drum), *P(cx + r * 0.55, by)], fill=(236, 220, 196))
    d.rectangle([*P(cx - r * 0.12, by + drum - 6), *P(cx + r * 0.12, by + drum * 0.3)], fill=(120, 80, 70))
    pts_r, pts_l = [], []
    n = 24
    for i in range(n + 1):
        t = i / n
        w = r * (math.sin(math.pi * min(1.0, t * 1.04) ** 0.62) ** 0.9)
        pts_r.append(P(cx + w, by + drum + h * t))
        pts_l.append(P(cx - w, by + drum + h * t))
    d.polygon(pts_r + pts_l[::-1], fill=c1)
    for k in range(-(stripes // 2), stripes // 2 + 1):
        line = []
        for i in range(n + 1):
            t = i / n
            w = r * (math.sin(math.pi * min(1.0, t * 1.04) ** 0.62) ** 0.9)
            line.append(P(cx + w * k / (stripes / 2 + 0.6), by + drum + h * t))
        d.line(line, fill=c2, width=2)
    tip = P(cx, by + drum + h)
    d.line([tip, P(cx, by + drum + h + 16)], fill=(240, 200, 90), width=2)
    d.ellipse([tip[0] - 3, tip[1] - 3, tip[0] + 3, tip[1] + 3], fill=(240, 200, 90))


def _landmark(k: float) -> Image.Image:
    """Собор Василия Блаженного, Кремлёвская стена и Спасская башня (RGBA)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return CX + (x + 150) * k, HY - y * k

    brick = (166, 60, 50, 255)
    dark = (120, 40, 36, 255)
    # стена
    d.rectangle([*P(-60, 40), *P(640, 0)], fill=brick)
    for x in range(-60, 640, 22):
        d.rectangle([*P(x, 54), *P(x + 13, 40)], fill=brick)
    for y in (12, 26):
        d.line([P(-60, y), P(640, y)], fill=dark, width=1)
    # Спасская башня
    d.rectangle([*P(300, 205), *P(372, 40)], fill=brick)
    d.rectangle([*P(294, 214), *P(378, 200)], fill=(222, 196, 150, 255))
    d.rectangle([*P(308, 262), *P(364, 214)], fill=(232, 214, 176, 255))
    cxy = P(336, 238)
    rr = 15 * k
    d.ellipse([cxy[0] - rr, cxy[1] - rr, cxy[0] + rr, cxy[1] + rr], fill=(250, 246, 236, 255))
    d.polygon([P(302, 262), P(370, 262), P(336, 350)], fill=(54, 116, 92, 255))
    d.line([P(336, 350), P(336, 372)], fill=(240, 200, 90, 255), width=2)
    star = [P(336, 396), P(342, 376), P(362, 376), P(346, 364), P(352, 344), P(336, 356),
            P(320, 344), P(326, 364), P(310, 376), P(330, 376)]
    d.polygon(star, fill=(236, 40, 44, 255))
    # вторая башня
    d.rectangle([*P(520, 150), *P(568, 40)], fill=brick)
    d.polygon([P(514, 150), P(574, 150), P(544, 220)], fill=(54, 116, 92, 255))
    # Василий Блаженный
    d.rectangle([*P(-330, 96), *P(-90, 0)], fill=(236, 222, 196, 255))
    for x in range(-318, -100, 34):
        d.rectangle([*P(x, 62), *P(x + 14, 24)], fill=(150, 64, 56, 255))
    d.rectangle([*P(-330, 40), *P(-90, 32)], fill=(176, 52, 46, 255))
    d.rectangle([*P(-250, 190), *P(-170, 96)], fill=(220, 90, 74, 255))
    for x in (-242, -222, -202, -182):
        d.rectangle([*P(x, 150), *P(x + 8, 110)], fill=(236, 222, 196, 255))
    d.polygon([P(-256, 190), P(-164, 190), P(-210, 312)], fill=(178, 42, 42, 255))
    for x in (-236, -210, -184):
        d.line([P(x, 190), P(-210, 312)], fill=(240, 220, 190, 255), width=1)
    d.ellipse([*P(-218, 326), *P(-202, 308)], fill=(242, 200, 80, 255))
    d.line([P(-210, 326), P(-210, 344)], fill=(242, 200, 80, 255), width=2)
    _onion(d, P, -306, 96, 30, 70, (70, 150, 96, 255), (236, 196, 70, 255))
    _onion(d, P, -262, 96, 26, 62, (60, 100, 190, 255), (240, 240, 250, 255), drum=20)
    _onion(d, P, -158, 96, 28, 66, (238, 196, 70, 255), (176, 52, 46, 255))
    _onion(d, P, -114, 96, 30, 72, (200, 56, 56, 255), (250, 232, 210, 255))
    return img


# ----------------------------------------------------------------- наложения
@lru_cache(maxsize=1)
def _vignette() -> np.ndarray:
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    return (1.0 - 0.38 * np.clip(d - 0.45, 0, 1) ** 1.4)[:, :, None]


@lru_cache(maxsize=1)
def _ground() -> Image.Image:
    h = H - int(HY)
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    far = np.array((150, 128, 120), np.float32)
    near = np.array((54, 50, 56), np.float32)
    col = far + (near - far) * np.clip(y * 1.6, 0, 1)
    return Image.fromarray(np.broadcast_to(col, (h, W, 3)).astype(np.uint8), "RGB")


PALETTE = [(216, 172, 112), (232, 214, 178), (208, 134, 112), (172, 192, 152),
           (152, 164, 186), (226, 190, 140)]

PEOPLE = [  # (x, мировой z0, скорость м/с, цвет пальто, рост)
    (-2.6, 14, 1.0, (28, 30, 44), 1.78), (2.9, 24, -1.3, (122, 52, 52), 1.68),
    (-0.8, 32, -1.1, (44, 74, 96), 1.74), (1.4, 18, 1.1, (200, 196, 190), 1.62),
    (-3.6, 40, -1.2, (60, 60, 64), 1.80), (3.8, 8, 1.0, (34, 84, 70), 1.70),
    (0.3, 50, -1.4, (150, 110, 60), 1.72),
]


def _people(d: ImageDraw.ImageDraw, s: float, T: float) -> None:
    items = []
    for i, (x, z0, v, col, hgt) in enumerate(PEOPLE):
        zw = (z0 + v * T) % 70.0 if v < 0 else (z0 + v * T) % 70.0
        z = zw - s % 70.0
        z = z % 70.0
        if 2.2 < z < 58:
            items.append((z, x, col, hgt, i))
    for z, x, col, hgt, i in sorted(items, reverse=True):
        sc = F / z
        px, py = proj(x, 0, z)
        phase = T * 5.0 + i
        sw = math.sin(phase) * 0.22
        w = 0.24 * sc
        top = py - hgt * sc
        # ноги
        for sgn in (1, -1):
            lx = px + sgn * sw * sc * 0.6
            d.line([(px + sgn * 0.05 * sc, py - 0.85 * sc), (lx, py)], fill=(24, 24, 32), width=max(2, int(0.13 * sc)))
        # корпус и голова
        d.rounded_rectangle([px - w, top + 0.2 * sc, px + w, py - 0.82 * sc], radius=max(2, int(w * 0.5)), fill=col)
        hr = 0.13 * sc
        d.ellipse([px - hr, top, px + hr, top + 2 * hr], fill=(214, 168, 140))


def _lamps(layer: ImageDraw.ImageDraw, s: float) -> None:
    pitch = 16.0
    first = math.floor(s / pitch)
    zs = []
    for n in range(first, first + 6):
        z = n * pitch + 6.0 - s
        if 2.0 < z < 44:
            zs.append(z)
    for z in sorted(zs, reverse=True):
        for sx in (-1, 1):
            bx, by = proj(sx * 5.0, 0, z)
            tx, ty = proj(sx * 5.0, 5.2, z)
            wdt = max(1, int(0.12 * F / z))
            layer.line([(bx, by), (tx, ty)], fill=(30, 30, 38, 255), width=wdt)
            lx, ly = proj(sx * 4.5, 5.2, z)
            layer.line([(tx, ty), (lx, ly)], fill=(30, 30, 38, 255), width=wdt)
            r = max(2.0, 0.28 * F / z)
            for k, a in ((4.0, 26), (2.4, 50), (1.4, 110), (1.0, 255)):
                layer.ellipse([lx - r * k, ly - r * k, lx + r * k, ly + r * k], fill=(255, 226, 160, a))


def _facades(d: ImageDraw.ImageDraw, s: float) -> None:
    block = 14.0
    first = math.floor(s / block)
    for n in range(first + 6, first - 1, -1):          # далёкие первыми
        za, zb = n * block - s, n * block + block - s
        if zb < 1.4 or za > 30:
            continue
        za, zb = max(za, 1.4), min(zb, 30.0)
        hf = 6.0 + 3.5 * _hash(n * 7 + 3)
        for side in (-1, 1):
            hh = hf + (2.0 if side > 0 else 0) * _hash(n * 13 + side)
            x = side * 7.5
            col = PALETTE[int(_hash(n * 5 + (3 if side > 0 else 1)) * len(PALETTE)) % len(PALETTE)]
            shade = 1.0 if side < 0 else 0.74
            col = tuple(int(c * shade) for c in col)
            quad = [proj(x, 0, za), proj(x, hh, za), proj(x, hh, zb), proj(x, 0, zb)]
            d.polygon(quad, fill=col)
            # карниз
            d.line([proj(x, hh, za), proj(x, hh, zb)], fill=tuple(int(c * 0.6) for c in col), width=2)
            # окна
            wz = 3.0
            z_start = math.ceil((n * block - s) / wz) * wz if False else None
            for j in range(int(block / wz)):
                zw0 = n * block + j * wz - s + 0.7
                zw1 = zw0 + 1.7
                if zw0 < 1.4 or zw1 > 30:
                    continue
                floors = int((hh - 1.2) // 3.4)
                for fl in range(floors):
                    y0 = 1.6 + fl * 3.4 if fl else 0.4
                    y1 = y0 + (2.2 if fl else 2.6)
                    lit = _hash(n * 97 + j * 13 + fl * 5 + side) > 0.55
                    wc = (255, 208, 130) if (lit or fl == 0) else (46, 54, 78)
                    d.polygon([proj(x, y0, zw0), proj(x, y1, zw0), proj(x, y1, zw1), proj(x, y0, zw1)], fill=wc)


def city_frame(t: float, walk: float = 0.0) -> Image.Image:
    T = walk + t
    s = SPEED * T
    img = _sky().copy()
    full = Image.new("RGB", (W, H), (0, 0, 0))
    full.paste(img, (0, 0))
    # дальний силуэт «Москва-Сити»
    sk = _skyline()
    full.paste(sk, (-int(s * 1.6) % 60 - 60, 0), sk)
    # ориентир: сначала издалека, потом приближается
    k = 1.05 / max(0.62, 1.0 - s / 170.0)
    lm = np.asarray(_landmark(k), np.float32)
    rgb, a = lm[:, :, :3], lm[:, :, 3:4] / 255.0
    haze = 0.16
    rgb = rgb * (1 - haze) + HAZE * haze
    base = np.asarray(full, np.float32)
    base = base * (1 - a) + rgb * a
    full = Image.fromarray(base.astype(np.uint8), "RGB")

    # земля
    full.paste(_ground(), (0, int(HY)))
    d = ImageDraw.Draw(full, "RGBA")
    # тротуары
    for sx in (-1, 1):
        d.polygon([proj(sx * 5.4, 0, 1.4), proj(sx * 7.5, 0, 1.4), proj(sx * 7.5, 0, 44), proj(sx * 5.4, 0, 44)],
                  fill=(168, 156, 150, 255))
        d.line([proj(sx * 5.4, 0, 1.4), proj(sx * 5.4, 0, 44)], fill=(96, 88, 88, 255), width=2)
    # швы брусчатки
    for m in range(1, 80):
        zc = 0.9 * m - (s % 0.9) - 0.9 + 0.9
        if zc < 1.4 or zc > 60:
            continue
        a_ = proj(-5.4, 0, zc)
        b_ = proj(5.4, 0, zc)
        d.line([a_, b_], fill=(96, 86, 88, 120), width=1)
    for xk in range(-6, 7):
        d.line([proj(xk * 0.9, 0, 1.4), proj(xk * 0.9, 0, 60)], fill=(96, 86, 88, 90), width=1)
    # фасады, люди, фонари
    _facades(d, s)
    _people(d, s, T)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    _lamps(ImageDraw.Draw(glow), s)
    full = Image.alpha_composite(full.convert("RGBA"), glow).convert("RGB")

    arr = np.asarray(full, np.float32)
    # дымка у горизонта
    yy = np.arange(H, dtype=np.float32)[:, None, None]
    hz = np.exp(-((yy - HY) ** 2) / (2 * 70.0**2)) * 0.22
    arr = arr * (1 - hz) + HAZE * hz
    # тёплый тон, виньетка, зерно
    arr = arr * np.array((1.04, 1.0, 0.94), np.float32) * _vignette()
    rng = np.random.default_rng(int(T * 30) + 7)
    arr = arr + rng.normal(0, 3.0, arr.shape).astype(np.float32)
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")

    # «ручная» камера: качка шагов
    dx = 6 * math.sin(2 * math.pi * 0.9 * T) + 3 * math.sin(2 * math.pi * 1.9 * T + 1.0)
    dy = 5 * abs(math.sin(math.pi * 1.8 * T)) - 2.5
    ang = 0.45 * math.sin(2 * math.pi * 0.55 * T)
    out = out.rotate(ang, resample=Image.BICUBIC, translate=(dx, dy), fillcolor=(10, 10, 10))
    m = 36
    out = out.crop((m, int(m * 0.5625), W - m, H - int(m * 0.5625))).resize((W, H), Image.BICUBIC)
    return out


if __name__ == "__main__":
    import sys
    t = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0
    walk = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    city_frame(t, walk).save(sys.argv[3] if len(sys.argv) > 3 else "city.png")
