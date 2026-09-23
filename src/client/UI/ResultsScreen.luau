--!strict
-- End-of-match screen: win/lose, your stats, Scrap earned line by line, and how close you are to the next car.
-- This is the "okay, one more match" moment, so the progress bar gets the spotlight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)

local ResultsScreen = {}

ResultsScreen.GarageRequested = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local scoreLine: TextLabel
local mvpLine: TextLabel
local statsLine: TextLabel
local rewardList: Frame
local totalLabel: TextLabel
local goalTitle: TextLabel
local goalFill: Frame
local goalNote: TextLabel
local board: Frame
local showToken = 0

local function clearChildren(frame: Instance, keepClass: string?)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not (keepClass and child:IsA(keepClass)) then
			child:Destroy()
		end
	end
end

local function build()
	gui = Theme.screen("TurboResults", 10)
	gui.Enabled = false

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = gui

	panel = Theme.panel(gui, "Results", UDim2.fromOffset(760, 540), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.gradient(panel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 230))
	Theme.padding(panel, 18)

	title = Theme.label(panel, { size = UDim2.new(1, 0, 0, 64), text = "VICTORY!" })
	scoreLine = Theme.label(panel, { size = UDim2.new(1, 0, 0, 30), position = UDim2.fromOffset(0, 64), text = "" })
	mvpLine = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 96),
		text = "",
		color = C.Gold,
		font = Theme.Body,
	})
	statsLine = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.fromOffset(0, 124),
		text = "",
		font = Theme.Body,
		color = C.Muted,
	})

	-- Left: Scrap earned.
	local left = Instance.new("Frame")
	left.Size = UDim2.new(0.5, -8, 0, 250)
	left.Position = UDim2.fromOffset(0, 156)
	left.BackgroundColor3 = C.PanelLight
	left.Parent = panel
	Theme.corner(left, 12)
	Theme.padding(left, 10)
	Theme.label(left, { size = UDim2.new(1, 0, 0, 28), text = "🔩 SCRAP EARNED", color = C.Scrap })
	rewardList = Instance.new("Frame")
	rewardList.Size = UDim2.new(1, 0, 1, -72)
	rewardList.Position = UDim2.fromOffset(0, 32)
	rewardList.BackgroundTransparency = 1
	rewardList.Parent = left
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = rewardList
	totalLabel = Theme.label(left, {
		size = UDim2.new(1, 0, 0, 34),
		position = UDim2.new(0, 0, 1, -34),
		text = "",
		color = C.Scrap,
	})

	-- Right: scoreboard.
	board = Instance.new("Frame")
	board.Size = UDim2.new(0.5, -8, 0, 250)
	board.Position = UDim2.new(0.5, 8, 0, 156)
	board.BackgroundColor3 = C.PanelLight
	board.Parent = panel
	Theme.corner(board, 12)
	Theme.padding(board, 8)
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 3)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = board

	-- Bottom: next car progress.
	goalTitle = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 414),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	local goalBack = Instance.new("Frame")
	goalBack.Size = UDim2.new(1, -160, 0, 22)
	goalBack.Position = UDim2.fromOffset(0, 446)
	goalBack.BackgroundColor3 = C.PanelDark
	goalBack.Parent = panel
	Theme.corner(goalBack, 11)
	goalFill = Instance.new("Frame")
	goalFill.Size = UDim2.fromScale(0, 1)
	goalFill.BackgroundColor3 = C.Good
	goalFill.Parent = goalBack
	Theme.corner(goalFill, 11)
	goalNote = Theme.label(panel, {
		size = UDim2.new(1, -160, 0, 22),
		position = UDim2.fromOffset(0, 472),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
	})
	local garage = Theme.button(panel, {
		size = UDim2.fromOffset(150, 46),
		position = UDim2.new(1, 0, 0, 438),
		anchor = Vector2.new(1, 0),
		text = "🚗 GARAGE",
	})
	garage.Activated:Connect(function()
		gui.Enabled = false
		ResultsScreen.GarageRequested:Fire()
	end)
	local close = Theme.button(panel, {
		size = UDim2.fromOffset(150, 36),
		position = UDim2.fromScale(1, 1),
		anchor = Vector2.new(1, 1),
		text = "Close",
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
	frame.Size = UDim2.new(1, 0, 0, 22)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Parent = parent
	local widths = { 0.46, 0.18, 0.12, 0.12, 0.12 }
	local x = 0
	for i, text in cells do
		Theme.label(frame, {
			size = UDim2.fromScale(widths[i], 1),
			position = UDim2.fromScale(x, 0),
			text = text,
			font = if bold then Theme.Title else Theme.Body,
			color = color,
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
	title.Text = if outcome == "Win" then "🏆 VICTORY! 🏆" elseif outcome == "Draw" then "DRAW!" else "GOOD GAME!"
	title.TextColor3 = if outcome == "Win" then C.Gold elseif outcome == "Draw" then C.Text else C.Muted
	scoreLine.Text = `BLUE {payload.blueScore or 0}  -  {payload.orangeScore or 0} ORANGE`
	mvpLine.Text = if payload.youAreMvp
		then "⭐ YOU ARE THE MVP! ⭐"
		elseif type(payload.mvp) == "string" and payload.mvp ~= "" then `MVP: {payload.mvp}`
		else ""
	local stats = if type(payload.stats) == "table" then payload.stats else {}
	statsLine.Text = string.format(
		"Goals %d   Assists %d   Saves %d   Shots %d   Touches %d   Style %d",
		stats.goals or 0,
		stats.assists or 0,
		stats.saves or 0,
		stats.shots or 0,
		stats.touches or 0,
		stats.styleTouches or 0
	)

	clearChildren(board)
	row(board, 0, { "PLAYER", "PTS", "G", "A", "S" }, C.Muted, true)
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

	-- Reward lines count up one by one.
	clearChildren(rewardList)
	totalLabel.Text = ""
	gui.Enabled = true
	panel.Position = UDim2.fromScale(0.5, 0.55)
	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.5) })
		:Play()

	local lines = if type(payload.lines) == "table" then payload.lines else {}
	local total = if type(payload.total) == "number" then payload.total else 0
	task.spawn(function()
		local running = 0
		for i, line in lines do
			task.wait(0.25)
			if token ~= showToken then
				return
			end
			running += line.amount
			local label = Theme.label(rewardList, {
				size = UDim2.new(1, 0, 0, 20),
				text = `{line.label}   +{line.amount}`,
				font = Theme.Body,
				align = Enum.TextXAlignment.Left,
				stroke = false,
			})
			label.LayoutOrder = i
			totalLabel.Text = `TOTAL  +{running}`
		end
		totalLabel.Text = `TOTAL  +{total}`
	end)

	local goal = payload.nextGoal
	if type(goal) == "table" then
		goalTitle.Text = `{goal.emoji} {string.upper(goal.displayName)}: {goal.have} / {goal.price}`
		local fraction = math.clamp(goal.have / math.max(goal.price, 1), 0, 1)
		goalFill.Size = UDim2.fromScale(0, 1)
		TweenService
			:Create(goalFill, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) })
			:Play()
		goalFill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
		goalNote.Text = if goal.canAfford
			then `You can unlock {goal.displayName} now! Open the Garage.`
			else `{goal.remaining} more Scrap to unlock! One more match?`
	else
		goalTitle.Text = "🏆 You've unlocked every car!"
		goalFill.Size = UDim2.fromScale(1, 1)
		goalNote.Text = "More cars are coming in future seasons."
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
