--!strict
-- Match twists: a surprise rule for a whole match, shown when it starts ("🏀 GIANT BALL!"). Most matches get
-- one; each week one twist is "featured" and turns up more often; and on weekends there's a Twist Weekend
-- event - every match has a twist and pays extra Scrap.
--
-- A twist only changes numbers that the server and every client use in the same way (the ball's size, gravity
-- and bounce, the cars' grip and gravity...), so everyone sees the same match.

local Daily = require(script.Parent.Daily)
local GameConfig = require(script.Parent.GameConfig)

local Twists = {}

export type TwistDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Description: string,
	Weight: number, -- how often it's picked, compared with the others
	Ball: { [string]: number }?, -- changes to GameConfig.Ball
	Car: { [string]: number }?, -- changes to GameConfig.Car
	UnlimitedBoost: boolean?,
	MegaMultiplier: number?, -- the Mega meter fills this many times faster
	BoxRespawn: number?, -- item boxes come back after this many seconds
	Night: boolean?, -- the match is played at night (just the looks)
}

export type EventDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Description: string,
	ScrapMultiplier: number,
	AlwaysTwist: boolean,
}

Twists.Chance = 0.7 -- how many matches get a twist (outside events)
Twists.FeaturedBoost = 3 -- the featured twist is this many times as likely

Twists.List = {
	{
		Id = "giant",
		Name = "Giant Ball",
		Emoji = "🏀",
		Description = "The ball is HUGE - easy to hit, hard to stop!",
		Weight = 3,
		-- (Big, but it must still fit right inside the 24-stud-deep net to count as a goal.)
		Ball = { Radius = 11.5, Gravity = 55 },
	},
	{
		Id = "moon",
		Name = "Low Gravity",
		Emoji = "🌙",
		Description = "Everything floats. Go for big air hits!",
		Weight = 3,
		Ball = { Gravity = 32 },
		Car = { Gravity = 36 },
	},
	{
		Id = "bouncy",
		Name = "Bouncy Ball",
		Emoji = "🏐",
		Description = "The ball bounces like crazy!",
		Weight = 3,
		Ball = { Restitution = 0.92, RestThreshold = 2, SurfaceFriction = 0.1, RollingFriction = 1.5 },
	},
	{
		Id = "ice",
		Name = "Ice Rink",
		Emoji = "⛸️",
		Description = "Slippery! Your car slides all over the place.",
		Weight = 2,
		Car = { Grip = 2.2, Acceleration = 55, BrakeDeceleration = 60, CoastDeceleration = 6 },
		Ball = { RollingFriction = 1.2 },
	},
	{
		Id = "turbo",
		Name = "Turbo Mode",
		Emoji = "⚡",
		Description = "Boost never runs out!",
		Weight = 2,
		UnlimitedBoost = true,
	},
	{
		Id = "mega",
		Name = "Mega Madness",
		Emoji = "💥",
		Description = "Mega meters fill 3x faster and item boxes come back quickly.",
		Weight = 2,
		MegaMultiplier = 3,
		BoxRespawn = 4,
	},
	{
		Id = "night",
		Name = "Neon Night",
		Emoji = "🌃",
		Description = "A match under the stars. Everything glows!",
		Weight = 2,
		Night = true,
	},
} :: { TwistDef }

Twists.Weekend = {
	Id = "weekend",
	Name = "Twist Weekend",
	Emoji = "🎉",
	Description = "Every match has a twist, and you earn +50% Scrap!",
	ScrapMultiplier = 1.5,
	AlwaysTwist = true,
} :: EventDef

local byId: { [string]: TwistDef } = {}
for _, twist in Twists.List do
	byId[twist.Id] = twist
end

-- The twist with this id (nil for "no twist").
function Twists.get(id: string?): TwistDef?
	return if id then byId[id] else nil
end

-- 0 = Sunday ... 6 = Saturday (1 January 1970 was a Thursday).
function Twists.weekday(unixTime: number): number
	return (Daily.dayNumber(unixTime) + 4) % 7
end

-- The event running at `unixTime` (Twist Weekend on Saturdays and Sundays), or nil.
function Twists.event(unixTime: number): EventDef?
	local weekday = Twists.weekday(unixTime)
	if weekday == 0 or weekday == 6 then
		return Twists.Weekend
	end
	return nil
end

-- This week's featured twist (a new one every Sunday).
function Twists.featured(unixTime: number): TwistDef
	local week = (Daily.dayNumber(unixTime) + 4) // 7
	return Twists.List[week % #Twists.List + 1]
end

-- Picks a match's twist from two random numbers between 0 and 1 ("" = no twist).
function Twists.pick(unixTime: number, rollChance: number, rollWhich: number): string
	local event = Twists.event(unixTime)
	local always = event ~= nil and event.AlwaysTwist
	if not always and rollChance >= Twists.Chance then
		return ""
	end
	local featured = Twists.featured(unixTime)
	local function weight(twist: TwistDef): number
		return twist.Weight * (if twist == featured then Twists.FeaturedBoost else 1)
	end
	local total = 0
	for _, twist in Twists.List do
		total += weight(twist)
	end
	local target = math.clamp(rollWhich, 0, 0.999999) * total
	for _, twist in Twists.List do
		target -= weight(twist)
		if target < 0 then
			return twist.Id
		end
	end
	return Twists.List[#Twists.List].Id
end

local function withChanges<T>(base: T, changes: { [string]: number }?): T
	local copy = table.clone(base :: any)
	if changes then
		for key, value in changes do
			copy[key] = value
		end
	end
	return copy :: any
end

-- The ball's settings during a twist (the normal ones for "" or an unknown twist).
function Twists.ballConfig(id: string?): typeof(GameConfig.Ball)
	local twist = Twists.get(id)
	return withChanges(GameConfig.Ball, if twist then twist.Ball else nil)
end

-- The cars' settings during a twist.
function Twists.carConfig(id: string?): typeof(GameConfig.Car)
	local twist = Twists.get(id)
	return withChanges(GameConfig.Car, if twist then twist.Car else nil)
end

return Twists
