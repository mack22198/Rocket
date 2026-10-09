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
		Theme.setButtonColor(tab, if k == kind then C.Gold else C.CardShade)
	end
	for _, tile in tiles do
		local def = tile.def
		tile.button.Visible = def.Kind == kind
		local owned = data.style.owned[def.Id] == true
		local on = equippedOf(def.Kind) == def.Id
		local picked = def.Id == selectedId
		if on then
			tile.status.Text = "WEARING"
			tile.status.TextColor3 = if picked then C.Ink else C.GoodText
		elseif owned then
			tile.status.Text = "OWNED"
			tile.status.TextColor3 = C.InkMuted
		elseif def.Vip then
			tile.status.Text = "VIP"
			tile.status.TextColor3 = C.Shop
		elseif def.Season and def.Gold then
			tile.status.Text = "GOLD PASS"
			tile.status.TextColor3 = C.InkMuted
		elseif def.Season then
			local theme = Season.theme(def.Season)
			tile.status.Text = if theme then string.upper(theme.Name) else "SEASON"
			tile.status.TextColor3 = C.Evolve
		else
			tile.status.Text = `{Theme.formatNumber(def.Price)} SCRAP`
			tile.status.TextColor3 = if data.scrap >= def.Price then C.Ink else C.InkMuted
		end
		local stroke = tile.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if picked then 4 else 2
		end
		tile.button.BackgroundColor3 = if picked then C.Gold else C.CardShade
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
		then "HAT: SITS ON YOUR ROOF"
		elseif def.Kind == "horn" then "HORN: PRESS H (OR D-PAD UP) IN A MATCH"
		else "GOAL PARTY: WHEN YOU SCORE"
	descriptionLabel.Text = def.Description
	hearButton.Visible = def.Kind == "horn"
	if on then
		statusLabel.Text = "You're using this one."
		primaryButton.Text = "USING THIS ONE"
		Theme.setButtonColor(primaryButton, C.CardLine, C.InkMuted)
	elseif owned then
		statusLabel.Text = "You own this."
		primaryButton.Text = "USE THIS"
		Theme.setButtonColor(primaryButton, C.Good)
	elseif def.Vip then
		statusLabel.Text = "Comes with VIP. See the SHOP in the menu."
		primaryButton.Text = "VIP ONLY"
		Theme.setButtonColor(primaryButton, C.CardLine, C.InkMuted)
	elseif def.Season then
		local theme = Season.theme(def.Season)
		local name = if theme then theme.Name else "season"
		statusLabel.Text = if def.Gold
			then `A Gold Season Pass reward on the {name} track.`
			else `A reward on the {name} season track. Keep playing to earn it!`
		primaryButton.Text = if def.Gold then "GOLD PASS REWARD" else "SEASON REWARD"
		Theme.setButtonColor(primaryButton, C.CardLine, C.InkMuted)
	elseif data.scrap >= def.Price then
		statusLabel.Text = "Fixed price. No surprises."
		primaryButton.Text = `BUY: {Theme.formatNumber(def.Price)} SCRAP`
		Theme.setButtonColor(primaryButton, C.Gold)
	else
		statusLabel.Text = `You need {Theme.formatNumber(def.Price - data.scrap)} more Scrap.`
		primaryButton.Text = `{Theme.formatNumber(def.Price)} SCRAP`
		Theme.setButtonColor(primaryButton, C.CardLine, C.InkMuted)
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
	elseif def.Vip then
		toast("Comes with VIP - see the Shop!", false)
	elseif def.Season then
		toast(if def.Gold then "A Gold Season Pass reward!" else "Earn it on the season track!", false)
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
	left.Size = UDim2.new(1, 0, 1, -54)
	left.Position = UDim2.fromOffset(0, 54)
	left.BackgroundTransparency = 1
	left.Visible = false
	left.Parent = leftParent
	for i, k in Cosmetics.Kinds do
		local tab = Theme.button(left, {
			name = `Kind{i}`,
			size = UDim2.fromOffset(94, 34),
			position = UDim2.fromOffset((i - 1) * 100, 0),
			text = Theme.noEmoji(Cosmetics.KindNames[k]),
			color = C.CardShade,
			textSize = 15,
		})
		tab.Activated:Connect(function()
			showKind(k :: Cosmetics.Kind)
		end)
		kindTabs[k] = tab
	end
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Items"
	grid.Size = UDim2.new(1, 4, 1, -46)
	grid.Position = UDim2.fromOffset(0, 46)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = C.Ink
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
		button.BackgroundColor3 = C.CardShade
		button.Parent = grid
		Theme.corner(button, 12)
		Theme.stroke(button, C.Ink, 2)
		Theme.pop(button)
		Theme.label(button, {
			size = UDim2.new(1, 0, 0, 44),
			position = UDim2.fromOffset(0, 8),
			text = def.Emoji,
			textSize = 38,
		})
		Theme.label(button, {
			size = UDim2.new(1, -10, 0, 16),
			position = UDim2.fromOffset(5, 58),
			text = def.Name,
			textSize = 13,
		})
		local status = Theme.label(button, {
			size = UDim2.new(1, -10, 0, 13),
			position = UDim2.fromOffset(5, 79),
			text = "",
			font = Theme.Caps,
			textSize = 11,
		})
		button.Activated:Connect(function()
			choose(def.Id)
			if def.Kind == "horn" then
				playHorn(def)
			end
		end)
		table.insert(tiles, { def = def, button = button, status = status })
	end

	right = Theme.card(rightGroup, "Style", UDim2.fromOffset(372, 572), UDim2.fromOffset(396, 126), Vector2.new(1, 0))
	right.Visible = false
	Theme.padding(right, 16)
	local stage = Theme.well(right, "Picture", UDim2.new(1, 0, 0, 150), UDim2.new())
	bigEmoji = Theme.label(stage, {
		name = "Emoji",
		size = UDim2.fromOffset(120, 120),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		textSize = 100,
	})
	nameLabel = Theme.heading(right, {
		name = "ItemName",
		size = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromOffset(0, 164),
		text = "",
		textSize = 34,
	})
	kindLabel = Theme.label(right, {
		name = "Kind",
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 204),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
	})
	descriptionLabel = Theme.label(right, {
		name = "Description",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 230),
		text = "",
		font = Theme.Body,
		scaled = false,
		textSize = 17,
	})
	statusLabel = Theme.label(right, {
		name = "Status",
		size = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromOffset(0, 282),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		scaled = false,
		textSize = 14,
	})
	primaryButton = Theme.button(right, {
		name = "Primary",
		size = UDim2.new(1, 0, 0, 62),
		position = UDim2.new(0, 0, 1, -124),
		text = "",
		textSize = 26,
	})
	primaryButton.Activated:Connect(onPrimary)
	hearButton = Theme.button(right, {
		name = "Hear",
		size = UDim2.new(1, 0, 0, 54),
		position = UDim2.new(0, 0, 1, -54),
		text = "HEAR IT",
		color = C.Sky,
		textSize = 24,
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
