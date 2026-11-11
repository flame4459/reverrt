"""High-resolution vector bike art for the classes the render set doesn't cover.

The finished renders in ``bikes/`` are ~1200 px studio renders; there is no
cruiser, adventure or scooter among them. This module draws those classes as
smooth vector art at 1600x1000 and hands the result to
``pixel_art_bikes.pixelate`` so the exported sprite lands on the same logical
grid and palette discipline as the rest of the set.

Shapes are built from Catmull-Rom outlines: closed splines for bodywork, thick
open splines for tubes and pipes, plus a small amount of flat three-tone
shading (base / shadow / highlight) so the pixelated result keeps readable
volume.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image

from pixel_art_bikes import spline

W, H = 1600, 1000
GROUND = 900

INK = (12, 12, 16)
TIRE = (32, 32, 38)
BLACK = (26, 26, 32)
DGRAY = (60, 60, 68)
MGRAY = (108, 108, 118)
LGRAY = (168, 168, 178)
CHROME = (200, 204, 214)
WHITE = (240, 240, 244)


def _erode(mask):
    e = mask.copy()
    e[1:, :] &= mask[:-1, :]
    e[:-1, :] &= mask[1:, :]
    e[:, 1:] &= mask[:, :-1]
    e[:, :-1] &= mask[:, 1:]
    return e


def _distance(mask, depth):
    """Cheap city-block interior distance: how many erosions a pixel survives."""
    out = np.zeros(mask.shape, np.float32)
    cur = mask
    for level in range(1, depth + 1):
        cur = _erode(cur)
        if not cur.any():
            break
        out[cur] = level
    out[mask & (out == 0)] = 0.5
    return out


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def lighten(c, t=0.20):
    return mix(c, (255, 255, 255), t)


def darken(c, t=0.22):
    return mix(c, (0, 0, 0), t)


class Raster:
    """Plain scanline raster at full resolution, no supersampling."""

    def __init__(self, w=W, h=H):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.uint8)
        self.a = np.zeros((h, w), bool)

    def poly(self, pts, color):
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        y0 = max(0, int(math.floor(min(ys))))
        y1 = min(self.h - 1, int(math.floor(max(ys))))
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
                x1 = min(self.w - 1, int(math.floor(xs[i + 1] - 0.5)))
                if x1 >= x0:
                    self.rgb[y, x0 : x1 + 1] = color
                    self.a[y, x0 : x1 + 1] = True

    def shape(self, pts, color, per=12, closed=True):
        self.poly(spline(pts, per=per, closed=closed), color)

    def ellipse(self, cx, cy, rx, ry, color, steps=64):
        self.poly(
            [(cx + rx * math.cos(2 * math.pi * i / steps), cy + ry * math.sin(2 * math.pi * i / steps))
             for i in range(steps)],
            color,
        )

    def disc(self, cx, cy, r, color):
        self.ellipse(cx, cy, r, r, color)

    def ring(self, cx, cy, r_out, r_in, color, steps=64):
        pts = [(cx + r_out * math.cos(2 * math.pi * i / steps),
                cy + r_out * math.sin(2 * math.pi * i / steps)) for i in range(steps)]
        pts += [(cx + r_in * math.cos(2 * math.pi * i / steps),
                 cy + r_in * math.sin(2 * math.pi * i / steps)) for i in range(steps - 1, -1, -1)]
        self.poly(pts, color)

    def rect(self, x0, y0, x1, y1, color):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], color)

    def line_path(self, pts, width, color):
        left, right = [], []
        n = len(pts)
        for i in range(n):
            p = pts[i]
            q = pts[min(i + 1, n - 1)]
            r = pts[max(i - 1, 0)]
            dx, dy = q[0] - r[0], q[1] - r[1]
            d = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / d * width / 2, dx / d * width / 2
            left.append((p[0] + nx, p[1] + ny))
            right.append((p[0] - nx, p[1] - ny))
        self.poly(left + right[::-1], color)

    def line(self, p0, p1, width, color):
        self.line_path([p0, p1], width, color)

    def band(self, pts, width, color):
        self.line_path(spline(pts, per=10, closed=False), width, color)

    def arc(self, cx, cy, r_in, r_out, a0, a1, color, steps=48):
        outer, inner = [], []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            outer.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
            inner.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
        self.poly(outer + inner[::-1], color)

    # -- shaded parts ------------------------------------------------------

    def _mask(self, poly, pad=6):
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        x0 = max(0, int(min(xs)) - pad)
        x1 = min(self.w, int(max(xs)) + pad + 1)
        y0 = max(0, int(min(ys)) - pad)
        y1 = min(self.h, int(max(ys)) + pad + 1)
        h, w = y1 - y0, x1 - x0
        mask = np.zeros((h, w), bool)
        n = len(poly)
        for y in range(h):
            sy = y0 + y + 0.5
            xs_hit = []
            for i in range(n):
                ax, ay = poly[i]
                bx, by = poly[(i + 1) % n]
                if ay == by:
                    continue
                if (ay <= sy < by) or (by <= sy < ay):
                    t = (sy - ay) / (by - ay)
                    xs_hit.append(ax + t * (bx - ax))
            if not xs_hit:
                continue
            xs_hit.sort()
            for i in range(0, len(xs_hit) - 1, 2):
                a = max(0, int(math.ceil(xs_hit[i] - x0 - 0.5)))
                b = min(w - 1, int(math.floor(xs_hit[i + 1] - x0 - 0.5)))
                if b >= a:
                    mask[y, a : b + 1] = True
        return x0, y0, mask

    def shade_poly(self, poly, color, bevel=18, light=(-0.55, -0.83),
                   highlight=0.34, shadow=0.30, edge=0.58, edge_px=3, levels=3):
        """Fill a polygon with a bevelled three-tone shade and an inner keyline.

        Distance-to-edge drives the bevel, and a directional ramp over the
        bounding box gives every panel the same top-left light. The inner
        keyline separates overlapping parts the way the reference art does.
        """
        x0, y0, mask = self._mask(poly)
        if not mask.any():
            return
        h, w = mask.shape
        d = _distance(mask, int(bevel) + 2)
        t = np.clip(d / max(bevel, 1), 0, 1)

        yy, xx = np.mgrid[0:h, 0:w]
        nx = (xx / max(w - 1, 1) - 0.5) * 2
        ny = (yy / max(h - 1, 1) - 0.5) * 2
        proj = np.clip(-(nx * light[0] + ny * light[1]), -1, 1)
        f = np.clip((0.45 + 0.55 * (proj * 0.5 + 0.5)) * t, 0, 1)
        if levels and levels > 1:  # cel-shade: flat steps read better after pixelation
            f = np.round(f * (levels - 1)) / (levels - 1)

        base = np.array(color, float)
        dark = base * (1 - shadow)
        bright = base + (255 - base) * highlight
        shade = dark[None, None, :] + (bright - dark)[None, None, :] * f[..., None]

        inner = mask
        for _ in range(edge_px):
            inner = _erode(inner)
        border = mask & ~inner
        shade[border] = np.array(mix(color, (0, 0, 0), edge), float)

        region = self.rgb[y0 : y0 + h, x0 : x0 + w]
        region[mask] = shade[mask].astype(np.uint8)
        self.a[y0 : y0 + h, x0 : x0 + w] |= mask

    def part_ellipse(self, cx, cy, rx, ry, color, steps=64, **kw):
        poly = [(cx + rx * math.cos(2 * math.pi * i / steps),
                 cy + ry * math.sin(2 * math.pi * i / steps)) for i in range(steps)]
        self.shade_poly(poly, color, **kw)

    def part(self, pts, color, per=12, **kw):
        self.shade_poly(spline(pts, per=per, closed=True), color, **kw)

    def part_arc(self, cx, cy, r_in, r_out, a0, a1, color, steps=56, **kw):
        outer, inner = [], []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            outer.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
            inner.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
        self.shade_poly(outer + inner[::-1], color, **kw)

    def keyline(self, color=INK, width=3):
        a = self.a
        grown = a.copy()
        for _ in range(width):
            g = grown.copy()
            g[1:, :] |= grown[:-1, :]
            g[:-1, :] |= grown[1:, :]
            g[:, 1:] |= grown[:, :-1]
            g[:, :-1] |= grown[:, 1:]
            grown = g
        border = grown & ~a
        self.rgb[border] = color
        self.a = grown

    def to_image(self, pad=6):
        ys, xs = np.where(self.a)
        y0, y1 = max(0, ys.min() - pad), min(self.h - 1, ys.max() + pad)
        x0, x1 = max(0, xs.min() - pad), min(self.w - 1, xs.max() + pad)
        rgba = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), np.uint8)
        rgba[..., :3] = self.rgb[y0 : y1 + 1, x0 : x1 + 1]
        rgba[..., 3] = np.where(self.a[y0 : y1 + 1, x0 : x1 + 1], 255, 0)
        return Image.fromarray(rgba, "RGBA")


# ---------------------------------------------------------------------------
# Shared components
# ---------------------------------------------------------------------------


def real_wheel(r: Raster, name: str, side: str, cx, cy, radius):
    """Paste a wheel cropped from the finished renders (see Scripts/parts.py)."""
    from parts import paste_wheel, wheel as crop_wheel

    paste_wheel(r, crop_wheel(name, side), cx, cy, radius)


def wheel(r: Raster, cx, cy, radius, livery_rim=CHROME, spokes=6, wire=False, tyre_ratio=0.30):
    r.disc(cx, cy, radius, TIRE)
    rim_in = radius * (1 - tyre_ratio)
    r.ring(cx, cy, radius * (1 - tyre_ratio * 0.55), rim_in * 0.94, livery_rim)
    r.disc(cx, cy, rim_in * 0.94, BLACK)
    for k in range(spokes):
        a = 2 * math.pi * k / spokes - 0.3
        r.line((cx, cy), (cx + rim_in * 0.92 * math.cos(a), cy + rim_in * 0.92 * math.sin(a)),
               radius * 0.055 if not wire else radius * 0.022, livery_rim)
    r.disc(cx, cy, radius * 0.13, livery_rim)
    r.disc(cx, cy, radius * 0.055, DGRAY)


def shock(r: Raster, top, bottom, width=16, spring=(232, 170, 60)):
    r.line(top, bottom, width, CHROME)
    mid = ((top[0] + bottom[0]) / 2, (top[1] + bottom[1]) / 2)
    r.line(mid, bottom, width * 1.35, spring)


AMBER = (246, 168, 40)


def fins(r: Raster, x0, y0, x1, y1, color, step=14):
    y = y0
    while y < y1:
        r.line((x0, y), (x1, y), 5, color)
        y += step


# ---------------------------------------------------------------------------
# Cruiser
# ---------------------------------------------------------------------------


def cruiser(livery, variant="sportster") -> Raster:
    """Low, long V-twin cruiser, proportioned off a side-on Virago 535.

    Measured from the reference: wheelbase 2.5 wheel diameters, seat 1.1,
    tank top 1.5, bar height 1.64, overall framing ~1.8 wide.
    """
    primary, accent = livery["primary"], livery["accent"]
    dark = darken(primary, 0.25)
    r = Raster()

    rear = (400, 730)
    front = (1250, 710)
    rear_r = 170
    front_r = 190

    # --- rear suspension --------------------------------------------------
    r.line((790, 700), (400, 730), 22, DGRAY)
    r.line((700, 706), (676, 566), 18, CHROME)
    r.line((688, 646), (682, 590), 24, AMBER)

    # --- frame ------------------------------------------------------------
    r.band([(1170, 400), (1000, 442), (860, 470), (790, 478)], 22, BLACK)
    r.band([(1172, 432), (1100, 640), (1010, 706)], 20, BLACK)
    r.band([(790, 478), (700, 500), (630, 512)], 18, BLACK)
    r.band([(630, 512), (612, 650), (700, 700)], 16, BLACK)

    # --- engine: V-twin ---------------------------------------------------
    r.part([(796, 640), (1004, 632), (1020, 792), (812, 802)], DGRAY, bevel=26)
    r.part([(822, 636), (752, 500), (812, 484), (878, 622)], MGRAY, bevel=16)
    r.part([(936, 628), (1030, 508), (1090, 540), (996, 652)], MGRAY, bevel=16)
    fins(r, 772, 548, 866, 628, LGRAY, 14)
    fins(r, 956, 548, 1064, 628, LGRAY, 14)
    r.part_ellipse(906, 720, 44, 36, LGRAY, bevel=16)
    r.part_ellipse(906, 720, 24, 20, MGRAY, bevel=10)

    # --- tank sitting at 1.5 diameters -----------------------------------
    r.part([(722, 470), (762, 412), (854, 396), (932, 422), (958, 470), (940, 514),
            (800, 520), (730, 500)], primary, bevel=28, highlight=0.40)
    r.band([(748, 492), (846, 486), (944, 496)], 12, accent)

    # --- seat, side cover --------------------------------------------------
    r.part([(560, 500), (664, 492), (754, 502), (756, 536), (664, 542), (566, 528)],
           (36, 36, 42), bevel=14, highlight=0.18)
    r.part([(612, 540), (700, 534), (722, 626), (626, 632)], dark, bevel=20)

    # --- fenders -----------------------------------------------------------
    r.part_arc(rear[0], rear[1], rear_r + 8, rear_r + 40, 196, 350, primary, bevel=14)
    r.line((520, 690), (612, 556), 14, BLACK)
    r.line((400, 730), (366, 640), 12, BLACK)
    r.part_arc(front[0], front[1], front_r + 8, front_r + 34, 204, 336, primary, bevel=14)

    # --- front end ---------------------------------------------------------
    r.line((1158, 400), (1250, 710), 32, CHROME)
    r.line((1222, 610), (1246, 726), 28, DGRAY)
    r.line((1122, 418), (1230, 690), 22, CHROME)
    r.rect(1148, 386, 1192, 418, DGRAY)
    r.ring(front[0], front[1], 100, 84, MGRAY)
    r.part_ellipse(1150, 424, 46, 46, CHROME, bevel=20)
    r.part_ellipse(1150, 424, 36, 36, (250, 246, 228), bevel=16)
    r.part_ellipse(1150, 424, 15, 15, AMBER, bevel=8)

    r.band([(1166, 396), (1120, 340), (1024, 326)], 18, BLACK)
    r.line((1024, 326), (982, 332), 22, DGRAY)
    r.line((1112, 340), (1098, 288), 8, BLACK)
    r.part_ellipse(1094, 276, 30, 20, BLACK, bevel=14)

    # --- exhaust, pegs, plate ---------------------------------------------
    r.band([(1012, 686), (992, 786), (852, 830), (688, 834)], 36, CHROME)
    r.band([(688, 834), (620, 832), (566, 826)], 42, CHROME)
    r.part([(468, 806), (566, 806), (566, 848), (468, 848)], CHROME, bevel=18)
    r.rect(468, 814, 484, 842, DGRAY)
    r.line((742, 784), (724, 842), 12, DGRAY)
    r.line((724, 842), (772, 844), 14, DGRAY)
    r.rect(344, 690, 378, 738, BLACK)

    from parts import paste_wheel, wheel as crop_wheel
    paste_wheel(r, crop_wheel("bike-cb1000r", "rear"), *rear, rear_r)
    paste_wheel(r, crop_wheel("bike-cb1000r", "front"), *front, front_r)

    r.keyline()
    return r


def adventure(livery, variant="gs") -> Raster:
    """Tall adventure bike: beak, screen, spoked wheels, high exhaust."""
    primary, accent = livery["primary"], livery["accent"]
    light = lighten(primary, 0.24)
    dark = darken(primary, 0.26)
    r = Raster()

    rear = (372, 738)
    front = (1286, 700)
    rear_r = 178
    front_r = 204

    real_wheel(r, "bike-cb1000r", "rear", *rear, rear_r)
    real_wheel(r, "bike-cb1000r", "front", *front, front_r)

    # swingarm + shock
    r.line((756, 700), (372, 738), 20, DGRAY)
    r.line((700, 706), (668, 566), 18, CHROME)
    r.line((686, 640), (676, 586), 24, AMBER)

    # trellis frame
    r.band([(1206, 470), (1040, 512), (880, 544), (768, 560)], 20, dark)
    r.band([(1206, 500), (1100, 620), (1010, 700)], 18, dark)
    r.band([(768, 560), (700, 600), (660, 660)], 18, dark)

    # engine: parallel twin with a bash plate
    r.shape([(838, 618), (1006, 610), (1024, 760), (856, 768)], DGRAY)
    r.shape([(852, 618), (872, 552), (952, 548), (986, 612)], LGRAY)
    fins(r, 866, 566, 972, 606, MGRAY, 13)
    r.shape([(824, 758), (1040, 752), (1024, 800), (846, 806)], CHROME)

    # tank + seat
    r.part([(776, 470), (900, 448), (1006, 466), (1054, 512), (1024, 562), (812, 558)],
           primary, bevel=26, highlight=0.38)
    r.shape([(792, 476), (900, 458), (994, 476), (1022, 506), (940, 500), (806, 508)], light)
    r.band([(800, 532), (920, 518), (1012, 534)], 20, accent)
    r.part([(556, 512), (700, 500), (786, 508), (790, 556), (660, 560), (572, 548)], (36, 36, 42), bevel=14)

    # tail + pannier
    r.part([(470, 528), (566, 508), (600, 552), (492, 574)], primary, bevel=18)
    r.part([(392, 486), (484, 476), (492, 570), (400, 578)], light, bevel=16)   # pannier
    r.line((400, 500), (486, 492), 6, dark)

    # beak + mudguard + screen
    r.part([(1226, 506), (1392, 540), (1408, 574), (1240, 560)], light, bevel=18)
    r.part_arc(front[0], front[1], front_r + 8, front_r + 34, 206, 336, primary, bevel=14)
    r.shape([(1136, 334), (1226, 316), (1252, 424), (1160, 436)], (58, 96, 122))
    r.line((1140, 340), (1218, 324), 6, (120, 200, 220))

    # forks, bars, handguards
    r.line((1198, 470), (1286, 700), 30, CHROME)
    r.line((1260, 622), (1290, 744), 26, DGRAY)
    r.band([(1198, 468), (1140, 430), (1056, 418)], 18, BLACK)
    r.shape([(1034, 396), (1082, 390), (1086, 434), (1038, 440)], BLACK)
    r.shape([(1040, 400), (1078, 396), (1080, 428), (1042, 432)], accent)
    r.line((1132, 428), (1122, 372), 8, BLACK)
    r.ellipse(1118, 360, 30, 20, BLACK)

    # high exhaust
    r.band([(1006, 700), (1000, 580), (934, 528)], 32, CHROME)
    r.rect(462, 596, 560, 646, CHROME)

    r.keyline()
    return r


def scooter(livery, variant="tmax") -> Raster:
    """Step-through scooter: small wheels, leg shield, floorboard."""
    primary, accent = livery["primary"], livery["accent"]
    light = lighten(primary, 0.24)
    dark = darken(primary, 0.26)
    r = Raster()

    rear = (452, 790)
    front = (1252, 790)
    radius = 118

    real_wheel(r, "bike-cb300r", "rear", *rear, radius)
    real_wheel(r, "bike-cb300r", "front", *front, radius)

    # engine + swingarm
    r.shape([(596, 726), (760, 726), (768, 812), (612, 816)], DGRAY)
    r.shape([(470, 760), (640, 754), (648, 800), (486, 806)], DGRAY)
    r.line((452, 790), (600, 786), 22, DGRAY)

    # body: rear cowl + seat
    r.part([(356, 742), (420, 664), (560, 646), (720, 668), (742, 726), (620, 756), (420, 762)],
           primary, bevel=26, highlight=0.36)
    r.shape([(380, 726), (440, 676), (548, 660), (700, 678), (700, 700), (560, 686), (400, 720)],
            light)
    r.part([(470, 646), (610, 636), (700, 652), (704, 686), (556, 682), (476, 672)], (36, 36, 42), bevel=14)

    # leg shield + floorboard
    r.part([(1000, 546), (1090, 528), (1136, 690), (1120, 806), (1040, 806), (1046, 700)], primary, bevel=24, highlight=0.36)
    r.shape([(1010, 552), (1080, 536), (1112, 690), (1100, 780), (1064, 780), (1068, 696)], light)
    r.part([(700, 792), (1044, 786), (1052, 812), (700, 818)], dark, bevel=10)

    # front fork, bars, headlight
    r.line((1170, 616), (1252, 790), 26, CHROME)
    r.band([(1160, 610), (1096, 560), (1030, 548)], 18, BLACK)
    r.disc(1074, 596, 44, CHROME)
    r.disc(1074, 596, 34, (250, 246, 228))
    r.shape([(1046, 470), (1120, 456), (1136, 526), (1062, 536)], (58, 96, 122))

    # exhaust + rear light
    r.rect(360, 774, 470, 812, CHROME)
    r.shape([(716, 690), (760, 686), (762, 716), (718, 720)], (200, 40, 44))

    r.keyline()
    return r


def naked(livery, variant="street") -> Raster:
    """Upright naked bike: exposed engine, round headlight, flat bars.

    Also stands in for the Mini class, which shares the upright stance and the
    small cast wheels.
    """
    primary, accent = livery["primary"], livery["accent"]
    dark = darken(primary, 0.25)
    r = Raster()

    rear = (420, 730)
    front = (1240, 720)
    rear_r = 168
    front_r = 168

    # --- swingarm, shock --------------------------------------------------
    r.line((800, 700), (420, 730), 22, DGRAY)
    r.line((742, 706), (700, 560), 18, CHROME)
    r.line((724, 646), (712, 586), 24, AMBER)

    # --- frame: twin spar ------------------------------------------------
    r.band([(1186, 452), (1010, 486), (860, 500)], 26, dark)
    r.band([(1186, 486), (1090, 660), (990, 714)], 22, dark)
    r.band([(860, 500), (760, 520), (700, 540)], 20, dark)
    r.band([(700, 540), (690, 660), (760, 700)], 18, dark)

    # --- inline-four engine ----------------------------------------------
    r.part([(806, 616), (1000, 606), (1014, 752), (820, 762)], DGRAY, bevel=24)
    r.part([(826, 604), (846, 512), (960, 508), (992, 600)], MGRAY, bevel=18)
    fins(r, 844, 526, 966, 592, LGRAY, 12)
    r.part([(800, 754), (1016, 746), (1004, 792), (816, 798)], CHROME, bevel=14)

    # --- tank + seat -------------------------------------------------------
    r.part([(756, 452), (846, 424), (946, 440), (990, 486), (964, 528), (786, 524),
            (752, 496)], primary, bevel=26, highlight=0.38)
    r.band([(770, 490), (860, 480), (960, 492)], 12, accent)
    r.part([(596, 500), (700, 492), (764, 500), (766, 536), (676, 542), (602, 530)],
           (36, 36, 42), bevel=14, highlight=0.18)
    r.part([(654, 540), (742, 534), (760, 610), (676, 616)], dark, bevel=18)

    # --- tail + fender ------------------------------------------------------
    r.part([(520, 486), (600, 470), (640, 512), (556, 528)], primary, bevel=18)
    r.part_arc(rear[0], rear[1], rear_r + 8, rear_r + 36, 200, 348, primary, bevel=12)

    # --- front end ----------------------------------------------------------
    r.part_arc(front[0], front[1], front_r + 8, front_r + 32, 206, 334, primary, bevel=12)
    r.line((1156, 470), (1240, 720), 32, CHROME)
    r.line((1210, 640), (1236, 728), 28, DGRAY)
    r.line((1120, 490), (1218, 700), 22, CHROME)
    r.rect(1146, 452, 1190, 486, DGRAY)
    r.ring(front[0], front[1], 96, 82, MGRAY)
    r.part_ellipse(1176, 470, 44, 44, CHROME, bevel=18)
    r.part_ellipse(1176, 470, 34, 34, (250, 246, 228), bevel=14)
    r.part_ellipse(1176, 470, 14, 14, AMBER, bevel=8)
    r.part([(1132, 424), (1200, 412), (1214, 452), (1146, 464)], (52, 88, 112), bevel=14)

    # flat bars + mirrors
    r.line((1168, 462), (1080, 442), 18, BLACK)
    r.line((1080, 442), (1042, 448), 20, DGRAY)
    r.line((1104, 440), (1092, 392), 8, BLACK)
    r.part_ellipse(1088, 380, 28, 18, BLACK, bevel=12)

    # --- exhaust, pegs -------------------------------------------------------
    r.band([(1006, 700), (900, 760), (760, 786)], 30, CHROME)
    r.part([(672, 762), (760, 758), (762, 792), (674, 796)], CHROME, bevel=14)
    r.line((786, 740), (770, 790), 12, DGRAY)
    r.line((770, 790), (814, 792), 14, DGRAY)

    from parts import paste_wheel, wheel as crop_wheel
    paste_wheel(r, crop_wheel("bike-cb300r", "rear"), *rear, rear_r)
    paste_wheel(r, crop_wheel("bike-cb300r", "front"), *front, front_r)

    r.keyline()
    return r


def sport(livery, variant="supersport", wheelbase_mm: float | None = None) -> Raster:
    """Faired sportbike built as separate sub-assemblies.

    Proportions come from the measured references (wheelbase 2.5 diameters,
    seat 1.15, tank top 1.5, bars 1.64); the detail comes from splitting the
    bodywork into tank / fairing / belly / seat unit and drawing the seams,
    vents, discs and chain that read at sprite size.
    """
    primary, accent = livery["primary"], livery["accent"]
    dark = darken(primary, 0.28)
    light = lighten(primary, 0.18)
    r = Raster()

    rear = (400, 730)
    # Real wheelbase stretches the bike between the axles; wheels stay round
    # because they are pasted images rather than vector shapes.
    k = 1.0
    if wheelbase_mm:
        k = float(min(1.18, max(0.86, wheelbase_mm / 1400.0)))
    front = (400 + (1240 - 400) * k, 730)
    rr = fr = 168
    r.stretch = (400, k)

    # --- chassis ----------------------------------------------------------
    r.line((790, 706), (400, 730), 20, DGRAY)          # swingarm
    r.line((790, 690), (400, 726), 8, (70, 70, 78))    # chain run
    for k in range(9):                                  # chain links
        t = k / 8
        r.disc(400 + (790 - 400) * t, 726 + (690 - 726) * t, 4, (44, 44, 50))
    r.line((706, 706), (676, 566), 16, CHROME)          # shock
    r.line((694, 646), (686, 590), 22, AMBER)
    r.band([(1176, 432), (1000, 470), (860, 486)], 20, BLACK)
    r.band([(1178, 456), (1092, 662), (1000, 722)], 18, BLACK)

    # --- engine: cases, block, radiator --------------------------------
    r.part([(800, 620), (1000, 612), (1012, 762), (816, 772)], DGRAY, bevel=22)
    r.part([(818, 604), (996, 598), (1004, 640), (824, 646)], MGRAY, bevel=12)
    for k in range(5):                                  # cooling fins
        r.line((822, 606 + k * 8), (998, 600 + k * 8), 3, (52, 52, 60))
    r.part([(1040, 596), (1140, 606), (1136, 690), (1044, 686)], (36, 38, 44), bevel=14)
    for k in range(7):                                  # radiator core
        r.line((1048, 606 + k * 12), (1132, 612 + k * 12), 4, (70, 74, 82))

    # --- tank, separated from the fairing by a seam --------------------
    r.part([(770, 496), (812, 450), (898, 440), (962, 470), (978, 512), (930, 546), (800, 542)],
           primary, bevel=24, highlight=0.34)
    r.part([(792, 470), (860, 452), (930, 466), (952, 492), (880, 486), (800, 496)],
           light, bevel=10)
    r.band([(786, 512), (880, 502), (966, 516)], 10, accent)
    r.band([(770, 540), (870, 532), (968, 542)], 4, INK)   # tank/seat seam

    # --- seat unit + tail ------------------------------------------------
    r.part([(600, 512), (700, 500), (768, 512), (770, 546), (686, 550), (606, 538)],
           (34, 34, 40), bevel=12, highlight=0.16)
    r.band([(620, 516), (700, 508), (760, 518)], 3, (60, 60, 68))
    r.part([(452, 496), (560, 472), (628, 494), (640, 528), (540, 536), (466, 526)],
           primary, bevel=16)
    r.part([(470, 504), (556, 486), (620, 502), (612, 520), (520, 522), (478, 518)],
           light, bevel=8)
    r.part([(440, 484), (492, 474), (500, 506), (448, 512)], dark, bevel=10)  # tail light

    # --- fairing: nose shell + lower + belly ------------------------------
    r.part([(958, 520), (1080, 496), (1186, 512), (1242, 574), (1214, 640),
            (1092, 700), (982, 688), (944, 620)], primary, bevel=24, highlight=0.30)
    r.part([(986, 640), (1100, 690), (1206, 646), (1192, 700), (1040, 722), (992, 686)],
           dark, bevel=16)
    r.part([(1058, 556), (1158, 572), (1170, 618), (1068, 602)], BLACK, bevel=8)   # vent
    r.band([(962, 544), (1090, 526), (1200, 550)], 14, accent)
    r.band([(958, 596), (1084, 620), (1200, 622)], 3, INK)                        # seam

    # --- screen, headlight, mirrors ----------------------------------------
    r.shape([(1162, 468), (1232, 428), (1272, 500), (1202, 510)], (52, 88, 112), per=8)
    r.line_path([(1164, 468), (1230, 432), (1268, 500)], 5, (120, 200, 220))
    r.part([(1222, 520), (1268, 518), (1266, 568), (1220, 558)], (250, 246, 228), bevel=10)
    r.line((1188, 456), (1108, 430), 14, BLACK)
    r.line((1108, 432), (1094, 384), 7, BLACK)
    r.part_ellipse(1088, 372, 26, 17, BLACK, bevel=10)

    # --- front end ---------------------------------------------------------
    r.part_arc(front[0], front[1], fr + 8, fr + 30, 208, 332, primary, bevel=10)
    r.line((1188, 460), (1240, 730), 28, CHROME)
    r.line((1224, 600), (1244, 726), 24, DGRAY)
    r.line((1152, 470), (1230, 720), 18, CHROME)
    r.rect(1152, 448, 1196, 480, DGRAY)                 # triple clamp
    r.ring(front[0], front[1], 96, 82, MGRAY)           # disc
    r.ring(rear[0], rear[1], 92, 80, MGRAY)

    # --- exhaust, pegs ------------------------------------------------------
    r.band([(1012, 686), (940, 758), (820, 784)], 28, CHROME)
    r.part([(700, 760), (818, 756), (820, 790), (702, 794)], CHROME, bevel=12)
    r.rect(704, 764, 716, 786, DGRAY)
    r.line((820, 744), (800, 800), 10, DGRAY)
    r.line((800, 800), (836, 802), 12, DGRAY)

    from parts import paste_wheel, wheel as crop_wheel
    paste_wheel(r, crop_wheel("bike-cb1000r", "rear"), *rear, rr)
    paste_wheel(r, crop_wheel("bike-cb1000r", "front"), *front, fr)

    r.keyline()
    return r


CLASSES = {"cruiser": cruiser, "adventure": adventure, "scooter": scooter,
           "naked": naked, "sport": sport}

LIVERIES = {
    "harley": {"primary": (98, 98, 110), "accent": (232, 116, 32)},
    "indian": {"primary": (150, 32, 36), "accent": (226, 220, 208)},
    "honda": {"primary": (40, 40, 48), "accent": (200, 40, 44)},
    "yamaha": {"primary": (38, 46, 92), "accent": (200, 200, 210)},
    "kawasaki": {"primary": (36, 36, 44), "accent": (104, 190, 58)},
    "suzuki": {"primary": (40, 44, 56), "accent": (200, 120, 40)},
    "triumph": {"primary": (66, 66, 74), "accent": (176, 182, 196)},
    "bmw": {"primary": (40, 44, 54), "accent": (40, 100, 190)},
    "ducati": {"primary": (200, 30, 42), "accent": (230, 230, 235)},
    "royal-enfield": {"primary": (44, 92, 64), "accent": (222, 190, 120)},
}
