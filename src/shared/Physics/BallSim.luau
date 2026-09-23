--!strict
-- Deterministic ball physics. The server runs it for real, and every client runs the same code to predict
-- where the ball is going between network updates. It never uses Roblox physics, so the math is identical
-- everywhere and can be tested offline.

local ArenaShape = require(script.Parent.Parent.Arena.ArenaShape)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

type Arena = ArenaShape.Arena

export type Config = {
	Radius: number,
	Gravity: number,
	AirDrag: number,
	Restitution: number,
	RestThreshold: number,
	SurfaceFriction: number,
	RollingFriction: number,
	MaxSpeed: number,
	FixedStep: number,
}

export type BallState = {
	position: Vector3,
	velocity: Vector3,
}

local BallSim = {}

function BallSim.newState(position: Vector3, velocity: Vector3?): BallState
	return { position = position, velocity = velocity or Vector3.zero }
end

function BallSim.copy(state: BallState): BallState
	return { position = state.position, velocity = state.velocity }
end

-- Advances `state` in place by dt seconds. Returns the normal of the surface it touched (if any).
function BallSim.step(arena: Arena, config: Config, state: BallState, dt: number): Vector3?
	local position = state.position
	local velocity = state.velocity

	velocity += Vector3.new(0, -config.Gravity * dt, 0)
	velocity *= math.max(0, 1 - config.AirDrag * dt)

	-- Split fast movement into small moves so the ball never skips through a surface.
	local maxMove = config.Radius * 0.5
	local substeps = math.clamp(math.ceil(velocity.Magnitude * dt / maxMove), 1, 16)
	local h = dt / substeps
	local touched: Vector3? = nil

	for _ = 1, substeps do
		position += velocity * h
		for _ = 1, 4 do
			local normal, depth = arena:deepestContact(position, config.Radius)
			if not normal then
				break
			end
			position += normal * depth
			touched = normal
			local normalSpeed = velocity:Dot(normal)
			if normalSpeed < 0 then
				local tangent = velocity - normal * normalSpeed
				local bounceSpeed = -normalSpeed * config.Restitution
				if -normalSpeed < config.RestThreshold then
					bounceSpeed = 0
				end
				local tangentSpeed = tangent.Magnitude
				if tangentSpeed > 1e-4 then
					local reduction
					if bounceSpeed > 0 then
						-- A real bounce grips the surface: the harder the impact, the more sliding speed it eats.
						reduction = config.SurfaceFriction * (bounceSpeed - normalSpeed)
					else
						-- Rolling along a surface only has a little rolling resistance.
						reduction = config.RollingFriction * h
					end
					reduction = math.min(tangentSpeed, reduction)
					tangent *= (tangentSpeed - reduction) / tangentSpeed
				end
				velocity = tangent + normal * bounceSpeed
			end
		end
	end

	velocity = MathUtil.clampMagnitude(velocity, config.MaxSpeed)
	state.position = position
	state.velocity = velocity
	return touched
end

-- Runs the simulation forward for `duration` seconds in fixed steps, calling `visit(state, elapsed)` after each
-- step. Stops early if `visit` returns true. Works on a copy; the original state is untouched.
function BallSim.simulate(
	arena: Arena,
	config: Config,
	state: BallState,
	duration: number,
	visit: ((BallState, number) -> boolean?)?
): BallState
	local s = BallSim.copy(state)
	local step = config.FixedStep
	local elapsed = 0
	while elapsed < duration - 1e-9 do
		local dt = math.min(step, duration - elapsed)
		BallSim.step(arena, config, s, dt)
		elapsed += dt
		if visit and visit(s, elapsed) then
			break
		end
	end
	return s
end

-- If the ball keeps going as it is, does it end up in a goal within `lookahead` seconds?
-- Returns the goal side (1 = +Z goal, -1 = -Z goal) and how long it takes.
function BallSim.predictGoal(arena: Arena, config: Config, state: BallState, lookahead: number): (number?, number?)
	local side: number? = nil
	local when: number? = nil
	BallSim.simulate(arena, config, state, lookahead, function(s, elapsed)
		local goal = arena:goalSide(s.position, config.Radius)
		if goal then
			side = goal
			when = elapsed
			return true
		end
		return false
	end)
	return side, when
end

-- Where the ball will be after `duration` seconds.
function BallSim.predictPosition(arena: Arena, config: Config, state: BallState, duration: number): Vector3
	if duration <= 0 then
		return state.position
	end
	return BallSim.simulate(arena, config, state, duration).position
end

return BallSim
