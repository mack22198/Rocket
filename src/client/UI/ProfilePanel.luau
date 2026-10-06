--!strict
-- Your profile (tap your card in the main menu): your level and how close the next one is, your win streak, your
-- lifetime stats, every achievement with how far along you are, and the titles you can wear under your name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Levels = require(Shared.Config.Levels)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local ProfilePanel = {}

ProfilePanel.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

type AchievementCell = {
	frame: Frame,
	stroke: UIStroke,
	icon: TextLabel,
	bar: Theme.Bar,
	count: TextLabel,
	reward: TextLabel,
}

type TitleCell = { button: TextButton, stroke: UIStroke, name: TextLabel, note: TextLabel }

local STATS: { { key: string, emoji: string, label: string } } = {
	{ key = "matches", emoji = "🎮", label = "MATCHES" },
	{ key = "wins", emoji = "🏆", label = "WINS" },
	{ key = "goals", emoji = "⚽", label = "GOALS" },
	{ key = "assists", emoji = "🤝", label = "ASSISTS" },
	{ key = "saves", emoji = "🧤", label = "SAVES" },
	{ key = "demos", emoji = "💥", label = "DEMOS" },
	{ key = "mvps", emoji = "⭐", label = "MVPS" },
	{ key = "bestStreak", emoji = "🔥", label = "BEST STREAK" },
}

local gui: ScreenGui
local panel: Frame
local levelBadge: TextLabel
local titleLine: TextLabel
local levelBar: Theme.Bar
local levelText: TextLabel
local streakLine: TextLabel
local statValues: { [string]: TextLabel } = {}
local tabs: { TextButton } = {}
local achievementGrid: ScrollingFrame
local titleGrid: ScrollingFrame
local achievementCells: { [string]: AchievementCell } = {}
local titleCells: { [string]: TitleCell } = {}
local countLabel: TextLabel
local message: TextLabel
local page = 1
local choosing = false

local function makeAchievementCell(def: Achievements.AchievementDef, order: number): AchievementCell
	local frame = Instance.new("Frame")
	frame.Name = def.Id
	frame.LayoutOrder = order
	frame.BackgroundColor3 = C.PanelDark
	frame.Parent = achievementGrid
	Theme.corner(frame, 12)
	local stroke = Theme.stroke(frame, C.Gold, 2)
	local icon = Theme.label(frame, {
		name = "Icon",
		size = UDim2.fromOffset(54, 54),
		position = UDim2.fromOffset(10, 12),
		text = def.Emoji,
		stroke = false,
	})
	icon.BackgroundColor3 = C.PanelLight
	icon.BackgroundTransparency = 0.3
	Theme.corner(icon, 27)
	Theme.label(frame, {
		name = "Name",
		size = UDim2.new(1, -150, 0, 22),
		position = UDim2.fromOffset(74, 8),
		text = def.Name,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(frame, {
		name = "Text",
		size = UDim2.new(1, -84, 0, 16),
		position = UDim2.fromOffset(74, 32),
		text = if def.Title then `{def.Text}  ·  🏷️ {def.Title}` else def.Text,
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	local bar = Theme.bar(frame, UDim2.new(1, -150, 0, 12), UDim2.fromOffset(74, 58), C.Gold)
	local count = Theme.label(frame, {
		name = "Count",
		size = UDim2.fromOffset(64, 16),
		position = UDim2.new(1, -72, 0, 56),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	local reward = Theme.label(frame, {
		name = "Reward",
		size = UDim2.fromOffset(70, 20),
		position = UDim2.new(1, -78, 0, 8),
		text = `🔩{def.Reward}`,
		color = C.Scrap,
		align = Enum.TextXAlignment.Right,
	})
	return { frame = frame, stroke = stroke, icon = icon, bar = bar, count = count, reward = reward }
end

local function chooseTitle(id: string)
	if choosing then
		return
	end
	choosing = true
	local ok, result = pcall(function()
		return Remotes.Profile:InvokeServer("title", id)
	end)
	choosing = false
	if ok and type(result) == "table" and result.ok ~= true and type(result.message) == "string" then
		message.Text = `🔒 {result.message}`
	end
end

local function makeTitleCell(id: string, text: string, order: number): TitleCell
	local button = Instance.new("TextButton")
	button.Name = if id == "" then "Auto" else id
	button.LayoutOrder = order
	button.BackgroundColor3 = C.PanelDark
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = titleGrid
	Theme.corner(button, 12)
	local stroke = Theme.stroke(button, C.Gold, 2)
	local name = Theme.label(button, {
		name = "Name",
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.fromOffset(8, 10),
		text = text,
	})
	local note = Theme.label(button, {
		name = "Note",
		size = UDim2.new(1, -16, 0, 16),
		position = UDim2.fromOffset(8, 42),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})
	button.Activated:Connect(function()
		chooseTitle(id)
	end)
	return { button = button, stroke = stroke, name = name, note = note }
end

local function refresh()
	local data = PlayerDataClient.get()
	local level, into, need = Levels.levelFor(data.xp)
	levelBadge.Text = tostring(level)
	local wearing = if data.title ~= "" then data.title else Achievements.levelTitle(level)
	titleLine.Text = Achievements.titleText(wearing)
	levelBar.set(into / need)
	levelText.Text = `LEVEL {level}  ·  {into} / {need} XP TO LEVEL {level + 1}`
	streakLine.Text = if data.winStreak >= 2
		then `🔥 {data.winStreak} WINS IN A ROW!`
		elseif data.winStreak == 1 then "🔥 1 WIN - WIN THE NEXT ONE FOR A STREAK!"
		else "🔥 WIN 2 IN A ROW FOR A STREAK BONUS"
	for key, label in statValues do
		local value = data.stats[key]
		label.Text = Theme.formatNumber(if type(value) == "number" then value else 0)
	end

	-- Achievements: done ones first, then the closest to done.
	local view = Achievements.viewOf(data.stats, data.owned, data.carStage, data.daily.streak, data.xp)
	local done = 0
	type Row = { def: Achievements.AchievementDef, isDone: boolean, fraction: number, index: number }
	local rows: { Row } = {}
	for index, def in Achievements.List do
		local progress, target = Achievements.progress(def, view)
		local isDone = data.achievements[def.Id] == true
		if isDone then
			done += 1
		end
		table.insert(rows, { def = def, isDone = isDone, fraction = progress / target, index = index })
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		if a.isDone ~= b.isDone then
			return not a.isDone -- the ones still to do come first...
		elseif a.fraction ~= b.fraction then
			return a.fraction > b.fraction -- ...closest first
		end
		return a.index < b.index
	end)
	for order, row in rows do
		local def = row.def
		local cell = achievementCells[def.Id]
		if not cell then
			cell = makeAchievementCell(def, order)
			achievementCells[def.Id] = cell
		end
		cell.frame.LayoutOrder = order
		local progress, target = Achievements.progress(def, view)
		if row.isDone then
			cell.bar.set(1)
			cell.count.Text = "✅ DONE"
			cell.count.TextColor3 = C.Good
			cell.stroke.Transparency = 0
			cell.icon.TextTransparency = 0
			cell.reward.TextTransparency = 0.5
		else
			cell.bar.set(progress / target)
			cell.count.Text = `{progress}/{target}`
			cell.count.TextColor3 = C.Muted
			cell.stroke.Transparency = 0.75
			cell.icon.TextTransparency = 0.4
			cell.reward.TextTransparency = 0
		end
	end
	countLabel.Text = `🏅 {done} / {#Achievements.List} ACHIEVEMENTS`

	-- Titles: "automatic" first, then every title (the ones you've got first).
	local entries: { { id: string, text: string, owned: boolean } } = {
		{
			id = "",
			text = `✨ Best level title`,
			owned = true,
		},
	}
	for _, title in Achievements.Titles do
		table.insert(entries, {
			id = title.Id,
			text = `{title.Emoji} {title.Text}`,
			owned = Achievements.ownsTitle(title.Id, level, data.achievements),
		})
	end
	for order, entry in entries do
		local cell = titleCells[if entry.id == "" then "_auto" else entry.id]
		if not cell then
			cell = makeTitleCell(entry.id, entry.text, order)
			titleCells[if entry.id == "" then "_auto" else entry.id] = cell
		end
		local worn = entry.id == data.title
		cell.button.LayoutOrder = if entry.owned then order else order + 1000
		cell.name.TextTransparency = if entry.owned then 0 else 0.5
		cell.stroke.Transparency = if worn then 0 elseif entry.owned then 0.6 else 0.9
		cell.stroke.Color = if worn then C.Good else C.Gold
		cell.note.Text = if worn
			then "✅ WEARING"
			elseif entry.owned then "TAP TO WEAR"
			else `🔒 {Achievements.howToUnlock(entry.id)}`
		cell.note.TextColor3 = if worn then C.Good elseif entry.owned then C.Gold else C.Muted
	end
end

local function showPage(index: number)
	page = index
	achievementGrid.Visible = index == 1
	titleGrid.Visible = index == 2
	for i, tab in tabs do
		Theme.setButtonColor(tab, if i == index then C.Gold else C.PanelLight, if i == index then nil else C.Text)
	end
	message.Text = ""
end

local function grid(name: string, cellSize: UDim2): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 1, -262)
	frame.Position = UDim2.fromOffset(0, 262)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 6
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cellSize
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

local function build()
	gui = Theme.screen("TurboProfile", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = gui

	panel = Theme.panel(gui, "Profile", UDim2.fromOffset(1000, 620), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)

	-- You.
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromOffset(84, 84)
	avatar.BackgroundColor3 = C.PanelLight
	avatar.Image = `rbxthumb://type=AvatarHeadShot&id={localPlayer.UserId}&w=150&h=150`
	avatar.Parent = panel
	Theme.corner(avatar, 42)
	Theme.stroke(avatar, C.Gold, 3)
	levelBadge = Theme.label(panel, {
		name = "Level",
		size = UDim2.fromOffset(38, 38),
		position = UDim2.fromOffset(56, 54),
		text = "1",
		color = C.Ink,
		stroke = false,
		zIndex = 3,
	})
	levelBadge.BackgroundColor3 = C.Gold
	levelBadge.BackgroundTransparency = 0
	Theme.corner(levelBadge, 19)
	Theme.stroke(levelBadge, C.Ink, 2)
	Theme.label(panel, {
		name = "PlayerName",
		size = UDim2.fromOffset(460, 40),
		position = UDim2.fromOffset(104, 0),
		text = localPlayer.DisplayName,
		align = Enum.TextXAlignment.Left,
	})
	titleLine = Theme.label(panel, {
		name = "Wearing",
		size = UDim2.fromOffset(460, 22),
		position = UDim2.fromOffset(105, 40),
		text = "",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	levelBar = Theme.bar(panel, UDim2.fromOffset(480, 14), UDim2.fromOffset(105, 70), C.Blue)
	levelText = Theme.label(panel, {
		name = "LevelText",
		size = UDim2.fromOffset(420, 16),
		position = UDim2.fromOffset(105, 88),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	streakLine = Theme.pill(panel, {
		name = "Streak",
		size = UDim2.fromOffset(330, 30),
		position = UDim2.new(1, -152, 0, 10),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Mega,
		transparency = 0.3,
	})
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
		ProfilePanel.close()
	end)

	-- Lifetime stats.
	local statsRow = Instance.new("Frame")
	statsRow.Name = "Stats"
	statsRow.Size = UDim2.new(1, 0, 0, 74)
	statsRow.Position = UDim2.fromOffset(0, 116)
	statsRow.BackgroundTransparency = 1
	statsRow.Parent = panel
	local statsLayout = Instance.new("UIGridLayout")
	statsLayout.CellSize = UDim2.new(1 / #STATS, -8, 1, 0)
	statsLayout.CellPadding = UDim2.fromOffset(8, 0)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsRow
	for order, stat in STATS do
		local chip = Instance.new("Frame")
		chip.Name = stat.key
		chip.LayoutOrder = order
		chip.BackgroundColor3 = C.PanelDark
		chip.BackgroundTransparency = 0.2
		chip.Parent = statsRow
		Theme.corner(chip, 10)
		statValues[stat.key] = Theme.label(chip, {
			name = "Value",
			size = UDim2.new(1, -8, 0, 34),
			position = UDim2.fromOffset(4, 6),
			text = "0",
		})
		Theme.label(chip, {
			name = "Label",
			size = UDim2.new(1, -8, 0, 16),
			position = UDim2.fromOffset(4, 48),
			text = `{stat.emoji} {stat.label}`,
			font = Theme.Caps,
			color = C.Muted,
			stroke = false,
		})
	end

	-- Achievements and titles.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.Size = UDim2.new(1, 0, 0, 44)
	tabBar.Position = UDim2.fromOffset(0, 206)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel
	for i, text in { "🏅 ACHIEVEMENTS", "🏷️ TITLES" } do
		local tab = Theme.button(tabBar, {
			name = `Tab{i}`,
			size = UDim2.fromOffset(220, 44),
			position = UDim2.fromOffset((i - 1) * 232, 0),
			text = text,
			color = C.PanelLight,
			textColor = C.Text,
		})
		tab.Activated:Connect(function()
			showPage(i)
		end)
		table.insert(tabs, tab)
	end
	countLabel = Theme.label(tabBar, {
		name = "Count",
		size = UDim2.fromOffset(300, 24),
		position = UDim2.fromScale(1, 0.5),
		anchor = Vector2.new(1, 0.5),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	message = Theme.label(tabBar, {
		name = "Message",
		size = UDim2.fromOffset(300, 20),
		position = UDim2.fromOffset(480, 12),
		text = "",
		font = Theme.Body,
		color = C.Bad,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	achievementGrid = grid("Achievements", UDim2.new(0.5, -5, 0, 84))
	titleGrid = grid("Titles", UDim2.new(0.25, -8, 0, 66))

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Opens the profile (on the achievements, or `startPage` 2 for the titles).
function ProfilePanel.open(startPage: number?)
	gui.Enabled = true
	refresh()
	showPage(startPage or page)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
	Theme.focus(tabs[page])
end

function ProfilePanel.close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		ProfilePanel.Closed:Fire()
	end
end

function ProfilePanel.isOpen(): boolean
	return gui.Enabled
end

function ProfilePanel.start()
	build()
	PlayerDataClient.Changed:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
end

return ProfilePanel
