--!strict
-- The in-game HUD: scoreboard + clock, countdown and GOAL text, boost gauge, Mega Shot meter,
-- and the lobby panel (Scrap, next unlock, Garage button, next-match timer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Rewards = require(Shared.Config.Rewards)
local Signal = require(Shared.Util.Signal)

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local HUD = {}

HUD.GarageRequested = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local Phases = MatchState.Phases
local Attr = MatchState.Attr
local CarAttr = MatchState.CarAttr

local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()

local gui: ScreenGui
local scoreboard: Frame
local blueScore: TextLabel
local orangeScore: TextLabel
local clockLabel: TextLabel
local clockNote: TextLabel
local bigText: TextLabel
local subText: TextLabel
local boostPanel: Frame
local boostFill: Frame
local boostNumber: TextLabel
local megaPanel: Frame
local megaFill: Frame
local megaLabel: TextLabel
local lobbyPanel: Frame
local scrapLabel: TextLabel
local goalLabel: TextLabel
local goalFill: Frame
local bannerLabel: TextLabel
local teamBadge: TextLabel
local camLabel: TextLabel

local messageUntil = 0
local lastPhase = ""

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Big centre text, e.g. "3", "GO!", "GOAL!".
function HUD.flash(text: string, color: Color3, sub: string?, duration: number?)
	bigText.Text = text
	bigText.TextColor3 = color
	bigText.Visible = true
	subText.Text = sub or ""
	subText.Visible = sub ~= nil and sub ~= ""
	messageUntil = os.clock() + (duration or 1.5)
	bigText.Size = UDim2.fromOffset(700, 60)
	TweenService:Create(bigText, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(700, 130),
	}):Play()
end

local function build()
	gui = Theme.screen("TurboHUD", 5)

	-- Scoreboard.
	scoreboard = Instance.new("Frame")
	scoreboard.Name = "Scoreboard"
	scoreboard.Size = UDim2.fromOffset(360, 62)
	scoreboard.Position = UDim2.new(0.5, 0, 0, 10)
	scoreboard.AnchorPoint = Vector2.new(0.5, 0)
	scoreboard.BackgroundTransparency = 1
	scoreboard.Parent = gui

	local function scoreBox(name: string, color: Color3, x: number): TextLabel
		local box = Instance.new("Frame")
		box.Name = name
		box.Size = UDim2.fromOffset(92, 62)
		box.Position = UDim2.fromOffset(x, 0)
		box.BackgroundColor3 = color
		box.Parent = scoreboard
		Theme.corner(box, 14)
		Theme.stroke(box, Color3.new(0, 0, 0), 2)
		return Theme.label(box, { size = UDim2.fromScale(1, 0.9), position = UDim2.fromScale(0, 0.05), text = "0" })
	end
	blueScore = scoreBox("Blue", C.Blue, 0)
	orangeScore = scoreBox("Orange", C.Orange, 268)

	local clockBox = Instance.new("Frame")
	clockBox.Name = "Clock"
	clockBox.Size = UDim2.fromOffset(164, 62)
	clockBox.Position = UDim2.fromOffset(98, 0)
	clockBox.BackgroundColor3 = C.Panel
	clockBox.Parent = scoreboard
	Theme.corner(clockBox, 14)
	Theme.stroke(clockBox, Color3.new(0, 0, 0), 2)
	clockLabel =
		Theme.label(clockBox, { size = UDim2.fromScale(1, 0.9), position = UDim2.fromScale(0, 0.05), text = "5:00" })
	clockNote = Theme.label(scoreboard, {
		size = UDim2.fromOffset(360, 22),
		position = UDim2.fromOffset(0, 66),
		text = "",
		color = C.Gold,
	})

	teamBadge = Theme.label(gui, {
		name = "TeamBadge",
		size = UDim2.fromOffset(220, 30),
		position = UDim2.fromOffset(16, 14),
		text = "",
		align = Enum.TextXAlignment.Left,
	})

	-- Centre messages.
	bigText = Theme.label(gui, {
		name = "BigText",
		size = UDim2.fromOffset(700, 130),
		position = UDim2.fromScale(0.5, 0.3),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 5,
	})
	bigText.Visible = false
	local bigStroke = Instance.new("UIStroke")
	bigStroke.Thickness = 4
	bigStroke.Color = Color3.new(0, 0, 0)
	bigStroke.Parent = bigText
	subText = Theme.label(gui, {
		name = "SubText",
		size = UDim2.fromOffset(700, 44),
		position = UDim2.new(0.5, 0, 0.3, 80),
		anchor = Vector2.new(0.5, 0),
		text = "",
		zIndex = 5,
	})
	subText.Visible = false

	-- Boost gauge.
	boostPanel = Theme.panel(gui, "Boost", UDim2.fromOffset(130, 130), UDim2.new(1, -20, 1, -20), Vector2.new(1, 1))
	local fillBack = Instance.new("Frame")
	fillBack.Size = UDim2.new(1, -20, 1, -20)
	fillBack.Position = UDim2.fromOffset(10, 10)
	fillBack.BackgroundColor3 = C.PanelDark
	fillBack.ClipsDescendants = true
	fillBack.Parent = boostPanel
	Theme.corner(fillBack, 10)
	boostFill = Instance.new("Frame")
	boostFill.AnchorPoint = Vector2.new(0, 1)
	boostFill.Position = UDim2.fromScale(0, 1)
	boostFill.Size = UDim2.fromScale(1, 0.33)
	boostFill.BackgroundColor3 = C.Boost
	boostFill.BorderSizePixel = 0
	boostFill.Parent = fillBack
	Theme.gradient(boostFill, Color3.fromRGB(255, 230, 110), Color3.fromRGB(255, 120, 30))
	boostNumber = Theme.label(boostPanel, {
		size = UDim2.fromScale(1, 0.55),
		position = UDim2.fromScale(0, 0.12),
		text = "33",
		zIndex = 3,
	})
	Theme.label(boostPanel, {
		size = UDim2.fromScale(1, 0.2),
		position = UDim2.fromScale(0, 0.68),
		text = "BOOST",
		zIndex = 3,
	})

	-- Mega Shot meter.
	megaPanel = Theme.panel(gui, "Mega", UDim2.fromOffset(330, 40), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
	local megaBack = Instance.new("Frame")
	megaBack.Size = UDim2.new(1, -12, 1, -12)
	megaBack.Position = UDim2.fromOffset(6, 6)
	megaBack.BackgroundColor3 = C.PanelDark
	megaBack.ClipsDescendants = true
	megaBack.Parent = megaPanel
	Theme.corner(megaBack, 8)
	megaFill = Instance.new("Frame")
	megaFill.Size = UDim2.fromScale(0, 1)
	megaFill.BackgroundColor3 = C.Mega
	megaFill.BorderSizePixel = 0
	megaFill.Parent = megaBack
	Theme.gradient(megaFill, Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 70, 30))
	megaLabel = Theme.label(megaPanel, {
		size = UDim2.new(1, -16, 1, -8),
		position = UDim2.fromOffset(8, 4),
		text = "MEGA SHOT",
		zIndex = 3,
	})
	camLabel = Theme.label(gui, {
		size = UDim2.fromOffset(200, 22),
		position = UDim2.new(1, -20, 1, -156),
		anchor = Vector2.new(1, 1),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
	})

	-- Lobby panel: Scrap, next unlock, Garage button, match timer.
	lobbyPanel = Theme.panel(gui, "Lobby", UDim2.fromOffset(300, 168), UDim2.fromOffset(16, 16), Vector2.zero)
	Theme.padding(lobbyPanel, 10)
	scrapLabel = Theme.label(lobbyPanel, {
		size = UDim2.new(1, 0, 0, 34),
		text = "🔩 0 Scrap",
		color = C.Scrap,
		align = Enum.TextXAlignment.Left,
	})
	goalLabel = Theme.label(lobbyPanel, {
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.fromOffset(0, 38),
		text = "",
		font = Theme.Body,
		align = Enum.TextXAlignment.Left,
	})
	local goalBack = Instance.new("Frame")
	goalBack.Size = UDim2.new(1, 0, 0, 12)
	goalBack.Position = UDim2.fromOffset(0, 64)
	goalBack.BackgroundColor3 = C.PanelDark
	goalBack.Parent = lobbyPanel
	Theme.corner(goalBack, 6)
	goalFill = Instance.new("Frame")
	goalFill.Size = UDim2.fromScale(0, 1)
	goalFill.BackgroundColor3 = C.Good
	goalFill.Parent = goalBack
	Theme.corner(goalFill, 6)
	local garageButton = Theme.button(lobbyPanel, {
		name = "GarageButton",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 84),
		text = "🚗 GARAGE",
	})
	garageButton.Activated:Connect(function()
		HUD.GarageRequested:Fire()
	end)
	bannerLabel = Theme.label(gui, {
		name = "Banner",
		size = UDim2.fromOffset(700, 36),
		position = UDim2.new(0.5, 0, 0, 14),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Gold,
	})

	local scaledObjects: { GuiObject } =
		{ scoreboard, bigText, subText, boostPanel, megaPanel, camLabel, lobbyPanel, bannerLabel, teamBadge }
	for _, object in scaledObjects do
		Theme.scaled(object)
	end

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function refreshData()
	local data = PlayerDataClient.get()
	scrapLabel.Text = `🔩 {Theme.formatNumber(data.scrap)} Scrap`
	local goal = Rewards.nextGoal(data.owned, data.scrap)
	if goal then
		goalLabel.Text = if goal.canAfford
			then `{goal.emoji} {goal.displayName}: ready to unlock!`
			else `{goal.emoji} {goal.displayName}: {Theme.formatNumber(goal.have)} / {Theme.formatNumber(
				goal.price
			)}`
		goalFill.Size = UDim2.fromScale(math.clamp(goal.have / goal.price, 0, 1), 1)
		goalFill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
	else
		goalLabel.Text = "You own every car! 🏆"
		goalFill.Size = UDim2.fromScale(1, 1)
	end
end

local function numberAttr(name: string): number
	local value = stateObject:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function update()
	local now = serverNow()
	local phase = MatchState.phase(stateObject)
	local car = CarController.getCar()
	local driving = car ~= nil
	local inMatchPhase = phase == Phases.Countdown or phase == Phases.Playing or phase == Phases.GoalScored

	-- Scoreboard is visible to everyone while a match is on (spectators too).
	scoreboard.Visible = inMatchPhase or phase == Phases.Results
	blueScore.Text = tostring(numberAttr(Attr.BlueScore))
	orangeScore.Text = tostring(numberAttr(Attr.OrangeScore))
	local seconds = MatchState.clockSeconds(stateObject, now)
	local overtime = stateObject:GetAttribute(Attr.Overtime) == true
	clockLabel.Text = if overtime then "+" .. MatchState.formatClock(seconds) else MatchState.formatClock(seconds)
	clockLabel.TextColor3 = if overtime then C.Gold elseif seconds <= 30 then C.Bad else C.Text
	if stateObject:GetAttribute(Attr.WaitingForBall) == true then
		clockNote.Text = "0:00 - play on until the ball hits the ground!"
	elseif overtime then
		clockNote.Text = "OVERTIME - next goal wins!"
	else
		clockNote.Text = ""
	end

	-- Countdown before kickoff.
	if phase == Phases.Countdown then
		local left = math.ceil(MatchState.phaseSecondsLeft(stateObject, now))
		if left >= 1 then
			bigText.Text = tostring(left)
			bigText.TextColor3 = C.Gold
			bigText.Visible = true
			subText.Visible = false
			messageUntil = os.clock() + 0.2
		end
	elseif phase == Phases.Playing and lastPhase == Phases.Countdown then
		HUD.flash("GO!", C.Good, nil, 0.8)
	end
	lastPhase = phase
	if os.clock() > messageUntil then
		bigText.Visible = false
		subText.Visible = false
	end

	-- Driving widgets.
	boostPanel.Visible = driving and inMatchPhase
	megaPanel.Visible = driving and inMatchPhase
	camLabel.Visible = driving and inMatchPhase
	if car then
		local boost = car:GetAttribute(CarAttr.Boost)
		local boostValue = if type(boost) == "number" then boost else 0
		boostNumber.Text = tostring(math.floor(boostValue))
		boostFill.Size = UDim2.fromScale(1, math.clamp(boostValue / 100, 0, 1))
		local mega = car:GetAttribute(CarAttr.Mega)
		local megaValue = if type(mega) == "number" then mega else 0
		local armed = car:GetAttribute(CarAttr.MegaArmed) == true
		megaFill.Size = UDim2.fromScale(math.clamp(megaValue / GameConfig.Mega.Max, 0, 1), 1)
		local key = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			then "tap MEGA"
			elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "press X"
			else "press F"
		if armed then
			megaLabel.Text = "🔥 MEGA ARMED - HIT THE BALL! 🔥"
			megaLabel.TextColor3 = C.Gold
		elseif megaValue >= GameConfig.Mega.Max then
			megaLabel.Text = `⚡ MEGA READY - {key}! ⚡`
			megaLabel.TextColor3 = if math.floor(os.clock() * 4) % 2 == 0 then C.Gold else C.Text
		else
			megaLabel.Text = "MEGA SHOT"
			megaLabel.TextColor3 = C.Text
		end
		camLabel.Text = if CameraController.isBallCam() then "Ball cam: ON (C)" else "Ball cam: OFF (C)"
		local team = car:GetAttribute(CarAttr.Team)
		teamBadge.Text = if type(team) == "string" then `{string.upper(team)} TEAM` else ""
		teamBadge.TextColor3 = Theme.teamColor(if type(team) == "string" then team else nil)
	end
	teamBadge.Visible = driving

	-- Lobby.
	lobbyPanel.Visible = not driving
	local banner = stateObject:GetAttribute(Attr.Banner)
	if not driving and phase == Phases.Intermission then
		bannerLabel.Text = `Next match in {math.ceil(MatchState.phaseSecondsLeft(stateObject, now))}s!`
	elseif not driving and inMatchPhase then
		bannerLabel.Text = "Match in progress - you'll jump in when a seat opens!"
	elseif not driving and type(banner) == "string" then
		bannerLabel.Text = banner
	else
		bannerLabel.Text = ""
	end
	bannerLabel.Visible = not scoreboard.Visible and bannerLabel.Text ~= ""
end

function HUD.start()
	build()
	refreshData()
	PlayerDataClient.Changed:Connect(refreshData)
	RunService.RenderStepped:Connect(update)

	Remotes.GoalScored.OnClientEvent:Connect(function(team: any, scorer: any, assist: any, _position: any, combo: any)
		local teamName = if type(team) == "string" then team else ""
		local line = if type(scorer) == "string" and scorer ~= ""
			then `{scorer} scores for {string.upper(teamName)}!`
			else `{string.upper(teamName)} scores!`
		if type(assist) == "string" and assist ~= "" then
			line ..= ` (assist: {assist})`
		end
		if type(combo) == "string" and combo ~= "" then
			line = `{combo}  {line}`
		end
		HUD.flash("GOAL!", Theme.teamColor(teamName), line, 3.2)
	end)
	Remotes.Announce.OnClientEvent:Connect(function(kind: any, text: any)
		if kind == "overtime" and type(text) == "string" then
			HUD.flash("OVERTIME!", C.Gold, "Next goal wins!", 2.5)
		end
	end)
end

return HUD
