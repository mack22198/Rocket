--!strict
-- Cars already collide physically; this adds a knock-back that depends on each car's Weight and BumpPower,
-- so the Monster Truck really does bully the Tiny Kart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Util.MathUtil)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)
local StatsService = require(script.Parent.StatsService)

type Participant = Roster.Participant

local BumpService = {}

local cfg = GameConfig.Bump
local lastBump: { [string]: number } = {}

local function push(p: Participant, change: Vector3)
	if p.driver then
		p.driver:addVelocity(change)
	elseif p.player then
		Remotes.Bumped:FireClient(p.player, change)
	end
end

local function contactDistance(a: Participant, b: Participant): number
	local sizeA = a.def.Hitbox
	local sizeB = b.def.Hitbox
	-- Rough overlap test: average of each car's half-length and half-width, plus a little margin.
	return (sizeA.Z + sizeA.X) / 4 + (sizeB.Z + sizeB.X) / 4 + 0.6
end

function BumpService.update()
	local now = workspace:GetServerTimeNow()
	local list = Roster.all()
	for i = 1, #list do
		local a = list[i]
		local chassisA = a.chassis
		if not chassisA or chassisA.Anchored then
			continue
		end
		for j = i + 1, #list do
			local b = list[j]
			local chassisB = b.chassis
			if not chassisB or chassisB.Anchored then
				continue
			end
			local offset = chassisB.Position - chassisA.Position
			if offset.Magnitude > contactDistance(a, b) then
				continue
			end
			local key = if a.key < b.key then `{a.key}|{b.key}` else `{b.key}|{a.key}`
			if now - (lastBump[key] or -math.huge) < cfg.Cooldown then
				continue
			end
			local direction = MathUtil.safeUnit(offset, Vector3.xAxis) -- from a toward b
			local approachA = chassisA.AssemblyLinearVelocity:Dot(direction)
			local approachB = chassisB.AssemblyLinearVelocity:Dot(-direction)
			local attacker, victim, speed, towardVictim
			if approachA >= approachB then
				attacker, victim, speed, towardVictim = a, b, approachA, direction
			else
				attacker, victim, speed, towardVictim = b, a, approachB, -direction
			end
			if speed < cfg.MinSpeed then
				continue
			end
			lastBump[key] = now
			local power = attacker.def.Stats.BumpPower / victim.def.Stats.Weight
			local flat = MathUtil.safeUnit(MathUtil.flat(towardVictim), towardVictim)
			local teammates = attacker.team == victim.team
			local strength = if teammates then 0.4 else 1
			push(victim, (flat * (speed * cfg.Knockback * power) + Vector3.new(0, cfg.Pop, 0)) * strength)
			push(attacker, -flat * (speed * cfg.AttackerSlowdown / power) * strength)
			if not teammates and speed >= cfg.BigBumpSpeed then
				StatsService.announce("bump", "BUMP!", attacker.team, attacker.name)
			end
		end
	end
end

function BumpService.reset()
	table.clear(lastBump)
end

return BumpService
