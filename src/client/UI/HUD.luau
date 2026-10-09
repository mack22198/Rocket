--!strict
-- The in-game HUD: the scoreboard and clock, your ultimate meter (and a big banner and flash of colour when you set
-- it off), big centre text (countdown, GO!, GOAL!), a note about what's happening to your car, and the MENU
-- button. It's only shown during matches - the menus have
-- their own screens. (On phones and tablets the ultimate meter is the ULT button instead; see TouchControls.)
--
-- Everything stays clear of Roblox's own buttons in the top corners.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)
local Twists = require(Shared.Config.Twists)
local Signal = require(Shared.Util.Signal)

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local Theme = require(script.Parent.Theme)

local HUD = {}

-- The MENU button was pressed.
HUD.MenuRequested = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local Phases = MatchState.Phases
local Attr = MatchState.Attr
local CarAttr = MatchState.CarAttr
local rgb = Color3.fromRGB

local RING_SEGMENTS = 24

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
local menuButton: TextButton
-- Your ultimate
local ultDial: Frame
local ultRing: Theme.Ring
local ultNumber: TextLabel
local ultIcon: TextLabel
local ultCaption: TextLabel
local ultKey: TextLabel
local ultName: TextLabel
local lastCharge = -1
-- Setting it off
local ultFlash: Frame
local ultBanner: Frame
local ultBannerPop: UIScale
local ultBannerIcon: TextLabel
local ultBannerName: TextLabel
local ultBannerShown = 0
-- What's happening to your car
local statusPill: TextLabel
local noticeText = ""
local noticeUntil = 0
-- Match twist
local twistBanner: Frame
local twistName: TextLabel
local twistText: TextLabel
local twistPill: TextLabel
local twistShownFor = -1 -- the match whose twist banner has been shown
local twistBannerUntil = 0

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
		Size = UDim2.fromOffset(700, 140),
	}):Play()
end

local function buildScoreboard()
	scoreboard = Instance.new("Frame")
	scoreboard.Name = "Scoreboard"
	scoreboard.Size = UDim2.fromOffset(392, 100)
	scoreboard.Position = UDim2.new(0.5, 0, 0, 10)
	scoreboard.AnchorPoint = Vector2.new(0.5, 0)
	scoreboard.BackgroundTransparency = 1
	scoreboard.Parent = gui

	local function teamBlock(team: string, color: Color3, x: number): TextLabel
		local block = Instance.new("Frame")
		block.Name = team
		block.Size = UDim2.fromOffset(96, 66)
		block.Position = UDim2.fromOffset(x, 0)
		block.BackgroundColor3 = color
		block.Parent = scoreboard
		Theme.corner(block, 14)
		Theme.stroke(block, C.Ink, 3)
		Theme.lip(block, 6)
		return Theme.heading(block, {
			name = "Score",
			size = UDim2.new(1, 0, 1, -8),
			position = UDim2.fromOffset(0, 2),
			text = "0",
			color = C.Text,
			textSize = 50,
			stroke = true,
		})
	end
	blueScore = teamBlock("Blue", C.Blue, 0)
	orangeScore = teamBlock("Orange", C.Orange, 296)

	local clock = Theme.slab(scoreboard, "Clock", UDim2.fromOffset(180, 58), UDim2.fromOffset(106, 4))
	clockLabel = Theme.heading(clock, {
		size = UDim2.new(1, -20, 1, -10),
		position = UDim2.fromOffset(10, 3),
		text = MatchState.formatClock(GameConfig.Match.Length),
		color = C.Text,
		textSize = 42,
	})
	clockNote = Theme.pill(scoreboard, {
		name = "Note",
		size = UDim2.fromOffset(300, 28),
		position = UDim2.fromOffset(46, 72),
		text = "",
		background = C.Gold,
	})
	youTag = Theme.pill(scoreboard, {
		name = "You",
		size = UDim2.fromOffset(60, 24),
		position = UDim2.fromOffset(18, 72),
		text = "YOU",
		background = C.Text,
	})
end

-- The ultimate meter: a round dial whose ring fills up, with the ultimate's name above it and its key on it.
local function buildUltDial()
	ultDial = Instance.new("Frame")
	ultDial.Name = "Ultimate"
	ultDial.Size = UDim2.fromOffset(150, 150)
	ultDial.Position = UDim2.new(1, -24, 1, -24)
	ultDial.AnchorPoint = Vector2.new(1, 1)
	ultDial.BackgroundColor3 = C.Panel
	ultDial.Parent = gui
	Theme.corner(ultDial, 75)
	Theme.stroke(ultDial, C.Ink, 4)
	ultRing = Theme.ring(ultDial, RING_SEGMENTS, 58, Vector2.new(9, 18))
	ultNumber = Theme.heading(ultDial, {
		name = "Charge",
		size = UDim2.fromOffset(96, 46),
		position = UDim2.new(0.5, 0, 0.5, -6),
		anchor = Vector2.new(0.5, 0.5),
		text = "0%",
		color = C.Text,
		textSize = 40,
	})
	ultIcon = Theme.label(ultDial, {
		name = "Icon",
		size = UDim2.fromOffset(60, 60),
		position = UDim2.new(0.5, 0, 0.5, -10),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		color = C.Text,
	})
	ultCaption = Theme.label(ultDial, {
		name = "Caption",
		size = UDim2.fromOffset(92, 16),
		position = UDim2.new(0.5, 0, 0.5, 28),
		anchor = Vector2.new(0.5, 0.5),
		text = "ULTIMATE",
		font = Theme.Caps,
		color = C.Muted,
		textSize = 13,
	})
	ultKey = Theme.pill(ultDial, {
		name = "Key",
		size = UDim2.fromOffset(44, 30),
		position = UDim2.new(1, 6, 0, 0),
		anchor = Vector2.new(1, 0),
		text = "E",
		background = C.Text,
	})
	ultName = Theme.pill(ultDial, {
		name = "Name",
		size = UDim2.fromOffset(176, 30),
		position = UDim2.new(0.5, 0, 0, -12),
		anchor = Vector2.new(0.5, 1),
		text = "",
	})
end

-- The moment you set off your ultimate: the screen flashes its colour and its name bursts onto the screen.
local function buildUltBanner()
	ultFlash = Instance.new("Frame")
	ultFlash.Name = "UltFlash"
	ultFlash.Size = UDim2.fromScale(1, 1)
	ultFlash.BackgroundTransparency = 1
	ultFlash.BorderSizePixel = 0
	ultFlash.Parent = gui

	ultBanner = Instance.new("Frame")
	ultBanner.Name = "UltBanner"
	ultBanner.Size = UDim2.fromOffset(760, 210)
	ultBanner.Position = UDim2.fromScale(0.5, 0.42)
	ultBanner.AnchorPoint = Vector2.new(0.5, 0.5)
	ultBanner.BackgroundTransparency = 1
	ultBanner.Visible = false
	ultBanner.Parent = gui
	local inner = Instance.new("Frame")
	inner.Name = "Pop"
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.Parent = ultBanner
	ultBannerPop = Instance.new("UIScale")
	ultBannerPop.Parent = inner
	ultBannerIcon = Theme.label(inner, {
		name = "Icon",
		size = UDim2.fromOffset(84, 84),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Text,
	})
	Theme.pill(inner, {
		name = "Kicker",
		size = UDim2.fromOffset(170, 30),
		position = UDim2.new(0.5, 0, 0, 84),
		anchor = Vector2.new(0.5, 0),
		text = "ULTIMATE!",
		background = C.Gold,
	})
	ultBannerName = Theme.heading(inner, {
		name = "Name",
		size = UDim2.new(1, 0, 0, 92),
		position = UDim2.fromOffset(0, 116),
		text = "",
		textSize = 80,
		stroke = true,
	})
	Theme.outline(ultBannerName, 5)
end

local function showUltBanner(power: Powers.PowerDef)
	ultBannerShown += 1
	local shown = ultBannerShown
	ultFlash.BackgroundColor3 = power.Color
	ultFlash.BackgroundTransparency = 0.6
	TweenService:Create(ultFlash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	ultBannerIcon.Text = power.Emoji
	ultBannerName.Text = `{string.upper(power.Name)}!`
	ultBannerName.TextColor3 = power.Color
	ultBanner.Visible = true
	ultBannerPop.Scale = 0.3
	TweenService:Create(ultBannerPop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(1.5, function()
		if shown == ultBannerShown then
			ultBanner.Visible = false
		end
	end)
end

local function buildMenuButton()
	local holder = Instance.new("Frame")
	holder.Name = "Menu"
	holder.Size = UDim2.fromOffset(104, 46)
	holder.Position = UDim2.fromOffset(16, 64)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	Theme.scaled(holder)
	menuButton = Theme.button(holder, {
		name = "MenuButton",
		size = UDim2.fromScale(1, 1),
		text = "MENU",
		color = C.Panel,
		textSize = 20,
	})
	menuButton.Activated:Connect(function()
		HUD.MenuRequested:Fire()
	end)
end

-- "MATCH TWIST: GIANT BALL": shown big at the first kickoff, then as a small tag under the scoreboard all match.
local function buildTwist()
	twistBanner = Theme.card(gui, "Twist", UDim2.fromOffset(540, 128), UDim2.fromScale(0.5, 0.6), Vector2.new(0.5, 0.5))
	Theme.label(twistBanner, {
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.fromOffset(0, 14),
		text = "MATCH TWIST",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 14,
	})
	twistName = Theme.heading(twistBanner, {
		name = "Name",
		size = UDim2.new(1, -20, 0, 48),
		position = UDim2.fromOffset(10, 34),
		text = "",
		textSize = 46,
	})
	twistText = Theme.label(twistBanner, {
		name = "Text",
		size = UDim2.new(1, -40, 0, 20),
		position = UDim2.fromOffset(20, 88),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 17,
	})
	twistBanner.Visible = false
	twistPill = Theme.pill(gui, {
		name = "TwistPill",
		size = UDim2.fromOffset(200, 28),
		position = UDim2.new(0.5, 0, 0, 116),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Gold,
	})
	twistPill.Visible = false
end

local function build()
	gui = Theme.screen("TurboHUD", 5)
	buildScoreboard()
	buildUltDial()
	buildUltBanner()
	buildTwist()
	buildMenuButton()
	statusPill = Theme.pill(gui, {
		name = "Status",
		size = UDim2.fromOffset(340, 34),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
	})
	statusPill.Visible = false

	-- Centre messages.
	bigText = Theme.heading(gui, {
		name = "BigText",
		size = UDim2.fromOffset(700, 140),
		position = UDim2.fromScale(0.5, 0.3),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		color = C.Text,
		zIndex = 5,
	})
	bigText.Visible = false
	Theme.outline(bigText, 6)
	subText = Theme.pill(gui, {
		name = "SubText",
		size = UDim2.fromOffset(720, 40),
		position = UDim2.new(0.5, 0, 0.3, 84),
		anchor = Vector2.new(0.5, 0),
		text = "",
	})
	subText.ZIndex = 5
	subText.Visible = false

	local scaledObjects: { GuiObject } =
		{ scoreboard, bigText, subText, ultDial, ultBanner, statusPill, twistBanner, twistPill }
	for _, object in scaledObjects do
		Theme.scaled(object)
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function numberAttr(name: string): number
	local value = stateObject:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function keyName(keyboard: string, gamepad: string): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return gamepad
	end
	return keyboard
end

-- What's happening to your car right now, for the status pill (most important first).
local function statusText(car: Model): (string?, Color3)
	local spin, slow = CarController.effects()
	if spin > 0 then
		return "SPUN OUT!", rgb(255, 230, 90)
	elseif slow > 0 then
		return "STUCK IN CHEESE!", rgb(255, 200, 60)
	elseif car:GetAttribute(CarAttr.MegaArmed) == true then
		return "HOT SAUCE: HIT THE BALL!", C.Gold
	elseif car:GetAttribute(CarAttr.Ghost) == true then
		return "SHARK DIVE: UNTOUCHABLE", rgb(110, 220, 255)
	elseif car:GetAttribute(CarAttr.Pull) == "beam" then
		return "TRACTOR BEAM", rgb(150, 255, 130)
	end
	return nil, C.Text
end

-- The ultimate meter: the ring fills in the ultimate's colour, then the dial glows and pulses when it's ready.
local function updateUlt(car: Model)
	local carId = car:GetAttribute(CarAttr.CarId)
	local power = Powers.forCar(if type(carId) == "string" then carId else "")
	local charge, ready = CarController.ultCharge()
	local pulse = math.floor(os.clock() * 4) % 2 == 0
	ultName.Text = string.upper(power.Name)
	ultName.TextColor3 = power.Color
	ultKey.Text = keyName("E", "X")
	ultNumber.Visible = not ready
	ultIcon.Visible = ready
	if ready then
		ultRing.set(1, if pulse then C.Gold else power.Color)
		ultIcon.Text = power.Emoji
		ultIcon.Size = UDim2.fromOffset(if pulse then 64 else 58, if pulse then 64 else 58)
		ultCaption.Text = "READY!"
		ultCaption.TextColor3 = C.Gold
		ultDial.BackgroundColor3 = power.Color:Lerp(C.Panel, if pulse then 0.35 else 0.55)
		ultKey.BackgroundColor3 = C.Gold
	else
		ultRing.set(charge / GameConfig.Ultimate.Max, power.Color)
		ultNumber.Text = `{math.floor(charge / GameConfig.Ultimate.Max * 100)}%`
		ultCaption.Text = "ULTIMATE"
		ultCaption.TextColor3 = C.Muted
		ultDial.BackgroundColor3 = C.Panel
		ultKey.BackgroundColor3 = C.Muted
	end
	-- "+12" floats up beside the meter when something you did charged it.
	if lastCharge >= 0 and charge - lastCharge >= 2 and ultDial.Visible then
		Theme.floatText(
			ultDial,
			`+{math.floor(charge - lastCharge)}`,
			UDim2.new(0, -6, 0.5, 0),
			Vector2.new(1, 0.5),
			46
		)
	end
	lastCharge = charge
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

	-- The match twist: a big banner at the first kickoff, then a small reminder under the scoreboard.
	local twist = Twists.get(stateObject:GetAttribute(Attr.Twist) :: string?)
	local matchId = numberAttr(Attr.MatchId)
	if twist and phase == Phases.Countdown and twistShownFor ~= matchId then
		twistShownFor = matchId
		twistBannerUntil = os.clock() + 4.5
		twistName.Text = string.upper(twist.Name)
		twistText.Text = twist.Description
	end
	twistBanner.Visible = twist ~= nil and os.clock() < twistBannerUntil and inMatchPhase
	twistPill.Visible = twist ~= nil and scoreboard.Visible and not twistBanner.Visible
	if twist then
		twistPill.Text = string.upper(twist.Name)
	end

	if os.clock() > messageUntil then
		bigText.Visible = false
		subText.Visible = false
	end

	-- Your car: the ultimate meter (on touch screens it's on the ULT button instead) and what's happening to it.
	local showDriving = driving and inMatchPhase
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	ultDial.Visible = showDriving and not touchOnly
	statusPill.Visible = false
	youTag.Visible = false
	if car then
		updateUlt(car)
		local text, color = statusText(car)
		if not text and os.clock() < noticeUntil then
			text, color = noticeText, C.Text
		end
		statusPill.Visible = text ~= nil and showDriving
		statusPill.Text = text or ""
		statusPill.TextColor3 = color

		local team = car:GetAttribute(CarAttr.Team)
		if team == "Blue" or team == "Orange" then
			youTag.Visible = scoreboard.Visible
			youTag.Position = UDim2.fromOffset(if team == "Blue" then 18 else 338, 70)
		end
	end
end

-- The HUD only shows during matches.
function HUD.setVisible(on: boolean)
	gui.Enabled = on
end

function HUD.start()
	build()
	gui.Enabled = false
	RunService.RenderStepped:Connect(update)

	CarController.CarChanged:Connect(function()
		lastCharge = -1
	end)
	-- A quick note when ball cam is switched on or off (C / Y).
	CameraController.BallCamChanged:Connect(function(on: boolean)
		noticeText = if on then "BALL CAM ON" else "BALL CAM OFF"
		noticeUntil = os.clock() + 1.5
	end)
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
	-- You set off your ultimate.
	Remotes.PowerFx.OnClientEvent:Connect(function(kind: any, _position: any, _team: any, car: any)
		local mine = CarController.getCar()
		if kind == "ult" and mine and car == mine then
			local id = mine:GetAttribute(CarAttr.Power)
			local power = if type(id) == "string" then Powers.power(id) else nil
			if power then
				showUltBanner(power)
			end
		end
	end)
end

return HUD
