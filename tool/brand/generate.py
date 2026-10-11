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
def svg_symbol(white=mark.WHITE, red=mark.RED, bg=None):
    parts = [f'<rect width="512" height="512" fill="{bg}"/>'] if bg else []
    for _, fill, pts in mark.shapes(white, red):
        parts.append(f'<path d="{poly_d(pts)}" fill="{fill}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            + "".join(parts) + "</svg>\n")


def svg_logo(white=mark.WHITE, red=mark.RED, sub=None, bg=None):
    """Horizontal lockup: mark + KINO / PLAYBACK."""
    sub = sub or red
    h = 512
    s = 1.0
    kino_d, kino_w = text_path("KINO", FONT_BOLD, 250, 520, 330, tracking=0.02)
    pb_d, pb_w = text_path("PLAYBACK", FONT_SEMI, 64, 528, 430, tracking=0.42)
    w = int(520 + max(kino_w, pb_w) + 60)
    parts = [f'<rect width="{w}" height="{h}" fill="{bg}"/>'] if bg else []
    for _, fill, pts in mark.shapes(white, red):
        parts.append(f'<path d="{poly_d(pts, s)}" fill="{fill}"/>')
    parts.append(f'<path d="{kino_d}" fill="{white}"/>')
    parts.append(f'<path d="{pb_d}" fill="{sub}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            + "".join(parts) + "</svg>\n"), w


# -------------------------------------------------------------------- PNG --
SS = 4  # supersampling


def draw_mark(img, box, white=mark.WHITE, red=mark.RED):
    """Draws the mark scaled into box=(x, y, size) on an RGBA/RGB image."""
    x0, y0, size = box
    d = ImageDraw.Draw(img)
    k = size / 512
    for _, fill, pts in mark.shapes(white, red):
        d.polygon([(x0 + x * k, y0 + y * k) for x, y in pts], fill=fill)


def icon(size, brackets=True, bg=mark.BLACK, scale=0.70, alpha=False):
    S = size * SS
    img = Image.new("RGBA" if alpha else "RGB", (S, S), (0, 0, 0, 0) if alpha else bg)
    d = ImageDraw.Draw(img)
    if brackets:
        k = S / 512
        for poly in mark.brackets():
            d.polygon([(x * k, y * k) for x, y in poly], fill=mark.RED)
    # centre the mark's bounding box
    bx0, by0, bx1, by1 = mark.bounds()
    msize = S * scale
    k = msize / 512
    ox = (S - (bx1 - bx0) * k) / 2 - bx0 * k
    oy = (S - (by1 - by0) * k) / 2 - by0 * k
    draw_mark(img, (ox, oy, msize))
    return img.resize((size, size), Image.LANCZOS)


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
        for _, fill, pts in mark.shapes():
            if fill == mark.RED:
                gd.polygon([(ox + x * k, oy + y * k) for x, y in pts], fill=(255, 30, 45, 210))
        g = g.filter(ImageFilter.GaussianBlur(60 * S))
        img = Image.alpha_composite(img, g)
    draw_mark(img, (ox, oy, msize))
    d = ImageDraw.Draw(img)
    fk = ImageFont.truetype(str(FONT_BOLD), 330 * S)
    fp = ImageFont.truetype(str(FONT_SEMI), 84 * S)
    tx = ox + (bx1 + 40) * k
    d.text((tx, 250 * S), "KINO", font=fk, fill=mark.WHITE)
    x = tx + 8 * S
    for ch in "PLAYBACK":
        d.text((x, 640 * S), ch, font=fp, fill=mark.RED)
        x += d.textlength(ch, font=fp) + 34 * S
    img = img.resize((W, H), Image.LANCZOS)
    if not transparent:
        img = img.convert("RGB")
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
        icon(int(round(sz))).convert("RGB").save(d / fn)  # no alpha on iOS
    print("  iOS AppIcon:", len(contents["images"]), "entries")
    li = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for fn, s in [("LaunchImage.png", 1), ("LaunchImage@2x.png", 2), ("LaunchImage@3x.png", 3)]:
        icon(96 * s, brackets=False, scale=1.0, alpha=True).save(li / fn)
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
        icon(int(108 * f), brackets=False, scale=0.50, alpha=True).save(d / "ic_launcher_foreground.png")
        # monochrome (themed icons): white mark only
        mono = Image.new("RGBA", (int(108 * f) * SS,) * 2, (0, 0, 0, 0))
        S = int(108 * f) * SS
        bx0, by0, bx1, by1 = mark.bounds()
        msize = S * 0.50
        k = msize / 512
        draw_mark(mono, ((S - (bx1 - bx0) * k) / 2 - bx0 * k, (S - (by1 - by0) * k) / 2 - by0 * k, msize),
                  white="#FFFFFF", red="#FFFFFF")
        mono.resize((int(108 * f),) * 2, Image.LANCZOS).save(d / "ic_launcher_monochrome.png")
        icon(int(96 * f), brackets=False, scale=1.0, alpha=True).save(d / "launch_mark.png")
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
    src = f"""// GENERATED by tool/brand/generate.py — do not edit by hand.
import 'dart:ui';

/// KINO PLAYBACK mark on a 512×512 grid.
abstract final class KpMarkGeometry {{
  static const double grid = 512;
  static const List<Offset> stem = {lst(mark.STEM)};
  static const List<Offset> arm = {lst(mark.ARM)};
  static const List<Offset> play = {lst(mark.PLAY)};
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
    pdfmetrics.registerFont(RLTTF("Inter", str(ROOT / "assets/fonts/Inter-Regular.ttf")))
    W, H = landscape(A4)
    c = canvas.Canvas(str(path), pagesize=(W, H))
    c.setTitle("KINO PLAYBACK — Brand Guide")

    def bg(color=mark.BLACK):
        c.setFillColor(HexColor(color))
        c.rect(0, 0, W, H, stroke=0, fill=1)

    def vmark(x, y, size, white=mark.WHITE, red=mark.RED):
        k = size / 512
        for _, fill, pts in mark.shapes(white, red):
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
    title("Знак", "K: белая ножка и верхнее плечо; нижнее плечо — красный треугольник Play. Сетка 512 × 512.")
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
        c.drawString(470, yy, f"{name}: " + "  ".join(f"({x},{y})" for x, y in pts))
        yy -= 18
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
    vmark(330, 270, 180, white=mark.BLACK, red=mark.BLACK)
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(320, 235, "Монохромная чёрная")
    vmark(580, 270, 180, white=mark.WHITE, red=mark.WHITE)
    c.drawString(580, 235, "Монохромная белая")
    c.setFillColor(HexColor(mark.GRAPHITE))
    c.roundRect(60, 40, 170, 170, 34, stroke=0, fill=1)
    vmark(85, 65, 120)
    c.setFillColor(HexColor(mark.GREY))
    c.drawString(250, 120, "Иконка приложения: чёрный фон, красные уголки видоискателя, знак без надписей.")
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
    c.setFont("Inter-Bold", 40)
    c.drawString(48, 150, "Inter Bold — KINO")
    c.setFont("Inter-SemiBold", 18)
    c.setFillColor(HexColor(mark.RED))
    c.drawString(48, 120, "INTER SEMIBOLD · P L A Y B A C K")
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
    white, _ = svg_logo(white=mark.WHITE, red=mark.WHITE, sub=mark.WHITE)
    (OUT / "kino-playback-logo-white.svg").write_text(white)
    black, _ = svg_logo(white=mark.BLACK, red=mark.BLACK, sub=mark.BLACK)
    (OUT / "kino-playback-logo-black.svg").write_text(black)
    icon(1024).convert("RGB").save(OUT / "kino-playback-icon-1024.png")
    # maskable: content inside the central 80% safe circle
    icon(1024, brackets=False, scale=0.52).convert("RGB").save(OUT / "kino-playback-icon-maskable.png")
    logo_png(OUT / "kino-playback-logo-transparent.png")
    logo_png(OUT / "kino-playback-logo-presentation.png", glow=True, transparent=False)
    icon(512, brackets=False, scale=1.0, alpha=True).save(OUT / "kino-playback-symbol-512.png")
    brand_pdf(OUT / "kino-playback-brand-guide.pdf")
    ios_icons()
    android_icons()
    dart_geometry()
    print("done")


if __name__ == "__main__":
    main()
