--!strict
-- Arcade car handling, written as a pure function so it can be tested offline.
-- CarDriver feeds it raycast results and applies the returned velocities to the real car part.
--
-- Controls:  throttle (-1..1)  steer (-1..1)  pitch (-1..1, air only; defaults to throttle)  roll (-1..1)
--            boost  jump
-- On the ground: drive, steer, jump (pushes off whatever surface you're on, even walls).
-- In the air:    pitch tips the nose, steer = yaw, roll = barrel roll. Jump again within 1.5s to double jump,
--                or jump while holding a direction to dodge/flip into the ball.

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type Config = {
	Gravity: number,
	RideHeight: number,
	SuspensionReach: number,
	SpringStrength: number,
	SpringDamping: number,
	AlignStrength: number,
	WallStick: number,
	MaxSpeed: number,
	MaxReverseSpeed: number,
	Acceleration: number,
	BrakeDeceleration: number,
	CoastDeceleration: number,
	Grip: number,
	TurnRate: number,
	TurnSpeedRamp: number,
	HighSpeedTurnFactor: number,
	SteerResponse: number,
	BoostAcceleration: number,
	MaxBoostedSpeed: number,
	JumpSpeed: number,
	JumpSuspensionPause: number,
	DoubleJumpSpeed: number,
	DodgeSpeed: number,
	DodgeSpinRate: number,
	DodgeDuration: number,
	SecondJumpWindow: number,
	AirPitchRate: number,
	AirYawRate: number,
	AirRollRate: number,
	AirControlResponse: number,
	AirSpinDamping: number,
	MaxAngularSpeed: number,
	AutoRightDelay: number,
}

export type Stats = {
	Speed: number,
	Acceleration: number,
	Handling: number,
	AirControl: number,
	Jump: number,
}

export type Input = {
	throttle: number,
	steer: number,
	pitch: number?, -- air pitch; when nil, throttle is used (keyboard W/S does both)
	roll: number,
	boost: boolean,
	jump: boolean, -- is the jump button held right now
}

export type Ground = {
	contacts: number, -- how many wheels touch a surface
	normal: Vector3, -- average surface normal under the touching wheels
	gap: number, -- average distance past ride height (negative = suspension squashed)
}

export type State = {
	jumpHeld: boolean,
	grounded: boolean,
	canSecondJump: boolean,
	sinceJump: number,
	dodgeTimer: number,
	suspensionPause: number,
	stuckTimer: number,
}

export type StepParams = {
	config: Config,
	stats: Stats,
	state: State,
	input: Input,
	cframe: CFrame,
	velocity: Vector3,
	angularVelocity: Vector3,
	ground: Ground,
	dt: number,
	worldGravity: number, -- the gravity the physics engine applies (workspace.Gravity)
	hasBoost: boolean,
}

export type StepResult = {
	velocity: Vector3,
	angularVelocity: Vector3,
	teleport: CFrame?, -- set when the car hops back onto its wheels
	grounded: boolean,
	jumped: boolean,
	dodged: boolean,
	boosting: boolean,
}

local CarPhysics = {}

CarPhysics.NoInput = table.freeze({ throttle = 0, steer = 0, roll = 0, boost = false, jump = false }) :: Input

-- Wheel rays start this far above the bottom of the chassis, so a slightly sunken wheel still sees the ground.
CarPhysics.RayLift = 0.3

-- Where the four wheel rays start, relative to the centre of a car hitbox of the given size.
function CarPhysics.wheelMounts(hitbox: Vector3): { Vector3 }
	local x = hitbox.X / 2 - 0.5
	local y = -hitbox.Y / 2 + CarPhysics.RayLift
	local z = hitbox.Z / 2 - 1.1
	return { Vector3.new(x, y, -z), Vector3.new(-x, y, -z), Vector3.new(x, y, z), Vector3.new(-x, y, z) }
end

function CarPhysics.rayLength(config: Config): number
	return config.RideHeight + config.SuspensionReach + CarPhysics.RayLift
end

export type WheelHit = { distance: number, normal: Vector3 }

-- Turns the wheel ray hits into the ground summary that step() needs.
function CarPhysics.groundFromHits(config: Config, hits: { WheelHit }): Ground
	if #hits == 0 then
		return { contacts = 0, normal = Vector3.yAxis, gap = 0 }
	end
	local gap = 0
	local normal = Vector3.zero
	for _, hit in hits do
		gap += (hit.distance - CarPhysics.RayLift) - config.RideHeight
		normal += hit.normal
	end
	return { contacts = #hits, normal = MathUtil.safeUnit(normal, Vector3.yAxis), gap = gap / #hits }
end

function CarPhysics.newState(): State
	return {
		jumpHeld = false,
		grounded = false,
		canSecondJump = false,
		sinceJump = math.huge,
		dodgeTimer = 0,
		suspensionPause = 0,
		stuckTimer = 0,
	}
end

local function pitchOf(input: Input): number
	return if input.pitch ~= nil then input.pitch else input.throttle
end

local function hasAirInput(input: Input): boolean
	return math.abs(pitchOf(input)) > 0.05 or math.abs(input.steer) > 0.05 or math.abs(input.roll) > 0.05
end

function CarPhysics.step(p: StepParams): StepResult
	local config, stats, state, input = p.config, p.stats, p.state, p.input
	local dt = p.dt
	local cframe = p.cframe
	local velocity = p.velocity
	local angular = p.angularVelocity
	local up, look, right = cframe.UpVector, cframe.LookVector, cframe.RightVector

	local result: StepResult = {
		velocity = velocity,
		angularVelocity = angular,
		teleport = nil,
		grounded = false,
		jumped = false,
		dodged = false,
		boosting = false,
	}

	state.suspensionPause = math.max(0, state.suspensionPause - dt)
	local jumpPressed = input.jump and not state.jumpHeld
	state.jumpHeld = input.jump

	local grounded = p.ground.contacts >= 2 and state.suspensionPause <= 0
	if state.grounded and not grounded and state.suspensionPause <= 0 then
		-- Rolled off an edge without jumping: still allowed one jump/flip in the air.
		state.canSecondJump = true
		state.sinceJump = 0
	end
	state.grounded = grounded
	result.grounded = grounded

	-- The engine pulls with workspace gravity; top up (or cancel) the difference to get our own gravity.
	velocity += Vector3.yAxis * ((p.worldGravity - config.Gravity) * dt)

	if grounded then
		local normal = p.ground.normal
		state.canSecondJump = false
		state.dodgeTimer = 0

		-- Suspension: a damped spring along the surface normal. It may pull down, but never harder than gravity.
		-- (Damping uses the incoming velocity, before this frame's gravity correction was added.)
		local normalSpeed = p.velocity:Dot(normal)
		local springAccel = config.SpringStrength * -p.ground.gap - config.SpringDamping * normalSpeed
		springAccel = math.max(springAccel, -config.Gravity)
		velocity += normal * (springAccel * dt)
		if normal.Y < 0.9 then
			velocity -= normal * (config.WallStick * dt) -- hug ramps and walls
		end

		-- Driving directions follow the surface.
		local forward = MathUtil.safeUnit(look - normal * look:Dot(normal), look)
		local side = forward:Cross(normal)
		local forwardSpeed = velocity:Dot(forward)

		-- Throttle, brakes and coasting.
		local maxSpeed = config.MaxSpeed * stats.Speed
		local accel = 0
		local braking = false
		if input.throttle > 0.05 then
			if forwardSpeed < -1 then
				accel, braking = config.BrakeDeceleration, true
			else
				local falloff = math.clamp((maxSpeed - forwardSpeed) / (maxSpeed * 0.15), 0, 1)
				accel = config.Acceleration * stats.Acceleration * input.throttle * falloff
			end
		elseif input.throttle < -0.05 then
			if forwardSpeed > 1 then
				accel, braking = -config.BrakeDeceleration, true
			else
				local reverseMax = config.MaxReverseSpeed
				local falloff = math.clamp((reverseMax + forwardSpeed) / (reverseMax * 0.2), 0, 1)
				accel = config.Acceleration * stats.Acceleration * input.throttle * falloff
			end
		elseif math.abs(forwardSpeed) > 1e-3 then
			accel, braking = -math.sign(forwardSpeed) * config.CoastDeceleration, true
		end
		if braking and math.abs(accel * dt) > math.abs(forwardSpeed) then
			accel = -forwardSpeed / dt -- stop exactly instead of rolling backwards
		end
		velocity += forward * (accel * dt)

		-- Tyre grip: bleed off sideways sliding.
		local sideSpeed = velocity:Dot(side)
		velocity -= side * (sideSpeed * MathUtil.expDecay(config.Grip, dt))

		-- Steering: turn rate grows with speed, then softens at very high speed. Reversing flips it like a real car.
		local absSpeed = math.abs(forwardSpeed)
		local turn = config.TurnRate
			* stats.Handling
			* math.clamp(absSpeed / config.TurnSpeedRamp, 0, 1)
			* (1 - config.HighSpeedTurnFactor * math.clamp(absSpeed / config.MaxBoostedSpeed, 0, 1))
		local direction = if forwardSpeed >= 0 then 1 else -1
		local targetYaw = -input.steer * turn * direction
		local currentYaw = angular:Dot(normal)
		local yaw = currentYaw + (targetYaw - currentYaw) * MathUtil.expDecay(config.SteerResponse, dt)

		-- Tilt to match the surface (this is what lets the car ride smoothly up the curved walls).
		local align = up:Cross(normal) * config.AlignStrength
		angular = align + normal * yaw

		if jumpPressed then
			velocity += normal * (config.JumpSpeed * stats.Jump)
			state.suspensionPause = config.JumpSuspensionPause
			state.canSecondJump = true
			state.sinceJump = 0
			state.grounded = false
			result.jumped = true
		end
	else
		state.sinceJump += dt

		if jumpPressed and state.canSecondJump and state.sinceJump <= config.SecondJumpWindow then
			state.canSecondJump = false
			local forwardInput = pitchOf(input)
			if math.abs(forwardInput) + math.abs(input.steer) > 0.3 then
				-- Dodge: a burst in the pressed direction plus a flip.
				local flatForward = MathUtil.safeUnit(MathUtil.flat(look), Vector3.new(0, 0, -1))
				local flatRight = MathUtil.safeUnit(MathUtil.flat(right), Vector3.xAxis)
				local dodgeDirection =
					MathUtil.safeUnit(flatForward * forwardInput + flatRight * input.steer, flatForward)
				velocity += dodgeDirection * config.DodgeSpeed
				if velocity.Y < 0 then
					velocity = Vector3.new(velocity.X, velocity.Y * 0.5, velocity.Z)
				end
				angular = right * (-forwardInput * config.DodgeSpinRate) + look * (input.steer * config.DodgeSpinRate)
				state.dodgeTimer = config.DodgeDuration
				result.dodged = true
			else
				velocity += up * config.DoubleJumpSpeed
				result.jumped = true
			end
		end

		if state.dodgeTimer > 0 then
			state.dodgeTimer = math.max(0, state.dodgeTimer - dt)
		elseif hasAirInput(input) then
			local control = stats.AirControl
			local target = right * (-pitchOf(input) * config.AirPitchRate * control)
				+ up * (-input.steer * config.AirYawRate * control)
				+ look * (input.roll * config.AirRollRate * control)
			angular = angular:Lerp(target, MathUtil.expDecay(config.AirControlResponse, dt))
		else
			angular *= math.exp(-config.AirSpinDamping * dt)
		end
	end

	if input.boost and p.hasBoost then
		velocity += look * (config.BoostAcceleration * dt)
		result.boosting = true
	end

	velocity = MathUtil.clampMagnitude(velocity, config.MaxBoostedSpeed)
	angular = MathUtil.clampMagnitude(angular, config.MaxAngularSpeed)

	-- Stuck on the roof or side? Hop back onto the wheels after a moment.
	if not grounded and up.Y < 0.3 and velocity.Magnitude < 8 and angular.Magnitude < 4 then
		state.stuckTimer += dt
		if state.stuckTimer >= config.AutoRightDelay then
			state.stuckTimer = 0
			result.teleport = MathUtil.uprightFacing(cframe.Position + Vector3.new(0, 3, 0), look)
			velocity = Vector3.new(0, 10, 0)
			angular = Vector3.zero
		end
	else
		state.stuckTimer = 0
	end

	result.velocity = velocity
	result.angularVelocity = angular
	return result
end

return CarPhysics
