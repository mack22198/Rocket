--!strict
-- Builds each car's 3D model out of plain parts (no uploaded assets needed), at any of its evolution stages.
-- Every car is an invisible physics box called "Chassis" (the hitbox) with decorative parts welded on.
-- The same builder makes the cars in the menu showroom, the garage previews and the VIP lounge.
--
-- Car space: the car faces -Z, +Y is up, the chassis centre is the origin.
--
-- The cars are sporty "battle cars": chunky wheels with spoked rims under flared arches, a low glasshouse,
-- light bars and spoilers - each dressed in its own theme (a pizza delivery hot hatch, a banana roadster, a
-- go-kart, a shark supercar, a monster truck, a flying saucer, a taco truck, a rubber duck and a hot dog).
-- Fused cars are built from their base car's design, repainted, with a piece of the other car added on.
--
-- Parts are coloured by role ("body", "accent", ...) so each evolution stage can repaint the whole car:
-- stages 1 and 2 use the car's own colours, stage 3 turns every car into glowing lava and stage 4 into
-- deep space. Evolving is only for looks; it never changes how a car drives.
--
-- Smooth bodies: once the Blender meshes (see CarMeshes and tools/meshes) have been imported into the place,
-- each car's blocky shell parts are swapped for smooth MeshParts, painted by role in exactly the same way.

local CarCatalog = require(script.Parent.Parent.Config.CarCatalog)
local CarMeshes = require(script.Parent.CarMeshes)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MeshLibrary = require(script.Parent.Parent.Build.MeshLibrary)

type CarDef = CarCatalog.CarDef

export type BuildOptions = {
	teamColor: Color3?, -- underglow, antenna and team light colour (nil = neutral, for previews)
	preview: boolean?, -- true = no physics setup (showroom and garage)
	stage: number?, -- evolution stage, 1 (as unlocked) to GameConfig.Evolution.Stages
	topper: string?, -- a hat on the roof (see Cosmetics)
}

type Shape = "Block" | "Wedge" | "Cylinder" | "Ball" | "Ellipsoid" | "Mesh"

type Look = { color: Color3, material: Enum.Material?, transparency: number?, reflectance: number? }

type Roles = { [string]: Look }

type PartSpec = {
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	role: string,
	name: string?,
	text: string?, -- painted on the part (a badge on a door, a sign)
	look: Look?, -- a fixed look instead of the role's (hats keep their colours at every stage)
	mesh: string?, -- for "Mesh": which imported mesh to copy (see MeshLibrary)
}

-- Adds one part to the car being built.
type Add = (role: string, shape: Shape, size: Vector3, cframe: CFrame, name: string?, text: string?) -> ()

type Design = {
	roles: { Roles }, -- the car's own colours at stage 1 and stage 2
	antenna: Vector3, -- where the team antenna sticks out of the body
	topper: (h: Vector3) -> Vector3, -- where a hat sits (the middle of its brim)
	build: (h: Vector3, stage: number, add: Add) -> (),
}

-- The side profile of a car body, as heights (y) and positions along the car (z). See `coupe`.
type Profile = {
	width: number,
	bottom: number, -- underside
	nose: number, -- top of the front bumper (the bonnet rises from here)
	belt: number, -- where the windows start
	tail: number, -- top of the back edge
	roof: number,
	front: number, -- z of the front bumper
	back: number, -- z of the rear bumper
	screen: number, -- z where the windscreen starts
	roofFront: number,
	roofBack: number,
	deck: number, -- z where the rear window meets the boot
	cabin: number, -- width of the glasshouse
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
	dark = look(rgb(30, 31, 38)),
	trim = look(rgb(58, 60, 72), METAL),
	white = look(rgb(248, 248, 250)),
	glass = look(rgb(24, 32, 50), GLASS, 0.1, 0.3),
	cabin = look(rgb(16, 17, 22)),
	lamp = look(rgb(255, 250, 226), NEON),
	tail = look(rgb(255, 44, 40), NEON),
	tire = look(rgb(34, 34, 40)),
	sidewall = look(rgb(58, 58, 66)),
	rim = look(rgb(222, 226, 236), METAL),
	metal = look(rgb(186, 190, 202), METAL),
}

-- Stage 3 and 4 repaint every car with the same theme.
local THEMES: { [number]: Roles } = {
	[3] = { -- Lava: cooled black rock with molten orange glowing through
		body = look(rgb(64, 42, 38), Enum.Material.Slate),
		body2 = look(rgb(40, 28, 26), Enum.Material.Basalt),
		accent = look(rgb(255, 104, 26), NEON),
		stripe = look(rgb(255, 140, 40), NEON),
		light = look(rgb(255, 168, 56), NEON),
		leaf = look(rgb(255, 120, 40), NEON),
		skin = look(rgb(255, 150, 60), NEON),
		mouth = look(rgb(44, 22, 16)),
		dark = look(rgb(28, 20, 18)),
		trim = look(rgb(80, 52, 42), METAL),
		white = look(rgb(255, 196, 120)),
		glass = look(rgb(120, 50, 20), GLASS, 0.2, 0.2),
		lamp = look(rgb(255, 214, 140), NEON),
		tail = look(rgb(255, 60, 20), NEON),
		tire = look(rgb(30, 22, 20)),
		sidewall = look(rgb(56, 36, 30)),
		rim = look(rgb(255, 118, 40), NEON),
		metal = look(rgb(96, 64, 54), METAL),
	},
	[4] = { -- Galaxy: deep space purple with starlight trim
		body = look(rgb(50, 32, 120), SMOOTH, 0, 0.14),
		body2 = look(rgb(108, 60, 200), SMOOTH, 0, 0.12),
		accent = look(rgb(90, 232, 255), NEON),
		stripe = look(rgb(255, 128, 228), NEON),
		light = look(rgb(255, 128, 228), NEON),
		leaf = look(rgb(90, 232, 255), NEON),
		skin = look(rgb(150, 255, 220), NEON),
		mouth = look(rgb(24, 14, 56)),
		dark = look(rgb(20, 14, 48)),
		trim = look(rgb(80, 60, 160), METAL),
		white = look(rgb(214, 236, 255)),
		glass = look(rgb(60, 90, 200), GLASS, 0.2, 0.25),
		lamp = look(rgb(214, 250, 255), NEON),
		tail = look(rgb(255, 110, 220), NEON),
		tire = look(rgb(26, 18, 52)),
		sidewall = look(rgb(50, 36, 100)),
		rim = look(rgb(90, 232, 255), NEON),
		metal = look(rgb(150, 132, 222), METAL),
	},
}

-- Distance from the chassis centre down to the ground when the car rests on its suspension.
local function groundY(hitbox: Vector3): number
	local sag = GameConfig.Car.Gravity / GameConfig.Car.SpringStrength
	return -hitbox.Y / 2 - (GameConfig.Car.RideHeight - sag)
end

---------------------------------------------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------------------------------------------

-- The size and centre of the box between two corners (given in any order).
local function span(a: Vector3, b: Vector3): (Vector3, CFrame)
	local low = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local high = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return high - low, CFrame.new((low + high) / 2)
end

local function box(add: Add, role: string, a: Vector3, b: Vector3, name: string?)
	local size, cframe = span(a, b)
	add(role, "Block", size, cframe, name)
end

-- A wedge filling the box from a to b, its slope rising towards the back (+Z) - like a bonnet.
local function rampUp(add: Add, role: string, a: Vector3, b: Vector3, name: string?)
	local size, cframe = span(a, b)
	add(role, "Wedge", size, cframe, name)
end

-- A wedge whose slope rises towards the front (-Z) - like a boot lid or a rear window.
local function rampDown(add: Add, role: string, a: Vector3, b: Vector3, name: string?)
	local size, cframe = span(a, b)
	add(role, "Wedge", size, cframe * CFrame.Angles(0, math.pi, 0), name)
end

-- A thin strip lying on a slope that runs from (y0, z0) to (y1, z1), raised `lift` studs off it. Used for
-- racing stripes and window pillars.
local function strip(
	add: Add,
	role: string,
	x: number,
	width: number,
	y0: number,
	z0: number,
	y1: number,
	z1: number,
	lift: number,
	name: string?
)
	local run, rise = z1 - z0, y1 - y0
	local angle = math.atan2(rise, run)
	local centre = Vector3.new(x, (y0 + y1) / 2 + math.cos(angle) * lift, (z0 + z1) / 2 - math.sin(angle) * lift)
	add(
		role,
		"Block",
		Vector3.new(width, 0.06, math.sqrt(run * run + rise * rise)),
		CFrame.new(centre) * CFrame.Angles(-angle, 0, 0),
		name
	)
end

-- A flared wheel arch over the top of a wheel: a curved band of short blocks, seen from the side.
local function arch(add: Add, role: string, centre: Vector3, radius: number, thickness: number, x0: number, x1: number)
	local segments = 7
	local from, to = math.rad(-80), math.rad(80)
	local step = (to - from) / segments
	local length = 2 * (radius + thickness / 2) * math.tan(step / 2) + 0.05
	for i = 0, segments - 1 do
		local a = from + (i + 0.5) * step
		local position = Vector3.new((x0 + x1) / 2, centre.Y + math.cos(a) * radius, centre.Z + math.sin(a) * radius)
		add(
			role,
			"Block",
			Vector3.new(math.abs(x1 - x0), thickness, length),
			CFrame.new(position) * CFrame.Angles(a, 0, 0),
			"Arch"
		)
	end
end

-- A wheel: tyre, sidewall, a rim with a dark dish, spokes and a hub cap (and chunky treads if asked).
local function wheel(
	add: Add,
	centre: Vector3,
	side: number,
	radius: number,
	width: number,
	spokes: number,
	treads: boolean?
)
	local c = CFrame.new(centre)
	local face = side * width / 2
	add("tire", "Cylinder", Vector3.new(width, radius * 2, radius * 2), c, "Wheel")
	add(
		"sidewall",
		"Cylinder",
		Vector3.new(0.05, radius * 1.7, radius * 1.7),
		c * CFrame.new(face + side * 0.02, 0, 0),
		"Sidewall"
	)
	add(
		"rim",
		"Cylinder",
		Vector3.new(0.1, radius * 1.32, radius * 1.32),
		c * CFrame.new(face + side * 0.05, 0, 0),
		"Rim"
	)
	add(
		"dark",
		"Cylinder",
		Vector3.new(0.1, radius * 1.1, radius * 1.1),
		c * CFrame.new(face + side * 0.08, 0, 0),
		"RimDish"
	)
	for k = 0, spokes - 1 do
		local angle = k / spokes * math.pi * 2
		add(
			"rim",
			"Block",
			Vector3.new(0.1, radius * 0.2, radius * 0.5),
			c * CFrame.new(face + side * 0.12, 0, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, radius * 0.3),
			"Spoke"
		)
	end
	add(
		"metal",
		"Cylinder",
		Vector3.new(0.16, radius * 0.36, radius * 0.36),
		c * CFrame.new(face + side * 0.15, 0, 0),
		"HubCap"
	)
	if treads then
		for k = 0, 11 do
			add(
				"tire",
				"Block",
				Vector3.new(width + 0.08, radius * 0.22, radius * 0.3),
				c * CFrame.Angles(k * math.pi / 6, 0, 0) * CFrame.new(0, radius - 0.02, 0),
				"Tread"
			)
		end
	end
end

-- A dark wheel well painted on the body behind a wheel, so the arch looks hollow.
local function wheelWell(add: Add, centre: Vector3, radius: number, x: number)
	add("dark", "Cylinder", Vector3.new(0.04, radius * 2, radius * 2), CFrame.new(x, centre.Y, centre.Z), "WheelWell")
end

-- Four wheels at the given axles, each under a flared arch (unless `open`, like a go-kart).
type WheelSet = {
	g: number, -- ground height
	x: number, -- body half-width (the tyres start just inside it)
	front: number,
	rear: number,
	radius: number,
	rearRadius: number?,
	width: number,
	rearWidth: number?,
	spokes: number,
	archRole: string?,
	open: boolean?,
	treads: boolean?,
	inset: number?, -- how far the tyre's inner face sits inside the body
}

local function wheelSet(add: Add, w: WheelSet)
	for _, z in { w.front, w.rear } do
		local rear = z == w.rear
		local r = if rear then (w.rearRadius or w.radius) else w.radius
		local width = if rear then (w.rearWidth or w.width) else w.width
		local inner = w.x - (w.inset or 0.25)
		for _, side in { -1, 1 } do
			local centre = Vector3.new(side * (inner + width / 2), w.g + r, z)
			wheel(add, centre, side, r, width, w.spokes, w.treads)
			if not w.open then
				arch(
					add,
					w.archRole or "body",
					centre,
					r + 0.24,
					0.44,
					side * (inner - 0.1),
					side * (inner + width + 0.12)
				)
				wheelWell(add, centre, r + 0.12, side * (w.x + 0.02))
			end
		end
	end
end

-- The main shell of a car: a lower body (in body2), a bonnet rising to the windscreen, the doors, a boot (or a
-- ducktail, if the tail sits higher than the windows), and a tinted glasshouse with a painted roof and pillars.
local function coupe(add: Add, p: Profile)
	local hw = p.width / 2
	box(add, "body2", Vector3.new(-hw, p.bottom, p.front), Vector3.new(hw, p.nose, p.back), "LowerBody")
	rampUp(add, "body", Vector3.new(-hw, p.nose, p.front), Vector3.new(hw, p.belt, p.screen), "Bonnet")
	box(add, "body", Vector3.new(-hw, p.nose, p.screen), Vector3.new(hw, p.belt, p.deck), "Doors")
	if p.tail < p.belt - 0.01 then
		box(add, "body", Vector3.new(-hw, p.nose, p.deck), Vector3.new(hw, p.tail, p.back), "RearBody")
		rampDown(add, "body", Vector3.new(-hw, p.tail, p.deck), Vector3.new(hw, p.belt, p.back), "Boot")
	else
		box(add, "body", Vector3.new(-hw, p.nose, p.deck), Vector3.new(hw, p.belt, p.back), "RearBody")
		if p.tail > p.belt + 0.01 then
			rampUp(add, "body", Vector3.new(-hw, p.belt, p.deck), Vector3.new(hw, p.tail, p.back), "Ducktail")
		end
	end

	local cw = p.cabin / 2
	-- A dark interior behind the tinted glass (seats and all, as far as anyone can tell).
	box(
		add,
		"cabin",
		Vector3.new(-cw + 0.25, p.belt - 0.05, p.roofFront - 0.3),
		Vector3.new(cw - 0.25, p.roof - 0.35, p.roofBack + 0.2),
		"Interior"
	)
	rampUp(add, "glass", Vector3.new(-cw, p.belt, p.screen), Vector3.new(cw, p.roof, p.roofFront), "Windscreen")
	box(
		add,
		"glass",
		Vector3.new(-cw + 0.02, p.belt, p.roofFront),
		Vector3.new(cw - 0.02, p.roof - 0.1, p.roofBack),
		"Windows"
	)
	rampDown(add, "glass", Vector3.new(-cw, p.belt, p.roofBack), Vector3.new(cw, p.roof, p.deck), "RearWindow")
	box(
		add,
		"body",
		Vector3.new(-cw - 0.05, p.roof - 0.14, p.roofFront - 0.08),
		Vector3.new(cw + 0.05, p.roof + 0.04, p.roofBack + 0.08),
		"Roof"
	)
	for _, side in { -1, 1 } do
		local x = side * (cw + 0.02)
		strip(add, "body", x, 0.14, p.belt, p.screen, p.roof, p.roofFront, 0.02, "APillar")
		strip(add, "body", x, 0.14, p.roof, p.roofBack, p.belt, p.deck, 0.02, "CPillar")
		box(
			add,
			"body",
			Vector3.new(x - 0.07, p.belt, p.roofBack - 0.35),
			Vector3.new(x + 0.07, p.roof, p.roofBack - 0.05),
			"BPillar"
		)
		-- Chrome along the bottom of the side windows, and the door shut lines.
		box(
			add,
			"trim",
			Vector3.new(x - side * 0.04, p.belt - 0.02, p.roofFront - 0.2),
			Vector3.new(x + side * 0.08, p.belt + 0.06, p.roofBack + 0.1),
			"WindowTrim"
		)
		for _, z in { p.screen + 0.25, p.roofBack - 0.2 } do
			box(
				add,
				"dark",
				Vector3.new(side * (hw - 0.02), p.nose + 0.1, z - 0.03),
				Vector3.new(side * (hw + 0.02), p.belt - 0.05, z + 0.03),
				"DoorLine"
			)
		end
		-- A dark sill along the bottom of each side, between the arches.
		box(
			add,
			"dark",
			Vector3.new(side * (hw - 0.05), p.bottom, p.front + 2.4),
			Vector3.new(side * (hw + 0.12), p.bottom + 0.32, p.back - 2.4),
			"SideSkirt"
		)
	end
end

-- Racing stripes along the top of a coupe (over the bonnet, roof and boot).
local function stripes(add: Add, p: Profile, role: string, offset: number, width: number)
	local xs: { number } = if offset > 0 then { -offset, offset } else { 0 }
	for _, x in xs do
		strip(add, role, x, width, p.nose, p.front, p.belt, p.screen, 0.035, "Stripe")
		box(
			add,
			role,
			Vector3.new(x - width / 2, p.roof + 0.04, p.roofFront - 0.06),
			Vector3.new(x + width / 2, p.roof + 0.08, p.roofBack + 0.06),
			"Stripe"
		)
		if p.tail < p.belt - 0.01 then
			strip(add, role, x, width, p.belt, p.deck, p.tail, p.back, 0.035, "Stripe")
		end
	end
end

-- Headlights in chrome bezels on the front face, at height y, their centres `x` from the middle.
local function headlights(add: Add, x: number, y: number, z: number, width: number, height: number)
	for _, side in { -1, 1 } do
		box(
			add,
			"trim",
			Vector3.new(side * x - width / 2 - 0.08, y - height / 2 - 0.08, z + 0.02),
			Vector3.new(side * x + width / 2 + 0.08, y + height / 2 + 0.08, z + 0.14),
			"LightBezel"
		)
		box(
			add,
			"lamp",
			Vector3.new(side * x - width / 2, y - height / 2, z - 0.04),
			Vector3.new(side * x + width / 2, y + height / 2, z + 0.06),
			"Headlight"
		)
	end
end

-- Red tail lights on the back face, joined by a thin light bar.
local function taillights(add: Add, x: number, y: number, z: number, width: number, height: number)
	for _, side in { -1, 1 } do
		box(
			add,
			"tail",
			Vector3.new(side * x - width / 2, y - height / 2, z - 0.06),
			Vector3.new(side * x + width / 2, y + height / 2, z + 0.06),
			"TailLight"
		)
	end
	box(
		add,
		"tail",
		Vector3.new(-x + width / 2, y - 0.05, z - 0.03),
		Vector3.new(x - width / 2, y + 0.05, z + 0.04),
		"LightBar"
	)
end

-- A rear wing on two struts, with endplates and a team-coloured light along its edge.
local function wing(add: Add, role: string, width: number, depth: number, y: number, z: number, strutFrom: number)
	for _, side in { -1, 1 } do
		box(
			add,
			"dark",
			Vector3.new(side * width * 0.3 - 0.09, strutFrom, z - 0.15),
			Vector3.new(side * width * 0.3 + 0.09, y, z + 0.15),
			"WingStrut"
		)
		box(
			add,
			role,
			Vector3.new(side * width / 2 - 0.08, y - 0.35, z - depth / 2 - 0.05),
			Vector3.new(side * width / 2 + 0.02, y + 0.25, z + depth / 2 + 0.05),
			"Endplate"
		)
	end
	add(role, "Block", Vector3.new(width, 0.14, depth), at(0, y + 0.05, z) * CFrame.Angles(math.rad(-7), 0, 0), "Wing")
	box(
		add,
		"team",
		Vector3.new(-width / 2 + 0.1, y + 0.1, z + depth / 2 - 0.02),
		Vector3.new(width / 2 - 0.1, y + 0.2, z + depth / 2 + 0.06),
		"TeamLight"
	)
end

local function exhausts(add: Add, x: number, y: number, z: number, size: number)
	for _, side in { -1, 1 } do
		add("metal", "Cylinder", Vector3.new(0.7, size, size), at(side * x, y, z) * CYL_ALONG_Z, "ExhaustPipe")
		add(
			"dark",
			"Cylinder",
			Vector3.new(0.72, size * 0.62, size * 0.62),
			at(side * x, y, z) * CYL_ALONG_Z,
			"ExhaustHole"
		)
	end
end

local function mirrors(add: Add, x: number, y: number, z: number)
	for _, side in { -1, 1 } do
		box(
			add,
			"dark",
			Vector3.new(side * x, y - 0.06, z - 0.05),
			Vector3.new(side * (x + 0.3), y + 0.02, z + 0.05),
			"MirrorArm"
		)
		box(
			add,
			"body",
			Vector3.new(side * (x + 0.22), y - 0.14, z - 0.2),
			Vector3.new(side * (x + 0.55), y + 0.14, z + 0.2),
			"Mirror"
		)
	end
end

-- Round badges on both doors, with the car's emoji painted on.
local function badges(add: Add, x: number, y: number, z: number, size: number, text: string)
	for _, side in { -1, 1 } do
		add("white", "Cylinder", Vector3.new(0.06, size, size), at(side * x, y, z), "Badge", text)
	end
end

---------------------------------------------------------------------------------------------------------------
-- The cars
---------------------------------------------------------------------------------------------------------------

local designs: { [string]: Design } = {}

-- A pizza delivery hot hatch: tomato red over a golden crust, melted-cheese stripes and a pizza box on the roof.
designs.pizza = {
	roles = {
		{
			body = look(rgb(214, 44, 36)),
			body2 = look(rgb(240, 176, 64)),
			accent = look(rgb(255, 218, 92)),
			stripe = look(rgb(255, 218, 92)),
			light = look(rgb(250, 246, 236)),
		},
		{ -- Burnt: a little too long in the oven
			body = look(rgb(74, 40, 30)),
			body2 = look(rgb(44, 30, 26)),
			accent = look(rgb(255, 118, 36), NEON),
			stripe = look(rgb(255, 118, 36), NEON),
			light = look(rgb(214, 180, 130)),
			rim = look(rgb(255, 176, 60), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 1.94, 1.55) -- on the pizza box
	end,
	antenna = Vector3.new(1.55, 1.5, 2.05),
	build = function(h, stage, add)
		local g = groundY(h)
		local p: Profile = {
			width = 4.6,
			bottom = g + 0.55,
			nose = -0.3,
			belt = 0.35,
			tail = 0.15,
			roof = 1.5,
			front = -4.3,
			back = 4.25,
			screen = -1.2,
			roofFront = 0.15,
			roofBack = 2.35,
			deck = 3.35,
			cabin = 3.8,
		}
		coupe(add, p)
		stripes(add, p, "stripe", 0.55, 0.5)
		wheelSet(add, { g = g, x = 2.3, front = -2.65, rear = 2.65, radius = 1.05, width = 0.95, spokes = 5 })
		-- Face: grille, headlights and a chin splitter.
		box(
			add,
			"dark",
			Vector3.new(-1.1, p.bottom + 0.3, p.front - 0.05),
			Vector3.new(1.1, p.nose - 0.12, p.front + 0.1),
			"Grille"
		)
		for k = 0, 2 do
			local y = p.bottom + 0.42 + k * 0.2
			box(
				add,
				"trim",
				Vector3.new(-1.05, y - 0.03, p.front - 0.09),
				Vector3.new(1.05, y + 0.03, p.front - 0.03),
				"GrilleBar"
			)
		end
		headlights(add, 1.6, p.nose - 0.27, p.front, 0.85, 0.3)
		box(
			add,
			"dark",
			Vector3.new(-2.4, p.bottom - 0.05, p.front - 0.3),
			Vector3.new(2.4, p.bottom + 0.12, p.front + 0.6),
			"Splitter"
		)
		-- Back: tail lights, a diffuser and twin exhausts.
		taillights(add, 1.65, p.tail - 0.25, p.back, 0.8, 0.3)
		box(
			add,
			"dark",
			Vector3.new(-1.6, p.bottom - 0.02, p.back - 0.5),
			Vector3.new(1.6, p.bottom + 0.35, p.back + 0.12),
			"Diffuser"
		)
		exhausts(add, 0.6, p.bottom + 0.2, p.back + 0.2, 0.42)
		mirrors(add, 1.9, p.belt + 0.15, p.screen + 0.45)
		badges(add, 2.33, (p.nose + p.belt) / 2 + 0.05, -0.2, 1.35, "🍕")
		-- The pizza box and its sign on the roof.
		box(add, "light", Vector3.new(-1.05, p.roof + 0.04, 0.55), Vector3.new(1.05, p.roof + 0.44, 2.05), "PizzaBox")
		box(add, "body", Vector3.new(-1.07, p.roof + 0.3, 0.53), Vector3.new(1.07, p.roof + 0.36, 2.07), "BoxStripe")
		add("light", "Block", Vector3.new(2.3, 0.75, 0.16), at(0, p.roof + 0.82, 0.62), "RoofSign", "🍕 PIZZA")
		-- A roof spoiler once it's been in the oven a while.
		if stage >= 2 then
			add(
				"body",
				"Block",
				Vector3.new(3.9, 0.12, 0.8),
				at(0, p.roof - 0.02, p.roofBack + 0.4) * CFrame.Angles(math.rad(8), 0, 0),
				"RoofSpoiler"
			)
		end
		box(
			add,
			"team",
			Vector3.new(-1.7, p.roof - 0.1, p.roofBack + 0.02),
			Vector3.new(1.7, p.roof - 0.02, p.roofBack + 0.12),
			"TeamLight"
		)
	end,
}

-- A banana roadster: long and low, curving up at the back like a banana, a brown tip at the front and a leafy
-- stem holding up the wing.
designs.banana = {
	roles = {
		{
			body = look(rgb(255, 216, 56)),
			body2 = look(rgb(226, 186, 36)),
			accent = look(rgb(104, 70, 34)),
			stripe = look(rgb(255, 244, 206)),
			light = look(rgb(255, 244, 206)),
			leaf = look(rgb(118, 168, 54)),
		},
		{ -- Ripe: sweeter and spottier
			body = look(rgb(250, 196, 36)),
			body2 = look(rgb(214, 158, 28)),
			accent = look(rgb(82, 50, 22)),
			stripe = look(rgb(255, 236, 180)),
			light = look(rgb(255, 236, 180)),
			leaf = look(rgb(96, 142, 44)),
			rim = look(rgb(255, 214, 90), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 1.19, 1.05)
	end,
	antenna = Vector3.new(1.35, 1.05, 1.9),
	build = function(h, stage, add)
		local g = groundY(h)
		local p: Profile = {
			width = 4.3,
			bottom = g + 0.5,
			nose = -0.6,
			belt = 0.1,
			tail = 0.4,
			roof = 1.15,
			front = -4.45,
			back = 4.45,
			screen = -0.55,
			roofFront = 0.55,
			roofBack = 1.55,
			deck = 3.1,
			cabin = 3.4,
		}
		coupe(add, p)
		stripes(add, p, "stripe", 0, 0.8)
		wheelSet(add, { g = g, x = 2.15, front = -2.85, rear = 2.85, radius = 1.0, width = 0.9, spokes = 6 })
		-- The dark tip of the banana, as a nose cone.
		add("accent", "Ellipsoid", Vector3.new(1.3, 0.75, 1.2), at(0, p.nose + 0.05, p.front - 0.25), "Tip")
		box(
			add,
			"dark",
			Vector3.new(-1.3, p.bottom + 0.25, p.front - 0.05),
			Vector3.new(1.3, p.nose - 0.18, p.front + 0.08),
			"Grille"
		)
		headlights(add, 1.45, p.nose - 0.22, p.front, 0.9, 0.22)
		box(
			add,
			"dark",
			Vector3.new(-2.2, p.bottom - 0.05, p.front - 0.25),
			Vector3.new(2.2, p.bottom + 0.1, p.front + 0.5),
			"Splitter"
		)
		taillights(add, 1.5, p.belt - 0.1, p.back, 0.9, 0.24)
		exhausts(add, 0.5, p.bottom + 0.2, p.back + 0.2, 0.36)
		mirrors(add, 1.72, p.belt + 0.14, p.screen + 0.4)
		badges(add, 2.18, (p.nose + p.belt) / 2, -0.4, 1.2, "🍌")
		-- Brown spots (more of them once it's ripe).
		local spots = { Vector2.new(0.05, -2.0), Vector2.new(-0.3, 1.2), Vector2.new(-0.05, 2.6) }
		if stage == 2 then
			table.insert(spots, Vector2.new(-0.35, -1.1))
			table.insert(spots, Vector2.new(0.0, 0.6))
			table.insert(spots, Vector2.new(-0.25, 3.5))
		end
		for _, spot in spots do
			for _, side in { -1, 1 } do
				add("accent", "Cylinder", Vector3.new(0.05, 0.42, 0.42), at(side * 2.16, spot.X, spot.Y), "Spot")
			end
		end
		-- The stem at the back holds up a leaf-shaped wing.
		local stem = at(0, p.tail + 0.45, p.back - 0.55) * CFrame.Angles(math.rad(-35), 0, 0)
		add("leaf", "Cylinder", Vector3.new(1.3, 0.45, 0.45), stem * CYL_ALONG_Z, "Stem")
		add(
			"leaf",
			"Ellipsoid",
			Vector3.new(4.2, 0.22, 1.25),
			at(0, p.tail + 0.95, p.back - 0.35) * CFrame.Angles(math.rad(-6), 0, 0),
			"LeafWing"
		)
		box(
			add,
			"team",
			Vector3.new(-1.6, p.tail + 1.0, p.back + 0.15),
			Vector3.new(1.6, p.tail + 1.08, p.back + 0.25),
			"TeamLight"
		)
		if stage >= 2 then
			for _, side in { -1, 1 } do
				add(
					"leaf",
					"Ellipsoid",
					Vector3.new(0.2, 0.9, 1.4),
					at(side * 1.95, p.tail + 0.75, p.back - 0.4),
					"LeafFin"
				)
			end
		end
	end,
}

-- An open-wheel go-kart: a low tub, side pods, the driver in a helmet, and a big rear wing.
designs.kart = {
	roles = {
		{
			body = look(rgb(52, 204, 96)),
			body2 = look(rgb(28, 128, 62)),
			accent = look(rgb(236, 60, 56)), -- racing suit
			light = look(rgb(248, 248, 250)),
			glass = look(rgb(20, 30, 50), GLASS, 0.05, 0.4),
		},
		{ -- Turbo: gold trim and racing stripes
			body = look(rgb(30, 214, 124)),
			body2 = look(rgb(18, 110, 72)),
			accent = look(rgb(255, 196, 40)),
			light = look(rgb(255, 255, 255)),
			glass = look(rgb(20, 30, 50), GLASS, 0.05, 0.4),
			rim = look(rgb(255, 200, 48), METAL),
		},
	},
	topper = function(h)
		return Vector3.new(0, groundY(h) + 3.0, 0.6) -- on the driver's helmet
	end,
	antenna = Vector3.new(0.9, 0.5, 2.3),
	build = function(h, stage, add)
		local g = groundY(h)
		local floor = g + 0.3
		wheelSet(add, {
			g = g,
			x = 1.75,
			front = -2.45,
			rear = 2.35,
			radius = 0.82,
			rearRadius = 1.05,
			width = 0.85,
			rearWidth = 1.2,
			spokes = 4,
			open = true,
			inset = 0,
		})
		box(add, "dark", Vector3.new(-1.45, floor, -3.3), Vector3.new(1.45, floor + 0.28, 3.3), "Floor")
		-- Nose cone with a number disc, and a front wing.
		box(add, "body", Vector3.new(-0.85, floor + 0.28, -3.35), Vector3.new(0.85, floor + 0.75, -0.9), "Nose")
		rampUp(add, "body", Vector3.new(-0.85, floor + 0.75, -3.35), Vector3.new(0.85, floor + 1.25, -0.9), "NoseTop")
		add("body", "Ellipsoid", Vector3.new(1.7, 0.55, 0.9), at(0, floor + 0.52, -3.4), "NoseTip")
		box(add, "body2", Vector3.new(-2.35, floor + 0.05, -3.95), Vector3.new(2.35, floor + 0.18, -3.4), "FrontWing")
		for _, side in { -1, 1 } do
			box(
				add,
				"body2",
				Vector3.new(side * 2.35 - 0.06, floor + 0.05, -4.0),
				Vector3.new(side * 2.35 + 0.06, floor + 0.55, -3.35),
				"WingEnd"
			)
		end
		add("metal", "Cylinder", Vector3.new(3.6, 0.32, 0.32), at(0, floor + 0.2, 3.75), "Bumper")
		-- Side pods with stripes and number badges.
		for _, side in { -1, 1 } do
			box(
				add,
				"body",
				Vector3.new(side * 0.95, floor + 0.28, -0.75),
				Vector3.new(side * 1.55, floor + 1.05, 1.55),
				"SidePod"
			)
			rampDown(
				add,
				"body",
				Vector3.new(side * 0.95, floor + 0.28, -1.45),
				Vector3.new(side * 1.55, floor + 1.05, -0.75),
				"PodIntake"
			)
			box(
				add,
				"light",
				Vector3.new(side * 1.56, floor + 0.55, -0.6),
				Vector3.new(side * 1.6, floor + 0.75, 1.45),
				"PodStripe"
			)
		end
		badges(add, 1.59, floor + 0.65, 0.75, 0.62, "7")
		-- Seat, driver and steering wheel.
		box(add, "dark", Vector3.new(-0.75, floor + 0.28, 0.1), Vector3.new(0.75, floor + 0.6, 1.3), "Seat")
		add(
			"dark",
			"Block",
			Vector3.new(1.5, 1.3, 0.3),
			at(0, floor + 1.0, 1.35) * CFrame.Angles(math.rad(-12), 0, 0),
			"SeatBack"
		)
		add("accent", "Ellipsoid", Vector3.new(1.35, 1.45, 1.0), at(0, floor + 1.15, 0.75), "Driver")
		add("body", "Ball", Vector3.one * 1.45, at(0, floor + 2.3, 0.6), "Helmet")
		add("light", "Cylinder", Vector3.new(0.26, 1.5, 1.5), at(0, floor + 2.3, 0.6), "HelmetStripe")
		add("glass", "Ellipsoid", Vector3.new(1.15, 0.5, 0.6), at(0, floor + 2.32, 0.02), "Visor")
		add(
			"dark",
			"Cylinder",
			Vector3.new(0.12, 0.8, 0.8),
			at(0, floor + 1.35, -0.3) * CFrame.Angles(0, math.rad(90), math.rad(-60)),
			"SteeringWheel"
		)
		-- Engine, exhausts and the big wing.
		box(add, "metal", Vector3.new(-0.9, floor + 0.28, 1.6), Vector3.new(0.9, floor + 1.1, 2.9), "Engine")
		for _, side in { -1, 1 } do
			add(
				"metal",
				"Cylinder",
				Vector3.new(1.2, 0.34, 0.34),
				at(side * 0.45, floor + 1.0, 3.3) * CFrame.Angles(0, math.rad(90), math.rad(25)),
				"ExhaustPipe"
			)
			box(
				add,
				"tail",
				Vector3.new(side * 1.3 - 0.25, floor + 0.35, 3.62),
				Vector3.new(side * 1.3 + 0.25, floor + 0.6, 3.72),
				"TailLight"
			)
		end
		wing(add, "body", 4.2, 1.1, floor + 2.1, 3.25, floor + 1.1)
		if stage >= 2 then
			-- Turbo: a stripe down the nose and tall fins on the wing.
			box(
				add,
				"accent",
				Vector3.new(-0.2, floor + 1.1, -3.3),
				Vector3.new(0.2, floor + 1.14, -0.95),
				"NoseStripe"
			)
			for _, side in { -1, 1 } do
				box(
					add,
					"accent",
					Vector3.new(side * 2.1 - 0.05, floor + 1.7, 2.6),
					Vector3.new(side * 2.1 + 0.05, floor + 2.45, 3.9),
					"WingFin"
				)
			end
		end
	end,
}

-- A shark supercar: low and pointy, a white belly, glowing gills, teeth in the grille and a fin on the roof.
designs.shark = {
	roles = {
		{
			body = look(rgb(96, 124, 160)),
			body2 = look(rgb(232, 238, 246)),
			accent = look(rgb(40, 255, 236), NEON),
			stripe = look(rgb(70, 94, 128)),
			mouth = look(rgb(120, 24, 38)),
		},
		{ -- Tiger: orange with dark stripes
			body = look(rgb(222, 132, 58)),
			body2 = look(rgb(250, 238, 216)),
			accent = look(rgb(255, 214, 64), NEON),
			stripe = look(rgb(52, 38, 30)),
			mouth = look(rgb(120, 24, 38)),
			rim = look(rgb(255, 214, 64), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 2.72, 1.66) -- on top of the fin
	end,
	antenna = Vector3.new(1.3, 1.0, 2.2),
	build = function(h, stage, add)
		local g = groundY(h)
		local p: Profile = {
			width = 4.6,
			bottom = g + 0.45,
			nose = -0.8,
			belt = 0.05,
			tail = 0.05,
			roof = 1.0,
			front = -4.5,
			back = 4.5,
			screen = -1.4,
			roofFront = 0.05,
			roofBack = 0.95,
			deck = 2.7,
			cabin = 3.2,
		}
		coupe(add, p)
		wheelSet(add, {
			g = g,
			x = 2.3,
			front = -2.95,
			rear = 2.8,
			radius = 1.02,
			rearRadius = 1.1,
			width = 0.95,
			rearWidth = 1.1,
			spokes = 5,
		})
		-- The mouth: a dark red grille with rows of teeth.
		box(
			add,
			"mouth",
			Vector3.new(-1.35, p.bottom + 0.2, p.front - 0.06),
			Vector3.new(1.35, p.nose - 0.1, p.front + 0.1),
			"Mouth"
		)
		for i = -3, 3 do
			add(
				"white",
				"Wedge",
				Vector3.new(0.3, 0.32, 0.14),
				at(i * 0.36, p.nose - 0.28, p.front - 0.1) * CFrame.Angles(math.pi, 0, 0),
				"Tooth"
			)
			add(
				"white",
				"Wedge",
				Vector3.new(0.3, 0.26, 0.14),
				at(i * 0.36 + 0.18, p.bottom + 0.33, p.front - 0.1),
				"Tooth"
			)
		end
		headlights(add, 1.7, p.nose - 0.18, p.front, 0.75, 0.16)
		box(
			add,
			"dark",
			Vector3.new(-2.4, p.bottom - 0.05, p.front - 0.3),
			Vector3.new(2.4, p.bottom + 0.1, p.front + 0.6),
			"Splitter"
		)
		-- Glowing gills behind the front wheels, and engine vents on the deck.
		for _, side in { -1, 1 } do
			for k = 0, 2 do
				local z = -1.55 + k * 0.38
				box(
					add,
					"accent",
					Vector3.new(side * 2.3 - 0.02, p.nose + 0.05, z - 0.06),
					Vector3.new(side * 2.3 + 0.03, p.belt - 0.12, z + 0.06),
					"Gill"
				)
			end
			rampDown(
				add,
				"dark",
				Vector3.new(side * 2.32, p.nose + 0.1, 0.6),
				Vector3.new(side * 2.36, p.belt - 0.1, 1.9),
				"SideIntake"
			)
		end
		for k = 0, 3 do
			box(
				add,
				"dark",
				Vector3.new(-0.9, p.belt + 0.01, 2.95 + k * 0.35),
				Vector3.new(0.9, p.belt + 0.05, 3.1 + k * 0.35),
				"Vent"
			)
		end
		taillights(add, 1.9, p.tail - 0.22, p.back, 0.5, 0.16)
		box(
			add,
			"dark",
			Vector3.new(-1.7, p.bottom - 0.02, p.back - 0.5),
			Vector3.new(1.7, p.bottom + 0.35, p.back + 0.12),
			"Diffuser"
		)
		exhausts(add, 0.35, p.bottom + 0.25, p.back + 0.2, 0.46)
		mirrors(add, 1.62, p.belt + 0.12, p.screen + 0.7)
		-- The dorsal fin, and a tail fin holding up the wing.
		rampUp(
			add,
			"body",
			Vector3.new(-0.16, p.roof, p.roofFront + 0.2),
			Vector3.new(0.16, p.roof + 1.7, p.roofBack + 0.9),
			"DorsalFin"
		)
		box(
			add,
			"team",
			Vector3.new(-0.18, p.roof + 1.55, p.roofBack + 0.5),
			Vector3.new(0.18, p.roof + 1.72, p.roofBack + 0.92),
			"TeamLight"
		)
		rampUp(
			add,
			"body",
			Vector3.new(-0.14, p.belt, p.back - 1.3),
			Vector3.new(0.14, p.belt + 1.05, p.back - 0.2),
			"TailFin"
		)
		wing(add, "body", 4.0, 0.9, p.belt + 1.05, p.back - 0.6, p.belt)
		if stage == 2 then
			-- Tiger stripes over the bonnet and down the sides.
			for k = 0, 3 do
				strip(
					add,
					"stripe",
					0,
					3.6 - k * 0.8,
					p.nose,
					p.front,
					p.belt,
					p.screen,
					0.03 + k * 0.004,
					"TigerStripe"
				)
				local z = -0.4 + k * 0.7
				box(
					add,
					"stripe",
					Vector3.new(-2.33, p.nose + 0.05, z),
					Vector3.new(2.33, p.belt - 0.2, z + 0.22),
					"TigerStripe"
				)
			end
		end
	end,
}

-- A monster truck: a lifted pickup on huge treaded tyres, with chrome bumpers, a roof light bar, a roll bar
-- and exhaust stacks.
designs.monster = {
	roles = {
		{
			body = look(rgb(222, 48, 44)),
			body2 = look(rgb(150, 26, 30)),
			accent = look(rgb(255, 200, 40)),
			rim = look(rgb(255, 200, 40), METAL),
			metal = look(rgb(226, 228, 236), METAL, 0, 0.25),
		},
		{ -- Mega: black paint, chrome and flames
			body = look(rgb(38, 38, 48)),
			body2 = look(rgb(22, 22, 28)),
			accent = look(rgb(255, 132, 30), NEON),
			metal = look(rgb(232, 234, 242), METAL, 0, 0.35),
			rim = look(rgb(232, 234, 242), METAL, 0, 0.3),
		},
	},
	topper = function()
		return Vector3.new(0, 2.99, 0.45)
	end,
	antenna = Vector3.new(2.3, 2.9, 1.1),
	build = function(h, stage, add)
		local g = groundY(h)
		local r = 1.75
		local axleY = g + r
		wheelSet(add, {
			g = g,
			x = 2.7,
			front = -2.95,
			rear = 2.95,
			radius = r,
			width = 1.45,
			spokes = 6,
			archRole = "trim",
			treads = true,
			inset = 0.05,
		})
		-- Frame, axles and big coil-over shocks.
		for _, side in { -1, 1 } do
			box(
				add,
				"dark",
				Vector3.new(side * 1.0, axleY - 0.25, -4.2),
				Vector3.new(side * 1.4, axleY + 0.2, 4.2),
				"FrameRail"
			)
		end
		for _, z in { -2.95, 2.95 } do
			add("metal", "Cylinder", Vector3.new(6.0, 0.5, 0.5), at(0, axleY, z), "Axle")
			box(
				add,
				"dark",
				Vector3.new(-0.6, axleY - 0.45, z - 0.45),
				Vector3.new(0.6, axleY + 0.4, z + 0.45),
				"Differential"
			)
			for _, side in { -1, 1 } do
				add(
					"accent",
					"Cylinder",
					Vector3.new(1.6, 0.42, 0.42),
					at(side * 1.85, axleY + 0.75, z) * CFrame.Angles(0, 0, math.rad(90 + side * 18)),
					"Shock"
				)
			end
		end
		-- The pickup body.
		local base, hood, belt, roof = 0.1, 1.15, 1.55, 2.95
		box(add, "body2", Vector3.new(-2.6, base, -4.6), Vector3.new(2.6, base + 0.55, 4.6), "LowerBody")
		box(add, "body", Vector3.new(-2.6, base + 0.55, -4.6), Vector3.new(2.6, hood, -1.4), "Hood")
		box(add, "body", Vector3.new(-1.0, hood, -4.2), Vector3.new(1.0, hood + 0.25, -1.8), "HoodBulge")
		box(add, "dark", Vector3.new(-0.7, hood + 0.25, -3.9), Vector3.new(0.7, hood + 0.55, -3.2), "Scoop")
		box(add, "body", Vector3.new(-2.6, base + 0.55, -1.4), Vector3.new(2.6, belt, 1.3), "Cab")
		rampUp(add, "glass", Vector3.new(-2.35, belt, -1.4), Vector3.new(2.35, roof, -0.6), "Windscreen")
		box(add, "glass", Vector3.new(-2.33, belt, -0.6), Vector3.new(2.33, roof - 0.1, 1.2), "Windows")
		box(add, "body", Vector3.new(-2.45, roof - 0.14, -0.7), Vector3.new(2.45, roof + 0.04, 1.3), "Roof")
		for _, side in { -1, 1 } do
			strip(add, "body", side * 2.37, 0.14, belt, -1.4, roof, -0.6, 0.02, "APillar")
			box(
				add,
				"body",
				Vector3.new(side * 2.37 - 0.08, belt, 1.0),
				Vector3.new(side * 2.37 + 0.08, roof, 1.3),
				"CPillar"
			)
		end
		-- The open bed, with a roll bar.
		box(add, "dark", Vector3.new(-2.4, base + 0.55, 1.3), Vector3.new(2.4, base + 0.75, 4.5), "BedFloor")
		for _, side in { -1, 1 } do
			box(
				add,
				"body",
				Vector3.new(side * 2.35, base + 0.55, 1.3),
				Vector3.new(side * 2.6, belt + 0.15, 4.6),
				"BedSide"
			)
			add(
				"metal",
				"Cylinder",
				Vector3.new(1.6, 0.26, 0.26),
				at(side * 2.1, belt + 0.95, 1.7) * CYL_ALONG_Y,
				"RollBarLeg"
			)
		end
		box(add, "body", Vector3.new(-2.35, base + 0.55, 4.35), Vector3.new(2.35, belt + 0.15, 4.6), "Tailgate")
		add("metal", "Cylinder", Vector3.new(4.5, 0.26, 0.26), at(0, belt + 1.75, 1.7), "RollBar")
		-- Chrome bumpers, grille and round headlights.
		box(add, "metal", Vector3.new(-2.9, base - 0.1, -4.95), Vector3.new(2.9, base + 0.45, -4.55), "FrontBumper")
		box(add, "metal", Vector3.new(-2.9, base - 0.1, 4.55), Vector3.new(2.9, base + 0.45, 4.95), "RearBumper")
		box(add, "dark", Vector3.new(-1.5, base + 0.55, -4.66), Vector3.new(1.5, hood - 0.1, -4.55), "Grille")
		for k = 0, 3 do
			local y = base + 0.65 + k * 0.1
			box(add, "metal", Vector3.new(-1.45, y - 0.02, -4.7), Vector3.new(1.45, y + 0.02, -4.64), "GrilleBar")
		end
		for _, side in { -1, 1 } do
			add(
				"trim",
				"Cylinder",
				Vector3.new(0.14, 0.72, 0.72),
				at(side * 2.05, hood - 0.3, -4.62) * CYL_ALONG_Z,
				"LightBezel"
			)
			add(
				"lamp",
				"Cylinder",
				Vector3.new(0.12, 0.56, 0.56),
				at(side * 2.05, hood - 0.3, -4.68) * CYL_ALONG_Z,
				"Headlight"
			)
			box(
				add,
				"tail",
				Vector3.new(side * 2.45 - 0.15, base + 0.7, 4.6),
				Vector3.new(side * 2.45 + 0.15, belt, 4.68),
				"TailLight"
			)
			-- Exhaust stacks behind the cab.
			add(
				"metal",
				"Cylinder",
				Vector3.new(2.4, 0.42, 0.42),
				at(side * 2.1, belt + 0.9, 1.45) * CYL_ALONG_Y,
				"Stack"
			)
			add(
				"dark",
				"Cylinder",
				Vector3.new(0.3, 0.46, 0.46),
				at(side * 2.1, belt + 2.05, 1.45) * CYL_ALONG_Y,
				"StackTip"
			)
			box(
				add,
				"dark",
				Vector3.new(side * 2.7, axleY - 0.3, 3.95),
				Vector3.new(side * 3.9, axleY + 0.9, 4.05),
				"MudFlap"
			)
		end
		badges(add, 2.63, base + 0.95, 0.0, 1.3, "🛻")
		-- A light bar on the roof.
		box(add, "dark", Vector3.new(-2.3, roof + 0.04, -0.55), Vector3.new(2.3, roof + 0.32, -0.25), "LightBar")
		box(add, "team", Vector3.new(-2.3, roof + 0.32, -0.55), Vector3.new(2.3, roof + 0.38, -0.25), "TeamLight")
		for k = 0, 4 do
			add(
				"lamp",
				"Cylinder",
				Vector3.new(0.12, 0.34, 0.34),
				at(-1.8 + k * 0.9, roof + 0.18, -0.58) * CYL_ALONG_Z,
				"RoofLight"
			)
		end
		if stage >= 2 then
			-- Flames licking along the sides.
			for _, side in { -1, 1 } do
				for k = 0, 2 do
					add(
						"accent",
						"Ellipsoid",
						Vector3.new(0.1, 0.46 - k * 0.08, 2.4 - k * 0.4),
						at(side * 2.61, base + 0.7 + k * 0.22, -3.2 + k * 0.6),
						"Flame"
					)
				end
			end
		end
	end,
}

-- A flying saucer: a two-part hull with a glowing rim of lights, a glass dome with a little alien pilot, and
-- hover pads instead of wheels.
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
	topper = function()
		return Vector3.new(0, 1.86, 0.3) -- on the alien's head
	end,
	antenna = Vector3.new(2.3, -0.1, 2.3),
	build = function(h, stage, add)
		local floor = groundY(h)
		add("body", "Ellipsoid", Vector3.new(7.4, 1.3, 7.4), at(0, -0.35, 0), "Saucer")
		add("body2", "Ellipsoid", Vector3.new(4.8, 1.6, 4.8), at(0, -0.8, 0), "Belly")
		add("trim", "Cylinder", Vector3.new(0.1, 5.6, 5.6), at(0, 0.18, 0) * CYL_ALONG_Y, "PanelRing")
		add("accent", "Cylinder", Vector3.new(0.22, 7.6, 7.6), at(0, -0.35, 0) * CYL_ALONG_Y, "Rim")
		add("team", "Cylinder", Vector3.new(0.14, 3.4, 3.4), at(0, -1.55, 0) * CYL_ALONG_Y, "TeamLight")
		local lights = if stage >= 2 then 16 else 12
		for i = 0, lights - 1 do
			local angle = i / lights * math.pi * 2
			local role = if i % 2 == 0 then "light" else "lamp"
			add(role, "Ball", Vector3.one * 0.55, at(math.sin(angle) * 3.4, -0.1, math.cos(angle) * 3.4), "RimLight")
		end
		-- The pilot, under a glass dome.
		add("glass", "Ellipsoid", Vector3.new(3.6, 3.0, 3.6), at(0, 0.45, 0.3), "Dome")
		add("trim", "Cylinder", Vector3.new(0.2, 3.7, 3.7), at(0, 0.3, 0.3) * CYL_ALONG_Y, "DomeRing")
		add("skin", "Ellipsoid", Vector3.new(1.3, 1.1, 1.2), at(0, 0.35, 0.35), "Alien")
		add("skin", "Ellipsoid", Vector3.new(1.6, 1.4, 1.4), at(0, 1.15, 0.3), "AlienHead")
		for _, side in { -1, 1 } do
			local socket = at(side * 0.36, 1.2, -0.28) * CFrame.Angles(0, 0, math.rad(-side * 25))
			add("pupil", "Ellipsoid", Vector3.new(0.5, 0.78, 0.3), socket, "AlienEye")
			add("shine", "Ball", Vector3.one * 0.14, socket * CFrame.new(0.08, 0.18, -0.13), "EyeShine")
			local tip = Vector3.new(side * 0.55, 2.3, 0.3)
			local base = Vector3.new(side * 0.3, 1.75, 0.3)
			local stalk = CFrame.new((tip + base) / 2) * CFrame.Angles(0, 0, math.rad(90 - side * 25))
			add("skin", "Cylinder", Vector3.new((tip - base).Magnitude, 0.1, 0.1), stalk, "AlienAntenna")
			add("accent", "Ball", Vector3.one * 0.3, CFrame.new(tip), "AntennaTip")
		end
		-- Glowing hover pads instead of wheels.
		for _, x in { -2.2, 2.2 } do
			for _, z in { -2.3, 2.3 } do
				add("dark", "Cylinder", Vector3.new(0.5, 1.6, 1.6), at(x, floor + 0.85, z) * CYL_ALONG_Y, "PadHolder")
				add("lamp", "Cylinder", Vector3.new(0.3, 1.3, 1.3), at(x, floor + 0.55, z) * CYL_ALONG_Y, "HoverPad")
			end
		end
		-- Little fins at the back (bigger once it's golden).
		for _, side in { -1, 1 } do
			local size = if stage >= 2 then Vector3.new(0.3, 1.2, 2.0) else Vector3.new(0.25, 0.8, 1.4)
			add("body2", "Wedge", size, at(side * 2.5, 0.2, 2.5) * CFrame.Angles(0, 0, math.rad(-side * 20)), "Fin")
		end
	end,
}

-- A taco food truck: a tall teal van with a serving hatch under a striped awning, a menu board, and a giant taco
-- on the roof.
designs.taco = {
	roles = {
		{
			body = look(rgb(38, 184, 168)),
			body2 = look(rgb(26, 124, 116)),
			accent = look(rgb(255, 96, 64)),
			stripe = look(rgb(255, 204, 64)),
			light = look(rgb(255, 246, 222)),
			shell = look(rgb(240, 184, 72)),
			leaf = look(rgb(104, 190, 64)),
			tomato = look(rgb(230, 52, 40)),
			meat = look(rgb(132, 72, 40)),
		},
		{ -- Spicy: hot sauce red with chilli peppers on the roof
			body = look(rgb(214, 56, 34)),
			body2 = look(rgb(140, 32, 22)),
			accent = look(rgb(255, 176, 40)),
			stripe = look(rgb(255, 150, 30), NEON),
			light = look(rgb(255, 238, 200)),
			rim = look(rgb(255, 196, 70), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 2.42, -0.9)
	end,
	antenna = Vector3.new(-1.9, 2.3, 3.9),
	build = function(h, stage, add)
		local g = groundY(h)
		local bottom = g + 0.75
		local roof = 2.3
		-- The van: a tall box behind a short cab with a big sloping windscreen.
		box(add, "body2", Vector3.new(-2.45, bottom, -4.5), Vector3.new(2.45, bottom + 0.45, 4.5), "LowerBody")
		box(add, "body", Vector3.new(-2.45, bottom + 0.45, -1.9), Vector3.new(2.45, roof, 4.5), "Van")
		box(add, "body", Vector3.new(-2.45, bottom + 0.45, -4.5), Vector3.new(2.45, 0.35, -1.9), "Cab")
		box(add, "cabin", Vector3.new(-2.0, 0.35, -3.2), Vector3.new(2.0, roof - 0.3, -1.95), "Interior")
		rampUp(add, "glass", Vector3.new(-2.25, 0.35, -3.4), Vector3.new(2.25, roof, -1.9), "Windscreen")
		box(add, "body", Vector3.new(-2.5, roof - 0.12, -2.05), Vector3.new(2.5, roof + 0.12, 4.55), "RoofRail")
		-- A yellow band all the way round.
		for _, side in { -1, 1 } do
			box(add, "stripe", Vector3.new(side * 2.44, 0.05, -4.45), Vector3.new(side * 2.5, 0.45, 4.45), "Stripe")
		end
		-- Face: grille, round-ish headlights, a chunky bumper.
		box(add, "dark", Vector3.new(-1.3, bottom + 0.55, -4.56), Vector3.new(1.3, 0.2, -4.45), "Grille")
		for k = 0, 2 do
			local y = bottom + 0.72 + k * 0.28
			box(add, "trim", Vector3.new(-1.25, y - 0.04, -4.62), Vector3.new(1.25, y + 0.04, -4.55), "GrilleBar")
		end
		headlights(add, 1.85, 0.0, -4.5, 0.7, 0.45)
		box(add, "trim", Vector3.new(-2.5, bottom - 0.1, -4.8), Vector3.new(2.5, bottom + 0.4, -4.45), "Bumper")
		box(add, "trim", Vector3.new(-2.5, bottom - 0.1, 4.45), Vector3.new(2.5, bottom + 0.4, 4.8), "RearBumper")
		taillights(add, 1.95, 0.2, 4.5, 0.55, 0.5)
		exhausts(add, 1.0, bottom + 0.1, 4.75, 0.4)
		mirrors(add, 2.45, 0.8, -3.1)
		-- The serving hatch on the right, with a counter and a scalloped awning propped over it.
		box(add, "dark", Vector3.new(2.44, 0.75, -0.9), Vector3.new(2.5, 1.95, 2.8), "Hatch")
		box(add, "trim", Vector3.new(2.45, 0.6, -0.95), Vector3.new(2.95, 0.72, 2.85), "Counter")
		add(
			"accent",
			"Block",
			Vector3.new(1.4, 0.1, 3.9),
			at(3.1, 2.05, 0.95) * CFrame.Angles(0, 0, math.rad(-18)),
			"Awning"
		)
		for k = 0, 5 do
			add("white", "Ball", Vector3.one * 0.5, at(3.72, 1.78, -0.7 + k * 0.66), "AwningScallop")
		end
		-- The menu board on the left.
		add(
			"light",
			"Block",
			Vector3.new(2.8, 0.85, 0.1),
			at(-2.52, 1.35, 1.2) * CFrame.Angles(0, math.rad(90), 0),
			"MenuBoard",
			"🌮 TACOS"
		)
		wheelSet(add, { g = g, x = 2.45, front = -3.0, rear = 2.9, radius = 1.1, width = 1.0, spokes = 6 })
		-- The giant taco on the roof: two halves of a crunchy shell with the filling between them.
		for _, side in { -1, 1 } do
			add("shell", "Cylinder", Vector3.new(0.24, 3.6, 3.6), at(side * 0.58, roof, 1.3), "TacoShell")
		end
		add("meat", "Ellipsoid", Vector3.new(0.95, 0.9, 3.0), at(0, roof + 1.25, 1.3), "TacoMeat")
		add("leaf", "Ellipsoid", Vector3.new(1.05, 0.55, 3.2), at(0, roof + 1.6, 1.3), "TacoLettuce")
		for k = 0, 3 do
			add(
				"tomato",
				"Ball",
				Vector3.one * 0.42,
				at(if k % 2 == 0 then -0.22 else 0.22, roof + 1.78, 0.2 + k * 0.75),
				"TacoTomato"
			)
		end
		box(add, "team", Vector3.new(-2.2, roof + 0.12, -2.02), Vector3.new(2.2, roof + 0.22, -1.88), "TeamLight")
		if stage >= 2 then
			-- Chilli peppers on the front corners of the roof.
			for _, side in { -1, 1 } do
				add(
					"tomato",
					"Ellipsoid",
					Vector3.new(0.5, 0.5, 1.5),
					at(side * 1.9, roof + 0.35, -1.2) * CFrame.Angles(math.rad(-15), 0, math.rad(side * 10)),
					"Chilli"
				)
				add("leaf", "Cylinder", Vector3.new(0.35, 0.18, 0.18), at(side * 1.9, roof + 0.5, -0.45), "ChilliStem")
			end
		end
	end,
}

-- A rubber duck car: a round yellow body with its tail up, little wings, a big head with an orange beak and
-- googly eyes, on small open wheels.
designs.duck = {
	roles = {
		{
			body = look(rgb(255, 214, 46)),
			body2 = look(rgb(246, 188, 30)),
			beak = look(rgb(255, 134, 30)),
			light = look(rgb(255, 250, 230)),
		},
		{ -- Disco: purple wings, shades and a glowing collar
			body = look(rgb(255, 210, 56)),
			body2 = look(rgb(170, 100, 255)),
			beak = look(rgb(255, 120, 40)),
			light = look(rgb(255, 120, 230), NEON),
			rim = look(rgb(200, 150, 255), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 3.3, -2.2) -- on the duck's head
	end,
	antenna = Vector3.new(1.4, 1.0, 2.7),
	build = function(h, stage, add)
		local g = groundY(h)
		wheelSet(add, {
			g = g,
			x = 2.0,
			front = -2.5,
			rear = 2.6,
			radius = 0.85,
			width = 0.8,
			spokes = 5,
			open = true,
		})
		add("body", "Ellipsoid", Vector3.new(5.2, 2.8, 7.8), at(0, -0.05, 0.5), "DuckBody")
		add(
			"body",
			"Ellipsoid",
			Vector3.new(2.6, 1.8, 2.3),
			at(0, 1.0, 4.0) * CFrame.Angles(math.rad(-32), 0, 0),
			"Tail"
		)
		for _, side in { -1, 1 } do
			add(
				"body2",
				"Ellipsoid",
				Vector3.new(0.7, 1.5, 3.5),
				at(side * 2.5, 0.35, 0.9) * CFrame.Angles(math.rad(12), 0, 0),
				"Wing"
			)
		end
		-- The head, beak and googly eyes.
		add("body", "Ellipsoid", Vector3.new(3.2, 3.0, 3.0), at(0, 1.85, -2.2), "DuckHead")
		add("beak", "Ellipsoid", Vector3.new(2.0, 0.75, 1.7), at(0, 1.5, -3.7), "Beak")
		add("dark", "Block", Vector3.new(1.5, 0.05, 1.0), at(0, 1.47, -3.9), "BeakLine")
		for _, side in { -1, 1 } do
			local eye = at(side * 0.78, 2.3, -3.45) * CFrame.Angles(0, math.rad(side * 22), 0)
			add("eye", "Ellipsoid", Vector3.new(0.95, 1.15, 0.5), eye, "Eye")
			add("pupil", "Ball", Vector3.one * 0.5, eye * CFrame.new(0, -0.08, -0.2), "Pupil")
			add("shine", "Ball", Vector3.one * 0.16, eye * CFrame.new(0.1, 0.1, -0.4), "EyeShine")
		end
		-- Headlights on its chest, tail lights either side of the tail.
		for _, side in { -1, 1 } do
			add("lamp", "Ellipsoid", Vector3.new(0.8, 0.45, 0.3), at(side * 1.15, 0.25, -3.25), "Headlight")
			add("tail", "Ball", Vector3.one * 0.45, at(side * 1.25, 0.35, 4.15), "TailLight")
		end
		exhausts(add, 0.55, g + 1.05, 4.25, 0.34)
		-- A team-coloured collar around its neck.
		add("team", "Cylinder", Vector3.new(0.25, 2.9, 2.9), at(0, 0.62, -2.2) * CYL_ALONG_Y, "TeamLight")
		if stage >= 2 then
			-- Disco shades.
			add("dark", "Block", Vector3.new(2.2, 0.5, 0.2), at(0, 2.35, -3.72), "Shades")
			add("light", "Block", Vector3.new(2.3, 0.08, 0.22), at(0, 2.62, -3.7), "ShadesRim")
		end
	end,
}

-- A hot dog: a long bun on four wheels, the sausage running the full length with a mustard zigzag, and a
-- bubble canopy for the driver.
designs.hotdog = {
	roles = {
		{
			body = look(rgb(226, 168, 96)),
			body2 = look(rgb(196, 134, 72)),
			accent = look(rgb(182, 64, 46)),
			stripe = look(rgb(255, 214, 40)),
			light = look(rgb(255, 245, 230)),
			chilli = look(rgb(122, 44, 26)),
		},
		{ -- Chili dog: a spoonful of chili and melted cheese
			body = look(rgb(214, 150, 80)),
			body2 = look(rgb(170, 108, 56)),
			accent = look(rgb(160, 50, 36)),
			stripe = look(rgb(255, 196, 40), NEON),
			rim = look(rgb(255, 200, 80), METAL),
		},
	},
	topper = function()
		return Vector3.new(0, 1.97, -2.1) -- on the canopy
	end,
	antenna = Vector3.new(1.35, 0.7, 3.5),
	build = function(h, stage, add)
		local g = groundY(h)
		wheelSet(add, {
			g = g,
			x = 2.2,
			front = -3.1,
			rear = 3.1,
			radius = 1.0,
			width = 0.85,
			spokes = 5,
			archRole = "body2",
		})
		-- The bun: a flat base with a soft half on each side.
		add("body2", "Ellipsoid", Vector3.new(4.8, 1.5, 9.8), at(0, -0.75, 0), "BunBase")
		for _, side in { -1, 1 } do
			add("body", "Ellipsoid", Vector3.new(1.9, 1.9, 9.4), at(side * 1.45, 0.05, 0), "Bun")
		end
		-- The sausage, poking out of both ends.
		local sausageY = 0.45
		local halfLength = 5.4
		add("accent", "Ellipsoid", Vector3.new(2.0, 1.9, halfLength * 2), at(0, sausageY, 0), "Sausage")
		local function topOfSausage(z: number): number
			return sausageY + 0.95 * math.sqrt(math.max(0, 1 - (z / halfLength) ^ 2))
		end
		-- A mustard zigzag behind the canopy.
		for k = 0, 5 do
			local z = -0.3 + k * 0.85
			add(
				"stripe",
				"Block",
				Vector3.new(0.26, 0.1, 1.15),
				at(0, topOfSausage(z) + 0.02, z) * CFrame.Angles(0, math.rad(if k % 2 == 0 then 38 else -38), 0),
				"Mustard"
			)
		end
		add("glass", "Ellipsoid", Vector3.new(1.7, 1.1, 2.3), at(0, topOfSausage(-2.1) + 0.1, -2.1), "Canopy")
		add(
			"trim",
			"Cylinder",
			Vector3.new(0.12, 1.8, 2.4),
			at(0, topOfSausage(-2.1) - 0.2, -2.1) * CYL_ALONG_Y,
			"CanopyRing"
		)
		for _, side in { -1, 1 } do
			add("lamp", "Ellipsoid", Vector3.new(0.85, 0.45, 0.3), at(side * 1.5, -0.35, -4.62), "Headlight")
			add("tail", "Ellipsoid", Vector3.new(0.85, 0.45, 0.3), at(side * 1.5, -0.35, 4.62), "TailLight")
			add("team", "Block", Vector3.new(0.1, 0.14, 5.5), at(side * 2.25, -0.95, 0), "TeamLight")
		end
		exhausts(add, 0.7, g + 0.75, 4.95, 0.36)
		if stage >= 2 then
			-- Chili on top, with cheese dripping over it.
			for k = 0, 6 do
				local z = 0.2 + k * 0.62
				add(
					"chilli",
					"Ball",
					Vector3.one * (0.55 + (k % 3) * 0.12),
					at(if k % 2 == 0 then -0.3 else 0.3, topOfSausage(z) + 0.12, z),
					"Chili"
				)
			end
			for _, side in { -1, 1 } do
				add("stripe", "Block", Vector3.new(0.14, 0.6, 0.2), at(side * 0.9, sausageY + 0.55, 1.4), "CheeseDrip")
			end
		end
	end,
}

---------------------------------------------------------------------------------------------------------------
-- Fused cars (see CarCatalog): the Base car's shape in new colours, with a piece of the Flavor car added on.
---------------------------------------------------------------------------------------------------------------

type Fused = {
	roles: { Roles }, -- laid over the base car's own colours, at stage 1 and stage 2
	skip: { [string]: boolean }?, -- base car parts to leave off (by name)
	extra: (h: Vector3, stage: number, add: Add) -> (),
}

local FUSED: { [string]: Fused } = {}

-- Pizza Shark: a Neon Shark made of melted cheese on a crust, covered in pepperoni, with a slice of pizza for
-- a fin. Deluxe adds olives and green peppers.
FUSED.pizzashark = {
	roles = {
		{
			body = look(rgb(255, 200, 76)),
			body2 = look(rgb(214, 146, 64)),
			accent = look(rgb(255, 120, 40), NEON),
			crust = look(rgb(196, 124, 52)),
			pepperoni = look(rgb(186, 40, 34)),
			olive = look(rgb(34, 30, 34)),
			pepper = look(rgb(70, 170, 60)),
		},
		{ -- Deluxe: golden brown, with all the toppings
			body = look(rgb(255, 184, 56)),
			body2 = look(rgb(160, 100, 44)),
			accent = look(rgb(255, 90, 30), NEON),
			rim = look(rgb(255, 196, 70), METAL),
		},
	},
	skip = { TigerStripe = true },
	extra = function(_h, stage, add)
		-- (The shark's bonnet rises from y -0.8 at its nose, z -4.5, to y 0.05 at the windscreen, z -1.4.)
		local nose, belt, front, screen = -0.8, 0.05, -4.5, -1.4
		local slope = math.atan2(belt - nose, screen - front)
		local function onBonnet(x: number, z: number, lift: number): CFrame
			local y = nose + (z - front) / (screen - front) * (belt - nose)
			return CFrame.new(x, y + lift, z) * CFrame.Angles(-slope, 0, 0)
		end
		for _, spot in { { -1.1, -3.7 }, { 0.9, -3.3 }, { -0.3, -2.4 }, { 1.4, -2.0 }, { -1.5, -1.9 } } do
			add(
				"pepperoni",
				"Cylinder",
				Vector3.new(0.06, 0.9, 0.9),
				onBonnet(spot[1], spot[2], 0.04) * CYL_ALONG_Y,
				"Pepperoni"
			)
		end
		for _, side in { -1, 1 } do
			add(
				"pepperoni",
				"Cylinder",
				Vector3.new(0.06, 0.8, 0.8),
				at(side * 1.75, 0.08, 3.3) * CYL_ALONG_Y,
				"Pepperoni"
			)
		end
		badges(add, 2.33, -0.37, -0.05, 0.78, "🍕")
		-- The dorsal fin is a slice of pizza: crust down its back edge, pepperoni on both sides.
		box(add, "crust", Vector3.new(-0.26, 1.0, 1.58), Vector3.new(0.26, 2.55, 1.95), "Crust")
		for _, side in { -1, 1 } do
			add("pepperoni", "Cylinder", Vector3.new(0.05, 0.44, 0.44), at(side * 0.18, 1.5, 1.08), "Pepperoni")
			add("pepperoni", "Cylinder", Vector3.new(0.05, 0.36, 0.36), at(side * 0.18, 1.98, 1.42), "Pepperoni")
		end
		if stage >= 2 then
			for _, spot in { { 0.2, -3.9 }, { -0.9, -2.9 }, { 1.0, -2.6 }, { 0.3, -1.7 } } do
				local where = onBonnet(spot[1], spot[2], 0.05)
				add("olive", "Cylinder", Vector3.new(0.07, 0.42, 0.42), where * CYL_ALONG_Y, "Olive")
				add("body", "Cylinder", Vector3.new(0.08, 0.18, 0.18), where * CYL_ALONG_Y, "OliveHole")
			end
			for _, spot in { { -1.6, -3.2, 30 }, { 1.75, -3.7, -25 }, { -0.9, -1.75, 60 } } do
				local where = onBonnet(spot[1], spot[2], 0.05) * CFrame.Angles(0, math.rad(spot[3]), 0)
				add("pepper", "Block", Vector3.new(0.16, 0.06, 0.8), where, "GreenPepper")
			end
		end
	end,
}

-- Duck Saucer: a rubber-duck-yellow UFO, with a rubber duck at the controls instead of the alien. At Disco it
-- turns purple and the pilot puts its shades on.
FUSED.ducksaucer = {
	roles = {
		{
			body = look(rgb(255, 214, 46)),
			body2 = look(rgb(255, 150, 40)),
			accent = look(rgb(90, 200, 255), NEON),
			light = look(rgb(255, 150, 40), NEON),
			glass = look(rgb(210, 245, 255), GLASS, 0.7, 0.1), -- clearer, so you can see who's flying
			duck = look(rgb(255, 222, 60)),
			beak = look(rgb(255, 134, 30)),
		},
		{ -- Disco
			body = look(rgb(170, 100, 255), SMOOTH, 0, 0.1),
			body2 = look(rgb(255, 210, 56)),
			accent = look(rgb(255, 120, 230), NEON),
			light = look(rgb(90, 232, 255), NEON),
		},
	},
	skip = {
		Alien = true,
		AlienHead = true,
		AlienEye = true,
		EyeShine = true,
		AlienAntenna = true,
		AntennaTip = true,
	},
	extra = function(_h, stage, add)
		-- (The glass dome is 3.6 wide and 3 tall, centred at y 0.45, z 0.3.)
		add("duck", "Ellipsoid", Vector3.new(1.5, 1.1, 1.8), at(0, 0.45, 0.6), "DuckPilot")
		add(
			"duck",
			"Ellipsoid",
			Vector3.new(0.8, 0.5, 0.75),
			at(0, 0.82, 1.35) * CFrame.Angles(math.rad(-35), 0, 0),
			"DuckTail"
		)
		add("duck", "Ball", Vector3.one * 1.35, at(0, 1.18, 0.2), "DuckHead")
		add("beak", "Ellipsoid", Vector3.new(0.8, 0.32, 0.66), at(0, 1.05, -0.52), "Beak")
		for _, side in { -1, 1 } do
			add("pupil", "Ball", Vector3.one * 0.26, at(side * 0.28, 1.36, -0.37), "Eye")
			add("shine", "Ball", Vector3.one * 0.09, at(side * 0.28 + 0.04, 1.42, -0.48), "EyeShine")
		end
		if stage >= 2 then
			add("dark", "Block", Vector3.new(1.05, 0.26, 0.1), at(0, 1.36, -0.5), "Shades")
			add("light", "Block", Vector3.new(1.1, 0.05, 0.12), at(0, 1.5, -0.49), "ShadesRim")
		end
	end,
}

-- Monster Taco: a teal-and-yellow Monster Truck from the taco stand, with a giant taco riding in its bed.
-- At Spicy it turns hot-sauce red with chillies on the bonnet.
FUSED.monstertaco = {
	roles = {
		{
			body = look(rgb(38, 184, 168)),
			body2 = look(rgb(26, 124, 116)),
			accent = look(rgb(255, 96, 64)),
			stripe = look(rgb(255, 204, 64)),
			rim = look(rgb(255, 204, 64), METAL),
			shell = look(rgb(240, 184, 72)),
			leaf = look(rgb(104, 190, 64)),
			tomato = look(rgb(230, 52, 40)),
			meat = look(rgb(132, 72, 40)),
		},
		{ -- Spicy
			body = look(rgb(214, 56, 34)),
			body2 = look(rgb(140, 32, 22)),
			accent = look(rgb(255, 176, 40), NEON),
			stripe = look(rgb(255, 150, 30), NEON),
			rim = look(rgb(255, 196, 70), METAL),
		},
	},
	skip = { Badge = true },
	extra = function(_h, stage, add)
		-- (The truck's sides are 2.6 out; its bed floor is at y 0.85, from z 1.3 back to 4.35.)
		badges(add, 2.63, 1.05, 0.0, 1.3, "🌮")
		for _, side in { -1, 1 } do
			box(add, "stripe", Vector3.new(side * 2.59, 0.6, -4.55), Vector3.new(side * 2.64, 0.78, 4.55), "Stripe")
		end
		-- The taco: two halves of a crunchy shell with the filling between them.
		for _, side in { -1, 1 } do
			add("shell", "Cylinder", Vector3.new(0.24, 2.8, 2.8), at(side * 0.55, 1.5, 2.95), "TacoShell")
		end
		add("meat", "Ellipsoid", Vector3.new(0.9, 0.75, 2.3), at(0, 2.47, 2.95), "TacoMeat")
		add("leaf", "Ellipsoid", Vector3.new(1.0, 0.45, 2.5), at(0, 2.75, 2.95), "TacoLettuce")
		for k = 0, 3 do
			add(
				"tomato",
				"Ball",
				Vector3.one * 0.36,
				at(if k % 2 == 0 then -0.18 else 0.18, 2.9, 2.1 + k * 0.57),
				"TacoTomato"
			)
		end
		if stage >= 2 then
			for _, side in { -1, 1 } do
				add(
					"tomato",
					"Ellipsoid",
					Vector3.new(0.5, 0.5, 1.5),
					at(side * 1.65, 1.4, -3.0) * CFrame.Angles(0, math.rad(side * 12), 0),
					"Chilli"
				)
				add(
					"leaf",
					"Cylinder",
					Vector3.new(0.3, 0.14, 0.14),
					at(side * 1.8, 1.6, -2.3) * CYL_ALONG_Y,
					"ChilliStem"
				)
			end
		end
	end,
}

-- Makes a fused car's design: its base car's build (without the skipped parts) plus the extras.
local function fusedDesign(recipe: Fused, base: Design): Design
	-- Each stage's colours: the base car's for that stage, then the fused car's own, then that stage's changes.
	local roles: { Roles } = {}
	for stage, over in recipe.roles do
		local merged = table.clone(base.roles[math.min(stage, #base.roles)])
		for _, layer in { recipe.roles[1], over } do
			for role, value in layer do
				merged[role] = value
			end
		end
		roles[stage] = merged
	end
	local skip = recipe.skip or {}
	return {
		roles = roles,
		antenna = base.antenna,
		topper = base.topper,
		build = function(h, stage, add)
			base.build(h, stage, function(role, shape, size, cframe, name, text)
				if not skip[name or ""] then
					add(role, shape, size, cframe, name, text)
				end
			end)
			recipe.extra(h, stage, add)
		end,
	}
end

for _, def in CarCatalog.ordered() do
	local fusion = def.Fusion
	local recipe = FUSED[def.Id]
	local base = if fusion then designs[fusion.Base] else nil
	if recipe and base then
		designs[def.Id] = fusedDesign(recipe, base)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Hats (see Cosmetics). Each is built around the middle of its brim, sitting on the car's roof.
---------------------------------------------------------------------------------------------------------------

type HatAdd = (name: string, shape: Shape, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?) -> ()

-- A cone made of stacked discs, from `radius` at the bottom to a point, in `colors` from the bottom up.
local function stackedCone(put: HatAdd, name: string, y: number, radius: number, height: number, colors: { Color3 })
	local layers = #colors
	local step = height / layers
	for i, color in colors do
		local r = radius * (1 - (i - 1) / layers) + 0.06
		put(name, "Cylinder", Vector3.new(step, r * 2, r * 2), at(0, y + (i - 0.5) * step, 0) * CYL_ALONG_Y, color)
	end
end

local HATS: { [string]: (put: HatAdd) -> () } = {
	cap = function(put)
		local red, dark = rgb(220, 40, 44), rgb(160, 24, 30)
		put("HatCrown", "Ellipsoid", Vector3.new(1.5, 1.05, 1.5), at(0, 0.1, 0.1), red)
		put("HatBrim", "Ellipsoid", Vector3.new(1.15, 0.12, 1.2), at(0, 0.1, -0.75), dark)
		put("HatButton", "Ball", Vector3.one * 0.24, at(0, 0.62, 0.1), rgb(255, 255, 255))
		put("HatBadge", "Ellipsoid", Vector3.new(0.5, 0.36, 0.1), at(0, 0.34, -0.63), rgb(255, 255, 255))
	end,
	party = function(put)
		local pink, yellow = rgb(255, 92, 170), rgb(255, 214, 64)
		stackedCone(put, "HatCone", 0, 0.62, 1.5, { pink, yellow, pink, yellow, pink })
		put("HatPompom", "Ball", Vector3.one * 0.42, at(0, 1.62, 0), rgb(255, 255, 255))
	end,
	cone = function(put)
		local orange, white = rgb(255, 120, 30), rgb(250, 250, 250)
		put("HatBase", "Block", Vector3.new(1.4, 0.14, 1.4), at(0, 0.07, 0), rgb(30, 30, 34))
		stackedCone(put, "HatCone", 0.14, 0.55, 1.5, { orange, white, orange, white, orange })
	end,
	tophat = function(put)
		local black = rgb(26, 26, 30)
		put("HatBrim", "Cylinder", Vector3.new(0.12, 1.9, 1.9), at(0, 0.06, 0) * CYL_ALONG_Y, black)
		put("HatCrown", "Cylinder", Vector3.new(1.3, 1.25, 1.25), at(0, 0.75, 0) * CYL_ALONG_Y, black)
		put("HatBand", "Cylinder", Vector3.new(0.24, 1.29, 1.29), at(0, 0.28, 0) * CYL_ALONG_Y, rgb(210, 36, 44))
	end,
	chick = function(put)
		local yellow = rgb(255, 222, 70)
		put("HatShell", "Ellipsoid", Vector3.new(1.5, 0.9, 1.5), at(0, 0.2, 0), rgb(250, 248, 240))
		put("HatChick", "Ball", Vector3.one * 1.0, at(0, 0.72, 0.05), yellow)
		put("HatChickHead", "Ball", Vector3.one * 0.78, at(0, 1.35, -0.1), yellow)
		put("HatBeak", "Ellipsoid", Vector3.new(0.3, 0.18, 0.36), at(0, 1.31, -0.52), rgb(255, 140, 30))
		for _, side in { -1, 1 } do
			put("HatEye", "Ball", Vector3.one * 0.14, at(side * 0.17, 1.45, -0.43), rgb(20, 20, 26))
		end
	end,
	unicorn = function(put)
		put("HatRing", "Cylinder", Vector3.new(0.14, 1.1, 1.1), at(0, 0.07, 0) * CYL_ALONG_Y, rgb(255, 140, 220))
		local tilt = at(0, 0.1, 0) * CFrame.Angles(math.rad(-18), 0, 0)
		local colors = { rgb(255, 255, 255), rgb(255, 214, 90), rgb(255, 255, 255), rgb(255, 214, 90) }
		for i, color in colors do
			local r = 0.34 * (1 - (i - 1) / #colors) + 0.05
			put(
				"HatHorn",
				"Cylinder",
				Vector3.new(0.4, r * 2, r * 2),
				tilt * at(0, (i - 0.5) * 0.4, 0) * CYL_ALONG_Y,
				color
			)
		end
		put("HatHornTip", "Ball", Vector3.one * 0.12, tilt * at(0, 1.66, 0), rgb(255, 214, 90), NEON)
	end,
	crown = function(put)
		local gold = rgb(255, 196, 50)
		for i = 0, 9 do
			local angle = i / 10 * math.pi * 2
			put(
				"HatBand",
				"Block",
				Vector3.new(0.42, 0.5, 0.12),
				at(math.sin(angle) * 0.62, 0.25, math.cos(angle) * 0.62) * CFrame.Angles(0, angle, 0),
				gold,
				METAL
			)
		end
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			local x, z = math.sin(angle) * 0.62, math.cos(angle) * 0.62
			put(
				"HatSpike",
				"Block",
				Vector3.new(0.2, 0.4, 0.12),
				at(x, 0.68, z) * CFrame.Angles(0, angle, 0),
				gold,
				METAL
			)
			put("HatSpikeBall", "Ball", Vector3.one * 0.22, at(x, 0.92, z), gold, METAL)
		end
		for i, color in { rgb(230, 30, 60), rgb(40, 120, 255), rgb(230, 30, 60) } do
			local angle = math.pi + (i - 2) * 0.55
			put(
				"HatGem",
				"Ball",
				Vector3.one * 0.2,
				at(math.sin(angle) * 0.69, 0.27, math.cos(angle) * 0.69),
				color,
				NEON
			)
		end
	end,
	trophy = function(put)
		local gold, dark = rgb(255, 200, 60), rgb(70, 50, 30)
		put("HatBase", "Block", Vector3.new(0.9, 0.24, 0.9), at(0, 0.12, 0), dark)
		put("HatStem", "Cylinder", Vector3.new(0.4, 0.26, 0.26), at(0, 0.44, 0) * CYL_ALONG_Y, gold, METAL)
		put("HatCup", "Ellipsoid", Vector3.new(0.95, 0.7, 0.95), at(0, 0.86, 0), gold, METAL)
		put("HatRim", "Cylinder", Vector3.new(0.1, 1.0, 1.0), at(0, 1.16, 0) * CYL_ALONG_Y, gold, METAL)
		for _, side in { -1, 1 } do
			put(
				"HatHandle",
				"Cylinder",
				Vector3.new(0.12, 0.5, 0.5),
				at(side * 0.55, 0.9, 0) * CFrame.Angles(0, math.rad(90), 0),
				gold,
				METAL
			)
		end
		put("HatStar", "Ball", Vector3.one * 0.2, at(0, 0.86, -0.46), rgb(255, 250, 220), NEON)
	end,
	diamond = function(put)
		local ice, white = rgb(140, 220, 255), rgb(235, 250, 255)
		for i = 0, 9 do
			local angle = i / 10 * math.pi * 2
			put(
				"HatBand",
				"Block",
				Vector3.new(0.42, 0.42, 0.12),
				at(math.sin(angle) * 0.62, 0.21, math.cos(angle) * 0.62) * CFrame.Angles(0, angle, 0),
				white,
				METAL
			)
		end
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			local x, z = math.sin(angle) * 0.62, math.cos(angle) * 0.62
			put(
				"HatSpike",
				"Wedge",
				Vector3.new(0.12, 0.5, 0.3),
				at(x, 0.66, z) * CFrame.Angles(0, angle + math.rad(90), 0),
				ice,
				GLASS
			)
			put("HatGem", "Ball", Vector3.one * 0.2, at(x, 0.95, z), ice, NEON)
		end
		put("HatDiamond", "Ball", Vector3.one * 0.38, at(0, 0.62, 0), ice, GLASS)
	end,
}

-- Every hat that can be built (for the tests).
function CarModelBuilder.hats(): { string }
	local list = {}
	for id in HATS do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

---------------------------------------------------------------------------------------------------------------
-- Putting a car together
---------------------------------------------------------------------------------------------------------------

local function makePart(spec: PartSpec, style: Look): BasePart
	local part: BasePart
	local copy = if spec.shape == "Mesh" and spec.mesh then MeshLibrary.copy(spec.mesh) else nil
	if copy then
		part = copy
	elseif spec.shape == "Wedge" then
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
	-- Painted plastic gets a hint of shine, like a toy car's glossy paint.
	part.Reflectance = style.reflectance or (if part.Material == SMOOTH then 0.05 else 0)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = style.material ~= NEON and (style.transparency or 0) < 0.3
	return part
end

-- Paints `text` on a part: on a badge (a flat cylinder) its outward face, on a sign both big faces.
local function paint(part: BasePart, spec: PartSpec, text: string)
	local faces: { Enum.NormalId }
	if spec.shape == "Cylinder" then
		local outward = spec.cframe.XVector:Dot(spec.cframe.Position) >= 0
		faces = { if outward then Enum.NormalId.Right else Enum.NormalId.Left }
	else
		faces = { Enum.NormalId.Front, Enum.NormalId.Back }
	end
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Paint"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Position = UDim2.fromScale(0.05, 0.1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = rgb(200, 36, 30)
		label.Parent = gui
		gui.Parent = part
	end
end

-- The colours for a car at a stage: its own colours (or the stage's theme), then the shared defaults.
local function rolesFor(design: Design, stage: number, teamColor: Color3): (string) -> Look
	local own = design.roles[math.min(stage, #design.roles)]
	local theme = THEMES[stage]
	local base = design.roles[1]
	local team = look(teamColor, NEON)
	return function(role: string): Look
		if role == "team" then
			return team
		end
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

-- Parts that belong to a wheel (and turn with it).
local WHEEL_PARTS: { [string]: boolean } = {
	Wheel = true,
	Sidewall = true,
	Rim = true,
	RimDish = true,
	Spoke = true,
	HubCap = true,
	Tread = true,
}

-- The boost flame colours for each stage.
local FLAMES = {
	[3] = ColorSequence.new(rgb(255, 214, 90), rgb(210, 30, 10)),
	[4] = ColorSequence.new(rgb(196, 140, 255), rgb(60, 220, 255)),
}

-- How high the chassis centre sits above the ground when the car rests on its wheels.
function CarModelBuilder.restHeight(def: CarDef): number
	return -groundY(def.Hitbox)
end

---------------------------------------------------------------------------------------------------------------
-- Smooth meshes
---------------------------------------------------------------------------------------------------------------

-- Hands over the folder the Blender meshes were imported into (nil = there isn't one). Any MeshParts inside it,
-- however deep, are used by name - by the cars here and by the ball (see MeshLibrary).
function CarModelBuilder.setMeshLibrary(folder: Instance?)
	MeshLibrary.set(folder)
end

-- The smooth meshes for a car, if every one of them has been imported (a half-imported car stays all parts).
local function meshSetFor(def: CarDef): CarMeshes.CarMeshSet?
	local set = CarMeshes.Cars[def.Id]
	if not set or #set.meshes == 0 then
		return nil
	end
	for _, info in set.meshes do
		if not MeshLibrary.get(info.name) then
			return nil
		end
	end
	return set
end

-- The parts of a wheel the tyre mesh takes the place of.
local TIRE_REPLACES: { [string]: boolean } = { Sidewall = true }

-- Is this car built with smooth meshes right now?
function CarModelBuilder.usesMeshes(def: CarDef): boolean
	return meshSetFor(def) ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------------------------

-- Every part of a car at a stage (in car space), before any hat or antenna. `meshes` swaps the shell for the
-- smooth meshes when they're available.
local function collectSpecs(def: CarDef, stage: number, meshes: boolean): { PartSpec }
	local design = designs[def.Id] or designs.pizza
	local set = if meshes then meshSetFor(def) else nil
	local replaced = if set then set.replaces else {}
	local tire = if meshes then CarMeshes.Shared.tire else nil
	if tire and not MeshLibrary.get(tire.name) then
		tire = nil
	end
	local specs: { PartSpec } = {}
	design.build(def.Hitbox, stage, function(role, shape, size, cframe, name, text)
		if replaced[name or ""] or (tire and TIRE_REPLACES[name or ""]) then
			return
		end
		if tire and name == "Wheel" then
			-- A treaded tyre instead of a plain cylinder (still called "Wheel", so it turns on its hub).
			table.insert(specs, {
				role = role,
				shape = "Mesh",
				size = size * tire.size,
				cframe = cframe * CFrame.new(tire.center * size),
				name = "Wheel" :: string,
				mesh = tire.name,
			})
			return
		end
		table.insert(specs, { role = role, shape = shape, size = size, cframe = cframe, name = name, text = text })
	end)
	if set then
		for _, info in set.meshes do
			table.insert(specs, {
				role = info.role,
				shape = "Mesh",
				size = info.size,
				cframe = CFrame.new(info.center),
				name = info.name,
				mesh = info.name,
			})
		end
	end
	return specs
end

export type SpecData = {
	name: string,
	role: string,
	shape: string,
	size: Vector3,
	cframe: CFrame,
	text: string?,
}

-- A car's parts as plain data (always the plain-parts version), for the tools that make the meshes.
function CarModelBuilder.specs(def: CarDef, stage: number?): { SpecData }
	local list: { SpecData } = {}
	for _, spec in collectSpecs(def, stage or 1, false) do
		table.insert(list, {
			name = spec.name or "Body",
			role = spec.role,
			shape = spec.shape :: string,
			size = spec.size,
			cframe = spec.cframe,
			text = spec.text,
		})
	end
	return list
end

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
	local teamColor = opts.teamColor or rgb(236, 236, 240)
	local styleOf = rolesFor(design, stage, teamColor)
	local specs = collectSpecs(def, stage, true)
	-- A hat on the roof.
	local hat = if opts.topper then HATS[opts.topper] else nil
	if hat then
		local anchor = CFrame.new(design.topper(hitbox))
		hat(function(name, shape, size, offset, color, material)
			table.insert(specs, {
				role = "hat",
				shape = shape,
				size = size,
				cframe = anchor * offset,
				name = name,
				look = look(color, material),
			})
		end)
	end

	-- A team-coloured ball on an antenna, so teams are easy to tell apart from anywhere on the field.
	local antennaHeight = hitbox.Y + 1.1 - design.antenna.Y
	table.insert(specs, {
		role = "dark",
		shape = "Cylinder",
		size = Vector3.new(antennaHeight, 0.14, 0.14),
		cframe = CFrame.new(design.antenna + Vector3.new(0, antennaHeight / 2, 0)) * CYL_ALONG_Y,
		name = "Antenna",
	})
	table.insert(specs, {
		role = "team",
		shape = "Ball",
		size = Vector3.one * 0.85,
		cframe = CFrame.new(design.antenna + Vector3.new(0, antennaHeight + 0.25, 0)),
		name = "TeamFlag",
	})

	-- In a match the wheels turn: each wheel's parts hang off an invisible hub on a Motor6D, which CarVisuals
	-- spins (and steers, for the front wheels) on every player's screen.
	local hubs: { { centre: Vector3, part: BasePart } } = {}
	if not opts.preview then
		for _, spec in specs do
			if spec.name == "Wheel" then
				local centre = spec.cframe.Position
				local hub: BasePart = Instance.new("Part")
				hub.Name = "WheelHub"
				hub.Size = Vector3.one * 0.4
				hub.CFrame = CFrame.new(centre)
				hub.Transparency = 1
				hub.CanCollide = false
				hub.CanQuery = false
				hub.CanTouch = false
				hub.CastShadow = false
				hub.Massless = true
				hub:SetAttribute("Front", centre.Z < 0)
				hub:SetAttribute("Radius", spec.size.Y / 2)
				local motor = Instance.new("Motor6D")
				motor.Name = "WheelMotor"
				motor.Part0 = chassis
				motor.Part1 = hub
				motor.C0 = CFrame.new(centre)
				motor.Parent = hub
				hub.Parent = model
				table.insert(hubs, { centre = centre, part = hub })
			end
		end
	end
	local function anchorFor(spec: PartSpec): BasePart
		local best: BasePart = chassis
		if WHEEL_PARTS[spec.name or ""] then
			local bestDistance = math.huge
			for _, hub in hubs do
				local distance = (hub.centre - spec.cframe.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = hub.part, distance
				end
			end
		end
		return best
	end

	for _, spec in specs do
		local part = makePart(spec, spec.look or styleOf(spec.role))
		if spec.text then
			paint(part, spec, spec.text)
		end
		if opts.preview then
			part.Anchored = true
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorFor(spec)
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end

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
