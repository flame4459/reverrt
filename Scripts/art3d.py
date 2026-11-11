"""A small 3D renderer for motorcycle art.

Flat vector art could not reach the quality of the finished renders because it
has no volume: no shading, no silhouette from other angles, no turntable. This
module builds low-poly meshes from primitives, projects them orthographically
with auto-framing, shades each face with a key/fill light rig, supersamples and
hands the result to the pixel pipeline.

The output is pixelated down to ~340 px, so detail below that resolution is
thrown away anyway - which is what makes a low-poly model viable here.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------


class Mesh:
    def __init__(self):
        self.vertices: list[list[float]] = []
        self.faces: list[tuple[list[int], tuple[int, int, int]]] = []

    def add(self, vertices, faces, colour) -> "Mesh":
        base = len(self.vertices)
        self.vertices.extend(np.asarray(vertices, float).tolist())
        for face in faces:
            self.faces.append(([base + i for i in face], tuple(colour)))
        return self

    def merged(self, other: "Mesh") -> "Mesh":
        base = len(self.vertices)
        self.vertices.extend(other.vertices)
        for indices, colour in other.faces:
            self.faces.append(([base + i for i in indices], colour))
        return self

    def scaled(self, sx: float, sy: float | None = None, sz: float | None = None) -> "Mesh":
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        self.vertices = [[v[0] * sx, v[1] * sy, v[2] * sz] for v in self.vertices]
        return self

    def moved(self, dx=0.0, dy=0.0, dz=0.0) -> "Mesh":
        self.vertices = [[v[0] + dx, v[1] + dy, v[2] + dz] for v in self.vertices]
        return self

    def rotated(self, axis: str, degrees: float) -> "Mesh":
        rot = rotation(axis, degrees)
        self.vertices = (np.asarray(self.vertices) @ rot.T).tolist()
        return self


def rotation(axis: str, degrees: float) -> np.ndarray:
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], float)
    if axis == "y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], float)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], float)


def frame_from(direction: np.ndarray) -> np.ndarray:
    """Orthonormal basis whose +z maps onto `direction`."""
    d = direction / (np.linalg.norm(direction) or 1.0)
    up = np.array([0.0, 1.0, 0.0])
    if abs(float(d @ up)) > 0.95:
        up = np.array([1.0, 0.0, 0.0])
    x = np.cross(up, d)
    x /= np.linalg.norm(x) or 1.0
    y = np.cross(d, x)
    return np.stack([x, y, d], axis=1)


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------


def box(size, centre, colour, rot=None) -> Mesh:
    sx, sy, sz = (s / 2 for s in size)
    pts = np.array([
        [-sx, -sy, -sz], [sx, -sy, -sz], [sx, sy, -sz], [-sx, sy, -sz],
        [-sx, -sy, sz], [sx, -sy, sz], [sx, sy, sz], [-sx, sy, sz],
    ], float)
    if rot is not None:
        pts = pts @ np.asarray(rot).T
    pts += np.asarray(centre, float)
    faces = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4),
             (2, 3, 7, 6), (0, 3, 7, 4), (1, 2, 6, 5)]
    return Mesh().add(pts, faces, colour)


def cylinder(radius, length, centre, colour, axis="z", segments=20, taper=1.0) -> Mesh:
    pts, faces = [], []
    half = length / 2
    for side, r in ((-half, radius), (half, radius * taper)):
        for i in range(segments):
            a = 2 * math.pi * i / segments
            pts.append([r * math.cos(a), r * math.sin(a), side])
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((i, j, segments + j, segments + i))
    faces.append(tuple(range(segments))[::-1])
    faces.append(tuple(range(segments, 2 * segments)))
    pts = np.asarray(pts, float) + np.asarray(centre, float)
    return Mesh().add(pts, faces, colour)


def tube(p0, p1, radius, colour, segments=12, taper=1.0) -> Mesh:
    """Cylinder between two points - frame rails, forks, exhaust pipes."""
    a, b = np.asarray(p0, float), np.asarray(p1, float)
    length = float(np.linalg.norm(b - a))
    if length < 1e-6:
        return Mesh()
    m = cylinder(radius, length, (0, 0, 0), colour, segments=segments, taper=taper)
    basis = frame_from(b - a)
    verts = np.asarray(m.vertices) @ basis.T + (a + b) / 2
    out = Mesh()
    return out.add(verts, [f[0] for f in m.faces], colour)


def torus(major, minor, centre, colour, major_segments=26, minor_segments=10, start=0.0, end=360.0):
    """Tyre: a ring of circular cross-section."""
    pts, faces = [], []
    arc = (end - start) / 360.0
    for i in range(major_segments + 1):
        a = math.radians(start + (end - start) * i / major_segments)
        cx, cy = major * math.cos(a), major * math.sin(a)
        for j in range(minor_segments):
            b = 2 * math.pi * j / minor_segments
            r = minor * math.cos(b)
            pts.append([(major + r) * math.cos(a), (major + r) * math.sin(a), minor * math.sin(b)])
    for i in range(major_segments):
        for j in range(minor_segments):
            j2 = (j + 1) % minor_segments
            a0 = i * minor_segments + j
            a1 = i * minor_segments + j2
            b0 = (i + 1) * minor_segments + j
            b1 = (i + 1) * minor_segments + j2
            faces.append((a0, a1, b1, b0))
    pts = np.asarray(pts, float) + np.asarray(centre, float)
    return Mesh().add(pts, faces, colour)


def ellipsoid(radius, centre, colour, sx=1.0, sy=1.0, sz=1.0, rings=10, segments=18) -> Mesh:
    pts, faces = [], []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            pts.append([
                radius * sx * math.sin(phi) * math.cos(theta),
                radius * sy * math.cos(phi),
                radius * sz * math.sin(phi) * math.sin(theta),
            ])
    for r in range(rings):
        for s in range(segments):
            a = r * segments + s
            b = r * segments + (s + 1) % segments
            c = (r + 1) * segments + (s + 1) % segments
            d = (r + 1) * segments + s
            faces.append((a, b, c, d))
    pts = np.asarray(pts, float) + np.asarray(centre, float)
    return Mesh().add(pts, faces, colour)


def wedge(front, back, height, depth, centre, colour, tilt=0.0) -> Mesh:
    """Tapered slab: fairing noses, seats, tail units."""
    pts = [
        [-back, -height / 2, -depth / 2], [front, -height * 0.2, -depth * 0.35],
        [front, height * 0.3, -depth * 0.35], [-back, height / 2, -depth / 2],
        [-back, -height / 2, depth / 2], [front, -height * 0.2, depth * 0.35],
        [front, height * 0.3, depth * 0.35], [-back, height / 2, depth / 2],
    ]
    pts = np.asarray(pts, float)
    if tilt:
        pts = pts @ rotation("z", tilt).T
    pts += np.asarray(centre, float)
    faces = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4),
             (2, 3, 7, 6), (0, 3, 7, 4), (1, 2, 6, 5)]
    return Mesh().add(pts, faces, colour)


def loft(sections, colour, segments=18, cap=True, sides=0.0) -> Mesh:
    """Bodywork from cross-sections along x - the shape a box cannot make.

    Each section is ``(x, cy, cz, ry, rz)``: an ellipse standing at that station.
    Consecutive sections are bridged with quads, so a tank that swells and then
    tapers into a nose is one continuous surface rather than scattered blocks.
    ``sides`` squares the section off (0 round, 1 boxy).
    """
    pts, faces = [], []
    for x, cy, cz, ry, rz in sections:
        for i in range(segments):
            a = 2 * math.pi * i / segments
            cy_, sz_ = math.cos(a), math.sin(a)
            if sides:
                cy_ = math.copysign(abs(cy_) ** (1 - sides), cy_)
                sz_ = math.copysign(abs(sz_) ** (1 - sides), sz_)
            pts.append([x, cy + ry * cy_, cz + rz * sz_])
    rings = len(sections)
    for r in range(rings - 1):
        for i in range(segments):
            j = (i + 1) % segments
            a = r * segments + i
            b = r * segments + j
            c = (r + 1) * segments + j
            d = (r + 1) * segments + i
            faces.append((a, b, c, d))
    if cap:
        faces.append(tuple(range(segments))[::-1])
        faces.append(tuple(range((rings - 1) * segments, rings * segments)))
    return Mesh().add(pts, faces, colour)


def sweep(path, radii, colour, segments=12):
    """Tube along an arbitrary path with per-point radius - exhausts, frames."""
    pts, faces = [], []
    path = [np.asarray(p, float) for p in path]
    for i, (p, r) in enumerate(zip(path, radii)):
        tangent = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)])
        basis = frame_from(tangent)
        for k in range(segments):
            a = 2 * math.pi * k / segments
            pts.append(p + basis @ np.array([r * math.cos(a), r * math.sin(a), 0.0]))
    for i in range(len(path) - 1):
        for k in range(segments):
            j = (k + 1) % segments
            faces.append((i * segments + k, i * segments + j,
                          (i + 1) * segments + j, (i + 1) * segments + k))
    return Mesh().add(pts, faces, colour)


# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------


def render(mesh: Mesh, yaw: float = 0.0, pitch: float = 0.0, size=(1200, 800),
           light=(-0.45, 0.55, -0.70), fill=(0.7, 0.1, 0.4),
           supersample: int = 3, margin: float = 0.04, shadow: bool = True) -> Image.Image:
    w, h = size[0] * supersample, size[1] * supersample
    pts = np.asarray(mesh.vertices, float)
    pts = pts @ (rotation("y", yaw) @ rotation("x", pitch)).T

    # Orthographic projection, then fit the silhouette into the frame.
    xy = np.stack([pts[:, 0], -pts[:, 1]], axis=1)
    span = xy.max(axis=0) - xy.min(axis=0)
    target = np.array([w * (1 - 2 * margin), h * (1 - 2 * margin)])
    scale = float(np.min(target / np.maximum(span, 1e-6)))
    projected = (xy - (xy.max(axis=0) + xy.min(axis=0)) / 2) * scale + np.array([w / 2, h / 2])
    depth = pts[:, 2]

    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if shadow:
        # Contact shadow keeps the bike planted instead of floating.
        ground = float(projected[:, 1].max())
        left = float(projected[:, 0].min())
        right = float(projected[:, 0].max())
        spread = (right - left) * 0.42
        cx = (left + right) / 2
        for layer in range(6, 0, -1):
            alpha = int(16 + 7 * layer)
            pad = spread * (0.60 + 0.10 * layer)
            draw.ellipse(
                [cx - pad, ground - spread * 0.09, cx + pad, ground + spread * 0.09],
                fill=(6, 8, 12, alpha),
            )

    # Auto-exposure: dark meshes get lifted so every model reads at the same
    # brightness against the dark canvas.
    mean_lum = float(np.mean([0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
                              for _, c in mesh.faces])) / 255.0
    exposure = float(np.clip(0.42 / max(mean_lum, 0.08), 1.0, 2.4))

    key = np.asarray(light, float)
    key /= np.linalg.norm(key)
    fill = np.asarray(fill, float)
    fill /= np.linalg.norm(fill)
    rim_dir = np.array([0.55, 0.75, -0.6])
    rim_dir /= np.linalg.norm(rim_dir)

    order = sorted(
        ((float(np.mean(depth[list(idx)])), idx, colour) for idx, colour in mesh.faces),
        key=lambda item: item[0],
    )

    for _, indices, colour in order:
        poly = [tuple(projected[i]) for i in indices]
        v0 = pts[indices[1]] - pts[indices[0]]
        v1 = pts[indices[2]] - pts[indices[0]]
        normal = np.cross(v0, v1)
        norm = float(np.linalg.norm(normal))
        if norm < 1e-9:
            continue
        normal /= norm
        if normal[2] < 0:
            normal = -normal
        lam = max(0.0, float(normal @ key))
        rim = max(0.0, float(normal @ fill))
        # Fake ambient occlusion: undersides and back faces sit in shadow.
        down = max(0.0, -float(normal[1]))
        edge = max(0.0, float(normal @ rim_dir)) ** 2
        shade = (0.38 + 0.62 * lam + 0.14 * rim - 0.22 * down + 0.22 * edge) * exposure
        brightness = (colour[0] * 0.299 + colour[1] * 0.587 + colour[2] * 0.114) / 255
        if brightness > 0.45:  # painted and chrome surfaces catch a highlight
            half = key + np.array([0.0, 0.0, 1.0])
            half /= np.linalg.norm(half)
            shade += 0.30 * max(0.0, float(normal @ half)) ** 18
        rgb = tuple(int(min(255, c * shade)) for c in colour)
        draw.polygon(poly, fill=rgb + (255,))

    if supersample > 1:
        image = image.resize(size, Image.LANCZOS)
    return image

def vertex_normals(mesh: Mesh) -> np.ndarray:
    """Area-weighted smooth normals, so bodywork shades as a surface."""
    verts = np.asarray(mesh.vertices, float)
    normals = np.zeros_like(verts)
    for indices, _colour in mesh.faces:
        if len(indices) < 3:
            continue
        a, b, c = verts[indices[0]], verts[indices[1]], verts[indices[2]]
        n = np.cross(b - a, c - a)
        for i in indices:
            normals[i] += n
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    return normals / np.maximum(length, 1e-9)


def render_smooth(mesh: Mesh, yaw: float = 0.0, pitch: float = 0.0, size=(1200, 800),
                  light=(-0.45, 0.55, -0.70), fill=(0.7, 0.1, 0.4),
                  supersample: int = 3, margin: float = 0.04, shadow: bool = True,
                  studio: bool = True) -> Image.Image:
    """Z-buffered renderer with a studio material model.

    Per-pixel normals, a key/fill/rim rig, a sky-ground environment term,
    Blinn-Phong specular weighted by how metallic the base colour looks,
    fresnel rim, screen-space ambient occlusion from the depth buffer, and a
    filmic tone map. This is what separates a flat fill from something that
    reads as a rendered product shot.
    """
    w, h = size[0] * supersample, size[1] * supersample
    verts = np.asarray(mesh.vertices, float)
    normals = vertex_normals(mesh)
    rot = rotation("y", yaw) @ rotation("x", pitch)
    verts = verts @ rot.T
    normals = normals @ rot.T

    xy = np.stack([verts[:, 0], -verts[:, 1]], axis=1)
    span = xy.max(axis=0) - xy.min(axis=0)
    target = np.array([w * (1 - 2 * margin), h * (1 - 2 * margin)])
    scale = float(np.min(target / np.maximum(span, 1e-6)))
    proj = (xy - (xy.max(axis=0) + xy.min(axis=0)) / 2) * scale + np.array([w / 2, h / 2])

    colour = np.zeros((h, w, 3), np.float32)
    depth = np.full((h, w), 1e9, np.float32)
    alpha = np.zeros((h, w), bool)

    colours = np.array([c for _, c in mesh.faces], float)
    mean_lum = float(np.mean([0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] for c in colours])) / 255.0
    exposure = float(np.clip(0.42 / max(mean_lum, 0.08), 1.0, 2.2))

    key = np.asarray(light, float); key /= np.linalg.norm(key)
    fillv = np.asarray(fill, float); fillv /= np.linalg.norm(fillv)
    rimdir = np.array([0.55, 0.75, -0.60]); rimdir /= np.linalg.norm(rimdir)
    view = np.array([0.0, 0.0, 1.0])

    for indices, face_colour in mesh.faces:
        if len(indices) < 3:
            continue
        pts = proj[list(indices[:3])]
        x0 = max(int(np.floor(pts[:, 0].min())), 0); x1 = min(int(np.ceil(pts[:, 0].max())), w - 1)
        y0 = max(int(np.floor(pts[:, 1].min())), 0); y1 = min(int(np.ceil(pts[:, 1].max())), h - 1)
        if x1 <= x0 or y1 <= y0:
            continue
        tri = pts
        d = (tri[1, 1] - tri[2, 1]) * (tri[0, 0] - tri[2, 0]) + (tri[2, 0] - tri[1, 0]) * (tri[0, 1] - tri[2, 1])
        if abs(d) < 1e-9:
            continue
        ys, xs = np.mgrid[y0 : y1 + 1, x0 : x1 + 1]
        w0 = ((tri[1, 1] - tri[2, 1]) * (xs - tri[2, 0]) + (tri[2, 0] - tri[1, 0]) * (ys - tri[2, 1])) / d
        w1 = ((tri[2, 1] - tri[0, 1]) * (xs - tri[2, 0]) + (tri[0, 0] - tri[2, 0]) * (ys - tri[2, 1])) / d
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * verts[indices[0], 2] + w1 * verts[indices[1], 2] + w2 * verts[indices[2], 2]
        n = (w0[..., None] * normals[indices[0]] + w1[..., None] * normals[indices[1]]
             + w2[..., None] * normals[indices[2]])
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)

        sub = (slice(y0, y1 + 1), slice(x0, x1 + 1))
        nearer = inside & (z < depth[sub])
        if not nearer.any():
            continue

        nn = n[nearer]
        base = np.asarray(face_colour, float) / 255.0
        lum = float(0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2])
        metallic = np.clip((lum - 0.42) / 0.45, 0.0, 1.0)   # bright paint = glossy
        rough = 1.0 - metallic

        ndl = np.clip(nn @ key, 0, 1)
        ndf = np.clip(nn @ fillv, 0, 1)
        env = 0.5 - 0.5 * nn[..., 1]                          # sky above, ground below
        diffuse = 0.52 * ndl + 0.22 * ndf + 0.26 * env

        half = key + view; half /= np.linalg.norm(half)
        spec_pow = 18 + 70 * metallic
        spec = np.clip(nn @ half, 0, 1) ** spec_pow * (0.35 + 1.4 * metallic)

        fres = (1.0 - np.clip(nn @ view, 0, 1)) ** 4 * (0.25 + 0.5 * metallic)
        rim = np.clip(nn @ rimdir, 0, 1) ** 2 * 0.22

        lit = base[None, :] * (diffuse[..., None] * exposure) + spec[..., None] * (0.9, 0.92, 1.0) \
            + fres[..., None] * (0.55, 0.62, 0.75) + rim[..., None] * (0.5, 0.58, 0.7)
        lit = lit / (1.0 + lit)                                # Reinhard tone map
        lit = np.power(np.clip(lit, 0, 1), 1 / 1.05)

        # Head-on the extruded face is the reference image itself; blending the
        # raw colour back in keeps its baked detail instead of repainting it.
        flatness = max(0.0, 1.0 - abs(yaw) / 28.0)
        if flatness > 0.0:
            facing = np.clip(nn[..., 2], 0, 1)
            k = (flatness * facing)[..., None]
            lit = lit * (1 - k) + base[None, :] * k

        depth[sub][nearer] = z[nearer]
        colour[sub][nearer] = lit * 255.0
        alpha[sub][nearer] = True

    if studio and alpha.any():
        # Screen-space ambient occlusion: pixels sitting behind their
        # neighbours get darkened, which is what gives contact shadows and
        # separation between overlapping parts.
        d = np.where(alpha, depth, depth[alpha].max())
        occ = np.zeros_like(d)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
            shifted = np.roll(np.roll(d, dy, axis=0), dx, axis=1)
            occ += (shifted < d - 1e-3).astype(np.float32)
        occ = np.clip(occ / 8.0, 0, 1)
        colour *= (1.0 - 0.35 * occ)[..., None]

    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(colour, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(alpha, 255, 0)
    image = Image.fromarray(out, "RGBA")

    if shadow:
        ys, xs = np.nonzero(alpha)
        if ys.size:
            ground = float(ys.max()); left = float(xs.min()); right = float(xs.max())
            cx = (left + right) / 2; spread = (right - left) * 0.42
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d2 = ImageDraw.Draw(layer)
            for i in range(6, 0, -1):
                pad = spread * (0.60 + 0.10 * i)
                d2.ellipse([cx - pad, ground - spread * 0.10, cx + pad, ground + spread * 0.10],
                           fill=(6, 8, 12, 16 + 7 * i))
            layer.alpha_composite(image)
            image = layer

    if supersample > 1:
        image = image.resize(size, Image.LANCZOS)
    return image


def render(mesh: Mesh, yaw: float = 0.0, pitch: float = 0.0, size=(1200, 800),
           light=(-0.45, 0.55, -0.70), fill=(0.7, 0.1, 0.4),
           supersample: int = 3, margin: float = 0.04, shadow: bool = True) -> Image.Image:
    w, h = size[0] * supersample, size[1] * supersample
    pts = np.asarray(mesh.vertices, float)
    pts = pts @ (rotation("y", yaw) @ rotation("x", pitch)).T

    # Orthographic projection, then fit the silhouette into the frame.
    xy = np.stack([pts[:, 0], -pts[:, 1]], axis=1)
    span = xy.max(axis=0) - xy.min(axis=0)
    target = np.array([w * (1 - 2 * margin), h * (1 - 2 * margin)])
    scale = float(np.min(target / np.maximum(span, 1e-6)))
    projected = (xy - (xy.max(axis=0) + xy.min(axis=0)) / 2) * scale + np.array([w / 2, h / 2])
    depth = pts[:, 2]

    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if shadow:
        # Contact shadow keeps the bike planted instead of floating.
        ground = float(projected[:, 1].max())
        left = float(projected[:, 0].min())
        right = float(projected[:, 0].max())
        spread = (right - left) * 0.42
        cx = (left + right) / 2
        for layer in range(6, 0, -1):
            alpha = int(16 + 7 * layer)
            pad = spread * (0.60 + 0.10 * layer)
            draw.ellipse(
                [cx - pad, ground - spread * 0.09, cx + pad, ground + spread * 0.09],
                fill=(6, 8, 12, alpha),
            )

    # Auto-exposure: dark meshes get lifted so every model reads at the same
    # brightness against the dark canvas.
    mean_lum = float(np.mean([0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
                              for _, c in mesh.faces])) / 255.0
    exposure = float(np.clip(0.42 / max(mean_lum, 0.08), 1.0, 2.4))

    key = np.asarray(light, float)
    key /= np.linalg.norm(key)
    fill = np.asarray(fill, float)
    fill /= np.linalg.norm(fill)
    rim_dir = np.array([0.55, 0.75, -0.6])
    rim_dir /= np.linalg.norm(rim_dir)

    order = sorted(
        ((float(np.mean(depth[list(idx)])), idx, colour) for idx, colour in mesh.faces),
        key=lambda item: item[0],
    )

    for _, indices, colour in order:
        poly = [tuple(projected[i]) for i in indices]
        v0 = pts[indices[1]] - pts[indices[0]]
        v1 = pts[indices[2]] - pts[indices[0]]
        normal = np.cross(v0, v1)
        norm = float(np.linalg.norm(normal))
        if norm < 1e-9:
            continue
        normal /= norm
        if normal[2] < 0:
            normal = -normal
        lam = max(0.0, float(normal @ key))
        rim = max(0.0, float(normal @ fill))
        # Fake ambient occlusion: undersides and back faces sit in shadow.
        down = max(0.0, -float(normal[1]))
        edge = max(0.0, float(normal @ rim_dir)) ** 2
        shade = (0.38 + 0.62 * lam + 0.14 * rim - 0.22 * down + 0.22 * edge) * exposure
        brightness = (colour[0] * 0.299 + colour[1] * 0.587 + colour[2] * 0.114) / 255
        if brightness > 0.45:  # painted and chrome surfaces catch a highlight
            half = key + np.array([0.0, 0.0, 1.0])
            half /= np.linalg.norm(half)
            shade += 0.30 * max(0.0, float(normal @ half)) ** 18
        rgb = tuple(int(min(255, c * shade)) for c in colour)
        draw.polygon(poly, fill=rgb + (255,))

    if supersample > 1:
        image = image.resize(size, Image.LANCZOS)
    return image

def vertex_normals(mesh: Mesh) -> np.ndarray:
    """Area-weighted smooth normals, so bodywork shades as a surface."""
    verts = np.asarray(mesh.vertices, float)
    normals = np.zeros_like(verts)
    for indices, _colour in mesh.faces:
        if len(indices) < 3:
            continue
        a, b, c = verts[indices[0]], verts[indices[1]], verts[indices[2]]
        n = np.cross(b - a, c - a)
        for i in indices:
            normals[i] += n
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    return normals / np.maximum(length, 1e-9)


def render_smooth(mesh: Mesh, yaw: float = 0.0, pitch: float = 0.0, size=(1200, 800),
                  light=(-0.45, 0.55, -0.70), fill=(0.7, 0.1, 0.4),
                  supersample: int = 3, margin: float = 0.04, shadow: bool = True) -> Image.Image:
    """Z-buffered renderer with per-pixel normal interpolation.

    Flat shading exposed every polygon; interpolating the vertex normals lets
    the bodywork read as continuous surfaces, which is where the perceived
    detail comes from at sprite resolution.
    """
    w, h = size[0] * supersample, size[1] * supersample
    verts = np.asarray(mesh.vertices, float)
    normals = vertex_normals(mesh)
    rot = rotation("y", yaw) @ rotation("x", pitch)
    verts = verts @ rot.T
    normals = normals @ rot.T
    xy = np.stack([verts[:, 0], -verts[:, 1]], axis=1)
    span = xy.max(axis=0) - xy.min(axis=0)
    target = np.array([w * (1 - 2 * margin), h * (1 - 2 * margin)])
    scale = float(np.min(target / np.maximum(span, 1e-6)))
    proj = (xy - (xy.max(axis=0) + xy.min(axis=0)) / 2) * scale + np.array([w / 2, h / 2])

    colour = np.zeros((h, w, 3), np.float32)
    depth = np.full((h, w), 1e9, np.float32)
    alpha = np.zeros((h, w), bool)

    colours = np.array([c for _, c in mesh.faces], float)
    mean_lum = float(np.mean([0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] for c in colours])) / 255.0
    exposure = float(np.clip(0.42 / max(mean_lum, 0.08), 1.0, 2.4))

    key = np.asarray(light, float); key /= np.linalg.norm(key)
    fillv = np.asarray(fill, float); fillv /= np.linalg.norm(fillv)

    for face_index, (indices, face_colour) in enumerate(mesh.faces):
        if len(indices) < 3:
            continue
        pts = proj[list(indices)]
        x0 = max(int(np.floor(pts[:, 0].min())), 0)
        x1 = min(int(np.ceil(pts[:, 0].max())), w - 1)
        y0 = max(int(np.floor(pts[:, 1].min())), 0)
        y1 = min(int(np.ceil(pts[:, 1].max())), h - 1)
        if x1 <= x0 or y1 <= y0:
            continue
        tri = pts[:3]
        d = (tri[1, 1] - tri[2, 1]) * (tri[0, 0] - tri[2, 0]) + (tri[2, 0] - tri[1, 0]) * (tri[0, 1] - tri[2, 1])
        if abs(d) < 1e-9:
            continue
        ys, xs = np.mgrid[y0 : y1 + 1, x0 : x1 + 1]
        w0 = ((tri[1, 1] - tri[2, 1]) * (xs - tri[2, 0]) + (tri[2, 0] - tri[1, 0]) * (ys - tri[2, 1])) / d
        w1 = ((tri[2, 1] - tri[0, 1]) * (xs - tri[2, 0]) + (tri[0, 0] - tri[2, 0]) * (ys - tri[2, 1])) / d
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * verts[indices[0], 2] + w1 * verts[indices[1], 2] + w2 * verts[indices[2], 2]
        n = (w0[..., None] * normals[indices[0]] + w1[..., None] * normals[indices[1]]
             + w2[..., None] * normals[indices[2]])
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        lam = np.clip(n @ key, 0, 1)
        rim = np.clip(n @ fillv, 0, 1)
        down = np.clip(-n[..., 1], 0, 1)
        shade = (0.38 + 0.62 * lam + 0.14 * rim - 0.22 * down) * exposure
        # Head-on, the extruded face *is* the reference image, so lighting it
        # would only flatten detail that is already baked in. Fade the shading
        # out as the camera approaches the side view.
        flatness = max(0.0, 1.0 - abs(yaw) / 30.0)
        if flatness > 0.0:
            facing = np.clip(n[..., 2], 0, 1)
            shade = shade * (1 - flatness * facing) + flatness * facing
        bright = (0.299 * face_colour[0] + 0.587 * face_colour[1] + 0.114 * face_colour[2]) / 255
        if bright > 0.45:
            half = key + np.array([0.0, 0.0, 1.0]); half /= np.linalg.norm(half)
            shade = shade + 0.28 * np.clip(n @ half, 0, 1) ** 18
        sub = (slice(y0, y1 + 1), slice(x0, x1 + 1))
        nearer = inside & (z < depth[sub])
        if not nearer.any():
            continue
        depth[sub][nearer] = z[nearer]
        fc = np.asarray(face_colour, float)
        colour[sub][nearer] = fc[None, :] * shade[nearer][:, None]
        alpha[sub][nearer] = True

    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(colour, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(alpha, 255, 0)
    image = Image.fromarray(out, "RGBA")

    if shadow:
        ys, xs = np.nonzero(alpha)
        if ys.size:
            ground = float(ys.max()); left = float(xs.min()); right = float(xs.max())
            cx = (left + right) / 2; spread = (right - left) * 0.42
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            for i in range(6, 0, -1):
                pad = spread * (0.60 + 0.10 * i)
                d.ellipse([cx - pad, ground - spread * 0.10, cx + pad, ground + spread * 0.10],
                          fill=(6, 8, 12, 16 + 7 * i))
            layer.alpha_composite(image)
            image = layer

    if supersample > 1:
        image = image.resize(size, Image.LANCZOS)
    return image
