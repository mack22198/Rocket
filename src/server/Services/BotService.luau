--!strict
-- Drives the bot cars on the server. Bots "think" a dozen times a second (BotBrain) and drive every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallSim = require(Shared.Physics.BallSim)
local BotBrain = require(Shared.Bots.BotBrain)
local CarPhysics = require(Shared.Physics.CarPhysics)
local GameConfig = require(Shared.Config.GameConfig)

local Roster = require(script.Parent.Parent.Match.Roster)
local BallService = require(script.Parent.BallService)
local CarService = require(script.Parent.CarService)

type Participant = Roster.Participant

type BotMind = {
	memory: BotBrain.Memory,
	input: CarPhysics.Input,
	role: BotBrain.Role,
	aimOffset: Vector3,
	aimTimer: number,
}

local BotService = {}

local THINK_INTERVAL = 1 / GameConfig.Bots.ThinkRate
local PREDICTION_STEP = 0.05
local PREDICTION_SAMPLES = 32

local thinkTimer = 0
local lastAttacker: { [Roster.Team]: string? } = {}
local rng = Random.new()

local function mindOf(p: Participant): BotMind
	local brain = p.brain
	if brain and brain.memory then
		return brain :: any
	end
	local mind: BotMind = {
		memory = BotBrain.newMemory(),
		input = table.clone(CarPhysics.NoInput) :: CarPhysics.Input,
		role = "support",
		aimOffset = Vector3.zero,
		aimTimer = 0,
	}
	p.brain = mind :: any
	return mind
end

-- One shared forecast of the ball's path per think tick, so every bot can ask "where will it be in t seconds".
local function forecast(): (number) -> Vector3
	local arena = BallService.arena()
	local state = BallService.getState()
	local samples = { state.position }
	local halfStep = GameConfig.Ball.FixedStep / 2
	BallSim.simulate(arena, GameConfig.Ball, state, PREDICTION_STEP * PREDICTION_SAMPLES, function(s, elapsed)
		local index = math.floor(elapsed / PREDICTION_STEP + 0.5)
		if index == #samples and math.abs(elapsed - index * PREDICTION_STEP) < halfStep then
			samples[index + 1] = s.position
		end
		return false
	end)
	return function(seconds: number): Vector3
		local f = math.clamp(seconds / PREDICTION_STEP, 0, #samples - 1)
		local i = math.floor(f)
		local a = samples[i + 1]
		local b = samples[math.min(i + 2, #samples)] or a
		return a:Lerp(b, f - i)
	end
end

local function think()
	local arena = BallService.arena()
	local ball = BallService.getState()
	local predict = forecast()
	local skill = GameConfig.Bots.Skill

	for _, team: Roster.Team in { "Blue", "Orange" } :: { Roster.Team } do
		local members: { BotBrain.Member } = {}
		for _, p in Roster.onTeam(team) do
			if p.chassis then
				table.insert(members, { key = p.key, position = p.chassis.Position })
			end
		end
		local defendsSide = GameConfig.Teams[team].DefendsSide
		local roles = BotBrain.assignRoles(members, ball.position, defendsSide, arena.halfLength, lastAttacker[team])
		for key, role in roles do
			if role == "attack" then
				lastAttacker[team] = key
			end
		end

		for _, p in Roster.onTeam(team) do
			local chassis = p.chassis
			if not p.isBot or not chassis or not p.driver then
				continue
			end
			local mind = mindOf(p)
			mind.role = roles[p.key] or "support"
			mind.aimTimer -= THINK_INTERVAL
			if mind.aimTimer <= 0 then
				mind.aimTimer = 2
				local wobble = (1 - skill) * 6
				mind.aimOffset = Vector3.new(rng:NextNumber(-wobble, wobble), 0, rng:NextNumber(-wobble, wobble))
			end
			local input, wantsMega = BotBrain.decide({
				carCFrame = chassis.CFrame,
				carVelocity = chassis.AssemblyLinearVelocity,
				grounded = p.driver:isGrounded(),
				boost = p.boost,
				megaReady = p.mega >= GameConfig.Mega.Max and not p.megaArmed,
				ballPosition = ball.position,
				ballVelocity = ball.velocity,
				predict = predict,
				defendsSide = defendsSide,
				role = mind.role,
				skill = skill,
				arena = arena,
				aimOffset = mind.aimOffset,
			}, mind.memory, THINK_INTERVAL)
			mind.input = input
			if wantsMega then
				CarService.activateMega(p)
			end
		end
	end
end

-- Runs before physics each frame. `active` is false while bots should sit still (e.g. goal celebrations).
function BotService.update(dt: number, active: boolean)
	if active then
		thinkTimer += dt
		if thinkTimer >= THINK_INTERVAL then
			thinkTimer = 0
			think()
		end
	end
	for _, p in Roster.all() do
		local driver = p.driver
		if p.isBot and driver then
			local mind = mindOf(p)
			local input = if active then mind.input else CarPhysics.NoInput
			local result = driver:step(dt, input, p.boost > 0)
			p.boosting = result ~= nil and result.boosting
		end
	end
end

function BotService.reset()
	thinkTimer = 0
	table.clear(lastAttacker)
	for _, p in Roster.all() do
		if p.isBot then
			p.brain = nil
		end
	end
end

return BotService
