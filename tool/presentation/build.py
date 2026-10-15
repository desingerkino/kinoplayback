#!/usr/bin/env python3
"""Собирает видеопрезентацию KINO PLAYBACK из slides.yaml.

Для каждого слайда: картинка 1920x1080 (Pillow) + озвучка мужским голосом
(edge-tts, ru-RU-DmitryNeural) -> фрагмент MP4 (ffmpeg) -> общий MP4.

Запуск (в GitHub Actions это делает workflow):
    python3 tool/presentation/build.py --out build/presentation
Проверка без интернета (тишина вместо голоса):
    python3 tool/presentation/build.py --out /tmp/p --silent
"""
from __future__ import annotations

import argparse
import asyncio
import subprocess
import sys
import wave
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FONTS = ROOT / "assets" / "fonts"
BRAND = ROOT / "assets" / "brand"

W, H = 1920, 1080
BG = (10, 10, 10)
PANEL = (27, 27, 27)
WHITE = (255, 255, 255)
GREY = (154, 154, 154)
RED = (255, 30, 45)

PAD_END = 0.7      # пауза после речи, сек
FADE = 0.35        # затухание на стыках, сек
FPS = 30


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def title_font(text: str, size: int) -> ImageFont.FreeTypeFont:
    """Unbounded в репозитории без кириллицы: для русского заголовка берём Inter."""
    if text.isascii():
        return font("Unbounded-ExtraBold.ttf", size)
    return font("Inter-Bold.ttf", round(size * 1.08))


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_w: int) -> list[str]:
    lines: list[str] = []
    cur = ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def logo(width: int) -> Image.Image:
    im = Image.open(BRAND / "kino-playback-logo-transparent.png").convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def slide_title(s: dict) -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    if s["title"].strip().upper() == "KINO PLAYBACK":
        lg = logo(1100)
        img.paste(lg, ((W - lg.width) // 2, 250), lg)
        y = 250 + lg.height + 70
    else:
        d.text((W // 2, 420), s["title"], font=title_font(s["title"], 120),
               fill=WHITE, anchor="mm")
        y = 560
    sub = s.get("sub", "")
    if sub:
        d.text((W // 2, y), sub, font=font("Inter-Medium.ttf", 48), fill=GREY, anchor="mt")
    d.rectangle([W // 2 - 60, H - 150, W // 2 + 60, H - 144], fill=RED)
    return img


def slide_bullets(s: dict, idx: int, total: int) -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    mark = logo(220)
    img.paste(mark, (96, 70), mark)
    d.text((W - 96, 96), f"{idx:02d} / {total:02d}", font=font("Inter-Medium.ttf", 30),
           fill=GREY, anchor="ra")
    d.rectangle([96, 200, 96 + 90, 206], fill=RED)
    d.text((96, 240), s["title"], font=title_font(s["title"], 76), fill=WHITE)

    f = font("Inter-SemiBold.ttf", 46)
    max_w = W - 96 * 2 - 90
    y = 440
    for b in s["bullets"]:
        lines = wrap(d, b, f, max_w)
        block_h = len(lines) * 62
        d.rounded_rectangle([96, y, W - 96, y + block_h + 36], radius=18, fill=PANEL)
        d.rectangle([96, y + 18, 106, y + block_h + 18], fill=RED)
        for i, ln in enumerate(lines):
            d.text((146, y + 18 + i * 62), ln, font=f, fill=WHITE)
        y += block_h + 36 + 22
    return img


def render(slides: list[dict], out: Path) -> list[Path]:
    paths = []
    for i, s in enumerate(slides, 1):
        img = slide_title(s) if s.get("kind") == "title" else slide_bullets(s, i, len(slides))
        p = out / f"slide_{i:02d}.png"
        img.save(p)
        paths.append(p)
    return paths


async def _tts(text: str, voice: str, rate: str, dest: Path) -> None:
    import edge_tts

    last: Exception | None = None
    for attempt in range(4):
        try:
            await edge_tts.Communicate(text, voice, rate=rate).save(str(dest))
            if dest.exists() and dest.stat().st_size > 1000:
                return
        except Exception as e:  # сеть/сервис: повторяем
            last = e
        await asyncio.sleep(2 + attempt * 2)
    raise RuntimeError(f"Не удалось озвучить: {text[:40]!r}... ({last})")


def silent_wav(seconds: float, dest: Path) -> None:
    with wave.open(str(dest), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(b"\x00\x00" * int(24000 * seconds))


def probe_duration(path: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def make_audio(slides: list[dict], voice: str, rate: str, out: Path, silent: bool) -> list[Path]:
    paths = []
    for i, s in enumerate(slides, 1):
        text = " ".join(str(s["say"]).split())
        if silent:
            p = out / f"voice_{i:02d}.wav"
            silent_wav(max(3.0, len(text.split()) / 2.4), p)  # ~2.4 слова/сек
        else:
            p = out / f"voice_{i:02d}.mp3"
            asyncio.run(_tts(text, voice, rate, p))
        paths.append(p)
        print(f"  голос {i}/{len(slides)}: {p.name}", flush=True)
    return paths


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ffmpeg завершился с ошибкой:\n{' '.join(cmd)}\n{r.stderr[-2000:]}")


def make_segments(pngs: list[Path], auds: list[Path], out: Path) -> list[Path]:
    segs = []
    for i, (png, aud) in enumerate(zip(pngs, auds), 1):
        dur = probe_duration(aud) + PAD_END
        seg = out / f"seg_{i:02d}.mp4"
        vf = (f"fade=t=in:st=0:d={FADE},fade=t=out:st={dur - FADE:.3f}:d={FADE},"
              f"format=yuv420p")
        af = f"apad=pad_dur={PAD_END},afade=t=in:st=0:d=0.05"
        run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-framerate", str(FPS),
             "-i", str(png), "-i", str(aud), "-t", f"{dur:.3f}", "-vf", vf, "-af", af,
             "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-tune", "stillimage",
             "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
             str(seg)])
        segs.append(seg)
    return segs


def concat(segs: list[Path], dest: Path, out: Path) -> None:
    lst = out / "list.txt"
    lst.write_text("".join(f"file '{s.resolve()}'\n" for s in segs), encoding="utf-8")
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", "-movflags", "+faststart", str(dest)])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--slides", default=str(HERE / "slides.yaml"))
    ap.add_argument("--out", default="build/presentation")
    ap.add_argument("--silent", action="store_true", help="без голоса (проверка вёрстки)")
    ap.add_argument("--voice", default="")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.slides).read_text(encoding="utf-8"))
    slides = cfg["slides"]
    voice = args.voice or cfg.get("voice", "ru-RU-DmitryNeural")
    rate = str(cfg.get("rate", "+0%"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"Слайдов: {len(slides)}, голос: {voice if not args.silent else 'тишина'}")
    pngs = render(slides, out)
    auds = make_audio(slides, voice, rate, out, args.silent)
    segs = make_segments(pngs, auds, out)
    final = out / "KINO_PLAYBACK_presentation.mp4"
    concat(segs, final, out)
    print(f"Готово: {final} ({probe_duration(final):.0f} с, {final.stat().st_size / 1e6:.1f} МБ)")


if __name__ == "__main__":
    main()
