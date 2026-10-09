--!strict
-- Demolitions! Smash into a car on the other team on a Nitro Rocket (see Demolition) and it goes POOF - a cloud of
-- smoke, stars and flying bits - then pops back in at its own goal a couple of seconds later. While it's gone
-- it's out of the game: it stays where it was, hidden on every screen, and can't touch the ball, grab anything,
-- use anything or be bumped (everything else already ignores a car that's anchored in place).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)
local StatsService = require(script.Parent.StatsService)

type Participant = Roster.Participant

local DemolitionService = {}

local A = MatchState.CarAttr
local wrecked: { [Participant]: boolean } = {}
local round = 0 -- goes up at every kickoff, so a respawn still waiting from before it is dropped
local respawnSpot: (p: Participant) -> CFrame = function(p)
	local chassis = p.chassis
	return if chassis then chassis.CFrame else CFrame.new()
end

-- `spot` says where a demolished car comes back (somewhere safe in front of its own goal).
function DemolitionService.init(spot: (p: Participant) -> CFrame)
	respawnSpot = spot
end

function DemolitionService.isDemolished(p: Participant): boolean
	return wrecked[p] == true
end

local function restore(p: Participant)
	wrecked[p] = nil
	local car, chassis = p.car, p.chassis
	if car then
		car:SetAttribute(A.Demolished, false)
	end
	if chassis then
		chassis.CanCollide = true
	end
end

function DemolitionService.demolish(attacker: Participant, victim: Participant)
	local car, chassis = victim.car, victim.chassis
	if not car or not chassis or wrecked[victim] then
		return
	end
	wrecked[victim] = true
	local position = chassis.Position
	chassis.Anchored = true
	chassis.CanCollide = false
	if victim.driver then
		victim.driver:reset()
	end
	-- Whatever they had going (Hot Sauce, a spin-out) is gone; their ultimate meter stays.
	table.clear(victim.effects)
	car:SetAttribute(A.Demolished, true)
	CarService.sync(victim)

	attacker.stats.demos += 1
	attacker.stats.points += GameConfig.Points.Demo
	Remotes.PowerFx:FireAllClients("demo", position, victim.team, car)
	StatsService.announce("demo", `{attacker.name} demolished {victim.name}!`, attacker.team, attacker.name)

	local myRound = round
	task.delay(GameConfig.Bump.DemoRespawn, function()
		if round ~= myRound or not wrecked[victim] or victim.car ~= car then
			return -- a kickoff already brought them back, or they've gone
		end
		local spot = respawnSpot(victim)
		CarService.freezeAt(victim, spot)
		restore(victim)
		CarService.sync(victim)
		CarService.release(victim)
		Remotes.PowerFx:FireAllClients("respawn", spot.Position, victim.team, car)
	end)
end

-- A participant is leaving the match (their seat is being handed to someone else).
function DemolitionService.forget(p: Participant)
	wrecked[p] = nil
end

-- Kickoffs and the end of the match bring everyone back (the kickoff puts them in their spots).
function DemolitionService.reset()
	round += 1
	for p in wrecked do
		restore(p)
	end
	table.clear(wrecked)
end

return DemolitionService
