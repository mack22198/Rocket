--!strict
-- Builds each car's 3D model out of plain parts (no uploaded assets needed).
-- Every car is an invisible physics box called "Chassis" (the hitbox) with decorative parts welded on.
-- The same builder makes the spinning previews in the garage.
--
-- Car space: the car faces -Z, +Y is up, the chassis centre is the origin.

local CarCatalog = require(script.Parent.Parent.Config.CarCatalog)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

type CarDef = CarCatalog.CarDef

export type BuildOptions = {
	teamColor: Color3?, -- underglow + antenna colour (nil = neutral, for previews)
	preview: boolean?, -- true = no physics setup (garage viewport)
}

type Shape = "Block" | "Wedge" | "Cylinder" | "Ball"

type PartSpec = {
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	name: string?,
}

local CarModelBuilder = {}

local rgb = Color3.fromRGB
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal

local TIRE = rgb(35, 35, 40)
local HUB = rgb(200, 200, 210)
local WINDOW = rgb(150, 210, 255)
local BLACK = rgb(20, 20, 25)
local WHITE = rgb(245, 245, 245)

-- Rotations that turn a cylinder's axis (its X axis) to point along world axes.
local CYL_ALONG_Y = CFrame.Angles(0, 0, math.rad(90)) -- flat disc lying on the ground
local CYL_ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- tube pointing forward

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Distance from the chassis centre down to the ground when the car rests on its suspension.
local function groundY(hitbox: Vector3): number
	local sag = GameConfig.Car.Gravity / GameConfig.Car.SpringStrength
	return -hitbox.Y / 2 - (GameConfig.Car.RideHeight - sag)
end

type WheelOptions = {
	inset: number?,
	frontInset: number?,
	rearRadius: number?,
	color: Color3?,
	hubColor: Color3?,
}

local function wheels(specs: { PartSpec }, hitbox: Vector3, radius: number, width: number, options: WheelOptions?)
	local o: WheelOptions = options or ({} :: WheelOptions)
	local inset = o.inset or 0.8
	local frontZ = -hitbox.Z / 2 + (o.frontInset or 1.6)
	local rearZ = hitbox.Z / 2 - 1.6
	local floor = groundY(hitbox)
	for _, side in { -1, 1 } do
		for _, z in { frontZ, rearZ } do
			local r = if z == rearZ then (o.rearRadius or radius) else radius
			local x = side * (hitbox.X / 2 - inset + width / 2 - 0.2)
			local y = floor + r
			table.insert(specs, {
				shape = "Cylinder",
				size = Vector3.new(width, r * 2, r * 2),
				cframe = at(x, y, z),
				color = o.color or TIRE,
				name = "Wheel",
			})
			table.insert(specs, {
				shape = "Cylinder",
				size = Vector3.new(width + 0.1, r * 1.1, r * 1.1),
				cframe = at(x, y, z),
				color = o.hubColor or HUB,
				material = METAL,
				name = "Hub",
			})
		end
	end
end

local designs: { [string]: (hitbox: Vector3) -> { PartSpec } } = {}

designs.pizza = function(h)
	local crust = rgb(222, 158, 78)
	local crustDark = rgb(170, 105, 45)
	local cheese = rgb(255, 208, 70)
	local pepperoni = rgb(190, 45, 35)
	local s: { PartSpec } = {
		{ shape = "Block", size = Vector3.new(5.4, 1.3, 8.2), cframe = at(0, -0.3, 0), color = crust },
		{ shape = "Wedge", size = Vector3.new(5.2, 0.8, 2.6), cframe = at(0, 0.75, -2.7), color = cheese },
		{ shape = "Block", size = Vector3.new(4.6, 1.2, 3.8), cframe = at(0, 0.95, 0.9), color = crust },
		{
			shape = "Wedge",
			size = Vector3.new(4.4, 1.1, 1.2),
			cframe = at(0, 0.95, -1.6),
			color = WINDOW,
			material = GLASS,
			transparency = 0.2,
		},
		-- the giant pizza on the roof
		{
			shape = "Cylinder",
			size = Vector3.new(0.35, 5.2, 5.2),
			cframe = at(0, 1.7, 0.9) * CYL_ALONG_Y,
			color = crustDark,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.4, 4.6, 4.6),
			cframe = at(0, 1.73, 0.9) * CYL_ALONG_Y,
			color = cheese,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.45, 1.1, 1.1),
			cframe = at(1.1, 1.75, 0.2) * CYL_ALONG_Y,
			color = pepperoni,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.45, 1.1, 1.1),
			cframe = at(-1.0, 1.75, 1.8) * CYL_ALONG_Y,
			color = pepperoni,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.45, 1.0, 1.0),
			cframe = at(-0.9, 1.75, -0.3) * CYL_ALONG_Y,
			color = pepperoni,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.45, 1.0, 1.0),
			cframe = at(1.0, 1.75, 2.1) * CYL_ALONG_Y,
			color = pepperoni,
		},
		-- crusty rear bumper and headlights
		{ shape = "Cylinder", size = Vector3.new(5.6, 1.1, 1.1), cframe = at(0, -0.1, 4.0), color = crustDark },
		{
			shape = "Ball",
			size = Vector3.new(0.7, 0.7, 0.7),
			cframe = at(1.9, -0.1, -4.05),
			color = WHITE,
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(0.7, 0.7, 0.7),
			cframe = at(-1.9, -0.1, -4.05),
			color = WHITE,
			material = NEON,
		},
	}
	wheels(s, h, 1.1, 0.9)
	return s
end

designs.banana = function(h)
	local yellow = rgb(255, 225, 60)
	local tip = rgb(90, 60, 25)
	local s: { PartSpec } = {
		{ shape = "Cylinder", size = Vector3.new(6.0, 3.0, 3.0), cframe = at(0, 0.1, 0) * CYL_ALONG_Z, color = yellow },
		{ shape = "Ball", size = Vector3.new(3.0, 3.0, 3.0), cframe = at(0, 0.1, -3.0), color = yellow },
		{ shape = "Ball", size = Vector3.new(3.0, 3.0, 3.0), cframe = at(0, 0.1, 3.0), color = yellow },
		{ shape = "Ball", size = Vector3.new(1.0, 1.0, 1.0), cframe = at(0, 0.3, -4.35), color = tip },
		-- stem curling up at the back
		{
			shape = "Cylinder",
			size = Vector3.new(1.8, 0.8, 0.8),
			cframe = at(0, 1.2, 4.0) * CFrame.Angles(0, math.rad(90), math.rad(-50)),
			color = rgb(120, 150, 40),
		},
		-- peeled-back skin flaps
		{
			shape = "Wedge",
			size = Vector3.new(0.3, 1.2, 2.2),
			cframe = at(1.4, 1.2, 1.6) * CFrame.Angles(0, 0, math.rad(-20)),
			color = yellow,
		},
		{
			shape = "Wedge",
			size = Vector3.new(0.3, 1.2, 2.2),
			cframe = at(-1.4, 1.2, 1.6) * CFrame.Angles(0, 0, math.rad(20)),
			color = yellow,
		},
		{ shape = "Block", size = Vector3.new(2.2, 0.9, 1.8), cframe = at(0, 1.35, 0.6), color = rgb(255, 250, 225) },
		{
			shape = "Wedge",
			size = Vector3.new(2.2, 0.9, 1.0),
			cframe = at(0, 1.35, -0.7),
			color = WINDOW,
			material = GLASS,
			transparency = 0.2,
		},
		-- brown speckles
		{ shape = "Ball", size = Vector3.new(0.35, 0.35, 0.35), cframe = at(1.45, 0.3, -1.2), color = tip },
		{ shape = "Ball", size = Vector3.new(0.3, 0.3, 0.3), cframe = at(-1.45, 0.6, 0.4), color = tip },
		{ shape = "Ball", size = Vector3.new(0.4, 0.4, 0.4), cframe = at(1.3, 0.8, 2.3), color = tip },
	}
	wheels(s, h, 1.0, 0.8, { inset = 0.6 })
	return s
end

designs.kart = function(h)
	local green = rgb(60, 205, 90)
	local s: { PartSpec } = {
		{ shape = "Block", size = Vector3.new(3.6, 0.5, 7.0), cframe = at(0, -0.55, 0), color = green },
		{ shape = "Wedge", size = Vector3.new(3.4, 0.7, 2.0), cframe = at(0, -0.05, -2.6), color = green },
		{ shape = "Block", size = Vector3.new(5.0, 0.35, 1.0), cframe = at(0, -0.5, -3.3), color = BLACK }, -- front bumper
		{ shape = "Block", size = Vector3.new(1.0, 0.6, 3.6), cframe = at(1.9, -0.45, 0.4), color = rgb(40, 160, 70) },
		{ shape = "Block", size = Vector3.new(1.0, 0.6, 3.6), cframe = at(-1.9, -0.45, 0.4), color = rgb(40, 160, 70) },
		{ shape = "Block", size = Vector3.new(2.0, 0.5, 1.6), cframe = at(0, -0.1, 0.9), color = BLACK }, -- seat
		{ shape = "Block", size = Vector3.new(2.0, 1.5, 0.4), cframe = at(0, 0.5, 1.7), color = BLACK }, -- backrest
		{
			shape = "Cylinder",
			size = Vector3.new(0.25, 1.2, 1.2),
			cframe = at(0, 0.45, -0.6) * CFrame.Angles(math.rad(-60), 0, math.rad(90)),
			color = BLACK,
		}, -- steering wheel
		{
			shape = "Block",
			size = Vector3.new(2.4, 1.0, 1.4),
			cframe = at(0, -0.1, 3.0),
			color = rgb(90, 90, 100),
			material = METAL,
		}, -- engine
		{
			shape = "Cylinder",
			size = Vector3.new(1.2, 0.45, 0.45),
			cframe = at(0.7, 0.2, 3.9) * CYL_ALONG_Z,
			color = HUB,
			material = METAL,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(1.2, 0.45, 0.45),
			cframe = at(-0.7, 0.2, 3.9) * CYL_ALONG_Z,
			color = HUB,
			material = METAL,
		},
		{ shape = "Block", size = Vector3.new(4.6, 0.25, 0.9), cframe = at(0, 1.2, 3.7), color = green }, -- little wing
	}
	wheels(s, h, 0.85, 0.9, { rearRadius = 1.15, inset = 0.55, frontInset = 1.3 })
	return s
end

designs.shark = function(h)
	local skin = rgb(95, 120, 150)
	local belly = rgb(235, 240, 245)
	local neon = rgb(40, 255, 240)
	local s: { PartSpec } = {
		{ shape = "Block", size = Vector3.new(4.8, 1.6, 6.2), cframe = at(0, -0.05, 0.8), color = skin },
		{ shape = "Wedge", size = Vector3.new(4.8, 1.6, 2.6), cframe = at(0, -0.05, -3.6), color = skin }, -- snout
		{ shape = "Block", size = Vector3.new(4.9, 0.45, 8.6), cframe = at(0, -0.95, -0.2), color = belly },
		{ shape = "Wedge", size = Vector3.new(0.45, 2.4, 2.8), cframe = at(0, 1.95, 0.4), color = skin }, -- dorsal fin
		{ shape = "Wedge", size = Vector3.new(0.45, 2.2, 1.6), cframe = at(0, 1.4, 4.35), color = skin }, -- tail fin
		{
			shape = "Wedge",
			size = Vector3.new(0.3, 1.1, 2.0),
			cframe = at(2.7, -0.4, 0.2) * CFrame.Angles(0, 0, math.rad(-70)),
			color = skin,
		}, -- side fins
		{
			shape = "Wedge",
			size = Vector3.new(0.3, 1.1, 2.0),
			cframe = at(-2.7, -0.4, 0.2) * CFrame.Angles(0, 0, math.rad(70)),
			color = skin,
		},
		{ shape = "Ball", size = Vector3.new(0.75, 0.75, 0.75), cframe = at(1.9, 0.35, -2.9), color = BLACK }, -- eyes
		{ shape = "Ball", size = Vector3.new(0.75, 0.75, 0.75), cframe = at(-1.9, 0.35, -2.9), color = BLACK },
		{
			shape = "Ball",
			size = Vector3.new(0.25, 0.25, 0.25),
			cframe = at(2.1, 0.5, -3.1),
			color = WHITE,
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(0.25, 0.25, 0.25),
			cframe = at(-2.1, 0.5, -3.1),
			color = WHITE,
			material = NEON,
		},
		{ shape = "Block", size = Vector3.new(4.2, 0.15, 0.25), cframe = at(0, -0.55, -4.5), color = rgb(120, 20, 30) }, -- mouth
		{
			shape = "Wedge",
			size = Vector3.new(0.35, 0.4, 0.3),
			cframe = at(1.2, -0.3, -4.6) * CFrame.Angles(math.rad(180), 0, 0),
			color = WHITE,
		},
		{
			shape = "Wedge",
			size = Vector3.new(0.35, 0.4, 0.3),
			cframe = at(0.4, -0.3, -4.7) * CFrame.Angles(math.rad(180), 0, 0),
			color = WHITE,
		},
		{
			shape = "Wedge",
			size = Vector3.new(0.35, 0.4, 0.3),
			cframe = at(-0.4, -0.3, -4.7) * CFrame.Angles(math.rad(180), 0, 0),
			color = WHITE,
		},
		{
			shape = "Wedge",
			size = Vector3.new(0.35, 0.4, 0.3),
			cframe = at(-1.2, -0.3, -4.6) * CFrame.Angles(math.rad(180), 0, 0),
			color = WHITE,
		},
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.25, 6.0),
			cframe = at(2.45, 0.25, 0.6),
			color = neon,
			material = NEON,
		}, -- neon stripes
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.25, 6.0),
			cframe = at(-2.45, 0.25, 0.6),
			color = neon,
			material = NEON,
		},
		-- gills
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.8, 0.12),
			cframe = at(2.45, -0.2, -1.4),
			color = rgb(60, 80, 105),
		},
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.8, 0.12),
			cframe = at(2.45, -0.2, -1.0),
			color = rgb(60, 80, 105),
		},
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.8, 0.12),
			cframe = at(-2.45, -0.2, -1.4),
			color = rgb(60, 80, 105),
		},
		{
			shape = "Block",
			size = Vector3.new(0.12, 0.8, 0.12),
			cframe = at(-2.45, -0.2, -1.0),
			color = rgb(60, 80, 105),
		},
	}
	wheels(s, h, 1.05, 0.85, { inset = 0.7 })
	return s
end

designs.monster = function(h)
	local red = rgb(220, 45, 45)
	local s: { PartSpec } = {
		{ shape = "Block", size = Vector3.new(5.2, 1.4, 8.4), cframe = at(0, 0.5, 0), color = red },
		{ shape = "Wedge", size = Vector3.new(5.2, 0.6, 2.4), cframe = at(0, 1.5, -2.9), color = red },
		{ shape = "Block", size = Vector3.new(4.6, 1.4, 3.6), cframe = at(0, 1.9, 1.0), color = red },
		{
			shape = "Wedge",
			size = Vector3.new(4.4, 1.3, 1.2),
			cframe = at(0, 1.85, -1.4),
			color = WINDOW,
			material = GLASS,
			transparency = 0.2,
		},
		{
			shape = "Block",
			size = Vector3.new(4.7, 0.8, 2.6),
			cframe = at(0, 2.0, 1.2),
			color = WINDOW,
			material = GLASS,
			transparency = 0.3,
		},
		{ shape = "Block", size = Vector3.new(5.4, 0.25, 0.3), cframe = at(0, 2.75, -0.6), color = BLACK }, -- light bar
		{
			shape = "Ball",
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = at(1.8, 3.0, -0.6),
			color = rgb(255, 230, 90),
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = at(0.6, 3.0, -0.6),
			color = rgb(255, 230, 90),
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = at(-0.6, 3.0, -0.6),
			color = rgb(255, 230, 90),
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = at(-1.8, 3.0, -0.6),
			color = rgb(255, 230, 90),
			material = NEON,
		},
		{
			shape = "Block",
			size = Vector3.new(5.8, 0.6, 0.6),
			cframe = at(0, -0.1, -4.4),
			color = rgb(80, 80, 90),
			material = METAL,
		}, -- bumper
		{
			shape = "Block",
			size = Vector3.new(1.0, 1.0, 5.5),
			cframe = at(0, -0.7, 0),
			color = rgb(60, 60, 65),
			material = METAL,
		}, -- axle frame
		{
			shape = "Block",
			size = Vector3.new(0.4, 0.4, 0.4),
			cframe = at(2.2, 0.8, -4.25),
			color = WHITE,
			material = NEON,
		},
		{
			shape = "Block",
			size = Vector3.new(0.4, 0.4, 0.4),
			cframe = at(-2.2, 0.8, -4.25),
			color = WHITE,
			material = NEON,
		},
	}
	wheels(s, h, 1.75, 1.4, { inset = 0.2, color = rgb(25, 25, 25), hubColor = rgb(255, 200, 40) })
	return s
end

designs.ufo = function(h)
	local silver = rgb(190, 200, 215)
	local lime = rgb(120, 255, 80)
	local s: { PartSpec } = {
		{
			shape = "Cylinder",
			size = Vector3.new(0.9, 7.2, 7.2),
			cframe = at(0, -0.2, 0) * CYL_ALONG_Y,
			color = silver,
			material = METAL,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.5, 5.2, 5.2),
			cframe = at(0, -0.8, 0) * CYL_ALONG_Y,
			color = rgb(120, 130, 150),
			material = METAL,
		},
		{
			shape = "Cylinder",
			size = Vector3.new(0.3, 7.5, 7.5),
			cframe = at(0, -0.2, 0) * CYL_ALONG_Y,
			color = lime,
			material = NEON,
		},
		{
			shape = "Ball",
			size = Vector3.new(3.8, 3.8, 3.8),
			cframe = at(0, 0.5, 0.2),
			color = rgb(170, 240, 255),
			material = GLASS,
			transparency = 0.45,
		},
		{ shape = "Ball", size = Vector3.new(1.5, 1.5, 1.5), cframe = at(0, 0.8, 0.2), color = rgb(110, 220, 90) }, -- alien
		{ shape = "Ball", size = Vector3.new(0.45, 0.6, 0.3), cframe = at(0.35, 1.0, -0.5), color = BLACK },
		{ shape = "Ball", size = Vector3.new(0.45, 0.6, 0.3), cframe = at(-0.35, 1.0, -0.5), color = BLACK },
		{
			shape = "Cylinder",
			size = Vector3.new(1.0, 0.12, 0.12),
			cframe = at(0.3, 1.9, 0.2) * CYL_ALONG_Y,
			color = rgb(110, 220, 90),
		},
		{
			shape = "Ball",
			size = Vector3.new(0.35, 0.35, 0.35),
			cframe = at(0.3, 2.4, 0.2),
			color = lime,
			material = NEON,
		},
	}
	for i = 0, 7 do
		local angle = i * math.pi / 4
		table.insert(s, {
			shape = "Ball",
			size = Vector3.new(0.6, 0.6, 0.6),
			cframe = at(math.sin(angle) * 3.3, 0.1, math.cos(angle) * 3.3),
			color = if i % 2 == 0 then rgb(255, 90, 200) else rgb(90, 200, 255),
			material = NEON,
		})
	end
	-- glowing hover pads instead of wheels
	local floor = groundY(h)
	for _, x in { -2.2, 2.2 } do
		for _, z in { -2.4, 2.4 } do
			table.insert(s, {
				shape = "Cylinder",
				size = Vector3.new(0.4, 1.4, 1.4),
				cframe = at(x, floor + 0.5, z) * CYL_ALONG_Y,
				color = lime,
				material = NEON,
			})
		end
	end
	return s
end

local function makePart(spec: PartSpec): BasePart
	local part: BasePart
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if spec.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif spec.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end
	part.Name = spec.name or "Body"
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color
	part.Material = spec.material or SMOOTH
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

-- Builds a car model positioned at the origin. Move it with model:PivotTo(cframe).
function CarModelBuilder.build(def: CarDef, options: BuildOptions?): Model
	local opts: BuildOptions = options or ({} :: BuildOptions)
	local hitbox = def.Hitbox
	local model = Instance.new("Model")
	model.Name = def.DisplayName

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

	local build = designs[def.Id] or designs.pizza
	local specs = build(hitbox)

	-- Team underglow and antenna so teams are easy to tell apart from anywhere on the field.
	local teamColor = opts.teamColor or rgb(230, 230, 230)
	local floor = groundY(hitbox)
	table.insert(specs, {
		shape = "Block",
		size = Vector3.new(hitbox.X - 1.4, 0.15, hitbox.Z - 1.8),
		cframe = at(0, floor + 0.35, 0),
		color = teamColor,
		material = NEON,
		transparency = 0.15,
		name = "TeamGlow",
	})
	table.insert(specs, {
		shape = "Cylinder",
		size = Vector3.new(2.6, 0.12, 0.12),
		cframe = at(hitbox.X / 2 - 0.9, hitbox.Y / 2 + 1.3, hitbox.Z / 2 - 1.0) * CYL_ALONG_Y,
		color = BLACK,
		name = "Antenna",
	})
	table.insert(specs, {
		shape = "Ball",
		size = Vector3.new(0.7, 0.7, 0.7),
		cframe = at(hitbox.X / 2 - 0.9, hitbox.Y / 2 + 2.65, hitbox.Z / 2 - 1.0),
		color = teamColor,
		material = NEON,
		name = "TeamFlag",
	})

	for _, spec in specs do
		local part = makePart(spec)
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

	-- Boost flames come out of the back.
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(0, -0.2, hitbox.Z / 2 + 0.2)
	exhaust.Parent = chassis

	local flames = Instance.new("ParticleEmitter")
	flames.Name = "BoostFlames"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(rgb(255, 240, 120), rgb(255, 90, 20))
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
	local megaGlow = Instance.new("ParticleEmitter")
	megaGlow.Name = "MegaGlow"
	megaGlow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	megaGlow.Color = ColorSequence.new(rgb(255, 200, 60), rgb(255, 60, 20))
	megaGlow.LightEmission = 1
	megaGlow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	megaGlow.Lifetime = NumberRange.new(0.4, 0.7)
	megaGlow.Rate = 40
	megaGlow.Speed = NumberRange.new(2, 5)
	megaGlow.SpreadAngle = Vector2.new(180, 180)
	megaGlow.Enabled = false
	megaGlow.Parent = chassis

	return model
end

return CarModelBuilder
