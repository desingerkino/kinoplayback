#!/usr/bin/env python3
"""Generates all KINO PLAYBACK identity files from tool/brand/mark.py.

Outputs:
  assets/brand/*.svg, *.png, kino-playback-brand-guide.pdf
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png, LaunchImage.imageset/*.png
  android/app/src/main/res/mipmap-*/ic_launcher*.png, adaptive icon XML,
  launch background
  lib/core/brand/kp_mark_geometry.dart
Run from the repo root: python3 tool/brand/generate.py
"""
import json
import os
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import mark  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/brand"
FONT_BOLD = ROOT / "assets/fonts/Inter-Bold.ttf"
FONT_SEMI = ROOT / "assets/fonts/Inter-SemiBold.ttf"
FONT_REG = ROOT / "assets/fonts/Inter-Regular.ttf"
# Wordmark: Unbounded (SIL OFL), wide geometric — KINO in ExtraBold, PLAYBACK in Regular.
FONT_WORD = ROOT / "assets/fonts/Unbounded-ExtraBold.ttf"
FONT_WORD_SUB = ROOT / "assets/fonts/Unbounded-Regular.ttf"
TAGLINE = "CAMERA · MONITOR · PLAYBACK"
OUT.mkdir(parents=True, exist_ok=True)


# ------------------------------------------------------------ text → paths --
def text_path(text, font_file, size, x, y, tracking=0.0):
    """SVG path data for [text] set in [font_file] at [size] px, baseline y.
    Returns (d, advance_width). Real outlines, no font dependency."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    f = TTFont(str(font_file))
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    upm = f["head"].unitsPerEm
    scale = size / upm
    pen = SVGPathPen(gs)
    cx = x
    for ch in text:
        gname = cmap.get(ord(ch))
        if gname is None:
            continue
        tp = TransformPen(pen, (scale, 0, 0, -scale, cx, y))
        gs[gname].draw(tp)
        cx += gs[gname].width * scale + tracking * size
    width = cx - x - (tracking * size if text else 0)
    return pen.getCommands(), width


def poly_d(pts, s=1.0, ox=0.0, oy=0.0):
    return "M" + " L".join(f"{ox + x * s:.2f},{oy + y * s:.2f}" for x, y in pts) + " Z"


# -------------------------------------------------------------------- SVG --
def svg_symbol(white=mark.WHITE, red=mark.RED, bg=None, graphite=mark.GRAPHITE):
    parts = [f'<rect width="512" height="512" fill="{bg}"/>'] if bg else []
    for _, fill, pts in mark.shapes(white, red, graphite):
        parts.append(f'<path d="{poly_d(pts)}" fill="{fill}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            + "".join(parts) + "</svg>\n")


def svg_logo(white=mark.WHITE, red=mark.RED, sub=None, bg=None, graphite=mark.GRAPHITE):
    """Horizontal lockup: mark + KINO / PLAYBACK."""
    sub = sub or red
    h = 512
    s = 1.0
    kino_d, kino_w = text_path("KINO", FONT_WORD, 190, 520, 320, tracking=0.0)
    _, pb_w0 = text_path("PLAYBACK", FONT_WORD_SUB, 56, 0, 0)
    pb_d, pb_w = text_path("PLAYBACK", FONT_WORD_SUB, 56, 524, 420, tracking=(kino_w - 8 - pb_w0) / 7 / 56)
    w = int(520 + max(kino_w, pb_w) + 60)
    parts = [f'<rect width="{w}" height="{h}" fill="{bg}"/>'] if bg else []
    for _, fill, pts in mark.shapes(white, red, graphite):
        parts.append(f'<path d="{poly_d(pts, s)}" fill="{fill}"/>')
    parts.append(f'<path d="{kino_d}" fill="{white}"/>')
    parts.append(f'<path d="{pb_d}" fill="{sub}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            + "".join(parts) + "</svg>\n"), w


# -------------------------------------------------------------------- PNG --
SS = 4  # supersampling


def _hex(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _gradient(size, top, bottom):
    """Vertical gradient image (RGBA) of [size]."""
    w, h = size
    g = Image.new("RGBA", (1, max(h, 2)))
    t, b = _hex(top), _hex(bottom)
    for y in range(g.height):
        k = y / (g.height - 1)
        g.putpixel((0, y), tuple(int(t[i] + (b[i] - t[i]) * k) for i in range(3)) + (255,))
    return g.resize((w, h))


def draw_mark(img, box, white=None, red=None, graphite=None, rich=False):
    """Draws the mark into box=(x, y, size). [rich] adds the icon's gradients
    (glossy white, graphite, red); flat colours otherwise."""
    x0, y0, size = box
    k = size / 512
    for name, fill, pts in mark.shapes(white or mark.WHITE, red or mark.RED, graphite or mark.GRAPHITE):
        poly = [(x0 + x * k, y0 + y * k) for x, y in pts]
        role = mark.ROLE[name]
        if not rich or (white or red or graphite):
            ImageDraw.Draw(img).polygon(poly, fill=fill)
            continue
        top, bottom = {
            "white": ("#FFFFFF", "#C9C9C9"),
            "graphite": ("#3A3A3A", "#101010"),
            "red": ("#FF3B30", "#B0141C"),
        }[role]
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        bx0, by0, bx1, by1 = int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1
        grad = _gradient((bx1 - bx0, by1 - by0), top, bottom)
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        layer.paste(grad, (bx0, by0))
        img.paste(layer, (0, 0), m)


def _rounded_mask(S, inset, radius):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, S - inset, S - inset], radius=radius, fill=255)
    return m


def icon(size, tile=True, bg=mark.BLACK, scale=0.74, alpha=False, rich=True):
    """App icon. [tile]: full-bleed black square with the red rim and glow of
    the approved icon (the OS applies its own corner mask)."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0) if alpha else _hex(bg) + (255,))
    if tile:
        # warm dark vignette
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([S * 0.1, S * 0.05, S * 0.9, S * 0.85], fill=(90, 8, 10, 120))
        glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
        img = Image.alpha_composite(img, glow)
        # red rim following the platform corner radius, with soft glow
        inset, r = S * 0.035, S * 0.20
        rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(rim).rounded_rectangle([inset, inset, S - inset, S - inset], radius=r,
                                              outline=(255, 40, 45, 255), width=max(2, int(S * 0.012)))
        halo = rim.filter(ImageFilter.GaussianBlur(S * 0.02))
        img = Image.alpha_composite(img, halo)
        img = Image.alpha_composite(img, rim)
    bx0, by0, bx1, by1 = mark.bounds()
    msize = S * scale
    k = msize / 512
    ox = (S - (bx1 - bx0) * k) / 2 - bx0 * k
    oy = (S - (by1 - by0) * k) / 2 - by0 * k
    draw_mark(img, (ox, oy, msize), rich=rich)
    out = img.resize((size, size), Image.LANCZOS)
    return out if alpha else out.convert("RGB")


def logo_png(path, glow=False, transparent=True):
    W, H = 2400, 1000
    S = 2
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0) if transparent else mark.BLACK)
    msize = 760 * S
    bx0, by0, bx1, by1 = mark.bounds()
    k = msize / 512
    oy = (H * S - (by1 - by0) * k) / 2 - by0 * k
    ox = 80 * S - bx0 * k
    if glow:
        g = Image.new("RGBA", img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        for name, fill, pts in mark.shapes():
            if mark.ROLE[name] == "red":
                gd.polygon([(ox + x * k, oy + y * k) for x, y in pts], fill=(255, 30, 45, 210))
        g = g.filter(ImageFilter.GaussianBlur(60 * S))
        img = Image.alpha_composite(img, g)
    draw_mark(img, (ox, oy, msize), rich=True)
    d = ImageDraw.Draw(img)
    fk = ImageFont.truetype(str(FONT_WORD), 250 * S)
    fp = ImageFont.truetype(str(FONT_WORD_SUB), 74 * S)
    tx = ox + (bx1 + 40) * k
    d.text((tx, 300 * S), "KINO", font=fk, fill=mark.WHITE)
    kw = d.textlength("KINO", font=fk)
    _spread(d, tx + 6 * S, 640 * S, "PLAYBACK", fp, kw - 12 * S, mark.RED)
    img = img.resize((W, H), Image.LANCZOS)
    if not transparent:
        img = img.convert("RGB")
    img.save(path)


def _spread(d, x, y, text, font, width, fill):
    """Draws [text] letter-spaced so that it spans exactly [width]."""
    adv = [d.textlength(ch, font=font) for ch in text]
    gap = (width - sum(adv)) / max(len(text) - 1, 1)
    for ch, a in zip(text, adv):
        d.text((x, y), ch, font=font, fill=fill)
        x += a + gap


def home_png(path, W=1200, transparent=True):
    """Stacked home-screen lockup (approved reference): the mark inside red
    viewfinder corners with a red glow, KINO, letter-spaced PLAYBACK and the
    CAMERA · MONITOR · PLAYBACK line. Proportions follow the reference."""
    S2 = 2
    w = W * S2
    h = int(w * 1.3)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bx0, by0, bx1, by1 = mark.bounds()
    mw = w * 0.53  # mark width
    k = mw / (bx1 - bx0)
    ox = (w - mw) / 2 - bx0 * k + w * 0.005
    fy0 = w * 0.08
    oy = fy0 + w * 0.05 - by0 * k
    g = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    for name, fill, pts in mark.shapes():
        if mark.ROLE[name] == "red":
            gd.polygon([(ox + x * k, oy + y * k) for x, y in pts], fill=(255, 30, 45, 150))
    img = Image.alpha_composite(img, g.filter(ImageFilter.GaussianBlur(w * 0.02)))
    draw_mark(img, (ox, oy, 512 * k), rich=True)
    d = ImageDraw.Draw(img)
    fx0, fx1 = w * 0.09, w * 0.91
    fy1 = oy + by1 * k + w * 0.02
    L, t = w * 0.06, max(2, int(w * 0.006))
    for (cx, cy, sx, sy) in [(fx0, fy0, 1, 1), (fx1, fy0, -1, 1), (fx0, fy1, 1, -1), (fx1, fy1, -1, -1)]:
        d.line([(cx, cy + sy * L), (cx, cy), (cx + sx * L, cy)], fill=mark.RED, width=t, joint="curve")
    # KINO spans ~84% of the width
    target = w * 0.84
    fk = ImageFont.truetype(str(FONT_WORD), 100)
    fk = ImageFont.truetype(str(FONT_WORD), int(100 * target / d.textlength("KINO", font=fk)))
    l, tp, r, bt = d.textbbox((0, 0), "KINO", font=fk)
    kx = (w - (r - l)) / 2 - l
    ky = fy1 + w * 0.045 - tp
    d.text((kx, ky), "KINO", font=fk, fill=mark.WHITE)
    left, right = kx + l, kx + r
    fp = ImageFont.truetype(str(FONT_WORD_SUB), int(w * 0.07))
    pl, pt, pr, pb = d.textbbox((0, 0), "P", font=fp)
    py = ky + bt + w * 0.035 - pt
    _spread(d, left + w * 0.004, py, "PLAYBACK", fp, right - left - w * 0.008, mark.RED)
    ft = ImageFont.truetype(str(FONT_REG), int(w * 0.036))
    tl, tt, tr, tb = d.textbbox((0, 0), "C", font=ft)
    ty = py + pb + w * 0.04 - tt
    _spread(d, left + w * 0.004, ty, TAGLINE, ft, right - left - w * 0.008, "#9A9A9A")
    bottom = int(ty + tb + w * 0.06)
    img = img.crop((0, 0, w, bottom))
    if not transparent:
        bg = Image.new("RGBA", img.size, _hex(mark.BLACK) + (255,))
        img = Image.alpha_composite(bg, img).convert("RGB")
    img = img.resize((W, int(img.height / S2)), Image.LANCZOS)
    img.save(path)


# ---------------------------------------------------------- platform icons --
def ios_icons():
    d = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if not d.exists():
        print("  (no iOS icon set)")
        return
    contents = json.loads((d / "Contents.json").read_text())
    for im in contents["images"]:
        fn = im.get("filename")
        if not fn:
            continue
        sz = float(im["size"].split("x")[0]) * int(im["scale"].rstrip("x"))
        icon(int(round(sz))).save(d / fn)  # RGB, no alpha (App Store requirement)
    print("  iOS AppIcon:", len(contents["images"]), "entries")
    li = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for fn, s in [("LaunchImage.png", 1), ("LaunchImage@2x.png", 2), ("LaunchImage@3x.png", 3)]:
        icon(120 * s, tile=False, scale=0.92, alpha=True).save(li / fn)
    sb = ROOT / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
    if sb.exists():
        t = sb.read_text()
        t = t.replace('<color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
                      '<color key="backgroundColor" red="0.0392" green="0.0392" blue="0.0392" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>')
        t = t.replace('<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>',
                      '<color key="backgroundColor" red="0.0392" green="0.0392" blue="0.0392" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>')
        sb.write_text(t)


def android_icons():
    res = ROOT / "android/app/src/main/res"
    if not res.exists():
        print("  (no Android res)")
        return
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, f in dens.items():
        d = res / f"mipmap-{name}"
        d.mkdir(exist_ok=True)
        icon(int(48 * f)).save(d / "ic_launcher.png")
        # adaptive foreground: 108dp canvas, mark inside the 66dp safe zone
        icon(int(108 * f), tile=False, scale=0.52, alpha=True).save(d / "ic_launcher_foreground.png")
        # monochrome (themed icons): white mark only
        mono = Image.new("RGBA", (int(108 * f) * SS,) * 2, (0, 0, 0, 0))
        S = int(108 * f) * SS
        bx0, by0, bx1, by1 = mark.bounds()
        msize = S * 0.50
        k = msize / 512
        draw_mark(mono, ((S - (bx1 - bx0) * k) / 2 - bx0 * k, (S - (by1 - by0) * k) / 2 - by0 * k, msize),
                  white="#FFFFFF", red="#FFFFFF", graphite="#FFFFFF")
        mono.resize((int(108 * f),) * 2, Image.LANCZOS).save(d / "ic_launcher_monochrome.png")
        icon(int(120 * f), tile=False, scale=0.92, alpha=True).save(d / "launch_mark.png")
    any26 = res / "mipmap-anydpi-v26"
    any26.mkdir(exist_ok=True)
    (any26 / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n')
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#0A0A0A</color>\n</resources>\n')
    launch = ('<?xml version="1.0" encoding="utf-8"?>\n'
              '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
              '    <item android:drawable="@color/ic_launcher_background" />\n'
              '    <item>\n        <bitmap android:gravity="center" android:src="@mipmap/launch_mark" />\n    </item>\n'
              '</layer-list>\n')
    for sub in ("drawable", "drawable-v21"):
        p = res / sub / "launch_background.xml"
        if p.exists():
            p.write_text(launch)
    print("  Android: legacy + adaptive + monochrome icons, launch background")


# ------------------------------------------------------------ Dart geometry --
def dart_geometry():
    def lst(pts):
        return "[" + ", ".join(f"Offset({x}, {y})" for x, y in pts) + "]"
    parts = "\n".join(f"    KpMarkPart(KpMarkRole.{mark.ROLE[k]}, {lst(v)})," for k, v in mark.PARTS.items())
    src = f"""// GENERATED by tool/brand/generate.py — do not edit by hand.
import 'dart:ui';

enum KpMarkRole {{ white, graphite, red }}

class KpMarkPart {{
  const KpMarkPart(this.role, this.points);
  final KpMarkRole role;
  final List<Offset> points;
}}

/// KINO PLAYBACK mark on a 512×512 grid (traced from the approved icon).
abstract final class KpMarkGeometry {{
  static const double grid = 512;
  static const List<KpMarkPart> parts = [
{parts}
  ];
  static const Rect bounds = Rect.fromLTRB{mark.bounds()};
}}
"""
    p = ROOT / "lib/core/brand/kp_mark_geometry.dart"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(src)


# --------------------------------------------------------------- brand PDF --
def brand_pdf(path):
    from reportlab.lib.colors import HexColor
    from reportlab.lib.pagesizes import landscape, A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont as RLTTF
    from reportlab.pdfgen import canvas

    pdfmetrics.registerFont(RLTTF("Inter-Bold", str(FONT_BOLD)))
    pdfmetrics.registerFont(RLTTF("Inter-SemiBold", str(FONT_SEMI)))
    pdfmetrics.registerFont(RLTTF("Unbounded-ExtraBold", str(FONT_WORD)))
    pdfmetrics.registerFont(RLTTF("Unbounded-Regular", str(FONT_WORD_SUB)))
    pdfmetrics.registerFont(RLTTF("Inter", str(ROOT / "assets/fonts/Inter-Regular.ttf")))
    W, H = landscape(A4)
    c = canvas.Canvas(str(path), pagesize=(W, H))
    c.setTitle("KINO PLAYBACK — Brand Guide")

    def bg(color=mark.BLACK):
        c.setFillColor(HexColor(color))
        c.rect(0, 0, W, H, stroke=0, fill=1)

    def vmark(x, y, size, white=mark.WHITE, red=mark.RED, graphite=mark.GRAPHITE):
        k = size / 512
        for _, fill, pts in mark.shapes(white, red, graphite):
            p = c.beginPath()
            for i, (px, py) in enumerate(pts):
                X, Y = x + px * k, y + (512 - py) * k
                (p.moveTo if i == 0 else p.lineTo)(X, Y)
            p.close()
            c.setFillColor(HexColor(fill))
            c.drawPath(p, stroke=0, fill=1)

    def title(t, sub=None):
        c.setFillColor(HexColor(mark.WHITE))
        c.setFont("Inter-Bold", 26)
        c.drawString(48, H - 70, t)
        if sub:
            c.setFillColor(HexColor(mark.GREY))
            c.setFont("Inter", 12)
            c.drawString(48, H - 92, sub)

    # 1 — cover
    bg()
    vmark(70, H / 2 - 150, 300)
    c.setFillColor(HexColor(mark.WHITE))
    c.setFont("Inter-Bold", 120)
    c.drawString(400, H / 2 - 10, "KINO")
    c.setFillColor(HexColor(mark.RED))
    c.setFont("Inter-SemiBold", 30)
    c.drawString(406, H / 2 - 60, "P  L  A  Y  B  A  C  K")
    c.setFillColor(HexColor(mark.GREY))
    c.setFont("Inter", 12)
    c.drawString(406, H / 2 - 100, "Brand guide · CAMERA · MONITOR · PLAYBACK")
    c.showPage()

    # 2 — mark construction
    bg()
    title("Знак", "Блок K (белая и графитовая половины, диагональный разрез), красный треугольник Play и объектив. Сетка 512 × 512.")
    x0, y0, s = 60, 60, 360
    c.setStrokeColor(HexColor("#2A2A2A"))
    c.setLineWidth(0.5)
    for i in range(0, 513, 32):
        c.line(x0 + i * s / 512, y0, x0 + i * s / 512, y0 + s)
        c.line(x0, y0 + i * s / 512, x0 + s, y0 + i * s / 512)
    vmark(x0, y0, s)
    c.setFont("Inter", 10)
    c.setFillColor(HexColor(mark.GREY))
    yy = y0 + s - 10
    for name, _, pts in mark.shapes():
        c.drawString(470, yy, f"{name}: " + " ".join(f"({x:.0f},{y:.0f})" for x, y in pts))
        yy -= 16
    c.drawString(470, yy - 10, "Минимальный размер знака: 16 px.")
    c.drawString(470, yy - 26, "Рекомендуемый в интерфейсе: 24–32 px.")
    c.drawString(470, yy - 42, "Охранное поле: ширина ножки K со всех сторон.")
    for i, sz in enumerate([96, 48, 32, 24, 16]):
        vmark(470 + i * 110, 120, sz)
    c.showPage()

    # 3 — versions
    bg()
    title("Версии")
    vmark(60, 260, 200)
    c.setFillColor(HexColor(mark.GREY))
    c.setFont("Inter", 11)
    c.drawString(60, 235, "Основная: белый + красный на чёрном")
    c.setFillColor(HexColor(mark.WHITE))
    c.roundRect(320, 260, 200, 200, 24, stroke=0, fill=1)
    vmark(330, 270, 180, white=mark.BLACK, red=mark.BLACK, graphite="#5A5A5A")
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(320, 235, "Монохромная чёрная")
    vmark(580, 270, 180, white=mark.WHITE, red=mark.WHITE, graphite="#9A9A9A")
    c.drawString(580, 235, "Монохромная белая")
    c.setFillColor(HexColor(mark.GRAPHITE))
    c.roundRect(60, 40, 170, 170, 34, stroke=0, fill=1)
    vmark(85, 65, 120)
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(250, 120, "Иконка приложения: чёрный фон, красный контур со свечением, знак без надписей.")
    c.drawString(250, 102, "iOS — без прозрачности; Android — адаптивная (фон #0A0A0A + передний слой + monochrome).")
    c.showPage()

    # 4 — colours & type
    bg()
    title("Цвет и типографика")
    sw = [(mark.BLACK, "Чёрный", "#0A0A0A", "фон, монитор"), (mark.GRAPHITE, "Графит", "#1B1B1B", "панели"),
          (mark.RED, "Красный", "#FF1E2D", "REC, активные команды, важные предупреждения"),
          (mark.WHITE, "Белый", "#FFFFFF", "текст, знак"), ("#2FD36B", "Зелёный (функц.)", "#2FD36B",
                                                           "только подтверждённое рабочее состояние")]
    for i, (col, name, hx, use) in enumerate(sw):
        x = 48 + i * 150
        c.setFillColor(HexColor(col))
        c.setStrokeColor(HexColor("#333333"))
        c.rect(x, 300, 130, 130, stroke=1, fill=1)
        c.setFillColor(HexColor(mark.WHITE))
        c.setFont("Inter-SemiBold", 12)
        c.drawString(x, 280, name)
        c.setFont("Inter", 10)
        c.setFillColor(HexColor(mark.GREY))
        c.drawString(x, 265, hx)
        c.drawString(x, 251, use[:28])
        if len(use) > 28:
            c.drawString(x, 238, use[28:56])
    c.setFillColor(HexColor(mark.WHITE))
    c.setFont("Unbounded-ExtraBold", 40)
    c.drawString(48, 150, "KINO")
    c.setFont("Unbounded-Regular", 18)
    c.setFillColor(HexColor(mark.RED))
    c.drawString(48, 120, "P L A Y B A C K")
    c.setFont("Inter", 10)
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(200, 150, "Знак: Unbounded ExtraBold / Regular (SIL OFL), только для KINO и PLAYBACK.")
    c.setFont("Inter", 12)
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(48, 92, "Интерфейс: Inter Regular / Medium / SemiBold, табличные цифры для таймкода и метрик.")
    c.drawString(48, 74, "Не использовать: оранжевый как фирменный, синие/фиолетовые акценты, неон, тяжёлое свечение в интерфейсе.")
    c.showPage()
    c.save()


def main():
    print("brand:")
    (OUT / "kino-playback-symbol.svg").write_text(svg_symbol())
    logo, _ = svg_logo(bg=mark.BLACK)
    (OUT / "kino-playback-logo.svg").write_text(logo)
    white, _ = svg_logo(white=mark.WHITE, red=mark.WHITE, sub=mark.WHITE, graphite="#9A9A9A")
    (OUT / "kino-playback-logo-white.svg").write_text(white)
    black, _ = svg_logo(white=mark.BLACK, red=mark.BLACK, sub=mark.BLACK, graphite="#5A5A5A")
    (OUT / "kino-playback-logo-black.svg").write_text(black)
    icon(1024).save(OUT / "kino-playback-icon-1024.png")
    # maskable: no rim, content inside the central 80% safe circle
    icon(1024, tile=False, scale=0.50).save(OUT / "kino-playback-icon-maskable.png")
    logo_png(OUT / "kino-playback-logo-transparent.png")
    logo_png(OUT / "kino-playback-logo-presentation.png", glow=True, transparent=False)
    home_png(OUT / "kino-playback-home-lockup.png")
    home_png(OUT / "kino-playback-home-lockup-black.png", transparent=False)
    icon(512, tile=False, scale=0.92, alpha=True).save(OUT / "kino-playback-symbol-512.png")
    brand_pdf(OUT / "kino-playback-brand-guide.pdf")
    ios_icons()
    android_icons()
    dart_geometry()
    print("done")


if __name__ == "__main__":
    main()
