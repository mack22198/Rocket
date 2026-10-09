--!strict
-- Decision making for bot drivers. Pure logic (no Roblox objects), so it's easy to test and tweak.
-- Bots share three roles per team: one ATTACKS the ball, one DEFENDS near its own goal, the rest SUPPORT.
-- Skill (0..1) controls aim wobble, how quick off the mark they are and flip attempts. Default bots are meant to be
-- beatable. A bot that isn't chasing the ball goes for the charge orb when it's close.
--
-- Bots on a player's team are team-mates, not ball hogs: they leave the ball to the player when the player is
-- nearly as close, and pass it up to them when they're further upfield. Bots playing against players get a
-- little easier while the players are behind (and for new players) and a little harder while they're ahead.

local ArenaShape = require(script.Parent.Parent.Arena.ArenaShape)
local CarPhysics = require(script.Parent.Parent.Physics.CarPhysics)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type Role = "attack" | "support" | "defend"

export type Context = {
	carCFrame: CFrame,
	carVelocity: Vector3,
	grounded: boolean,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	ballRadius: number,
	predict: (seconds: number) -> Vector3, -- where the ball will be
	defendsSide: number, -- 1 or -1: which goal this bot protects
	role: Role,
	skill: number,
	arena: ArenaShape.Arena,
	aimOffset: Vector3, -- per-bot wobble so bots aren't perfect
	feed: Vector3?, -- a player on our team to pass to (where their car is)
	orb: Vector3?, -- the charge orb, if there's one on the pitch
}

export type Memory = {
	jumpMode: number, -- 0 = none, 1 = jump, 2 = flip
	jumpTimer: number,
	stuckTimer: number,
	reverseTimer: number,
	reverseSteer: number,
}

export type Member = { key: string, position: Vector3, human: boolean? }

-- Bots leave the ball to a player on their team who's within this many studs of being as close as they are.
local PLAYER_PRIORITY = 25

local BotBrain = {}

function BotBrain.newMemory(): Memory
	return { jumpMode = 0, jumpTimer = 0, stuckTimer = 0, reverseTimer = 0, reverseSteer = 1 }
end

-- Returns steer (-1..1, positive = right), the signed angle to the target (positive = left), and distance.
function BotBrain.steerToward(carCFrame: CFrame, target: Vector3): (number, number, number)
	local look = MathUtil.safeUnit(MathUtil.flat(carCFrame.LookVector), Vector3.new(0, 0, -1))
	local toTarget = MathUtil.flat(target - carCFrame.Position)
	local distance = toTarget.Magnitude
	local direction = MathUtil.safeUnit(toTarget, look)
	local angle = math.atan2(look:Cross(direction).Y, look:Dot(direction))
	return math.clamp(-angle * 2.5, -1, 1), angle, distance
end

-- Picks roles for one team. Everyone on the team (players too) is considered, so bots fill the gaps players
-- leave. `previousAttacker` keeps the attacker from flip-flopping between two equally close cars.
function BotBrain.assignRoles(
	members: { Member },
	ballPosition: Vector3,
	defendsSide: number,
	halfLength: number,
	previousAttacker: string?
): { [string]: Role }
	local roles: { [string]: Role } = {}
	if #members == 0 then
		return roles
	end
	-- How strong a claim each car has on the ball: the closer the better, and players come first.
	local function claim(m: Member): number
		return MathUtil.flat(m.position - ballPosition).Magnitude - (if m.human then PLAYER_PRIORITY else 0)
	end
	local attacker = members[1]
	for _, m in members do
		if claim(m) < claim(attacker) then
			attacker = m
		end
	end
	if previousAttacker and previousAttacker ~= attacker.key and not attacker.human then
		for _, m in members do
			if m.key == previousAttacker and claim(m) < claim(attacker) + 12 then
				attacker = m
			end
		end
	end
	roles[attacker.key] = "attack"

	local ownGoal = Vector3.new(0, 0, defendsSide * halfLength)
	local defender: Member? = nil
	for _, m in members do
		if m ~= attacker then
			if not defender or (m.position - ownGoal).Magnitude < (defender.position - ownGoal).Magnitude then
				defender = m
			end
		end
	end
	for _, m in members do
		if m ~= attacker then
			roles[m.key] = if m == defender then "defend" else "support"
		end
	end
	return roles
end

local function chaseTarget(ctx: Context, aimGoal: Vector3): (Vector3, number)
	local carPos = ctx.carCFrame.Position
	local speed = ctx.carVelocity.Magnitude
	local distance = MathUtil.flat(ctx.ballPosition - carPos).Magnitude
	local eta = math.clamp(distance / math.max(speed, 45), 0.05, 1.5)
	local meet = ctx.predict(eta)
	local aim = MathUtil.safeUnit(MathUtil.flat(aimGoal - meet), Vector3.new(0, 0, -ctx.defendsSide))
	local approach = MathUtil.safeUnit(MathUtil.flat(meet - carPos), aim)
	local alignment = approach:Dot(aim)
	local target
	if alignment > 0.2 or distance < ctx.ballRadius + 6 then
		target = meet - aim * (ctx.ballRadius * 0.3) + ctx.aimOffset -- lined up: drive through the ball
	else
		-- Wrong side of the ball: loop around behind it instead of knocking it toward our own goal.
		local side = MathUtil.safeUnit(aim:Cross(Vector3.yAxis), Vector3.xAxis)
		local sideSign = if (carPos - meet):Dot(side) >= 0 then 1 else -1
		target = meet - aim * 26 + side * (sideSign * 14)
	end
	return ctx.arena:clampInside(Vector3.new(target.X, 0, target.Z), 6), alignment
end

-- Where an attacking bot sends the ball: at the goal, or - when a player on its team is further upfield and the
-- goal isn't close - up to that player, a little ahead of them.
function BotBrain.aimPoint(ctx: Context, enemyGoal: Vector3): Vector3
	local feed = ctx.feed
	if not feed then
		return enemyGoal
	end
	local upfield = Vector3.new(0, 0, -ctx.defendsSide)
	local ahead = MathUtil.flat(feed - ctx.ballPosition):Dot(upfield)
	local gap = MathUtil.flat(feed - ctx.ballPosition).Magnitude
	local nearGoal = MathUtil.flat(enemyGoal - ctx.ballPosition).Magnitude < 70
	if ahead > 15 and gap < 90 and not nearGoal then
		return Vector3.new(feed.X, 0, feed.Z) + upfield * 12
	end
	return enemyGoal
end

-- How good bots playing against players are. `playersLead` is the players' team's score minus the bots';
-- `rookie` is true while one of the players is new to the game.
function BotBrain.adaptiveSkill(base: number, playersLead: number, rookie: boolean): number
	local tuning = GameConfig.Bots
	local skill = base + math.clamp(playersLead, -3, 3) * tuning.SkillPerGoal
	if rookie then
		skill -= tuning.RookieEase
	end
	return math.clamp(skill, tuning.MinSkill, tuning.MaxSkill)
end

-- The most a bot steers (see the end of BotBrain.decide).
local BOT_LOCK = 0.84

-- Bots that aren't chasing the ball go for the charge orb when it's at most this far away.
local ORB_RANGE = 130

-- Decides this frame's controls.
function BotBrain.decide(ctx: Context, memory: Memory, dt: number): CarPhysics.Input
	local carPos = ctx.carCFrame.Position
	local speed = ctx.carVelocity.Magnitude
	local halfLength = ctx.arena.halfLength
	local ownGoal = Vector3.new(0, 0, ctx.defendsSide * halfLength)
	local enemyGoal = Vector3.new(0, 0, -ctx.defendsSide * halfLength)
	local ballFlatDistance = MathUtil.flat(ctx.ballPosition - carPos).Magnitude
	local ballNearOurGoal = MathUtil.flat(ctx.ballPosition - ownGoal).Magnitude < halfLength * 0.45

	local target: Vector3
	local urgent = false
	local orb = ctx.orb
	if ctx.role == "attack" then
		target = chaseTarget(ctx, BotBrain.aimPoint(ctx, enemyGoal))
		urgent = true
	elseif ctx.role == "defend" and ballNearOurGoal then
		-- Clear it: hit the ball away from our goal.
		local away = ctx.ballPosition + (ctx.ballPosition - ownGoal)
		target = chaseTarget(ctx, Vector3.new(away.X, 0, away.Z))
		urgent = true
	elseif orb and MathUtil.flat(orb - carPos).Magnitude < ORB_RANGE then
		-- Nothing to do just now: grab the charge orb.
		target = Vector3.new(orb.X, 0, orb.Z)
		urgent = true
	elseif ctx.role == "defend" then
		local shadow = ownGoal + MathUtil.flat(ctx.ballPosition - ownGoal) * 0.3
		target = ctx.arena:clampInside(shadow, 12)
	else
		local support = Vector3.new(-ctx.ballPosition.X * 0.5, 0, ctx.ballPosition.Z + ctx.defendsSide * 55)
		target = ctx.arena:clampInside(support, 14)
	end

	local steer, angle, distance = BotBrain.steerToward(ctx.carCFrame, target)
	local absAngle = math.abs(angle)
	local throttle = 1
	if absAngle > 2.2 and distance < 30 then
		throttle = -0.7 -- target is behind us and close: back up while turning
		steer = -steer
	elseif absAngle > 1.2 and speed > 35 then
		throttle = -0.5 -- brake into a sharp turn, otherwise we just orbit the target
	elseif absAngle > 0.6 and speed > 60 then
		throttle = 0.1 -- ease off for a medium turn
	elseif not urgent and distance < 14 then
		throttle = distance / 14 * 0.4 -- arrive gently at a waiting spot
	end
	throttle *= 0.7 + 0.3 * ctx.skill -- sleepier bots are slower off the mark

	-- Unstick: if we're pushing but not moving, reverse for a moment.
	if memory.reverseTimer > 0 then
		memory.reverseTimer -= dt
		throttle = -1
		steer = memory.reverseSteer
	elseif ctx.grounded and throttle > 0.5 and speed < 3 then
		memory.stuckTimer += dt
		if memory.stuckTimer > 1.2 then
			memory.stuckTimer = 0
			memory.reverseTimer = 0.8
			memory.reverseSteer = if steer >= 0 then -1 else 1
		end
	else
		memory.stuckTimer = 0
	end

	-- Jumps and flips.
	local jump = false
	if memory.jumpMode == 0 and ctx.grounded and urgent and math.abs(angle) < 0.5 then
		local r = ctx.ballRadius
		local height = ctx.ballPosition.Y - r -- how far the bottom of the ball is off the ground
		local reach = ballFlatDistance - r
		if height > 3 and height < 14 and reach < 8 then
			memory.jumpMode, memory.jumpTimer = 1, 0
		elseif height < 4 and reach < 7 and speed > 35 and math.abs(angle) < 0.25 and ctx.skill > 0.55 then
			memory.jumpMode, memory.jumpTimer = 2, 0
		end
	end
	if memory.jumpMode ~= 0 then
		local t = memory.jumpTimer -- (time since the jump started, before this decision: the first one presses jump)
		memory.jumpTimer += dt
		if memory.jumpMode == 1 then
			jump = t < 0.08
			if t > 0.9 then
				memory.jumpMode = 0
			end
		else
			jump = t < 0.06 or (t > 0.14 and t < 0.22)
			if t > 0.1 then
				throttle, steer = 1, 0 -- flip straight at the ball
			end
			if t > 1.0 then
				memory.jumpMode = 0
			end
		end
	end

	-- In the air (and not mid-flip): level out so we land on our wheels.
	local roll = 0
	if not ctx.grounded and memory.jumpMode ~= 2 then
		local look, right = ctx.carCFrame.LookVector, ctx.carCFrame.RightVector
		throttle = if look.Y > 0.15 then 1 elseif look.Y < -0.15 then -1 else 0
		roll = if right.Y > 0.15 then 1 elseif right.Y < -0.15 then -1 else 0
		steer = 0
	end

	return {
		throttle = math.clamp(throttle, -1, 1),
		-- (Just short of full lock, so bots don't slide into drifts and scrub off the speed they hit the ball with.)
		steer = math.clamp(steer, -BOT_LOCK, BOT_LOCK),
		roll = roll,
		boost = false,
		jump = jump,
	}
end

return BotBrain
