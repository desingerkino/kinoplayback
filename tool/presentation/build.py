#!/usr/bin/env python3
"""Собирает видеопрезентацию KINO PLAYBACK из slides.yaml.

Слайд = картинка или анимированная сцена (scenes.py) + озвучка мужским голосом
(edge-tts, ru-RU-DmitryNeural) + вшитые субтитры. Озвучка делается по фразам,
по ним же строятся субтитры и тайминг.

Запуск (в GitHub Actions это делает workflow):
    python3 tool/presentation/build.py --out build/presentation
Проверка без интернета (тишина вместо голоса):
    python3 tool/presentation/build.py --out /tmp/p --silent
"""
from __future__ import annotations

import argparse
import asyncio
import math
import re
import subprocess
import sys
import wave
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scenes  # noqa: E402

ROOT = HERE.parents[1]
FONTS = ROOT / "assets" / "fonts"
BRAND = ROOT / "assets" / "brand"

W, H = 1920, 1080
BG = (10, 10, 10)
PANEL = (27, 27, 27)
WHITE = (255, 255, 255)
GREY = (154, 154, 154)
RED = (255, 30, 45)

GAP = 0.38         # пауза между фразами, сек
PAD_END = 0.7      # пауза после последней фразы
FADE = 0.35        # затухание на стыках
FPS = 30
SUB_BOTTOM = 1040  # нижний край субтитра: 40 px от низа кадра
SUB_MAX_W = 1560
MAX_CHUNK = 120    # символов в одной фразе субтитра


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


# ------------------------------------------------------------------ слайды
def slide_title(s: dict) -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    if s["title"].strip().upper() == "KINO PLAYBACK":
        lg = logo(1100)
        img.paste(lg, ((W - lg.width) // 2, 220), lg)
        y = 220 + lg.height + 70
    else:
        d.text((W // 2, 400), s["title"], font=title_font(s["title"], 120), fill=WHITE, anchor="mm")
        y = 520
    if s.get("sub"):
        d.text((W // 2, y), s["sub"], font=font("Inter-Medium.ttf", 48), fill=GREY, anchor="mt")
    d.rectangle([W // 2 - 60, 790, W // 2 + 60, 796], fill=RED)
    return img


def slide_bullets(s: dict, idx: int, total: int) -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    mark = logo(200)
    img.paste(mark, (96, 56), mark)
    d.text((W - 96, 86), f"{idx:02d} / {total:02d}", font=font("Inter-Medium.ttf", 30), fill=GREY, anchor="ra")
    d.rectangle([96, 190, 96 + 90, 196], fill=RED)
    d.text((96, 214), s["title"], font=title_font(s["title"], 72), fill=WHITE)

    top, bottom = 340, 850
    for size in range(46, 31, -2):
        f = font("Inter-SemiBold.ttf", size)
        lh = round(size * 1.3)
        max_w = W - 96 * 2 - 90
        blocks = [wrap(d, b, f, max_w) for b in s["bullets"]]
        total_h = sum(len(b) * lh + 32 + 18 for b in blocks)
        if top + total_h <= bottom:
            break
    else:
        sys.exit(f"Слайд «{s['title']}»: пункты не помещаются в кадр, сократи текст")
    y = top
    for lines in blocks:
        bh = len(lines) * lh
        d.rounded_rectangle([96, y, W - 96, y + bh + 32], radius=18, fill=PANEL)
        d.rectangle([96, y + 16, 106, y + bh + 16], fill=RED)
        for i, ln in enumerate(lines):
            d.text((146, y + 16 + i * lh), ln, font=f, fill=WHITE)
        y += bh + 32 + 18
    return img


# ------------------------------------------------------------- фразы и субтитры
def chunks(text: str) -> list[str]:
    text = " ".join(str(text).split())
    out: list[str] = []
    for sent in re.split(r"(?<=[.!?])\s+", text):
        sent = sent.strip()
        while len(sent) > MAX_CHUNK:
            cut = max(sent.rfind(", ", 0, MAX_CHUNK), sent.rfind(" и ", 0, MAX_CHUNK))
            if cut < 40:
                cut = sent.rfind(" ", 0, MAX_CHUNK)
            piece = sent[: cut + 1].strip()
            out.append(piece)
            sent = sent[cut + 1:].strip()
        if sent:
            out.append(sent)
    return out


_sub_cache: dict[str, Image.Image] = {}


def subtitle_strip(text: str) -> Image.Image:
    """RGBA-полоса субтитра на всю ширину кадра, нижний край на SUB_BOTTOM."""
    if text in _sub_cache:
        return _sub_cache[text]
    tmp = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    for size in (46, 44, 42, 40):
        f = font("Inter-Medium.ttf", size)
        lines = wrap(tmp, text, f, SUB_MAX_W)
        if len(lines) <= 2:
            break
    else:
        sys.exit(f"Субтитр не помещается в 2 строки: {text!r}")
    lh = round(size * 1.3)
    box_h = len(lines) * lh + 36
    strip = Image.new("RGBA", (W, box_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(strip)
    widest = max(tmp.textlength(ln, font=f) for ln in lines)
    x0, x1 = W / 2 - widest / 2 - 36, W / 2 + widest / 2 + 36
    d.rounded_rectangle([x0, 0, x1, box_h - 1], radius=22, fill=(0, 0, 0, 205))
    for i, ln in enumerate(lines):
        d.text((W / 2, 18 + i * lh), ln, font=f, fill=WHITE, anchor="ma")
    _sub_cache[text] = strip
    return strip


def add_subtitle(img: Image.Image, text: str) -> Image.Image:
    strip = subtitle_strip(text)
    out = img.copy()
    out.paste(strip, (0, SUB_BOTTOM - strip.height), strip)
    return out


# ------------------------------------------------------------------- озвучка
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


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"Команда завершилась с ошибкой:\n{' '.join(cmd)}\n{r.stderr[-2000:]}")


RATE = 24000


def silence_frames(seconds: float) -> bytes:
    return b"\x00\x00" * int(RATE * seconds)


def read_wav(path: Path) -> bytes:
    with wave.open(str(path), "rb") as w:
        return w.readframes(w.getnframes())


def make_slide_audio(chs: list[str], voice: str, rate: str, work: Path, tag: str, silent: bool):
    """Возвращает (wav-файл, список (старт, конец, текст))."""
    pcm = b""
    cues = []
    t = 0.0
    for i, text in enumerate(chs):
        if silent:
            data = silence_frames(max(1.2, len(text.split()) / 2.4 + 0.3))
        else:
            mp3 = work / f"{tag}_{i}.mp3"
            wav = work / f"{tag}_{i}.wav"
            asyncio.run(_tts(text, voice, rate, mp3))
            trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.04,areverse,"
                    "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.04,areverse")
            run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3), "-af", trim, "-ar", str(RATE),
                 "-ac", "1", "-f", "wav", str(wav)])
            data = read_wav(wav)
        dur = len(data) / 2 / RATE
        pcm += data + silence_frames(GAP)
        cues.append((t, t + dur + GAP, text))
        t += dur + GAP
    pcm += silence_frames(PAD_END)
    out = work / f"{tag}.wav"
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    return out, cues, len(pcm) / 2 / RATE


# --------------------------------------------------------------------- видео
def encode_args(dur: float) -> tuple[list[str], list[str]]:
    vf = (f"fade=t=in:st=0:d={FADE},fade=t=out:st={dur - FADE:.3f}:d={FADE},format=yuv420p")
    af = "afade=t=in:st=0:d=0.05"
    tail = ["-vf", vf, "-af", af, "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-t", f"{dur:.3f}"]
    return tail, []


def segment_static(base: Image.Image, cues, wav: Path, dur: float, work: Path, tag: str) -> Path:
    """Статичный слайд: кадры подаются в ffmpeg по трубе, как и у сцен."""
    seg = work / f"{tag}.mp4"
    tail, _ = encode_args(dur)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-framerate", str(FPS), "-i", "-", "-i", str(wav), *tail, str(seg)]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    n = math.ceil(dur * FPS)
    cache: dict[str, bytes] = {}
    try:
        for i in range(n):
            t = i / FPS
            text = next((c[2] for c in cues if c[0] <= t < c[1]), cues[-1][2] if t >= cues[-1][0] else None)
            key = text or ""
            if key not in cache:
                cache[key] = (add_subtitle(base, text) if text else base).tobytes()
            p.stdin.write(cache[key])
        p.stdin.close()
    except BrokenPipeError:
        pass
    err = p.stderr.read().decode("utf-8", "replace")
    if p.wait() != 0:
        sys.exit(f"ffmpeg (слайд {tag}) завершился с ошибкой:\n{err[-2000:]}")
    return seg


def segment_scene(s: dict, cues, wav: Path, dur: float, work: Path, tag: str) -> Path:
    seg = work / f"{tag}.mp4"
    tail, _ = encode_args(dur)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-framerate", str(FPS), "-i", "-", "-i", str(wav), *tail, str(seg)]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    n = math.ceil(dur * FPS)
    walk = float(s.get("walk", 0))
    rec_at = s.get("rec_at")
    try:
        for i in range(n):
            t = i / FPS
            frame = scenes.scene_frame(s["scene"], t, walk, rec_at)
            text = next((c[2] for c in cues if c[0] <= t < c[1]), None)
            if text:
                frame = add_subtitle(frame, text)
            p.stdin.write(frame.tobytes())
        p.stdin.close()
    except BrokenPipeError:
        pass
    err = p.stderr.read().decode("utf-8", "replace")
    if p.wait() != 0:
        sys.exit(f"ffmpeg (сцена {tag}) завершился с ошибкой:\n{err[-2000:]}")
    return seg


def concat(segs: list[Path], dest: Path, work: Path) -> None:
    lst = work / "list.txt"
    lst.write_text("".join(f"file '{s.resolve()}'\n" for s in segs), encoding="utf-8")
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", "-movflags", "+faststart", str(dest)])


def probe_duration(path: Path) -> float:
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "default=nw=1:nk=1", str(path)], capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--slides", default=str(HERE / "slides.yaml"))
    ap.add_argument("--out", default="build/presentation")
    ap.add_argument("--silent", action="store_true", help="без голоса (проверка вёрстки)")
    ap.add_argument("--voice", default="")
    ap.add_argument("--only", default="", help="номера слайдов через запятую (отладка)")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.slides).read_text(encoding="utf-8"))
    slides = cfg["slides"]
    voice = args.voice or cfg.get("voice", "ru-RU-DmitryNeural")
    rate = str(cfg.get("rate", "+0%"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    only = {int(x) for x in args.only.split(",") if x.strip()}

    print(f"Слайдов: {len(slides)}, голос: {voice if not args.silent else 'тишина'}", flush=True)
    segs = []
    for i, s in enumerate(slides, 1):
        if only and i not in only:
            continue
        tag = f"s{i:02d}"
        chs = chunks(s["say"])
        wav, cues, dur = make_slide_audio(chs, voice, rate, out, tag, args.silent)
        kind = s.get("kind", "bullets")
        if kind == "scene":
            seg = segment_scene(s, cues, wav, dur, out, tag)
        else:
            base = slide_title(s) if kind == "title" else slide_bullets(s, i, len(slides))
            base.save(out / f"slide_{i:02d}.png")
            seg = segment_static(base, cues, wav, dur, out, tag)
        segs.append(seg)
        print(f"  слайд {i}/{len(slides)} ({kind}): {dur:.1f} с, фраз {len(cues)}", flush=True)
    final = out / "KINO_PLAYBACK_presentation.mp4"
    concat(segs, final, out)
    print(f"Готово: {final} ({probe_duration(final):.0f} с, {final.stat().st_size / 1e6:.1f} МБ)")


if __name__ == "__main__":
    main()
