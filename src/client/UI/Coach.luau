--!strict
-- Tips for your first few matches: one short hint at a time, near the bottom of the screen, when it's useful
-- ("Hold SHIFT to boost!" while you're cruising) - and each one only until you've done what it says. The
-- buttons it names are the ones you're using: keyboard, gamepad or touch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)

local BallView = require(script.Parent.Parent.Controllers.BallView)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local Coach = {}

local C = Theme.Colors
local A = MatchState.CarAttr
local Phases = MatchState.Phases
local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()

local ROOKIE_MATCHES = 3 -- the coach helps out until you've finished this many matches
local SHOW_FOR = 6 -- seconds a hint stays up (unless you do it first)
local GAP = 2.5 -- seconds between hints

type Keys = { boost: string, jump: string, item: string, power: string }

-- What the coach looks at.
type Situation = {
	sinceKickoff: number,
	speed: number,
	boost: number,
	ballHigh: boolean,
	item: string?,
	powerReady: boolean,
	power: string,
}

type Hint = {
	id: string,
	when: (s: Situation) -> boolean,
	text: (s: Situation, keys: Keys) -> string,
}

local HINTS: { Hint } = {
	{
		id = "ball",
		when = function(s)
			return s.sinceKickoff < 4
		end,
		text = function()
			return "🚗 Drive into the ball to knock it toward the other goal!"
		end,
	},
	{
		id = "boost",
		when = function(s)
			return s.sinceKickoff > 6 and s.boost > 30 and s.speed > 15 and s.speed < 70
		end,
		text = function(_, keys)
			return `🚀 Hold {keys.boost} to boost - it's super fast!`
		end,
	},
	{
		id = "jump",
		when = function(s)
			return s.ballHigh
		end,
		text = function(_, keys)
			return `⬆️ Ball in the air? Press {keys.jump} to jump - twice to flip into it!`
		end,
	},
	{
		id = "item",
		when = function(s)
			return s.item ~= nil
		end,
		text = function(s, keys)
			local def = Powers.item(s.item or "")
			local name = if def then `{def.Emoji} {def.Name}` else "an item"
			return `🎁 You got a {name}! Press {keys.item} to use it.`
		end,
	},
	{
		id = "power",
		when = function(s)
			return s.sinceKickoff > 20 and s.powerReady
		end,
		text = function(s, keys)
			return `⚡ Press {keys.power} for your car's power: {s.power}!`
		end,
	},
}

local gui: ScreenGui
local pill: TextLabel
local done: { [string]: boolean } = {}
local showing: Hint? = nil
local shownAt = 0
local hiddenAt = -math.huge
local kickoffAt = 0
local visible = true
local hadItem = false

local function keys(): Keys
	if InputController.isTouch() then
		return { boost = "BOOST", jump = "JUMP", item = "ITEM", power = "POWER" }
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return { boost = "B", jump = "A", item = "RB", power = "LB" }
	end
	return { boost = "SHIFT", jump = "SPACE", item = "R", power = "G" }
end

local function isRookie(): boolean
	local matches = PlayerDataClient.get().stats.matches
	return PlayerDataClient.isLoaded() and (type(matches) ~= "number" or matches < ROOKIE_MATCHES)
end

local function hide()
	if showing then
		done[showing.id] = true
		showing = nil
		hiddenAt = os.clock()
		TweenService:Create(pill, TweenInfo.new(0.25), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.3, function()
			if not showing then
				pill.Visible = false
			end
		end)
	end
end

local function show(hint: Hint, situation: Situation)
	showing = hint
	shownAt = os.clock()
	pill.Text = hint.text(situation, keys())
	pill.Visible = true
	pill.TextTransparency = 0
	pill.BackgroundTransparency = 0.15
	pill.Position = UDim2.fromScale(0.5, 0.76)
	TweenService:Create(pill, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.72),
	}):Play()
end

local function numberOf(car: Model, name: string): number
	local value = car:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function update()
	local car = CarController.getCar()
	local chassis = CarController.getChassis()
	local playing = MatchState.phase(stateObject) == Phases.Playing
	if not car or not chassis or not playing or not visible or not isRookie() then
		if showing then
			hide()
		end
		return
	end
	local now = workspace:GetServerTimeNow()
	local held = car:GetAttribute(A.Item)
	local itemReady = type(held) == "string" and held ~= "" and now >= numberOf(car, A.ItemReadyAt)
	local ball = BallView.getPosition()
	local carId = car:GetAttribute(A.CarId)
	local situation: Situation = {
		sinceKickoff = os.clock() - kickoffAt,
		speed = chassis.AssemblyLinearVelocity.Magnitude,
		boost = numberOf(car, A.Boost),
		ballHigh = BallView.isVisible()
			and ball.Y > BallView.radius() + 5
			and Vector3.new(ball.X - chassis.Position.X, 0, ball.Z - chassis.Position.Z).Magnitude < 30,
		item = if itemReady then held :: string else nil,
		powerReady = now >= numberOf(car, A.PowerReadyAt),
		power = Powers.forCar(if type(carId) == "string" then carId else "").Name,
	}

	-- Did what the hint says (or it's been up long enough)?
	local current = showing
	if current then
		local didIt = (current.id == "boost" and CarController.isBoosting())
			or (current.id == "item" and hadItem and not itemReady)
			or (current.id == "power" and not situation.powerReady)
		if didIt or os.clock() - shownAt > SHOW_FOR then
			hide()
		end
	elseif os.clock() - hiddenAt > GAP then
		for _, hint in HINTS do
			if not done[hint.id] and hint.when(situation) then
				show(hint, situation)
				break
			end
		end
	end
	hadItem = itemReady
end

-- Hidden while replays and the podium are on screen (the same as the HUD).
function Coach.setVisible(on: boolean)
	visible = on
	gui.Enabled = on
end

function Coach.start()
	gui = Theme.screen("TurboCoach", 6)
	pill = Theme.pill(gui, {
		name = "Hint",
		size = UDim2.fromOffset(640, 44),
		position = UDim2.fromScale(0.5, 0.72),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		font = Theme.Title,
		background = C.PanelDark,
		transparency = 0.15,
	})
	pill.Visible = false
	Theme.stroke(pill, C.Gold, 2).Transparency = 0.2
	Theme.scaled(pill)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	CarController.Jumped:Connect(function()
		if showing and showing.id == "jump" then
			hide()
		end
	end)
	-- Every kickoff restarts the clock the hints go by.
	stateObject:GetAttributeChangedSignal(MatchState.Attr.Phase):Connect(function()
		if MatchState.phase(stateObject) == Phases.Playing then
			kickoffAt = os.clock()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			update()
		end
	end)
end

return Coach
