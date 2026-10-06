--!strict
-- The ball's look: a white ball with the twelve dark patches of a classic soccer ball. With the Blender meshes
-- imported (see MeshLibrary) the patches are crisp pentagons with stitching between all the panels; without
-- them, each patch is a bigger sphere sunk into the ball so only a thin round cap pokes out.

local CarMeshes = require(script.Parent.Parent.Cars.CarMeshes)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MeshLibrary = require(script.Parent.Parent.Build.MeshLibrary)

local BallModelBuilder = {}

local PATCH_COLOR = Color3.fromRGB(34, 40, 64)
local SEAM_COLOR = Color3.fromRGB(150, 156, 176)
local PATCH_RADIUS = 4 -- radius of each sunken sphere (bigger = flatter patch)
local PATCH_HEIGHT = 0.12 -- how far each patch sticks out of the ball

-- The corners of an icosahedron: twelve evenly spread directions.
local function patchDirections(): { Vector3 }
	local phi = (1 + math.sqrt(5)) / 2
	local list = {}
	for _, a in { -1, 1 } do
		for _, b in { -phi, phi } do
			table.insert(list, Vector3.new(0, a, b).Unit)
			table.insert(list, Vector3.new(a, b, 0).Unit)
			table.insert(list, Vector3.new(b, 0, a).Unit)
		end
	end
	return list
end

local function sphere(name: string, diameter: number, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * diameter
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Builds the ball model at the origin (normal size unless `size` is given). Its PrimaryPart is the main white
-- sphere, named "Ball".
function BallModelBuilder.build(size: number?): Model
	local radius = size or GameConfig.Ball.Radius
	local model = Instance.new("Model")
	model.Name = "Ball"
	local ball = sphere("Ball", radius * 2, CFrame.new(), Color3.fromRGB(248, 248, 252))
	ball.Parent = model
	model.PrimaryPart = ball
	-- The Blender patches and stitching, if they've been imported (they're made for a ball one stud across).
	local diameter = radius * 2
	local patches, seams = CarMeshes.Shared.ball_patches, CarMeshes.Shared.ball_seams
	if MeshLibrary.get(patches.name) and MeshLibrary.get(seams.name) then
		local looks: { { info: CarMeshes.MeshInfo, color: Color3, name: string } } = {
			{ info = patches, color = PATCH_COLOR, name = "Patch" },
			{ info = seams, color = SEAM_COLOR, name = "Seam" },
		}
		for _, entry in looks do
			local info, color = entry.info, entry.color
			local part = MeshLibrary.copy(info.name) :: MeshPart
			part.Name = entry.name
			part.Size = info.size * diameter
			part.CFrame = CFrame.new(info.center * diameter)
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Parent = model
		end
		return model
	end
	-- The patches grow with the ball, so a giant ball still looks like a soccer ball.
	local scale = radius / GameConfig.Ball.Radius
	local patchRadius = PATCH_RADIUS * scale
	local offset = radius + PATCH_HEIGHT * scale - patchRadius
	for _, direction in patchDirections() do
		sphere("Patch", patchRadius * 2, CFrame.new(direction * offset), PATCH_COLOR).Parent = model
	end
	return model
end

return BallModelBuilder
