--!strict
-- The world outside the stadium: grass all round, hills on the horizon, trees and clouds, so there's no empty
-- void past the stands. Terrain is filled in when the server starts.

local Palette = require(script.Parent.Palette)
local PartKit = require(script.Parent.PartKit)
local StadiumBuilder = require(script.Parent.StadiumBuilder)

local EnvironmentBuilder = {}

-- One terrain fill, as plain data (so the offline previewer can draw it too).
export type TerrainPiece = {
	kind: "block" | "ball",
	position: Vector3,
	size: Vector3,
	material: "Grass" | "LeafyGrass",
}

local MATERIALS = {
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
}

-- A tiny repeatable random number generator, so the scenery is the same every time.
local seed = 1
local function random(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end

function EnvironmentBuilder.terrainPlan(): { TerrainPiece }
	local plan: { TerrainPiece } = {}
	-- Flat grass, its surface just under the stadium's paving.
	local tile = 1024
	for i = -1, 1 do
		for j = -1, 1 do
			table.insert(plan, {
				kind = "block",
				position = Vector3.new(i * tile, -9, j * tile),
				size = Vector3.new(tile, 16, tile),
				material = "Grass",
			})
		end
	end
	-- Rolling hills on the horizon.
	seed = 777
	for k = 0, 9 do
		local angle = k / 10 * math.pi * 2 + (random() - 0.5) * 0.4
		local distance = 820 + random() * 280
		local radius = 110 + random() * 60
		table.insert(plan, {
			kind = "ball",
			position = Vector3.new(math.cos(angle) * distance, -radius * 0.45, math.sin(angle) * distance),
			size = Vector3.one * radius * 2,
			material = if k % 3 == 0 then "LeafyGrass" else "Grass",
		})
	end
	return plan
end

function EnvironmentBuilder.applyTerrain(terrain: Terrain, plan: { TerrainPiece })
	for _, piece in plan do
		local material = MATERIALS[piece.material]
		if piece.kind == "block" then
			terrain:FillBlock(CFrame.new(piece.position), piece.size, material)
		else
			terrain:FillBall(piece.position, piece.size.X / 2, material)
		end
	end
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(98, 166, 70))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(80, 146, 60))
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain
end

-- A round cartoon tree.
local function tree(folder: Instance, base: Vector3, scale: number)
	PartKit.part(folder, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10 * scale, 1.8 * scale, 1.8 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Palette.Trunk,
		Collide = false,
		Query = false,
	})
	local shade = Palette.Foliage[math.floor(random() * #Palette.Foliage) + 1]
	for i, offset in { Vector3.new(0, 13, 0), Vector3.new(2.4, 10.5, 1.2), Vector3.new(-2, 11, -1.6) } do
		PartKit.part(folder, {
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (10 - i * 1.5) * scale,
			CFrame = CFrame.new(base + offset * scale),
			Color = shade:Lerp(Color3.new(0, 0, 0), (i - 1) * 0.06),
			Material = Enum.Material.Grass,
			Collide = false,
			Query = false,
		})
	end
end

function EnvironmentBuilder.build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Environment"

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		EnvironmentBuilder.applyTerrain(terrain, EnvironmentBuilder.terrainPlan())
	end

	-- Trees scattered around the stadium (but not on it).
	seed = 4242
	local bounds = StadiumBuilder.Bounds + Vector2.new(40, 40)
	local planted = 0
	while planted < 70 do
		local angle = random() * math.pi * 2
		local distance = 320 + random() * 480
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if math.abs(x) > bounds.X or math.abs(z) > bounds.Y then
			tree(folder, Vector3.new(x, -1, z), 0.9 + random() * 0.8)
			planted += 1
		end
	end

	folder.Parent = workspace
	return folder
end

return EnvironmentBuilder
