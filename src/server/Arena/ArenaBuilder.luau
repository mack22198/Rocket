--!strict
-- Builds the arena out of parts when the server starts, using the same numbers as ArenaShape
-- (so what you see matches what the ball bounces off).
--
-- Workspace.Arena      = everything cars drive on or bump into (wheel rays only look at this folder)
-- Workspace.ArenaDecor = field lines, trim, glass, goal nets and signs (no collisions, invisible to rays)
--
-- Each wall, from the floor up: the curved ramp, solid boards with adverts, then glass up to the invisible
-- ceiling. StadiumBuilder builds the stands around the arena.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local Palette = require(script.Parent.Palette)
local PartKit = require(script.Parent.PartKit)

local ArenaBuilder = {}

type Team = typeof(GameConfig.Teams.Blue)

-- One straight stretch of wall, described by its inner face at floor level.
type Piece = {
	a: Vector3,
	b: Vector3,
	inward: Vector3, -- horizontal, pointing into the field
	cornerA: boolean, -- ends in a 45 degree corner at a (parts reach past it to close the joint)
	cornerB: boolean,
}

local rgb = Color3.fromRGB
local cfg = GameConfig.Arena
local UP = Vector3.yAxis
local NEON = Enum.Material.Neon

local BOARD_BOTTOM = cfg.CurveRadius -- the ramp covers the wall below this
local BOARD_TOP = cfg.CurveRadius + 10
local HEADER_TOP = BOARD_TOP + 6 -- top of the team sign above each goal
local MITER = math.tan(math.rad(22.5)) -- how far a wall part reaches past a 45 degree corner, per stud of depth
local LINE_WIDTH = 1.2
local LINE_Y = 0.02 -- field markings sit just above the grass
local NET_COLOR = rgb(240, 244, 250)

-- Pretend sponsors on the boards, one for every car.
local ADS: { PartKit.BannerItem } = {
	{ text = "🍕 PIZZA CAR PIZZERIA", color = rgb(255, 196, 84) },
	{ text = "⚡ TURBO BALL ⚡", color = rgb(255, 255, 255) },
	{ text = "🍌 BANANA BOOST JUICE", color = rgb(255, 232, 96) },
	{ text = "🦈 SHARK BITE SNACKS", color = rgb(120, 214, 255) },
	{ text = "🛸 UFO SPACE TOURS", color = rgb(150, 255, 120) },
	{ text = "🏁 KART KINGDOM", color = rgb(120, 255, 170) },
	{ text = "👹 MONSTER MUNCH", color = rgb(255, 128, 128) },
}
local nextAd = 0

local function takeAds(count: number): { PartKit.BannerItem }
	local list = {}
	for _ = 1, count do
		nextAd = nextAd % #ADS + 1
		table.insert(list, ADS[nextAd])
	end
	return list
end

local function teamForSide(side: number): Team
	return if GameConfig.Teams.Blue.DefendsSide == side then GameConfig.Teams.Blue else GameConfig.Teams.Orange
end

-- A painted line on the floor from a to b. By default it reaches half its width past each end so corners close.
local function stripe(
	decor: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	color: Color3,
	material: Enum.Material?,
	exact: boolean?
): Part
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local centre = Vector3.new((a.X + b.X) / 2, LINE_Y, (a.Z + b.Z) / 2)
	return PartKit.decor(decor, {
		Name = name,
		Size = Vector3.new(LINE_WIDTH, 0.2, flat.Magnitude + (if exact then 0 else LINE_WIDTH)),
		CFrame = CFrame.fromMatrix(centre, UP:Cross(flat.Unit), UP),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Shadow = false,
	})
end

local function buildField(arena: Instance, decor: Instance)
	local W, L, R = cfg.Width, cfg.Length, cfg.CurveRadius
	local GW, GD, T = cfg.GoalWidth, cfg.GoalDepth, cfg.WallThickness

	-- Mowed stripes, each half tinted a touch toward its team's colour.
	local stripes = 10
	local stripeLength = L / stripes
	for i = 0, stripes - 1 do
		local z = -L / 2 + stripeLength * (i + 0.5)
		local team = teamForSide(if z < 0 then -1 else 1)
		local base = if i % 2 == 0 then Palette.GrassLight else Palette.GrassDark
		PartKit.part(arena, {
			Name = "Floor",
			Size = Vector3.new(W, 2, stripeLength),
			CFrame = CFrame.new(0, -1, z),
			Color = base:Lerp(team.Color, 0.07),
			Material = Enum.Material.Grass,
		})
	end
	for _, side in { 1, -1 } do
		PartKit.part(arena, {
			Name = "GoalFloor",
			Size = Vector3.new(GW + 2 * T, 2, GD + T),
			CFrame = CFrame.new(0, -1, side * (L / 2 + (GD + T) / 2)),
			Color = Palette.GoalFloor,
		})
	end

	-- The boundary where the flat pitch meets the ramps: the wall outline pulled in by the ramp radius.
	local halfW, halfL = W / 2, L / 2
	local inset = R + LINE_WIDTH / 2
	local sideX = halfW - inset
	local endZ = halfL - inset
	local diagonalSum = halfW + halfL - cfg.CornerCut - inset * math.sqrt(2) -- x + z along the corner boundary
	local mouth = GW / 2 - LINE_WIDTH / 2
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local points = {
				Vector3.new(sx * mouth, 0, sz * (halfL - LINE_WIDTH / 2)),
				Vector3.new(sx * mouth, 0, sz * endZ),
				Vector3.new(sx * (diagonalSum - endZ), 0, sz * endZ),
				Vector3.new(sx * sideX, 0, sz * (diagonalSum - sideX)),
				Vector3.new(sx * sideX, 0, 0),
			}
			for i = 1, #points - 1 do
				stripe(decor, "Touchline", points[i], points[i + 1], Palette.Line)
			end
		end
	end

	stripe(decor, "HalfwayLine", Vector3.new(-sideX, 0, 0), Vector3.new(sideX, 0, 0), Palette.Line)
	local circleRadius = 30
	local circleSegments = 48
	for i = 0, circleSegments - 1 do
		local a0 = i / circleSegments * math.pi * 2
		local a1 = (i + 1) / circleSegments * math.pi * 2
		stripe(
			decor,
			"CenterCircle",
			Vector3.new(math.cos(a0), 0, math.sin(a0)) * circleRadius,
			Vector3.new(math.cos(a1), 0, math.sin(a1)) * circleRadius,
			Palette.Line
		)
	end
	PartKit.disc(decor, Vector3.new(0, LINE_Y, 0), 1.8, 0.2, {
		Name = "CenterSpot",
		Color = Palette.Line,
		Collide = false,
		Query = false,
		Shadow = false,
	})

	for _, side in { 1, -1 } do
		local team = teamForSide(side)
		local boxHalf = GW / 2 + 14
		local front = side * (halfL - 40)
		stripe(decor, "BoxLine", Vector3.new(-boxHalf, 0, front), Vector3.new(boxHalf, 0, front), Palette.Line)
		for _, sx in { 1, -1 } do
			stripe(
				decor,
				"BoxLine",
				Vector3.new(sx * boxHalf, 0, front),
				Vector3.new(sx * boxHalf, 0, side * endZ),
				Palette.Line
			)
		end
		local goalZ = side * (halfL - LINE_WIDTH / 2)
		stripe(
			decor,
			"GoalLine",
			Vector3.new(-(mouth - LINE_WIDTH / 2), 0, goalZ),
			Vector3.new(mouth - LINE_WIDTH / 2, 0, goalZ),
			team.Color,
			NEON,
			true
		)
	end
end

-- One curved ramp, built from flat strips. Where two ramps meet in a 45 degree corner, each strip stops on the
-- corner's bisector (reaching a hair past it, out of sight under the other ramp), so the seams are clean.
local function buildRamp(arena: Instance, ramp: ArenaShape.Ramp, segments: number)
	local R = ramp.radius
	local thickness = 2
	local function crossSection(angle: number): Vector2
		return Vector2.new(R - R * math.sin(angle), R - R * math.cos(angle))
	end
	for i = 0, segments - 1 do
		local p0 = crossSection(i / segments * math.pi / 2)
		local p1 = crossSection((i + 1) / segments * math.pi / 2)
		local mid = (p0 + p1) / 2
		local outward = (mid - Vector2.new(R, R)).Unit -- away from the curve's centre, into the solid
		local centre2D = mid + outward * (thickness / 2)
		local near = math.min(p0.X, p1.X) -- distance from the wall to the strip's nearest edge
		local cornerFrom, cornerTo = ramp.cornerFrom, ramp.cornerTo
		local s0 = if cornerFrom then cornerFrom + MITER * near - 0.05 else ramp.from
		local s1 = if cornerTo then cornerTo - MITER * near + 0.05 else ramp.to
		local centre = ramp.wallPoint + ramp.inward * centre2D.X + UP * centre2D.Y + ramp.along * ((s0 + s1) / 2)
		local surfaceNormal = -(ramp.inward * outward.X + UP * outward.Y)
		PartKit.part(arena, {
			Name = "Ramp",
			Size = Vector3.new(s1 - s0, thickness, (p1 - p0).Magnitude + 0.08),
			CFrame = CFrame.fromMatrix(centre, ramp.along, surfaceNormal),
			Color = Palette.Ramp,
			Material = Enum.Material.Grass,
		})
	end
end

-- A box against a wall piece: `depth` is measured back from the inner face (negative = in front of it), `s`
-- along the piece from a. Unless s is given, pieces ending in a corner reach past it far enough to close the joint.
local function wallBox(
	piece: Piece,
	depth0: number,
	depth1: number,
	y0: number,
	y1: number,
	s0: number?,
	s1: number?
): (CFrame, Vector3)
	local offset = piece.b - piece.a
	local length = offset.Magnitude
	local reach = MITER * math.max(depth1, 0)
	local from = s0 or (if piece.cornerA then -reach else 0)
	local to = s1 or (if piece.cornerB then length + reach else length)
	local centre = piece.a
		+ offset.Unit * ((from + to) / 2)
		- piece.inward * ((depth0 + depth1) / 2)
		+ UP * ((y0 + y1) / 2)
	-- The part's front face looks into the field.
	return CFrame.fromMatrix(centre, piece.inward:Cross(UP), UP), Vector3.new(to - from, y1 - y0, depth1 - depth0)
end

local function buildBoards(arena: Instance, decor: Instance, piece: Piece, team: Team, adverts: number)
	local T = cfg.WallThickness
	local cf, size = wallBox(piece, 0, T, BOARD_BOTTOM, BOARD_TOP)
	local board = PartKit.part(arena, { Name = "Boards", CFrame = cf, Size = size, Color = Palette.Board })
	if adverts > 0 then
		PartKit.banner(board, Enum.NormalId.Front, takeAds(adverts), { pixelsPerStud = 8 })
	end
	-- Concrete behind the ramp (only seen from outside).
	cf, size = wallBox(piece, 0.4, T, 0, BOARD_BOTTOM)
	PartKit.decor(decor, {
		Name = "WallBase",
		CFrame = cf,
		Size = size,
		Color = Palette.DarkConcrete,
		Material = Enum.Material.Concrete,
	})
	-- A glowing strip in the team's colour along the top, and a white line where the ramp ends.
	cf, size = wallBox(piece, -0.15, T + 0.15, BOARD_TOP - 0.45, BOARD_TOP + 0.45)
	PartKit.decor(decor, {
		Name = "BoardTrim",
		CFrame = cf,
		Size = size,
		Color = team.Color,
		Material = NEON,
		Shadow = false,
	})
	cf, size = wallBox(piece, -0.1, 0.5, BOARD_BOTTOM - 0.1, BOARD_BOTTOM + 0.7)
	PartKit.decor(decor, { Name = "RampLip", CFrame = cf, Size = size, Color = Palette.Line, Shadow = false })
end

local function buildGlass(arena: Instance, decor: Instance, piece: Piece, bottom: number, endPosts: boolean)
	local T, H = cfg.WallThickness, cfg.Height
	local cf, size = wallBox(piece, 0, T, bottom, H)
	PartKit.part(arena, {
		Name = "Wall",
		CFrame = cf,
		Size = size,
		Color = Palette.Glass,
		Transparency = 1,
		Shadow = false,
	})
	cf, size = wallBox(piece, 0, 0.4, bottom, H)
	PartKit.decor(decor, {
		Name = "Glass",
		CFrame = cf,
		Size = size,
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.72,
		Shadow = false,
	})
	-- Steel frame: a rim along the top with a light strip under it, and posts behind the glass.
	cf, size = wallBox(piece, -0.6, T + 0.6, H, H + 2.2)
	PartKit.decor(decor, {
		Name = "Rim",
		CFrame = cf,
		Size = size,
		Color = Palette.Steel,
		Material = Enum.Material.Metal,
	})
	cf, size = wallBox(piece, -0.45, -0.1, H - 0.5, H)
	PartKit.decor(decor, {
		Name = "RimLight",
		CFrame = cf,
		Size = size,
		Color = Color3.new(1, 1, 1),
		Material = NEON,
		Shadow = false,
	})
	local length = (piece.b - piece.a).Magnitude
	local count = math.max(1, math.floor(length / 30 + 0.5))
	for k = if endPosts then 0 else 1, if endPosts then count else count - 1 do
		local s = length * k / count
		cf, size = wallBox(piece, T + 0.1, T + 1.3, bottom, H, s - 0.6, s + 0.6)
		PartKit.decor(decor, {
			Name = "Mullion",
			CFrame = cf,
			Size = size,
			Color = Palette.Steel,
			Material = Enum.Material.Metal,
		})
	end
end

-- A steel post covering the outside of a corner joint.
local function buildCornerPost(decor: Instance, vertex: Vector3, inward1: Vector3, inward2: Vector3)
	local outward = -(inward1 + inward2).Unit
	local p = vertex + outward * (cfg.WallThickness / math.cos(math.rad(22.5)) + 0.4)
	local height = cfg.Height + 2.2 - BOARD_TOP
	PartKit.decor(decor, {
		Name = "CornerPost",
		Size = Vector3.new(1.8, height, 1.8),
		CFrame = CFrame.fromMatrix(Vector3.new(p.X, BOARD_TOP + height / 2, p.Z), UP:Cross(outward), UP),
		Color = Palette.Steel,
		Material = Enum.Material.Metal,
	})
end

local function buildWalls(arena: Instance, decor: Instance)
	local halfW, halfL, cut = cfg.Width / 2, cfg.Length / 2, cfg.CornerCut
	local mouth = cfg.GoalWidth / 2 + cfg.WallThickness -- the goal's side walls and header fill up to here

	for _, sx in { 1, -1 } do
		local inward = Vector3.new(-sx, 0, 0)
		-- Side wall: boards in two halves (so each half's trim shows its team), one long run of glass.
		for _, sz in { -1, 1 } do
			buildBoards(arena, decor, {
				a = Vector3.new(sx * halfW, 0, sz * (halfL - cut)),
				b = Vector3.new(sx * halfW, 0, 0),
				inward = inward,
				cornerA = true,
				cornerB = false,
			}, teamForSide(sz), 2)
		end
		buildGlass(arena, decor, {
			a = Vector3.new(sx * halfW, 0, -(halfL - cut)),
			b = Vector3.new(sx * halfW, 0, halfL - cut),
			inward = inward,
			cornerA = true,
			cornerB = true,
		}, BOARD_TOP, false)

		for _, sz in { 1, -1 } do
			local team = teamForSide(sz)
			local diagonal: Piece = {
				a = Vector3.new(sx * halfW, 0, sz * (halfL - cut)),
				b = Vector3.new(sx * (halfW - cut), 0, sz * halfL),
				inward = -Vector3.new(sx, 0, sz).Unit,
				cornerA = true,
				cornerB = true,
			}
			buildBoards(arena, decor, diagonal, team, 1)
			buildGlass(arena, decor, diagonal, BOARD_TOP, false)

			-- End wall beside the goal.
			local endWall: Piece = {
				a = Vector3.new(sx * (halfW - cut), 0, sz * halfL),
				b = Vector3.new(sx * mouth, 0, sz * halfL),
				inward = Vector3.new(0, 0, -sz),
				cornerA = true,
				cornerB = false,
			}
			buildBoards(arena, decor, endWall, team, 1)
			buildGlass(arena, decor, endWall, BOARD_TOP, false)

			buildCornerPost(decor, diagonal.a, inward, diagonal.inward)
			buildCornerPost(decor, diagonal.b, diagonal.inward, endWall.inward)
		end
	end

	-- Glass above each goal's header.
	for _, sz in { 1, -1 } do
		buildGlass(arena, decor, {
			a = Vector3.new(mouth, 0, sz * halfL),
			b = Vector3.new(-mouth, 0, sz * halfL),
			inward = Vector3.new(0, 0, -sz),
			cornerA = false,
			cornerB = false,
		}, HEADER_TOP, true)
	end

	-- The invisible ceiling keeps the ball in.
	local T = cfg.WallThickness
	PartKit.part(arena, {
		Name = "Ceiling",
		Size = Vector3.new(cfg.Width + 2 * T, T, cfg.Length + 2 * (cfg.GoalDepth + T)),
		CFrame = CFrame.new(0, cfg.Height + T / 2, 0),
		Color = Palette.Glass,
		Transparency = 1,
		Shadow = false,
	})
end

-- A grid of thin white bars in front of one inside face of a goal.
local function net(decor: Instance, origin: Vector3, uAxis: Vector3, uLength: number, vAxis: Vector3, vLength: number)
	local spacing = 4
	local function props(): PartKit.Props
		return { Name = "Net", Color = NET_COLOR, Collide = false, Query = false, Shadow = false }
	end
	for k = 1, math.floor(uLength / spacing - 0.01) do
		local p = origin + uAxis * (k * spacing)
		PartKit.between(decor, p, p + vAxis * vLength, 0.25, props())
	end
	for k = 1, math.floor(vLength / spacing - 0.01) do
		local p = origin + vAxis * (k * spacing)
		PartKit.between(decor, p, p + uAxis * uLength, 0.25, props())
	end
end

local function buildGoal(arena: Instance, decor: Instance, side: number)
	local team = teamForSide(side)
	local L, GW, GH, GD, T = cfg.Length, cfg.GoalWidth, cfg.GoalHeight, cfg.GoalDepth, cfg.WallThickness
	local R = cfg.CurveRadius
	local half = GW / 2
	local outer = half + T

	-- World z of a point `depth` studs behind this goal's line.
	local function z(depth: number): number
		return side * (L / 2 + depth)
	end
	local function box(folder: Instance, name: string, low: Vector3, high: Vector3, props: PartKit.Props): Part
		props.Name = name
		return PartKit.box(folder, low:Min(high), low:Max(high), props)
	end
	local function glow(): PartKit.Props
		return { Color = team.Color, Material = NEON, Collide = false, Query = false, Shadow = false }
	end

	-- The goal box: side walls, roof and back in the team's dark colour.
	for _, sx in { 1, -1 } do
		box(arena, "GoalWall", Vector3.new(sx * half, 0, z(0)), Vector3.new(sx * outer, GH, z(GD)), {
			Color = team.DarkColor,
		})
	end
	box(arena, "GoalRoof", Vector3.new(-outer, GH, z(T)), Vector3.new(outer, GH + T, z(GD)), {
		Color = team.DarkColor,
	})
	box(arena, "GoalBack", Vector3.new(-outer, 0, z(GD)), Vector3.new(outer, GH + T, z(GD + T)), {
		Color = team.DarkColor,
	})
	-- The header above the goal mouth, with the team's name on it.
	local header = box(arena, "GoalHeader", Vector3.new(-outer, GH, z(0)), Vector3.new(outer, HEADER_TOP, z(T)), {
		Color = Palette.Board,
	})
	PartKit.sign(header, if side > 0 then Enum.NormalId.Front else Enum.NormalId.Back, {
		`{string.upper(team.Name)} GOAL`,
	}, { color = team.Color, pixelsPerStud = 10 })
	box(
		decor,
		"HeaderTrim",
		Vector3.new(-outer, HEADER_TOP - 0.45, z(-0.15)),
		Vector3.new(outer, HEADER_TOP + 0.45, z(T + 0.15)),
		glow()
	)

	-- Glowing frame: posts and crossbar flush with the wall, and a strip following each ramp's rounded end.
	box(
		decor,
		"Crossbar",
		Vector3.new(-(half + 1.6), GH - 0.15, z(-0.15)),
		Vector3.new(half + 1.6, GH + 1.4, z(1.6)),
		glow()
	)
	for _, sx in { 1, -1 } do
		box(
			decor,
			"GoalPost",
			Vector3.new(sx * (half - 0.15), BOARD_BOTTOM, z(-0.15)),
			Vector3.new(sx * (half + 1.6), GH + 1.4, z(1.6)),
			glow()
		)
		local segments = cfg.CurveSegments
		local function point(angle: number): Vector3
			local u, v = R - R * math.sin(angle), R - R * math.cos(angle)
			return Vector3.new(sx * (half + 0.725), v, z(-u))
		end
		for i = 0, segments - 1 do
			local p0 = point(i / segments * math.pi / 2)
			local p1 = point((i + 1) / segments * math.pi / 2)
			local tangent = (p1 - p0).Unit
			local props = glow()
			props.Name = "GoalEdge"
			props.Size = Vector3.new(1.75, 0.8, (p1 - p0).Magnitude + 0.3)
			props.CFrame = CFrame.fromMatrix((p0 + p1) / 2, Vector3.xAxis, tangent:Cross(Vector3.xAxis), tangent)
			PartKit.part(decor, props)
		end
	end

	-- Nets on the inside faces.
	local inset = 0.2
	net(decor, Vector3.new(-half, 0, z(GD - inset)), Vector3.xAxis, GW, UP, GH)
	for _, sx in { 1, -1 } do
		net(decor, Vector3.new(sx * (half - inset), 0, z(0)), Vector3.new(0, 0, side), GD, UP, GH)
	end
	net(decor, Vector3.new(-half, GH - inset, z(T)), Vector3.xAxis, GW, Vector3.new(0, 0, side), GD - T)

	local lamp = PartKit.decor(decor, {
		Name = "GoalLight",
		Size = Vector3.one,
		CFrame = CFrame.new(0, GH / 2, z(GD - 3)),
		Color = team.Color,
		Transparency = 1,
		Shadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = team.Color
	light.Range = 36
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = lamp
end

-- Builds everything and returns the Arena folder (the one wheel rays should hit) and the math shape.
function ArenaBuilder.build(): (Folder, ArenaShape.Arena)
	local shape = ArenaShape.new(cfg)
	nextAd = 0

	local arena = Instance.new("Folder")
	arena.Name = MatchState.Folders.Arena
	local decor = Instance.new("Folder")
	decor.Name = "ArenaDecor"

	buildField(arena, decor)
	for _, ramp in shape.ramps do
		buildRamp(arena, ramp, cfg.CurveSegments)
	end
	buildWalls(arena, decor)
	for _, side in { 1, -1 } do
		buildGoal(arena, decor, side)
	end

	arena.Parent = workspace
	decor.Parent = workspace
	return arena, shape
end

return ArenaBuilder
