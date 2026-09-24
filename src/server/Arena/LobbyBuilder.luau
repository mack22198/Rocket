--!strict
-- The VIP deck built into the stands, where players wait between matches. It looks straight out over the
-- pitch, and has a showroom of every car (so there's always something to want), a how-to-play board, and the
-- big Turbo Ball sign that can be seen from the pitch too. LobbyController slowly spins the showroom stands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local Palette = require(script.Parent.Palette)
local PartKit = require(script.Parent.PartKit)

local LobbyBuilder = {}

local rgb = Color3.fromRGB
local UP = Vector3.yAxis
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

local function decor(name: string, color: Color3, material: Enum.Material?): PartKit.Props
	return { Name = name, Color = color, Material = material, Collide = false, Query = false }
end

local function solid(name: string, color: Color3, material: Enum.Material?): PartKit.Props
	return { Name = name, Color = color, Material = material }
end

-- A round tree in a planter box.
local function planter(folder: Instance, base: Vector3)
	PartKit.box(
		folder,
		base + Vector3.new(-3, 0, -3),
		base + Vector3.new(3, 2.4, 3),
		solid("Planter", Palette.DeckTrim)
	)
	PartKit.box(
		folder,
		base + Vector3.new(-2.6, 2.4, -2.6),
		base + Vector3.new(2.6, 2.6, 2.6),
		decor("Soil", rgb(90, 64, 44))
	)
	PartKit.part(folder, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 1, 1),
		CFrame = CFrame.new(base + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Palette.Trunk,
	})
	for i, offset in { Vector3.new(0, 10, 0), Vector3.new(1.4, 8.6, 0.8), Vector3.new(-1.2, 9, -0.9) } do
		local props = decor("Leaves", Palette.Foliage[i], Enum.Material.Grass)
		props.Shape = Enum.PartType.Ball
		props.Size = Vector3.one * (6 - i)
		props.CFrame = CFrame.new(base + offset)
		PartKit.part(folder, props)
	end
end

-- A lamp post with a glowing globe.
local function lamp(folder: Instance, base: Vector3)
	PartKit.part(folder, {
		Name = "LampPost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10, 0.6, 0.6),
		CFrame = CFrame.new(base + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Palette.DeckTrim,
		Material = METAL,
	})
	local globe = decor("LampGlobe", rgb(255, 244, 214), NEON)
	globe.Shape = Enum.PartType.Ball
	globe.Size = Vector3.one * 1.6
	globe.CFrame = CFrame.new(base + Vector3.new(0, 10.6, 0))
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 226, 170)
	light.Range = 18
	light.Brightness = 1
	light.Shadows = false
	light.Parent = PartKit.part(folder, globe)
end

local function bench(folder: Instance, centre: Vector3, alongZ: boolean)
	local size = if alongZ then Vector3.new(2.4, 0.5, 8) else Vector3.new(8, 0.5, 2.4)
	PartKit.box(
		folder,
		centre - Vector3.new(size.X / 2, -1.6, size.Z / 2),
		centre + Vector3.new(size.X / 2, 2.1, size.Z / 2),
		{
			Name = "Bench",
			Color = Palette.Deck:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.WoodPlanks,
		}
	)
	for _, t in { -0.35, 0.35 } do
		local leg = if alongZ then Vector3.new(0, 0, t * size.Z) else Vector3.new(t * size.X, 0, 0)
		PartKit.box(
			folder,
			centre + leg - Vector3.new(0.3, 0, 0.3),
			centre + leg + Vector3.new(0.3, 1.6, 0.3),
			decor("BenchLeg", Palette.DeckTrim, METAL)
		)
	end
end

-- A flag pole with a team flag.
local function flag(folder: Instance, base: Vector3, color: Color3)
	PartKit.part(folder, {
		Name = "FlagPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(16, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Palette.Steel,
		Material = METAL,
	})
	PartKit.box(
		folder,
		base + Vector3.new(-0.1, 11.5, 0.3),
		base + Vector3.new(0.1, 15.5, 6.3),
		decor("Flag", color, Enum.Material.Fabric)
	)
end

-- One showroom stand: a turntable with the car on it and a floating name tag.
local function showroomStand(folder: Instance, def: CarCatalog.CarDef, position: Vector3, facing: Vector3)
	local rarity = CarCatalog.Rarities[def.Rarity]
	local stand = Instance.new("Model")
	stand.Name = `Showroom_{def.Id}`
	PartKit.disc(stand, position + Vector3.new(0, 0.25, 0), 9, 0.5, decor("StandGlow", rarity.Color, NEON))
	local turntable =
		PartKit.disc(stand, position + Vector3.new(0, 0.6, 0), 8.4, 1.2, solid("Turntable", Palette.DeckTrim, METAL))

	local model = CarModelBuilder.build(def, { preview = true })
	local lift = def.Hitbox.Y / 2 + GameConfig.Car.RideHeight - GameConfig.Car.Gravity / GameConfig.Car.SpringStrength
	local right = facing:Cross(UP)
	model:PivotTo(CFrame.fromMatrix(position + Vector3.new(0, 1.2 + lift, 0), right, UP))
	model.Name = "Car"
	model.Parent = stand

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(220, 66)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 8.5, 0)
	tag.MaxDistance = 90
	tag.LightInfluence = 0
	tag.Adornee = turntable
	tag.Parent = turntable
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Text = `{def.Emoji} {def.DisplayName}`
	title.Parent = tag
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromScale(0, 0.6)
	subtitle.Size = UDim2.fromScale(1, 0.4)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.TextColor3 = rarity.Color
	subtitle.TextStrokeTransparency = 0.3
	subtitle.Text = if def.Price == 0
		then `{string.upper(def.Rarity)}  ·  STARTER CAR`
		else `{string.upper(def.Rarity)}  ·  {def.Price} SCRAP`
	subtitle.Parent = tag

	stand:SetAttribute("CarId", def.Id)
	stand.Parent = folder
end

function LobbyBuilder.build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = MatchState.Folders.Lobby

	local cfg = GameConfig.Lobby
	local centre, size = cfg.Center, cfg.Size
	local top = centre.Y
	local front, back = centre.X - size.X / 2, centre.X + size.X / 2 -- front edge faces the pitch
	local left, right = centre.Z - size.Z / 2, centre.Z + size.Z / 2

	-- The building holding the deck up, with a strip of windows facing the pitch.
	PartKit.box(folder, Vector3.new(front, -0.2, left), Vector3.new(back, top - size.Y, right), {
		Name = "LobbyBuilding",
		Color = Palette.Concrete,
		Material = Enum.Material.Concrete,
		Collide = false,
		Query = false,
	})
	PartKit.box(
		folder,
		Vector3.new(front - 0.6, top - 9.5, left + 1),
		Vector3.new(front, top - size.Y - 0.6, right - 1),
		decor("Windows", rgb(40, 70, 110), Enum.Material.Glass)
	)
	PartKit.box(folder, Vector3.new(front - 1.2, top - size.Y, left), Vector3.new(back, top, right), {
		Name = "Deck",
		Color = Palette.Deck,
		Material = Enum.Material.WoodPlanks,
	})
	PartKit.box(
		folder,
		Vector3.new(front - 1.4, top - 1.4, left),
		Vector3.new(front - 1.1, top - 0.6, right),
		decor("DeckEdgeGlow", Palette.Gold, NEON)
	)

	-- Glass railings all round, with invisible walls behind them so nobody falls off.
	local railHeight = 3.6
	local edges = {
		{ Vector3.new(front + 0.5, 0, left + 0.5), Vector3.new(front + 0.5, 0, right - 0.5) },
		{ Vector3.new(back - 0.5, 0, left + 0.5), Vector3.new(back - 0.5, 0, right - 0.5) },
		{ Vector3.new(front + 0.5, 0, left + 0.5), Vector3.new(back - 0.5, 0, left + 0.5) },
		{ Vector3.new(front + 0.5, 0, right - 0.5), Vector3.new(back - 0.5, 0, right - 0.5) },
	}
	for _, edge in edges do
		local a, b = edge[1] + Vector3.new(0, top, 0), edge[2] + Vector3.new(0, top, 0)
		local along = (b - a).Unit
		local length = (b - a).Magnitude
		local frame = CFrame.fromMatrix((a + b) / 2, along, UP)
		local glass = decor("Railing", Palette.Glass, Enum.Material.Glass)
		glass.Transparency = 0.55
		glass.Shadow = false
		glass.CFrame = frame * CFrame.new(0, railHeight / 2, 0)
		glass.Size = Vector3.new(length, railHeight, 0.3)
		PartKit.part(folder, glass)
		local rail = decor("Handrail", Palette.Steel, METAL)
		rail.CFrame = frame * CFrame.new(0, railHeight + 0.25, 0)
		rail.Size = Vector3.new(length + 0.8, 0.5, 0.8)
		PartKit.part(folder, rail)
		local wall = solid("Barrier", Color3.new(1, 1, 1))
		wall.Transparency = 1
		wall.Query = false
		wall.Shadow = false
		wall.CFrame = frame * CFrame.new(0, 7, 0)
		wall.Size = Vector3.new(length, 14, 1)
		PartKit.part(folder, wall)
		for k = 0, math.floor(length / 12) do
			local post = decor("RailPost", Palette.Steel, METAL)
			post.CFrame = frame * CFrame.new(-length / 2 + k * length / math.floor(length / 12), railHeight / 2, 0)
			post.Size = Vector3.new(0.6, railHeight, 0.6)
			PartKit.part(folder, post)
		end
	end

	-- Spawn pad near the railing, facing the pitch, so the first thing you see is the match.
	local spawnPoint = Vector3.new(front + 18, top, centre.Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.CFrame = CFrame.new(spawnPoint + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CanTouch = true
	spawn.Parent = folder
	local rings: { { radius: number, color: Color3, material: Enum.Material? } } = {
		{ radius = 7.2, color = Palette.Gold, material = NEON },
		{ radius = 6.2, color = Palette.Board },
		{ radius = 2.2, color = Palette.Gold, material = NEON },
	}
	for i, ring in rings do
		local height = spawnPoint + Vector3.new(0, 0.05 + i * 0.06, 0)
		PartKit.disc(folder, height, ring.radius, 0.1, decor("SpawnPad", ring.color, ring.material))
	end
	-- A carpet from the spawn pad back to the showroom.
	PartKit.box(
		folder,
		Vector3.new(spawnPoint.X + 7.5, top, -7),
		Vector3.new(back - 34, top + 0.12, 7),
		decor("Carpet", Palette.Board, Enum.Material.Fabric)
	)
	PartKit.box(
		folder,
		Vector3.new(back - 34, top, left + 12),
		Vector3.new(back - 6, top + 0.12, right - 12),
		decor("ShowroomFloor", Palette.Board, Enum.Material.Fabric)
	)

	-- Showroom along the back: every car on a turntable, facing the spawn pad.
	local showroom = Instance.new("Folder")
	showroom.Name = "Showroom"
	showroom.Parent = folder
	local cars = CarCatalog.ordered()
	local rowX = back - 20
	local spread = size.Z - 52
	for i, def in cars do
		local z = centre.Z - spread / 2 + (i - 1) * spread / math.max(1, #cars - 1)
		local position = Vector3.new(rowX, top, z)
		local toSpawn = Vector3.new(spawnPoint.X - rowX, 0, spawnPoint.Z - z).Unit
		showroomStand(showroom, def, position, toSpawn)
	end

	-- The big sign behind the showroom (tall enough to be seen from the pitch).
	local signBottom, signTop = top + 12, top + 36
	for _, z in { -34, 34 } do
		PartKit.box(
			folder,
			Vector3.new(back - 4, top, z - 1),
			Vector3.new(back - 2, signBottom, z + 1),
			solid("SignPost", Palette.DeckTrim, METAL)
		)
	end
	local board = PartKit.box(
		folder,
		Vector3.new(back - 4.4, signBottom, -48),
		Vector3.new(back - 1.6, signTop, 48),
		decor("TitleSign", Palette.Board)
	)
	local screen = PartKit.screen(board, Enum.NormalId.Left, Palette.Board, 8)
	local blue, orange = GameConfig.Teams.Blue, GameConfig.Teams.Orange
	PartKit.label(screen, "Turbo", "TURBO", orange.Color, Vector2.new(0.3, 0.4), Vector2.new(0.44, 0.58))
	PartKit.label(screen, "Ball", "BALL", blue.Color, Vector2.new(0.72, 0.4), Vector2.new(0.36, 0.58))
	PartKit.label(
		screen,
		"Tagline",
		"3v3 CAR SOCCER",
		Color3.new(1, 1, 1),
		Vector2.new(0.5, 0.84),
		Vector2.new(0.6, 0.18),
		Enum.Font.GothamBold
	)
	for _, y in { signBottom - 0.4, signTop + 0.4 } do
		PartKit.box(
			folder,
			Vector3.new(back - 4.8, y - 0.4, -48.4),
			Vector3.new(back - 1.4, y + 0.4, 48.4),
			decor("SignGlow", Palette.Gold, NEON)
		)
	end

	-- How to play, at one end of the deck.
	local howTo = PartKit.box(
		folder,
		Vector3.new(centre.X - 26, top + 3, left + 2),
		Vector3.new(centre.X + 26, top + 22, left + 3),
		solid("HowToPlay", Palette.Board)
	)
	PartKit.sign(howTo, Enum.NormalId.Back, {
		"HOW TO PLAY",
		"W / S  drive     A / D  steer",
		"SPACE  jump (twice to flip)",
		"SHIFT or CLICK  boost",
		"F  Mega Shot when your meter is full",
		"C  ball cam     Q / E  air roll",
	}, { color = Color3.new(1, 1, 1), background = Palette.Board })
	-- ...and the garage hint at the other end.
	local garage = PartKit.box(
		folder,
		Vector3.new(centre.X - 26, top + 3, right - 3),
		Vector3.new(centre.X + 26, top + 22, right - 2),
		solid("GarageSign", Palette.Board)
	)
	PartKit.sign(garage, Enum.NormalId.Front, {
		"🏎️ GARAGE",
		"Win Scrap in matches to unlock new cars",
		"Play with a car to power it up",
		"then EVOLVE it into something epic!",
	}, { color = Palette.Gold, background = Palette.Board })

	-- Things to make it feel like a place: trees, lamps, benches and team flags.
	for _, z in { left + 8, right - 8 } do
		planter(folder, Vector3.new(front + 8, top, z))
		planter(folder, Vector3.new(back - 8, top, z))
		lamp(folder, Vector3.new(front + 3, top, z + (if z < 0 then 14 else -14)))
	end
	for _, z in { -64, -36, 36, 64 } do
		bench(folder, Vector3.new(front + 9, top, z), true)
	end
	flag(folder, Vector3.new(front + 3, top, left + 30), blue.Color)
	flag(folder, Vector3.new(front + 3, top, right - 30), orange.Color)

	folder.Parent = workspace
	return folder
end

return LobbyBuilder
