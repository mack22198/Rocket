--!strict
-- The server's sanity checks for "my car hit the ball" messages from players.
-- Players predict their own hits so the game feels instant; the server only accepts a hit that could really
-- have happened given what the server itself saw (allowing for network lag).

local HitModel = require(script.Parent.Parent.Physics.HitModel)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type Config = {
	MaxClaimAge: number,
	MaxClaimLead: number,
	CarPositionTolerance: number,
	CarPositionLatencyFactor: number,
	BallPositionTolerance: number,
	BallPositionLatencyFactor: number,
	BallVelocityTolerance: number,
	BallVelocityLatencyFactor: number,
	OverlapSlack: number,
	MinInterval: number,
	MaxCarSpeedFactor: number,
}

export type Claim = {
	time: number, -- server time at which the client saw the hit
	carCFrame: CFrame,
	carVelocity: Vector3,
	ballPosition: Vector3,
	ballVelocity: Vector3,
}

export type ServerView = {
	now: number,
	carPosition: Vector3, -- where the server currently thinks the car is
	carVelocity: Vector3,
	ballPositionAtClaim: Vector3, -- the server's own ball history at claim.time
	ballVelocityAtClaim: Vector3,
	lastAcceptedHit: number, -- server time of this car's previous accepted hit
	carHalfSize: Vector3,
	ballRadius: number,
	maxCarSpeed: number,
}

local HitValidation = {}

function HitValidation.check(config: Config, claim: Claim, view: ServerView): (boolean, string?)
	if not (MathUtil.isFiniteNumber(claim.time) and MathUtil.isFiniteVector(claim.carCFrame.Position)) then
		return false, "bad numbers"
	end
	if not (MathUtil.isFiniteVector(claim.carVelocity) and MathUtil.isFiniteVector(claim.ballPosition)) then
		return false, "bad numbers"
	end
	if not MathUtil.isFiniteVector(claim.ballVelocity) then
		return false, "bad numbers"
	end
	if claim.time > view.now + config.MaxClaimLead then
		return false, "from the future"
	end
	if claim.time < view.now - config.MaxClaimAge then
		return false, "too old"
	end
	if claim.time - view.lastAcceptedHit < config.MinInterval then
		return false, "too soon after the last hit"
	end
	if claim.carVelocity.Magnitude > view.maxCarSpeed * config.MaxCarSpeedFactor then
		return false, "car too fast"
	end

	local carSlack = config.CarPositionTolerance + view.carVelocity.Magnitude * config.CarPositionLatencyFactor
	if (claim.carCFrame.Position - view.carPosition).Magnitude > carSlack then
		return false, "car is not where the server sees it"
	end

	local ballSpeed = view.ballVelocityAtClaim.Magnitude
	local ballSlack = config.BallPositionTolerance + ballSpeed * config.BallPositionLatencyFactor
	if (claim.ballPosition - view.ballPositionAtClaim).Magnitude > ballSlack then
		return false, "ball is not where the server had it"
	end
	local velocitySlack = config.BallVelocityTolerance + ballSpeed * config.BallVelocityLatencyFactor
	if (claim.ballVelocity - view.ballVelocityAtClaim).Magnitude > velocitySlack then
		return false, "ball speed does not match"
	end

	local contact = HitModel.findContact(
		claim.carCFrame,
		view.carHalfSize,
		claim.ballPosition,
		view.ballRadius + config.OverlapSlack
	)
	if not contact then
		return false, "car was not touching the ball"
	end
	return true, nil
end

return HitValidation
