--!strict
-- What happens when a car touches the ball. Used by the server (authoritative) and by the client that is
-- driving the car (so a player's own hits feel instant instead of waiting for the network). Players with driving
-- help on (see DriveAssist) get a shot assist: their hits bend partly toward the goal they're attacking.

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type Config = {
	CarMassShare: number,
	Restitution: number,
	KickScaleSlow: number,
	KickScaleMid: number,
	KickScaleFast: number,
	KickMidSpeed: number,
	KickFastSpeed: number,
	VerticalBias: number,
	ForwardBias: number,
	MegaSpeedMultiplier: number,
	MegaMinSpeed: number,
	MegaAimAssist: number,
	ShotAssist: number, -- with driving help: how much of the way toward the goal a hit bends (0..1)...
	ShotAssistCone: number, -- ...when it's already going within this angle (radians) of the goal
}

export type Contact = {
	normal: Vector3, -- from the car's surface toward the ball centre
	point: Vector3, -- closest point on the car's box
	depth: number,
	halfSize: Vector3, -- the car box that was tested
}

export type HitResult = {
	ballPosition: Vector3,
	ballVelocity: Vector3,
	carVelocityChange: Vector3,
	impactSpeed: number, -- how hard the car hit the ball (for sounds/effects)
}

local HitModel = {}

function HitModel.closestPointOnBox(boxCFrame: CFrame, halfSize: Vector3, point: Vector3): Vector3
	local localPoint = boxCFrame:PointToObjectSpace(point)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)
	return boxCFrame:PointToWorldSpace(clamped)
end

-- Does a car's hitbox overlap the ball?
function HitModel.findContact(carCFrame: CFrame, halfSize: Vector3, ballPosition: Vector3, ballRadius: number): Contact?
	local closest = HitModel.closestPointOnBox(carCFrame, halfSize, ballPosition)
	local offset = ballPosition - closest
	local distance = offset.Magnitude
	if distance >= ballRadius then
		return nil
	end
	local normal
	if distance > 1e-4 then
		normal = offset / distance
	else
		-- Ball centre inside the car (very fast hit): push it out away from the car's centre.
		normal = MathUtil.safeUnit(ballPosition - carCFrame.Position, carCFrame.LookVector)
	end
	return { normal = normal, point = closest, depth = ballRadius - distance, halfSize = halfSize }
end

local function kickScale(config: Config, speed: number): number
	if speed <= config.KickMidSpeed then
		return MathUtil.remapClamped(speed, 0, config.KickMidSpeed, config.KickScaleSlow, config.KickScaleMid)
	end
	return MathUtil.remapClamped(
		speed,
		config.KickMidSpeed,
		config.KickFastSpeed,
		config.KickScaleMid,
		config.KickScaleFast
	)
end

-- Turns `velocity` (around the vertical axis only) `amount` of the way toward `toward`, if it's within `cone`
-- radians of it along the ground. Speed and the up-and-down part are kept.
function HitModel.bendToward(velocity: Vector3, toward: Vector3, amount: number, cone: number): Vector3
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local flatToward = Vector3.new(toward.X, 0, toward.Z)
	local speed = flatVelocity.Magnitude
	if speed < 1 or flatToward.Magnitude < 1e-3 or amount <= 0 then
		return velocity
	end
	local current = flatVelocity / speed
	local wanted = flatToward.Unit
	local angle = math.acos(math.clamp(current:Dot(wanted), -1, 1))
	if angle > cone then
		return velocity
	end
	local turn = angle * math.clamp(amount, 0, 1) * (if current:Cross(wanted).Y >= 0 then 1 else -1)
	local bent = CFrame.Angles(0, turn, 0):VectorToWorldSpace(current) * speed
	return Vector3.new(bent.X, velocity.Y, bent.Z)
end

-- Computes the ball's new motion after a touch. `contact` must come from findContact for the same car/ball.
function HitModel.resolve(
	config: Config,
	carCFrame: CFrame,
	carVelocity: Vector3,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	ballRadius: number,
	contact: Contact,
	mega: boolean,
	maxBallSpeed: number,
	aim: Vector3? -- the goal to bend shots toward (driving help), or nil
): HitResult
	local normal = contact.normal
	local relativeVelocity = carVelocity - ballVelocity
	local approachSpeed = math.max(0, relativeVelocity:Dot(normal))

	-- 1) The physical bump: like two bodies colliding, where the car is much heavier than the ball.
	local newVelocity = ballVelocity + normal * (approachSpeed * (1 + config.Restitution) * config.CarMassShare)

	-- 2) The arcade "kick": aims the ball away from the car's centre, flattened so hits don't all go straight up.
	local look = carCFrame.LookVector
	local fromCar = ballPosition - carCFrame.Position
	fromCar = Vector3.new(fromCar.X, fromCar.Y * config.VerticalBias, fromCar.Z)
	fromCar -= look * (fromCar:Dot(look) * config.ForwardBias)
	local kickDirection = MathUtil.safeUnit(fromCar, normal)
	local relativeSpeed = relativeVelocity.Magnitude
	newVelocity += kickDirection * (relativeSpeed * kickScale(config, relativeSpeed))

	-- 3) Driving help: bend the shot part of the way toward the goal, if it's already heading roughly that way.
	if aim and not mega then
		newVelocity = HitModel.bendToward(newVelocity, aim - ballPosition, config.ShotAssist, config.ShotAssistCone)
	end

	-- 4) Mega Shot: a huge, slightly aim-assisted blast.
	if mega then
		local blast = MathUtil.safeUnit(newVelocity, kickDirection):Lerp(look, config.MegaAimAssist)
		blast = MathUtil.safeUnit(blast + Vector3.new(0, 0.12, 0), look)
		local speed = math.max(newVelocity.Magnitude * config.MegaSpeedMultiplier, config.MegaMinSpeed)
		newVelocity = blast * speed
	end

	newVelocity = MathUtil.clampMagnitude(newVelocity, maxBallSpeed)

	-- Move the ball out of the car so it doesn't get hit again on the next frame.
	local newPosition
	if contact.depth < ballRadius then
		newPosition = contact.point + normal * (ballRadius + 0.05)
	else
		-- The centre ended up inside the car: slide it out along the normal until it clears the box.
		local halfSize = contact.halfSize
		local localNormal = carCFrame:VectorToObjectSpace(normal)
		local exit = math.huge
		for _, pair in { { localNormal.X, halfSize.X }, { localNormal.Y, halfSize.Y }, { localNormal.Z, halfSize.Z } } do
			if math.abs(pair[1]) > 1e-4 then
				exit = math.min(exit, pair[2] / math.abs(pair[1]))
			end
		end
		newPosition = carCFrame.Position + normal * (exit + ballRadius + 0.05)
	end

	-- The car feels a small push back (the ball is light).
	local carChange = -normal * (approachSpeed * (1 + config.Restitution) * (1 - config.CarMassShare))

	return {
		ballPosition = newPosition,
		ballVelocity = newVelocity,
		carVelocityChange = carChange,
		impactSpeed = relativeSpeed,
	}
end

return HitModel
