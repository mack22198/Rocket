--!strict
-- The in-game HUD: the scoreboard and clock, a boost dial, the Mega Shot meter, your item and car power, big
-- centre text (countdown, GO!, GOAL!) and the ☰ MENU button. It's only shown during matches - the menus have
-- their own screens.
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
local Signal = require(Shared.Util.Signal)

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local Theme = require(script.Parent.Theme)

local HUD = {}

-- The ☰ MENU button was pressed.
HUD.MenuRequested = Signal.new() :: Signal.Signal<>

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
local menuButton: TextButton
-- Item and power
type Slot = {
	frame: Frame,
	icon: TextLabel,
	caption: TextLabel,
	key: TextLabel,
	cooldown: Frame,
	timer: TextLabel,
	stroke: UIStroke,
}
local powerPanel: Frame
local itemSlot: Slot
local powerSlot: Slot
local statusPill: TextLabel
local noticeText = ""
local noticeUntil = 0

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

local function buildMenuButton()
	local holder = Instance.new("Frame")
	holder.Name = "Menu"
	holder.Size = UDim2.fromOffset(118, 42)
	holder.Position = UDim2.fromOffset(16, 66)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	Theme.scaled(holder)
	menuButton = Theme.button(holder, {
		name = "MenuButton",
		size = UDim2.fromScale(1, 1),
		text = "☰  MENU",
		color = C.Panel,
		textColor = C.Text,
	})
	menuButton.BackgroundTransparency = 0.15
	menuButton.Activated:Connect(function()
		HUD.MenuRequested:Fire()
	end)
end

-- One square slot (the item or the power) with a big emoji, its key in the corner and its name below.
local function buildSlot(name: string, x: number): Slot
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromOffset(92, 92)
	frame.Position = UDim2.fromOffset(x, 8)
	frame.BackgroundColor3 = C.Panel
	frame.BackgroundTransparency = 0.12
	frame.Parent = powerPanel
	Theme.corner(frame, 20)
	local stroke = Theme.stroke(frame, rgb(255, 255, 255), 3)
	stroke.Transparency = 0.7
	local icon = Theme.label(frame, {
		name = "Icon",
		size = UDim2.fromOffset(62, 62),
		position = UDim2.fromScale(0.5, 0.47),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		stroke = false,
		zIndex = 2,
	})
	local cooldown = Instance.new("Frame")
	cooldown.Name = "Cooldown"
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.BackgroundColor3 = rgb(0, 0, 0)
	cooldown.BackgroundTransparency = 0.45
	cooldown.BorderSizePixel = 0
	cooldown.ZIndex = 3
	cooldown.Parent = frame
	Theme.corner(cooldown, 20)
	local timer = Theme.label(frame, {
		name = "Timer",
		size = UDim2.fromOffset(60, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 4,
	})
	local caption = Theme.label(powerPanel, {
		name = `{name}Caption`,
		size = UDim2.fromOffset(108, 16),
		position = UDim2.fromOffset(x + 46, 106),
		anchor = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Caps,
		stroke = false,
	})
	local key = Theme.pill(frame, {
		name = "Key",
		size = UDim2.fromOffset(38, 24),
		position = UDim2.new(1, 8, 0, -8),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		background = C.Text,
		color = C.Ink,
		transparency = 0,
	})
	key.ZIndex = 5
	return {
		frame = frame,
		icon = icon,
		caption = caption,
		key = key,
		cooldown = cooldown,
		timer = timer,
		stroke = stroke,
	}
end

local function buildPowerPanel()
	powerPanel = Instance.new("Frame")
	powerPanel.Name = "Powers"
	powerPanel.Size = UDim2.fromOffset(222, 124)
	powerPanel.Position = UDim2.new(0, 22, 1, -22)
	powerPanel.AnchorPoint = Vector2.new(0, 1)
	powerPanel.BackgroundTransparency = 1
	powerPanel.Parent = gui
	itemSlot = buildSlot("Item", 0)
	powerSlot = buildSlot("Power", 122)
	statusPill = Theme.pill(gui, {
		name = "Status",
		size = UDim2.fromOffset(340, 34),
		position = UDim2.new(0.5, 0, 1, -86),
		anchor = Vector2.new(0.5, 1),
		text = "",
		font = Theme.Caps,
	})
	statusPill.Visible = false
end

local function build()
	gui = Theme.screen("TurboHUD", 5)
	buildScoreboard()
	buildBoostDial()
	buildMegaMeter()
	buildPowerPanel()
	buildMenuButton()

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
		{ scoreboard, bigText, subText, dial, camPill, megaPanel, powerPanel, statusPill }
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
	local spin, slow, freeze = CarController.effects()
	if car:GetAttribute(CarAttr.Frozen) == true or freeze > 0 then
		return "❄️ FROZEN!", rgb(170, 230, 255)
	elseif spin > 0 then
		return "🌀 SPUN OUT!", rgb(255, 230, 90)
	elseif slow > 0 then
		return "🧀 STUCK IN CHEESE!", rgb(255, 200, 60)
	elseif car:GetAttribute(CarAttr.Shield) == true then
		return "🛡️ BUBBLE SHIELD", rgb(140, 190, 255)
	elseif car:GetAttribute(CarAttr.Ghost) == true then
		return "🌊 SHARK DIVE - UNTOUCHABLE", rgb(110, 220, 255)
	elseif car:GetAttribute(CarAttr.Rocket) == true then
		return "🚀 ROCKET FUEL - BOOST FOREVER!", rgb(255, 180, 70)
	elseif car:GetAttribute(CarAttr.Pull) == "magnet" then
		return "🧲 MAGNET ON", rgb(255, 120, 130)
	elseif car:GetAttribute(CarAttr.Pull) == "beam" then
		return "🛸 TRACTOR BEAM", rgb(150, 255, 130)
	end
	return nil, C.Text
end

local function numberOf(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function updatePowers(car: Model, now: number, pulse: boolean)
	-- The item slot: empty, spinning like a slot machine, or ready to use.
	local item = car:GetAttribute(CarAttr.Item)
	local itemDef = if type(item) == "string" then Powers.item(item) else nil
	local itemReadyAt = numberOf(car, CarAttr.ItemReadyAt)
	itemSlot.key.Text = keyName("R", "RB")
	itemSlot.cooldown.Size = UDim2.fromScale(1, 0)
	itemSlot.timer.Text = ""
	if not itemDef then
		itemSlot.icon.Text = "?"
		itemSlot.icon.TextTransparency = 0.6
		itemSlot.caption.Text = "GRAB A ? BOX"
		itemSlot.caption.TextColor3 = C.Muted
		itemSlot.frame.BackgroundColor3 = C.Panel
		itemSlot.stroke.Color = rgb(255, 255, 255)
		itemSlot.stroke.Transparency = 0.7
		itemSlot.key.Visible = false
	elseif now < itemReadyAt then
		local order = Powers.ItemOrder
		local spinning = Powers.Items[order[math.floor(os.clock() * 14) % #order + 1]]
		itemSlot.icon.Text = spinning.Emoji
		itemSlot.icon.TextTransparency = 0
		itemSlot.caption.Text = "..."
		itemSlot.caption.TextColor3 = C.Gold
		itemSlot.frame.BackgroundColor3 = spinning.Color:Lerp(C.Panel, 0.5)
		itemSlot.stroke.Color = C.Gold
		itemSlot.stroke.Transparency = 0
		itemSlot.key.Visible = false
	else
		itemSlot.icon.Text = itemDef.Emoji
		itemSlot.icon.TextTransparency = 0
		itemSlot.caption.Text = string.upper(itemDef.Name)
		itemSlot.caption.TextColor3 = itemDef.Color
		itemSlot.frame.BackgroundColor3 = itemDef.Color:Lerp(C.Panel, if pulse then 0.35 else 0.5)
		itemSlot.stroke.Color = itemDef.Color
		itemSlot.stroke.Transparency = 0
		itemSlot.key.Visible = true
	end

	-- The power slot: the car's own power, with a shade that drains away as it recharges.
	local powerId = car:GetAttribute(CarAttr.Power)
	local carId = car:GetAttribute(CarAttr.CarId)
	local power = Powers.forCar(if type(carId) == "string" then carId else "")
	local left = numberOf(car, CarAttr.PowerReadyAt) - now
	powerSlot.icon.Text = power.Emoji
	powerSlot.icon.TextTransparency = 0
	powerSlot.caption.Text = string.upper(power.Name)
	powerSlot.key.Text = keyName("G", "LB")
	if type(powerId) == "string" and left > 0 then
		powerSlot.cooldown.Size = UDim2.fromScale(1, math.clamp(left / power.Cooldown, 0, 1))
		powerSlot.timer.Text = tostring(math.ceil(left))
		powerSlot.caption.TextColor3 = C.Muted
		powerSlot.frame.BackgroundColor3 = C.Panel
		powerSlot.stroke.Color = rgb(255, 255, 255)
		powerSlot.stroke.Transparency = 0.7
		powerSlot.key.Visible = false
	else
		powerSlot.cooldown.Size = UDim2.fromScale(1, 0)
		powerSlot.timer.Text = ""
		powerSlot.caption.TextColor3 = power.Color
		powerSlot.frame.BackgroundColor3 = power.Color:Lerp(C.Panel, if pulse then 0.35 else 0.5)
		powerSlot.stroke.Color = power.Color
		powerSlot.stroke.Transparency = 0
		powerSlot.key.Visible = true
	end

	-- What's happening to your car (or a quick note, like "no one close enough to freeze").
	local text, color = statusText(car)
	if os.clock() < noticeUntil then
		text, color = noticeText, C.Bad
	end
	statusPill.Visible = text ~= nil and megaPanel.Visible
	statusPill.Text = text or ""
	statusPill.TextColor3 = color
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
	powerPanel.Visible = showDriving and not touchOnly
	statusPill.Visible = false
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
		updatePowers(car, now, pulse)

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
	-- A quick note from the server, like "No one close enough to freeze!".
	Remotes.PowerFx.OnClientEvent:Connect(function(kind: any, _position: any, _team: any, message: any)
		if kind == "fizzle" and type(message) == "string" then
			noticeText = message
			noticeUntil = os.clock() + 1.8
		end
	end)
end

return HUD
