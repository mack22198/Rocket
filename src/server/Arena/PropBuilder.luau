--!strict
-- The things on the pitch besides the ball and the cars: the charge orb, and what ultimates leave lying around
-- (gooey cheese, banana peels, ketchup). Just the looks; OrbService and PowerService decide where they go and
-- what they do.

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

-- The charge orb: a bright glowing ball inside a glassy shell, with a ring on the ground below it and a tall beam
-- of light over it so you can see where it is from anywhere on the pitch. `position` is the middle of the orb.
function PropBuilder.chargeOrb(folder: Instance, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "ChargeOrb"
	local centre = CFrame.new(position)
	local shell = part(model, "Shell", Vector3.one * 7.4, centre, rgb(150, 236, 255))
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.Glass
	shell.Transparency = 0.45
	shell.Reflectance = 0.2
	local core = part(model, "Core", Vector3.one * 4.6, centre, rgb(80, 220, 255))
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = rgb(120, 230, 255)
	light.Range = 22
	light.Brightness = 2.5
	light.Parent = core
	local ring = part(
		model,
		"Spot",
		Vector3.new(0.12, 11, 11),
		CFrame.new(position.X, 0.07, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(80, 220, 255)
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	local beacon = part(
		model,
		"Beacon",
		Vector3.new(70, 2.4, 2.4),
		CFrame.new(position.X, position.Y + 35, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(80, 220, 255)
	)
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.7
	model.PrimaryPart = core
	model:SetAttribute("Home", position)
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

-- A thick, gooey flood of melted cheese with a lumpy rim and bubbles in it, ringed in the dropping team's colour.
local function buildCheese(model: Model, surface: CFrame, teamColor: Color3)
	local ring = disc(model, "TeamRing", surface, T.CheeseRadius + 0.8, 0.16, teamColor)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	disc(model, "Cheese", surface, T.CheeseRadius, 0.5, rgb(255, 190, 40))
	disc(model, "Melt", surface * CFrame.new(1.2, 0, -0.8), T.CheeseRadius * 0.62, 0.7, rgb(255, 222, 110))
	-- A lumpy rim, so it stands up off the pitch even from far away.
	for i = 1, 14 do
		local angle = i / 14 * math.pi * 2
		local lump = piece(
			model,
			"Rim",
			Vector3.new(2.6, 1.1 + (i % 3) * 0.25, 2.6),
			surface * CFrame.new(math.cos(angle) * (T.CheeseRadius - 1), 0.4, math.sin(angle) * (T.CheeseRadius - 1)),
			rgb(255, 176, 30)
		)
		lump.Shape = Enum.PartType.Ball
	end
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2 + 0.4
		local distance = T.CheeseRadius * (0.25 + 0.12 * (i % 4))
		local size = 1.3 + (i % 3) * 0.5
		local bubble = piece(
			model,
			"Bubble",
			Vector3.one * size,
			surface * CFrame.new(math.cos(angle) * distance, 0.45, math.sin(angle) * distance),
			rgb(255, 236, 150)
		)
		bubble.Shape = Enum.PartType.Ball
	end
end

-- A big bright yellow banana peel, splayed out, sitting on a team-coloured ring.
local function buildPeel(model: Model, surface: CFrame, teamColor: Color3)
	local ring = disc(model, "TeamRing", surface, T.PeelRadius + 0.6, 0.14, teamColor)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	local yellow = rgb(255, 222, 60)
	local s = 1.35 -- (drawn small, then made this much bigger)
	local centre = piece(model, "Peel", Vector3.new(2.4, 1.6, 2.4) * s, surface * CFrame.new(0, 0.8 * s, 0), yellow)
	centre.Shape = Enum.PartType.Ball
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2
		local petal = piece(
			model,
			"Petal",
			Vector3.new(1.7, 0.45, 3.9) * s,
			surface * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.45 * s, -2.2 * s) * CFrame.Angles(math.rad(12), 0, 0),
			yellow
		)
		local corner = Instance.new("SpecialMesh")
		corner.MeshType = Enum.MeshType.Sphere
		corner.Parent = petal
		piece(
			model,
			"Tip",
			Vector3.new(0.75, 0.45, 0.75) * s,
			surface * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.85 * s, -3.9 * s),
			rgb(110, 76, 30)
		)
	end
	local stem = piece(
		model,
		"Stem",
		Vector3.new(1.3, 0.65, 0.65) * s,
		surface * CFrame.new(0, 2 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(120, 86, 34)
	)
	stem.Shape = Enum.PartType.Cylinder
end

-- A long, glossy slick of ketchup (lying along the surface's Z axis), edged in the dropping team's colour. It's
-- made of short blobs end to end, so every screen can show it squirting out one blob after another.
local function buildKetchup(model: Model, surface: CFrame, teamColor: Color3)
	local length, width = T.KetchupLength, T.KetchupWidth
	local red = rgb(214, 28, 30)
	local blobs = 8
	local step = length / blobs
	for k = 0, blobs - 1 do
		local z = -length / 2 + (k + 0.5) * step
		local wobble = math.sin(k * 1.9) * 0.45
		local blob =
			piece(model, "Ketchup", Vector3.new(width + wobble, 0.3, step + 1), surface * CFrame.new(0, 0.15, z), red)
		blob.Reflectance = 0.25
		for _, side in { -1, 1 } do
			local edge = piece(
				model,
				"TeamEdge",
				Vector3.new(0.3, 0.2, step),
				surface * CFrame.new(side * (width / 2 + 0.45), 0.1, z),
				teamColor
			)
			edge.Material = Enum.Material.Neon
		end
		if k % 2 == 1 then
			-- A darker splat now and then.
			disc(
				model,
				"Splat",
				surface * CFrame.new((k % 4 - 1.5) * 0.9, 0.14, z),
				0.7 + (k % 3) * 0.25,
				0.26,
				rgb(150, 14, 20)
			)
		end
	end
	for _, z in { -length / 2, length / 2 } do
		local cap = disc(model, "KetchupEnd", surface * CFrame.new(0, 0, z), width / 2, 0.3, red)
		cap.Reflectance = 0.25
	end
end

-- A cheese puddle ("cheese"), banana peel ("peel") or ketchup slick ("ketchup") lying on a surface. `surface`
-- is a CFrame on the surface whose UpVector points out of it (and whose Z axis a ketchup slick runs along).
function PropBuilder.hazard(kind: string, surface: CFrame, teamColor: Color3): Model
	local model = Instance.new("Model")
	if kind == "cheese" then
		model.Name = "CheesePuddle"
		buildCheese(model, surface, teamColor)
	elseif kind == "ketchup" then
		model.Name = "KetchupSlick"
		buildKetchup(model, surface, teamColor)
	else
		model.Name = "BananaPeel"
		buildPeel(model, surface, teamColor)
	end
	model.WorldPivot = surface -- (screens animate a trap around where it lies)
	return model
end

return PropBuilder
