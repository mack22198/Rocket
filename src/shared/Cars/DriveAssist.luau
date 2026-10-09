--!strict
-- Driving help, for players new to car soccer (on by default; it can be switched off in the match menu):
--   * Keyboard steering eases in instead of snapping to full lock, so a tap of A or D is a small nudge.
--   * Aim assist: while you hold the throttle and the ball is roughly ahead, the car steers itself toward the spot
--     that knocks the ball at the other team's goal. Your own steering always wins.
--   * Shot assist (see HitModel): your hits bend partly toward the other team's goal.
--   * Jump assist (see CarPhysics): jumping near a ball in the air jumps toward it, and the second jump flips
--     into it; in the air the car stays level instead of tipping over while you hold W.
-- All pure maths, so it's easy to test.

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local DriveAssist = {}

-- Keyboard steering: how fast it builds up to full lock, and how fast it lets go.
DriveAssist.KeyRise = 4.5 -- full lock after about a fifth of a second
DriveAssist.KeyFall = 11

-- Aim assist.
DriveAssist.Range = 110 -- the ball must be this close (studs, along the ground)...
DriveAssist.Cone = math.rad(80) -- ...and within this angle of where the car is pointing
DriveAssist.Strength = 0.9 -- how much of the steering it does when you aren't steering
DriveAssist.Gain = 2.6 -- steering per radian off target
DriveAssist.MinThrottle = 0.2 -- only while you're driving forward

-- Jump assist.
DriveAssist.JumpReach = 32 -- a ball in the air within this many studs (along the ground) pulls the jump toward it
DriveAssist.JumpPull = 1.1 -- sideways speed per stud of distance...
DriveAssist.MaxJumpPull = 24 -- ...up to this
DriveAssist.FlipReach = 24 -- the second jump flips into a ball this close

export type SteerParams = {
	carCFrame: CFrame,
	carVelocity: Vector3,
	grounded: boolean,
	throttle: number,
	steer: number, -- what the player is steering (-1..1)
	ballPosition: Vector3,
	ballVelocity: Vector3,
	ballRadius: number,
	enemyGoal: Vector3, -- the middle of the goal to score in
}

-- Moves keyboard steering toward `wanted` (-1, 0 or 1) over `dt` seconds.
function DriveAssist.smoothKey(current: number, wanted: number, dt: number): number
	if wanted == 0 or (current ~= 0 and math.sign(current) ~= math.sign(wanted)) then
		-- Letting go (or switching sides): back to the middle quickly.
		local step = DriveAssist.KeyFall * dt
		if math.abs(current) <= step then
			return if wanted == 0 then 0 else wanted * math.min(step - math.abs(current), 1)
		end
		return current - math.sign(current) * step
	end
	local step = DriveAssist.KeyRise * dt
	return math.clamp(current + math.sign(wanted) * step, -1, 1) * math.abs(wanted)
end

-- Where the car should head to knock the ball toward `enemyGoal`: just behind the ball on the line from the goal
-- (or straight at the ball when the car is on the wrong side of it). Also returns how well lined up the car is
-- (1 = right behind the ball, -1 = between the ball and the goal).
function DriveAssist.target(p: SteerParams): (Vector3, number)
	local carPos = p.carCFrame.Position
	local distance = MathUtil.flat(p.ballPosition - carPos).Magnitude
	local speed = math.max(MathUtil.flat(p.carVelocity).Magnitude, 40)
	local eta = math.clamp(distance / speed, 0, 1.2)
	local meet = p.ballPosition + MathUtil.flat(p.ballVelocity) * eta
	local aim = MathUtil.safeUnit(MathUtil.flat(p.enemyGoal - meet), Vector3.zAxis)
	local approach = MathUtil.safeUnit(MathUtil.flat(meet - carPos), aim)
	local alignment = approach:Dot(aim)
	local target = if alignment > 0 then meet - aim * (p.ballRadius * 0.5) else meet
	return Vector3.new(target.X, carPos.Y, target.Z), alignment
end

-- The steering to use this frame: the player's own, with a pull toward the ball when it's ahead.
function DriveAssist.steer(p: SteerParams): number
	if not p.grounded or p.throttle < DriveAssist.MinThrottle then
		return p.steer
	end
	local carPos = p.carCFrame.Position
	local look = MathUtil.safeUnit(MathUtil.flat(p.carCFrame.LookVector), Vector3.new(0, 0, -1))
	local target = DriveAssist.target(p)
	local toTarget = MathUtil.flat(target - carPos)
	local distance = toTarget.Magnitude
	if distance > DriveAssist.Range or distance < 1e-3 then
		return p.steer
	end
	local direction = toTarget / distance
	local angle = math.atan2(look:Cross(direction).Y, look:Dot(direction)) -- positive = to the left
	if math.abs(angle) > DriveAssist.Cone then
		return p.steer -- the ball is off to the side or behind: that's your turn to make
	end
	-- Fade in from the edges of the range and the cone, so the pull never snaps on.
	local weight = math.clamp((DriveAssist.Range - distance) / 25, 0, 1)
		* math.clamp((DriveAssist.Cone - math.abs(angle)) / math.rad(20), 0, 1)
	local assist = math.clamp(-angle * DriveAssist.Gain, -1, 1) * DriveAssist.Strength * weight
	if math.abs(p.steer) > 0.6 and math.sign(p.steer) ~= math.sign(assist) then
		return p.steer -- steering hard the other way: you're in charge
	end
	return math.clamp(p.steer + assist * (1 - math.abs(p.steer)), -1, 1)
end

-- The sideways push a jump gets toward a ball in the air (zero if there's no ball to jump at).
function DriveAssist.jumpPull(carPosition: Vector3, ball: Vector3): Vector3
	local offset = MathUtil.flat(ball - carPosition)
	local distance = offset.Magnitude
	if ball.Y < carPosition.Y + 2 or distance > DriveAssist.JumpReach or distance < 1 then
		return Vector3.zero
	end
	return offset / distance * math.min(distance * DriveAssist.JumpPull, DriveAssist.MaxJumpPull)
end

-- Is the ball close enough for the second jump to flip into it?
function DriveAssist.canFlipAt(carPosition: Vector3, ball: Vector3): boolean
	return (ball - carPosition).Magnitude <= DriveAssist.FlipReach
end

-- The middle of the goal a team scores in.
function DriveAssist.enemyGoal(defendsSide: number, arenaLength: number, goalHeight: number): Vector3
	return Vector3.new(0, goalHeight / 2, -defendsSide * arenaLength / 2)
end

return DriveAssist
