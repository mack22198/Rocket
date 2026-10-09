--!strict
-- The winners' podium at the end of a match: a glowing stage in the middle of the pitch with three steps -
-- gold in the middle, silver on the left, bronze on the right (as the camera sees it) - and the top three
-- players' cars standing on them under their names. It's built on your own screen only (PodiumController).
--
-- Podium space: the stage centre is PodiumBuilder.Origin and the cars face -Z, towards the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Util.MathUtil)
local PartKit = require(Shared.Build.PartKit)

local PodiumBuilder = {}

export type Entry = {
	name: string,
	team: string,
	carId: string,
	stage: number,
	points: number,
	topper: string?,
}

export type Podium = {
	model: Model,
	cars: { Model },
}

local rgb = Color3.fromRGB

PodiumBuilder.Origin = Vector3.new(0, 0, 0)
PodiumBuilder.StageRadius = 21

-- The three steps: 1st in the middle, 2nd on +X (the camera's left), 3rd on -X (its right).
PodiumBuilder.Steps = {
	{ x = 0, height = 6, color = rgb(255, 200, 60), label = "1", yaw = 0 },
	{ x = 12.5, height = 3.8, color = rgb(205, 214, 232), label = "2", yaw = math.rad(16) },
	{ x = -12.5, height = 2.2, color = rgb(222, 140, 74), label = "3", yaw = math.rad(-16) },
}

local STAGE_TOP = 0.5
local PLATE = 0.35 -- the medal-coloured plate on top of each step

-- Moves every part of a model by the same amount (like PivotTo, but works everywhere).
local function moveModel(model: Model, target: CFrame)
	local primary = model.PrimaryPart
	local offset = target * (if primary then primary.CFrame else CFrame.new()):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = offset * d.CFrame
		end
	end
end

local function decor(parent: Instance, props: PartKit.Props): Part
	return PartKit.decor(parent, props)
end

-- A name tag floating over a car on the podium.
local function nameTag(chassis: BasePart, rank: number, entry: Entry)
	local tag = Instance.new("BillboardGui")
	tag.Name = "PodiumTag"
	tag.Size = UDim2.fromOffset(230, if rank == 1 then 86 else 58)
	tag.StudsOffset = Vector3.new(0, if rank == 1 then 7.5 else 6, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = chassis
	local teamInfo = (GameConfig.Teams :: any)[entry.team]
	local color = if teamInfo then teamInfo.Color else rgb(255, 255, 255)
	local lines: { { text: string, color: Color3, height: number } } = {}
	if rank == 1 then
		table.insert(lines, { text = "MVP", color = rgb(255, 214, 90), height = 30 })
	end
	table.insert(lines, { text = entry.name, color = color, height = 30 })
	table.insert(lines, { text = `{entry.points} pts`, color = rgb(235, 240, 255), height = 22 })
	local y = 0
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{i}`
		label.Size = UDim2.new(1, 0, 0, line.height)
		label.Position = UDim2.fromOffset(0, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = line.color
		label.TextStrokeTransparency = 0.15
		label.Text = line.text
		label.Parent = tag
		y += line.height + 2
	end
	tag.Parent = chassis
end

-- Builds the podium with up to three cars on it (best first) and returns it.
function PodiumBuilder.build(parent: Instance, entries: { Entry }): Podium
	local origin = PodiumBuilder.Origin
	local model = Instance.new("Model")
	model.Name = "Podium"

	-- The stage: a dark disc with a glowing gold rim.
	decor(model, {
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, (PodiumBuilder.StageRadius + 0.8) * 2, (PodiumBuilder.StageRadius + 0.8) * 2),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rgb(255, 196, 70),
		Material = Enum.Material.Neon,
	})
	decor(model, {
		Name = "Stage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(STAGE_TOP, PodiumBuilder.StageRadius * 2, PodiumBuilder.StageRadius * 2),
		CFrame = CFrame.new(origin + Vector3.new(0, STAGE_TOP / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rgb(72, 78, 122),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.2,
	})

	-- A backdrop behind the steps: a dark screen in a glowing gold frame, with WINNERS across the top.
	local back = origin + Vector3.new(0, 0, 10)
	local backTop = 18
	local screenColor = rgb(22, 24, 40)
	local function plain(name: string): PartKit.Props
		return {
			Name = name,
			Color = screenColor,
			Material = Enum.Material.SmoothPlastic,
			Collide = false,
			Query = false,
		}
	end
	local function glow(name: string): PartKit.Props
		return { Name = name, Color = rgb(255, 196, 70), Material = Enum.Material.Neon, Collide = false, Query = false }
	end
	PartKit.box(model, back + Vector3.new(-21, STAGE_TOP, 0), back + Vector3.new(21, backTop, 1), plain("Backdrop"))
	local banner = PartKit.box(
		model,
		back + Vector3.new(-18, backTop - 5.5, -0.2),
		back + Vector3.new(18, backTop - 0.6, 0),
		plain("Banner")
	)
	PartKit.sign(banner, Enum.NormalId.Front, { "WINNERS" }, {
		color = rgb(255, 214, 90),
		background = screenColor,
		pixelsPerStud = 12,
	})
	local edge = 0.6
	PartKit.box(
		model,
		back + Vector3.new(-21 - edge, backTop, -0.3),
		back + Vector3.new(21 + edge, backTop + edge, 1.2),
		glow("FrameTop")
	)
	PartKit.box(
		model,
		back + Vector3.new(-21 - edge, STAGE_TOP, -0.3),
		back + Vector3.new(-21, backTop, 1.2),
		glow("FrameLeft")
	)
	PartKit.box(
		model,
		back + Vector3.new(21, STAGE_TOP, -0.3),
		back + Vector3.new(21 + edge, backTop, 1.2),
		glow("FrameRight")
	)

	for i, step in PodiumBuilder.Steps do
		local low = origin + Vector3.new(step.x - 5.5, STAGE_TOP, -5)
		local high = origin + Vector3.new(step.x + 5.5, STAGE_TOP + step.height, 5)
		local block = PartKit.box(model, low, high, {
			Name = `Step{i}`,
			Color = rgb(64, 72, 112),
			Material = Enum.Material.SmoothPlastic,
			Collide = false,
			Query = false,
		})
		PartKit.sign(block, Enum.NormalId.Front, { step.label }, { color = step.color, pixelsPerStud = 24 })
		PartKit.box(
			model,
			Vector3.new(low.X - 0.2, high.Y, low.Z - 0.2),
			Vector3.new(high.X + 0.2, high.Y + PLATE, high.Z + 0.2),
			{ Name = `Plate{i}`, Color = step.color, Material = Enum.Material.Metal, Collide = false, Query = false }
		)
		-- A glowing strip along the front edge of each step.
		PartKit.box(
			model,
			Vector3.new(low.X, high.Y - 0.3, low.Z - 0.25),
			Vector3.new(high.X, high.Y - 0.1, low.Z - 0.05),
			{ Name = `Strip{i}`, Color = step.color, Material = Enum.Material.Neon, Collide = false, Query = false }
		)
	end

	local cars: { Model } = {}
	for rank, entry in entries do
		local step = PodiumBuilder.Steps[rank]
		if not step then
			break
		end
		local def = CarCatalog.get(entry.carId) or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
		local teamInfo = (GameConfig.Teams :: any)[entry.team]
		local car = CarModelBuilder.build(def, {
			preview = true,
			stage = entry.stage,
			teamColor = if teamInfo then teamInfo.Color else nil,
			topper = entry.topper,
		})
		local top = STAGE_TOP + step.height + PLATE
		local position = origin + Vector3.new(step.x, top + CarModelBuilder.restHeight(def), 0)
		moveModel(car, CFrame.new(position) * CFrame.Angles(0, step.yaw, 0))
		car.Parent = model
		local chassis = car.PrimaryPart
		if chassis then
			nameTag(chassis, rank, entry)
		end
		table.insert(cars, car)
	end

	model.Parent = parent
	return { model = model, cars = cars }
end

-- Where the camera stands `t` seconds into the podium moment: in front of the stage, drifting slowly side to
-- side. Returns the camera's position and the point it looks at.
function PodiumBuilder.camera(t: number): (Vector3, Vector3)
	local focus = PodiumBuilder.Origin + Vector3.new(0, 10, 0)
	local angle = math.sin(t * 0.35) * math.rad(16)
	local distance = 44 - math.min(t, 4) * 1.5 -- eases in a little at the start
	local position = focus + Vector3.new(math.sin(angle) * distance, 7, -math.cos(angle) * distance)
	return position, focus
end

-- The camera as a CFrame (for the game's camera).
function PodiumBuilder.cameraCFrame(t: number): CFrame
	local position, focus = PodiumBuilder.camera(t)
	return MathUtil.lookAlong(position, focus - position, Vector3.yAxis)
end

return PodiumBuilder
