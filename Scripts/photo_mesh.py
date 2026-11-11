"""Build a 3D mesh from a side-on reference image.

When no modelled mesh exists for a bike, the reference photo is still the most
accurate description of its shape. This takes a cut-out side profile, extrudes
the silhouette along Z with a depth profile (thin at the wheels, deep through
the fairing and engine) and bakes the image's own colours onto the front and
back faces.

Side-on the result is the reference itself - every decal, disc and shadow
survives. Off-axis it is a solid with volume that the renderer can light and
shade, which is what the turntable needs.
"""

from __future__ import annotations

import numpy as np
from PIL import Image

import art3d as A


def depth_profile(width: int, depth: float = 0.22) -> np.ndarray:
    """Half-thickness per column: wheels thin, body deep, nose and tail taper."""
    x = np.linspace(0.0, 1.0, width)
    bell = np.exp(-((x - 0.52) ** 2) / (2 * 0.22 ** 2))
    return depth * (0.22 + 0.78 * np.clip(bell, 0, 1))


def mesh_from_image(image: Image.Image, columns: int = 150,
                    depth: float = 0.22) -> A.Mesh:
    """Extrude an RGBA side profile into a coloured mesh."""
    image = image.convert("RGBA")
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > 40)
    if ys.size == 0:
        raise ValueError("empty reference")
    image = image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    height = max(2, round(image.height * columns / image.width))
    small = image.resize((columns, height), Image.BOX)
    rgba = np.asarray(small).astype(np.float32)
    mask = rgba[..., 3] > 90
    colours = rgba[..., :3]
    # Normalise exposure so a photo shot in shade still lands at sprite brightness.
    if mask.any():
        lum = colours[mask] @ np.array([0.299, 0.587, 0.114])
        gain = float(np.clip(0.58 / max(np.mean(lum) / 255.0, 0.05), 0.85, 2.1))
        colours = np.clip(colours * gain, 0, 255)

    half = depth_profile(columns, depth) * (columns / 150.0)
    verts_front, verts_back, colors = [], [], []
    index_front = {}
    index_back = {}

    for x in range(columns):
        for y in range(height):
            if not mask[y, x]:
                continue
            px = (x / (columns - 1) - 0.5) * 2.0
            py = (0.5 - y / (height - 1)) * 2.0 * (height / columns)
            z = half[x]
            index_front[(x, y)] = len(verts_front)
            verts_front.append([px, py, z])
            colors.append(colours[y, x])

    base = len(verts_front)
    for key, i in index_front.items():
        index_back[key] = base + i
        v = verts_front[i]
        verts_back.append([v[0], v[1], -v[2]])

    mesh = A.Mesh()
    mesh.vertices = verts_front + verts_back
    mesh.faces = []

    def quad(a, b, c, d, colour):
        # emit triangles: the z-buffer rasteriser only handles tri faces
        mesh.faces.append(([a, b, c], colour))
        mesh.faces.append(([a, c, d], colour))

    for x in range(columns - 1):
        for y in range(height - 1):
            corners = [(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]
            if not all(c in index_front for c in corners):
                continue
            mean = np.mean([colors[index_front[c]] for c in corners], axis=0)
            colour = tuple(int(v) for v in mean)
            # front face (image colour), back face (shaded by the renderer)
            quad(index_front[corners[0]], index_front[corners[1]],
                 index_front[corners[2]], index_front[corners[3]], colour)
            quad(index_back[corners[3]], index_back[corners[2]],
                 index_back[corners[1]], index_back[corners[0]],
                 tuple(int(c * 0.55) for c in colour))

    return mesh


def from_reference(path, columns: int = 150, depth: float = 0.22) -> A.Mesh:
    with Image.open(path) as image:
        return mesh_from_image(image, columns=columns, depth=depth)
