"""Minimal glTF / GLB loader.

Enough of the spec to pull triangle meshes and base colours out of a .glb:
JSON chunk, binary chunk, accessors, buffer views, node transforms and material
factors. Anything fancier (skinning, morph targets, textures, draco) is ignored
- the output is a flat-shaded pixel sprite, so per-vertex colour is plenty.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import numpy as np

COMPONENTS = {5120: np.int8, 5121: np.uint8, 5122: np.int16,
              5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path: Path) -> dict:
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a GLB file")
    offset = 12
    json_chunk, bin_chunk = None, None
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            json_chunk = json.loads(payload.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            bin_chunk = payload
        offset += 8 + chunk_len
    if json_chunk is None:
        raise ValueError("no JSON chunk")
    json_chunk["__bin__"] = bin_chunk
    return json_chunk


def _accessor(gltf: dict, index: int) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    count = acc["count"]
    width = WIDTHS[acc["type"]]
    dtype = COMPONENTS[acc["componentType"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or (np.dtype(dtype).itemsize * width)
    buf = gltf["__bin__"]
    out = np.zeros((count, width), dtype=np.float32 if dtype == np.float32 else np.int64)
    for i in range(count):
        chunk = buf[start + i * stride : start + i * stride + np.dtype(dtype).itemsize * width]
        out[i] = np.frombuffer(chunk, dtype=dtype, count=width)
    if width == 1:
        out = out.reshape(-1)
    return out


def _matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.asarray(node["matrix"], float).reshape(4, 4).T
    t = np.asarray(node.get("translation", [0, 0, 0]), float)
    r = np.asarray(node.get("rotation", [0, 0, 0, 1]), float)
    s = np.asarray(node.get("scale", [1, 1, 1]), float)
    x, y, z, w = r
    rot = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m = np.eye(4)
    m[:3, :3] = rot * s
    m[:3, 3] = t
    return m


def load_mesh(path: Path, up_axis: str = "y") -> tuple[np.ndarray, np.ndarray]:
    """Return (triangles[N,3,3], colours[N,3]) in model space."""
    gltf = load_glb(path)
    tris, cols = [], []

    texture_cache: dict[int, object] = {}

    def get_texture(index: int):
        """Decode a base-colour texture out of the binary chunk."""
        if index in texture_cache:
            return texture_cache[index]
        tex = gltf["textures"][index]
        image = gltf["images"][tex.get("source", 0)]
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        blob = gltf["__bin__"][start : start + view["byteLength"]]
        from io import BytesIO
        from PIL import Image
        decoded = Image.open(BytesIO(blob)).convert("RGB")
        texture_cache[index] = decoded
        return decoded

    def base_colour(material_index, uv=None):
        if material_index is None or "materials" not in gltf:
            return np.array([180, 180, 190], float)
        mat = gltf["materials"][material_index]
        pbr = mat.get("pbrMetallicRoughness", {})
        c = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        factor = np.array([c[0], c[1], c[2]], float) * 255
        if "baseColorTexture" in pbr and uv is not None:
            tex = get_texture(pbr["baseColorTexture"]["index"])
            u = float(np.clip(uv[0], 0, 0.999))
            v = float(np.clip(uv[1], 0, 0.999))
            px = tex.getpixel((int(u * (tex.width - 1)), int((1 - v) * (tex.height - 1))))
            return np.array(px, float) * (factor / 255)
        return factor

    def walk(node_index: int, parent: np.ndarray):
        node = gltf["nodes"][node_index]
        world = parent @ _matrix(node)
        if "mesh" in node:
            mesh = gltf["meshes"][node["mesh"]]
            for prim in mesh.get("primitives", []):
                if prim.get("mode", 4) != 4:
                    continue
                pos = _accessor(gltf, prim["attributes"]["POSITION"]).astype(float)
                hom = np.concatenate([pos, np.ones((pos.shape[0], 1))], axis=1)
                pos = (hom @ world.T)[:, :3]
                uv = None
                if "TEXCOORD_0" in prim.get("attributes", {}):
                    uv = _accessor(gltf, prim["attributes"]["TEXCOORD_0"]).astype(float)
                if "indices" in prim:
                    idx = _accessor(gltf, prim["indices"]).astype(int)
                else:
                    idx = np.arange(pos.shape[0])
                for i in range(0, len(idx) - 2, 3):
                    tri = pos[idx[i : i + 3]]
                    if np.linalg.norm(np.cross(tri[1] - tri[0], tri[2] - tri[0])) < 1e-9:
                        continue
                    tris.append(tri)
                    centre_uv = None
                    if uv is not None:
                        centre_uv = uv[[idx[i], idx[i + 1], idx[i + 2]]].mean(axis=0)
                    cols.append(base_colour(prim.get("material"), centre_uv))
        for child in node.get("children", []):
            walk(child, world)

    scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)]
    for node_index in scene.get("nodes", []):
        walk(node_index, np.eye(4))

    triangles = np.asarray(tris, float) if tris else np.zeros((0, 3, 3))
    colours = np.asarray(cols, float) if cols else np.zeros((0, 3))
    if up_axis == "y":  # glTF is Y-up; our renderer is too
        pass
    return triangles, colours


def bounds(triangles: np.ndarray):
    flat = triangles.reshape(-1, 3)
    return flat.min(axis=0), flat.max(axis=0)
