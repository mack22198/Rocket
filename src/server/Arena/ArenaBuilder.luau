--!strict
-- Builds the stadium out of parts when the server starts, using the same numbers as ArenaShape
-- (so what you see matches what the ball bounces off).
--
-- Workspace.Arena      = everything cars drive on or bump into (wheel rays only look at this folder)
-- Workspace.ArenaDecor = lines, goal frames, signs and stands (no collisions)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local ArenaBuilder = {}

local rgb = Color3.fromRGB
local cfg = GameConfig.Arena

local FIELD_LIGHT = rgb(88, 190, 90)
local FIELD_DARK = rgb(72, 170, 76)
local WALL_COLOR = rgb(190, 225, 255)
local RIM_COLOR = rgb(235, 245, 255)

type PartProps = {
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Name: string?,
	CastShadow: boolean?,
}

local function makePart(parent: Instance, props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Anchored = true
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	part.CanTouch = false
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function decor(parent: Instance, props: PartProps): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = false
	return makePart(parent, props)
end

local function teamForSide(side: number): typeof(GameConfig.Teams.Blue)
	return if GameConfig.Teams.Blue.DefendsSide == side then GameConfig.Teams.Blue else GameConfig.Teams.Orange
end

local function addLabel(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
end

-- One curved ramp, approximated with flat strips.
local function buildRamp(parent: Instance, ramp: ArenaShape.Ramp, segments: number)
	local R = ramp.radius
	local thickness = 2
	local length = ramp.to - ramp.from
	local middle = (ramp.from + ramp.to) / 2
	local function crossSection(angle: number): Vector2
		return Vector2.new(R - R * math.sin(angle), R - R * math.cos(angle))
	end
	for i = 0, segments - 1 do
		local a0 = (i / segments) * math.pi / 2
		local a1 = ((i + 1) / segments) * math.pi / 2
		local p0, p1 = crossSection(a0), crossSection(a1)
		local mid = (p0 + p1) / 2
		local chord = (p1 - p0).Magnitude
		local outward = (mid - Vector2.new(R, R)).Unit -- away from the curve's centre, into the solid
		local centre2D = mid + outward * (thickness / 2)
		local centre = ramp.wallPoint + ramp.inward * centre2D.X + Vector3.yAxis * centre2D.Y + ramp.along * middle
		local surfaceNormal = -(ramp.inward * outward.X + Vector3.yAxis * outward.Y)
		local t = if segments > 1 then i / (segments - 1) else 0
		makePart(parent, {
			Name = "Ramp",
			Size = Vector3.new(length, thickness, chord + 0.08),
			CFrame = CFrame.fromMatrix(centre, ramp.along, surfaceNormal),
			Color = FIELD_LIGHT:Lerp(WALL_COLOR, t),
			Material = if t < 0.5 then Enum.Material.Grass else Enum.Material.SmoothPlastic,
		})
	end
end

local function buildField(arena: Instance, decorFolder: Instance)
	local W, L = cfg.Width, cfg.Length
	-- Striped grass floor.
	local stripes = 10
	local stripeLength = L / stripes
	for i = 0, stripes - 1 do
		local z = -L / 2 + stripeLength * (i + 0.5)
		makePart(arena, {
			Name = "Floor",
			Size = Vector3.new(W, 2, stripeLength),
			CFrame = CFrame.new(0, -1, z),
			Color = if i % 2 == 0 then FIELD_LIGHT else FIELD_DARK,
			Material = Enum.Material.Grass,
		})
	end
	-- Floors inside the goals.
	for _, side in { 1, -1 } do
		local team = teamForSide(side)
		makePart(arena, {
			Name = "GoalFloor",
			Size = Vector3.new(cfg.GoalWidth + 2 * cfg.WallThickness, 2, cfg.GoalDepth + cfg.WallThickness),
			CFrame = CFrame.new(0, -1, side * (L / 2 + (cfg.GoalDepth + cfg.WallThickness) / 2)),
			Color = team.DarkColor,
		})
	end
	-- Stadium base under everything.
	decor(decorFolder, {
		Name = "StadiumBase",
		Size = Vector3.new(W + 260, 2, L + 200),
		CFrame = CFrame.new(40, -3, 0),
		Color = rgb(55, 60, 75),
		Material = Enum.Material.Concrete,
	})

	-- Field markings (no collisions, invisible to wheel rays).
	local lineColor = rgb(250, 250, 250)
	decor(decorFolder, {
		Name = "CenterLine",
		Size = Vector3.new(W - 2 * cfg.CurveRadius, 0.06, 1.2),
		CFrame = CFrame.new(0, 0.04, 0),
		Color = lineColor,
		Material = Enum.Material.Neon,
	})
	local circleRadius = 30
	local circleSegments = 36
	for i = 0, circleSegments - 1 do
		local angle = (i + 0.5) / circleSegments * math.pi * 2
		local segmentLength = 2 * math.pi * circleRadius / circleSegments + 0.2
		decor(decorFolder, {
			Name = "CenterCircle",
			Size = Vector3.new(1.2, 0.06, segmentLength),
			CFrame = CFrame.new(math.cos(angle) * circleRadius, 0.04, math.sin(angle) * circleRadius)
				* CFrame.Angles(0, -angle, 0),
			Color = lineColor,
			Material = Enum.Material.Neon,
		})
	end
	for _, side in { 1, -1 } do
		local team = teamForSide(side)
		local boxDepth = 36
		local boxWidth = cfg.GoalWidth + 30
		local lineZ = side * (L / 2 - boxDepth)
		decor(decorFolder, {
			Name = "GoalBoxFront",
			Size = Vector3.new(boxWidth, 0.06, 1.2),
			CFrame = CFrame.new(0, 0.04, lineZ),
			Color = team.Color,
			Material = Enum.Material.Neon,
		})
		for _, sx in { 1, -1 } do
			decor(decorFolder, {
				Name = "GoalBoxSide",
				Size = Vector3.new(1.2, 0.06, boxDepth - cfg.CurveRadius),
				CFrame = CFrame.new(sx * boxWidth / 2, 0.04, lineZ + side * (boxDepth - cfg.CurveRadius) / 2),
				Color = team.Color,
				Material = Enum.Material.Neon,
			})
		end
	end
end

local function buildWalls(arena: Instance, decorFolder: Instance)
	local W, L, H, C, T = cfg.Width, cfg.Length, cfg.Height, cfg.CornerCut, cfg.WallThickness
	local GW, GH, GD = cfg.GoalWidth, cfg.GoalHeight, cfg.GoalDepth

	local function wall(size: Vector3, cframe: CFrame, color: Color3, transparency: number)
		makePart(arena, {
			Name = "Wall",
			Size = size,
			CFrame = cframe,
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = transparency,
			CastShadow = false,
		})
	end

	-- Side walls.
	local sideLength = L - 2 * C
	for _, sx in { 1, -1 } do
		wall(Vector3.new(T, H, sideLength), CFrame.new(sx * (W / 2 + T / 2), H / 2, 0), WALL_COLOR, 0.6)
		decor(decorFolder, {
			Name = "WallRim",
			Size = Vector3.new(T + 0.4, 0.8, sideLength),
			CFrame = CFrame.new(sx * (W / 2 + T / 2), H, 0),
			Color = RIM_COLOR,
			Material = Enum.Material.Neon,
		})
	end

	-- 45 degree corner walls.
	local diagonalLength = C * math.sqrt(2)
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local a = Vector3.new(sx * W / 2, 0, sz * (L / 2 - C))
			local b = Vector3.new(sx * (W / 2 - C), 0, sz * L / 2)
			local outward = Vector3.new(sx, 0, sz).Unit
			local centre = (a + b) / 2 + outward * (T / 2) + Vector3.new(0, H / 2, 0)
			wall(
				Vector3.new(T, H, diagonalLength + T),
				CFrame.fromMatrix(centre, outward, Vector3.yAxis),
				WALL_COLOR,
				0.6
			)
		end
	end

	-- End walls with the goal holes, and the goals themselves.
	local sideSegment = W / 2 - C - GW / 2
	for _, side in { 1, -1 } do
		local team = teamForSide(side)
		local tint = WALL_COLOR:Lerp(team.Color, 0.35)
		local wallZ = side * (L / 2 + T / 2)
		for _, sx in { 1, -1 } do
			wall(
				Vector3.new(sideSegment + T, H, T),
				CFrame.new(sx * (GW / 2 + sideSegment / 2 + T / 2), H / 2, wallZ),
				tint,
				0.45
			)
		end
		local above = makePart(arena, {
			Name = "Wall",
			Size = Vector3.new(GW, H - GH, T),
			CFrame = CFrame.new(0, GH + (H - GH) / 2, wallZ),
			Color = tint,
			Material = Enum.Material.Glass,
			Transparency = 0.45,
			CastShadow = false,
		})
		addLabel(
			above,
			if side > 0 then Enum.NormalId.Front else Enum.NormalId.Back,
			`{string.upper(team.Name)} GOAL`,
			team.Color
		)

		-- Goal box: side walls, roof and back, glowing in the team colour.
		local goalMiddleZ = side * (L / 2 + GD / 2)
		for _, sx in { 1, -1 } do
			makePart(arena, {
				Name = "GoalWall",
				Size = Vector3.new(T, GH, GD),
				CFrame = CFrame.new(sx * (GW / 2 + T / 2), GH / 2, goalMiddleZ),
				Color = team.Color,
				Material = Enum.Material.ForceField,
			})
		end
		makePart(arena, {
			Name = "GoalRoof",
			Size = Vector3.new(GW + 2 * T, T, GD),
			CFrame = CFrame.new(0, GH + T / 2, goalMiddleZ),
			Color = team.Color,
			Material = Enum.Material.ForceField,
		})
		makePart(arena, {
			Name = "GoalBack",
			Size = Vector3.new(GW + 2 * T, GH + T, T),
			CFrame = CFrame.new(0, (GH + T) / 2, side * (L / 2 + GD + T / 2)),
			Color = team.Color,
			Material = Enum.Material.ForceField,
		})

		-- Glowing goal frame (flush with the wall face, so it never gets in the ball's way).
		local frameZ = side * (L / 2 + 0.55)
		for _, sx in { 1, -1 } do
			decor(decorFolder, {
				Name = "GoalPost",
				Size = Vector3.new(1.2, GH + 1.2, 1.2),
				CFrame = CFrame.new(sx * (GW / 2 + 0.6), (GH + 1.2) / 2, frameZ),
				Color = team.Color,
				Material = Enum.Material.Neon,
			})
		end
		decor(decorFolder, {
			Name = "Crossbar",
			Size = Vector3.new(GW + 2.4, 1.2, 1.2),
			CFrame = CFrame.new(0, GH + 0.6, frameZ),
			Color = team.Color,
			Material = Enum.Material.Neon,
		})
		local light = Instance.new("PointLight")
		light.Color = team.Color
		light.Range = 40
		light.Brightness = 2
		light.Parent = makePart(decorFolder, {
			Name = "GoalLight",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(0, GH / 2, side * (L / 2 + GD - 2)),
			Color = team.Color,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- Invisible ceiling keeps the ball in.
	makePart(arena, {
		Name = "Ceiling",
		Size = Vector3.new(W + 2 * T, T, L + 2 * (GD + T)),
		CFrame = CFrame.new(0, H + T / 2, 0),
		Color = WALL_COLOR,
		Transparency = 1,
		CastShadow = false,
	})
end

local function buildStands(decorFolder: Instance)
	-- A few rows of colourful seats on the far side and behind the goals, for atmosphere.
	local W, L, T = cfg.Width, cfg.Length, cfg.WallThickness
	local seatColors = { rgb(255, 90, 90), rgb(255, 210, 70), rgb(90, 200, 255), rgb(150, 110, 255), rgb(90, 220, 120) }
	for row = 0, 5 do
		local x = -(W / 2 + T + 6 + row * 7)
		decor(decorFolder, {
			Name = "Stand",
			Size = Vector3.new(7, 4 + row * 4, L - 40),
			CFrame = CFrame.new(x, (4 + row * 4) / 2, 0),
			Color = seatColors[row % #seatColors + 1],
			Material = Enum.Material.SmoothPlastic,
		})
	end
	for _, side in { 1, -1 } do
		for row = 0, 3 do
			local z = side * (L / 2 + cfg.GoalDepth + T + 6 + row * 7)
			decor(decorFolder, {
				Name = "Stand",
				Size = Vector3.new(W - 20, 4 + row * 4, 7),
				CFrame = CFrame.new(0, (4 + row * 4) / 2, z),
				Color = seatColors[(row + 2) % #seatColors + 1],
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
end

local function setupLighting()
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 1
		atmosphere.Color = rgb(200, 225, 255)
		atmosphere.Parent = Lighting
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.12
	color.Contrast = 0.05
	color.Parent = Lighting
end

-- Builds everything and returns the Arena folder (the one wheel rays should hit) and the math shape.
function ArenaBuilder.build(): (Folder, ArenaShape.Arena)
	local shape = ArenaShape.new(cfg)

	local arena = Instance.new("Folder")
	arena.Name = MatchState.Folders.Arena
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "ArenaDecor"

	buildField(arena, decorFolder)
	buildWalls(arena, decorFolder)
	for _, ramp in shape.ramps do
		buildRamp(arena, ramp, cfg.CurveSegments)
	end
	buildStands(decorFolder)
	setupLighting()

	arena.Parent = workspace
	decorFolder.Parent = workspace
	return arena, shape
end

return ArenaBuilder
