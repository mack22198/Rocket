# Smooth car meshes (Blender)

The cars are designed in code (`src/shared/Cars/CarModelBuilder.luau`) out of boxes, wedges, cylinders and
spheres. These tools turn each car's *shell* - its paint and its windows - into smooth meshes with Blender,
so the cars look molded instead of blocky, while keeping every design exactly where it is.

How it works:

1. `export_parts.luau` (Lune) runs the game's real car builder and writes every car's parts, at evolution
   stages 1 and 2, to `parts.json`.
2. `build_meshes.py` (Python with Blender's `bpy` module) picks the shell parts of each car (paint and glass,
   plus any other chunky coloured parts; never wheels, lights, signs or thin trims), and for each colour:
   - turns every part into a signed-distance shape (a box or wedge with rounded edges, a cylinder, a ball or an
     ellipsoid; the little blocks of each wheel arch become one smooth curved band),
   - melts them together with rounded joins, and extracts the surface with marching cubes,
   - cleans the mesh up in Blender, slims it down (at most 4,500 triangles for a body, 1,800 for the rest) and
     shades it smooth.

   Fused cars share their base car's meshes when they're the same shape.
3. It writes:
   - `assets/meshes/TurboBallCars.fbx` - every mesh, named `<car>_<colour>` (e.g. `pizza_body`). This is the
     file to import in Roblox Studio (see the main README).
   - `tools/preview/meshes/cars.glb` - the same meshes for the offline previews.
   - `src/shared/Cars/CarMeshes.luau` - which parts each car's meshes replace, and each mesh's colour role, size
     and position on the car.

In the game, `CarModelBuilder` uses a car's meshes only when all of them have been imported (see
`CarModelBuilder.setMeshLibrary`); it copies each one, sizes and places it from `CarMeshes`, and paints it by
role like any other part - so evolution stages, team colours and fused cars all still work.

## Running it

```sh
python3 -m venv .venv && .venv/bin/pip install bpy==4.2.0 "numpy<2" scikit-image
lune run tools/meshes/export_parts
.venv/bin/python tools/meshes/build_meshes.py
```

`bpy` needs Python 3.11. A run takes under a minute. Re-run both steps whenever a car's design changes, then
re-import the `.fbx` in Studio.

The FBX is exported so its coordinates are the game's own (Y up, cars facing -Z) with no rotation on any object,
so a mesh can be dropped straight onto a car; `build_meshes.py` checks Blender's axis conversion on every run.
The game sets each mesh's size itself, so it doesn't matter what units Studio imports the file in.
