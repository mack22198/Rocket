--!strict
-- The in-game HUD. While driving: the scoreboard and clock, a boost dial, the Mega Shot meter and big centre
-- text (countdown, GO!, GOAL!). In the lobby: your Scrap, the next car you're saving for, the match timer and a
-- big Garage button (with a badge when one of your cars is ready to evolve).
--
-- Everything stays clear of Roblox's own buttons in the top corners.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Evolution = require(Shared.Config.Evolution)
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
local rgb = Color3.fromRGB

local DIAL_SEGMENTS = 20

local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()

local gui: ScreenGui
-- Match
local scoreboard: Frame
local blueScore: TextLabel
local orangeScore: TextLabel
local clockLabel: TextLabel
local clockNote: TextLabel
local youTag: TextLabel
local bigText: TextLabel
local subText: TextLabel
local dial: Frame
local dialSegments: { Frame } = {}
local dialColors: { Color3 } = {}
local boostNumber: TextLabel
local megaPanel: Frame
local megaBar: Theme.Bar
local megaLabel: TextLabel
local camPill: TextLabel
-- Lobby
local lobbyInfo: Frame
local scrapPill: TextLabel
local nextName: TextLabel
local nextAmount: TextLabel
local nextBar: Theme.Bar
local garageArea: Frame
local evolveBadge: TextLabel
local banner: TextLabel

local messageUntil = 0
local lastPhase = ""
local evolveReady = false

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
		Size = UDim2.fromOffset(700, 140),
	}):Play()
end

local function buildScoreboard()
	scoreboard = Instance.new("Frame")
	scoreboard.Name = "Scoreboard"
	scoreboard.Size = UDim2.fromOffset(420, 96)
	scoreboard.Position = UDim2.new(0.5, 0, 0, 8)
	scoreboard.AnchorPoint = Vector2.new(0.5, 0)
	scoreboard.BackgroundTransparency = 1
	scoreboard.Parent = gui

	local function teamBlock(team: string, color: Color3, x: number): TextLabel
		local block = Instance.new("Frame")
		block.Name = team
		block.Size = UDim2.fromOffset(100, 66)
		block.Position = UDim2.fromOffset(x, 0)
		block.BackgroundColor3 = color
		block.Parent = scoreboard
		Theme.corner(block, 16)
		Theme.stroke(block, color:Lerp(rgb(0, 0, 0), 0.55), 3)
		Theme.gradient(block, rgb(255, 255, 255), rgb(200, 200, 200))
		Theme.label(block, {
			name = "Team",
			size = UDim2.fromScale(1, 0.24),
			position = UDim2.fromScale(0, 0.72),
			text = string.upper(team),
			font = Enum.Font.GothamBlack,
			stroke = false,
		})
		return Theme.label(block, {
			name = "Score",
			size = UDim2.fromScale(1, 0.72),
			position = UDim2.fromScale(0, 0.02),
			text = "0",
		})
	end
	blueScore = teamBlock("Blue", C.Blue, 0)
	orangeScore = teamBlock("Orange", C.Orange, 320)

	local clock = Instance.new("Frame")
	clock.Name = "Clock"
	clock.Size = UDim2.fromOffset(200, 58)
	clock.Position = UDim2.fromOffset(110, 4)
	clock.BackgroundColor3 = C.Panel
	clock.Parent = scoreboard
	Theme.corner(clock, 14)
	Theme.stroke(clock, rgb(255, 255, 255), 2).Transparency = 0.8
	clockLabel = Theme.label(clock, {
		size = UDim2.new(1, -20, 0.84, 0),
		position = UDim2.new(0, 10, 0.08, 0),
		text = "5:00",
		stroke = false,
	})
	clockNote = Theme.pill(scoreboard, {
		name = "Note",
		size = UDim2.fromOffset(240, 26),
		position = UDim2.fromOffset(90, 68),
		text = "",
		color = C.Gold,
		font = Enum.Font.GothamBlack,
	})
	youTag = Theme.pill(scoreboard, {
		name = "You",
		size = UDim2.fromOffset(64, 24),
		position = UDim2.fromOffset(18, 70),
		text = "▲ YOU",
		font = Enum.Font.GothamBlack,
		background = C.Text,
		color = C.Ink,
		transparency = 0,
	})
end

local function buildBoostDial()
	dial = Instance.new("Frame")
	dial.Name = "Boost"
	dial.Size = UDim2.fromOffset(156, 156)
	dial.Position = UDim2.new(1, -22, 1, -22)
	dial.AnchorPoint = Vector2.new(1, 1)
	dial.BackgroundColor3 = C.Panel
	dial.BackgroundTransparency = 0.12
	dial.Parent = gui
	Theme.corner(dial, 78)
	Theme.stroke(dial, rgb(255, 255, 255), 2).Transparency = 0.8
	-- A 270 degree arc of segments, like a speedometer.
	for i = 1, DIAL_SEGMENTS do
		local t = (i - 0.5) / DIAL_SEGMENTS
		local angle = math.rad(-135 + 270 * t)
		local segment = Instance.new("Frame")
		segment.Name = `Segment{i}`
		segment.Size = UDim2.fromOffset(10, 22)
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.Position = UDim2.new(0.5, math.sin(angle) * 60, 0.5, -math.cos(angle) * 60)
		segment.Rotation = math.deg(angle)
		segment.BorderSizePixel = 0
		segment.Parent = dial
		Theme.corner(segment, 4)
		table.insert(dialSegments, segment)
		table.insert(dialColors, rgb(255, 236, 110):Lerp(rgb(255, 84, 30), t))
	end
	boostNumber = Theme.label(dial, {
		size = UDim2.fromOffset(90, 54),
		position = UDim2.new(0.5, 0, 0.5, -4),
		anchor = Vector2.new(0.5, 0.5),
		text = "0",
	})
	Theme.label(dial, {
		size = UDim2.fromOffset(80, 18),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "BOOST",
		font = Enum.Font.GothamBlack,
		color = C.Boost,
		stroke = false,
	})
	camPill = Theme.pill(gui, {
		name = "BallCam",
		size = UDim2.fromOffset(170, 30),
		position = UDim2.new(1, -22, 1, -190),
		anchor = Vector2.new(1, 1),
		text = "",
		font = Enum.Font.GothamBold,
		color = C.Muted,
	})
end

local function buildMegaMeter()
	megaPanel = Instance.new("Frame")
	megaPanel.Name = "Mega"
	megaPanel.Size = UDim2.fromOffset(400, 54)
	megaPanel.Position = UDim2.new(0.5, 0, 1, -20)
	megaPanel.AnchorPoint = Vector2.new(0.5, 1)
	megaPanel.BackgroundColor3 = C.Panel
	megaPanel.BackgroundTransparency = 0.12
	megaPanel.Parent = gui
	Theme.corner(megaPanel, 27)
	Theme.stroke(megaPanel, rgb(255, 255, 255), 2).Transparency = 0.8
	local icon = Theme.label(megaPanel, {
		name = "Icon",
		size = UDim2.fromOffset(46, 46),
		position = UDim2.fromOffset(4, 4),
		text = "💥",
		stroke = false,
	})
	icon.BackgroundColor3 = C.Mega
	icon.BackgroundTransparency = 0
	Theme.corner(icon, 23)
	megaBar = Theme.bar(megaPanel, UDim2.new(1, -70, 0, 30), UDim2.fromOffset(58, 12), C.Mega)
	megaLabel = Theme.label(megaPanel, {
		size = UDim2.new(1, -86, 0, 24),
		position = UDim2.fromOffset(66, 15),
		text = "MEGA SHOT",
		zIndex = 3,
	})
end

local function buildLobby()
	lobbyInfo = Instance.new("Frame")
	lobbyInfo.Name = "LobbyInfo"
	lobbyInfo.Size = UDim2.fromOffset(310, 150)
	lobbyInfo.Position = UDim2.fromOffset(16, 68)
	lobbyInfo.BackgroundTransparency = 1
	lobbyInfo.Parent = gui
	scrapPill = Theme.pill(lobbyInfo, {
		name = "Scrap",
		size = UDim2.fromOffset(210, 48),
		text = "🔩 0",
		color = C.Scrap,
	})
	local card = Theme.panel(lobbyInfo, "NextCar", UDim2.fromOffset(310, 86), UDim2.fromOffset(0, 58))
	Theme.label(card, {
		size = UDim2.fromOffset(200, 16),
		position = UDim2.fromOffset(14, 10),
		text = "SAVING UP FOR",
		font = Enum.Font.GothamBlack,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	nextName = Theme.label(card, {
		size = UDim2.new(1, -28, 0, 26),
		position = UDim2.fromOffset(14, 28),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	nextBar = Theme.bar(card, UDim2.new(1, -118, 0, 14), UDim2.fromOffset(14, 62), C.Good)
	nextAmount = Theme.label(card, {
		size = UDim2.fromOffset(92, 18),
		position = UDim2.new(1, -100, 0, 60),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})

	garageArea = Instance.new("Frame")
	garageArea.Name = "GarageArea"
	garageArea.Size = UDim2.fromOffset(300, 72)
	garageArea.Position = UDim2.new(0.5, 0, 1, -24)
	garageArea.AnchorPoint = Vector2.new(0.5, 1)
	garageArea.BackgroundTransparency = 1
	garageArea.Parent = gui
	local garageButton = Theme.button(garageArea, {
		name = "GarageButton",
		size = UDim2.fromScale(1, 1),
		text = "🚗  GARAGE",
	})
	garageButton.Activated:Connect(function()
		HUD.GarageRequested:Fire()
	end)
	evolveBadge = Theme.pill(garageArea, {
		name = "EvolveBadge",
		size = UDim2.fromOffset(200, 32),
		position = UDim2.new(0.5, 0, 0, -8),
		anchor = Vector2.new(0.5, 1),
		text = "✨ READY TO EVOLVE!",
		background = C.Evolve,
		transparency = 0,
	})
	evolveBadge.Rotation = -3

	banner = Theme.pill(gui, {
		name = "Banner",
		size = UDim2.fromOffset(580, 42),
		position = UDim2.new(0.5, 0, 0, 12),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Gold,
	})
end

local function build()
	gui = Theme.screen("TurboHUD", 5)
	buildScoreboard()
	buildBoostDial()
	buildMegaMeter()
	buildLobby()

	-- Centre messages.
	bigText = Theme.label(gui, {
		name = "BigText",
		size = UDim2.fromOffset(700, 140),
		position = UDim2.fromScale(0.5, 0.3),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 5,
	})
	bigText.Visible = false
	Theme.stroke(bigText, rgb(0, 0, 0), 5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	subText = Theme.label(gui, {
		name = "SubText",
		size = UDim2.fromOffset(760, 40),
		position = UDim2.new(0.5, 0, 0.3, 84),
		anchor = Vector2.new(0.5, 0),
		text = "",
		zIndex = 5,
	})
	subText.Visible = false

	local scaledObjects: { GuiObject } =
		{ scoreboard, bigText, subText, dial, camPill, megaPanel, lobbyInfo, garageArea, banner }
	for _, object in scaledObjects do
		Theme.scaled(object)
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function refreshData()
	local data = PlayerDataClient.get()
	scrapPill.Text = `🔩 {Theme.formatNumber(data.scrap)}`
	local goal = Rewards.nextGoal(data.owned, data.scrap)
	if goal then
		nextName.Text = `{goal.emoji} {goal.displayName}`
		nextAmount.Text = if goal.canAfford
			then "UNLOCK IT!"
			else `{Theme.formatNumber(goal.have)} / {Theme.formatNumber(goal.price)}`
		nextAmount.TextColor3 = if goal.canAfford then C.Gold else C.Muted
		nextBar.set(goal.have / math.max(goal.price, 1))
		nextBar.fill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
	else
		nextName.Text = "🏆 Every car unlocked!"
		nextAmount.Text = ""
		nextBar.set(1)
	end
	-- Is any car ready to evolve?
	evolveReady = false
	for id in data.owned do
		local def = CarCatalog.get(id)
		if def and Evolution.progress(def, data.carXp[id] or 0, data.carStage[id] or 1).ready then
			evolveReady = true
		end
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

	-- The scoreboard shows for everyone while a match is on (spectators too).
	scoreboard.Visible = inMatchPhase or phase == Phases.Results
	blueScore.Text = tostring(numberAttr(Attr.BlueScore))
	orangeScore.Text = tostring(numberAttr(Attr.OrangeScore))
	local seconds = MatchState.clockSeconds(stateObject, now)
	local overtime = stateObject:GetAttribute(Attr.Overtime) == true
	clockLabel.Text = if overtime then "+" .. MatchState.formatClock(seconds) else MatchState.formatClock(seconds)
	clockLabel.TextColor3 = if overtime then C.Gold elseif seconds <= 30 then C.Bad else C.Text
	if stateObject:GetAttribute(Attr.WaitingForBall) == true then
		clockNote.Text = "LAST CHANCE - UNTIL THE BALL LANDS!"
	elseif overtime then
		clockNote.Text = "OVERTIME - NEXT GOAL WINS!"
	else
		clockNote.Text = ""
	end
	clockNote.Visible = clockNote.Text ~= ""

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

	-- Driving widgets. On touch screens the boost amount shows on the BOOST button instead (see TouchControls).
	local showDriving = driving and inMatchPhase
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	dial.Visible = showDriving and not touchOnly
	megaPanel.Visible = showDriving
	camPill.Visible = showDriving and not touchOnly
	youTag.Visible = false
	if car then
		local boost = car:GetAttribute(CarAttr.Boost)
		local boostValue = if type(boost) == "number" then boost else 0
		boostNumber.Text = tostring(math.floor(boostValue))
		local lit = math.floor(boostValue / 100 * DIAL_SEGMENTS + 0.5)
		for i, segment in dialSegments do
			local on = i <= lit
			segment.BackgroundColor3 = if on then dialColors[i] else C.Text
			segment.BackgroundTransparency = if on then 0 else 0.82
		end

		local mega = car:GetAttribute(CarAttr.Mega)
		local megaValue = if type(mega) == "number" then mega else 0
		local armed = car:GetAttribute(CarAttr.MegaArmed) == true
		megaBar.set(megaValue / GameConfig.Mega.Max)
		local key = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			then "TAP MEGA"
			elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "PRESS X"
			else "PRESS F"
		local pulse = math.floor(os.clock() * 4) % 2 == 0
		if armed then
			megaLabel.Text = "🔥 ARMED - HIT THE BALL!"
			megaLabel.TextColor3 = C.Gold
			megaBar.fill.BackgroundColor3 = C.Gold
		elseif megaValue >= GameConfig.Mega.Max then
			megaLabel.Text = `MEGA READY - {key}!`
			megaLabel.TextColor3 = C.Text
			megaBar.fill.BackgroundColor3 = if pulse then C.Gold else C.Mega
		else
			megaLabel.Text = "MEGA SHOT"
			megaLabel.TextColor3 = C.Text
			megaBar.fill.BackgroundColor3 = C.Mega
		end
		camPill.Text = if CameraController.isBallCam() then "📷 BALL CAM: ON" else "📷 BALL CAM: OFF"

		local team = car:GetAttribute(CarAttr.Team)
		if team == "Blue" or team == "Orange" then
			youTag.Visible = scoreboard.Visible
			youTag.Position = UDim2.fromOffset(if team == "Blue" then 18 else 338, 70)
		end
	end

	-- Lobby.
	lobbyInfo.Visible = not driving
	garageArea.Visible = not driving
	evolveBadge.Visible = evolveReady
	if evolveReady then
		evolveBadge.Rotation = -3 + math.sin(os.clock() * 5) * 2
	end
	local bannerText = ""
	local status = stateObject:GetAttribute(Attr.Banner)
	if not driving and phase == Phases.Intermission then
		bannerText = `NEXT MATCH IN {math.ceil(MatchState.phaseSecondsLeft(stateObject, now))}`
	elseif not driving and inMatchPhase then
		bannerText = "MATCH IN PROGRESS - YOU'LL JOIN WHEN A SEAT OPENS"
	elseif not driving and type(status) == "string" then
		bannerText = string.upper(status)
	end
	banner.Text = bannerText
	banner.Visible = not scoreboard.Visible and bannerText ~= ""
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
