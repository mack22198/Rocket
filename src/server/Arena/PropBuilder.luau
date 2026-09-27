--!strict
-- The things items and powers put on the pitch: the spinning "?" item boxes, gooey cheese puddles and banana
-- peels. Just the looks; ItemService and PowerService decide where they go and what they do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Powers = require(Shared.Config.Powers)

local PropBuilder = {}

local T = Powers.Tuning
local rgb = Color3.fromRGB

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A glassy rainbow cube with a glowing "?" on every side.
function PropBuilder.itemBox(folder: Instance, position: Vector3, index: number): Model
	local model = Instance.new("Model")
	model.Name = `ItemBox{index}`
	local centre = CFrame.new(position + Vector3.new(0, T.BoxHeight, 0))
	local shell = part(model, "Box", Vector3.one * 4.2, centre, rgb(80, 180, 255))
	shell.Material = Enum.Material.Glass
	shell.Transparency = 0.2
	shell.Reflectance = 0.2
	-- Bright edges, so the box stands out from across the pitch.
	local edges = Instance.new("SelectionBox")
	edges.Name = "Edges"
	edges.Adornee = shell
	edges.Color3 = rgb(255, 255, 255)
	edges.LineThickness = 0.08
	edges.SurfaceColor3 = rgb(140, 210, 255)
	edges.SurfaceTransparency = 0.8
	edges.Parent = shell
	local core = part(model, "Core", Vector3.one * 2.6, centre * CFrame.Angles(0, math.rad(45), 0), rgb(255, 214, 90))
	core.Material = Enum.Material.Neon
	core.Transparency = 0.1
	for _, face in Enum.NormalId:GetEnumItems() do
		if face == Enum.NormalId.Bottom then
			continue
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = `Mark{face.Name}`
		gui.Face = face
		gui.CanvasSize = Vector2.new(100, 100)
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.Parent = shell
		local mark = Instance.new("TextLabel")
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Text = "?"
		mark.Font = Enum.Font.FredokaOne
		mark.TextScaled = true
		mark.TextColor3 = rgb(255, 255, 255)
		mark.TextStrokeTransparency = 0
		mark.TextStrokeColor3 = rgb(40, 60, 140)
		mark.Parent = gui
	end
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 220, 140)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = core
	-- A glowing ring on the floor marks the spot while the box is growing back.
	local ring = part(
		model,
		"Spot",
		Vector3.new(0.12, 7, 7),
		CFrame.new(position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(150, 210, 255)
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	model.PrimaryPart = shell
	model:SetAttribute("Home", position + Vector3.new(0, T.BoxHeight, 0))
	model:SetAttribute("Active", true)
	model.Parent = folder
	return model
end

local piece = part

-- A flat disc lying on the surface (cylinders point along X, so tip it up).
local function disc(parent: Instance, name: string, surface: CFrame, radius: number, thickness: number, color: Color3)
	local part = piece(
		parent,
		name,
		Vector3.new(thickness, radius * 2, radius * 2),
		surface * CFrame.new(0, thickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A gooey puddle of melted cheese with bubbles in it, ringed in the dropping team's colour.
local function buildCheese(model: Model, surface: CFrame, teamColor: Color3)
	local ring = disc(model, "TeamRing", surface, T.CheeseRadius + 0.7, 0.12, teamColor)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	disc(model, "Cheese", surface, T.CheeseRadius, 0.3, rgb(255, 190, 40))
	disc(model, "Melt", surface * CFrame.new(1.2, 0, -0.8), T.CheeseRadius * 0.62, 0.42, rgb(255, 222, 110))
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2 + 0.4
		local distance = T.CheeseRadius * (0.3 + 0.12 * (i % 3))
		local size = 1 + (i % 3) * 0.45
		local bubble = piece(
			model,
			"Bubble",
			Vector3.one * size,
			surface * CFrame.new(math.cos(angle) * distance, 0.25, math.sin(angle) * distance),
			rgb(255, 236, 150)
		)
		bubble.Shape = Enum.PartType.Ball
	end
end

-- A bright yellow banana peel, splayed out, sitting on a team-coloured ring.
local function buildPeel(model: Model, surface: CFrame, teamColor: Color3)
	local ring = disc(model, "TeamRing", surface, T.PeelRadius + 0.6, 0.12, teamColor)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	local yellow = rgb(255, 222, 60)
	local centre = piece(model, "Peel", Vector3.new(2.4, 1.6, 2.4), surface * CFrame.new(0, 0.8, 0), yellow)
	centre.Shape = Enum.PartType.Ball
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2
		local petal = piece(
			model,
			"Petal",
			Vector3.new(1.7, 0.45, 3.9),
			surface * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.45, -2.2) * CFrame.Angles(math.rad(12), 0, 0),
			yellow
		)
		local corner = Instance.new("SpecialMesh")
		corner.MeshType = Enum.MeshType.Sphere
		corner.Parent = petal
		piece(
			model,
			"Tip",
			Vector3.new(0.75, 0.45, 0.75),
			surface * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.85, -3.9),
			rgb(110, 76, 30)
		)
	end
	local stem = piece(
		model,
		"Stem",
		Vector3.new(1.3, 0.65, 0.65),
		surface * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(120, 86, 34)
	)
	stem.Shape = Enum.PartType.Cylinder
end

-- A cheese puddle (kind "cheese") or banana peel (kind "peel") lying on a surface. `surface` is a CFrame on the
-- surface whose UpVector points out of it.
function PropBuilder.hazard(kind: string, surface: CFrame, teamColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = if kind == "cheese" then "CheesePuddle" else "BananaPeel"
	if kind == "cheese" then
		buildCheese(model, surface, teamColor)
	else
		buildPeel(model, surface, teamColor)
	end
	return model
end

return PropBuilder
