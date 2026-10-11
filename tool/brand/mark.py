"""KINO PLAYBACK mark geometry — single source of truth for SVG, PNG, PDF and
the in-app CustomPainter (lib/core/brand/kp_mark_geometry.dart is generated).

Traced from the approved app icon: a K block split by a diagonal gap
(white stem side / graphite side), a red play triangle pointing into the K,
and a red trapezoid lens on the right — a video camera seen from the side.
Coordinates are on a 512×512 grid.
"""
RED = "#FF1E2D"
RED_DARK = "#B3121C"
WHITE = "#FFFFFF"
LIGHT = "#E6E6E6"
GRAPHITE = "#2A2A2A"
GRAPHITE_DARK = "#121212"
BLACK = "#0A0A0A"
GREY = "#8C8C8C"

# Traced in the source icon's pixel space (832×825), then mapped to 512.
_SRC = {
    "upperWhite": [(160, 212), (288, 212), (288, 404), (160, 534)],
    "upperGraphite": [(288, 212), (479, 212), (288, 404)],
    "lowerWhite": [(160, 556), (288, 427), (288, 600), (160, 600)],
    "lowerGraphite": [(288, 427), (470, 600), (288, 600)],
    "play": [(306, 410), (560, 262), (560, 598)],
    "lens": [(596, 352), (660, 312), (660, 528), (596, 482)],
}
_S = 400 / (660 - 160)
_CX, _CY = (160 + 660) / 2, (212 + 600) / 2


def _map(p):
    return (round(256 + (p[0] - _CX) * _S, 2), round(256 + (p[1] - _CY) * _S, 2))


PARTS = {k: [_map(p) for p in v] for k, v in _SRC.items()}
ROLE = {
    "upperWhite": "white",
    "lowerWhite": "white",
    "upperGraphite": "graphite",
    "lowerGraphite": "graphite",
    "play": "red",
    "lens": "red",
}


def shapes(white=WHITE, red=RED, graphite=GRAPHITE):
    col = {"white": white, "graphite": graphite, "red": red}
    return [(k, col[ROLE[k]], pts) for k, pts in PARTS.items()]


def bounds():
    pts = [p for v in PARTS.values() for p in v]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)
