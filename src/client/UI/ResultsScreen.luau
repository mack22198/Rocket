--!strict
-- End-of-match screen: first a big headline over the winners' podium (who won, who's MVP), then the card with
-- win/lose, your numbers, Scrap earned line by line, everyone's scores, and four progress bars: your player level,
-- how close your car is to its next evolution, how far along the season's reward track you are, and how close you
-- are to unlocking the next car. Levels reached and achievements finished pop up as cards (see Toasts).
-- This is the "okay, one more match" moment, so the progress gets the spotlight - and PLAY AGAIN is the big
-- button. GARAGE and MENU take you back to the main menu (the menus handle all three, see GameFlow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local ResultsScreen = {}

-- Fired with "again", "garage" or "menu" (and, for the garage, the car to show).
ResultsScreen.Chosen = Signal.new() :: Signal.Signal<string, string?>

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

type Progress = { title: TextLabel, bar: Theme.Bar, note: TextLabel }

local STATS = {
	{ key = "goals", label = "GOALS" },
	{ key = "assists", label = "ASSISTS" },
	{ key = "saves", label = "SAVES" },
	{ key = "shots", label = "SHOTS" },
	{ key = "touches", label = "TOUCHES" },
	{ key = "styleTouches", label = "STYLE" },
}

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local blueScore: TextLabel
local orangeScore: TextLabel
local mvpTag: TextLabel
local statValues: { [string]: TextLabel } = {}
local rewardList: Frame
local totalAmount: Theme.Amount
local board: Frame
local levelProgress: Progress
local carProgress: Progress
local seasonProgress: Progress
local unlockProgress: Progress
local againButton: TextButton
local menuButton: TextButton
local showToken = 0
local lastCarId: string? = nil
-- The headline over the podium.
local headlineGui: ScreenGui
local headlineTitle: TextLabel
local headlineShadow: TextLabel
local headlineMvp: TextLabel
local headlineScore: TextLabel

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local CARDS = 4

-- One of the progress cards along the bottom (`column` 0 to CARDS - 1).
local function progressCard(parent: Instance, name: string, column: number, color: Color3): Progress
	local card = Theme.well(
		parent,
		name,
		UDim2.new(1 / CARDS, -9, 0, 84),
		UDim2.new(column / CARDS, column * 12 / (CARDS - 1), 0, 410) -- 12px gaps, flush at both ends
	)
	local cardTitle = Theme.label(card, {
		size = UDim2.new(1, -24, 0, 18),
		position = UDim2.fromOffset(12, 12),
		text = "",
		textSize = 15,
		align = Enum.TextXAlignment.Left,
	})
	cardTitle.TextWrapped = false -- long car names shrink to one line
	local bar = Theme.bar(card, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 38), color, C.CardLine)
	local note = Theme.label(card, {
		size = UDim2.new(1, -24, 0, 14),
		position = UDim2.fromOffset(12, 60),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Left,
	})
	return { title = cardTitle, bar = bar, note = note }
end

local function build()
	gui = Theme.screen("TurboResults", 10)
	gui.Enabled = false

	Theme.scrim(gui, 0.5)

	panel = Theme.card(gui, "Results", UDim2.fromOffset(920, 624), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 20)

	-- The top: how it went, the score, the MVP and your numbers.
	title = Theme.heading(panel, {
		name = "Title",
		size = UDim2.fromOffset(440, 58),
		text = "VICTORY!",
		textSize = 58,
		align = Enum.TextXAlignment.Left,
		stroke = true,
	})
	title.TextWrapped = false
	local function scoreChip(team: string, color: Color3, x: number): TextLabel
		local chip = Theme.heading(panel, {
			name = team,
			size = UDim2.fromOffset(70, 54),
			position = UDim2.new(1, x, 0, 2),
			anchor = Vector2.new(1, 0),
			text = "0",
			color = C.Text,
			textSize = 40,
			stroke = true,
		})
		chip.BackgroundColor3 = color
		chip.BackgroundTransparency = 0
		Theme.corner(chip, 12)
		Theme.stroke(chip, C.Ink, 3)
		return chip
	end
	orangeScore = scoreChip("Orange", C.Orange, 0)
	Theme.heading(panel, {
		name = "Dash",
		size = UDim2.fromOffset(30, 54),
		position = UDim2.new(1, -74, 0, 2),
		anchor = Vector2.new(1, 0),
		text = "-",
		textSize = 40,
	})
	blueScore = scoreChip("Blue", C.Blue, -108)
	mvpTag = Theme.pill(panel, {
		name = "Mvp",
		size = UDim2.fromOffset(250, 30),
		position = UDim2.fromOffset(0, 70),
		text = "",
		background = C.Gold,
	})
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Size = UDim2.fromOffset(6 * 84 + 5 * 8, 58)
	stats.Position = UDim2.new(1, 0, 0, 66)
	stats.AnchorPoint = Vector2.new(1, 0)
	stats.BackgroundTransparency = 1
	stats.Parent = panel
	for i, stat in STATS do
		local box = Theme.well(stats, stat.key, UDim2.fromOffset(84, 58), UDim2.fromOffset((i - 1) * 92, 0))
		statValues[stat.key] = Theme.heading(box, {
			name = "Value",
			size = UDim2.new(1, 0, 0, 30),
			position = UDim2.fromOffset(0, 6),
			text = "0",
			textSize = 28,
		})
		Theme.label(box, {
			name = "Label",
			size = UDim2.new(1, -8, 0, 12),
			position = UDim2.fromOffset(4, 38),
			text = stat.label,
			font = Theme.Caps,
			color = C.InkMuted,
			textSize = 11,
		})
	end

	-- Middle left: Scrap earned. Middle right: everyone's scores.
	local rewards = Theme.well(panel, "Rewards", UDim2.new(0.5, -6, 0, 262), UDim2.fromOffset(0, 136))
	Theme.padding(rewards, 14)
	Theme.label(rewards, {
		size = UDim2.new(1, 0, 0, 18),
		text = "SCRAP EARNED",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})
	rewardList = Instance.new("Frame")
	rewardList.Size = UDim2.new(1, 0, 1, -72)
	rewardList.Position = UDim2.fromOffset(0, 26)
	rewardList.BackgroundTransparency = 1
	rewardList.Parent = rewards
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = rewardList
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.Position = UDim2.new(0, 0, 1, -42)
	divider.BackgroundColor3 = C.CardLine
	divider.BorderSizePixel = 0
	divider.Parent = rewards
	Theme.label(rewards, {
		size = UDim2.fromOffset(120, 32),
		position = UDim2.new(0, 0, 1, -32),
		text = "TOTAL",
		font = Theme.Display,
		textSize = 26,
		align = Enum.TextXAlignment.Left,
	})
	totalAmount = Theme.amount(rewards, 32, UDim2.new(1, 0, 1, -32), Vector2.new(1, 0))

	board = Theme.well(panel, "Scoreboard", UDim2.new(0.5, -6, 0, 262), UDim2.new(0.5, 6, 0, 136))
	Theme.padding(board, 12)
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 4)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = board

	-- Bottom: your level, your car's evolution, the season track and the next car to unlock.
	levelProgress = progressCard(panel, "LevelProgress", 0, C.Sky)
	carProgress = progressCard(panel, "CarProgress", 1, C.Evolve)
	seasonProgress = progressCard(panel, "SeasonProgress", 2, C.Gold)
	unlockProgress = progressCard(panel, "UnlockProgress", 3, C.Good)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.Size = UDim2.new(1, 0, 0, 68)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.BackgroundTransparency = 1
	buttons.Parent = panel
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom
	row.Padding = UDim.new(0, 12)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = buttons
	local function choice(order: number, name: string, width: number, height: number, text: string, color: Color3)
		local button = Theme.button(buttons, {
			name = name,
			size = UDim2.fromOffset(width, height),
			text = text,
			color = color,
		})
		button.LayoutOrder = order
		return button
	end
	againButton = choice(1, "PlayAgain", 340, 68, "PLAY AGAIN", C.Gold)
	Theme.sweep(againButton, 3)
	againButton.Activated:Connect(function()
		ResultsScreen.hide()
		ResultsScreen.Chosen:Fire("again", nil)
	end)
	local garage = choice(2, "Garage", 210, 58, "GARAGE", C.Card)
	garage.Activated:Connect(function()
		ResultsScreen.hide()
		ResultsScreen.Chosen:Fire("garage", lastCarId)
	end)
	menuButton = choice(3, "Menu", 210, 58, "MENU", C.Panel)
	menuButton.Activated:Connect(function()
		ResultsScreen.hide()
		ResultsScreen.Chosen:Fire("menu", nil)
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- One line of the scoreboard: name, points, goals, assists, saves.
local function row(parent: Instance, order: number, cells: { string }, team: string?, isMe: boolean)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 26)
	frame.BackgroundColor3 = if isMe then C.Gold else C.Card
	frame.BackgroundTransparency = if order == 0 then 1 else 0
	frame.LayoutOrder = order
	frame.Parent = parent
	Theme.corner(frame, 6)
	if team then
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 6, 1, 0)
		bar.BackgroundColor3 = Theme.teamColor(team)
		bar.BorderSizePixel = 0
		bar.Parent = frame
		Theme.corner(bar, 3)
	end
	local widths = { 0.48, 0.16, 0.12, 0.12, 0.12 }
	local x = 0
	for i, text in cells do
		Theme.label(frame, {
			size = UDim2.new(widths[i], if i == 1 then -14 else 0, 1, -6),
			position = UDim2.new(x, if i == 1 then 14 else 0, 0, 3),
			text = text,
			font = if order == 0 then Theme.Caps elseif isMe or i == 2 then Theme.Title else Theme.Body,
			color = if order == 0 then C.InkMuted else C.Ink,
			textSize = if order == 0 then 12 else 15,
			align = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		})
		x += widths[i]
	end
end

local function outcomeTitle(outcome: unknown): (string, Color3)
	if outcome == "Win" then
		return "VICTORY!", C.Gold
	elseif outcome == "Draw" then
		return "IT'S A DRAW!", C.Text
	end
	return "GOOD GAME!", C.Text
end

local function buildHeadline()
	headlineGui = Theme.screen("TurboPodium", 9)
	headlineGui.Enabled = false
	local holder = Instance.new("Frame")
	holder.Name = "Headline"
	holder.Size = UDim2.fromOffset(1000, 200)
	holder.Position = UDim2.new(0.5, 0, 0, 16)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Parent = headlineGui
	Theme.scaled(holder)
	local function big(name: string, color: Color3, y: number): TextLabel
		local label = Theme.heading(holder, {
			name = name,
			size = UDim2.fromOffset(1000, 96),
			position = UDim2.new(0.5, 0, 0, y),
			anchor = Vector2.new(0.5, 0),
			text = "",
			color = color,
		})
		Theme.outline(label, 5)
		return label
	end
	headlineShadow = big("Shadow", C.Ink, 8) -- a hard shadow, like a sticker
	headlineTitle = big("Title", C.Gold, 0)
	headlineMvp = Theme.heading(holder, {
		name = "Mvp",
		size = UDim2.fromOffset(800, 42),
		position = UDim2.new(0.5, 0, 0, 106),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Text,
		textSize = 38,
		stroke = true,
	})
	headlineScore = Theme.pill(holder, {
		name = "Score",
		size = UDim2.fromOffset(300, 36),
		position = UDim2.new(0.5, 0, 0, 158),
		anchor = Vector2.new(0.5, 0),
		text = "",
	})
	headlineGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function mvpText(payload: { [string]: any }): string
	if payload.youAreMvp then
		return "YOU ARE THE MVP!"
	elseif type(payload.mvp) == "string" and payload.mvp ~= "" then
		return `MVP: {payload.mvp}`
	end
	return ""
end

-- The big headline shown over the podium, before the results panel.
function ResultsScreen.showHeadline(payload: { [string]: any })
	local text, color = outcomeTitle(payload.outcome)
	headlineTitle.Text = text
	headlineTitle.TextColor3 = color
	headlineShadow.Text = text
	headlineMvp.Text = mvpText(payload)
	headlineScore.Text = `BLUE {payload.blueScore or 0} - {payload.orangeScore or 0} ORANGE`
	headlineGui.Enabled = true
	for _, label in { headlineTitle, headlineShadow } do
		label.Size = UDim2.fromOffset(500, 48)
		TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(1000, 96),
		}):Play()
	end
end

-- Fills a progress card's bar from empty, so it looks like it's just been earned.
local function fillTo(progress: Progress, fraction: number)
	progress.bar.set(0)
	progress.bar.fill.Visible = true
	TweenService:Create(progress.bar.fill, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
	}):Play()
end

function ResultsScreen.show(payload: { [string]: any })
	headlineGui.Enabled = false
	showToken += 1
	local token = showToken
	local outcome = payload.outcome
	local text, color = outcomeTitle(outcome)
	title.Text = text
	title.TextColor3 = if outcome == "Win" then color else C.Text
	blueScore.Text = tostring(payload.blueScore or 0)
	orangeScore.Text = tostring(payload.orangeScore or 0)
	mvpTag.Text = mvpText(payload)
	mvpTag.Visible = mvpTag.Text ~= ""
	local stats = if type(payload.stats) == "table" then payload.stats else {}
	for _, stat in STATS do
		statValues[stat.key].Text = tostring(stats[stat.key] or 0)
	end

	clearChildren(board)
	row(board, 0, { "PLAYER", "POINTS", "G", "A", "S" }, nil, false)
	if type(payload.scoreboard) == "table" then
		for i, entry in payload.scoreboard do
			local isMe = entry.name == localPlayer.DisplayName and not entry.isBot
			row(board, i, {
				tostring(entry.name),
				tostring(entry.points),
				tostring(entry.goals),
				tostring(entry.assists),
				tostring(entry.saves),
			}, entry.team, isMe)
		end
	end

	clearChildren(rewardList)
	totalAmount.set(0, "+")
	gui.Enabled = true
	Theme.focus(againButton)
	panel.Position = UDim2.fromScale(0.5, 0.57)
	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()

	-- Reward lines count up one by one.
	local lines = if type(payload.lines) == "table" then payload.lines else {}
	local total = if type(payload.total) == "number" then payload.total else 0
	task.spawn(function()
		local running = 0
		for i, line in lines do
			task.wait(0.22)
			if token ~= showToken then
				return
			end
			running += line.amount
			local item = Instance.new("Frame")
			item.Size = UDim2.new(1, 0, 0, 22)
			item.BackgroundTransparency = 1
			item.LayoutOrder = i
			item.Parent = rewardList
			Theme.label(item, {
				size = UDim2.fromScale(0.75, 1),
				text = Theme.noEmoji(tostring(line.label)),
				font = Theme.Body,
				textSize = 15,
				align = Enum.TextXAlignment.Left,
			})
			Theme.label(item, {
				size = UDim2.fromScale(0.25, 1),
				position = UDim2.fromScale(0.75, 0),
				text = if line.amount >= 0 then `+{line.amount}` else tostring(line.amount),
				font = Theme.Title,
				color = if line.amount >= 0 then C.Ink else C.Bad,
				textSize = 15,
				align = Enum.TextXAlignment.Right,
			})
			totalAmount.set(running, "+")
		end
		totalAmount.set(total, "+")
	end)

	-- Your player level (and a card for each level reached and achievement finished).
	local levels = payload.progress
	if type(levels) == "table" and type(levels.level) == "number" then
		levelProgress.title.Text = `LEVEL {levels.level}  +{levels.gained or 0} XP`
		local need = if type(levels.need) == "number" and levels.need > 0 then levels.need else 1
		local into = if type(levels.into) == "number" then levels.into else 0
		fillTo(levelProgress, into / need)
		local ups = if type(levels.levelUps) == "table" then levels.levelUps else {}
		if #ups > 0 then
			levelProgress.note.Text = `Level up! +{ups[#ups].scrap or 0} Scrap`
			levelProgress.note.TextColor3 = C.Good
		else
			levelProgress.note.Text = `{need - into} XP to level {levels.level + 1}`
			levelProgress.note.TextColor3 = C.InkMuted
		end
		local achievements = if type(levels.achievements) == "table" then levels.achievements else {}
		task.delay(1.2, function()
			if token ~= showToken then
				return
			end
			for _, up in ups do
				Toasts.levelUp(up)
			end
			for _, info in achievements do
				Toasts.achievement(info)
			end
		end)
	else
		levelProgress.title.Text = "LEVEL"
		levelProgress.bar.set(0)
		levelProgress.note.Text = ""
	end

	-- Your car's evolution.
	local car = payload.car
	lastCarId = if type(car) == "table" and type(car.id) == "string" then car.id else nil
	if type(car) == "table" and type(car.progress) == "table" then
		local progress = car.progress
		carProgress.title.Text = `{string.upper(tostring(car.name))}  +{car.xpGained or 0} XP`
		fillTo(carProgress, if type(progress.fraction) == "number" then progress.fraction else 0)
		if progress.ready then
			carProgress.note.Text = "Ready to evolve! Open the Garage."
			carProgress.note.TextColor3 = C.Evolve
		elseif progress.nextStage then
			carProgress.note.Text =
				`{Theme.formatNumber(math.max(0, progress.xpForNext - progress.xp))} XP until it evolves`
			carProgress.note.TextColor3 = C.InkMuted
		else
			carProgress.note.Text = "Fully evolved!"
			carProgress.note.TextColor3 = C.Evolve
		end
	else
		carProgress.title.Text = "YOUR CAR"
		carProgress.bar.set(0)
		carProgress.note.Text = ""
	end

	-- The season track (any tiers reached this match have already paid out).
	local season = payload.season
	if type(season) == "table" and type(season.tier) == "number" then
		seasonProgress.title.Text = `SEASON TIER {season.tier}  +{season.gained or 0} XP`
		local need = if type(season.need) == "number" and season.need > 0 then season.need else 1
		local into = if type(season.xp) == "number" then season.xp else 0
		fillTo(seasonProgress, into / need)
		local reached = if type(season.rewards) == "table" then season.rewards else {}
		if #reached > 0 then
			local latest = Theme.noEmoji(tostring(reached[#reached]))
			seasonProgress.note.Text = if #reached > 1 then `{latest} (and {#reached - 1} more!)` else latest
			seasonProgress.note.TextColor3 = C.Good
		else
			seasonProgress.note.Text = `Next: {Theme.noEmoji(tostring(season.nextReward or "?"))} ({need - into} XP)`
			seasonProgress.note.TextColor3 = C.InkMuted
		end
	else
		seasonProgress.title.Text = "SEASON"
		seasonProgress.bar.set(0)
		seasonProgress.note.Text = ""
	end

	-- The next car to unlock.
	local goal = payload.nextGoal
	if type(goal) == "table" then
		unlockProgress.title.Text = `{string.upper(tostring(goal.displayName))}  {goal.have}/{goal.price}`
		fillTo(unlockProgress, goal.have / math.max(goal.price, 1))
		unlockProgress.bar.fill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
		unlockProgress.note.Text = if goal.canAfford
			then "You can unlock it now!"
			else `{goal.remaining} more Scrap. One more match?`
		unlockProgress.note.TextColor3 = if goal.canAfford then C.Good else C.InkMuted
	else
		unlockProgress.title.Text = "EVERY CAR UNLOCKED!"
		unlockProgress.bar.set(1)
		unlockProgress.note.Text = "More cars are coming in future seasons."
	end
end

function ResultsScreen.hide()
	headlineGui.Enabled = false
	showToken += 1
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
	end
end

function ResultsScreen.isOpen(): boolean
	return gui.Enabled
end

-- (GameFlow shows the headline and then the panel when the match results arrive.)
function ResultsScreen.start()
	build()
	buildHeadline()
	-- The MENU button counts down to when the server sends everyone back to the menu anyway.
	local stateObject = MatchState.getObject()
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		if MatchState.phase(stateObject) == MatchState.Phases.Results then
			local left = math.ceil(MatchState.phaseSecondsLeft(stateObject, workspace:GetServerTimeNow()))
			menuButton.Text = `MENU ({left})`
		else
			menuButton.Text = "MENU"
		end
	end)
end

return ResultsScreen
