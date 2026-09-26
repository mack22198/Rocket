--!strict
-- The garage, laid over the 3D showroom: your cars on the left, the chosen car big on the turntable in the
-- middle, and on the right its strengths and weaknesses, its evolution track and the button for the next step
-- (unlock, drive it, EVOLVE, or pick one of the looks it has earned). Prices are fixed and shown up front;
-- evolving is earned by driving the car. Changes apply from your next match.

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
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local ShowroomController = require(script.Parent.Parent.Controllers.ShowroomController)
local Theme = require(script.Parent.Theme)

local Garage = {}

-- The BACK button (the menus decide where "back" goes).
Garage.BackPressed = Signal.new() :: Signal.Signal<>

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

type Node = { circle: TextButton, name: TextLabel }

local gui: ScreenGui
local leftGroup: Frame
local rightGroup: Frame
local backButton: TextButton
local scrapPill: TextLabel
local countLabel: TextLabel
local toast: TextLabel
local tiles: { Tile } = {}
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

-- Puts a freshly built car model in a tile's little window, with the camera pulled back to fit it.
local function showInViewport(viewport: ViewportFrame, def: CarCatalog.CarDef, stage: number): Model
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local model = CarModelBuilder.build(def, { preview = true, stage = stage })
	model.Parent = viewport
	local camera = viewport:FindFirstChildOfClass("Camera")
	if camera then
		local back = 9 + def.Hitbox.Z * 0.45
		camera.CFrame = CFrame.lookAt(Vector3.new(0, back * 0.4, back), Vector3.new(0, 0.2, 0))
	end
	return model
end

local function makeViewport(parent: Instance, size: UDim2, position: UDim2): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = size
	viewport.Position = position
	viewport.BackgroundColor3 = rgb(40, 48, 84)
	viewport.Ambient = rgb(170, 172, 196)
	viewport.LightColor = rgb(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = parent
	Theme.gradient(viewport, rgb(255, 255, 255), rgb(110, 115, 140))
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
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

-- The big "it evolved!" moment: a white flash, the new name, and a light show in the showroom.
local function celebrate(def: CarCatalog.CarDef, stage: number)
	celebrationName.Text = CarCatalog.stageName(def, stage)
	celebration.Visible = true
	celebration.BackgroundTransparency = 0.1
	celebrationTitle.TextTransparency = 0
	celebrationName.TextTransparency = 0
	TweenService:Create(celebration, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	celebrationTitle.Size = UDim2.fromOffset(700, 50)
	TweenService:Create(celebrationTitle, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
		Size = UDim2.fromOffset(700, 100),
	}):Play()
	-- Confetti.
	for i = 1, 40 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(10, 16)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.3)
		piece.BackgroundColor3 = ({ C.Gold, C.Evolve, C.Blue, C.Orange, C.Good })[i % 5 + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = i * 37
		piece.Parent = celebration
		local angle = i / 40 * math.pi * 2
		TweenService:Create(piece, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * 460, 0.3, math.sin(angle) * 280),
			Rotation = i * 37 + 360,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(1.4, function()
			piece:Destroy()
		end)
	end
	ShowroomController.celebrate()
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.8)
	task.delay(2.6, function()
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
	local ownedCount = 0
	for _, tile in tiles do
		local id = tile.def.Id
		local owned = data.owned[id] == true
		if owned then
			ownedCount += 1
		end
		local look = if owned then data.carLook[id] or 1 else 1
		if tile.shownStage ~= look or not tile.model then
			tile.model = showInViewport(tile.viewport, tile.def, look)
			tile.shownStage = look
		end
		tile.viewport.ImageColor3 = if owned then rgb(255, 255, 255) else rgb(95, 100, 125)
		tile.button.BackgroundColor3 = if id == selectedId then rgb(58, 70, 120) else C.PanelLight
		local stroke = tile.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == selectedId then C.Gold else CarCatalog.Rarities[tile.def.Rarity].Color
			stroke.Thickness = if id == selectedId then 4 else 2
			stroke.Transparency = if id == selectedId then 0 else 0.3
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
	countLabel.Text = `{ownedCount} / {#tiles} OWNED`

	-- Details.
	local def = selectedDef()
	local owned = data.owned[def.Id] == true
	local stage = if owned then data.carStage[def.Id] or 1 else 1
	local look = if owned then data.carLook[def.Id] or 1 else 1
	local xp = if owned then data.carXp[def.Id] or 0 else 0
	local progress = Evolution.progress(def, xp, stage)
	local rarity = CarCatalog.Rarities[def.Rarity]

	if gui.Enabled then
		ShowroomController.showCar(def, previewStage)
	end
	nameLabel.Text = `{def.Emoji} {CarCatalog.stageName(def, previewStage)}`
	rarityLabel.Text = `{string.upper(def.Rarity)}  ·  {string.upper(def.Tagline)}`
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
		node.name.TextColor3 = if i == previewStage then C.Gold elseif reached then C.Text else C.Muted
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
		local result = request("unlock", def)
		if result and result.ok then
			ShowroomController.celebrate()
		end
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
			refresh()
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
	Theme.corner(button, 12)
	Theme.stroke(button, CarCatalog.Rarities[def.Rarity].Color, 2)
	Theme.pop(button)
	local viewport = makeViewport(button, UDim2.new(1, -10, 0, 74), UDim2.fromOffset(5, 5))
	Theme.corner(viewport, 9)
	Theme.label(button, {
		size = UDim2.new(1, -10, 0, 20),
		position = UDim2.fromOffset(5, 82),
		text = `{def.Emoji} {def.DisplayName}`,
	})
	local status = Theme.label(button, {
		size = UDim2.new(1, -10, 0, 14),
		position = UDim2.fromOffset(5, 105),
		text = "",
		font = Theme.Caps,
		stroke = false,
	})
	button.Activated:Connect(function()
		selectCar(def.Id)
	end)
	return { def = def, button = button, viewport = viewport, model = nil, shownStage = 0, status = status }
end

local function buildLeft()
	leftGroup = Instance.new("Frame")
	leftGroup.Name = "Left"
	leftGroup.Size = UDim2.fromOffset(360, 720)
	leftGroup.BackgroundTransparency = 1
	leftGroup.Parent = gui
	Theme.scaled(leftGroup)

	backButton = Theme.button(leftGroup, {
		name = "Back",
		size = UDim2.fromOffset(120, 50),
		position = UDim2.fromOffset(24, 64),
		text = "◀ BACK",
		color = C.PanelLight,
		textColor = C.Text,
	})
	backButton.Activated:Connect(function()
		Garage.BackPressed:Fire()
	end)
	Theme.label(leftGroup, {
		name = "Title",
		size = UDim2.fromOffset(200, 46),
		position = UDim2.fromOffset(158, 66),
		text = "GARAGE",
		align = Enum.TextXAlignment.Left,
	})

	local list = Theme.panel(leftGroup, "Cars", UDim2.fromOffset(318, 572), UDim2.fromOffset(24, 126))
	list.BackgroundTransparency = 0.15
	Theme.padding(list, 12)
	Theme.label(list, {
		size = UDim2.fromOffset(160, 18),
		text = "YOUR CARS",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	countLabel = Theme.label(list, {
		size = UDim2.fromOffset(130, 18),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.Size = UDim2.new(1, 0, 1, -28)
	scroller.Position = UDim2.fromOffset(0, 28)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 5
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(141, 126)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller
	for i, def in CarCatalog.ordered() do
		table.insert(tiles, buildTile(scroller, def, i))
	end
end

local function buildRight()
	rightGroup = Instance.new("Frame")
	rightGroup.Name = "Right"
	rightGroup.Size = UDim2.fromOffset(420, 720)
	rightGroup.Position = UDim2.fromScale(1, 0)
	rightGroup.AnchorPoint = Vector2.new(1, 0)
	rightGroup.BackgroundTransparency = 1
	rightGroup.Parent = gui
	Theme.scaled(rightGroup)

	scrapPill = Theme.pill(rightGroup, {
		name = "Scrap",
		size = UDim2.fromOffset(200, 46),
		position = UDim2.fromOffset(396, 66),
		anchor = Vector2.new(1, 0),
		text = "",
		color = C.Scrap,
	})

	local panel =
		Theme.panel(rightGroup, "Details", UDim2.fromOffset(372, 572), UDim2.fromOffset(396, 126), Vector2.new(1, 0))
	panel.BackgroundTransparency = 0.15
	Theme.padding(panel, 16)
	nameLabel = Theme.label(panel, {
		name = "CarName",
		size = UDim2.new(1, 0, 0, 36),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	rarityLabel = Theme.label(panel, {
		name = "Rarity",
		size = UDim2.new(1, 0, 0, 15),
		position = UDim2.fromOffset(1, 40),
		text = "",
		font = Theme.Caps,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	descriptionLabel = Theme.label(panel, {
		name = "Description",
		size = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromOffset(1, 60),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	for i, row in STAT_ROWS do
		local y = 106 + (i - 1) * 23
		Theme.label(panel, {
			size = UDim2.fromOffset(70, 16),
			position = UDim2.fromOffset(0, y),
			text = row.label,
			font = Theme.Body,
			color = C.Muted,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
		table.insert(statBars, {
			key = row.key,
			bar = Theme.bar(panel, UDim2.new(1, -78, 0, 12), UDim2.fromOffset(78, y + 2), C.Gold),
		})
	end

	-- Evolution track: one node per stage, joined by a line that fills up as the car evolves. Tap a node to see
	-- that look on the turntable.
	Theme.label(panel, {
		size = UDim2.fromOffset(200, 16),
		position = UDim2.fromOffset(0, 230),
		text = "✨ EVOLUTION",
		font = Theme.Caps,
		color = C.Evolve,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	local trackLeft, span = 26, 288
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromOffset(span, 6)
	track.Position = UDim2.fromOffset(trackLeft, 273)
	track.BackgroundColor3 = C.PanelDark
	track.BorderSizePixel = 0
	track.Parent = panel
	trackFill = Instance.new("Frame")
	trackFill.Name = "Fill"
	trackFill.Size = UDim2.fromScale(0, 1)
	trackFill.BackgroundColor3 = C.Evolve
	trackFill.BorderSizePixel = 0
	trackFill.Parent = track
	for i = 1, STAGES do
		local x = trackLeft + (i - 1) / (STAGES - 1) * span
		local circle = Instance.new("TextButton")
		circle.Name = `Stage{i}`
		circle.Size = UDim2.fromOffset(40, 40)
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromOffset(x, 276)
		circle.BackgroundColor3 = C.PanelDark
		circle.Text = tostring(i)
		circle.Font = Theme.Title
		circle.TextScaled = true
		circle.TextColor3 = C.Text
		circle.AutoButtonColor = true
		circle.ZIndex = 2
		circle.Parent = panel
		Theme.corner(circle, 20)
		Theme.stroke(circle, rgb(0, 0, 0), 2)
		Theme.pop(circle)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.22, 0)
		padding.PaddingBottom = UDim.new(0.22, 0)
		padding.Parent = circle
		local name = Theme.label(panel, {
			size = UDim2.fromOffset(84, 15),
			position = UDim2.fromOffset(x, 300),
			anchor = Vector2.new(0.5, 0),
			text = "",
			font = Theme.Body,
			stroke = false,
		})
		circle.Activated:Connect(function()
			previewStage = i
			refresh()
		end)
		table.insert(nodes, { circle = circle, name = name })
	end

	xpBar = Theme.bar(panel, UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 330), C.Evolve)
	xpLabel = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 350),
		text = "",
		font = Theme.Body,
		stroke = false,
	})

	primaryButton = Theme.button(panel, {
		name = "Primary",
		size = UDim2.new(1, 0, 0, 62),
		position = UDim2.new(0, 0, 1, -122),
		text = "",
	})
	primaryButton.Activated:Connect(onPrimary)
	secondaryButton = Theme.button(panel, {
		name = "Secondary",
		size = UDim2.new(1, 0, 0, 52),
		position = UDim2.new(0, 0, 1, -52),
		text = "",
		color = C.Evolve,
		textColor = C.Text,
	})
	secondaryButton.Activated:Connect(onSecondary)
end

local function build()
	gui = Theme.screen("TurboGarage", 12)
	gui.Enabled = false
	Theme.shade(gui, "LeftShade", true, 0.32, 0.6)
	Theme.shade(gui, "RightShade", false, 0.36, 0.6)
	buildLeft()
	buildRight()

	toast = Theme.pill(gui, {
		name = "Toast",
		size = UDim2.fromOffset(520, 38),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
		background = C.PanelDark,
	})
	toast.Visible = false
	Theme.scaled(toast)

	celebration = Instance.new("Frame")
	celebration.Name = "Evolved"
	celebration.Size = UDim2.fromScale(1, 1)
	celebration.BackgroundColor3 = rgb(255, 255, 255)
	celebration.BackgroundTransparency = 1
	celebration.ZIndex = 10
	celebration.Visible = false
	celebration.Parent = gui
	celebrationTitle = Theme.label(celebration, {
		size = UDim2.fromOffset(700, 100),
		position = UDim2.fromScale(0.5, 0.2),
		anchor = Vector2.new(0.5, 0.5),
		text = "✨ EVOLVED! ✨",
		color = C.Gold,
		zIndex = 11,
	})
	Theme.stroke(celebrationTitle, rgb(40, 10, 60), 5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	celebrationName = Theme.label(celebration, {
		size = UDim2.fromOffset(700, 44),
		position = UDim2.new(0.5, 0, 0.2, 70),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 11,
	})
	Theme.scaled(celebrationTitle)
	Theme.scaled(celebrationName)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Opens the garage, showing `carId` (or your current car).
function Garage.open(carId: string?)
	local data = PlayerDataClient.get()
	local wasOpen = gui.Enabled
	gui.Enabled = true
	selectCar(if carId and CarCatalog.get(carId) then carId else data.equipped)
	if wasOpen then
		return
	end
	leftGroup.Position = UDim2.fromOffset(-60, 0)
	TweenService:Create(leftGroup, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()
	rightGroup.Position = UDim2.new(1, 60, 0, 0)
	TweenService:Create(rightGroup, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(1, 0),
	}):Play()
	Theme.focus(primaryButton)
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
		-- A few times a second, so the "ready to evolve" button pulses.
		if os.clock() - lastRefresh > 0.15 then
			refresh()
		end
	end)
end

return Garage
