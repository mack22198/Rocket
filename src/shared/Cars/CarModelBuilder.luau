--!strict
-- Builds each car's 3D model out of plain parts (no uploaded assets needed), at any of its evolution stages.
-- Every car is an invisible physics box called "Chassis" (the hitbox) with decorative parts welded on.
-- The same builder makes the showroom cars in the lobby and the spinning previews in the garage.
--
-- Car space: the car faces -Z, +Y is up, the chassis centre is the origin.
--
-- Parts are coloured by role ("body", "accent", ...) so each evolution stage can repaint the whole car:
-- stages 1 and 2 use the car's own colours, stage 3 turns every car into glowing lava and stage 4 into
-- deep space. Evolving is only for looks; it never changes how a car drives.

local CarCatalog = require(script.Parent.Parent.Config.CarCatalog)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

type CarDef = CarCatalog.CarDef

export type BuildOptions = {
	teamColor: Color3?, -- underglow + antenna colour (nil = neutral, for previews)
	preview: boolean?, -- true = no physics setup (showroom and garage)
	stage: number?, -- evolution stage, 1 (as unlocked) to GameConfig.Evolution.Stages
}

type Shape = "Block" | "Wedge" | "Cylinder" | "Ball" | "Ellipsoid"

type Look = { color: Color3, material: Enum.Material?, transparency: number?, reflectance: number? }

type Roles = { [string]: Look }

type PartSpec = {
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	role: string,
	name: string?,
}

-- Adds one part to the car being built.
type Add = (role: string, shape: Shape, size: Vector3, cframe: CFrame, name: string?) -> ()

type Design = {
	roles: { Roles }, -- the car's own colours at stage 1 and stage 2
	antenna: Vector3, -- where the team antenna sticks out of the body
	build: (h: Vector3, stage: number, add: Add) -> (),
}

local CarModelBuilder = {}

local rgb = Color3.fromRGB
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal

-- Rotations that turn a cylinder's axis (its X axis) to point along other axes.
local CYL_ALONG_Y = CFrame.Angles(0, 0, math.rad(90)) -- a flat disc lying down
local CYL_ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- a tube pointing forward

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function look(color: Color3, material: Enum.Material?, transparency: number?, reflectance: number?): Look
	return { color = color, material = material, transparency = transparency, reflectance = reflectance }
end

-- Colours every car shares unless it says otherwise.
local COMMON: Roles = {
	eye = look(rgb(255, 255, 255)),
	pupil = look(rgb(20, 20, 28)),
	shine = look(rgb(255, 255, 255), NEON),
	dark = look(rgb(34, 34, 42)),
	white = look(rgb(248, 248, 250)),
	glass = look(rgb(170, 222, 255), GLASS, 0.35, 0.1),
	lamp = look(rgb(255, 250, 226), NEON),
	tail = look(rgb(255, 56, 48), NEON),
	tire = look(rgb(36, 36, 42)),
	rim = look(rgb(226, 228, 236), METAL),
	metal = look(rgb(186, 190, 202), METAL),
}

-- Stage 3 and 4 repaint every car with the same theme (eyes stay as they are, so every car keeps its face).
local THEMES: { [number]: Roles } = {
	[3] = { -- Lava: cooled black rock with molten orange glowing through
		body = look(rgb(64, 42, 38), Enum.Material.Slate),
		body2 = look(rgb(44, 30, 28), Enum.Material.Basalt),
		accent = look(rgb(255, 104, 26), NEON),
		light = look(rgb(255, 168, 56), NEON),
		skin = look(rgb(255, 150, 60), NEON),
		dark = look(rgb(28, 20, 18)),
		white = look(rgb(255, 196, 120)),
		glass = look(rgb(255, 150, 90), GLASS, 0.3, 0.1),
		lamp = look(rgb(255, 214, 140), NEON),
		tail = look(rgb(255, 60, 20), NEON),
		tire = look(rgb(30, 22, 20)),
		rim = look(rgb(255, 118, 40), NEON),
		metal = look(rgb(96, 64, 54), METAL),
	},
	[4] = { -- Galaxy: deep space purple with starlight trim
		body = look(rgb(50, 32, 120), SMOOTH, 0, 0.12),
		body2 = look(rgb(108, 60, 200), SMOOTH, 0, 0.12),
		accent = look(rgb(90, 232, 255), NEON),
		light = look(rgb(255, 128, 228), NEON),
		skin = look(rgb(150, 255, 220), NEON),
		dark = look(rgb(20, 14, 48)),
		white = look(rgb(214, 236, 255)),
		glass = look(rgb(170, 230, 255), GLASS, 0.25, 0.15),
		lamp = look(rgb(214, 250, 255), NEON),
		tail = look(rgb(255, 110, 220), NEON),
		tire = look(rgb(26, 18, 52)),
		rim = look(rgb(90, 232, 255), NEON),
		metal = look(rgb(150, 132, 222), METAL),
	},
}

-- Distance from the chassis centre down to the ground when the car rests on its suspension.
local function groundY(hitbox: Vector3): number
	local sag = GameConfig.Car.Gravity / GameConfig.Car.SpringStrength
	return -hitbox.Y / 2 - (GameConfig.Car.RideHeight - sag)
end

-- A frame at `position` whose front (-Z) faces `facing`.
local function facingFrame(position: Vector3, facing: Vector3): CFrame
	local up = if math.abs(facing.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local right = facing:Cross(up).Unit
	return CFrame.fromMatrix(position, right, right:Cross(facing))
end

-- One cartoon eye on a surface that faces `facing`. `glance` nudges the pupil (in the eye's own left/right,
-- up/down), which is what gives each car its expression.
local function eye(add: Add, position: Vector3, facing: Vector3, size: number, glance: Vector2?)
	local frame = facingFrame(position, facing.Unit)
	local g = glance or Vector2.new(0, -0.12)
	add("eye", "Ellipsoid", Vector3.new(size, size * 1.2, size * 0.5), frame, "Eye")
	local pupil = frame * CFrame.new(g.X * size, g.Y * size, -size * 0.2)
	add("pupil", "Ellipsoid", Vector3.new(size * 0.52, size * 0.64, size * 0.32), pupil, "Pupil")
	add("shine", "Ball", Vector3.one * size * 0.18, pupil * CFrame.new(size * 0.1, size * 0.14, -size * 0.14), "Shine")
end

-- A pair of eyes side by side on a surface facing `facing`, looking a little inward (it's cuter).
local function eyes(add: Add, centre: Vector3, facing: Vector3, spacing: number, size: number)
	local frame = facingFrame(centre, facing.Unit)
	for _, side in { -1, 1 } do
		local position = frame * Vector3.new(side * spacing / 2, 0, 0)
		eye(add, position, facing, size, Vector2.new(-side * 0.1, -0.12))
	end
end

type WheelOptions = {
	inset: number?,
	frontInset: number?,
	rearRadius: number?,
	treads: boolean?,
}

local function wheels(add: Add, hitbox: Vector3, radius: number, width: number, options: WheelOptions?)
	local o: WheelOptions = options or ({} :: WheelOptions)
	local inset = o.inset or 0.8
	local frontZ = -hitbox.Z / 2 + (o.frontInset or 1.6)
	local rearZ = hitbox.Z / 2 - 1.6
	local floor = groundY(hitbox)
	for _, side in { -1, 1 } do
		for _, z in { frontZ, rearZ } do
			local r = if z == rearZ then (o.rearRadius or radius) else radius
			local x = side * (hitbox.X / 2 - inset + width / 2 - 0.2)
			local centre = at(x, floor + r, z)
			add("tire", "Cylinder", Vector3.new(width, r * 2, r * 2), centre, "Wheel")
			add("rim", "Cylinder", Vector3.new(width + 0.1, r * 1.2, r * 1.2), centre, "Rim")
			add("dark", "Cylinder", Vector3.new(width + 0.16, r * 0.45, r * 0.45), centre, "HubCap")
			if o.treads then
				for k = 0, 5 do
					local angle = k * math.pi / 3
					add(
						"tire",
						"Block",
						Vector3.new(width + 0.1, r * 0.34, r * 0.3),
						centre * CFrame.Angles(angle, 0, 0) * CFrame.new(0, r - 0.05, 0),
						"Tread"
					)
				end
			end
		end
	end
end

local designs: { [string]: Design } = {}

designs.pizza = {
	roles = {
		{
			body = look(rgb(228, 162, 86)), -- crust
			body2 = look(rgb(180, 110, 52)), -- darker crust
			accent = look(rgb(204, 48, 38)), -- pepperoni
			light = look(rgb(255, 208, 72)), -- cheese
		},
		{ -- Burnt: a little too long in the oven
			body = look(rgb(150, 88, 42)),
			body2 = look(rgb(76, 46, 28)),
			accent = look(rgb(140, 26, 20)),
			light = look(rgb(236, 164, 48)),
			rim = look(rgb(255, 196, 64), METAL),
		},
	},
	antenna = Vector3.new(1.75, 0.3, 2.9),
	build = function(h, stage, add)
		add("body2", "Block", Vector3.new(5.0, 0.8, 7.9), at(0, -0.75, 0))
		add("body", "Ellipsoid", Vector3.new(5.5, 2.3, 8.5), at(0, -0.15, 0))
		add("body", "Ellipsoid", Vector3.new(4.8, 0.9, 1.3), at(0, -0.62, -3.8))
		add("body2", "Cylinder", Vector3.new(5.3, 1.1, 1.1), at(0, -0.45, 3.85))
		-- Melted cheese over the hood, dripping down the sides, with pepperoni on top.
		add("light", "Ellipsoid", Vector3.new(4.7, 1.0, 4.4), at(0, 0.62, -1.7))
		for _, side in { -1, 1 } do
			add("light", "Ellipsoid", Vector3.new(0.55, 1.0, 0.8), at(side * 2.05, 0.25, -2.5))
			add("light", "Ellipsoid", Vector3.new(0.5, 0.8, 0.7), at(side * 2.15, 0.3, -1.2))
		end
		for _, spot in { Vector3.new(-1.0, 1.07, -2.4), Vector3.new(0.95, 1.06, -2.5), Vector3.new(0.1, 1.13, -1.3) } do
			add("accent", "Cylinder", Vector3.new(0.16, 1.05, 1.05), CFrame.new(spot) * CYL_ALONG_Y, "Pepperoni")
		end
		-- Bubble cabin with a face, and a delivery sign on the roof.
		add("glass", "Ellipsoid", Vector3.new(4.3, 2.2, 3.8), at(0, 0.85, 1.1))
		eyes(add, Vector3.new(0, 1.3, -0.5), Vector3.new(0, 0.3, -1), 1.7, 1.2)
		add("white", "Block", Vector3.new(2.4, 0.8, 1.0), at(0, 2.25, 1.5), "RoofSign")
		add("accent", "Block", Vector3.new(2.5, 0.28, 1.06), at(0, 2.32, 1.5))
		for _, side in { -1, 1 } do
			add("lamp", "Ball", Vector3.one * 0.75, at(side * 1.65, -0.05, -3.45), "Headlight")
			add("tail", "Block", Vector3.new(0.8, 0.4, 0.2), at(side * 1.7, -0.05, 3.45), "TailLight")
		end
		if stage == 2 then
			-- Burnt bits.
			for _, spot in { Vector3.new(2.4, 0.1, 1.2), Vector3.new(-2.35, 0.2, 0.4), Vector3.new(1.2, 0.72, 2.9) } do
				add("dark", "Ball", Vector3.one * 0.9, CFrame.new(spot), "Char")
			end
		end
		if stage >= 2 then
			-- A cheesy spoiler.
			for _, side in { -1, 1 } do
				add("dark", "Block", Vector3.new(0.25, 1.0, 0.35), at(side * 1.6, 1.1, 3.35))
				add("accent", "Cylinder", Vector3.new(0.1, 0.8, 0.8), at(side * 1.3, 1.83, 3.45) * CYL_ALONG_Y)
			end
			add("light", "Block", Vector3.new(5.0, 0.25, 1.4), at(0, 1.7, 3.45), "Spoiler")
		end
		wheels(add, h, 1.05, 0.9)
	end,
}

designs.banana = {
	roles = {
		{
			body = look(rgb(255, 222, 64)),
			body2 = look(rgb(124, 146, 52)), -- stem
			accent = look(rgb(112, 74, 36)), -- spots
			light = look(rgb(255, 246, 214)), -- the fruit inside
		},
		{ -- Ripe: sweeter and spottier
			body = look(rgb(250, 198, 42)),
			body2 = look(rgb(98, 72, 30)),
			accent = look(rgb(86, 54, 24)),
			light = look(rgb(255, 238, 190)),
			rim = look(rgb(255, 214, 90), METAL),
		},
	},
	antenna = Vector3.new(1.0, 0.75, 2.3),
	build = function(h, stage, add)
		-- The banana: three segments along a curve, both ends tipped up, a dark tip in front and the stem behind.
		add("body", "Ellipsoid", Vector3.new(3.9, 2.3, 4.8), at(0, -0.3, 0))
		add("body", "Ellipsoid", Vector3.new(3.4, 2.0, 4.2), at(0, 0.1, -2.6) * CFrame.Angles(math.rad(20), 0, 0))
		add("body", "Ellipsoid", Vector3.new(3.4, 2.0, 4.2), at(0, 0.1, 2.6) * CFrame.Angles(math.rad(-20), 0, 0))
		add("accent", "Ellipsoid", Vector3.new(0.6, 0.6, 0.9), at(0, 0.88, -4.52), "Tip")
		local stem = at(0, 1.35, 4.95) * CFrame.Angles(math.rad(-45), 0, 0)
		add("body2", "Cylinder", Vector3.new(1.7, 0.62, 0.62), stem * CYL_ALONG_Z, "Stem")
		add("accent", "Cylinder", Vector3.new(0.2, 0.66, 0.66), stem * CFrame.new(0, 0, 0.85) * CYL_ALONG_Z, "StemEnd")
		-- Peeled open on top, showing the fruit.
		add("light", "Ellipsoid", Vector3.new(2.6, 0.9, 3.0), at(0, 0.72, 0.35), "Fruit")
		eyes(add, Vector3.new(0, 1.18, -3.05), Vector3.new(0, 0.7, -1), 1.3, 0.95)
		-- Brown spots.
		local spots = { Vector3.new(1.85, -0.2, -0.8), Vector3.new(-1.9, 0.0, 0.7), Vector3.new(1.45, 0.45, 2.2) }
		if stage == 2 then
			table.insert(spots, Vector3.new(-1.45, 0.5, -2.1))
			table.insert(spots, Vector3.new(1.75, -0.6, 1.2))
			table.insert(spots, Vector3.new(-1.8, -0.55, -0.6))
		end
		for _, spot in spots do
			add("accent", "Ball", Vector3.one * 0.5, CFrame.new(spot), "Spot")
		end
		for _, side in { -1, 1 } do
			add("lamp", "Ball", Vector3.one * 0.45, at(side * 0.8, -0.15, -4.1), "Headlight")
			add("tail", "Ball", Vector3.one * 0.42, at(side * 0.8, -0.05, 4.1), "TailLight")
		end
		if stage >= 2 then
			-- A leafy wing.
			for _, side in { -1, 1 } do
				add("dark", "Block", Vector3.new(0.22, 0.9, 0.3), at(side * 1.3, 1.3, 2.9))
			end
			add("body2", "Ellipsoid", Vector3.new(4.4, 0.3, 1.5), at(0, 1.8, 2.95), "Spoiler")
		end
		wheels(add, h, 0.95, 0.8, { inset = 0.6 })
	end,
}

designs.kart = {
	roles = {
		{
			body = look(rgb(64, 208, 96)),
			body2 = look(rgb(34, 136, 66)),
			accent = look(rgb(236, 64, 64)), -- racing suit
			light = look(rgb(248, 248, 250)),
			glass = look(rgb(40, 64, 96), GLASS, 0.1, 0.3),
		},
		{ -- Turbo: gold and racing stripes
			body = look(rgb(36, 220, 128)),
			body2 = look(rgb(20, 120, 80)),
			accent = look(rgb(255, 200, 48)),
			light = look(rgb(255, 255, 255)),
			glass = look(rgb(40, 64, 96), GLASS, 0.1, 0.3),
			rim = look(rgb(255, 200, 48), METAL),
		},
	},
	antenna = Vector3.new(1.55, -0.55, 3.2),
	build = function(h, stage, add)
		add("dark", "Block", Vector3.new(3.8, 0.35, 6.6), at(0, -1.15, 0.1), "Floor")
		add("body", "Ellipsoid", Vector3.new(3.4, 1.1, 3.2), at(0, -0.75, -2.2), "Nose")
		add("body2", "Block", Vector3.new(4.6, 0.2, 0.9), at(0, -1.0, -3.4), "FrontWing")
		add("light", "Cylinder", Vector3.new(0.12, 1.1, 1.1), at(0, -0.21, -2.3) * CYL_ALONG_Y, "Number")
		for _, side in { -1, 1 } do
			add("body", "Ellipsoid", Vector3.new(1.2, 0.95, 3.2), at(side * 1.95, -0.85, 0.5), "SidePod")
			if stage >= 2 then
				add("light", "Block", Vector3.new(0.1, 0.25, 2.4), at(side * 2.52, -0.7, 0.5), "Stripe")
			end
		end
		add("metal", "Cylinder", Vector3.new(4.8, 0.45, 0.45), at(0, -1.0, 3.55), "Bumper")
		-- Seat and driver.
		add("dark", "Block", Vector3.new(1.8, 0.4, 1.5), at(0, -0.85, 0.7), "Seat")
		add("dark", "Block", Vector3.new(1.8, 1.4, 0.35), at(0, -0.25, 1.45) * CFrame.Angles(math.rad(-12), 0, 0))
		add("accent", "Ellipsoid", Vector3.new(1.5, 1.6, 1.1), at(0, -0.05, 0.75), "Driver")
		add("body", "Ball", Vector3.one * 1.6, at(0, 1.2, 0.55), "Helmet")
		add("light", "Cylinder", Vector3.new(0.3, 1.66, 1.66), at(0, 1.2, 0.55), "HelmetStripe")
		add("glass", "Ellipsoid", Vector3.new(1.2, 0.6, 0.6), at(0, 1.22, 0.02), "Visor")
		eyes(add, Vector3.new(0, 1.24, -0.2), Vector3.new(0, 0.1, -1), 0.5, 0.36)
		-- Engine, exhausts and wing.
		add("metal", "Block", Vector3.new(2.0, 0.9, 1.2), at(0, -0.6, 2.6), "Engine")
		for _, side in { -1, 1 } do
			add("metal", "Cylinder", Vector3.new(1.3, 0.4, 0.4), at(side * 0.55, -0.3, 3.4) * CYL_ALONG_Z)
			add("dark", "Block", Vector3.new(0.2, 1.3, 0.3), at(side * 1.3, 0.2, 3.25))
			add("tail", "Block", Vector3.new(0.5, 0.3, 0.15), at(side * 1.5, -0.7, 3.8), "TailLight")
		end
		add("body", "Block", Vector3.new(4.4, 0.22, 1.1), at(0, 0.9, 3.3), "Wing")
		if stage >= 2 then
			for _, side in { -1, 1 } do
				add("body2", "Block", Vector3.new(0.2, 0.9, 1.3), at(side * 2.25, 1.05, 3.3), "WingEnd")
			end
		end
		wheels(add, h, 0.85, 0.9, { rearRadius = 1.15, inset = 0.55, frontInset = 1.3 })
	end,
}

designs.shark = {
	roles = {
		{
			body = look(rgb(98, 126, 162)),
			body2 = look(rgb(72, 94, 128)),
			accent = look(rgb(40, 255, 236), NEON),
			light = look(rgb(236, 240, 246)), -- belly
			dark = look(rgb(120, 24, 38)), -- mouth
		},
		{ -- Tiger: stripes!
			body = look(rgb(214, 140, 74)),
			body2 = look(rgb(64, 46, 36)),
			accent = look(rgb(255, 214, 64), NEON),
			light = look(rgb(250, 238, 216)),
			dark = look(rgb(120, 24, 38)),
			rim = look(rgb(255, 214, 64), METAL),
		},
	},
	antenna = Vector3.new(1.2, 0.8, 2.7),
	build = function(h, stage, add)
		add("body", "Ellipsoid", Vector3.new(5.1, 2.5, 9.0), at(0, 0.05, 0))
		add("light", "Ellipsoid", Vector3.new(4.7, 1.5, 8.2), at(0, -0.5, -0.25), "Belly")
		-- A big grin full of teeth.
		add("dark", "Ellipsoid", Vector3.new(3.4, 0.8, 1.6), at(0, -0.3, -3.75), "Mouth")
		for i = -2, 2 do
			local z = if i == 0 then -4.3 elseif math.abs(i) == 1 then -4.2 else -3.9
			add(
				"white",
				"Wedge",
				Vector3.new(0.4, 0.5, 0.3),
				at(i * 0.6, 0.02, z) * CFrame.Angles(math.pi, 0, 0),
				"Tooth"
			)
		end
		for _, side in { -1, 1 } do
			eye(
				add,
				Vector3.new(side * 1.95, 0.55, -2.55),
				Vector3.new(side, 0.2, -0.45),
				1.0,
				Vector2.new(side * 0.12, -0.1)
			)
			-- Fins and glowing gills.
			add(
				"body2",
				"Wedge",
				Vector3.new(0.3, 1.2, 2.0),
				at(side * 2.55, -0.55, -0.3) * CFrame.Angles(0, 0, math.rad(-side * 120)),
				"SideFin"
			)
			for k = 0, 2 do
				local z = -1.4 + k * 0.45
				local x = 2.55 * math.sqrt(1 - (0.15 / 1.25) ^ 2 - (z / 4.5) ^ 2) + 0.02
				add("accent", "Block", Vector3.new(0.12, 0.9, 0.16), at(side * x, 0.2, z), "Gill")
			end
			add("lamp", "Ball", Vector3.one * 0.4, at(side * 1.4, -0.35, -3.85), "Headlight")
			add("tail", "Ball", Vector3.one * 0.4, at(side * 1.2, 0.0, 4.2), "TailLight")
		end
		add("body", "Wedge", Vector3.new(0.5, 2.3, 2.8), at(0, 2.15, 0.6), "DorsalFin")
		add(
			"body",
			"Wedge",
			Vector3.new(0.45, 2.0, 1.8),
			at(0, 1.3, 4.45) * CFrame.Angles(math.rad(-20), 0, 0),
			"TailFin"
		)
		if stage == 2 then
			for _, z in { -1.6, -0.3, 1.0, 2.3 } do
				local top = 0.05 + 1.25 * math.sqrt(1 - (z / 4.5) ^ 2)
				add("body2", "Ellipsoid", Vector3.new(3.6, 0.5, 0.5), at(0, top - 0.12, z), "Stripe")
			end
		end
		wheels(add, h, 1.05, 0.85, { inset = 0.7 })
	end,
}

designs.monster = {
	roles = {
		{
			body = look(rgb(224, 50, 46)),
			body2 = look(rgb(148, 28, 32)),
			accent = look(rgb(255, 200, 40)),
			rim = look(rgb(255, 200, 40), METAL),
		},
		{ -- Mega: black paint, chrome and flames
			body = look(rgb(42, 42, 52)),
			body2 = look(rgb(24, 24, 30)),
			accent = look(rgb(255, 132, 30), NEON),
			metal = look(rgb(226, 228, 236), METAL, 0, 0.3),
			rim = look(rgb(226, 228, 236), METAL, 0, 0.3),
		},
	},
	antenna = Vector3.new(2.4, 1.45, 4.0),
	build = function(h, stage, add)
		add("dark", "Block", Vector3.new(1.4, 0.8, 7.6), at(0, -1.0, 0), "Frame")
		for _, z in { -3.0, 3.0 } do
			add("metal", "Cylinder", Vector3.new(6.2, 0.5, 0.5), at(0, -0.63, z), "Axle")
		end
		add("body", "Block", Vector3.new(5.6, 1.3, 8.8), at(0, 0.0, 0))
		add("body", "Wedge", Vector3.new(5.6, 0.6, 2.6), at(0, 0.95, -2.9), "Hood")
		add("body", "Block", Vector3.new(5.2, 1.7, 3.2), at(0, 1.5, 0.3), "Cab")
		add("glass", "Wedge", Vector3.new(5.0, 1.5, 1.2), at(0, 1.5, -1.85), "Windshield")
		add("glass", "Block", Vector3.new(5.3, 0.9, 2.2), at(0, 1.75, 0.45), "Windows")
		add("body2", "Block", Vector3.new(5.4, 0.25, 3.4), at(0, 2.45, 0.3), "Roof")
		add("body2", "Block", Vector3.new(5.4, 0.8, 2.6), at(0, 1.05, 3.2), "Bed")
		add("dark", "Block", Vector3.new(4.6, 0.3, 2.2), at(0, 1.35, 3.2))
		-- The face: a toothy grille, headlight eyes and angry eyebrows.
		add("dark", "Block", Vector3.new(4.0, 1.0, 0.3), at(0, 0.05, -4.45), "Grille")
		for i = -3, 3 do
			add(
				"white",
				"Wedge",
				Vector3.new(0.45, 0.4, 0.2),
				at(i * 0.55, 0.35, -4.62) * CFrame.Angles(math.pi, 0, 0),
				"Tooth"
			)
			add("white", "Wedge", Vector3.new(0.45, 0.35, 0.2), at(i * 0.55 + 0.27, -0.27, -4.62), "Tooth")
		end
		for _, side in { -1, 1 } do
			eye(
				add,
				Vector3.new(side * 1.95, 0.95, -4.35),
				Vector3.new(0, 0.25, -1),
				1.05,
				Vector2.new(-side * 0.1, -0.05)
			)
			add(
				"dark",
				"Block",
				Vector3.new(1.3, 0.28, 0.3),
				at(side * 1.95, 1.62, -4.3) * CFrame.Angles(0, 0, math.rad(side * 18)),
				"Brow"
			)
			add("metal", "Cylinder", Vector3.new(1.6, 0.45, 0.45), at(side * 2.3, 2.3, 2.0) * CYL_ALONG_Y, "Exhaust")
			add("tail", "Block", Vector3.new(0.8, 0.4, 0.15), at(side * 2.2, 0.3, 4.45), "TailLight")
			if stage >= 2 then
				-- Flames licking along the sides.
				for k = 0, 2 do
					add(
						"accent",
						"Ellipsoid",
						Vector3.new(0.14, 0.55 - k * 0.1, 2.0 - k * 0.3),
						at(side * 2.81, 0.05 + k * 0.28, -2.6 + k * 0.5),
						"Flame"
					)
				end
			end
		end
		add("metal", "Block", Vector3.new(6.0, 0.6, 0.6), at(0, -0.5, -4.55), "Bumper")
		add("dark", "Block", Vector3.new(5.4, 0.25, 0.35), at(0, 2.8, -0.9), "LightBar")
		for i = 0, 3 do
			add("lamp", "Ball", Vector3.one * 0.5, at(-1.8 + i * 1.2, 3.05, -0.9), "RoofLight")
		end
		wheels(add, h, 1.75, 1.4, { inset = 0.2, treads = true })
	end,
}

designs.ufo = {
	roles = {
		{
			body = look(rgb(198, 206, 222), METAL),
			body2 = look(rgb(132, 140, 158), METAL),
			accent = look(rgb(120, 255, 80), NEON),
			light = look(rgb(255, 100, 210), NEON),
			skin = look(rgb(112, 222, 92)),
			glass = look(rgb(170, 240, 255), GLASS, 0.45, 0.1),
		},
		{ -- Golden
			body = look(rgb(255, 200, 64), METAL, 0, 0.2),
			body2 = look(rgb(200, 146, 40), METAL),
			accent = look(rgb(90, 232, 255), NEON),
			light = look(rgb(255, 255, 255), NEON),
			skin = look(rgb(112, 222, 92)),
			glass = look(rgb(200, 250, 255), GLASS, 0.45, 0.1),
		},
	},
	antenna = Vector3.new(2.3, -0.1, 2.3),
	build = function(h, stage, add)
		local floor = groundY(h)
		add("body", "Ellipsoid", Vector3.new(7.4, 1.3, 7.4), at(0, -0.35, 0), "Saucer")
		add("body2", "Ellipsoid", Vector3.new(4.6, 1.5, 4.6), at(0, -0.75, 0))
		add("accent", "Cylinder", Vector3.new(0.22, 7.6, 7.6), at(0, -0.35, 0) * CYL_ALONG_Y, "Rim")
		local lights = if stage >= 2 then 14 else 10
		for i = 0, lights - 1 do
			local angle = i / lights * math.pi * 2
			local role = if i % 2 == 0 then "light" else "lamp"
			add(role, "Ball", Vector3.one * 0.55, at(math.sin(angle) * 3.35, -0.12, math.cos(angle) * 3.35), "RimLight")
		end
		-- The pilot, under a glass dome.
		add("glass", "Ellipsoid", Vector3.new(3.6, 3.0, 3.6), at(0, 0.45, 0.3), "Dome")
		add("skin", "Ellipsoid", Vector3.new(1.3, 1.1, 1.2), at(0, 0.35, 0.35), "Alien")
		add("skin", "Ellipsoid", Vector3.new(1.6, 1.4, 1.4), at(0, 1.15, 0.3), "AlienHead")
		for _, side in { -1, 1 } do
			local socket = at(side * 0.36, 1.2, -0.28) * CFrame.Angles(0, 0, math.rad(-side * 25))
			add("pupil", "Ellipsoid", Vector3.new(0.5, 0.78, 0.3), socket, "AlienEye")
			add("shine", "Ball", Vector3.one * 0.14, socket * CFrame.new(0.08, 0.18, -0.13))
			local tip = Vector3.new(side * 0.55, 2.3, 0.3)
			local base = Vector3.new(side * 0.3, 1.75, 0.3)
			local stalk = CFrame.new((tip + base) / 2) * CFrame.Angles(0, 0, math.rad(90 - side * 25))
			add("skin", "Cylinder", Vector3.new((tip - base).Magnitude, 0.1, 0.1), stalk, "Antenna")
			add("accent", "Ball", Vector3.one * 0.3, CFrame.new(tip), "AntennaTip")
		end
		-- Glowing hover pads instead of wheels.
		for _, x in { -2.2, 2.2 } do
			for _, z in { -2.3, 2.3 } do
				add("dark", "Cylinder", Vector3.new(0.5, 1.6, 1.6), at(x, floor + 0.85, z) * CYL_ALONG_Y, "PadHolder")
				add("lamp", "Cylinder", Vector3.new(0.3, 1.3, 1.3), at(x, floor + 0.55, z) * CYL_ALONG_Y, "HoverPad")
			end
		end
		if stage >= 2 then
			for _, side in { -1, 1 } do
				add(
					"body2",
					"Wedge",
					Vector3.new(0.3, 1.0, 1.8),
					at(side * 2.6, 0.2, 2.4) * CFrame.Angles(0, 0, math.rad(-side * 20)),
					"Fin"
				)
			end
		end
	end,
}

local function makePart(spec: PartSpec, style: Look): BasePart
	local part: BasePart
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if spec.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif spec.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif spec.shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		part = p
	end
	part.Name = spec.name or "Body"
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = style.color
	part.Material = style.material or SMOOTH
	part.Transparency = style.transparency or 0
	part.Reflectance = style.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = style.material ~= NEON and (style.transparency or 0) < 0.3
	return part
end

-- The colours for a car at a stage: its own colours (or the stage's theme), then the shared defaults.
local function rolesFor(design: Design, stage: number): (string) -> Look
	local own = design.roles[math.min(stage, #design.roles)]
	local theme = THEMES[stage]
	local base = design.roles[1]
	return function(role: string): Look
		if theme and theme[role] then
			return theme[role]
		end
		return own[role] or base[role] or COMMON[role] or COMMON.white
	end
end

local function particles(
	parent: Instance,
	name: string,
	colors: ColorSequence,
	size: number,
	rate: number
): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = colors
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = parent
	return emitter
end

-- The boost flame colours for each stage.
local FLAMES = {
	[3] = ColorSequence.new(rgb(255, 214, 90), rgb(210, 30, 10)),
	[4] = ColorSequence.new(rgb(196, 140, 255), rgb(60, 220, 255)),
}

-- Builds a car model positioned at the origin. Move it with model:PivotTo(cframe).
function CarModelBuilder.build(def: CarDef, options: BuildOptions?): Model
	local opts: BuildOptions = options or ({} :: BuildOptions)
	local stage = math.clamp(math.floor(opts.stage or 1), 1, GameConfig.Evolution.Stages)
	local hitbox = def.Hitbox
	local model = Instance.new("Model")
	model.Name = CarCatalog.stageName(def, stage)
	model:SetAttribute("Stage", stage)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = hitbox
	chassis.CFrame = CFrame.new()
	chassis.Transparency = 1
	chassis.CanTouch = false
	chassis.CanQuery = false
	chassis.CastShadow = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	if opts.preview then
		chassis.CanCollide = false
		chassis.Anchored = true
	else
		chassis.CanCollide = true
		chassis.RootPriority = 10
		-- Friction 0.3, no bounce: the wheels do the driving, the box only matters when the car lands badly.
		chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0, 1, 1)
	end
	chassis.Parent = model
	model.PrimaryPart = chassis

	local design = designs[def.Id] or designs.pizza
	local styleOf = rolesFor(design, stage)
	local specs: { PartSpec } = {}
	design.build(hitbox, stage, function(role, shape, size, cframe, name)
		table.insert(specs, { role = role, shape = shape, size = size, cframe = cframe, name = name })
	end)

	-- A team-coloured ball on an antenna, so teams are easy to tell apart from anywhere on the field.
	local teamColor = opts.teamColor or rgb(236, 236, 240)
	local antennaHeight = hitbox.Y + 1.1 - design.antenna.Y
	table.insert(specs, {
		role = "dark",
		shape = "Cylinder",
		size = Vector3.new(antennaHeight, 0.14, 0.14),
		cframe = CFrame.new(design.antenna + Vector3.new(0, antennaHeight / 2, 0)) * CYL_ALONG_Y,
		name = "Antenna",
	})

	for _, spec in specs do
		local part = makePart(spec, styleOf(spec.role))
		if opts.preview then
			part.Anchored = true
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = chassis
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end
	local flag = makePart({
		role = "team",
		shape = "Ball",
		size = Vector3.one * 0.85,
		cframe = CFrame.new(design.antenna + Vector3.new(0, antennaHeight + 0.25, 0)),
		name = "TeamFlag",
	}, look(teamColor, NEON))
	if opts.preview then
		flag.Anchored = true
	else
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = flag
		weld.Parent = flag
	end
	flag.Parent = model

	-- Team-coloured light on the ground under the car.
	if opts.teamColor then
		local glowPoint = Instance.new("Attachment")
		glowPoint.Name = "Underglow"
		glowPoint.Position = Vector3.new(0, groundY(hitbox) + 0.6, 0)
		glowPoint.Parent = chassis
		local glow = Instance.new("PointLight")
		glow.Color = opts.teamColor
		glow.Range = 12
		glow.Brightness = 2.5
		glow.Shadows = false
		glow.Parent = glowPoint
	end

	-- Boost flames come out of the back.
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(0, -0.2, hitbox.Z / 2 + 0.2)
	exhaust.Parent = chassis

	local flames = Instance.new("ParticleEmitter")
	flames.Name = "BoostFlames"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = FLAMES[stage] or ColorSequence.new(rgb(255, 240, 120), rgb(255, 90, 20))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	flames.Lifetime = NumberRange.new(0.2, 0.35)
	flames.Rate = 90
	flames.Speed = NumberRange.new(14, 20)
	flames.SpreadAngle = Vector2.new(10, 10)
	flames.EmissionDirection = Enum.NormalId.Back
	flames.Enabled = false
	flames.Parent = exhaust

	-- Fire glow for an armed Mega Shot.
	local megaGlow = particles(chassis, "MegaGlow", ColorSequence.new(rgb(255, 200, 60), rgb(255, 60, 20)), 1.2, 40)
	megaGlow.Lifetime = NumberRange.new(0.4, 0.7)
	megaGlow.Speed = NumberRange.new(2, 5)
	megaGlow.Enabled = false

	-- Evolved cars give off embers (lava) or stardust (galaxy).
	if stage == 3 then
		local embers = particles(chassis, "StageAura", ColorSequence.new(rgb(255, 190, 70), rgb(255, 60, 20)), 0.35, 10)
		embers.Acceleration = Vector3.new(0, 5, 0)
	elseif stage >= 4 then
		particles(
			chassis,
			"StageAura",
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
				ColorSequenceKeypoint.new(0.5, rgb(120, 230, 255)),
				ColorSequenceKeypoint.new(1, rgb(255, 128, 228)),
			}),
			0.4,
			12
		)
	end

	return model
end

return CarModelBuilder
