-- Match twists: every twist only changes settings that exist, a giant ball still fits in the goal, a bouncy
-- ball really bounces higher, weekends are Twist Weekends, and the featured twist turns up more often.
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local GameConfig = require(Shared.Config.GameConfig)
local Twists = require(Shared.Config.Twists)

return function(t)
	local expect = t.expect
	local arena = ArenaShape.new(GameConfig.Arena)

	-- Noon UTC on some known days.
	local SATURDAY = 1790380800 + 12 * 3600 -- 2026-09-26
	local SUNDAY = 1790467200 + 12 * 3600 -- 2026-09-27
	local MONDAY = 1790553600 + 12 * 3600 -- 2026-09-28

	t.test("twists only change settings that exist", function()
		for _, twist in Twists.List do
			for key in twist.Ball or {} do
				expect.truthy((GameConfig.Ball :: any)[key] ~= nil, `{twist.Id}: Ball.{key}`)
			end
			for key in twist.Car or {} do
				expect.truthy((GameConfig.Car :: any)[key] ~= nil, `{twist.Id}: Car.{key}`)
			end
			expect.atLeast(twist.Weight, 1)
		end
		expect.equal(Twists.ballConfig("").Radius, GameConfig.Ball.Radius)
		expect.truthy(Twists.ballConfig("giant").Radius > GameConfig.Ball.Radius * 1.4)
		expect.equal(GameConfig.Ball.Radius, 6, "the normal settings are never changed")
	end)

	t.test("a giant ball still fits in the goal and scores", function()
		local cfg = Twists.ballConfig("giant")
		expect.truthy(cfg.Radius * 2 < GameConfig.Arena.GoalHeight - 2)
		expect.truthy(cfg.Radius * 2 < GameConfig.Arena.GoalWidth - 2)
		expect.truthy(cfg.Radius * 2 < GameConfig.Arena.GoalDepth, "it can get all the way into the net")
		local ball = BallSim.newState(Vector3.new(0, cfg.Radius, 100), Vector3.new(0, 0, 90))
		local scored = false
		BallSim.simulate(arena, cfg, ball, 3, function(s)
			if arena:goalSide(s.position, cfg.Radius) then
				scored = true
				return true
			end
			return false
		end)
		expect.truthy(scored)
	end)

	local function bounceHeight(cfg: any): number
		local ball = BallSim.newState(Vector3.new(0, 40, 0))
		local falling = true
		local best = 0
		BallSim.simulate(arena, cfg, ball, 6, function(s)
			if falling and s.velocity.Y > 0 then
				falling = false -- it has bounced
			end
			if not falling then
				best = math.max(best, s.position.Y)
				if s.velocity.Y < 0 then
					return true -- the top of the first bounce
				end
			end
			return false
		end)
		return best
	end

	t.test("a bouncy ball bounces higher, and low gravity floats", function()
		local normal = bounceHeight(GameConfig.Ball)
		local bouncy = bounceHeight(Twists.ballConfig("bouncy"))
		expect.truthy(bouncy > normal * 1.4, `bouncy {bouncy} vs normal {normal}`)
		expect.truthy(Twists.carConfig("moon").Gravity < GameConfig.Car.Gravity)
		expect.truthy(Twists.ballConfig("moon").Gravity < GameConfig.Ball.Gravity)
		expect.truthy(Twists.carConfig("ice").Grip < GameConfig.Car.Grip / 2)
	end)

	t.test("weekends are Twist Weekends", function()
		expect.equal(Twists.weekday(SATURDAY), 6)
		expect.equal(Twists.weekday(SUNDAY), 0)
		expect.equal(Twists.weekday(MONDAY), 1)
		expect.truthy(Twists.event(SATURDAY) ~= nil)
		expect.truthy(Twists.event(SUNDAY) ~= nil)
		expect.equal(Twists.event(MONDAY), nil)
	end)

	t.test("most weekday matches get a twist, weekend matches always do", function()
		expect.equal(Twists.pick(MONDAY, 0.95, 0.5), "")
		expect.truthy(Twists.pick(MONDAY, 0.1, 0.5) ~= "")
		for i = 0, 20 do
			expect.truthy(Twists.pick(SATURDAY, i / 20, 0.3) ~= "", "every weekend match has a twist")
		end
	end)

	t.test("the twist of the week turns up more often", function()
		local featured = Twists.featured(MONDAY)
		local counts: { [string]: number } = {}
		local samples = 2000
		for i = 0, samples - 1 do
			local id = Twists.pick(MONDAY, 0, (i + 0.5) / samples)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, twist in Twists.List do
			expect.atLeast(counts[twist.Id] or 0, 1, `{twist.Id} can turn up`)
			if twist ~= featured and twist.Weight == featured.Weight then
				expect.truthy(
					(counts[featured.Id] or 0) > (counts[twist.Id] or 0) * 2,
					`{featured.Id} beats {twist.Id}`
				)
			end
		end
		expect.truthy(Twists.featured(MONDAY + 7 * 86400) ~= featured, "a different one next week")
	end)
end
