"""
Makes smooth car-body meshes in Blender from the game's own car designs.

Each car's shell - its paint and its windows - is rebuilt as one smooth solid per colour: every part becomes a
signed-distance shape (a box or wedge with rounded edges, a cylinder, a ball or an ellipsoid), parts of the same
colour melt together with small rounded joins, and marching cubes turns the result into a mesh. Blender then
tidies it up, slims it down and exports it. Everything else (wheels, lights, grilles, signs, hats...) stays as
the game's own parts on top, so a car looks the same, just smooth instead of blocky.

Usage, from the repository root, with Blender's Python module installed (`pip install bpy numpy scikit-image`):
    lune run tools/meshes/export_parts
    python tools/meshes/build_meshes.py

It writes:
    assets/meshes/TurboBallCars.fbx     import this once in Roblox Studio (see the README)
    tools/preview/meshes/cars.glb       the same meshes for the offline previews
    src/shared/Cars/CarMeshes.luau      which parts the meshes replace, and where each one goes
"""

import hashlib
import json
import math
import os
import shutil
import subprocess
import time

import numpy as np
from skimage import measure

import bpy
import bmesh
from bpy_extras.io_utils import axis_conversion
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PARTS_JSON = os.path.join(ROOT, "tools", "meshes", "parts.json")
FBX_OUT = os.path.join(ROOT, "assets", "meshes", "TurboBallCars.fbx")
GLB_OUT = os.path.join(ROOT, "tools", "preview", "meshes", "cars.glb")
MANIFEST_OUT = os.path.join(ROOT, "src", "shared", "Cars", "CarMeshes.luau")

VOXEL = 0.04  # studs: how finely the shapes are sampled
ROUND = {"body": 0.32, "body2": 0.26}  # how round the edges of boxes and wedges are (by role)...
ROUND_DEFAULT = 0.18  # ...and for every other role
BLEND = {"body": 0.3}  # how far parts of the same colour melt into each other (by role)...
BLEND_DEFAULT = 0.22  # ...and for every other role
TRIANGLES = {"body": 4500}  # the most triangles each mesh may keep (by role)...
TRIANGLES_DEFAULT = 1800  # ...and for every other role

# Parts that always stay the game's own: wheels (they spin on hubs), team lights, signs and the like.
WHEEL_PARTS = {"Wheel", "Sidewall", "Rim", "RimDish", "Spoke", "HubCap", "Tread"}
NEVER = {"TeamLight", "Antenna", "TeamFlag", "Badge", "WheelWell"}
DETAIL_ROLES = {"team", "lamp", "tail", "tire", "sidewall", "rim", "metal", "eye", "pupil", "shine", "hat", "cabin"}
PAINT_ROLES = {"body", "body2", "glass"}
THIN = 0.12  # thinner than this and it's a detail (stripes, trims)
CHUNKY = 0.5  # parts in other colours are only smoothed when they're at least this thick


def part_ok(part):
    if part["name"] in WHEEL_PARTS or part["name"] in NEVER or part.get("text"):
        return False
    if part["role"] in DETAIL_ROLES:
        return False
    thickness = min(part["size"])
    if thickness < THIN:
        return False
    return part["role"] in PAINT_ROLES or thickness >= CHUNKY


def same_parts(a, b):
    if len(a) != len(b):
        return False
    for p, q in zip(a, b):
        if p["shape"] != q["shape"] or p["role"] != q["role"]:
            return False
        if not np.allclose(p["size"], q["size"], atol=1e-4) or not np.allclose(p["cframe"], q["cframe"], atol=1e-4):
            return False
    return True


def by_name(parts):
    groups = {}
    for part in parts:
        groups.setdefault(part["name"], []).append(part)
    return groups


def select(car):
    """Which parts of a car get smoothed: {role: [parts]}, and the names of the parts they replace."""
    stage1 = by_name(car["stages"]["1"])
    stage2 = by_name(car["stages"]["2"])
    roles, replaced = {}, set()
    for name, parts in stage1.items():
        # All parts with this name must qualify, and look the same at stage 2 (the mesh is used at every stage).
        if not all(part_ok(p) for p in parts) or not same_parts(parts, stage2.get(name, [])):
            continue
        replaced.add(name)
        for part in parts:
            roles.setdefault(part["role"], []).append(part)
    # A lone ball, ellipsoid or cylinder is already smooth: leave it be.
    for role in list(roles):
        parts = roles[role]
        if len(parts) == 1 and parts[0]["shape"] in ("Ball", "Ellipsoid", "Cylinder"):
            replaced.discard(parts[0]["name"])
            del roles[role]
    # A name can only be replaced if every part with that name made it into a mesh.
    kept = {p["name"] for parts in roles.values() for p in parts}
    replaced &= kept
    return roles, replaced


# --- Signed distance shapes (car space: X right, Y up, the car faces -Z) --------------------------------------


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def rounded_box(q, h, r):
    d = np.abs(q) - (h - r)
    return np.linalg.norm(np.maximum(d, 0.0), axis=1) + np.minimum(np.max(d, axis=1), 0.0) - r


def rounded_rect(a, b, r):
    # A rectangle in (a, b) - two distances that are negative inside - with its corners rounded by r.
    d = np.stack([a + r, b + r], axis=1)
    return np.linalg.norm(np.maximum(d, 0.0), axis=1) + np.minimum(np.max(d, axis=1), 0.0) - r


def shape_distance(part, q, rounding):
    h = np.array(part["size"], dtype=np.float64) / 2
    shape = part["shape"]
    if shape == "Arch":
        # A wheel arch: a curved band around the top of the wheel (q is relative to the wheel's centre).
        ring = np.abs(np.linalg.norm(q[:, 1:], axis=1) - part["radius"]) - part["thickness"] / 2
        across = np.abs(q[:, 0] - part["mid"]) - part["half"]
        r = min(rounding, 0.45 * part["thickness"] / 2)
        band = rounded_rect(ring, across, r)
        return smax(band, part["cut"] - q[:, 1], r)
    if shape == "Block":
        return rounded_box(q, h, min(rounding, 0.45 * h.min()))
    if shape == "Wedge":
        # Roblox's wedge: full height at the back (+Z), sloping down to the bottom front edge.
        r = min(rounding, 0.45 * h.min())
        n = np.array([0.0, h[2], -h[1]])
        n /= np.linalg.norm(n)
        return smax(rounded_box(q, h, r), q @ n, r)
    if shape == "Cylinder":
        # Along X: length size.X, diameter the smaller of size.Y and size.Z.
        radius = min(h[1], h[2])
        r = min(rounding, 0.45 * min(radius, h[0]))
        d = np.stack([np.linalg.norm(q[:, 1:], axis=1) - (radius - r), np.abs(q[:, 0]) - (h[0] - r)], axis=1)
        return np.linalg.norm(np.maximum(d, 0.0), axis=1) + np.minimum(np.max(d, axis=1), 0.0) - r
    if shape == "Ball":
        return np.linalg.norm(q, axis=1) - h.min()
    if shape == "Ellipsoid":
        k0 = np.linalg.norm(q / h, axis=1)
        k1 = np.linalg.norm(q / (h * h), axis=1)
        return k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    raise ValueError(f"unknown shape {shape}")


def corners(part):
    """The 8 corners of a part's box, in car space."""
    if part["shape"] == "Arch":
        c, reach = np.array(part["cframe"][0:3]), part["radius"] + part["thickness"]
        lo = c + np.array([part["mid"] - part["half"], part["cut"], -reach])
        hi = c + np.array([part["mid"] + part["half"], reach, reach])
        return np.array([lo, hi])
    h = np.array(part["size"]) / 2
    cf = part["cframe"]
    t = np.array(cf[0:3])
    rot = np.array(cf[3:12]).reshape(3, 3)
    signs = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)])
    return t + (signs * h) @ rot.T


def to_local(points, part):
    cf = part["cframe"]
    t = np.array(cf[0:3])
    rot = np.array(cf[3:12]).reshape(3, 3)
    return (points - t) @ rot


def arches(parts, wheels):
    """Swaps the little blocks that make up each wheel arch for one smooth curved band per wheel."""
    others = [p for p in parts if p["name"] != "Arch"]
    blocks = [p for p in parts if p["name"] == "Arch"]
    if not blocks or not wheels:
        return parts
    groups = {}
    for block in blocks:
        centre = np.array(block["cframe"][0:3])
        nearest = min(range(len(wheels)), key=lambda i: np.linalg.norm(np.array(wheels[i]["cframe"][0:3]) - centre))
        groups.setdefault(nearest, []).append(block)
    for index, group in groups.items():
        wheel = np.array(wheels[index]["cframe"][0:3])
        offsets = np.array([np.array(b["cframe"][0:3]) - wheel for b in group])
        radius = float(np.mean(np.linalg.norm(offsets[:, 1:], axis=1)))
        thickness = float(np.mean([b["size"][1] for b in group]))
        xs = [(o[0] - b["size"][0] / 2, o[0] + b["size"][0] / 2) for o, b in zip(offsets, group)]
        x0, x1 = min(x[0] for x in xs), max(x[1] for x in xs)
        others.append({
            "name": "Arch",
            "role": group[0]["role"],
            "shape": "Arch",
            "cframe": [*wheel.tolist(), 1, 0, 0, 0, 1, 0, 0, 0, 1],
            "size": [x1 - x0, radius, radius],
            "radius": radius,
            "thickness": thickness,
            "mid": (x0 + x1) / 2,
            "half": (x1 - x0) / 2,
            "cut": radius * math.cos(math.radians(84)),
        })
    return others


def smooth_solid(role, parts):
    """Melts the parts into one smooth solid and returns its surface: (vertices, triangles) in car space."""
    rounding = ROUND.get(role, ROUND_DEFAULT)
    blend = BLEND.get(role, BLEND_DEFAULT)
    margin = blend + 3 * VOXEL
    all_corners = np.concatenate([corners(p) for p in parts])
    lo = all_corners.min(axis=0) - margin
    hi = all_corners.max(axis=0) + margin
    shape = np.ceil((hi - lo) / VOXEL).astype(int) + 1
    field = np.full(shape, 10.0, dtype=np.float32)
    axes = [lo[i] + np.arange(shape[i]) * VOXEL for i in range(3)]
    for part in parts:
        pc = corners(part)
        i0 = np.clip(np.floor((pc.min(axis=0) - margin - lo) / VOXEL).astype(int), 0, shape - 1)
        i1 = np.clip(np.ceil((pc.max(axis=0) + margin - lo) / VOXEL).astype(int) + 1, 1, shape)
        gx, gy, gz = np.meshgrid(axes[0][i0[0] : i1[0]], axes[1][i0[1] : i1[1]], axes[2][i0[2] : i1[2]], indexing="ij")
        points = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
        d = shape_distance(part, to_local(points, part), rounding).reshape(gx.shape).astype(np.float32)
        block = field[i0[0] : i1[0], i0[1] : i1[1], i0[2] : i1[2]]
        field[i0[0] : i1[0], i0[1] : i1[1], i0[2] : i1[2]] = smin(block, d, blend)
    vertices, triangles, _, _ = measure.marching_cubes(field, level=0.0, spacing=(VOXEL, VOXEL, VOXEL))
    return vertices + lo, triangles


# --- Blender -------------------------------------------------------------------------------------------------

# Car space (Roblox) to Blender: Blender's FBX and glTF exporters turn (x, y, z) into (x, z, -y), so putting
# (x, -z, y) into Blender comes out exactly as the game's coordinates again.
def to_blender(points):
    return np.column_stack([points[:, 0], -points[:, 2], points[:, 1]])


def from_blender(points):
    return np.column_stack([points[:, 0], points[:, 2], -points[:, 1]])


def check_axes():
    matrix = axis_conversion(to_forward="-Z", to_up="Y")
    probe = np.array([[1.0, 2.0, 3.0]])
    exported = np.array(matrix @ Vector(to_blender(probe)[0]))
    assert np.allclose(exported, probe[0]), f"axis conversion is not what we expect: {exported}"


def make_object(name, vertices, triangles, budget):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(to_blender(vertices).tolist(), [], triangles.tolist())
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    if len(mesh.polygons) > budget:
        decimate = obj.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = budget / len(mesh.polygons)
        decimate.use_collapse_triangulate = True
        depsgraph = bpy.context.evaluated_depsgraph_get()
        slim = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        obj.modifiers.clear()
        obj.data = slim
        bpy.data.meshes.remove(mesh)
        mesh = slim
        mesh.name = name
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def bounds(obj):
    points = np.array([v.co[:] for v in obj.data.vertices])
    car = from_blender(points)
    lo, hi = car.min(axis=0), car.max(axis=0)
    return (hi - lo), (hi + lo) / 2


def fingerprint(role, parts):
    data = json.dumps([[role, p["shape"], np.round(p["size"], 4).tolist(), np.round(p["cframe"], 4).tolist()] for p in parts])
    return hashlib.sha1(data.encode()).hexdigest()


def luau_vector(v):
    return f"Vector3.new({v[0]:.4f}, {v[1]:.4f}, {v[2]:.4f})"


def write_manifest(cars):
    lines = [
        "--!strict",
        "-- GENERATED by tools/meshes/build_meshes.py - don't edit by hand (run the tool again instead).",
        "--",
        "-- Smooth car-body meshes made in Blender (see tools/meshes). For each car: the part names the meshes replace,",
        "-- and each mesh's role (which colour it's painted), size and centre in car space. The meshes themselves are in",
        "-- assets/meshes/TurboBallCars.fbx and have to be imported once in Roblox Studio; until they are, every car is",
        "-- built from plain parts as before.",
        "",
        "export type MeshInfo = { name: string, role: string, size: Vector3, center: Vector3 }",
        "",
        "export type CarMeshSet = { replaces: { [string]: boolean }, meshes: { MeshInfo } }",
        "",
        "return {",
        "\tVersion = 1,",
        "\tCars = {",
    ]
    for car_id in sorted(cars):
        info = cars[car_id]
        lines.append(f"\t\t{car_id} = {{")
        names = ", ".join(f"{name} = true" for name in sorted(info["replaces"]))
        lines.append(f"\t\t\treplaces = {{ {names} }},")
        lines.append("\t\t\tmeshes = {")
        for mesh in info["meshes"]:
            lines.append(
                f'\t\t\t\t{{ name = "{mesh["name"]}", role = "{mesh["role"]}", '
                f'size = {luau_vector(mesh["size"])}, center = {luau_vector(mesh["center"])} }},'
            )
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines += ["\t} :: { [string]: CarMeshSet },", "}", ""]
    with open(MANIFEST_OUT, "w") as f:
        f.write("\n".join(lines))
    # Tidy it the way the rest of the code is (CI checks the formatting).
    stylua = shutil.which("stylua") or os.path.expanduser("~/.rokit/bin/stylua")
    if os.path.exists(stylua):
        subprocess.run([stylua, MANIFEST_OUT], check=True, cwd=ROOT)
    else:
        print("stylua not found: run `stylua src` before committing")


def main():
    check_axes()
    with open(PARTS_JSON) as f:
        cars = json.load(f)["cars"]
    bpy.ops.wm.read_factory_settings(use_empty=True)

    made = {}  # fingerprint -> mesh name, so fused cars share their base car's meshes
    manifest = {}
    order = sorted(cars, key=lambda c: (cars[c]["base"] != c, c))  # plain cars first
    for index, car_id in enumerate(order):
        started = time.time()
        roles, replaced = select(cars[car_id])
        wheels = [p for p in cars[car_id]["stages"]["1"] if p["name"] == "Wheel"]
        meshes = []
        for role in sorted(roles):
            parts = arches(roles[role], wheels)
            roles[role] = parts
            key = fingerprint(role, parts)
            if key not in made:
                name = f"{car_id}_{role}"
                vertices, triangles = smooth_solid(role, parts)
                obj = make_object(name, vertices, triangles, TRIANGLES.get(role, TRIANGLES_DEFAULT))
                size, center = bounds(obj)
                # Line the cars up side by side in the file, so they're easy to look at after importing.
                obj.location = (index * 12.0, 0.0, 0.0)
                made[key] = {"name": name, "size": size.tolist(), "center": center.tolist(), "tris": len(obj.data.polygons)}
            mesh = made[key]
            meshes.append({"name": mesh["name"], "role": role, "size": mesh["size"], "center": mesh["center"]})
        manifest[car_id] = {"replaces": replaced, "meshes": meshes}
        detail = ", ".join(f"{m['role']}={made[fingerprint(m['role'], roles[m['role']])]['tris']}" for m in meshes)
        print(f"{car_id}: {len(replaced)} part names -> {len(meshes)} meshes ({detail}) in {time.time() - started:.1f}s")

    os.makedirs(os.path.dirname(FBX_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=FBX_OUT,
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        mesh_smooth_type="OFF",
        add_leaf_bones=False,
        bake_anim=False,
    )
    # The previews want every mesh where it sits on its car.
    for obj in bpy.context.scene.objects:
        obj.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_materials="NONE",
    )
    write_manifest(manifest)
    total = sum(m["tris"] for m in made.values())
    print(f"wrote {len(made)} meshes ({total} triangles) to {FBX_OUT}, {GLB_OUT} and {MANIFEST_OUT}")


if __name__ == "__main__":
    main()
