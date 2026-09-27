--!strict
-- The collection book: every car at every evolution stage. The ones you've got are shown in full colour with
-- their names; the rest are black mystery silhouettes ("???") with a hint on how to get them - the "I have to
-- collect them all" feeling. Pages are tabs across the top, so more kinds of collectibles can slot in later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local Cosmetics = require(Shared.Config.Cosmetics)
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local CollectionBook = {}

CollectionBook.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

-- One thing to collect.
export type Entry = {
	key: string,
	name: string,
	owned: boolean,
	hint: string, -- how to get it (shown while it's still a mystery)
	color: Color3, -- the frame colour (rarity)
	model: (() -> Model)?, -- a 3D look, or...
	emoji: string?, -- ...a big emoji
}

export type Page = { title: string, entries: () -> { Entry } }

type Cell = {
	frame: Frame,
	viewport: ViewportFrame?,
	emoji: TextLabel?,
	name: TextLabel,
	hint: TextLabel,
	stroke: UIStroke,
	key: string,
}

local gui: ScreenGui
local panel: Frame
local countLabel: TextLabel
local countBar: Theme.Bar
local tabBar: Frame
local grid: ScrollingFrame
local pages: { Page } = {}
local tabs: { TextButton } = {}
local cells: { [string]: Cell } = {}
local currentPage = 1

-- The cars page: each car at each evolution stage.
local function carEntries(): { Entry }
	local data = PlayerDataClient.get()
	local list: { Entry } = {}
	for _, def in CarCatalog.ordered() do
		local owned = data.owned[def.Id] == true
		local reached = if owned then data.carStage[def.Id] or 1 else 0
		for stage = 1, GameConfig.Evolution.Stages do
			local have = stage <= reached
			table.insert(list, {
				key = `car:{def.Id}:{stage}`,
				name = CarCatalog.stageName(def, stage),
				owned = have,
				hint = if not owned and def.Fusion
					then "🧬 Fuse in the Garage"
					elseif not owned then `🔒 Unlock for 🔩{Theme.formatNumber(def.Price)}`
					else "✨ Evolve to reveal",
				color = CarCatalog.Rarities[def.Rarity].Color,
				model = function(): Model
					return CarModelBuilder.build(def, { preview = true, stage = stage })
				end,
			})
		end
	end
	return list
end

-- A page for one kind of style item (hats, horns or goal parties).
local function styleEntries(kind: Cosmetics.Kind): () -> { Entry }
	return function(): { Entry }
		local owned = PlayerDataClient.get().style.owned
		local list: { Entry } = {}
		for _, item in Cosmetics.ofKind(kind) do
			if item.Id == "none" then
				continue
			end
			table.insert(list, {
				key = `style:{item.Id}`,
				name = item.Name,
				owned = owned[item.Id] == true,
				hint = if item.Season
					then `🏆 Season {item.Season} reward`
					else `🔩 {Theme.formatNumber(item.Price)} in the Garage`,
				color = if item.Season then C.Evolve else C.Gold,
				emoji = item.Emoji,
			})
		end
		return list
	end
end

-- Adds a page of collectibles (a tab across the top of the book).
function CollectionBook.addPage(page: Page)
	table.insert(pages, page)
end

-- How many of everything you've collected, across every page.
function CollectionBook.count(): (number, number)
	local have, total = 0, 0
	for _, page in pages do
		for _, entry in page.entries() do
			total += 1
			if entry.owned then
				have += 1
			end
		end
	end
	return have, total
end

-- How far a model reaches from its centre (works on anything, unlike GetExtentsSize).
local function reachOf(model: Model): number
	local reach = 1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			reach = math.max(reach, d.CFrame.Position.Magnitude + d.Size.Magnitude / 2)
		end
	end
	return reach
end

local function makeCell(entry: Entry, order: number): Cell
	local frame = Instance.new("Frame")
	frame.Name = entry.key
	frame.LayoutOrder = order
	frame.BackgroundColor3 = C.PanelDark
	frame.Parent = grid
	Theme.corner(frame, 12)
	local stroke = Theme.stroke(frame, entry.color, 2)
	local viewport: ViewportFrame? = nil
	local emoji: TextLabel? = nil
	if entry.model then
		local view = Instance.new("ViewportFrame")
		view.Size = UDim2.new(1, -12, 0, 78)
		view.Position = UDim2.fromOffset(6, 6)
		view.BackgroundColor3 = rgb(40, 48, 84)
		view.Ambient = rgb(170, 172, 196)
		view.LightColor = rgb(255, 255, 255)
		view.LightDirection = Vector3.new(-1, -2, -1)
		view.Parent = frame
		Theme.corner(view, 9)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 34
		camera.Parent = view
		view.CurrentCamera = camera
		local model = entry.model()
		model.Parent = view
		local back = 3 + reachOf(model) * 1.9
		camera.CFrame = CFrame.lookAt(Vector3.new(back * 0.62, back * 0.34, back * 0.8), Vector3.new(0, 0.2, 0))
		viewport = view
	else
		emoji = Theme.label(frame, {
			size = UDim2.new(1, -12, 0, 72),
			position = UDim2.fromOffset(6, 8),
			text = entry.emoji or "⭐",
			stroke = false,
		})
	end
	local name = Theme.label(frame, {
		name = "Name",
		size = UDim2.new(1, -10, 0, 18),
		position = UDim2.fromOffset(5, 88),
		text = "",
		font = Theme.Body,
		stroke = false,
	})
	local hint = Theme.label(frame, {
		name = "Hint",
		size = UDim2.new(1, -10, 0, 13),
		position = UDim2.fromOffset(5, 106),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})
	return {
		frame = frame,
		viewport = viewport,
		emoji = emoji,
		name = name,
		hint = hint,
		stroke = stroke,
		key = entry.key,
	}
end

local function showCell(cell: Cell, entry: Entry)
	cell.frame.Visible = true
	if cell.viewport then
		-- A black silhouette until you've got it.
		cell.viewport.ImageColor3 = if entry.owned then rgb(255, 255, 255) else rgb(0, 0, 0)
		cell.viewport.ImageTransparency = if entry.owned then 0 else 0.15
	end
	if cell.emoji then
		cell.emoji.TextTransparency = if entry.owned then 0 else 0.85
	end
	cell.name.Text = if entry.owned then entry.name else "???"
	cell.name.TextColor3 = if entry.owned then C.Text else C.Muted
	cell.hint.Text = if entry.owned then "✅ COLLECTED" else entry.hint
	cell.hint.TextColor3 = if entry.owned then C.Good else C.Muted
	cell.stroke.Transparency = if entry.owned then 0 else 0.6
end

local function showPage(index: number)
	currentPage = index
	for i, tab in tabs do
		Theme.setButtonColor(tab, if i == index then C.Gold else C.PanelLight, if i == index then nil else C.Text)
	end
	for _, cell in cells do
		cell.frame.Visible = false
	end
	local page = pages[index]
	if not page then
		return
	end
	for order, entry in page.entries() do
		local cell = cells[entry.key]
		if not cell then
			cell = makeCell(entry, order)
			cells[entry.key] = cell
		end
		cell.frame.LayoutOrder = order
		showCell(cell, entry)
	end
	local have, total = CollectionBook.count()
	countLabel.Text = `{have} / {total} COLLECTED`
	countBar.set(have / math.max(total, 1))
end

local function rebuildTabs()
	for _, tab in tabs do
		tab:Destroy()
	end
	table.clear(tabs)
	for i, page in pages do
		local tab = Theme.button(tabBar, {
			name = `Tab{i}`,
			size = UDim2.fromOffset(170, 40),
			position = UDim2.fromOffset((i - 1) * 180, 0),
			text = page.title,
			color = C.PanelLight,
			textColor = C.Text,
		})
		tab.Activated:Connect(function()
			showPage(i)
		end)
		table.insert(tabs, tab)
	end
end

local function build()
	gui = Theme.screen("TurboCollection", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = gui

	panel = Theme.panel(gui, "Book", UDim2.fromOffset(1000, 620), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)
	Theme.label(panel, {
		name = "Title",
		size = UDim2.fromOffset(400, 46),
		text = "📖 COLLECTION",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	countLabel = Theme.label(panel, {
		name = "Count",
		size = UDim2.fromOffset(260, 20),
		position = UDim2.fromOffset(420, 6),
		text = "",
		font = Theme.Caps,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	countBar = Theme.bar(panel, UDim2.fromOffset(260, 12), UDim2.fromOffset(420, 30), C.Evolve)
	local close = Theme.button(panel, {
		name = "Close",
		size = UDim2.fromOffset(140, 48),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "◀ BACK",
		color = C.PanelLight,
		textColor = C.Text,
	})
	close.Activated:Connect(function()
		CollectionBook.close()
	end)

	tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.Position = UDim2.fromOffset(0, 58)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, -110)
	grid.Position = UDim2.fromOffset(0, 110)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(230, 124)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function CollectionBook.open()
	rebuildTabs()
	gui.Enabled = true
	showPage(currentPage)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
	Theme.focus(tabs[currentPage])
end

function CollectionBook.close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		CollectionBook.Closed:Fire()
	end
end

function CollectionBook.isOpen(): boolean
	return gui.Enabled
end

function CollectionBook.start()
	build()
	CollectionBook.addPage({ title = "🚗 CARS", entries = carEntries })
	for _, kind in Cosmetics.Kinds do
		CollectionBook.addPage({ title = Cosmetics.KindNames[kind], entries = styleEntries(kind :: Cosmetics.Kind) })
	end
	PlayerDataClient.Changed:Connect(function()
		if gui.Enabled then
			showPage(currentPage)
		end
	end)
end

return CollectionBook
