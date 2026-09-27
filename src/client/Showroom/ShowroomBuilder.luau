--!strict
-- The garage showroom behind the menus: a dark studio with a polished floor and your car on a glowing
-- turntable under spotlights, with tyres, tools and trophies around the walls. It's only built on your own
-- screen, far away from the stadium.
--
-- The shiny floor is a trick: everything above the floor is built a second time, flipped upside down, under a
-- see-through dark floor. Looking down through the floor you see the flipped copy - which is exactly what a
-- reflection in polished stone looks like.
--
-- Room space: the floor centre is ShowroomBuilder.Origin, +Y is up, and the back wall (with the big screen) is
-- towards +Z. The menu camera stands in front of the car (towards -Z), so the props are on the far side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallModelBuilder = require(Shared.Ball.BallModelBuilder)
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Util.MathUtil)
local PartKit = require(Shared.Build.PartKit)

local ShowroomBuilder = {}

local rgb = Color3.fromRGB

-- The middle of the showroom floor: far from the stadium (and high above it), so neither can see the other.
ShowroomBuilder.Origin = Vector3.new(0, 1500, 3000)
ShowroomBuilder.Radius = 46 -- floor centre to the walls
ShowroomBuilder.Height = 30 -- floor to ceiling
ShowroomBuilder.RingRadius = 7.8 -- the glowing ring the car stands in

local R = ShowroomBuilder.Radius
local H = ShowroomBuilder.Height
local SIDES = 16
local PANEL_WIDTH = 2 * R * math.tan(math.pi / SIDES)
local TRUSS = 15 -- half the size of the lighting rig's square frame
local TRUSS_Y = H - 2.6

local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local CYLINDER = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's axis to point up

local COLORS = {
	Floor = rgb(16, 17, 23),
	Seam = rgb(6, 7, 10),
	Wall = rgb(27, 29, 38),
	WallDark = rgb(20, 21, 28),
	Kick = rgb(78, 82, 94),
	Ceiling = rgb(11, 12, 16),
	Rig = rgb(48, 51, 62),
	Light = rgb(236, 242, 255),
	Strip = rgb(150, 196, 255),
	Skirting = rgb(96, 136, 200),
	Corner = rgb(58, 84, 128),
	Blue = GameConfig.Teams.Blue.Color,
	Orange = GameConfig.Teams.Orange.Color,
	Rubber = rgb(30, 30, 34),
	Chrome = rgb(214, 218, 228),
	Red = rgb(196, 36, 42),
	Gold = rgb(255, 194, 60),
	Wood = rgb(112, 78, 52),
	Door = rgb(140, 146, 158),
	Warm = rgb(255, 178, 100),
}

export type Showroom = {
	folder: Folder,
	origin: Vector3,
	rings: { BasePart }, -- the turntable's glowing ring (tinted to match the car)
	flashLights: { Light }, -- lights that pulse when a car evolves
	screenLine: TextLabel, -- the second line of the big wall screen
	sparkles: ParticleEmitter?, -- bursts around the car (evolving, new car)
}

-- A car standing on the turntable, with its reflection and the soft shadow under it.
export type Display = {
	car: Model,
	reflection: Model,
	-- Turns the car to `yaw` and raises it `lift` studs off the floor (for the drop-in animation).
	place: (yaw: number, lift: number) -> (),
	destroy: () -> (),
}

-- Camera shots for the menus. `angle` is where the camera stands around the car (0 = straight in front, with
-- the big screen behind the car), `focus` is the height of the point on the car it frames, `tilt` aims that
-- many studs higher (which puts the car lower on screen), and `shift` pushes the car sideways on screen (as a
-- fraction of half the screen's width) to make room for the menu.
export type Shot = {
	angle: number,
	distance: number,
	height: number,
	focus: number,
	tilt: number,
	shift: number,
	fov: number,
}

ShowroomBuilder.Shots = {
	menu = {
		angle = math.rad(-16),
		distance = 21,
		height = 4.6,
		focus = 2,
		tilt = 1.8,
		shift = 0.14,
		fov = 40,
	} :: Shot,
	garage = {
		angle = math.rad(-24),
		distance = 22,
		height = 6.2,
		focus = 1.8,
		tilt = 0.3,
		shift = 0,
		fov = 38,
	} :: Shot,
}

-- Where the camera stands for a shot, and the point it looks at. `aspect` is the screen's width / height.
function ShowroomBuilder.camera(shot: Shot, aspect: number): (Vector3, Vector3)
	local origin = ShowroomBuilder.Origin
	local target = origin + Vector3.new(0, shot.focus, 0)
	local position = origin
		+ Vector3.new(math.sin(shot.angle) * shot.distance, shot.height, -math.cos(shot.angle) * shot.distance)
	local look = (target - position).Unit
	local right = look:Cross(Vector3.yAxis).Unit
	local halfWidth = math.tan(math.rad(shot.fov / 2)) * aspect
	local aim = target + Vector3.new(0, shot.tilt, 0) - right * ((target - position).Magnitude * halfWidth * shot.shift)
	return position, aim
end

-- Where a part's mirror image in a floor at height `floorY` goes. The part's own X axis gets flipped too, which
-- keeps the result a proper rotation; blocks, balls, cylinders and wedges all look the same flipped that way,
-- so the copy is an exact mirror image.
function ShowroomBuilder.reflect(cframe: CFrame, floorY: number): CFrame
	local p = cframe.Position
	local x, y, z = cframe.XVector, cframe.YVector, cframe.ZVector
	return CFrame.fromMatrix(
		Vector3.new(p.X, 2 * floorY - p.Y, p.Z),
		Vector3.new(-x.X, x.Y, -x.Z),
		Vector3.new(y.X, -y.Y, y.Z),
		Vector3.new(z.X, -z.Y, z.Z)
	)
end

-- Moves every part of a model by the same amount (like PivotTo, but works on anything).
local function moveModel(model: Model, target: CFrame)
	local primary = model.PrimaryPart
	local offset = target * (if primary then primary.CFrame else CFrame.new()):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = offset * d.CFrame
		end
	end
end

-- Things a reflection doesn't need (and text can't be mirrored anyway).
local function stripForMirror(root: Instance)
	for _, d in root:GetDescendants() do
		if
			d.Parent
			and (
				d:IsA("SurfaceGui")
				or d:IsA("ParticleEmitter")
				or d:IsA("Beam")
				or d:IsA("Attachment")
				or d:IsA("Trail")
			)
		then
			d:Destroy()
		end
	end
end

local function light(className: string, parent: Instance, props: { [string]: any }): Light
	local object = Instance.new(className) :: any
	for key, value in props do
		object[key] = value
	end
	object.Parent = parent
	return object :: Light
end

function ShowroomBuilder.build(): Showroom
	local origin = ShowroomBuilder.Origin
	local folder = Instance.new("Folder")
	folder.Name = "Showroom"
	local room = Instance.new("Folder")
	room.Name = "Room"
	room.Parent = folder
	local reflection = Instance.new("Folder")
	reflection.Name = "Reflection"
	reflection.Parent = folder

	local flashLights: { Light } = {}

	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z))
	end
	-- A frame on the floor against the wall at `angle` (0 = the back wall at +Z, turning towards +X), `inset`
	-- studs in from the wall. Its X axis runs along the wall and its front (-Z) faces the middle of the room.
	local function wall(angle: number, inset: number): CFrame
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		return MathUtil.lookAlong(origin + direction * (R - inset), -direction, Vector3.yAxis)
	end
	local function deco(props: PartKit.Props): Part
		props.Shadow = if props.Shadow == nil then props.Material ~= NEON else props.Shadow
		return PartKit.decor(room, props)
	end
	-- Things lying on the floor itself don't get a reflection.
	local function flat(part: BasePart): BasePart
		part:SetAttribute("NoMirror", true)
		return part
	end

	-------------------------------------------------------------------------------------------------------
	-- Floor: dark polished stone in big tiles, with the turntable's glowing ring in the middle.
	-------------------------------------------------------------------------------------------------------
	local floorSize = (R + 8) * 2
	local floor = flat(deco({
		Name = "Floor",
		Size = Vector3.new(floorSize, 0.4, floorSize),
		CFrame = at(0, -0.2, 0),
		Color = COLORS.Floor,
		Transparency = 0.26,
	}))
	for k = -4, 3 do
		local offset = (k + 0.5) * 13
		flat(deco({
			Name = "Seam",
			Size = Vector3.new(0.14, 0.04, R * 2),
			CFrame = at(offset, 0.02, 0),
			Color = COLORS.Seam,
			Shadow = false,
		}))
		flat(deco({
			Name = "Seam",
			Size = Vector3.new(R * 2, 0.04, 0.14),
			CFrame = at(0, 0.02, offset),
			Color = COLORS.Seam,
			Shadow = false,
		}))
	end

	local rings: { BasePart } = {}
	local function ring(radius: number, width: number, count: number, transparency: number)
		local length = 2 * radius * math.tan(math.pi / count) + 0.04
		for i = 0, count - 1 do
			local angle = (i + 0.5) / count * math.pi * 2
			local position = origin + Vector3.new(math.sin(angle) * radius, 0.06, math.cos(angle) * radius)
			table.insert(
				rings,
				flat(deco({
					Name = "Ring",
					Size = Vector3.new(length, 0.06, width),
					CFrame = CFrame.new(position) * CFrame.Angles(0, angle, 0),
					Color = COLORS.Strip,
					Material = NEON,
					Transparency = transparency,
				}))
			)
		end
	end
	ring(ShowroomBuilder.RingRadius, 0.24, 40, 0)
	ring(ShowroomBuilder.RingRadius + 0.9, 0.08, 40, 0.5)

	-------------------------------------------------------------------------------------------------------
	-- Walls: sixteen dark panels with metal kick plates, a light strip along the bottom, team-coloured bands
	-- up high (blue on one side of the room, orange on the other) and thin lights up every corner.
	-------------------------------------------------------------------------------------------------------
	for i = 0, SIDES - 1 do
		local angle = i / SIDES * math.pi * 2
		local frame = wall(angle, 0)
		local side = math.sin(angle)
		local accent = if side > 0.2 then COLORS.Orange elseif side < -0.2 then COLORS.Blue else COLORS.Strip
		deco({
			Name = "Wall",
			Size = Vector3.new(PANEL_WIDTH + 0.6, H, 2),
			CFrame = frame * CFrame.new(0, H / 2, 1),
			Color = if i % 2 == 0 then COLORS.Wall else COLORS.WallDark,
		})
		deco({
			Name = "KickPlate",
			Size = Vector3.new(PANEL_WIDTH + 0.4, 3.2, 0.5),
			CFrame = frame * CFrame.new(0, 1.6, -0.25),
			Color = COLORS.Kick,
			Material = Enum.Material.DiamondPlate,
		})
		deco({
			Name = "Skirting",
			Size = Vector3.new(PANEL_WIDTH, 0.16, 0.25),
			CFrame = frame * CFrame.new(0, 3.35, -0.35),
			Color = COLORS.Skirting,
			Material = NEON,
		})
		local band = deco({
			Name = "Band",
			Size = Vector3.new(PANEL_WIDTH, 0.4, 0.25),
			CFrame = frame * CFrame.new(0, H - 5, -0.15),
			Color = accent,
			Material = NEON,
		})
		if i % 2 == 1 then
			table.insert(
				flashLights,
				light("PointLight", band, { Color = accent, Range = 18, Brightness = 0.9, Shadows = false })
			)
		end
		-- The far half of the room (the half you see behind the car) gets lamps on the floor shining up the wall.
		if math.cos(angle) > -0.2 then
			local lamp = deco({
				Name = "Uplight",
				Size = Vector3.new(1.4, 0.5, 0.9),
				CFrame = frame * CFrame.new(0, 0.25, -1.4),
				Color = COLORS.Rig,
				Material = METAL,
			})
			light("SpotLight", lamp, {
				Face = Enum.NormalId.Top,
				Color = rgb(200, 220, 255),
				Brightness = 1.6,
				Range = 22,
				Angle = 70,
				Shadows = false,
			})
		end
		local cornerAngle = angle + math.pi / SIDES
		local cornerDirection = Vector3.new(math.sin(cornerAngle), 0, math.cos(cornerAngle))
		if i % 2 == 0 then
			deco({
				Name = "CornerLight",
				Size = Vector3.new(0.25, H - 9.4, 0.25),
				CFrame = CFrame.new(
					origin + cornerDirection * (R / math.cos(math.pi / SIDES) - 0.35) + Vector3.new(0, (H - 1.8) / 2, 0)
				),
				Color = COLORS.Corner,
				Material = NEON,
			})
		end
	end

	-------------------------------------------------------------------------------------------------------
	-- Ceiling and the lighting rig: a square truss holding a big soft light over the car and three
	-- spotlights (key, fill and a rim light from behind), each throwing a faint shaft of light.
	-------------------------------------------------------------------------------------------------------
	deco({
		Name = "Ceiling",
		Size = Vector3.new(floorSize + 4, 1, floorSize + 4),
		CFrame = at(0, H + 0.5, 0),
		Color = COLORS.Ceiling,
	})
	for _, v in { -TRUSS, TRUSS } do
		deco({
			Name = "Truss",
			Size = Vector3.new(1.2, 1.5, TRUSS * 2 + 1.2),
			CFrame = at(v, TRUSS_Y, 0),
			Color = COLORS.Rig,
			Material = METAL,
		})
		deco({
			Name = "Truss",
			Size = Vector3.new(TRUSS * 2 + 1.2, 1.5, 1.2),
			CFrame = at(0, TRUSS_Y, v),
			Color = COLORS.Rig,
			Material = METAL,
		})
		for _, w in { -TRUSS, TRUSS } do
			deco({
				Name = "Rod",
				Size = Vector3.new(0.3, H - TRUSS_Y, 0.3),
				CFrame = at(v, (H + TRUSS_Y) / 2, w),
				Color = COLORS.Rig,
				Material = METAL,
			})
		end
	end
	deco({
		Name = "Softbox",
		Size = Vector3.new(18, 0.8, 10),
		CFrame = at(0, H - 3.2, 0),
		Color = COLORS.Rig,
		Material = METAL,
	})
	for _, x in { -8, 8 } do
		for _, z in { -4, 4 } do
			deco({
				Name = "Rod",
				Size = Vector3.new(0.2, 2.8, 0.2),
				CFrame = at(x, H - 1.4, z),
				Color = COLORS.Rig,
				Material = METAL,
			})
		end
	end
	local softbox = deco({
		Name = "SoftboxLight",
		Size = Vector3.new(17, 0.2, 9),
		CFrame = at(0, H - 3.7, 0),
		Color = COLORS.Light,
		Material = NEON,
	})
	light("SurfaceLight", softbox, {
		Face = Enum.NormalId.Bottom,
		Angle = 80,
		Range = 36,
		Brightness = 1.3,
		Color = rgb(255, 250, 242),
		Shadows = true,
	})

	-- A spotlight at `position` aimed at `target` (both in room space).
	local function spot(
		position: Vector3,
		target: Vector3,
		color: Color3,
		brightness: number,
		angle: number,
		shaft: boolean
	)
		local from = origin + position
		local to = origin + target
		local frame = MathUtil.lookAlong(from, to - from, Vector3.yAxis)
		deco({
			Name = "SpotHousing",
			Size = Vector3.new(1.6, 1.6, 2.4),
			CFrame = frame,
			Color = COLORS.Rig,
			Material = METAL,
		})
		for _, sign in { -1, 1 } do
			deco({
				Name = "BarnDoor",
				Size = Vector3.new(1.6, 0.08, 0.9),
				CFrame = frame * CFrame.new(0, sign * 0.99, -1.61) * CFrame.Angles(sign * math.rad(25), 0, 0),
				Color = COLORS.Rig,
				Material = METAL,
			})
		end
		local lens = deco({
			Name = "Lens",
			Size = Vector3.new(1.3, 1.3, 0.1),
			CFrame = frame * CFrame.new(0, 0, -1.22),
			Color = color,
			Material = NEON,
		})
		local distance = (to - from).Magnitude
		table.insert(
			flashLights,
			light("SpotLight", lens, {
				Face = Enum.NormalId.Front,
				Color = color,
				Brightness = brightness,
				Range = math.min(60, distance + 18),
				Angle = angle,
				Shadows = shaft,
			})
		)
		if shaft then
			-- A faint cone of light in the air: two see-through ribbons, a narrow bright one inside a wide soft one.
			local startPoint = Instance.new("Attachment")
			startPoint.Name = "ShaftStart"
			startPoint.Position = Vector3.new(0, 0, -0.1)
			startPoint.Parent = lens
			local endPoint = Instance.new("Attachment")
			endPoint.Name = "ShaftEnd"
			endPoint.Position = to - floor.CFrame.Position
			endPoint.Parent = floor
			local spread = distance * math.tan(math.rad(angle / 2))
			for layer = 1, 2 do
				local beam = Instance.new("Beam")
				beam.Name = "LightShaft"
				beam.Attachment0 = startPoint
				beam.Attachment1 = endPoint
				beam.Color = ColorSequence.new(color)
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.FaceCamera = true
				beam.Segments = 1
				beam.Width0 = 1.0 * layer
				beam.Width1 = spread * (0.35 + 0.4 * layer)
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.9 + 0.03 * layer),
					NumberSequenceKeypoint.new(0.7, 0.975),
					NumberSequenceKeypoint.new(1, 1),
				})
				beam.Parent = lens
			end
		end
		-- Hang it from the rig.
		deco({
			Name = "Yoke",
			Size = Vector3.new(0.3, TRUSS_Y - position.Y, 0.3),
			CFrame = at(position.X, (TRUSS_Y + position.Y) / 2, position.Z),
			Color = COLORS.Rig,
			Material = METAL,
		})
	end
	spot(Vector3.new(-10, TRUSS_Y - 1.6, -TRUSS), Vector3.new(0, 1, 0), rgb(255, 242, 226), 4, 42, true)
	spot(Vector3.new(11, TRUSS_Y - 1.6, -TRUSS), Vector3.new(0, 1, 0), rgb(206, 222, 255), 2.2, 46, true)
	spot(Vector3.new(0, TRUSS_Y - 1.6, TRUSS), Vector3.new(0, 2, 0), rgb(255, 255, 255), 3.4, 40, true)

	-- Team-coloured lights on stands either side, grazing the car.
	local function stand(x: number, z: number, color: Color3)
		local base = at(x, 0, z)
		for k = 0, 2 do
			local leg = k / 3 * math.pi * 2
			deco({
				Name = "StandLeg",
				Size = Vector3.new(0.18, 0.18, 2.6),
				CFrame = base * CFrame.Angles(0, leg, 0) * CFrame.new(0, 1.0, 1.0) * CFrame.Angles(math.rad(-50), 0, 0),
				Color = COLORS.Rig,
				Material = METAL,
			})
		end
		deco({
			Name = "StandPole",
			Size = Vector3.new(0.25, 5, 0.25),
			CFrame = base * CFrame.new(0, 2.5, 0),
			Color = COLORS.Rig,
			Material = METAL,
		})
		spot(Vector3.new(x, 5.6, z), Vector3.new(0, 1.4, 0), color, 2.4, 34, false)
	end
	stand(-23, 7, rgb(70, 150, 255))
	stand(23, 7, rgb(255, 150, 60))

	-------------------------------------------------------------------------------------------------------
	-- The big screen on the back wall.
	-------------------------------------------------------------------------------------------------------
	local screenFrame = wall(math.rad(22.5), 0.6) * CFrame.new(0, 14.5, 0)
	local screen = deco({
		Name = "Screen",
		Size = Vector3.new(17, 8.5, 0.6),
		CFrame = screenFrame,
		Color = rgb(6, 7, 12),
	})
	for _, bar in
		{
			{ Vector3.new(0, 4.4, -0.1), Vector3.new(17.6, 0.3, 0.3) },
			{ Vector3.new(0, -4.4, -0.1), Vector3.new(17.6, 0.3, 0.3) },
			{ Vector3.new(-8.65, 0, -0.1), Vector3.new(0.3, 8.5, 0.3) },
			{ Vector3.new(8.65, 0, -0.1), Vector3.new(0.3, 8.5, 0.3) },
		}
	do
		deco({
			Name = "ScreenFrame",
			Size = bar[2],
			CFrame = screenFrame * CFrame.new(bar[1]),
			Color = COLORS.Strip,
			Material = NEON,
		})
	end
	local gui = PartKit.screen(screen, Enum.NormalId.Front, rgb(9, 11, 20), 20)
	gui.Brightness = 1.6
	local title = PartKit.label(
		gui,
		"Title",
		"TURBO BALL",
		COLORS.Gold,
		Vector2.new(0.5, 0.4),
		Vector2.new(0.86, 0.4),
		Enum.Font.LuckiestGuy
	)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(rgb(255, 240, 150), rgb(255, 150, 40))
	shine.Rotation = 90
	shine.Parent = title
	local screenLine = PartKit.label(
		gui,
		"Line",
		"YOUR GARAGE",
		rgb(190, 214, 255),
		Vector2.new(0.5, 0.76),
		Vector2.new(0.8, 0.14),
		Enum.Font.GothamBlack
	)

	-------------------------------------------------------------------------------------------------------
	-- Garage things around the far walls.
	-------------------------------------------------------------------------------------------------------
	-- Stacks of tyres.
	local tyres = wall(math.rad(45), 0.2)
	local function tyre(frame: CFrame)
		deco({
			Name = "Tyre",
			Shape = CYLINDER,
			Size = Vector3.new(1.7, 5.2, 5.2),
			CFrame = frame,
			Color = COLORS.Rubber,
			Material = Enum.Material.Rubber,
		})
		deco({
			Name = "TyreHole",
			Shape = CYLINDER,
			Size = Vector3.new(1.74, 3.2, 3.2),
			CFrame = frame,
			Color = rgb(10, 10, 12),
			Material = Enum.Material.Rubber,
		})
	end
	for _, stack in { { x = -4.6, count = 4 }, { x = 0.9, count = 3 } } do
		for k = 0, stack.count - 1 do
			tyre(tyres * CFrame.new(stack.x, 0.86 + k * 1.72, -3.2) * UPRIGHT)
		end
		deco({
			Name = "Rim",
			Shape = CYLINDER,
			Size = Vector3.new(0.3, 3.4, 3.4),
			CFrame = tyres * CFrame.new(stack.x, stack.count * 1.72 + 0.12, -3.2) * UPRIGHT,
			Color = COLORS.Chrome,
			Material = METAL,
		})
	end
	tyre(tyres * CFrame.new(5.8, 2.56, -1.6) * CFrame.Angles(math.rad(12), 0, 0) * CFrame.Angles(0, math.pi / 2, 0))

	-- A roller door with warm daylight leaking under it.
	local door = wall(math.rad(67.5), 0.3)
	for k = 0, 12 do
		deco({
			Name = "DoorSlat",
			Size = Vector3.new(15, 0.92, 0.35),
			CFrame = door * CFrame.new(0, 0.62 + k, 0),
			Color = COLORS.Door,
			Material = METAL,
		})
	end
	for _, x in { -7.9, 7.9 } do
		deco({
			Name = "DoorRail",
			Size = Vector3.new(0.7, 14, 0.8),
			CFrame = door * CFrame.new(x, 7, 0),
			Color = COLORS.Rig,
			Material = METAL,
		})
	end
	deco({
		Name = "DoorBox",
		Size = Vector3.new(16.6, 1.8, 1.6),
		CFrame = door * CFrame.new(0, 14.2, -0.3),
		Color = COLORS.Rig,
		Material = METAL,
	})
	local gap = deco({
		Name = "DoorGap",
		Size = Vector3.new(15, 0.14, 0.2),
		CFrame = door * CFrame.new(0, 0.08, -0.1),
		Color = COLORS.Warm,
		Material = NEON,
	})
	light("PointLight", gap, { Color = COLORS.Warm, Range = 10, Brightness = 1.2, Shadows = false })
	for _, x in { -7.2, 7.2 } do
		flat(deco({
			Name = "FloorLine",
			Size = Vector3.new(0.35, 0.04, 6),
			CFrame = door * CFrame.new(x, 0.03, -3.5),
			Color = COLORS.Gold,
			Shadow = false,
		}))
	end

	-- A red tool cabinet and a workbench with tools hanging on a pegboard.
	local bench = wall(math.rad(90), 0.3)
	local cabinet = bench * CFrame.new(-5.6, 0, -1.8)
	deco({
		Name = "ToolCabinet",
		Size = Vector3.new(5, 6, 3),
		CFrame = cabinet * CFrame.new(0, 3.5, 0),
		Color = COLORS.Red,
		Material = METAL,
	})
	deco({
		Name = "CabinetTop",
		Size = Vector3.new(5.1, 0.2, 3.1),
		CFrame = cabinet * CFrame.new(0, 6.6, 0),
		Color = COLORS.Kick,
		Material = Enum.Material.DiamondPlate,
	})
	for k = 0, 4 do
		local y = 1.1 + k * 1.1
		deco({
			Name = "DrawerGap",
			Size = Vector3.new(4.7, 0.06, 0.06),
			CFrame = cabinet * CFrame.new(0, y + 0.52, -1.52),
			Color = rgb(60, 12, 14),
		})
		deco({
			Name = "Handle",
			Size = Vector3.new(2.8, 0.16, 0.16),
			CFrame = cabinet * CFrame.new(0, y + 0.25, -1.58),
			Color = COLORS.Chrome,
			Material = METAL,
		})
	end
	for _, x in { -2.1, 2.1 } do
		for _, z in { -1.1, 1.1 } do
			deco({
				Name = "Caster",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7,
				CFrame = cabinet * CFrame.new(x, 0.35, z),
				Color = rgb(20, 20, 24),
			})
		end
	end
	local workbench = bench * CFrame.new(3.6, 0, -1.7)
	deco({
		Name = "BenchTop",
		Size = Vector3.new(8, 0.5, 3),
		CFrame = workbench * CFrame.new(0, 3.3, 0),
		Color = COLORS.Wood,
		Material = Enum.Material.WoodPlanks,
	})
	deco({
		Name = "BenchShelf",
		Size = Vector3.new(7.6, 0.2, 2.6),
		CFrame = workbench * CFrame.new(0, 0.9, 0),
		Color = COLORS.Rig,
		Material = METAL,
	})
	for _, x in { -3.7, 3.7 } do
		for _, z in { -1.3, 1.3 } do
			deco({
				Name = "BenchLeg",
				Size = Vector3.new(0.35, 3.05, 0.35),
				CFrame = workbench * CFrame.new(x, 1.53, z),
				Color = COLORS.Rig,
				Material = METAL,
			})
		end
	end
	deco({
		Name = "Toolbox",
		Size = Vector3.new(2.2, 1.1, 1.2),
		CFrame = workbench * CFrame.new(-2, 4.1, 0.2),
		Color = COLORS.Red,
		Material = METAL,
	})
	deco({
		Name = "Vise",
		Size = Vector3.new(1.2, 0.9, 0.8),
		CFrame = workbench * CFrame.new(2.6, 4.0, -0.7),
		Color = rgb(40, 60, 110),
		Material = METAL,
	})
	deco({
		Name = "Pegboard",
		Size = Vector3.new(8.6, 5, 0.2),
		CFrame = workbench * CFrame.new(0, 7, 1.5),
		Color = rgb(196, 186, 166),
		Material = Enum.Material.Plaster,
	})
	for k, tool in
		{
			{ x = -3, length = 2.6, color = COLORS.Chrome }, -- spanners of different sizes
			{ x = -2.2, length = 2.2, color = COLORS.Chrome },
			{ x = -1.5, length = 1.8, color = COLORS.Chrome },
			{ x = 0, length = 2.4, color = COLORS.Red }, -- screwdrivers
			{ x = 0.7, length = 2.4, color = rgb(250, 200, 40) },
			{ x = 1.4, length = 2.4, color = rgb(40, 120, 230) },
			{ x = 2.8, length = 3.0, color = COLORS.Wood }, -- a hammer
		}
	do
		local top = workbench * CFrame.new(tool.x, 8.6, 1.3)
		deco({
			Name = "Tool",
			Size = Vector3.new(0.22, tool.length, 0.14),
			CFrame = top * CFrame.new(0, -tool.length / 2, 0),
			Color = tool.color,
			Material = if tool.color == COLORS.Chrome then METAL else Enum.Material.SmoothPlastic,
		})
		if k == 7 then
			deco({
				Name = "HammerHead",
				Size = Vector3.new(1.1, 0.4, 0.3),
				CFrame = top,
				Color = COLORS.Rig,
				Material = METAL,
			})
		elseif k <= 3 then
			deco({
				Name = "SpannerEnd",
				Shape = CYLINDER,
				Size = Vector3.new(0.14, 0.55, 0.55),
				CFrame = top * CFrame.Angles(0, math.pi / 2, 0),
				Color = tool.color,
				Material = METAL,
			})
		end
	end

	-- Trophies on a shelf, with a warm light on them.
	local shelf = wall(0, 0.2)
	local plank = deco({
		Name = "Shelf",
		Size = Vector3.new(11, 0.4, 2.2),
		CFrame = shelf * CFrame.new(0, 8, -1.1),
		Color = COLORS.Wood,
		Material = Enum.Material.WoodPlanks,
	})
	light("PointLight", plank, { Color = rgb(255, 214, 140), Range = 9, Brightness = 1.4, Shadows = false })
	for _, x in { -4.5, 4.5 } do
		deco({
			Name = "Bracket",
			Size = Vector3.new(0.3, 1.2, 1.8),
			CFrame = shelf * CFrame.new(x, 7.2, -0.9),
			Color = COLORS.Rig,
			Material = METAL,
		})
	end
	local function trophy(base: CFrame, s: number)
		deco({
			Name = "TrophyBase",
			Size = Vector3.new(1.4, 0.7, 1.4) * s,
			CFrame = base * CFrame.new(0, 0.35 * s, 0),
			Color = rgb(30, 30, 36),
			Material = Enum.Material.Marble,
		})
		deco({
			Name = "TrophyStem",
			Shape = CYLINDER,
			Size = Vector3.new(1.0, 0.35, 0.35) * s,
			CFrame = base * CFrame.new(0, 1.2 * s, 0) * UPRIGHT,
			Color = COLORS.Gold,
			Material = METAL,
		})
		deco({
			Name = "TrophyCup",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.7 * s,
			CFrame = base * CFrame.new(0, 2.25 * s, 0),
			Color = COLORS.Gold,
			Material = METAL,
		})
		deco({
			Name = "TrophyRim",
			Shape = CYLINDER,
			Size = Vector3.new(0.2, 1.8, 1.8) * s,
			CFrame = base * CFrame.new(0, 2.75 * s, 0) * UPRIGHT,
			Color = COLORS.Gold,
			Material = METAL,
		})
		for _, x in { -1, 1 } do
			deco({
				Name = "TrophyHandle",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.55 * s,
				CFrame = base * CFrame.new(x * 0.95 * s, 2.35 * s, 0),
				Color = COLORS.Gold,
				Material = METAL,
			})
		end
	end
	trophy(shelf * CFrame.new(-3.2, 8.2, -1.1), 1)
	trophy(shelf * CFrame.new(0, 8.2, -1.1), 1.35)
	trophy(shelf * CFrame.new(3.2, 8.2, -1.1), 1)

	-- The match ball on a glowing plinth.
	local plinth = wall(math.rad(-22.5), 7)
	deco({
		Name = "Plinth",
		Shape = CYLINDER,
		Size = Vector3.new(1.2, 8, 8),
		CFrame = plinth * CFrame.new(0, 0.6, 0) * UPRIGHT,
		Color = rgb(24, 26, 34),
		Material = METAL,
	})
	local plinthGlow = deco({
		Name = "PlinthGlow",
		Shape = CYLINDER,
		Size = Vector3.new(0.2, 8.3, 8.3),
		CFrame = plinth * CFrame.new(0, 1.0, 0) * UPRIGHT,
		Color = COLORS.Strip,
		Material = NEON,
	})
	light("PointLight", plinthGlow, { Color = COLORS.Strip, Range = 9, Brightness = 1, Shadows = false })
	local ball = BallModelBuilder.build()
	moveModel(ball, plinth * CFrame.new(0, 1.2 + GameConfig.Ball.Radius, 0) * CFrame.Angles(0.4, 0.7, 0.2))
	ball.Parent = room

	-- A rack of shiny spare wheels.
	local rack = wall(math.rad(-45), 0.2)
	for _, y in { 2.2, 6.2 } do
		deco({
			Name = "RackShelf",
			Size = Vector3.new(11, 0.3, 2.4),
			CFrame = rack * CFrame.new(0, y - 1.95, -1.2),
			Color = COLORS.Rig,
			Material = METAL,
		})
		for k = -1, 1 do
			local wheel = rack * CFrame.new(k * 3.5, y, -1.2) * CFrame.Angles(0, math.pi / 2, 0)
			deco({
				Name = "SpareTyre",
				Shape = CYLINDER,
				Size = Vector3.new(1.2, 3.6, 3.6),
				CFrame = wheel,
				Color = COLORS.Rubber,
				Material = Enum.Material.Rubber,
			})
			deco({
				Name = "SpareRim",
				Shape = CYLINDER,
				Size = Vector3.new(1.3, 2.3, 2.3),
				CFrame = wheel,
				Color = if k == 0 then COLORS.Gold else COLORS.Chrome,
				Material = METAL,
			})
		end
	end
	for _, x in { -5.4, 5.4 } do
		deco({
			Name = "RackPost",
			Size = Vector3.new(0.3, 8.4, 0.3),
			CFrame = rack * CFrame.new(x, 4.2, -1.2),
			Color = COLORS.Rig,
			Material = METAL,
		})
	end

	-- Team banners hanging on the walls.
	for _, banner in { { angle = 45, color = COLORS.Orange }, { angle = 0, color = COLORS.Blue } } do
		local frame = wall(math.rad(banner.angle), 0.4) * CFrame.new(0, H - 12, 0)
		local cloth = deco({
			Name = "Banner",
			Size = Vector3.new(5.5, 12, 0.2),
			CFrame = frame,
			Color = banner.color,
			Material = Enum.Material.Fabric,
		})
		deco({
			Name = "BannerStripe",
			Size = Vector3.new(5.52, 0.6, 0.22),
			CFrame = frame * CFrame.new(0, -4.2, 0),
			Color = rgb(245, 245, 250),
			Material = Enum.Material.Fabric,
		})
		deco({
			Name = "BannerRod",
			Shape = CYLINDER,
			Size = Vector3.new(6.4, 0.3, 0.3),
			CFrame = frame * CFrame.new(0, 6.1, -0.1),
			Color = COLORS.Gold,
			Material = METAL,
		})
		local sign = PartKit.screen(cloth, Enum.NormalId.Front, nil, 20)
		sign.LightInfluence = 1
		PartKit.label(sign, "Ball", "⚽", rgb(255, 255, 255), Vector2.new(0.5, 0.3), Vector2.new(0.7, 0.3))
		PartKit.label(
			sign,
			"Team",
			if banner.color == COLORS.Blue then "BLUE" else "ORANGE",
			rgb(255, 255, 255),
			Vector2.new(0.5, 0.56),
			Vector2.new(0.84, 0.12),
			Enum.Font.GothamBlack
		)
	end

	-- Oil drums in team colours.
	local drums = wall(math.rad(112.5), 0.2)
	for k, x in { -3.4, 0.2, 3.8 } do
		local base = drums * CFrame.new(x, 2.1, -2.4 - (k % 2) * 0.8)
		local color = if k == 2 then COLORS.Orange else COLORS.Blue
		deco({
			Name = "Drum",
			Shape = CYLINDER,
			Size = Vector3.new(4.2, 3.1, 3.1),
			CFrame = base * UPRIGHT,
			Color = color,
			Material = METAL,
		})
		for _, y in { -1.2, 1.2 } do
			deco({
				Name = "DrumRing",
				Shape = CYLINDER,
				Size = Vector3.new(0.18, 3.22, 3.22),
				CFrame = base * CFrame.new(0, y, 0) * UPRIGHT,
				Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
				Material = METAL,
			})
		end
	end

	-- Dust drifting through the light.
	local dustBox = flat(deco({
		Name = "Dust",
		Size = Vector3.new(34, 18, 34),
		CFrame = at(0, 10, 0),
		Color = COLORS.Floor,
		Transparency = 1,
		Shadow = false,
	}))
	pcall(function()
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "Dust"
		dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		dust.Shape = Enum.ParticleEmitterShape.Box
		dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		dust.Color = ColorSequence.new(rgb(255, 246, 230))
		dust.LightEmission = 0.8
		dust.Size = NumberSequence.new(0.12)
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Lifetime = NumberRange.new(6, 10)
		dust.Rate = 14
		dust.Speed = NumberRange.new(0.2, 0.6)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.RotSpeed = NumberRange.new(-30, 30)
		dust.Parent = dustBox
	end)

	-- Sparkles that burst around the car (see ShowroomController).
	local sparkles: ParticleEmitter? = nil
	local burstPoint = flat(deco({
		Name = "Burst",
		Size = Vector3.new(8, 1, 8),
		CFrame = at(0, 1, 0),
		Color = COLORS.Floor,
		Transparency = 1,
		Shadow = false,
	}))
	pcall(function()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparkles"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(rgb(255, 255, 255))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new(0.1)
		emitter.Lifetime = NumberRange.new(0.8, 1.6)
		emitter.Speed = NumberRange.new(8, 20)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Acceleration = Vector3.new(0, -12, 0)
		emitter.Drag = 1.5
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = 0
		emitter.Parent = burstPoint
		sparkles = emitter
	end)

	-------------------------------------------------------------------------------------------------------
	-- The reflection: a flipped copy of everything that isn't lying on the floor.
	-------------------------------------------------------------------------------------------------------
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("NoMirror") ~= true then
			local copy = d:Clone()
			copy.CFrame = ShowroomBuilder.reflect(d.CFrame, origin.Y)
			stripForMirror(copy)
			copy.Parent = reflection
		end
	end

	return {
		folder = folder,
		origin = origin,
		rings = rings,
		flashLights = flashLights,
		screenLine = screenLine,
		sparkles = sparkles,
	}
end

-- Puts a car on the turntable (tinted `glow` underneath), with its reflection and a soft shadow.
function ShowroomBuilder.display(
	showroom: Showroom,
	def: CarCatalog.CarDef,
	stage: number,
	glow: Color3,
	topper: string?
): Display
	local origin = showroom.origin
	local rest = CarModelBuilder.restHeight(def)
	local car = CarModelBuilder.build(def, { preview = true, stage = stage, teamColor = glow, topper = topper })
	car.Name = "ShowroomCar"
	local mirror = car:Clone()
	mirror.Name = "ShowroomCarReflection"
	for _, d in mirror:GetDescendants() do
		if d.Parent and (d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Attachment")) then
			d:Destroy()
		end
	end

	-- Every part's place relative to the car's centre (the car is built around the origin).
	local carParts: { BasePart } = {}
	local carOffsets: { CFrame } = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(carParts, d)
			table.insert(carOffsets, d.CFrame)
		end
	end
	local mirrorParts: { BasePart } = {}
	local mirrorOffsets: { CFrame } = {}
	for _, d in mirror:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(mirrorParts, d)
			table.insert(mirrorOffsets, ShowroomBuilder.reflect(d.CFrame, -rest))
		end
	end

	-- A soft dark patch where the car meets the floor: three flat ovals, darkest in the middle.
	local shadowParts: { BasePart } = {}
	local shadowOffsets: { CFrame } = {}
	for k, layer in { { 0.9, 0.45 }, { 1.12, 0.7 }, { 1.36, 0.85 } } do
		local part = Instance.new("Part")
		part.Name = "ContactShadow"
		part.Size = Vector3.new(def.Hitbox.X * layer[1], 0.02, def.Hitbox.Z * layer[1])
		part.Color = Color3.new(0, 0, 0)
		part.Transparency = layer[2]
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		part.Parent = car
		table.insert(shadowParts, part)
		table.insert(shadowOffsets, CFrame.new(0, -rest + 0.05 + k * 0.01, 0))
	end

	local function place(yaw: number, lift: number)
		local spin = CFrame.Angles(0, yaw, 0)
		local above = CFrame.new(origin + Vector3.new(0, rest + lift, 0)) * spin
		local below = CFrame.new(origin + Vector3.new(0, rest - lift, 0)) * spin
		local ground = CFrame.new(origin + Vector3.new(0, rest, 0)) * spin
		for i, part in carParts do
			part.CFrame = above * carOffsets[i]
		end
		for i, part in mirrorParts do
			part.CFrame = below * mirrorOffsets[i]
		end
		for i, part in shadowParts do
			part.CFrame = ground * shadowOffsets[i]
		end
	end
	place(0, 0)
	car.Parent = showroom.folder
	mirror.Parent = showroom.folder

	return {
		car = car,
		reflection = mirror,
		place = place,
		destroy = function()
			car:Destroy()
			mirror:Destroy()
		end,
	}
end

return ShowroomBuilder
