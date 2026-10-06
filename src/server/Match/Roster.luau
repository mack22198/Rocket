--!strict
-- Everyone taking part in the current match (players and bots) and their per-match state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarDriver = require(Shared.Cars.CarDriver)
local Rewards = require(Shared.Config.Rewards)

export type Team = "Blue" | "Orange"

export type Participant = {
	key: string, -- "player:<userId>" or "bot:<n>"
	player: Player?, -- nil for bots
	isBot: boolean,
	name: string,
	team: Team,
	slot: number, -- kickoff position index within the team
	def: CarCatalog.CarDef,
	stage: number, -- which evolution look the car shows
	car: Model?,
	chassis: BasePart?,
	driver: CarDriver.CarDriver?, -- server-side driver (bots only)
	brain: { [string]: any }?, -- bot memory
	stats: Rewards.MatchStats,
	boost: number,
	boosting: boolean,
	mega: number,
	megaArmed: boolean,
	megaArmedUntil: number,
	lastHitAt: number, -- server time of the last accepted ball touch
	item: string?, -- the item from an item box they're holding (see Powers)
	itemReadyAt: number, -- server time the item stops spinning and can be used
	powerReadyAt: number, -- server time the car's power has recharged
	effects: { [string]: number }, -- effect name -> server time it wears off ("shield", "ghost", "rocket", ...)
	topper: string?, -- the hat on the car (see Cosmetics)
	horn: string,
	celebration: string, -- what goes off when they score
	experience: number, -- matches a player had finished before this one (bots: 0)
	level: number, -- player level (bots get a made-up one)
	title: string, -- the title shown under their name, e.g. "🧤 Brick Wall"
}

local Roster = {}

local participants: { Participant } = {}

function Roster.all(): { Participant }
	return participants
end

function Roster.add(participant: Participant)
	table.insert(participants, participant)
end

function Roster.remove(participant: Participant)
	local index = table.find(participants, participant)
	if index then
		table.remove(participants, index)
	end
end

function Roster.clear()
	table.clear(participants)
end

function Roster.byPlayer(player: Player): Participant?
	for _, p in participants do
		if p.player == player then
			return p
		end
	end
	return nil
end

function Roster.onTeam(team: Team): { Participant }
	local list = {}
	for _, p in participants do
		if p.team == team then
			table.insert(list, p)
		end
	end
	return list
end

function Roster.humans(): { Participant }
	local list = {}
	for _, p in participants do
		if not p.isBot then
			table.insert(list, p)
		end
	end
	return list
end

function Roster.bots(): { Participant }
	local list = {}
	for _, p in participants do
		if p.isBot then
			table.insert(list, p)
		end
	end
	return list
end

function Roster.otherTeam(team: Team): Team
	return if team == "Blue" then "Orange" else "Blue"
end

function Roster.newParticipant(fields: {
	key: string,
	player: Player?,
	name: string,
	team: Team,
	slot: number,
	def: CarCatalog.CarDef,
	stage: number,
}): Participant
	return {
		key = fields.key,
		player = fields.player,
		isBot = fields.player == nil,
		name = fields.name,
		team = fields.team,
		slot = fields.slot,
		def = fields.def,
		stage = fields.stage,
		car = nil,
		chassis = nil,
		driver = nil,
		brain = nil,
		stats = Rewards.emptyStats(),
		boost = 0,
		boosting = false,
		mega = 0,
		megaArmed = false,
		megaArmedUntil = 0,
		lastHitAt = -math.huge,
		item = nil,
		itemReadyAt = 0,
		powerReadyAt = 0,
		effects = {},
		topper = nil,
		horn = "beep",
		celebration = "fireworks",
		experience = 0,
		level = 1,
		title = "",
	}
end

-- Is an effect (like "shield") active on this participant at server time `now`?
function Roster.hasEffect(p: Participant, name: string, now: number): boolean
	local untilTime = p.effects[name]
	return untilTime ~= nil and untilTime > now
end

return Roster
