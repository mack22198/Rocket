--!strict
-- The garage, laid over the 3D showroom: your cars on the left, the chosen car big on the turntable in the
-- middle, and on the right its ultimate, its strengths and weaknesses, its evolution track and the button
-- for the next step (unlock, FUSE, drive it, EVOLVE, or pick one of the looks it has earned). Prices are fixed
-- and shown up front; evolving is earned by driving the car, and a fused car is made from two cars you own
-- (you keep both). Changes apply from your next match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local Evolution = require(Shared.Config.Evolution)
local GameConfig = require(Shared.Config.GameConfig)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local ShowroomController = require(script.Parent.Parent.Controllers.ShowroomController)
local StylePanel = require(script.Parent.StylePanel)
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
local carsCaption: TextLabel
local carsScroller: ScrollingFrame
local detailsPanel: Frame
local carsTab: TextButton
local styleTab: TextButton
local mode = "cars" -- "cars" or "style"
local backButton: TextButton
local scrapAmount: Theme.Amount
local countLabel: TextLabel
local toast: TextLabel
local tiles: { Tile } = {}
local nameLabel: TextLabel
local rarityLabel: TextLabel
local rarityTag: TextLabel
local powerIcon: TextLabel
local powerName: TextLabel
local powerText: TextLabel
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

local function showToast(text: string, good: boolean)
	text = Theme.noEmoji(text)
	toast.Text = text
	toast.BackgroundColor3 = if good then C.Good else C.Bad
	toast.TextColor3 = C.Text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0
	toast.Visible = true
	task.delay(2.8, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function()
				if toast.Text == text then
					toast.Visible = false
				end
			end)
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
	viewport.BackgroundColor3 = rgb(64, 72, 116)
	viewport.Ambient = rgb(170, 172, 196)
	viewport.LightColor = rgb(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = parent
	Theme.gradient(viewport, rgb(255, 255, 255), rgb(150, 155, 180))
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

-- The big "it evolved!" (or "fused!") moment: a white flash, the new name, and a light show in the showroom.
local function celebrate(def: CarCatalog.CarDef, stage: number, title: string?)
	celebrationTitle.Text = title or "EVOLVED!"
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
	SoundController.play("Fanfare", 0.8)
	task.delay(2.6, function()
		TweenService:Create(celebrationTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(celebrationName, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		celebration.Visible = false
	end)
end

-- The first of a fused car's two parts that you don't have yet (nil if you have both).
local function missingParent(def: CarCatalog.CarDef, owned: { [string]: boolean }): CarCatalog.CarDef?
	local base, flavor = CarCatalog.parents(def)
	for _, parent in { base, flavor } do
		if parent and not owned[parent.Id] then
			return parent
		end
	end
	return nil
end

local function refresh()
	lastRefresh = os.clock()
	local data = PlayerDataClient.get()
	scrapAmount.set(data.scrap)

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
		tile.viewport.ImageColor3 = if owned then rgb(255, 255, 255) else rgb(70, 74, 96)
		local selected = id == selectedId
		tile.button.BackgroundColor3 = if selected then C.Gold else C.CardShade
		local stroke = tile.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if selected then 4 else 2
		end
		if data.equipped == id then
			tile.status.Text = "DRIVING"
			tile.status.TextColor3 = if selected then C.Ink else C.GoodText
		elseif owned then
			local ready = Evolution.progress(tile.def, data.carXp[id] or 0, data.carStage[id] or 1).ready
			tile.status.Text = if ready then "EVOLVE!" else "OWNED"
			tile.status.TextColor3 = if ready then C.Evolve else C.InkMuted
		elseif tile.def.Fusion then
			local canFuse = CarCatalog.canFuse(tile.def, data.owned, data.scrap)
			tile.status.Text = if canFuse then "FUSE!" else "FUSION"
			tile.status.TextColor3 = if canFuse then C.Evolve else C.InkMuted
		else
			tile.status.Text = `{Theme.formatNumber(tile.def.Price)} SCRAP`
			tile.status.TextColor3 = if data.scrap >= tile.def.Price then C.Ink else C.InkMuted
		end
	end
	countLabel.Text = `{ownedCount}/{#tiles} OWNED`

	-- Details.
	local def = selectedDef()
	local owned = data.owned[def.Id] == true
	local stage = if owned then data.carStage[def.Id] or 1 else 1
	local look = if owned then data.carLook[def.Id] or 1 else 1
	local xp = if owned then data.carXp[def.Id] or 0 else 0
	local progress = Evolution.progress(def, xp, stage)
	local rarity = CarCatalog.Rarities[def.Rarity]

	if gui.Enabled and mode == "cars" then
		ShowroomController.showCar(def, previewStage, data.style.topper)
	end
	nameLabel.Text = string.upper(CarCatalog.stageName(def, previewStage))
	local base, flavor = CarCatalog.parents(def)
	rarityTag.Text = if base and flavor then "FUSED" else string.upper(def.Rarity)
	rarityTag.BackgroundColor3 = rarity.Color
	rarityTag.TextColor3 = if Theme.isLight(rarity.Color) then C.Ink else C.Text
	rarityLabel.Text = if base and flavor
		then `{string.upper(base.DisplayName)} + {string.upper(flavor.DisplayName)}`
		else string.upper(def.Tagline)
	descriptionLabel.Text = def.Description
	local power = Powers.forCar(def.Id)
	powerIcon.Text = power.Emoji
	powerIcon.BackgroundColor3 = power.Color
	powerName.Text = `ULTIMATE: {string.upper(power.Name)}`
	powerText.Text = power.Description
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
		node.circle.Text = if nextReady then "!" else tostring(i)
		node.circle.BackgroundColor3 = if reached then C.Evolve elseif nextReady then C.Gold else C.CardShade
		node.circle.TextColor3 = if reached then C.Text elseif nextReady then C.Ink else C.InkMuted
		local ring = node.circle:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Thickness = if i == previewStage then 5 else 3
		end
		node.name.Text = shortStageName(def, i)
		node.name.TextColor3 = if i == previewStage or reached then C.Ink else C.InkMuted
		node.name.Font = if i == previewStage then Theme.Caps else Theme.Body
		if nextReady and pulse then
			node.circle.BackgroundColor3 = C.Evolve
		end
	end
	trackFill.Size = UDim2.fromScale((math.max(stage, 1) - 1) / (STAGES - 1), 1)

	if not owned and base and flavor then
		xpBar.set(0)
		xpLabel.Text = `Fuse your {base.DisplayName} and {flavor.DisplayName} to make it (you keep both!)`
	elseif not owned then
		xpBar.set(0)
		xpLabel.Text = "Unlock this car to start evolving it"
	elseif progress.nextStage then
		xpBar.set(progress.fraction)
		xpLabel.Text = if progress.ready
			then `READY! Evolve into the {progress.nextName}`
			else `{Theme.formatNumber(xp)} / {Theme.formatNumber(progress.xpForNext)} XP to {progress.nextName}`
	else
		xpBar.set(1)
		xpLabel.Text = "Fully evolved!"
	end
	xpLabel.TextColor3 = if owned and progress.ready then C.Evolve else C.InkMuted

	-- Buttons.
	local fusion = def.Fusion
	if not owned and fusion then
		local canFuse = CarCatalog.canFuse(def, data.owned, data.scrap)
		local missing = missingParent(def, data.owned)
		primaryButton.Text = if canFuse
			then `FUSE: {Theme.formatNumber(fusion.Cost)} SCRAP`
			elseif missing then `NEEDS THE {string.upper(missing.DisplayName)}`
			else `{Theme.formatNumber(fusion.Cost - data.scrap)} MORE SCRAP`
		Theme.setButtonColor(
			primaryButton,
			if canFuse then C.Evolve else C.CardLine,
			if canFuse then nil else C.InkMuted
		)
	elseif not owned then
		local canAfford = data.scrap >= def.Price
		primaryButton.Text = if canAfford
			then `UNLOCK: {Theme.formatNumber(def.Price)} SCRAP`
			else `{Theme.formatNumber(def.Price - data.scrap)} MORE SCRAP`
		Theme.setButtonColor(
			primaryButton,
			if canAfford then C.Gold else C.CardLine,
			if canAfford then nil else C.InkMuted
		)
	elseif data.equipped == def.Id then
		primaryButton.Text = "DRIVING THIS ONE"
		Theme.setButtonColor(primaryButton, C.CardLine, C.InkMuted)
	else
		primaryButton.Text = "DRIVE THIS CAR"
		Theme.setButtonColor(primaryButton, C.Good)
	end
	if owned and progress.ready then
		secondaryButton.Visible = true
		secondaryButton.Text = "EVOLVE!"
		Theme.setButtonColor(secondaryButton, if pulse then C.Evolve else rgb(186, 146, 255), C.Text)
	elseif owned and previewStage <= stage and previewStage ~= look then
		secondaryButton.Visible = true
		secondaryButton.Text = "USE THIS LOOK"
		Theme.setButtonColor(secondaryButton, C.Sky)
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
	elseif def.Fusion then
		local canFuse, reason = CarCatalog.canFuse(def, data.owned, data.scrap)
		if not canFuse then
			showToast(reason or "You can't fuse this car yet.", false)
			return
		end
		local result = request("fuse", def)
		if result and result.fused then
			celebrate(def, 1, "FUSED!")
		end
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
	button.BackgroundColor3 = C.CardShade
	button.Parent = parent
	Theme.corner(button, 12)
	Theme.stroke(button, C.Ink, 2)
	Theme.pop(button)
	local viewport = makeViewport(button, UDim2.new(1, -12, 0, 72), UDim2.fromOffset(6, 6))
	Theme.corner(viewport, 8)
	Theme.label(button, {
		size = UDim2.new(1, -12, 0, 18),
		position = UDim2.fromOffset(6, 82),
		text = def.DisplayName,
		textSize = 14,
	})
	local status = Theme.label(button, {
		size = UDim2.new(1, -12, 0, 13),
		position = UDim2.fromOffset(6, 103),
		text = "",
		font = Theme.Caps,
		textSize = 11,
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
		size = UDim2.fromOffset(110, 50),
		position = UDim2.fromOffset(24, 64),
		text = "BACK",
		color = C.Panel,
		textSize = 22,
	})
	backButton.Activated:Connect(function()
		Garage.BackPressed:Fire()
	end)
	Theme.heading(leftGroup, {
		name = "Title",
		size = UDim2.fromOffset(200, 50),
		position = UDim2.fromOffset(148, 64),
		text = "GARAGE",
		color = C.Text,
		textSize = 46,
		align = Enum.TextXAlignment.Left,
		stroke = true,
	})

	local list = Theme.card(leftGroup, "Cars", UDim2.fromOffset(318, 572), UDim2.fromOffset(24, 126))
	Theme.padding(list, 12)
	-- CARS / STYLE tabs.
	carsTab = Theme.button(list, {
		name = "CarsTab",
		size = UDim2.fromOffset(143, 42),
		text = "CARS",
		color = C.Gold,
		textSize = 20,
	})
	carsTab.Activated:Connect(function()
		Garage.setMode("cars")
	end)
	styleTab = Theme.button(list, {
		name = "StyleTab",
		size = UDim2.fromOffset(143, 42),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "STYLE",
		color = C.CardShade,
		textSize = 20,
	})
	styleTab.Activated:Connect(function()
		Garage.setMode("style")
	end)
	carsCaption = Theme.label(list, {
		size = UDim2.fromOffset(160, 16),
		position = UDim2.fromOffset(2, 54),
		text = "YOUR CARS",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	countLabel = Theme.label(list, {
		size = UDim2.fromOffset(130, 16),
		position = UDim2.new(1, -2, 0, 54),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Ink,
		textSize = 13,
		align = Enum.TextXAlignment.Right,
	})
	local scroller = Instance.new("ScrollingFrame")
	carsScroller = scroller
	scroller.Name = "List"
	scroller.Size = UDim2.new(1, 4, 1, -78)
	scroller.Position = UDim2.fromOffset(0, 78)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = C.Ink
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(141, 124)
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

	local wallet =
		Theme.card(rightGroup, "Scrap", UDim2.fromOffset(170, 52), UDim2.fromOffset(396, 64), Vector2.new(1, 0))
	scrapAmount = Theme.amount(wallet, 30, UDim2.new(0.5, 0, 0.5, -2), Vector2.new(0.5, 0.5))

	local panel =
		Theme.card(rightGroup, "Details", UDim2.fromOffset(372, 572), UDim2.fromOffset(396, 126), Vector2.new(1, 0))
	detailsPanel = panel
	Theme.padding(panel, 16)
	nameLabel = Theme.heading(panel, {
		name = "CarName",
		size = UDim2.new(1, 0, 0, 34),
		text = "",
		textSize = 32,
		align = Enum.TextXAlignment.Left,
	})
	nameLabel.TextWrapped = false
	rarityTag = Theme.pill(panel, {
		name = "RarityTag",
		size = UDim2.fromOffset(96, 22),
		position = UDim2.fromOffset(0, 40),
		text = "",
	})
	rarityLabel = Theme.label(panel, {
		name = "Rarity",
		size = UDim2.new(1, -108, 0, 14),
		position = UDim2.fromOffset(108, 44),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Left,
	})
	-- The car's ultimate.
	local powerCard = Theme.well(panel, "Power", UDim2.new(1, 0, 0, 58), UDim2.fromOffset(0, 72))
	powerIcon = Theme.label(powerCard, {
		name = "Icon",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.fromOffset(7, 7),
		text = "",
		color = C.Text,
		textSize = 30,
	})
	powerIcon.BackgroundTransparency = 0
	Theme.corner(powerIcon, 10)
	Theme.stroke(powerIcon, C.Ink, 2)
	powerName = Theme.label(powerCard, {
		name = "PowerName",
		size = UDim2.new(1, -70, 0, 16),
		position = UDim2.fromOffset(62, 9),
		text = "",
		font = Theme.Caps,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})
	powerText = Theme.label(powerCard, {
		name = "PowerText",
		size = UDim2.new(1, -70, 0, 26),
		position = UDim2.fromOffset(62, 27),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Left,
	})
	descriptionLabel = Theme.label(panel, {
		name = "Description",
		size = UDim2.new(1, 0, 0, 32),
		position = UDim2.fromOffset(1, 138),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	for i, row in STAT_ROWS do
		local y = 176 + (i - 1) * 20
		Theme.label(panel, {
			size = UDim2.fromOffset(70, 16),
			position = UDim2.fromOffset(0, y),
			text = row.label,
			font = Theme.Caps,
			textSize = 12,
			align = Enum.TextXAlignment.Left,
		})
		table.insert(statBars, {
			key = row.key,
			bar = Theme.bar(panel, UDim2.new(1, -78, 0, 12), UDim2.fromOffset(78, y + 2), C.Gold, C.CardLine),
		})
	end

	-- Evolution track: one node per stage, joined by a line that fills up as the car evolves. Tap a node to see
	-- that look on the turntable.
	Theme.label(panel, {
		size = UDim2.fromOffset(200, 16),
		position = UDim2.fromOffset(0, 282),
		text = "EVOLUTION",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	local trackLeft, span = 26, 288
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromOffset(span, 8)
	track.Position = UDim2.fromOffset(trackLeft, 318)
	track.BackgroundColor3 = C.CardLine
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
		circle.Position = UDim2.fromOffset(x, 322)
		circle.BackgroundColor3 = C.CardShade
		circle.Text = tostring(i)
		circle.Font = Theme.Display
		circle.TextScaled = true
		circle.TextColor3 = C.Text
		circle.AutoButtonColor = true
		circle.ZIndex = 2
		circle.Parent = panel
		Theme.corner(circle, 20)
		Theme.stroke(circle, C.Ink, 3)
		Theme.pop(circle)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.2, 0)
		padding.PaddingBottom = UDim.new(0.16, 0)
		padding.Parent = circle
		local name = Theme.label(panel, {
			size = UDim2.fromOffset(84, 15),
			position = UDim2.fromOffset(x, 346),
			anchor = Vector2.new(0.5, 0),
			text = "",
			font = Theme.Body,
			textSize = 12,
		})
		circle.Activated:Connect(function()
			previewStage = i
			refresh()
		end)
		table.insert(nodes, { circle = circle, name = name })
	end

	xpBar = Theme.bar(panel, UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 370), C.Evolve, C.CardLine)
	xpLabel = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 388),
		text = "",
		font = Theme.Body,
		textSize = 13,
	})

	primaryButton = Theme.button(panel, {
		name = "Primary",
		size = UDim2.new(1, 0, 0, 62),
		position = UDim2.new(0, 0, 1, -124),
		text = "",
		textSize = 26,
	})
	primaryButton.Activated:Connect(onPrimary)
	secondaryButton = Theme.button(panel, {
		name = "Secondary",
		size = UDim2.new(1, 0, 0, 54),
		position = UDim2.new(0, 0, 1, -54),
		text = "",
		color = C.Evolve,
		textSize = 24,
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
	StylePanel.build(leftGroup:FindFirstChild("Cars") :: Frame, rightGroup, function(text: string, good: boolean)
		showToast(text, good)
	end)
	StylePanel.PreviewChanged:Connect(function()
		if gui.Enabled and mode == "style" then
			local data = PlayerDataClient.get()
			local def = CarCatalog.get(data.equipped) or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
			ShowroomController.showCar(def, data.carLook[def.Id] or 1, StylePanel.previewTopper())
		end
	end)

	toast = Theme.pill(gui, {
		name = "Toast",
		size = UDim2.fromOffset(520, 40),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
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
	celebrationTitle = Theme.heading(celebration, {
		size = UDim2.fromOffset(700, 100),
		position = UDim2.fromScale(0.5, 0.2),
		anchor = Vector2.new(0.5, 0.5),
		text = "EVOLVED!",
		color = C.Gold,
		zIndex = 11,
	})
	Theme.outline(celebrationTitle, 5)
	celebrationName = Theme.heading(celebration, {
		size = UDim2.fromOffset(700, 44),
		position = UDim2.new(0.5, 0, 0.2, 70),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		color = C.Text,
		textSize = 40,
		stroke = true,
		zIndex = 11,
	})
	Theme.scaled(celebrationTitle)
	Theme.scaled(celebrationName)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Switches between the car list ("cars") and hats, horns and goal parties ("style").
function Garage.setMode(newMode: string)
	mode = if newMode == "style" then "style" else "cars"
	local cars = mode == "cars"
	carsCaption.Visible = cars
	countLabel.Visible = cars
	carsScroller.Visible = cars
	detailsPanel.Visible = cars
	StylePanel.setVisible(not cars)
	Theme.setButtonColor(carsTab, if cars then C.Gold else C.CardShade)
	Theme.setButtonColor(styleTab, if cars then C.CardShade else C.Gold)
	refresh()
end

-- Opens the garage, showing `carId` (or your current car).
function Garage.open(carId: string?)
	local data = PlayerDataClient.get()
	local wasOpen = gui.Enabled
	gui.Enabled = true
	if not wasOpen then
		Garage.setMode("cars")
	end
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
