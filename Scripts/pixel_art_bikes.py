"""Parametric pixel-art motorcycle sprites.

Bikes are drawn from smooth spline outlines at 4x supersampling and reduced to
a 170x106 logical pixel grid with a mode filter, so bodywork curves read as
clean pixel steps while wheels and machined parts stay crisp. Every fill comes
from a small NES-flavoured palette, then a 1px ink keyline is grown around the
silhouette.

Output matches the shape of the hand-finished art in ``bikes/``: one RGBA PNG
per model generation, transparent background, bike only.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageFilter

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

INK = (10, 10, 14)
BLACK = (28, 28, 34)
TIRE = (34, 34, 40)
DGRAY = (62, 62, 70)
MGRAY = (112, 112, 122)
LGRAY = (170, 170, 180)
WHITE = (238, 238, 242)
PALE = (252, 250, 238)

RED = (206, 38, 44)
DRED = (126, 20, 26)
ORANGE = (234, 118, 30)
AMBER = (246, 168, 40)
YELLOW = (248, 216, 72)
GREEN = (118, 194, 58)
DGREEN = (44, 104, 38)
BLUE = (46, 108, 206)
DBLUE = (24, 44, 112)
CYAN = (86, 210, 230)
GLASS = (46, 80, 106)
CHROME = (198, 202, 212)
BRONZE = (146, 106, 62)

GROUND = 90
SS = 4  # supersampling factor

# 3x5 bitmap font, one string per row.
FONT = {
    "A": ("010", "101", "111", "101", "101"),
    "B": ("110", "101", "110", "101", "110"),
    "C": ("011", "100", "100", "100", "011"),
    "D": ("110", "101", "101", "101", "110"),
    "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"),
    "G": ("011", "100", "101", "101", "011"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "J": ("001", "001", "001", "101", "010"),
    "K": ("101", "101", "110", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "N": ("110", "101", "101", "101", "101"),
    "O": ("010", "101", "101", "101", "010"),
    "P": ("110", "101", "110", "100", "100"),
    "Q": ("010", "101", "101", "110", "011"),
    "R": ("110", "101", "110", "101", "101"),
    "S": ("011", "100", "010", "001", "110"),
    "T": ("111", "010", "010", "010", "010"),
    "U": ("101", "101", "101", "101", "011"),
    "V": ("101", "101", "101", "101", "010"),
    "W": ("101", "101", "111", "111", "101"),
    "X": ("101", "101", "010", "101", "101"),
    "Y": ("101", "101", "010", "010", "010"),
    "Z": ("111", "001", "010", "100", "111"),
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "001", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
    "-": ("000", "000", "111", "000", "000"),
    ".": ("000", "000", "000", "000", "010"),
    " ": ("000", "000", "000", "000", "000"),
}


# ---------------------------------------------------------------------------
# Splines
# ---------------------------------------------------------------------------


def _cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return (
        0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
               + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
        0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
               + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
    )


def spline(points, per=10, closed=True):
    """Catmull-Rom through `points`; returns a dense polygon."""
    pts = [tuple(p) for p in points]
    n = len(pts)
    if n < 3:
        return pts
    out = []
    last = n if closed else n - 1
    for i in range(last):
        p1 = pts[i % n]
        p0 = pts[(i - 1) % n] if (closed or i > 0) else p1
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        for j in range(per):
            out.append(_cr(p0, p1, p2, p3, j / per))
    if not closed:
        out.append(pts[-1])
    return out


# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------


class Canvas:
    """Supersampled raster reduced to a crisp logical pixel grid."""

    def __init__(self, width=170, height=106, zoom=1.0):
        self.w = width
        self.h = height
        self.zoom = zoom
        self.W = width * SS
        self.H = height * SS
        self.rgb = np.zeros((self.H, self.W, 3), np.uint8)
        self.a = np.zeros((self.H, self.W), bool)

    # -- rasteriser --------------------------------------------------------

    def poly(self, pts, color):
        if len(pts) < 3:
            return
        pts = [(x * SS * self.zoom, y * SS * self.zoom) for x, y in pts]
        ys = [p[1] for p in pts]
        y0 = max(0, int(math.floor(min(ys))))
        y1 = min(self.H - 1, int(math.floor(max(ys))))
        n = len(pts)
        for y in range(y0, y1 + 1):
            sy = y + 0.5
            xs = []
            for i in range(n):
                ax, ay = pts[i]
                bx, by = pts[(i + 1) % n]
                if ay == by:
                    continue
                if (ay <= sy < by) or (by <= sy < ay):
                    t = (sy - ay) / (by - ay)
                    xs.append(ax + t * (bx - ax))
            if not xs:
                continue
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                x0 = max(0, int(math.ceil(xs[i] - 0.5)))
                x1 = min(self.W - 1, int(math.floor(xs[i + 1] - 0.5)))
                if x1 >= x0:
                    self.rgb[y, x0 : x1 + 1] = color
                    self.a[y, x0 : x1 + 1] = True

    def shape(self, pts, color, per=10, closed=True):
        self.poly(spline(pts, per=per, closed=closed), color)

    def ellipse(self, cx, cy, rx, ry, color):
        pts = [(cx + rx * math.cos(2 * math.pi * i / 48), cy + ry * math.sin(2 * math.pi * i / 48))
               for i in range(48)]
        self.poly(pts, color)

    def disc(self, cx, cy, r, color):
        self.ellipse(cx, cy, r, r, color)

    def ring(self, cx, cy, r_out, r_in, color):
        pts = [(cx + r_out * math.cos(2 * math.pi * i / 48), cy + r_out * math.sin(2 * math.pi * i / 48))
               for i in range(48)]
        pts += [(cx + r_in * math.cos(2 * math.pi * i / 48), cy + r_in * math.sin(2 * math.pi * i / 48))
                for i in range(47, -1, -1)]
        self.poly(pts, color)

    def rect(self, x0, y0, x1, y1, color):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], color)

    def line_path(self, spine, width, color):
        left, right = [], []
        n = len(spine)
        for i in range(n):
            p = spine[i]
            q = spine[min(i + 1, n - 1)]
            r = spine[max(i - 1, 0)]
            dx, dy = q[0] - r[0], q[1] - r[1]
            d = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / d * width / 2, dx / d * width / 2
            left.append((p[0] + nx, p[1] + ny))
            right.append((p[0] - nx, p[1] - ny))
        self.poly(left + right[::-1], color)

    def line(self, p0, p1, width, color):
        self.line_path([p0, p1], width, color)

    def band(self, pts, width, color):
        self.line_path(spline(pts, per=8, closed=False), width, color)

    def arc(self, cx, cy, r_in, r_out, a0, a1, color, steps=28):
        outer, inner = [], []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            outer.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
            inner.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
        self.poly(outer + inner[::-1], color)

    def text(self, s, x, y, color, spacing=1):
        cx = x
        for ch in s.upper():
            g = FONT.get(ch, FONT[" "])
            for row in range(5):
                for col in range(3):
                    if g[row][col] == "1":
                        self.rect(cx + col, y + row, cx + col + 1, y + row + 1, color)
            cx += 3 + spacing

    # -- finishing ---------------------------------------------------------

    def _reduce(self):
        """Box-mode downsample: most common colour in each SS block wins."""
        h, w, s = self.h, self.w, SS
        blocks = self.rgb.reshape(h, s, w, s, 3).transpose(0, 2, 1, 3, 4).reshape(h, w, s * s, 3)
        alpha = self.a.reshape(h, s, w, s).transpose(0, 2, 1, 3).reshape(h, w, s * s)
        packed = (blocks[..., 0].astype(np.int32) << 16) | (blocks[..., 1].astype(np.int32) << 8) | blocks[..., 2]
        packed = np.where(alpha, packed, -1)

        out = np.zeros((h, w, 3), np.uint8)
        vis = np.zeros((h, w), bool)

        first = packed[..., 0]
        uniform = np.all(packed == first[..., None], axis=-1) & (first >= 0)
        v = first[uniform]
        out[uniform, 0] = (v >> 16) & 255
        out[uniform, 1] = (v >> 8) & 255
        out[uniform, 2] = v & 255
        vis[uniform] = True

        rest = (~uniform) & (packed.max(axis=-1) >= 0)
        for y, x in np.argwhere(rest):
            row = packed[y, x]
            row = row[row >= 0]
            vals, counts = np.unique(row, return_counts=True)
            v = int(vals[counts.argmax()])
            out[y, x] = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
            vis[y, x] = True
        return out, vis

    def outline_silhouette(self, color=INK):
        a = self.a
        grown = a.copy()
        grown[1:, :] |= a[:-1, :]
        grown[:-1, :] |= a[1:, :]
        grown[:, 1:] |= a[:, :-1]
        grown[:, :-1] |= a[:, 1:]
        border = grown & ~a
        self.rgb[border] = color
        self.a = grown

    def to_image(self, scale=7, pad=2):
        rgb, mask = self._reduce()
        if not mask.any():
            raise ValueError("empty canvas")
        ys, xs = np.where(mask)
        y0, y1 = max(0, ys.min() - pad), min(self.h - 1, ys.max() + pad)
        x0, x1 = max(0, xs.min() - pad), min(self.w - 1, xs.max() + pad)
        rgba = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), np.uint8)
        rgba[..., :3] = rgb[y0 : y1 + 1, x0 : x1 + 1]
        rgba[..., 3] = np.where(mask[y0 : y1 + 1, x0 : x1 + 1], 255, 0)
        img = Image.fromarray(rgba, "RGBA")
        return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


# ---------------------------------------------------------------------------
# Sub-assemblies
# ---------------------------------------------------------------------------


def wheel(cv, cx, cy, r, rim=CHROME, spokes=5, wire=False, rotor=False, tire=TIRE):
    cv.disc(cx, cy, r, tire)
    cv.ring(cx, cy, r * 0.74, r * 0.62, rim)
    cv.disc(cx, cy, r * 0.62, BLACK)
    if rotor:
        cv.ring(cx, cy, r * 0.56, r * 0.44, MGRAY)
    for k in range(spokes):
        a = 2 * math.pi * k / spokes + 0.4
        cv.line((cx, cy), (cx + r * 0.64 * math.cos(a), cy + r * 0.64 * math.sin(a)),
                2.0 if not wire else 0.7, rim)
    cv.disc(cx, cy, r * 0.24, rim)
    cv.disc(cx, cy, r * 0.10, DGRAY)


def caliper(cv, cx, cy, r, a_deg):
    a = math.radians(a_deg)
    x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    cv.rect(x - 2.2, y - 3.2, x + 2.2, y + 3.2, BLACK)
    cv.rect(x - 1.6, y - 2.4, x + 1.6, y + 2.4, AMBER)


def engine(cv, pts, color=DGRAY, fins=True):
    cv.shape(pts, color)
    if fins:
        ys = [p[1] for p in pts]
        xs = [p[0] for p in pts]
        for y in np.arange(min(ys) + 3, max(ys) - 2, 2.2):
            cv.line((min(xs) + 3, y), (max(xs) - 3, y), 0.8, BLACK)


def fork(cv, top, bottom, width=3.2, upper=LGRAY, lower=DGRAY):
    cv.line(top, bottom, width, upper)
    mid = ((top[0] + bottom[0]) / 2, (top[1] + bottom[1]) / 2)
    cv.line(mid, bottom, width * 0.9, lower)


def mirror(cv, x, y):
    cv.line((x, y), (x + 1, y - 3), 1.0, INK)
    cv.shape([(x, y - 4), (x + 5, y - 4.5), (x + 5, y - 2.5), (x, y - 2)], INK, per=4)
    cv.shape([(x + 1, y - 4), (x + 4, y - 4.2), (x + 4, y - 3), (x + 1, y - 2.8)], CHROME, per=4)


def exhaust_tip(cv, x, y, w=4, h=5):
    cv.rect(x, y, x + w, y + h, CHROME)
    cv.rect(x + w - 1.4, y + 1, x + w, y + h - 1, DGRAY)


# ---------------------------------------------------------------------------
# Liveries
# ---------------------------------------------------------------------------


class Livery:
    def __init__(self, primary, dark, light, accent, frame=BLACK, word=""):
        self.primary = primary
        self.dark = dark
        self.light = light
        self.accent = accent
        self.frame = frame
        self.word = word


# ---------------------------------------------------------------------------
# Sportbike
# ---------------------------------------------------------------------------


def sport_bike(lv: Livery) -> Canvas:
    cv = Canvas()
    rw = (40, 70, 19)
    fw = (142, 70, 19)

    wheel(cv, *rw)

    # swingarm, chain, shock
    cv.line((78, 65), (40, 70), 5.2, LGRAY)
    cv.line((78, 68), (40, 70), 1.0, DGRAY)
    cv.line((72, 62), (66, 44), 2.4, CHROME)
    cv.ring(69, 53, 2.2, 1.0, AMBER)

    # frame spar from the headstock
    cv.band([(88, 58), (100, 53), (116, 49)], 4.4, lv.frame)

    # engine
    engine(cv, [(80, 58), (96, 58), (102, 70), (100, 80), (84, 80), (79, 70)])

    # exhaust can under the tail
    cv.shape([(46, 66), (62, 60), (74, 59), (76, 66), (62, 70), (48, 73)], CHROME, per=6)
    cv.band([(48, 67), (64, 61.5), (74, 61)], 1.2, WHITE)
    exhaust_tip(cv, 46, 68)

    # tail unit
    cv.shape([(26, 52), (31, 44), (44, 39), (58, 36), (72, 39), (76, 46), (70, 50),
              (50, 52), (34, 52)], lv.primary, per=10)
    cv.shape([(29, 50), (34, 45), (46, 40.5), (58, 38), (70, 40), (70, 43), (56, 44),
              (38, 47)], lv.light, per=6)

    # seat pad
    cv.shape([(52, 40), (68, 38), (78, 42), (76, 48), (58, 47)], BLACK, per=6)

    # tank
    cv.shape([(76, 40), (90, 35), (102, 37), (110, 45), (106, 52), (90, 55), (78, 52)],
             lv.primary, per=10)
    cv.band([(80, 42), (92, 37.5), (101, 39)], 1.8, lv.light)
    cv.band([(79, 49), (95, 47), (106, 49)], 1.6, lv.accent)

    # upper fairing / nose, overhanging the front wheel
    cv.shape([(104, 52), (124, 47), (146, 43), (158, 48), (160, 57), (150, 61),
              (130, 61), (112, 58)], lv.primary, per=10)
    cv.band([(112, 53), (132, 50), (150, 47)], 1.6, lv.light)

    # side fairing / belly
    cv.shape([(100, 56), (130, 60), (147, 62), (143, 73), (128, 81), (108, 82),
              (97, 76), (93, 64)], lv.primary, per=10)
    cv.shape([(99, 70), (120, 78), (140, 72), (134, 82), (114, 83), (100, 79)],
             lv.dark, per=8)
    cv.shape([(108, 63), (122, 66), (123, 72), (109, 69)], BLACK, per=5)
    cv.band([(101, 58), (124, 60), (143, 64)], 2.0, lv.accent)

    # windscreen
    cv.shape([(136, 45), (152, 34), (161, 45), (147, 49)], GLASS, per=8)
    cv.band([(137, 45), (152, 36), (159, 45)], 1.0, CYAN)

    # headlight
    cv.shape([(148, 50), (159, 50), (158, 61), (148, 59)], PALE, per=6)
    cv.band([(151, 53), (156, 53)], 1.2, AMBER)

    # front wheel drawn last so nothing floats over it
    wheel(cv, *fw, rotor=True)
    caliper(cv, *fw, a_deg=-56)

    # front fender (drawn behind the tyre so only the crown shows)
    cv.arc(142, 70, 21, 24, 205, 325, lv.primary)
    cv.arc(142, 70, 21, 22.4, 205, 325, lv.light)

    # forks + clip-on + mirror
    fork(cv, (134, 46), (142, 70), width=3.6)
    fork(cv, (126, 51), (136, 64), width=2.0)
    cv.line((128, 44), (116, 40), 2.8, BLACK)
    cv.line((128, 44), (116, 40), 1.1, MGRAY)
    mirror(cv, 115, 38)

    # rear hugger
    cv.arc(40, 70, 19, 22, 250, 345, lv.dark)

    if lv.word:
        cv.text(lv.word[:6], 106, 74, WHITE)

    cv.outline_silhouette()
    return cv


def naked_bike(lv: Livery) -> Canvas:
    cv = Canvas()
    rw = (40, 70, 18)
    fw = (134, 70, 18)

    wheel(cv, *rw)
    wheel(cv, *fw, rotor=True)
    caliper(cv, *fw, a_deg=-50)

    cv.line((78, 65), (40, 70), 5.0, LGRAY)

    # trellis frame
    for a, b in [((70, 62), (120, 49)), ((74, 68), (116, 52)), ((120, 49), (84, 58)),
                 ((110, 50), (76, 66)), ((84, 58), (104, 70))]:
        cv.line(a, b, 2.4, lv.frame)

    # V-twin
    cv.shape([(78, 58), (100, 58), (102, 79), (80, 79)], DGRAY, per=6)
    cv.shape([(74, 50), (90, 53), (87, 64), (71, 61)], LGRAY, per=6)
    cv.shape([(92, 53), (104, 58), (99, 69), (88, 64)], LGRAY, per=6)
    for y in np.arange(53, 78, 2.6):
        cv.line((80, y), (100, y), 0.9, BLACK)

    # exhaust
    cv.shape([(48, 66), (64, 61), (76, 60), (78, 67), (64, 71), (50, 73)], CHROME, per=6)
    exhaust_tip(cv, 48, 68)

    # tail + seat
    cv.shape([(28, 50), (34, 43), (48, 39), (60, 40), (66, 46), (50, 50), (36, 51)], lv.primary, per=8)
    cv.shape([(48, 43), (64, 41), (72, 45), (68, 49), (54, 47)], BLACK, per=6)

    # tank
    cv.shape([(74, 40), (90, 36), (102, 39), (108, 47), (100, 55), (80, 54), (72, 47)],
             lv.primary, per=10)
    cv.band([(77, 42), (91, 38), (101, 40)], 1.8, lv.light)
    cv.band([(76, 49), (92, 47), (102, 49)], 1.6, lv.accent)

    # round headlight + flyscreen
    cv.disc(126, 46, 9, MGRAY)
    cv.disc(126, 46, 7.4, CHROME)
    cv.disc(126, 46, 6.0, PALE)
    cv.disc(126, 46, 2.6, AMBER)
    cv.shape([(118, 38), (131, 33), (136, 42), (124, 43)], GLASS, per=8)

    # forks + bars + mirror
    fork(cv, (126, 44), (134, 70), width=3.4)
    cv.line((124, 42), (110, 38), 3.0, BLACK)
    cv.line((124, 42), (110, 38), 1.2, MGRAY)
    mirror(cv, 109, 36)

    cv.arc(134, 70, 19, 22, 205, 330, lv.primary)

    if lv.word:
        cv.text(lv.word[:6], 84, 70, WHITE)

    cv.outline_silhouette()
    return cv


def cruiser_bike(lv: Livery) -> Canvas:
    cv = Canvas()
    rw = (38, 73, 15)
    fw = (146, 64, 20)

    wheel(cv, *rw, spokes=6)
    wheel(cv, *fw, spokes=6, rotor=True)

    # low frame spine
    cv.band([(52, 66), (96, 60), (136, 55)], 4.2, lv.frame)
    cv.line((100, 58), (104, 78), 3.6, lv.frame)

    # V-twin
    cv.shape([(84, 54), (104, 53), (106, 79), (86, 79)], DGRAY, per=6)
    cv.shape([(84, 47), (98, 50), (95, 61), (81, 58)], LGRAY, per=6)
    cv.shape([(100, 50), (110, 56), (105, 66), (96, 61)], LGRAY, per=6)
    for y in np.arange(50, 78, 2.8):
        cv.line((86, y), (104, y), 0.9, BLACK)

    # air cleaner
    cv.disc(97, 66, 6.6, CHROME)
    cv.disc(97, 66, 4.6, BLACK)

    # peanut tank
    cv.shape([(84, 43), (102, 41), (110, 48), (104, 54), (86, 52)], lv.primary, per=8)
    cv.band([(87, 45), (101, 43), (107, 48)], 1.6, lv.accent)

    # seat + rear fender
    cv.shape([(52, 54), (84, 51), (86, 59), (54, 62)], BLACK, per=6)
    cv.arc(38, 73, 16, 20, 190, 350, lv.primary)

    # front fender
    cv.arc(146, 64, 21, 25, 190, 345, lv.primary)
    cv.arc(146, 64, 21, 22.4, 190, 345, lv.accent)

    # long raked forks + high bars
    fork(cv, (126, 32), (146, 64), width=3.8)
    cv.line((125, 33), (112, 24), 3.2, BLACK)
    cv.line((112, 24), (102, 26), 2.6, BLACK)
    cv.line((112, 24), (102, 26), 1.0, MGRAY)
    mirror(cv, 120, 25)

    # long low pipe
    cv.band([(98, 78), (66, 76), (44, 72)], 4.6, CHROME)
    cv.shape([(30, 68), (48, 70), (48, 76), (30, 75)], MGRAY, per=4)
    cv.rect(30, 69, 32, 74, DGRAY)

    # belt drive
    cv.line((38, 73), (70, 68), 1.6, DGRAY)

    cv.outline_silhouette()
    return cv


def adventure_bike(lv: Livery) -> Canvas:
    cv = Canvas()
    rw = (40, 71, 16)
    fw = (140, 66, 20)

    wheel(cv, *rw, wire=True)
    wheel(cv, *fw, wire=True, rotor=True)

    # telelever arm + boxer engine
    cv.line((140, 66), (110, 58), 4.0, LGRAY)
    cv.shape([(84, 58), (104, 57), (106, 79), (86, 80)], DGRAY, per=6)
    cv.shape([(72, 61), (86, 59), (88, 74), (74, 76)], LGRAY, per=6)
    for y in np.arange(62, 75, 2.4):
        cv.line((74, y), (87, y), 0.9, MGRAY)

    # high exhaust + can
    cv.band([(102, 74), (98, 56), (86, 50)], 3.6, CHROME)
    cv.shape([(48, 52), (68, 50), (70, 58), (50, 60)], CHROME, per=4)

    # tail + seat
    cv.shape([(30, 48), (40, 42), (58, 40), (68, 44), (62, 52), (36, 53)], lv.primary, per=8)
    cv.shape([(48, 44), (72, 43), (76, 51), (50, 53)], BLACK, per=6)

    # tank
    cv.shape([(72, 42), (92, 38), (106, 42), (112, 52), (102, 60), (78, 58), (70, 50)],
             lv.primary, per=10)
    cv.shape([(75, 44), (93, 40), (105, 44), (107, 50), (94, 48), (77, 48)],
             lv.accent, per=6)
    cv.text("GS", 82, 50, WHITE)

    # tall screen + beak
    cv.shape([(112, 32), (128, 26), (136, 40), (116, 42)], GLASS, per=8)
    cv.band([(113, 33), (127, 28), (134, 39)], 1.0, CYAN)
    cv.shape([(130, 46), (158, 50), (156, 57), (128, 54)], lv.light, per=8)

    # forks + wide bars with handguards
    fork(cv, (124, 42), (140, 66), width=3.6)
    cv.line((122, 41), (108, 36), 3.2, BLACK)
    cv.line((122, 41), (108, 36), 1.0, MGRAY)
    cv.rect(104, 32, 112, 38, BLACK)
    cv.rect(105, 33, 111, 36, lv.accent)
    mirror(cv, 119, 33)

    # bash plate + front mudguard
    cv.shape([(78, 80), (104, 80), (100, 85), (82, 85)], CHROME, per=4)
    cv.arc(140, 66, 21, 24, 205, 330, lv.light)

    cv.outline_silhouette()
    return cv


LIVERIES = {
    "kawasaki": Livery(GREEN, DGREEN, (152, 214, 94), WHITE, frame=BLACK, word="KAWASAKI"),
    "ducati": Livery(RED, DRED, (232, 78, 74), WHITE, frame=BRONZE, word="DUCATI"),
    "harley": Livery((46, 46, 54), (26, 26, 32), (74, 74, 84), ORANGE, frame=BLACK, word="HARLEY"),
    "bmw": Livery((214, 220, 230), (140, 148, 162), WHITE, BLUE, frame=MGRAY, word="BMW"),
    "yamaha": Livery(BLUE, DBLUE, (86, 150, 232), WHITE, frame=BLACK, word="YAMAHA"),
    "honda": Livery(RED, DRED, (232, 78, 74), WHITE, frame=MGRAY, word="HONDA"),
    "suzuki": Livery(BLUE, DBLUE, (86, 150, 232), YELLOW, frame=BLACK, word="SUZUKI"),
    "triumph": Livery((198, 204, 214), (120, 126, 138), WHITE, (150, 60, 190), frame=BLACK, word="TRIUMPH"),
    "ktm": Livery(ORANGE, (150, 62, 14), AMBER, BLACK, frame=(22, 22, 26), word="KTM"),
}



# ---------------------------------------------------------------------------
# Reference-driven mode
#
# The finished art in ``bikes/`` is the style reference. These helpers copy a
# reference sprite into the same logical grid and palette discipline the
# parametric classes use, so generated art and hand-finished art share one
# idiom: one pixel = one logical pixel, flat colours, hard alpha edge.
# ---------------------------------------------------------------------------


def content_bbox(image: Image.Image, threshold: int = 8):
    alpha = np.asarray(image.convert("RGBA"))[..., 3]
    ys, xs = np.nonzero(alpha > threshold)
    if ys.size == 0:
        raise ValueError("empty reference")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def pixelate(image: Image.Image, width: int = 170, colors: int = 32,
             median: int = 1, alpha_cut: int = 110) -> Image.Image:
    """Copy a finished render down to a crisp logical pixel grid.

    Area-average down to ``width`` logical pixels, drop JPEG/AA noise with a
    median pass, then quantise to a flat palette and harden the alpha edge.
    The result is 1x: upscale with NEAREST (``Image.resize(..., NEAREST)``)
    when displaying or exporting.
    """
    image = image.convert("RGBA").crop(content_bbox(image))
    if median:
        image = image.filter(ImageFilter.MedianFilter(median))
    height = max(1, round(image.height * width / image.width))
    small = image.resize((width, height), Image.BOX)

    flat = (
        small.convert("RGB")
        .quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE)
        .convert("RGB")
    )
    out = flat.convert("RGBA")
    out.putalpha(small.getchannel("A").point(lambda v: 255 if v > alpha_cut else 0))
    return out


def palette_of(image: Image.Image) -> list[tuple[int, int, int]]:
    data = np.asarray(image.convert("RGBA"))
    visible = data[..., 3] > 0
    colours = data[..., :3][visible]
    if colours.size == 0:
        return []
    packed = (colours[:, 0].astype(np.int32) << 16) | (colours[:, 1].astype(np.int32) << 8) | colours[:, 2]
    values, counts = np.unique(packed, return_counts=True)
    order = counts.argsort()[::-1]
    return [
        ((int(v) >> 16) & 255, (int(v) >> 8) & 255, int(v) & 255)
        for v in values[order]
    ]


def dominant_hsv(image: Image.Image, sat_min: float = 0.30):
    """Hue and saturation of the largest chromatic area - the livery colour."""
    import colorsys

    data = np.asarray(image.convert("RGBA"))
    visible = data[..., 3] > 0
    colours = data[..., :3][visible]
    if colours.size == 0:
        return None
    packed = (colours[:, 0].astype(np.int32) << 16) | (colours[:, 1].astype(np.int32) << 8) | colours[:, 2]
    values, counts = np.unique(packed, return_counts=True)
    best, best_count = None, 0
    for value, count in zip(values, counts):
        r, g, b = ((int(value) >> 16) & 255) / 255, ((int(value) >> 8) & 255) / 255, (int(value) & 255) / 255
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if s >= sat_min and v > 0.15 and count > best_count:
            best, best_count = (h, s), int(count)
    return best


def dominant_hue(image: Image.Image, sat_min: float = 0.30):
    found = dominant_hsv(image, sat_min)
    return found[0] if found else None


def recolor(image: Image.Image, to_rgb: tuple[int, int, int],
            from_hue: float | None = None, tolerance: float = 0.16,
            sat_min: float = 0.22) -> Image.Image:
    """Swap the livery colour, leaving tyres, chrome and glass neutral.

    Palette entries within ``tolerance`` of the source livery hue are rotated
    to the destination hue, and their saturation is rescaled so a silver bike
    stays silver rather than turning into a pale colour. Value is untouched, so
    the flat shading survives the swap.
    """
    import colorsys

    source = dominant_hsv(image, sat_min)
    if source is None:
        return image.copy()
    src_h, src_s = source
    if from_hue is not None:
        src_h = from_hue
    t_h, t_s, _ = colorsys.rgb_to_hsv(*(c / 255 for c in to_rgb))
    sat_scale = (t_s / src_s) if src_s > 1e-3 else 1.0

    data = np.asarray(image.convert("RGBA")).copy()
    visible = data[..., 3] > 0
    rgb = data[..., :3][visible]
    packed = (rgb[:, 0].astype(np.int32) << 16) | (rgb[:, 1].astype(np.int32) << 8) | rgb[:, 2]
    remap = {}
    for value in np.unique(packed):
        r, g, b = ((int(value) >> 16) & 255) / 255, ((int(value) >> 8) & 255) / 255, (int(value) & 255) / 255
        h, sat, v = colorsys.rgb_to_hsv(r, g, b)
        delta = abs((h - src_h + 0.5) % 1.0 - 0.5)
        if sat >= sat_min and delta <= tolerance:
            new_h = (h + (t_h - src_h)) % 1.0
            new_s = min(1.0, max(0.0, sat * sat_scale))
            nr, ng, nb = colorsys.hsv_to_rgb(new_h, new_s, v)
            remap[int(value)] = (round(nr * 255), round(ng * 255), round(nb * 255))

    if not remap:
        return image.copy()
    flat = data[..., :3].reshape(-1, 3)
    packed_flat = (flat[:, 0].astype(np.int64) << 16) | (flat[:, 1].astype(np.int64) << 8) | flat[:, 2]
    for key, colour in remap.items():
        flat[packed_flat == key] = colour
    data[..., :3] = flat.reshape(data[..., :3].shape)
    return Image.fromarray(data, "RGBA")


CLASSES = {
    "sport": sport_bike,
    "naked": naked_bike,
    "cruiser": cruiser_bike,
    "adventure": adventure_bike,
}


def render(kind: str, livery: Livery, scale: int = 7) -> Image.Image:
    return CLASSES[kind](livery).to_image(scale=scale)
