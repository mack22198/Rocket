--!strict
-- Tips for your first few matches: one short hint at a time, near the bottom of the screen, when it's useful
-- ("Your Cheese Flood is ready! Press E!") - and each one only until you've done what it says. The buttons it
-- names are the ones you're using: keyboard, gamepad or touch.

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

type Keys = { jump: string, ult: string }

-- What the coach looks at.
type Situation = {
	sinceKickoff: number,
	ballHigh: boolean,
	ultReady: boolean,
	ultName: string,
	orbNear: boolean,
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
			return "Drive into the ball to knock it toward the other goal!"
		end,
	},
	{
		id = "ult",
		when = function(s)
			return s.ultReady
		end,
		text = function(s, keys)
			return `Your {s.ultName} is ready! Press {keys.ult} to use it!`
		end,
	},
	{
		id = "jump",
		when = function(s)
			return s.ballHigh
		end,
		text = function(_, keys)
			return `Ball in the air? Press {keys.jump} to jump, then again to flip into it!`
		end,
	},
	{
		id = "orb",
		when = function(s)
			return s.orbNear and not s.ultReady
		end,
		text = function()
			return "Grab the glowing orb to charge up your ultimate!"
		end,
	},
	{
		id = "charge",
		when = function(s)
			return s.sinceKickoff > 15 and not s.ultReady
		end,
		text = function()
			return "Hitting the ball charges up your ultimate!"
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
local ORB_NEAR = 90 -- the orb hint shows when it's this close

local function keys(): Keys
	if InputController.isTouch() then
		return { jump = "JUMP", ult = "ULT" }
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return { jump = "A", ult = "X" }
	end
	return { jump = "SPACE", ult = "E" }
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
	pill.BackgroundTransparency = 0
	pill.Position = UDim2.fromScale(0.5, 0.76)
	TweenService:Create(pill, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.72),
	}):Play()
end

-- Is the charge orb out, and close to `position`?
local function orbNear(position: Vector3): boolean
	local match = workspace:FindFirstChild(MatchState.Folders.Match)
	local orbFolder = if match then match:FindFirstChild(MatchState.Folders.Orbs) else nil
	if not orbFolder then
		return false
	end
	for _, orb in orbFolder:GetChildren() do
		local home = orb:GetAttribute("Home")
		if typeof(home) == "Vector3" and (home - position).Magnitude < ORB_NEAR then
			return true
		end
	end
	return false
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
	local ball = BallView.getPosition()
	local carId = car:GetAttribute(A.CarId)
	local _, ultReady = CarController.ultCharge()
	local situation: Situation = {
		sinceKickoff = os.clock() - kickoffAt,
		ballHigh = BallView.isVisible()
			and ball.Y > BallView.radius() + 5
			and Vector3.new(ball.X - chassis.Position.X, 0, ball.Z - chassis.Position.Z).Magnitude < 30,
		ultReady = ultReady,
		ultName = Powers.forCar(if type(carId) == "string" then carId else "").Name,
		orbNear = orbNear(chassis.Position),
	}

	-- Did what the hint says (or it's been up long enough)?
	local current = showing
	if current then
		local didIt = (current.id == "ult" and not ultReady) or (current.id == "orb" and not situation.orbNear)
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
		size = UDim2.fromOffset(640, 46),
		position = UDim2.fromScale(0.5, 0.72),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		font = Theme.Title,
		background = C.Card,
	})
	pill.Visible = false
	local stroke = pill:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end
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
