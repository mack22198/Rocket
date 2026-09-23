--!strict
-- The one true ball. The server simulates it with BallSim at a fixed 60 steps per second and streams its
-- state to every client, which run the same simulation to fill in the gaps smoothly.
--
-- Touches:
--   * bots: detected here every step (the server drives them, so it knows exactly where they are)
--   * players: their own client spots the touch the moment it happens (so it feels instant), tells the
--     server what it saw, and the server checks the story (HitValidation) before rewinding the ball to that
--     moment, applying the hit and fast-forwarding back to now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)
local HitValidation = require(Shared.Match.HitValidation)
local MathUtil = require(Shared.Util.MathUtil)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)

type Participant = Roster.Participant

export type TouchInfo = {
	participant: Participant,
	time: number,
	before: BallSim.BallState,
	after: BallSim.BallState,
	carCFrame: CFrame,
	carVelocity: Vector3,
	mega: boolean,
	impactSpeed: number,
}

local BallService = {}

BallService.Touched = Signal.new() :: Signal.Signal<TouchInfo>
BallService.GoalScored = Signal.new() :: Signal.Signal<number, Vector3>

local cfg = GameConfig.Ball
local STEP = cfg.FixedStep
local HISTORY_SECONDS = 1
local MAX_STEPS_PER_FRAME = 8

type HistoryEntry = { t: number, position: Vector3, velocity: Vector3 }

local arena: ArenaShape.Arena
local state: BallSim.BallState = BallSim.newState(Vector3.new(0, cfg.Radius, 0))
local simTime = 0
local accumulator = 0
local live = false
local hidden = false
local goalFired = false
local history: { HistoryEntry } = {}
local snapshotTimer = 0
local lastTouchTeam = 0 -- 0 = nobody, 1 = Blue, 2 = Orange (colours the ball's trail)
local lastClaimAt: { [Player]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flags(snap: boolean): number
	local value = 0
	if snap then
		value += Remotes.BallFlags.Snap
	end
	if hidden then
		value += Remotes.BallFlags.Hidden
	end
	if not live then
		value += Remotes.BallFlags.Frozen
	end
	return value
end

local function broadcast(snap: boolean)
	Remotes.BallState:FireAllClients(simTime, state.position, state.velocity, flags(snap), lastTouchTeam)
	snapshotTimer = 0
end

local function record()
	table.insert(history, { t = simTime, position = state.position, velocity = state.velocity })
	local cutoff = simTime - HISTORY_SECONDS
	while #history > 1 and history[1].t < cutoff do
		table.remove(history, 1)
	end
end

-- The ball as the server had it at time t (within the last second), or nil if that's too long ago.
local function stateAt(t: number): BallSim.BallState?
	if #history == 0 or t < history[1].t then
		return nil
	end
	local entry = history[1]
	for i = #history, 1, -1 do
		if history[i].t <= t then
			entry = history[i]
			break
		end
	end
	local s = BallSim.newState(entry.position, entry.velocity)
	local gap = t - entry.t
	if gap > 1e-4 then
		BallSim.step(arena, cfg, s, math.min(gap, STEP))
	end
	return s
end

local function applyHit(
	p: Participant,
	atTime: number,
	carCFrame: CFrame,
	carVelocity: Vector3,
	before: BallSim.BallState
): HitModel.HitResult?
	local chassis = p.chassis
	if not chassis then
		return nil
	end
	local contact = HitModel.findContact(
		carCFrame,
		chassis.Size / 2,
		before.position,
		cfg.Radius + GameConfig.HitValidation.OverlapSlack
	)
	if not contact then
		return nil
	end
	local mega = p.megaArmed
	local result = HitModel.resolve(
		GameConfig.Hit,
		carCFrame,
		carVelocity,
		before.position,
		before.velocity,
		cfg.Radius,
		contact,
		mega,
		cfg.MaxSpeed
	)

	-- The hit happened at `atTime`; replay the ball from then until now.
	local after = BallSim.newState(result.ballPosition, result.ballVelocity)
	local replay = math.clamp(simTime - atTime, 0, HISTORY_SECONDS)
	local current = if replay > 1e-4 then BallSim.simulate(arena, cfg, after, replay) else BallSim.copy(after)
	state.position = current.position
	state.velocity = current.velocity

	p.lastHitAt = atTime
	lastTouchTeam = if p.team == "Blue" then 1 else 2
	if mega then
		CarService.consumeMega(p)
	end
	BallService.Touched:Fire({
		participant = p,
		time = atTime,
		before = before,
		after = after,
		carCFrame = carCFrame,
		carVelocity = carVelocity,
		mega = mega,
		impactSpeed = result.impactSpeed,
	})
	broadcast(false)
	return result
end

local function detectBotTouches()
	for _, p in Roster.all() do
		local chassis = p.chassis
		if p.isBot and chassis and not chassis.Anchored and simTime - p.lastHitAt >= GameConfig.Hit.Cooldown then
			local contact = HitModel.findContact(chassis.CFrame, chassis.Size / 2, state.position, cfg.Radius)
			if contact then
				local result = applyHit(p, simTime, chassis.CFrame, chassis.AssemblyLinearVelocity, BallSim.copy(state))
				if result and p.driver then
					p.driver:addVelocity(result.carVelocityChange)
				end
			end
		end
	end
end

local function escaped(position: Vector3): boolean
	if not MathUtil.isFiniteVector(position) then
		return true
	end
	return math.abs(position.X) > arena.halfWidth + 10
		or math.abs(position.Z) > arena.halfLength + arena.goalDepth + 10
		or position.Y < -10
		or position.Y > arena.height + 10
end

local function fixedStep()
	BallSim.step(arena, cfg, state, STEP)
	simTime += STEP
	if escaped(state.position) then
		warn("[Ball] The ball escaped the arena; dropping it back in the middle.")
		state.position = Vector3.new(0, 40, 0)
		state.velocity = Vector3.zero
		broadcast(true)
	end
	detectBotTouches()
	record()
	if not goalFired then
		local side = arena:goalSide(state.position, cfg.Radius)
		if side then
			goalFired = true
			live = false
			hidden = true
			broadcast(false)
			BallService.GoalScored:Fire(side, state.position)
		end
	end
end

local function onClaim(
	player: Player,
	id: unknown,
	t: unknown,
	carCFrame: unknown,
	carVelocity: unknown,
	ballPosition: unknown,
	ballVelocity: unknown
)
	if type(id) ~= "number" then
		return
	end
	-- Ignore floods: a real car can't touch the ball more than a few times a second.
	local clock = os.clock()
	if clock - (lastClaimAt[player] or 0) < 0.03 then
		Remotes.BallHitResult:FireClient(player, id, false, simTime)
		return
	end
	lastClaimAt[player] = clock
	local accepted = false
	local p = Roster.byPlayer(player)
	local chassis = p and p.chassis
	if
		p
		and chassis
		and live
		and not chassis.Anchored
		and type(t) == "number"
		and typeof(carCFrame) == "CFrame"
		and typeof(carVelocity) == "Vector3"
		and typeof(ballPosition) == "Vector3"
		and typeof(ballVelocity) == "Vector3"
	then
		local past = stateAt(math.min(t, simTime))
		if past then
			local ok, reason = HitValidation.check(GameConfig.HitValidation, {
				time = t,
				carCFrame = carCFrame,
				carVelocity = carVelocity,
				ballPosition = ballPosition,
				ballVelocity = ballVelocity,
			}, {
				now = serverNow(),
				carPosition = chassis.Position,
				carVelocity = chassis.AssemblyLinearVelocity,
				ballPositionAtClaim = past.position,
				ballVelocityAtClaim = past.velocity,
				lastAcceptedHit = p.lastHitAt,
				carHalfSize = chassis.Size / 2,
				ballRadius = cfg.Radius,
				maxCarSpeed = GameConfig.Car.MaxBoostedSpeed,
			})
			if ok then
				accepted = applyHit(
					p,
					math.min(t, simTime),
					carCFrame,
					carVelocity,
					BallSim.newState(ballPosition, ballVelocity)
				) ~= nil
			elseif GameConfig.Debug.LogHitRejections then
				warn(`[Ball] Rejected hit from {player.Name}: {reason}`)
			end
		end
	end
	Remotes.BallHitResult:FireClient(player, id, accepted, simTime)
end

function BallService.init(shape: ArenaShape.Arena)
	arena = shape
	simTime = serverNow()
	record()
	Remotes.BallHit.OnServerEvent:Connect(onClaim)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastClaimAt[player] = nil
	end)
end

-- Runs every server frame (Heartbeat).
function BallService.update(dt: number)
	if live then
		accumulator += dt
		local steps = 0
		while accumulator >= STEP and live do
			accumulator -= STEP
			fixedStep()
			steps += 1
			if steps >= MAX_STEPS_PER_FRAME then
				accumulator = 0
				break
			end
		end
		-- Stay in step with real time after a server hiccup.
		local drift = serverNow() - simTime
		if drift > 0.25 or drift < -0.25 then
			simTime = serverNow()
		end
	end
	snapshotTimer += dt
	local interval = if live then 1 / cfg.SnapshotRate else 0.25
	if snapshotTimer >= interval then
		broadcast(false)
	end
end

-- Puts the ball at `position`, still and frozen (kickoff).
function BallService.reset(position: Vector3)
	state = BallSim.newState(position)
	simTime = serverNow()
	accumulator = 0
	live = false
	hidden = false
	goalFired = false
	lastTouchTeam = 0
	table.clear(history)
	record()
	broadcast(true)
end

function BallService.setLive(on: boolean)
	if on and not live then
		simTime = serverNow()
		accumulator = 0
		table.clear(history)
		record()
	end
	live = on
	broadcast(false)
end

function BallService.hide()
	hidden = true
	live = false
	broadcast(false)
end

function BallService.isLive(): boolean
	return live
end

function BallService.getState(): BallSim.BallState
	return BallSim.copy(state)
end

function BallService.isOnGround(): boolean
	return state.position.Y <= cfg.Radius + 0.75
end

function BallService.arena(): ArenaShape.Arena
	return arena
end

return BallService
