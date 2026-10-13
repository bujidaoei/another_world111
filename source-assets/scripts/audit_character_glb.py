"""Read binary GLB accessors and independently evaluate skeletal skin motion.

Python/NumPy asset QA, no engine or production mutation. Skin matrices follow
the Khronos glTF2 joint-global * inverse-bind definition. Engine review remains
separate from this container/geometry/weight/animation gate.
"""
from pathlib import Path
import copy
import hashlib
import json
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source-assets"
COMPONENTS = {5120: np.dtype("i1"), 5121: np.dtype("u1"), 5122: np.dtype("<i2"), 5123: np.dtype("<u2"), 5125: np.dtype("<u4"), 5126: np.dtype("<f4")}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Document:
    def __init__(self, path):
        self.bytes = path.read_bytes()
        magic, version, size = struct.unpack_from("<4sII", self.bytes)
        if magic != b"glTF" or version != 2 or size != len(self.bytes):
            raise ValueError("Invalid GLB header")
        length, kind = struct.unpack_from("<II", self.bytes, 12)
        if kind != 0x4e4f534a:
            raise ValueError("First GLB chunk is not JSON")
        self.doc = json.loads(self.bytes[20:20 + length])
        offset = 20 + length
        bin_length, bin_kind = struct.unpack_from("<II", self.bytes, offset)
        if bin_kind != 0x004e4942 or offset + 8 + bin_length != len(self.bytes):
            raise ValueError("Invalid embedded binary chunk")
        self.binary = self.bytes[offset + 8:]
        if any("uri" in item for key in ["buffers", "images"] for item in self.doc.get(key, [])):
            raise ValueError("Unexpected external dependency")
        self.parent = {}
        for parent, node in enumerate(self.doc["nodes"]):
            for child in node.get("children", []):
                if child in self.parent:
                    raise ValueError("Joint/node has multiple parents")
                self.parent[child] = parent

    def accessor(self, index):
        item = self.doc["accessors"][index]
        if "sparse" in item:
            raise ValueError("Unexpected sparse accessor")
        view = self.doc["bufferViews"][item["bufferView"]]
        dtype, width = COMPONENTS[item["componentType"]], WIDTHS[item["type"]]
        stride = view.get("byteStride", dtype.itemsize * width)
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        count = item["count"]
        if offset + (count - 1) * stride + width * dtype.itemsize > len(self.binary):
            raise ValueError("Accessor exceeds binary storage")
        array = np.ndarray((count, width), dtype=dtype, buffer=self.binary, offset=offset, strides=(stride, dtype.itemsize)).copy()
        if item.get("normalized", False):
            if dtype.kind == "u":
                array = array.astype(np.float64) / np.iinfo(dtype).max
            elif dtype.kind == "i":
                array = np.maximum(array.astype(np.float64) / np.iinfo(dtype).max, -1)
        if not np.isfinite(array).all():
            raise ValueError("Non-finite accessor")
        return array

    @staticmethod
    def matrix(node):
        if "matrix" in node:
            return np.array(node["matrix"], dtype=np.float64).reshape((4, 4), order="F")
        x, y, z, w = node.get("rotation", [0, 0, 0, 1])
        norm = np.linalg.norm([x, y, z, w])
        if norm < 1e-7:
            raise ValueError("Invalid zero rotation")
        x, y, z, w = np.array([x, y, z, w]) / norm
        matrix = np.eye(4)
        matrix[:3, :3] = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                           [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                           [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
        matrix[:3, :3] = matrix[:3, :3] @ np.diag(node.get("scale", [1, 1, 1]))
        matrix[:3, 3] = node.get("translation", [0, 0, 0])
        return matrix

    def transforms(self, nodes):
        result = {}
        active = set()
        def visit(index):
            if index in active:
                raise ValueError("Node cycle")
            if index not in result:
                active.add(index)
                local = self.matrix(nodes[index])
                result[index] = visit(self.parent[index]) @ local if index in self.parent else local
                active.remove(index)
            return result[index]
        return np.stack([visit(i) for i in range(len(nodes))])

    def animated_nodes(self, animation, time):
        nodes = copy.deepcopy(self.doc["nodes"])
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            interpolation = sampler.get("interpolation", "LINEAR")
            if interpolation not in ["LINEAR", "STEP"]:
                raise ValueError("Unexpected non-linear baked animation")
            times = self.accessor(sampler["input"]).flatten()
            values = self.accessor(sampler["output"])
            if len(values) != len(times) or np.any(np.diff(times) <= 0):
                raise ValueError("Malformed animation sampler")
            right = min(max(int(np.searchsorted(times, time, side="right")), 1), len(times) - 1)
            left = right - 1
            alpha = float(np.clip((time - times[left]) / (times[right] - times[left]), 0, 1))
            a, b = values[left].astype(np.float64), values[right].astype(np.float64)
            path = channel["target"]["path"]
            if interpolation == "STEP":
                value = a if time < times[right] else b
            elif path == "rotation":
                if np.dot(a, b) < 0:
                    b = -b
                cosine = float(np.clip(np.dot(a, b), -1, 1))
                if cosine < .9995:
                    angle = np.arccos(cosine)
                    value = (np.sin((1-alpha)*angle)*a + np.sin(alpha*angle)*b) / np.sin(angle)
                else:
                    value = a * (1-alpha) + b * alpha
                value /= np.linalg.norm(value)
            else:
                value = a * (1-alpha) + b * alpha
            nodes[channel["target"]["node"]][path] = value.tolist()
        return nodes


def audit(asset):
    path = ROOT / asset["runtime_file"]
    document = Document(path)
    doc = document.doc
    if hashlib.sha256(document.bytes).hexdigest() != asset["sha256"]:
        raise ValueError("Actual GLB hash differs from manifest")
    if len(doc.get("skins", [])) != 1 or len(doc.get("meshes", [])) != 1 or len(doc.get("materials", [])) != 1:
        raise ValueError("Character does not meet single skin/mesh/material contract")
    if len(doc["meshes"][0]["primitives"]) != 1:
        raise ValueError("Character has extra primitive submissions")
    primitive = doc["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    positions = document.accessor(attrs["POSITION"]).astype(np.float64)
    normals = document.accessor(attrs["NORMAL"]).astype(np.float64)
    uv = document.accessor(attrs["TEXCOORD_0"])
    joints = document.accessor(attrs["JOINTS_0"]).astype(np.int64)
    weights = document.accessor(attrs["WEIGHTS_0"]).astype(np.float64)
    skin = doc["skins"][0]
    if joints.min() < 0 or joints.max() >= len(skin["joints"]) or np.any(weights < 0) or np.max(np.abs(weights.sum(axis=1) - 1)) > 1e-5:
        raise ValueError("Invalid skin indices/normalized weights")
    if not np.allclose(np.linalg.norm(normals, axis=1), 1, atol=.001) or uv.min() < 0 or uv.max() > 1:
        raise ValueError("Invalid normals or UV bounds")
    inverse_bind = document.accessor(skin["inverseBindMatrices"]).astype(np.float64).reshape((-1, 4, 4)).transpose((0, 2, 1))
    if len(inverse_bind) != len(skin["joints"]) or any(abs(np.linalg.det(matrix)) < 1e-5 for matrix in inverse_bind):
        raise ValueError("Invalid bind matrices")
    index = document.accessor(primitive["indices"]).flatten()
    if len(index) % 3 or int(index.max()) >= len(positions) or len(index) // 3 != asset["geometry"]["triangles"]:
        raise ValueError("Runtime triangle/index count mismatch")
    homogeneous = np.column_stack([positions, np.ones(len(positions))])
    names = {doc["nodes"][node].get("name"): node for node in skin["joints"]}
    def evaluate(nodes):
        global_matrices = document.transforms(nodes)
        # World-space skinning cancels mesh-global and reapplies it, leaving
        # joint-global * inverse-bind as the matrix used for this world audit.
        skin_matrices = global_matrices[skin["joints"]] @ inverse_bind
        output = np.zeros_like(homogeneous)
        for component in range(4):
            output += np.einsum("nij,nj->ni", skin_matrices[joints[:, component]], homogeneous) * weights[:, component, None]
        return output[:, :3], global_matrices
    rest_vertices, rest_matrices = evaluate(doc["nodes"])
    rest_low, rest_high = rest_vertices.min(axis=0), rest_vertices.max(axis=0)
    if not np.allclose(rest_low, asset["bounds_godot_m"]["min"], atol=.002) or not np.allclose(rest_high, asset["bounds_godot_m"]["max"], atol=.002):
        raise ValueError("Actual skinned bind pose does not match source bounds")
    clip_reports = {}
    for animation in doc["animations"]:
        name = animation["name"]
        duration = max(float(document.accessor(s["input"])[-1, 0]) for s in animation["samplers"])
        source_clip = asset["animations_authored"][name]
        if abs(duration - source_clip["duration_s"]) > .001:
            raise ValueError("Actual animation duration differs from source")
        rows, endpoints = [], []
        for time in np.linspace(0, duration, source_clip["samples"]):
            vertices, transforms = evaluate(document.animated_nodes(animation, float(time)))
            row = {"time": float(time), "floor_y": float(vertices[:, 1].min())}
            for bone in ["Foot_L", "Foot_R", "Shin_L", "Shin_R", "Hand_L", "Hand_R"]:
                row[bone] = transforms[names[bone], :3, 3].tolist()
            rows.append(row)
            if time == 0 or time == duration:
                endpoints.append(vertices)
        spans = {bone: np.ptp([row[bone] for row in rows], axis=0).tolist() for bone in ["Foot_L", "Foot_R", "Shin_L", "Shin_R", "Hand_L", "Hand_R"]}
        floor_min = min(row["floor_y"] for row in rows)
        endpoint_error = float(np.linalg.norm(endpoints[0]-endpoints[-1], axis=1).max())
        issues = []
        if floor_min < -.002:
            issues.append("Binary skin motion crosses ground")
        if name == "Walk" and any(spans[bone][2] < .60 or spans[bone][1] < .12 for bone in ["Foot_L", "Foot_R"]):
            issues.append("Binary skin has no independent swing/plant")
        if source_clip["loop_intent"] and endpoint_error > .002:
            issues.append("Binary loop endpoints differ")
        if name == "SelfHeal" and spans["Hand_L"][1] < .30:
            issues.append("Binary repair wrist does not reach chest")
        clip_reports[name] = {"duration_s": duration, "channels": len(animation["channels"]), "samples_evaluated": len(rows), "bone_spans_metres": spans,
                              "min_skin_ground_y_m": floor_min, "max_endpoint_vertex_error_m": endpoint_error, "issues": issues, "ok": not issues}
    if set(clip_reports) != set(asset["clips_expected"]):
        raise ValueError("Actual animation clip set differs")
    return {"id": asset["id"], "sha256": asset["sha256"], "bytes": len(document.bytes), "skins": 1, "bones": len(skin["joints"]),
            "meshes": 1, "primitives": 1, "materials": 1, "textures": len(doc.get("textures", [])), "source_vertices": asset["geometry"]["vertices"],
            "runtime_split_vertices": len(positions), "triangles": len(index)//3, "max_weight_sum_error": float(np.max(np.abs(weights.sum(axis=1)-1))),
            "rest_bounds_m": {"min": rest_low.tolist(), "max": rest_high.tolist()}, "clips": clip_reports, "ok": all(c["ok"] for c in clip_reports.values())}


def main():
    manifest = json.loads((SOURCE / "character-manifest.json").read_text(encoding="utf-8"))
    reports = [audit(asset) for asset in manifest["assets"]]
    report = {"schema_version": 1, "algorithm_reference": "https://github.khronos.org/glTF-Tutorials/gltfTutorial/gltfTutorial_020_Skins.html",
              "scope": "binary accessor and independent CPU skin evaluation; Godot render acceptance separate", "numpy": np.__version__, "assets": reports, "ok": all(r["ok"] for r in reports)}
    (SOURCE / "evidence/character-glb-motion.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    if not report["ok"]:
        raise RuntimeError("Character binary motion gate failed")


if __name__ == "__main__":
    main()
