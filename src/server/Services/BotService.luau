--!strict
-- Drives the bot cars on the server. Bots "think" a dozen times a second (BotBrain) and drive every frame.
-- They use their items and car powers too (PowerService.botThink). Bots on a player's team play for them, and
-- bots against players adapt to the score (see BotBrain).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallSim = require(Shared.Physics.BallSim)
local BotBrain = require(Shared.Bots.BotBrain)
local CarPhysics = require(Shared.Physics.CarPhysics)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local MathUtil = require(Shared.Util.MathUtil)
local Powers = require(Shared.Config.Powers)

local Roster = require(script.Parent.Parent.Match.Roster)
local BallService = require(script.Parent.BallService)
local CarService = require(script.Parent.CarService)
local PowerService = require(script.Parent.PowerService)

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
local stateObject = MatchState.getObject()

local function score(team: Roster.Team): number
	local value =
		stateObject:GetAttribute(if team == "Blue" then MatchState.Attr.BlueScore else MatchState.Attr.OrangeScore)
	return if type(value) == "number" then value else 0
end

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
	local ballConfig = BallService.config()
	local halfStep = ballConfig.FixedStep / 2
	BallSim.simulate(arena, ballConfig, state, PREDICTION_STEP * PREDICTION_SAMPLES, function(s, elapsed)
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

-- What a bot can see when deciding on its item and power.
local function botView(
	p: Participant,
	chassis: BasePart,
	role: string,
	ball: Vector3,
	enemyGoal: Vector3
): Powers.BotView
	local cframe = chassis.CFrame
	local position = cframe.Position
	local look = MathUtil.safeUnit(MathUtil.flat(cframe.LookVector), Vector3.new(0, 0, -1))
	local toBall = MathUtil.flat(ball - position)
	local ballDirection = MathUtil.safeUnit(toBall, look)
	local goalDirection = MathUtil.safeUnit(MathUtil.flat(enemyGoal - ball), look)
	local nearest = math.huge
	local behind = false
	for _, other in Roster.all() do
		local otherChassis = other.chassis
		if other.team ~= p.team and otherChassis then
			local offset = otherChassis.CFrame.Position - position
			local distance = offset.Magnitude
			nearest = math.min(nearest, distance)
			if distance < 32 and MathUtil.flat(offset):Dot(look) < -distance * 0.5 then
				behind = true
			end
		end
	end
	return {
		role = role,
		ballDistance = toBall.Magnitude,
		ballHeight = ball.Y,
		ballInFront = look:Dot(ballDirection) > 0.7,
		shotLinedUp = ballDirection:Dot(goalDirection) > 0.6,
		nearestEnemy = nearest,
		enemyBehind = behind,
		heldFor = if p.item then workspace:GetServerTimeNow() - p.itemReadyAt else 0,
	}
end

local function think()
	local arena = BallService.arena()
	local ball = BallService.getState()
	local predict = forecast()

	-- Where the players are, and whether any of them is new.
	local players: { [Roster.Team]: number } = { Blue = 0, Orange = 0 }
	local rookie = false
	for _, p in Roster.all() do
		if not p.isBot then
			players[p.team] += 1
			rookie = rookie or p.experience < GameConfig.Bots.RookieMatches
		end
	end

	for _, team: Roster.Team in { "Blue", "Orange" } :: { Roster.Team } do
		local enemy: Roster.Team = if team == "Blue" then "Orange" else "Blue"
		local skill = GameConfig.Bots.Skill
		if players[team] == 0 and players[enemy] > 0 then
			skill = BotBrain.adaptiveSkill(skill, score(enemy) - score(team), rookie)
		end
		local defendsSide = GameConfig.Teams[team].DefendsSide
		local upfield = Vector3.new(0, 0, -defendsSide)
		local members: { BotBrain.Member } = {}
		local feed: Vector3? = nil
		for _, p in Roster.onTeam(team) do
			local chassis = p.chassis
			if chassis then
				local position = chassis.Position
				table.insert(members, { key = p.key, position = position, human = not p.isBot })
				-- The player furthest upfield is the one to pass to.
				if not p.isBot and (feed == nil or position:Dot(upfield) > (feed :: Vector3):Dot(upfield)) then
					feed = position
				end
			end
		end
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
				local wobble = (1 - skill) * 10
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
				ballRadius = BallService.config().Radius,
				predict = predict,
				defendsSide = defendsSide,
				role = mind.role,
				skill = skill,
				arena = arena,
				aimOffset = mind.aimOffset,
				feed = feed,
			}, mind.memory, THINK_INTERVAL)
			mind.input = input
			if wantsMega then
				CarService.activateMega(p)
			end
			local enemyGoal = Vector3.new(0, 0, -defendsSide * arena.halfLength)
			PowerService.botThink(p, botView(p, chassis, mind.role, ball.position, enemyGoal))
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
