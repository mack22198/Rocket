--!strict
-- End-of-match screen: win/lose, the scoreboard, Scrap earned line by line, and two progress bars: how close
-- your car is to its next evolution, and how close you are to unlocking the next car.
-- This is the "okay, one more match" moment, so the progress gets the spotlight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)

local ResultsScreen = {}

-- Fired with the car to show (or nil) when the player wants the garage.
ResultsScreen.GarageRequested = Signal.new() :: Signal.Signal<string?>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

type Progress = { title: TextLabel, bar: Theme.Bar, note: TextLabel }

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local blueScore: TextLabel
local orangeScore: TextLabel
local mvpLine: TextLabel
local statsLine: TextLabel
local rewardList: Frame
local totalLabel: TextLabel
local board: Frame
local carProgress: Progress
local unlockProgress: Progress
local garageButton: TextButton
local showToken = 0
local lastCarId: string? = nil

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function section(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = C.PanelDark
	frame.BackgroundTransparency = 0.35
	frame.Parent = parent
	Theme.corner(frame, 12)
	Theme.padding(frame, 10)
	return frame
end

local function progressCard(parent: Instance, name: string, position: UDim2, color: Color3): Progress
	local card = section(parent, name, UDim2.new(0.5, -6, 0, 86), position)
	local cardTitle = Theme.label(card, {
		size = UDim2.new(1, 0, 0, 24),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	local bar = Theme.bar(card, UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 32), color)
	local note = Theme.label(card, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 52),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	return { title = cardTitle, bar = bar, note = note }
end

local function build()
	gui = Theme.screen("TurboResults", 10)
	gui.Enabled = false

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = gui

	panel = Theme.panel(gui, "Results", UDim2.fromOffset(900, 610), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)

	title = Theme.label(panel, { size = UDim2.new(1, 0, 0, 62), text = "VICTORY!" })
	local scoreRow = Instance.new("Frame")
	scoreRow.Size = UDim2.fromOffset(300, 40)
	scoreRow.Position = UDim2.new(0.5, 0, 0, 64)
	scoreRow.AnchorPoint = Vector2.new(0.5, 0)
	scoreRow.BackgroundTransparency = 1
	scoreRow.Parent = panel
	local function scoreChip(team: string, color: Color3, x: number): TextLabel
		local chip = Theme.pill(scoreRow, {
			size = UDim2.fromOffset(120, 40),
			position = UDim2.fromOffset(x, 0),
			text = "",
			background = color,
			transparency = 0,
		})
		chip.Name = team
		return chip
	end
	blueScore = scoreChip("Blue", C.Blue, 0)
	orangeScore = scoreChip("Orange", C.Orange, 180)
	Theme.label(scoreRow, {
		size = UDim2.fromOffset(60, 40),
		position = UDim2.fromOffset(120, 0),
		text = "-",
	})
	mvpLine = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 110),
		text = "",
		color = C.Gold,
	})
	statsLine = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 138),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})

	-- Left: Scrap earned. Right: everyone's scores.
	local rewards = section(panel, "Rewards", UDim2.new(0.5, -6, 0, 250), UDim2.fromOffset(0, 166))
	Theme.label(rewards, {
		size = UDim2.new(1, 0, 0, 26),
		text = "🔩 SCRAP EARNED",
		color = C.Scrap,
		align = Enum.TextXAlignment.Left,
	})
	rewardList = Instance.new("Frame")
	rewardList.Size = UDim2.new(1, 0, 1, -70)
	rewardList.Position = UDim2.fromOffset(0, 32)
	rewardList.BackgroundTransparency = 1
	rewardList.Parent = rewards
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 3)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = rewardList
	totalLabel = Theme.label(rewards, {
		size = UDim2.new(1, 0, 0, 32),
		position = UDim2.new(0, 0, 1, -32),
		text = "",
		color = C.Scrap,
		align = Enum.TextXAlignment.Right,
	})

	board = section(panel, "Scoreboard", UDim2.new(0.5, -6, 0, 250), UDim2.new(0.5, 6, 0, 166))
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 4)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = board

	-- Bottom: your car's evolution progress and the next car to unlock.
	carProgress = progressCard(panel, "CarProgress", UDim2.fromOffset(0, 428), C.Evolve)
	unlockProgress = progressCard(panel, "UnlockProgress", UDim2.new(0.5, 6, 0, 428), C.Good)

	garageButton = Theme.button(panel, {
		size = UDim2.fromOffset(260, 52),
		position = UDim2.new(0.5, -8, 1, 0),
		anchor = Vector2.new(1, 1),
		text = "🚗 GARAGE",
	})
	garageButton.Activated:Connect(function()
		gui.Enabled = false
		ResultsScreen.GarageRequested:Fire(lastCarId)
	end)
	local close = Theme.button(panel, {
		size = UDim2.fromOffset(200, 52),
		position = UDim2.new(0.5, 8, 1, 0),
		anchor = Vector2.new(0, 1),
		text = "CLOSE",
		color = C.PanelLight,
		textColor = C.Text,
	})
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function row(parent: Instance, order: number, cells: { string }, color: Color3, bold: boolean)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 24)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = if bold and order > 0 then 0.75 else 1
	frame.LayoutOrder = order
	frame.Parent = parent
	Theme.corner(frame, 6)
	local widths = { 0.48, 0.16, 0.12, 0.12, 0.12 }
	local x = 0
	for i, text in cells do
		Theme.label(frame, {
			size = UDim2.new(widths[i], if i == 1 then -8 else 0, 1, -4),
			position = UDim2.new(x, if i == 1 then 8 else 0, 0, 2),
			text = text,
			font = if bold then Theme.Title else Theme.Body,
			color = if order == 0 then C.Muted else color:Lerp(C.Text, 0.35),
			align = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			stroke = false,
		})
		x += widths[i]
	end
end

local function show(payload: { [string]: any })
	showToken += 1
	local token = showToken
	local outcome = payload.outcome
	title.Text = if outcome == "Win"
		then "🏆 VICTORY! 🏆"
		elseif outcome == "Draw" then "IT'S A DRAW!"
		else "GOOD GAME!"
	title.TextColor3 = if outcome == "Win" then C.Gold elseif outcome == "Draw" then C.Text else C.Muted
	blueScore.Text = `BLUE {payload.blueScore or 0}`
	orangeScore.Text = `{payload.orangeScore or 0} ORANGE`
	mvpLine.Text = if payload.youAreMvp
		then "⭐ YOU ARE THE MVP! ⭐"
		elseif type(payload.mvp) == "string" and payload.mvp ~= "" then `MVP: {payload.mvp}`
		else ""
	local stats = if type(payload.stats) == "table" then payload.stats else {}
	statsLine.Text = string.format(
		"Goals %d   ·   Assists %d   ·   Saves %d   ·   Shots %d   ·   Touches %d   ·   Style %d",
		stats.goals or 0,
		stats.assists or 0,
		stats.saves or 0,
		stats.shots or 0,
		stats.touches or 0,
		stats.styleTouches or 0
	)

	clearChildren(board)
	row(board, 0, { "PLAYER", "POINTS", "G", "A", "S" }, C.Muted, false)
	if type(payload.scoreboard) == "table" then
		for i, entry in payload.scoreboard do
			local isMe = entry.name == localPlayer.DisplayName and not entry.isBot
			row(board, i, {
				(if isMe then "▶ " else "") .. tostring(entry.name),
				tostring(entry.points),
				tostring(entry.goals),
				tostring(entry.assists),
				tostring(entry.saves),
			}, Theme.teamColor(entry.team), isMe)
		end
	end

	clearChildren(rewardList)
	totalLabel.Text = ""
	gui.Enabled = true
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
			item.Size = UDim2.new(1, 0, 0, 20)
			item.BackgroundTransparency = 1
			item.LayoutOrder = i
			item.Parent = rewardList
			Theme.label(item, {
				size = UDim2.fromScale(0.75, 1),
				text = tostring(line.label),
				font = Theme.Body,
				align = Enum.TextXAlignment.Left,
				stroke = false,
			})
			Theme.label(item, {
				size = UDim2.fromScale(0.25, 1),
				position = UDim2.fromScale(0.75, 0),
				text = `+{line.amount}`,
				font = Theme.Body,
				color = if line.amount >= 0 then C.Scrap else C.Bad,
				align = Enum.TextXAlignment.Right,
				stroke = false,
			})
			totalLabel.Text = `TOTAL  +{running}`
		end
		totalLabel.Text = `TOTAL  +{total}`
	end)

	-- Your car's evolution.
	local car = payload.car
	lastCarId = if type(car) == "table" and type(car.id) == "string" then car.id else nil
	if type(car) == "table" and type(car.progress) == "table" then
		local progress = car.progress
		carProgress.title.Text = `{car.emoji or ""} {car.name}   +{car.xpGained or 0} XP`
		local fraction = if type(progress.fraction) == "number" then progress.fraction else 0
		carProgress.bar.set(0)
		TweenService:Create(carProgress.bar.fill, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		}):Play()
		carProgress.bar.fill.Visible = true
		if progress.ready then
			carProgress.note.Text = `✨ READY TO EVOLVE into the {progress.nextName}! Open the Garage.`
			carProgress.note.TextColor3 = C.Gold
		elseif progress.nextStage then
			carProgress.note.Text =
				`{Theme.formatNumber(math.max(0, progress.xpForNext - progress.xp))} XP until it evolves into the {progress.nextName}`
			carProgress.note.TextColor3 = C.Muted
		else
			carProgress.note.Text = "⭐ Fully evolved - what a car!"
			carProgress.note.TextColor3 = C.Gold
		end
	else
		carProgress.title.Text = "🚗 Your car"
		carProgress.bar.set(0)
		carProgress.note.Text = ""
	end

	-- The next car to unlock.
	local goal = payload.nextGoal
	if type(goal) == "table" then
		unlockProgress.title.Text = `{goal.emoji} {goal.displayName}   {goal.have} / {goal.price}`
		local fraction = math.clamp(goal.have / math.max(goal.price, 1), 0, 1)
		unlockProgress.bar.set(0)
		TweenService:Create(unlockProgress.bar.fill, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(fraction, 1),
		}):Play()
		unlockProgress.bar.fill.Visible = true
		unlockProgress.bar.fill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
		unlockProgress.note.Text = if goal.canAfford
			then `You can unlock the {goal.displayName} now!`
			else `{goal.remaining} more Scrap to unlock it. One more match?`
		unlockProgress.note.TextColor3 = if goal.canAfford then C.Gold else C.Muted
	else
		unlockProgress.title.Text = "🏆 Every car unlocked!"
		unlockProgress.bar.set(1)
		unlockProgress.note.Text = "More cars are coming in future seasons."
	end
end

function ResultsScreen.start()
	build()
	Remotes.MatchResults.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			show(payload)
		end
	end)
	-- Hide the results once the next match is about to start.
	local stateObject = MatchState.getObject()
	stateObject:GetAttributeChangedSignal(MatchState.Attr.Phase):Connect(function()
		if MatchState.phase(stateObject) == MatchState.Phases.Countdown then
			gui.Enabled = false
		end
	end)
end

return ResultsScreen
