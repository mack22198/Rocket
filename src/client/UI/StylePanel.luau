--!strict
-- The garage's STYLE tab: hats, horns and goal parties (see Cosmetics). The list is on the left (a tab for each
-- kind), and the chosen item on the right with its price and a BUY / EQUIP button. Hats are tried on the car
-- in the showroom, and horns can be heard before you buy them. Prices are fixed and shown up front.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Season = require(Shared.Config.Season)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local StylePanel = {}

-- Fired when the hat to try on the showroom car changes.
StylePanel.PreviewChanged = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB

type Tile = { def: Cosmetics.CosmeticDef, button: TextButton, status: TextLabel }

local left: Frame
local grid: ScrollingFrame
local kindTabs: { [string]: TextButton } = {}
local tiles: { Tile } = {}
local right: Frame
local bigEmoji: TextLabel
local nameLabel: TextLabel
local kindLabel: TextLabel
local descriptionLabel: TextLabel
local statusLabel: TextLabel
local primaryButton: TextButton
local hearButton: TextButton
local toast: (string, boolean) -> () = function(_: string, _: boolean) end

local kind: Cosmetics.Kind = "topper"
local selectedId = ""
local busy = false

local function selected(): Cosmetics.CosmeticDef?
	return Cosmetics.get(selectedId)
end

local function equippedOf(k: Cosmetics.Kind): string
	return (PlayerDataClient.get().style :: any)[k]
end

-- The hat on the showroom car: the one you're looking at on the hats tab, otherwise the one you wear.
function StylePanel.previewTopper(): string
	local def = selected()
	if def and def.Kind == "topper" then
		return def.Id
	end
	return PlayerDataClient.get().style.topper
end

local function playHorn(def: Cosmetics.CosmeticDef)
	if not def.Sound then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Sound
	sound.PlaybackSpeed = def.Pitch or 1
	sound.Volume = 0.9
	sound.Parent = SoundService
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

function StylePanel.refresh()
	local data = PlayerDataClient.get()
	for k, tab in kindTabs do
		Theme.setButtonColor(tab, if k == kind then C.Gold else C.PanelLight, if k == kind then nil else C.Text)
	end
	for _, tile in tiles do
		local def = tile.def
		tile.button.Visible = def.Kind == kind
		local owned = data.style.owned[def.Id] == true
		local on = equippedOf(def.Kind) == def.Id
		if on then
			tile.status.Text = "✅ ON"
			tile.status.TextColor3 = C.Good
		elseif owned then
			tile.status.Text = "OWNED"
			tile.status.TextColor3 = C.Text
		elseif def.Season then
			local theme = Season.theme(def.Season)
			tile.status.Text = if theme then `🏆 {string.upper(theme.Name)}` else "🏆 SEASON"
			tile.status.TextColor3 = C.Evolve
		else
			tile.status.Text = `🔩 {Theme.formatNumber(def.Price)}`
			tile.status.TextColor3 = if data.scrap >= def.Price then C.Gold else C.Muted
		end
		local stroke = tile.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if def.Id == selectedId then C.Gold else rgb(255, 255, 255)
			stroke.Thickness = if def.Id == selectedId then 4 else 2
			stroke.Transparency = if def.Id == selectedId then 0 else 0.8
		end
		tile.button.BackgroundColor3 = if def.Id == selectedId then rgb(58, 70, 120) else C.PanelLight
	end

	local def = selected()
	if not def then
		return
	end
	local owned = data.style.owned[def.Id] == true
	local on = equippedOf(def.Kind) == def.Id
	bigEmoji.Text = def.Emoji
	nameLabel.Text = def.Name
	kindLabel.Text = if def.Kind == "topper"
		then "HAT · SITS ON YOUR ROOF"
		elseif def.Kind == "horn" then "HORN · PRESS H (OR D-PAD UP) IN A MATCH"
		else "GOAL PARTY · WHEN YOU SCORE"
	descriptionLabel.Text = def.Description
	hearButton.Visible = def.Kind == "horn"
	if on then
		statusLabel.Text = "You're using this one."
		primaryButton.Text = "✅ EQUIPPED"
		Theme.setButtonColor(primaryButton, C.PanelLight, C.Muted)
	elseif owned then
		statusLabel.Text = "You own this."
		primaryButton.Text = "USE THIS"
		Theme.setButtonColor(primaryButton, C.Good)
	elseif def.Season then
		local theme = Season.theme(def.Season)
		local name = if theme then `{theme.Emoji} {theme.Name}` else "season"
		statusLabel.Text = `A reward on the {name} season track - keep playing to earn it!`
		primaryButton.Text = "🏆 SEASON REWARD"
		Theme.setButtonColor(primaryButton, C.PanelLight, C.Muted)
	elseif data.scrap >= def.Price then
		statusLabel.Text = "Fixed price - no surprises."
		primaryButton.Text = `BUY  🔩 {Theme.formatNumber(def.Price)}`
		Theme.setButtonColor(primaryButton, C.Gold)
	else
		statusLabel.Text = `You need {Theme.formatNumber(def.Price - data.scrap)} more Scrap.`
		primaryButton.Text = `🔒 🔩 {Theme.formatNumber(def.Price)}`
		Theme.setButtonColor(primaryButton, C.PanelLight, C.Muted)
	end
end

local function choose(id: string)
	selectedId = id
	StylePanel.refresh()
	StylePanel.PreviewChanged:Fire()
end

local function showKind(k: Cosmetics.Kind)
	kind = k
	-- Start on the item you're using of that kind.
	choose(equippedOf(k))
end

local function request(action: string, id: string)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.Garage:InvokeServer(action, id)
	end)
	busy = false
	if ok and type(result) == "table" then
		toast(tostring(result.message), result.ok == true)
	else
		toast("Couldn't reach the garage. Try again!", false)
	end
end

local function onPrimary()
	local def = selected()
	if not def then
		return
	end
	local data = PlayerDataClient.get()
	if equippedOf(def.Kind) == def.Id then
		return
	elseif data.style.owned[def.Id] then
		request("equipStyle", def.Id)
	elseif def.Season then
		toast("Earn it on the season track!", false)
	elseif data.scrap >= def.Price then
		request("buyStyle", def.Id)
	else
		toast(`You need {Theme.formatNumber(def.Price - data.scrap)} more Scrap. Keep playing!`, false)
	end
end

-- Builds the list inside `leftParent` and the details panel inside `rightGroup` (where the car details go).
function StylePanel.build(leftParent: Frame, rightGroup: Frame, showToast: (string, boolean) -> ())
	toast = showToast

	left = Instance.new("Frame")
	left.Name = "Style"
	left.Size = UDim2.new(1, 0, 1, -46)
	left.Position = UDim2.fromOffset(0, 46)
	left.BackgroundTransparency = 1
	left.Visible = false
	left.Parent = leftParent
	for i, k in Cosmetics.Kinds do
		local tab = Theme.button(left, {
			name = `Kind{i}`,
			size = UDim2.fromOffset(96, 30),
			position = UDim2.fromOffset((i - 1) * 100, 0),
			text = Cosmetics.KindNames[k],
			color = C.PanelLight,
			textColor = C.Text,
		})
		tab.Activated:Connect(function()
			showKind(k :: Cosmetics.Kind)
		end)
		kindTabs[k] = tab
	end
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Items"
	grid.Size = UDim2.new(1, 0, 1, -40)
	grid.Position = UDim2.fromOffset(0, 40)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 5
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = left
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(141, 100)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for order, def in Cosmetics.List do
		local button = Instance.new("TextButton")
		button.Name = def.Id
		button.LayoutOrder = order
		button.Text = ""
		button.BackgroundColor3 = C.PanelLight
		button.Parent = grid
		Theme.corner(button, 12)
		Theme.stroke(button, rgb(255, 255, 255), 2)
		Theme.pop(button)
		Theme.label(button, {
			size = UDim2.new(1, 0, 0, 46),
			position = UDim2.fromOffset(0, 6),
			text = def.Emoji,
			stroke = false,
		})
		Theme.label(button, {
			size = UDim2.new(1, -10, 0, 18),
			position = UDim2.fromOffset(5, 56),
			text = def.Name,
			font = Theme.Body,
			stroke = false,
		})
		local status = Theme.label(button, {
			size = UDim2.new(1, -10, 0, 15),
			position = UDim2.fromOffset(5, 78),
			text = "",
			font = Theme.Caps,
			stroke = false,
		})
		button.Activated:Connect(function()
			choose(def.Id)
			if def.Kind == "horn" then
				playHorn(def)
			end
		end)
		table.insert(tiles, { def = def, button = button, status = status })
	end

	right = Theme.panel(rightGroup, "Style", UDim2.fromOffset(372, 572), UDim2.fromOffset(396, 126), Vector2.new(1, 0))
	right.BackgroundTransparency = 0.15
	right.Visible = false
	Theme.padding(right, 16)
	bigEmoji = Theme.label(right, {
		name = "Emoji",
		size = UDim2.fromOffset(120, 120),
		position = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		text = "",
		stroke = false,
	})
	nameLabel = Theme.label(right, {
		name = "ItemName",
		size = UDim2.new(1, 0, 0, 38),
		position = UDim2.fromOffset(0, 140),
		text = "",
	})
	kindLabel = Theme.label(right, {
		name = "Kind",
		size = UDim2.new(1, 0, 0, 15),
		position = UDim2.fromOffset(0, 182),
		text = "",
		font = Theme.Caps,
		color = C.Evolve,
		stroke = false,
	})
	descriptionLabel = Theme.label(right, {
		name = "Description",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 210),
		text = "",
		font = Theme.Body,
		color = C.Text,
		stroke = false,
		scaled = false,
		textSize = 20,
	})
	statusLabel = Theme.label(right, {
		name = "Status",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 262),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
		scaled = false,
		textSize = 16,
	})
	primaryButton = Theme.button(right, {
		name = "Primary",
		size = UDim2.new(1, 0, 0, 62),
		position = UDim2.new(0, 0, 1, -122),
		text = "",
	})
	primaryButton.Activated:Connect(onPrimary)
	hearButton = Theme.button(right, {
		name = "Hear",
		size = UDim2.new(1, 0, 0, 52),
		position = UDim2.new(0, 0, 1, -52),
		text = "🔊 HEAR IT",
		color = C.Blue,
		textColor = C.Text,
	})
	hearButton.Activated:Connect(function()
		local def = selected()
		if def then
			playHorn(def)
		end
	end)

	PlayerDataClient.Changed:Connect(function()
		if left.Visible then
			StylePanel.refresh()
		end
	end)
end

function StylePanel.setVisible(on: boolean)
	left.Visible = on
	right.Visible = on
	if on then
		showKind(kind)
	end
end

function StylePanel.isVisible(): boolean
	return left.Visible
end

return StylePanel
