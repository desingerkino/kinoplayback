"""KINO PLAYBACK mark geometry — single source of truth for SVG, PNG, PDF and
the in-app CustomPainter (lib/core/brand/kp_mark_geometry.dart is generated).

512×512 grid. The mark is a K: a white stem, a white upper arm, and a red
play triangle that forms the K's lower arm. In the app-icon version, four red
corner brackets frame it like a camera viewfinder.
"""
RED = "#FF1E2D"
WHITE = "#FFFFFF"
BLACK = "#0A0A0A"
GRAPHITE = "#1B1B1B"
GREY = "#8C8C8C"

STEM = [(96, 96), (168, 96), (168, 416), (96, 416)]
ARM = [(188, 236), (310, 96), (404, 96), (240, 284)]
PLAY = [(204, 288), (204, 416), (420, 352)]


def shapes(white=WHITE, red=RED):
    return [("stem", white, STEM), ("arm", white, ARM), ("play", red, PLAY)]


def bounds():
    pts = STEM + ARM + PLAY
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def brackets(size=512, inset=40, length=72, thick=14):
    """Viewfinder corner brackets as polygons (for the app icon)."""
    s, i, l, t = size, inset, length, thick
    out = []
    for cx, cy, dx, dy in [(i, i, 1, 1), (s - i, i, -1, 1), (i, s - i, 1, -1), (s - i, s - i, -1, -1)]:
        out.append([(cx, cy), (cx + dx * l, cy), (cx + dx * l, cy + dy * t), (cx + dx * t, cy + dy * t),
                    (cx + dx * t, cy + dy * l), (cx, cy + dy * l)])
    return out
