--!strict
-- Decision making for bot drivers. Pure logic (no Roblox objects), so it's easy to test and tweak.
-- Bots share three roles per team: one ATTACKS the ball, one DEFENDS near its own goal, the rest SUPPORT.
-- Skill (0..1) controls aim wobble, boost use and flip attempts. Default bots are meant to be beatable.

local ArenaShape = require(script.Parent.Parent.Arena.ArenaShape)
local CarPhysics = require(script.Parent.Parent.Physics.CarPhysics)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type Role = "attack" | "support" | "defend"

export type Context = {
	carCFrame: CFrame,
	carVelocity: Vector3,
	grounded: boolean,
	boost: number,
	megaReady: boolean,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	predict: (seconds: number) -> Vector3, -- where the ball will be
	defendsSide: number, -- 1 or -1: which goal this bot protects
	role: Role,
	skill: number,
	arena: ArenaShape.Arena,
	aimOffset: Vector3, -- per-bot wobble so bots aren't perfect
}

export type Memory = {
	jumpMode: number, -- 0 = none, 1 = jump, 2 = flip
	jumpTimer: number,
	stuckTimer: number,
	reverseTimer: number,
	reverseSteer: number,
}

export type Member = { key: string, position: Vector3 }

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
	local function ballDistance(m: Member): number
		return MathUtil.flat(m.position - ballPosition).Magnitude
	end
	local attacker = members[1]
	for _, m in members do
		if ballDistance(m) < ballDistance(attacker) then
			attacker = m
		end
	end
	if previousAttacker and previousAttacker ~= attacker.key then
		for _, m in members do
			if m.key == previousAttacker and ballDistance(m) < ballDistance(attacker) + 12 then
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
	if alignment > 0.2 or distance < 12 then
		target = meet - aim * 2 + ctx.aimOffset -- lined up: drive through the ball
	else
		-- Wrong side of the ball: loop around behind it instead of knocking it toward our own goal.
		local side = MathUtil.safeUnit(aim:Cross(Vector3.yAxis), Vector3.xAxis)
		local sideSign = if (carPos - meet):Dot(side) >= 0 then 1 else -1
		target = meet - aim * 26 + side * (sideSign * 14)
	end
	return ctx.arena:clampInside(Vector3.new(target.X, 0, target.Z), 6), alignment
end

-- Decides this frame's controls. Returns the input and whether the bot wants to fire its Mega Shot.
function BotBrain.decide(ctx: Context, memory: Memory, dt: number): (CarPhysics.Input, boolean)
	local carPos = ctx.carCFrame.Position
	local speed = ctx.carVelocity.Magnitude
	local halfLength = ctx.arena.halfLength
	local ownGoal = Vector3.new(0, 0, ctx.defendsSide * halfLength)
	local enemyGoal = Vector3.new(0, 0, -ctx.defendsSide * halfLength)
	local ballFlatDistance = MathUtil.flat(ctx.ballPosition - carPos).Magnitude
	local ballNearOurGoal = MathUtil.flat(ctx.ballPosition - ownGoal).Magnitude < 75

	local target: Vector3
	local alignment = 0
	local urgent = false
	if ctx.role == "attack" then
		target, alignment = chaseTarget(ctx, enemyGoal)
		urgent = true
	elseif ctx.role == "defend" and ballNearOurGoal then
		-- Clear it: hit the ball away from our goal.
		local away = ctx.ballPosition + (ctx.ballPosition - ownGoal)
		target, alignment = chaseTarget(ctx, Vector3.new(away.X, 0, away.Z))
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
	throttle *= 0.85 + 0.15 * ctx.skill

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

	local boost = urgent
		and ctx.boost > 5
		and ctx.grounded
		and math.abs(angle) < 0.3
		and distance > 30
		and speed < 140
		and ctx.skill > 0.25

	-- Jumps and flips.
	local jump = false
	if memory.jumpMode == 0 and ctx.grounded and urgent and math.abs(angle) < 0.5 then
		local height = ctx.ballPosition.Y
		if height > 9 and height < 20 and ballFlatDistance < 14 then
			memory.jumpMode, memory.jumpTimer = 1, 0
		elseif height < 10 and ballFlatDistance < 13 and speed > 35 and math.abs(angle) < 0.25 and ctx.skill > 0.4 then
			memory.jumpMode, memory.jumpTimer = 2, 0
		end
	end
	if memory.jumpMode ~= 0 then
		memory.jumpTimer += dt
		local t = memory.jumpTimer
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
		boost = false
	end

	local wantsMega = ctx.megaReady and ctx.role == "attack" and ballFlatDistance < 45 and alignment > 0.5

	return {
		throttle = math.clamp(throttle, -1, 1),
		steer = math.clamp(steer, -1, 1),
		roll = roll,
		boost = boost,
		jump = jump,
	},
		wantsMega
end

return BotBrain
