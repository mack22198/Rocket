local ArenaShape = require(Shared.Arena.ArenaShape)
local BotBrain = require(Shared.Bots.BotBrain)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local arena = ArenaShape.new(GameConfig.Arena)

	local function context(overrides: { [string]: any })
		local ctx = {
			carCFrame = CFrame.new(0, 2, 60), -- facing -Z
			carVelocity = Vector3.zero,
			grounded = true,
			boost = 50,
			megaReady = false,
			ballPosition = Vector3.new(0, 6, 0),
			ballVelocity = Vector3.zero,
			predict = function(_)
				return Vector3.new(0, 6, 0)
			end,
			defendsSide = 1, -- defends +Z, attacks -Z
			role = "attack",
			skill = 0.6,
			arena = arena,
			aimOffset = Vector3.zero,
		}
		for k, v in overrides do
			ctx[k] = v
		end
		return ctx
	end

	t.test("steerToward turns toward targets on the right", function()
		local steer, angle = BotBrain.steerToward(CFrame.new(), Vector3.new(10, 0, -10))
		expect.truthy(steer > 0)
		expect.truthy(angle < 0)
		steer = BotBrain.steerToward(CFrame.new(), Vector3.new(-10, 0, -10))
		expect.truthy(steer < 0)
	end)

	t.test("an attacker lined up behind the ball drives at it", function()
		local input = BotBrain.decide(context({}), BotBrain.newMemory(), 1 / 12)
		expect.atLeast(input.throttle, 0.8)
		expect.atMost(math.abs(input.steer), 0.2)
	end)

	t.test("an attacker on the wrong side of the ball loops around instead", function()
		-- Car is between the ball and the enemy goal (at -Z), facing the ball.
		local ctx = context({ carCFrame = CFrame.new(0, 2, -40) * CFrame.Angles(0, math.pi, 0) })
		local input = BotBrain.decide(ctx, BotBrain.newMemory(), 1 / 12)
		expect.truthy(math.abs(input.steer) > 0.3, "should steer around the ball")
	end)

	t.test("defenders wait between the ball and their goal", function()
		local ctx =
			context({ role = "defend", ballPosition = Vector3.new(0, 6, -100), carCFrame = CFrame.new(0, 2, 150) })
		local input = BotBrain.decide(ctx, BotBrain.newMemory(), 1 / 12)
		expect.atLeast(input.throttle, 0.5) -- drive out toward the shadow spot
	end)

	t.test("roles: one attacker and one defender per team", function()
		local members = {
			{ key = "a", position = Vector3.new(0, 0, 20) },
			{ key = "b", position = Vector3.new(30, 0, 120) },
			{ key = "c", position = Vector3.new(-40, 0, 60) },
		}
		local roles = BotBrain.assignRoles(members, Vector3.new(0, 6, 0), 1, 160, nil)
		expect.equal(roles.a, "attack")
		expect.equal(roles.b, "defend")
		expect.equal(roles.c, "support")
	end)

	t.test("roles keep the current attacker unless someone is clearly closer", function()
		local members = {
			{ key = "a", position = Vector3.new(0, 0, 20) },
			{ key = "b", position = Vector3.new(0, 0, 25) },
		}
		local roles = BotBrain.assignRoles(members, Vector3.new(0, 6, 0), 1, 160, "b")
		expect.equal(roles.b, "attack")
	end)

	t.test("bots in the air level themselves out", function()
		local tilted = CFrame.new(0, 30, 0) * CFrame.Angles(math.rad(40), 0, 0) -- nose up
		local input = BotBrain.decide(context({ grounded = false, carCFrame = tilted }), BotBrain.newMemory(), 1 / 12)
		expect.equal(input.throttle, 1) -- pitch nose down
		expect.falsy(input.boost)
	end)

	t.test("bots leave the ball to a player on their team who's nearly as close", function()
		local ball = Vector3.new(0, 6, 0)
		local members = {
			{ key = "bot", position = Vector3.new(0, 2, 20) },
			{ key = "you", position = Vector3.new(0, 2, 35), human = true },
			{ key = "bot2", position = Vector3.new(0, 2, 120) },
		}
		local roles = BotBrain.assignRoles(members, ball, 1, arena.halfLength, "bot")
		expect.equal(roles.you, "attack")
		expect.truthy(roles.bot ~= "attack")
		-- But not when the player is far away.
		members[2].position = Vector3.new(0, 2, 90)
		roles = BotBrain.assignRoles(members, ball, 1, arena.halfLength, nil)
		expect.equal(roles.bot, "attack")
	end)

	t.test("bots pass up to a player who's further upfield", function()
		local enemyGoal = Vector3.new(0, 0, -arena.halfLength)
		-- Defends +Z, so upfield is -Z. The player is 40 studs ahead of the ball, off to the side.
		local ctx = context({ ballPosition = Vector3.new(0, 6, 40), feed = Vector3.new(30, 2, 0) })
		local aim = BotBrain.aimPoint(ctx, enemyGoal)
		expect.truthy(aim ~= enemyGoal, "passes")
		expect.atMost((aim - Vector3.new(30, 0, -12)).Magnitude, 0.01)
		-- Behind the ball, or the goal's right there: shoot instead.
		expect.equal(BotBrain.aimPoint(context({ feed = Vector3.new(0, 2, 60) }), enemyGoal), enemyGoal)
		local nearGoal = Vector3.new(0, 6, -arena.halfLength + 40)
		ctx = context({ ballPosition = nearGoal, feed = nearGoal + Vector3.new(10, 0, -20) })
		expect.equal(BotBrain.aimPoint(ctx, enemyGoal), enemyGoal)
		expect.equal(BotBrain.aimPoint(context({}), enemyGoal), enemyGoal)
	end)

	t.test("bots against players adapt to the score, and go easy on new players", function()
		local B = GameConfig.Bots
		local base = B.Skill
		expect.truthy(BotBrain.adaptiveSkill(base, -2, false) < base, "players behind: easier")
		expect.truthy(BotBrain.adaptiveSkill(base, 2, false) > base, "players ahead: harder")
		expect.equal(BotBrain.adaptiveSkill(base, 0, false), base)
		expect.truthy(BotBrain.adaptiveSkill(base, 0, true) < base, "rookies get easier bots")
		expect.atLeast(BotBrain.adaptiveSkill(base, -10, true), B.MinSkill)
		expect.atMost(BotBrain.adaptiveSkill(base, 10, false), B.MaxSkill)
	end)
end
