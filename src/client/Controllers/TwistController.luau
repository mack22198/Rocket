--!strict
-- Match twists on this screen (see Twists): the ball and your own car follow the twist's rules - the same
-- numbers the server uses - and a Neon Night match is played under an evening sky with everything glowing.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarDriver = require(Shared.Cars.CarDriver)
local MatchState = require(Shared.Match.MatchState)
local Signal = require(Shared.Util.Signal)
local Twists = require(Shared.Config.Twists)

local BallView = require(script.Parent.BallView)

local TwistController = {}

-- Fired with the new twist's id ("" = none) when it changes.
TwistController.Changed = Signal.new() :: Signal.Signal<string>

local rgb = Color3.fromRGB
local stateObject = MatchState.getObject()

local NIGHT_LIGHTING = {
	ClockTime = 20.7,
	Brightness = 1.6,
	Ambient = rgb(72, 62, 118),
	OutdoorAmbient = rgb(96, 86, 150),
	ExposureCompensation = 0.2,
}
local NIGHT_EFFECTS: { [string]: { [string]: any } } = {
	BloomEffect = { Intensity = 1.3, Threshold = 0.85, Size = 40 },
	ColorCorrectionEffect = { TintColor = rgb(218, 208, 255), Saturation = 0.32, Contrast = 0.2 },
	Atmosphere = { Color = rgb(70, 58, 120), Decay = rgb(40, 32, 90), Density = 0.34, Glare = 0.05, Haze = 1 },
	SunRaysEffect = { Intensity = 0 },
}

local current = ""
local inMatch = false
local nightOn = false
local saved: { [Instance]: { [string]: any } } = {}

local function override(object: Instance, values: { [string]: any })
	local store = saved[object] or {}
	for key, value in values do
		local ok, before = pcall(function()
			return (object :: any)[key]
		end)
		if ok then
			if store[key] == nil then
				store[key] = before
			end
			pcall(function()
				(object :: any)[key] = value
			end)
		end
	end
	saved[object] = store
end

local function restore()
	for object, store in saved do
		for key, value in store do
			pcall(function()
				(object :: any)[key] = value
			end)
		end
	end
	table.clear(saved)
end

local function setNight(on: boolean)
	if on == nightOn then
		return
	end
	nightOn = on
	if on then
		override(Lighting, NIGHT_LIGHTING)
		for className, values in NIGHT_EFFECTS do
			local effect = Lighting:FindFirstChildOfClass(className)
			if effect then
				override(effect, values)
			end
		end
	else
		restore()
	end
end

local function refresh()
	local value = stateObject:GetAttribute(MatchState.Attr.Twist)
	local id = if type(value) == "string" then value else ""
	if id ~= current then
		current = id
		CarDriver.setConfig(Twists.carConfig(id))
		BallView.setConfig(Twists.ballConfig(id))
		TwistController.Changed:Fire(id)
	end
	local twist = Twists.get(current)
	setNight(inMatch and twist ~= nil and twist.Night == true)
end

-- This match's twist ("" = none).
function TwistController.current(): string
	return current
end

-- The night sky only shows in the stadium. GameFlow calls this around switching between the menus (which have
-- their own lighting) and the match.
function TwistController.setInMatch(on: boolean)
	inMatch = on
	refresh()
end

function TwistController.start()
	stateObject:GetAttributeChangedSignal(MatchState.Attr.Twist):Connect(refresh)
	refresh()
end

return TwistController
