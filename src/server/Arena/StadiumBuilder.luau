--!strict
-- The stadium around the arena: tiered stands packed with fans, a roof, floodlight towers and big screens that
-- show the score (ArenaScreens on the client keeps them up to date). None of it touches the game itself.
--
-- The stands on the +X side leave a gap for the lobby deck (GameConfig.Lobby), so players waiting there get
-- the best seats in the house.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local Palette = require(script.Parent.Palette)
local PartKit = require(script.Parent.PartKit)

local StadiumBuilder = {}

type Team = typeof(GameConfig.Teams.Blue)

-- One row of one stand. Rows along the sides run along z; rows behind the goals run along x.
type Row = {
	sideways: boolean,
	front: number, -- world x (sideways) or z of the edge nearest the pitch
	back: number,
	from: number, -- world z (sideways) or x range along the row
	to: number,
	top: number,
}

local arena = GameConfig.Arena
local lobby = GameConfig.Lobby
local UP = Vector3.yAxis
local CONCRETE = Enum.Material.Concrete
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

local SIDE_FRONT = arena.Width / 2 + arena.WallThickness + 8 -- x where the side stands begin
local END_FRONT = arena.Length / 2 + arena.GoalDepth + arena.WallThickness + 8 -- z where the end stands begin
local ROWS = 16
local ROW_DEPTH = 6
local ROW_RISE = 4
local FIRST_ROW_TOP = 30 -- just over the boards, so the front row can see
local BACK_X = SIDE_FRONT + ROWS * ROW_DEPTH
local BACK_Z = END_FRONT + ROWS * ROW_DEPTH
local ROOF_Y = FIRST_ROW_TOP + ROWS * ROW_RISE + 14
local ROOF_DEPTH = 56
local LOBBY_FRONT = lobby.Center.X - lobby.Size.X / 2
local LOBBY_HALF_Z = lobby.Size.Z / 2

StadiumBuilder.Bounds = Vector2.new(BACK_X + 6, BACK_Z + 6) -- half-size of the whole stadium, seen from above
StadiumBuilder.RoofHeight = ROOF_Y

-- A tiny repeatable random number generator, so the fans sit in the same seats every time.
local seed = 20240917
local function random(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end

local function pick<T>(list: { T }): T
	return list[math.floor(random() * #list) + 1]
end

local function teamForZ(z: number): Team
	local blue = GameConfig.Teams.Blue
	return if (z < 0) == (blue.DefendsSide < 0) then blue else GameConfig.Teams.Orange
end

local function decorProps(name: string, color: Color3, material: Enum.Material?): PartKit.Props
	return { Name = name, Color = color, Material = material, Collide = false, Query = false }
end

local function depthAt(row: Row, t: number): number
	return row.front + (row.back - row.front) * t
end

local function rowPoint(row: Row, s: number, depth: number, y: number): Vector3
	return if row.sideways then Vector3.new(depth, y, s) else Vector3.new(s, y, depth)
end

-- A box in a row's own coordinates (s along the row, depth away from the pitch).
local function rowBox(
	folder: Instance,
	row: Row,
	s0: number,
	s1: number,
	d0: number,
	d1: number,
	y0: number,
	y1: number,
	props: PartKit.Props
): Part
	local a, b = rowPoint(row, s0, d0, y0), rowPoint(row, s1, d1, y1)
	return PartKit.box(folder, a:Min(b), a:Max(b), props)
end

local function buildRow(folder: Instance, crowd: Instance, row: Row, team: Team, shade: number, fanChance: number)
	local seatColor = team.Color:Lerp(Color3.new(1, 1, 1), shade)
	rowBox(
		folder,
		row,
		row.from,
		row.to,
		row.front,
		row.back,
		-0.2,
		row.top,
		decorProps("Step", Palette.Step, CONCRETE)
	)
	rowBox(
		folder,
		row,
		row.from,
		row.to,
		depthAt(row, 0.45),
		depthAt(row, 0.8),
		row.top,
		row.top + 1.1,
		decorProps("Seats", seatColor)
	)
	rowBox(
		folder,
		row,
		row.from,
		row.to,
		depthAt(row, 0.8),
		depthAt(row, 0.95),
		row.top,
		row.top + 2.6,
		decorProps("SeatBacks", seatColor:Lerp(Color3.new(0, 0, 0), 0.18))
	)

	-- Fans: most wear their team's colour.
	local spacing = 4
	local low = math.min(row.from, row.to)
	for i = 0, math.floor(math.abs(row.to - row.from) / spacing) - 1 do
		if random() < fanChance then
			local s = low + (i + 0.5) * spacing + (random() - 0.5) * 1.2
			local depth = depthAt(row, 0.62)
			local bottom = row.top + 1.1
			local height = 2 + random() * 0.7
			local shirt = if random() < 0.6 then team.Color else pick(Palette.Shirts)
			local body = decorProps("Fan", shirt)
			body.Shadow = false
			rowBox(crowd, row, s - 0.8, s + 0.8, depth - 0.5, depth + 0.5, bottom, bottom + height, body)
			PartKit.part(crowd, {
				Name = "FanHead",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.3,
				CFrame = CFrame.new(rowPoint(row, s, depth, bottom + height + 0.55)),
				Color = pick(Palette.Skin),
				Collide = false,
				Query = false,
				Shadow = false,
			})
		end
	end
end

local function buildStands(folder: Instance, crowd: Instance)
	for r = 0, ROWS - 1 do
		local top = FIRST_ROW_TOP + r * ROW_RISE
		local shade = if r % 2 == 0 then 0.1 else 0.22
		local sideFront = SIDE_FRONT + r * ROW_DEPTH
		local endFront = END_FRONT + r * ROW_DEPTH
		local sideReach = endFront + ROW_DEPTH -- side rows run on into the corners
		local fanChance = 0.36 - r * 0.012
		for _, sx in { 1, -1 } do
			local spans = { { -sideReach, 0 }, { 0, sideReach } }
			if sx > 0 and sideFront >= LOBBY_FRONT - 0.01 then
				spans = { { -sideReach, -LOBBY_HALF_Z }, { LOBBY_HALF_Z, sideReach } }
			end
			for _, span in spans do
				buildRow(folder, crowd, {
					sideways = true,
					front = sx * sideFront,
					back = sx * (sideFront + ROW_DEPTH),
					from = span[1],
					to = span[2],
					top = top,
				}, teamForZ((span[1] + span[2]) / 2), shade, fanChance)
			end
		end
		for _, sz in { 1, -1 } do
			buildRow(folder, crowd, {
				sideways = false,
				front = sz * endFront,
				back = sz * (endFront + ROW_DEPTH),
				from = -sideFront,
				to = sideFront,
				top = top,
			}, teamForZ(sz), shade, fanChance)
		end
	end
end

-- The concrete walls behind the top rows, and a roof over the back half of the stands.
local function buildRoof(folder: Instance)
	local fascia = function(low: Vector3, high: Vector3, face: Enum.NormalId, team: Team)
		local part = PartKit.box(folder, low, high, decorProps("Fascia", Palette.Roof))
		PartKit.banner(part, face, {
			{ text = `GO {string.upper(team.Name)}!`, color = team.Color },
			{ text = "⚡ TURBO BALL ⚡", color = Color3.fromRGB(40, 44, 60) },
			{ text = `GO {string.upper(team.Name)}!`, color = team.Color },
		}, { pixelsPerStud = 6, textHeight = 0.7 })
	end
	local roofFront = BACK_X + 4 - ROOF_DEPTH

	for _, sx in { 1, -1 } do
		local spans = { { -(BACK_Z + 6), 0 }, { 0, BACK_Z + 6 } }
		if sx > 0 then
			spans = { { -(BACK_Z + 6), -LOBBY_HALF_Z }, { LOBBY_HALF_Z, BACK_Z + 6 } }
		end
		for _, span in spans do
			local z0, z1 = span[1], span[2]
			local function box(name: string, x0: number, x1: number, y0: number, y1: number, color: Color3, material)
				return PartKit.box(
					folder,
					Vector3.new(math.min(sx * x0, sx * x1), y0, z0),
					Vector3.new(math.max(sx * x0, sx * x1), y1, z1),
					decorProps(name, color, material)
				)
			end
			box("BackWall", BACK_X, BACK_X + 4, -0.2, ROOF_Y, Palette.Concrete, CONCRETE)
			box("Roof", roofFront, BACK_X + 6, ROOF_Y, ROOF_Y + 2.5, Palette.Roof, METAL)
			box("RoofLight", roofFront + 0.5, roofFront + 2.5, ROOF_Y - 0.4, ROOF_Y, Color3.new(1, 1, 1), NEON)
			fascia(
				Vector3.new(math.min(sx * (roofFront - 1), sx * (roofFront + 1)), ROOF_Y - 3.5, z0),
				Vector3.new(math.max(sx * (roofFront - 1), sx * (roofFront + 1)), ROOF_Y + 2.5, z1),
				if sx > 0 then Enum.NormalId.Left else Enum.NormalId.Right,
				teamForZ((z0 + z1) / 2)
			)
		end
	end
	for _, sz in { 1, -1 } do
		local team = teamForZ(sz)
		local function box(name: string, x: number, zz0: number, zz1: number, y0: number, y1: number, color, material)
			return PartKit.box(
				folder,
				Vector3.new(-x, y0, math.min(sz * zz0, sz * zz1)),
				Vector3.new(x, y1, math.max(sz * zz0, sz * zz1)),
				decorProps(name, color, material)
			)
		end
		local zFront = BACK_Z + 4 - ROOF_DEPTH
		box("BackWall", BACK_X, BACK_Z, BACK_Z + 4, -0.2, ROOF_Y, Palette.Concrete, CONCRETE)
		box("Roof", roofFront, zFront, BACK_Z + 6, ROOF_Y, ROOF_Y + 2.5, Palette.Roof, METAL)
		box("RoofLight", roofFront, zFront + 0.5, zFront + 2.5, ROOF_Y - 0.4, ROOF_Y, Color3.new(1, 1, 1), NEON)
		fascia(
			Vector3.new(-roofFront, ROOF_Y - 3.5, math.min(sz * (zFront - 1), sz * (zFront + 1))),
			Vector3.new(roofFront, ROOF_Y + 2.5, math.max(sz * (zFront - 1), sz * (zFront + 1))),
			if sz > 0 then Enum.NormalId.Front else Enum.NormalId.Back,
			team
		)
	end
end

-- A floodlight tower in a corner, its lamps aimed at the middle of the pitch.
local function buildFloodlight(folder: Instance, x: number, z: number)
	local height = ROOF_Y + 52
	PartKit.box(
		folder,
		Vector3.new(x - 2.5, -0.2, z - 2.5),
		Vector3.new(x + 2.5, height, z + 2.5),
		decorProps("Mast", Palette.DarkSteel, METAL)
	)
	local headPosition = Vector3.new(x, height + 8, z)
	local look = (Vector3.new(0, 0, 0) - headPosition).Unit
	local right = look:Cross(UP).Unit
	local head = CFrame.fromMatrix(headPosition, right, right:Cross(look))
	local props = decorProps("LampFrame", Palette.DarkSteel, METAL)
	props.CFrame = head
	props.Size = Vector3.new(30, 17, 2.5)
	PartKit.part(folder, props)
	for i = 0, 3 do
		for j = 0, 2 do
			local lamp = decorProps("Lamp", Color3.fromRGB(255, 250, 235), NEON)
			lamp.CFrame = head * CFrame.new(-10.5 + i * 7, -5 + j * 5, -1.4)
			lamp.Size = Vector3.new(6, 4, 0.4)
			lamp.Shadow = false
			PartKit.part(folder, lamp)
		end
	end
end

-- A giant screen. Its labels are named so ArenaScreens can fill in the score.
local function buildScreen(folder: Instance, centre: Vector3, facing: Vector3, width: number, height: number)
	local cf = CFrame.fromMatrix(centre, facing:Cross(UP), UP)
	local frameProps = decorProps("ScreenFrame", Palette.DarkSteel, METAL)
	frameProps.CFrame = cf
	frameProps.Size = Vector3.new(width + 3, height + 3, 3)
	local frame = PartKit.part(folder, frameProps)
	-- Legs down to the roof.
	for _, side in { -1, 1 } do
		local foot = cf * Vector3.new(side * width * 0.3, -height / 2, 0)
		PartKit.box(
			folder,
			Vector3.new(foot.X - 1, ROOF_Y + 2.5, foot.Z - 1),
			Vector3.new(foot.X + 1, foot.Y, foot.Z + 1),
			decorProps("ScreenLeg", Palette.DarkSteel, METAL)
		)
	end
	local screenProps = decorProps("Jumbotron", Palette.Screen)
	screenProps.CFrame = cf * CFrame.new(0, 0, -1.6)
	screenProps.Size = Vector3.new(width, height, 0.4)
	local screen = PartKit.part(folder, screenProps)
	local gui = PartKit.screen(screen, Enum.NormalId.Front, Palette.Screen, 8)
	local blue, orange = GameConfig.Teams.Blue, GameConfig.Teams.Orange
	local white = Color3.new(1, 1, 1)
	PartKit.label(gui, "BlueName", string.upper(blue.Name), blue.Color, Vector2.new(0.17, 0.17), Vector2.new(0.28, 0.2))
	PartKit.label(
		gui,
		"OrangeName",
		string.upper(orange.Name),
		orange.Color,
		Vector2.new(0.83, 0.17),
		Vector2.new(0.28, 0.2)
	)
	PartKit.label(gui, "BlueScore", "0", white, Vector2.new(0.17, 0.58), Vector2.new(0.26, 0.52))
	PartKit.label(gui, "OrangeScore", "0", white, Vector2.new(0.83, 0.58), Vector2.new(0.26, 0.52))
	PartKit.label(gui, "Clock", "5:00", white, Vector2.new(0.5, 0.42), Vector2.new(0.36, 0.4))
	PartKit.label(gui, "Message", "TURBO BALL", Palette.Gold, Vector2.new(0.5, 0.82), Vector2.new(0.36, 0.16))
	return frame
end

function StadiumBuilder.build(): Folder
	seed = 20240917
	local folder = Instance.new("Folder")
	folder.Name = "Stadium"
	local crowd = Instance.new("Folder")
	crowd.Name = "Crowd"
	crowd.Parent = folder
	local screens = Instance.new("Folder")
	screens.Name = "Screens"
	screens.Parent = folder

	buildStands(folder, crowd)
	buildRoof(folder)
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			buildFloodlight(folder, sx * (BACK_X + 16), sz * (BACK_Z + 16))
		end
	end

	-- One big screen over each end, and one over the far side facing the lobby.
	local roofFront = BACK_X + 4 - ROOF_DEPTH
	local screenY = ROOF_Y + 6 + 16
	for _, sz in { 1, -1 } do
		buildScreen(screens, Vector3.new(0, screenY, sz * (BACK_Z + 8 - ROOF_DEPTH)), Vector3.new(0, 0, -sz), 64, 30)
	end
	buildScreen(screens, Vector3.new(-(roofFront + 4), screenY + 2, 0), Vector3.xAxis, 72, 34)

	-- Paving under everything, and grass-free corners behind the arena's corner walls.
	PartKit.box(
		folder,
		Vector3.new(-(BACK_X + 30), -1.2, -(BACK_Z + 30)),
		Vector3.new(BACK_X + 30, -0.2, BACK_Z + 30),
		decorProps("Concourse", Palette.DarkConcrete, CONCRETE)
	)
	local halfW, halfL, cut = arena.Width / 2, arena.Length / 2, arena.CornerCut
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local props = decorProps("CornerFill", Palette.DarkConcrete, CONCRETE)
			local vertical = Vector3.new(0, -sx * sz, 0)
			props.CFrame = CFrame.fromMatrix(
				Vector3.new(sx * (halfW - cut / 2), 0, sz * (halfL - cut / 2)),
				vertical,
				Vector3.new(0, 0, -sz)
			)
			props.Size = Vector3.new(0.3, cut, cut)
			PartKit.wedge(folder, props)
		end
	end

	folder.Parent = workspace
	return folder
end

return StadiumBuilder
