--!strict
-- The viewing deck beside the arena where players spawn between matches: a spawn pad, a how-to-play board,
-- and a showroom of every car you can unlock (so there's always something to want).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local LobbyBuilder = {}

local rgb = Color3.fromRGB

type BlockProps = {
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,
}

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	props: BlockProps?
): Part
	local p: BlockProps = props or ({} :: BlockProps)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.CanCollide = if p.collide == nil then true else p.collide
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function sign(part: BasePart, face: Enum.NormalId, lines: { string }, textColor: Color3, background: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background or rgb(25, 30, 50)
	frame.BackgroundTransparency = if background then 0 else 1
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	for i, text in lines do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.95, 1 / #lines * 0.9)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = textColor
		label.TextScaled = true
		label.Font = if i == 1 then Enum.Font.FredokaOne else Enum.Font.GothamBold
		label.LayoutOrder = i
		label.Parent = frame
	end
end

function LobbyBuilder.build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = MatchState.Folders.Lobby

	local lobby = GameConfig.Lobby
	local centre = lobby.Center
	local size = lobby.Size
	local top = centre.Y

	-- Deck.
	block(
		folder,
		"Deck",
		Vector3.new(size.X, size.Y, size.Z),
		CFrame.new(centre - Vector3.new(0, size.Y / 2, 0)),
		rgb(70, 80, 110),
		{
			material = Enum.Material.DiamondPlate,
		}
	)
	-- Invisible walls so nobody falls off, plus a low glass rail you can see.
	local wallHeight = 14
	local edges = {
		{ Vector3.new(1, wallHeight, size.Z), Vector3.new(-size.X / 2, wallHeight / 2, 0) },
		{ Vector3.new(1, wallHeight, size.Z), Vector3.new(size.X / 2, wallHeight / 2, 0) },
		{ Vector3.new(size.X, wallHeight, 1), Vector3.new(0, wallHeight / 2, -size.Z / 2) },
		{ Vector3.new(size.X, wallHeight, 1), Vector3.new(0, wallHeight / 2, size.Z / 2) },
	}
	for _, edge in edges do
		block(
			folder,
			"Barrier",
			edge[1],
			CFrame.new(Vector3.new(centre.X, top, centre.Z) + edge[2]),
			rgb(255, 255, 255),
			{
				transparency = 1,
			}
		)
		local railSize = Vector3.new(math.max(edge[1].X, 0.6), 3, math.max(edge[1].Z, 0.6))
		block(
			folder,
			"Rail",
			railSize,
			CFrame.new(Vector3.new(centre.X, top + 1.5, centre.Z) + edge[2] * Vector3.new(1, 0, 1)),
			rgb(170, 220, 255),
			{
				material = Enum.Material.Glass,
				transparency = 0.5,
				collide = false,
			}
		)
	end

	-- Spawn pad.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(centre.X, top + 0.5, centre.Z) * CFrame.Angles(0, math.rad(90), 0)
	spawn.Color = rgb(255, 210, 70)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CanTouch = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	-- Title sign at one end of the deck, controls board at the other.
	local title = block(
		folder,
		"TitleSign",
		Vector3.new(size.X - 10, 22, 1),
		CFrame.new(centre.X, top + 13, centre.Z + size.Z / 2 - 2),
		rgb(25, 30, 50)
	)
	sign(
		title,
		Enum.NormalId.Front,
		{ string.upper(GameConfig.GameName), "3v3 car soccer - grab a car and score!" },
		rgb(255, 210, 70)
	)

	local board = block(
		folder,
		"HowToPlay",
		Vector3.new(size.X - 10, 24, 1),
		CFrame.new(centre.X, top + 14, centre.Z - size.Z / 2 + 2),
		rgb(25, 30, 50)
	)
	sign(board, Enum.NormalId.Back, {
		"HOW TO PLAY",
		"W / S  drive     A / D  steer",
		"SPACE  jump (twice to flip)",
		"SHIFT or CLICK  boost",
		"F  Mega Shot when your meter is full",
		"C  ball cam     Q / E  air roll",
	}, rgb(255, 255, 255))

	-- Showroom: every car on a pedestal, facing the deck.
	local cars = CarCatalog.ordered()
	local spacing = (size.Z - 50) / math.max(1, #cars - 1)
	for i, def in cars do
		local z = centre.Z - (size.Z - 50) / 2 + (i - 1) * spacing
		local x = centre.X + size.X / 2 - 9
		local rarity = CarCatalog.Rarities[def.Rarity]
		local pedestal = block(folder, "Pedestal", Vector3.new(12, 2, 14), CFrame.new(x, top + 1, z), rarity.Color, {
			material = Enum.Material.Neon,
			transparency = 0.2,
		})
		local model = CarModelBuilder.build(def, { preview = true })
		local liftToFloor = def.Hitbox.Y / 2
			+ GameConfig.Car.RideHeight
			- GameConfig.Car.Gravity / GameConfig.Car.SpringStrength
		model:PivotTo(CFrame.new(x, top + 2 + liftToFloor, z) * CFrame.Angles(0, math.rad(90), 0))
		model.Parent = folder

		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(220, 70)
		tag.StudsOffset = Vector3.new(0, 6, 0)
		tag.MaxDistance = 90
		tag.LightInfluence = 0
		tag.Adornee = pedestal
		tag.Parent = pedestal
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = rgb(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.Text = if def.Price == 0
			then `{def.Emoji} {def.DisplayName}\nStarter car`
			else `{def.Emoji} {def.DisplayName}\n{def.Rarity} - {def.Price} Scrap`
		label.Parent = tag
	end

	folder.Parent = workspace
	return folder
end

return LobbyBuilder
