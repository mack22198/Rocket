-- Writes every car's parts (at evolution stages 1 and 2) to JSON for build_meshes.py, using the game's real
-- CarModelBuilder in Lune. Usage (from the repository root):
--   lune run tools/meshes/export_parts [out.json]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("../../tests/harness")

local outPath = process.args[1] or "tools/meshes/parts.json"

local Shared = harness.Shared
local CarCatalog = harness.require(Shared.Config.CarCatalog)
local CarModelBuilder = harness.require(Shared.Cars.CarModelBuilder)

local cars = {}
for _, def in CarCatalog.ordered() do
	local stages = {}
	for stage = 1, 2 do
		local parts = {}
		for _, spec in CarModelBuilder.specs(def, stage) do
			table.insert(parts, {
				name = spec.name,
				role = spec.role,
				shape = spec.shape,
				size = { spec.size.X, spec.size.Y, spec.size.Z },
				cframe = { spec.cframe:GetComponents() },
				text = spec.text,
			})
		end
		stages[tostring(stage)] = parts
	end
	cars[def.Id] = {
		-- (In design units, like the parts: the game scales the meshes up with everything else.)
		hitbox = (function()
			local box = CarCatalog.designHitbox(def)
			return { box.X, box.Y, box.Z }
		end)(),
		base = if def.Fusion then def.Fusion.Base else def.Id,
		stages = stages,
	}
end

fs.writeFile(outPath, serde.encode("json", { cars = cars }, true))
local count = 0
for _ in cars do
	count += 1
end
print(`wrote {count} cars to {outPath}`)
