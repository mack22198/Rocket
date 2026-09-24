--!strict
-- The garage. Left: every car, with a 3D preview and whether you own it. Right: the chosen car up close, its
-- strengths and weaknesses, its evolution track and the button for the next step (unlock, equip or EVOLVE).
-- Prices are fixed and shown up front; evolving is earned by driving the car. Changes apply from your next match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local Evolution = require(Shared.Config.Evolution)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local Garage = {}

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer
local STAGES = GameConfig.Evolution.Stages

type Tile = {
	def: CarCatalog.CarDef,
	button: TextButton,
	viewport: ViewportFrame,
	model: Model?,
	shownStage: number,
	status: TextLabel,
}

type Node = { circle: TextLabel, name: TextLabel }

local gui: ScreenGui
local panel: Frame
local scrapPill: TextLabel
local toast: TextLabel
local tiles: { Tile } = {}
local detailViewport: ViewportFrame
local detailModel: Model? = nil
local detailKey = ""
local nameLabel: TextLabel
local rarityLabel: TextLabel
local descriptionLabel: TextLabel
local statBars: { { key: string, bar: Theme.Bar } } = {}
local nodes: { Node } = {}
local trackFill: Frame
local xpBar: Theme.Bar
local xpLabel: TextLabel
local primaryButton: TextButton
local secondaryButton: TextButton
local celebration: Frame
local celebrationTitle: TextLabel
local celebrationName: TextLabel

local selectedId = CarCatalog.StarterId
local previewStage = 1
local busy = false
local spin = 0
local lastRefresh = 0

local STAT_ROWS = {
	{ key = "Speed", label = "Speed" },
	{ key = "Acceleration", label = "Accel" },
	{ key = "Handling", label = "Turning" },
	{ key = "Weight", label = "Weight" },
	{ key = "BumpPower", label = "Bump" },
}

local function selectedDef(): CarCatalog.CarDef
	return CarCatalog.get(selectedId) or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
end

-- The short name of a stage for the evolution track ("Classic", "Burnt", "Lava", "Galaxy").
local function shortStageName(def: CarCatalog.CarDef, stage: number): string
	if stage == 1 then
		return "Classic"
	end
	return string.match(CarCatalog.stageName(def, stage), "^(%S+)") or `Stage {stage}`
end

local function playSound(id: string, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

local function showToast(text: string, good: boolean)
	toast.Text = text
	toast.TextColor3 = if good then C.Good else C.Bad
	toast.TextTransparency = 0
	toast.Visible = true
	task.delay(2.8, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

-- Puts a freshly built car model in a viewport, with the camera pulled back to fit it.
local function showCar(viewport: ViewportFrame, def: CarCatalog.CarDef, stage: number, distance: number): Model
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local model = CarModelBuilder.build(def, { preview = true, stage = stage })
	model.Parent = viewport
	local camera = viewport:FindFirstChildOfClass("Camera")
	if camera then
		local back = distance + def.Hitbox.Z * 0.45
		camera.CFrame = CFrame.lookAt(Vector3.new(0, back * 0.42, back), Vector3.new(0, 0.3, 0))
	end
	return model
end

local function makeViewport(parent: Instance, size: UDim2, position: UDim2): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = size
	viewport.Position = position
	viewport.BackgroundColor3 = rgb(46, 56, 96)
	viewport.Ambient = rgb(170, 172, 196)
	viewport.LightColor = rgb(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = parent
	Theme.gradient(viewport, rgb(255, 255, 255), rgb(120, 125, 150))
	local camera = Instance.new("Camera")
	camera.FieldOfView = 36
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function request(action: string, def: CarCatalog.CarDef, extra: number?): { [string]: any }?
	if busy then
		return nil
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.Garage:InvokeServer(action, def.Id, extra)
	end)
	busy = false
	if ok and type(result) == "table" then
		showToast(tostring(result.message), result.ok == true)
		return result
	end
	showToast("Couldn't reach the garage. Try again!", false)
	return nil
end

-- The big "it evolved!" moment.
local function celebrate(def: CarCatalog.CarDef, stage: number)
	celebrationName.Text = CarCatalog.stageName(def, stage)
	celebration.Visible = true
	celebration.BackgroundTransparency = 0
	celebrationTitle.TextTransparency = 0
	celebrationName.TextTransparency = 0
	TweenService:Create(celebration, TweenInfo.new(0.8), { BackgroundTransparency = 0.35 }):Play()
	celebrationTitle.Size = UDim2.new(1, 0, 0, 40)
	TweenService:Create(celebrationTitle, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
		Size = UDim2.new(1, 0, 0, 90),
	}):Play()
	-- Confetti.
	for i = 1, 36 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(10, 16)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.45)
		piece.BackgroundColor3 = ({ C.Gold, C.Evolve, C.Blue, C.Orange, C.Good })[i % 5 + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = i * 37
		piece.Parent = celebration
		local angle = i / 36 * math.pi * 2
		TweenService:Create(piece, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * 420, 0.45, math.sin(angle) * 260),
			Rotation = i * 37 + 360,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(1.3, function()
			piece:Destroy()
		end)
	end
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.8)
	task.delay(2.6, function()
		TweenService:Create(celebration, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(celebrationTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(celebrationName, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		celebration.Visible = false
	end)
end

local function refresh()
	lastRefresh = os.clock()
	local data = PlayerDataClient.get()
	scrapPill.Text = `🔩 {Theme.formatNumber(data.scrap)}`

	-- Car list.
	for _, tile in tiles do
		local id = tile.def.Id
		local owned = data.owned[id] == true
		local look = if owned then data.carLook[id] or 1 else 1
		if tile.shownStage ~= look or not tile.model then
			tile.model = showCar(tile.viewport, tile.def, look, 9)
			tile.shownStage = look
		end
		tile.viewport.ImageColor3 = if owned then rgb(255, 255, 255) else rgb(95, 100, 125)
		local stroke = tile.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == selectedId then C.Gold else CarCatalog.Rarities[tile.def.Rarity].Color
			stroke.Thickness = if id == selectedId then 4 else 2
		end
		if data.equipped == id then
			tile.status.Text = "✅ DRIVING"
			tile.status.TextColor3 = C.Good
		elseif owned then
			local ready = Evolution.progress(tile.def, data.carXp[id] or 0, data.carStage[id] or 1).ready
			tile.status.Text = if ready then "✨ EVOLVE!" else "OWNED"
			tile.status.TextColor3 = if ready then C.Evolve else C.Text
		else
			tile.status.Text = `🔒 🔩 {Theme.formatNumber(tile.def.Price)}`
			tile.status.TextColor3 = if data.scrap >= tile.def.Price then C.Gold else C.Muted
		end
	end

	-- Details.
	local def = selectedDef()
	local owned = data.owned[def.Id] == true
	local stage = if owned then data.carStage[def.Id] or 1 else 1
	local look = if owned then data.carLook[def.Id] or 1 else 1
	local xp = if owned then data.carXp[def.Id] or 0 else 0
	local progress = Evolution.progress(def, xp, stage)
	local rarity = CarCatalog.Rarities[def.Rarity]

	local key = `{def.Id}:{previewStage}`
	if key ~= detailKey then
		detailKey = key
		detailModel = showCar(detailViewport, def, previewStage, 10)
	end
	detailViewport.ImageColor3 = if previewStage <= stage then rgb(255, 255, 255) else rgb(150, 150, 175)
	nameLabel.Text = `{def.Emoji} {CarCatalog.stageName(def, previewStage)}`
	rarityLabel.Text = `{string.upper(def.Rarity)}  ·  {def.Tagline}`
	rarityLabel.TextColor3 = rarity.Color
	descriptionLabel.Text = def.Description
	for _, row in statBars do
		local value = (def.Stats :: any)[row.key] :: number
		-- 0.6 .. 1.4 maps across the bar, so every car looks good at something.
		row.bar.set(math.clamp((value - 0.6) / 0.8, 0.06, 1))
		row.bar.fill.BackgroundColor3 = if value > 1.001 then C.Good elseif value < 0.999 then C.Bad else C.Gold
	end

	-- Evolution track.
	local pulse = math.floor(os.clock() * 3) % 2 == 0
	for i, node in nodes do
		local reached = owned and i <= stage
		local nextReady = owned and progress.ready and i == stage + 1
		node.circle.Text = if reached then tostring(i) elseif nextReady then "✨" else "🔒"
		node.circle.BackgroundColor3 = if reached then C.Evolve elseif nextReady then C.Gold else C.PanelDark
		node.circle.TextColor3 = if reached or nextReady then C.Text else C.Muted
		local ring = node.circle:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = if i == previewStage then C.Gold elseif owned and i == look then C.Text else rgb(0, 0, 0)
			ring.Thickness = if i == previewStage then 4 elseif owned and i == look then 3 else 2
			ring.Transparency = if i == previewStage or (owned and i == look) then 0 else 0.5
		end
		node.name.Text = shortStageName(def, i)
		node.name.TextColor3 = if reached then C.Text else C.Muted
		if nextReady and pulse then
			node.circle.BackgroundColor3 = C.Evolve
		end
	end
	trackFill.Size = UDim2.fromScale((math.max(stage, 1) - 1) / (STAGES - 1), 1)

	if not owned then
		xpBar.set(0)
		xpLabel.Text = "Unlock this car to start evolving it"
	elseif progress.nextStage then
		xpBar.set(progress.fraction)
		xpLabel.Text = if progress.ready
			then `READY! Evolve into the {progress.nextName}`
			else `{Theme.formatNumber(xp)} / {Theme.formatNumber(progress.xpForNext)} XP to {progress.nextName}`
	else
		xpBar.set(1)
		xpLabel.Text = "⭐ Fully evolved! ⭐"
	end
	xpLabel.TextColor3 = if owned and progress.ready then C.Gold else C.Muted

	-- Buttons.
	if not owned then
		local canAfford = data.scrap >= def.Price
		primaryButton.Text = if canAfford
			then `UNLOCK  🔩 {Theme.formatNumber(def.Price)}`
			else `🔒 {Theme.formatNumber(def.Price - data.scrap)} MORE SCRAP`
		Theme.setButtonColor(
			primaryButton,
			if canAfford then C.Gold else C.PanelLight,
			if canAfford then nil else C.Muted
		)
	elseif data.equipped == def.Id then
		primaryButton.Text = "✅ DRIVING THIS"
		Theme.setButtonColor(primaryButton, C.PanelLight, C.Muted)
	else
		primaryButton.Text = "DRIVE THIS CAR"
		Theme.setButtonColor(primaryButton, C.Good)
	end
	if owned and progress.ready then
		secondaryButton.Visible = true
		secondaryButton.Text = "✨ EVOLVE!"
		Theme.setButtonColor(secondaryButton, if pulse then C.Evolve else rgb(214, 160, 255), C.Text)
	elseif owned and previewStage <= stage and previewStage ~= look then
		secondaryButton.Visible = true
		secondaryButton.Text = "USE THIS LOOK"
		Theme.setButtonColor(secondaryButton, C.Blue, C.Text)
	else
		secondaryButton.Visible = false
	end
end

local function selectCar(id: string)
	selectedId = id
	local data = PlayerDataClient.get()
	previewStage = if data.owned[id] then data.carLook[id] or 1 else 1
	refresh()
end

local function onPrimary()
	local def = selectedDef()
	local data = PlayerDataClient.get()
	if data.equipped == def.Id then
		return
	elseif data.owned[def.Id] then
		request("equip", def)
	elseif data.scrap >= def.Price then
		request("unlock", def)
	else
		showToast(`You need {Theme.formatNumber(def.Price - data.scrap)} more Scrap. Keep playing!`, false)
	end
end

local function onSecondary()
	local def = selectedDef()
	local data = PlayerDataClient.get()
	local stage = data.carStage[def.Id] or 1
	local progress = Evolution.progress(def, data.carXp[def.Id] or 0, stage)
	if progress.ready then
		local result = request("evolve", def)
		if result and result.evolved then
			previewStage = stage + 1
			celebrate(def, stage + 1)
		end
	elseif previewStage <= stage then
		request("look", def, previewStage)
	end
end

local function buildTile(parent: Instance, def: CarCatalog.CarDef, order: number): Tile
	local button = Instance.new("TextButton")
	button.Name = def.Id
	button.LayoutOrder = order
	button.Text = ""
	button.AutoButtonColor = true
	button.BackgroundColor3 = C.PanelLight
	button.Parent = parent
	Theme.corner(button, 14)
	Theme.stroke(button, CarCatalog.Rarities[def.Rarity].Color, 2)
	local viewport = makeViewport(button, UDim2.new(1, -12, 0, 100), UDim2.fromOffset(6, 6))
	Theme.corner(viewport, 10)
	Theme.label(button, {
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 110),
		text = `{def.Emoji} {def.DisplayName}`,
	})
	local status = Theme.label(button, {
		size = UDim2.new(1, -12, 0, 18),
		position = UDim2.fromOffset(6, 134),
		text = "",
		font = Enum.Font.GothamBlack,
		stroke = false,
	})
	button.Activated:Connect(function()
		selectCar(def.Id)
	end)
	return { def = def, button = button, viewport = viewport, model = nil, shownStage = 0, status = status }
end

local function buildDetails(parent: Frame)
	detailViewport = makeViewport(parent, UDim2.new(1, 0, 0, 196), UDim2.new())
	Theme.corner(detailViewport, 14)
	nameLabel = Theme.label(parent, {
		size = UDim2.new(1, 0, 0, 38),
		position = UDim2.fromOffset(0, 204),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	rarityLabel = Theme.label(parent, {
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(2, 244),
		text = "",
		font = Enum.Font.GothamBlack,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	descriptionLabel = Theme.label(parent, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(2, 264),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	for i, row in STAT_ROWS do
		local column = if i <= 3 then 0 else 1
		local y = 290 + ((i - 1) % 3) * 22
		local x = column * 320
		Theme.label(parent, {
			size = UDim2.fromOffset(80, 16),
			position = UDim2.fromOffset(x, y),
			text = row.label,
			font = Theme.Body,
			color = C.Muted,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
		table.insert(statBars, {
			key = row.key,
			bar = Theme.bar(parent, UDim2.fromOffset(210, 12), UDim2.fromOffset(x + 84, y + 2), C.Gold),
		})
	end

	-- Evolution track: one node per stage, joined by a line that fills up as the car evolves.
	Theme.label(parent, {
		size = UDim2.fromOffset(300, 18),
		position = UDim2.fromOffset(0, 362),
		text = "✨ EVOLUTION",
		font = Enum.Font.GothamBlack,
		color = C.Evolve,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -120, 0, 6)
	track.Position = UDim2.fromOffset(60, 403)
	track.BackgroundColor3 = C.PanelDark
	track.BorderSizePixel = 0
	track.Parent = parent
	trackFill = Instance.new("Frame")
	trackFill.Name = "Fill"
	trackFill.Size = UDim2.fromScale(0, 1)
	trackFill.BackgroundColor3 = C.Evolve
	trackFill.BorderSizePixel = 0
	trackFill.Parent = track
	for i = 1, STAGES do
		local x = 60 + (i - 1) / (STAGES - 1) * 512
		local circle = Instance.new("TextButton")
		circle.Name = `Stage{i}`
		circle.Size = UDim2.fromOffset(42, 42)
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromOffset(x, 406)
		circle.BackgroundColor3 = C.PanelDark
		circle.Text = tostring(i)
		circle.Font = Theme.Title
		circle.TextScaled = true
		circle.TextColor3 = C.Text
		circle.AutoButtonColor = true
		circle.ZIndex = 2
		circle.Parent = parent
		Theme.corner(circle, 21)
		Theme.stroke(circle, rgb(0, 0, 0), 2)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.22, 0)
		padding.PaddingBottom = UDim.new(0.22, 0)
		padding.Parent = circle
		local name = Theme.label(parent, {
			size = UDim2.fromOffset(110, 16),
			position = UDim2.fromOffset(x, 430),
			anchor = Vector2.new(0.5, 0),
			text = "",
			font = Theme.Body,
			stroke = false,
		})
		circle.Activated:Connect(function()
			previewStage = i
			refresh()
		end)
		table.insert(nodes, { circle = circle :: any, name = name })
	end

	xpBar = Theme.bar(parent, UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 456), C.Evolve)
	xpLabel = Theme.label(parent, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 476),
		text = "",
		font = Theme.Body,
		stroke = false,
	})

	primaryButton = Theme.button(parent, {
		name = "Primary",
		size = UDim2.new(0.5, -6, 0, 50),
		position = UDim2.fromOffset(0, 500),
		text = "",
	})
	primaryButton.Activated:Connect(onPrimary)
	secondaryButton = Theme.button(parent, {
		name = "Secondary",
		size = UDim2.new(0.5, -6, 0, 50),
		position = UDim2.new(0.5, 6, 0, 500),
		text = "",
		color = C.Evolve,
		textColor = C.Text,
	})
	secondaryButton.Activated:Connect(onSecondary)
end

local function build()
	gui = Theme.screen("TurboGarage", 12)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = gui

	panel = Theme.panel(gui, "Garage", UDim2.fromOffset(1080, 640), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)
	Theme.label(panel, {
		size = UDim2.fromOffset(300, 44),
		text = "🚗 GARAGE",
		align = Enum.TextXAlignment.Left,
	})
	scrapPill = Theme.pill(panel, {
		size = UDim2.fromOffset(200, 42),
		position = UDim2.new(1, -60, 0, 2),
		anchor = Vector2.new(1, 0),
		text = "",
		color = C.Scrap,
	})
	local close = Theme.button(panel, {
		size = UDim2.fromOffset(46, 46),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "X",
		color = C.Bad,
		textColor = C.Text,
	})
	close.Activated:Connect(function()
		Garage.close()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Cars"
	list.Size = UDim2.new(0, 404, 1, -62)
	list.Position = UDim2.fromOffset(0, 60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(194, 160)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, def in CarCatalog.ordered() do
		table.insert(tiles, buildTile(list, def, i))
	end

	local details = Instance.new("Frame")
	details.Name = "Details"
	details.Size = UDim2.new(1, -424, 1, -62)
	details.Position = UDim2.fromOffset(424, 60)
	details.BackgroundTransparency = 1
	details.Parent = panel
	buildDetails(details)

	toast = Theme.pill(panel, {
		size = UDim2.fromOffset(620, 36),
		position = UDim2.new(0.5, 0, 1, 26),
		anchor = Vector2.new(0.5, 0),
		text = "",
		background = C.PanelDark,
	})
	toast.Visible = false

	celebration = Instance.new("Frame")
	celebration.Name = "Evolved"
	celebration.Size = UDim2.fromScale(1, 1)
	celebration.BackgroundColor3 = rgb(255, 255, 255)
	celebration.ZIndex = 10
	celebration.Visible = false
	celebration.Parent = panel
	Theme.corner(celebration, 16)
	celebrationTitle = Theme.label(celebration, {
		size = UDim2.new(1, 0, 0, 90),
		position = UDim2.fromScale(0.5, 0.36),
		anchor = Vector2.new(0.5, 0.5),
		text = "✨ EVOLVED! ✨",
		color = C.Gold,
		zIndex = 11,
	})
	celebrationName = Theme.label(celebration, {
		size = UDim2.new(1, 0, 0, 46),
		position = UDim2.fromScale(0.5, 0.52),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 11,
	})

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Opens the garage, showing `carId` (or your current car).
function Garage.open(carId: string?)
	local data = PlayerDataClient.get()
	selectCar(if carId and CarCatalog.get(carId) then carId else data.equipped)
	gui.Enabled = true
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
end

function Garage.close()
	gui.Enabled = false
end

function Garage.isOpen(): boolean
	return gui.Enabled
end

function Garage.start()
	build()
	selectCar(PlayerDataClient.get().equipped)
	PlayerDataClient.Changed:Connect(function()
		refresh()
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		if not gui.Enabled then
			return
		end
		spin += dt * 0.8
		local turn = CFrame.Angles(0, spin, 0)
		for _, tile in tiles do
			if tile.model then
				tile.model:PivotTo(turn)
			end
		end
		if detailModel then
			detailModel:PivotTo(turn)
		end
		-- A few times a second, so the "ready to evolve" button pulses.
		if os.clock() - lastRefresh > 0.15 then
			refresh()
		end
	end)
end

return Garage
