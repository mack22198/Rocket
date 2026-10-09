-- Driving help: smoother keyboard steering, aim assist and jump assist.
local DriveAssist = require(Shared.Cars.DriveAssist)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local DT = 1 / 60
	local r = GameConfig.Ball.Radius
	local goal = Vector3.new(0, 16, -300) -- straight ahead of a car facing -Z

	local function params(overrides: { [string]: any }?)
		local p = {
			carCFrame = CFrame.new(0, 2, 0), -- facing -Z
			carVelocity = Vector3.new(0, 0, -50),
			grounded = true,
			throttle = 1,
			steer = 0,
			ballPosition = Vector3.new(-25, r, -60), -- ahead, off to the left
			ballVelocity = Vector3.zero,
			ballRadius = r,
			enemyGoal = goal,
		}
		for k, v in overrides or {} do
			p[k] = v
		end
		return p :: any
	end

	t.test("a tap of a steering key is a nudge, holding it builds up to full lock", function()
		local steer = DriveAssist.smoothKey(0, 1, DT)
		expect.truthy(steer > 0 and steer < 0.2, "one frame is a nudge")
		for _ = 1, 15 do
			steer = DriveAssist.smoothKey(steer, 1, DT)
		end
		expect.equal(steer, 1) -- full lock within about a quarter of a second
		steer = DriveAssist.smoothKey(0, -1, DT)
		expect.truthy(steer < 0 and steer > -0.2, "the other way too")
	end)

	t.test("steering for a ball that's too close to reach makes the car drift round to it", function()
		local close = Vector3.new(-20, r, -15) -- just ahead, off to the left
		local radius = 27 -- the car's turning circle at this speed
		expect.truthy(DriveAssist.needsTightTurn(params({ ballPosition = close, steer = -1 }), radius))
		expect.falsy(
			DriveAssist.needsTightTurn(params({ ballPosition = close, steer = 1 }), radius),
			"steering away from it"
		)
		expect.falsy(
			DriveAssist.needsTightTurn(params({ ballPosition = close, steer = -1 }), 10),
			"a car that can already turn that tight"
		)
		expect.falsy(
			DriveAssist.needsTightTurn(params({ ballPosition = Vector3.new(0, r, -30), steer = -1 }), radius),
			"straight ahead"
		)
		expect.falsy(
			DriveAssist.needsTightTurn(params({ ballPosition = Vector3.new(-20, r, -80), steer = -1 }), radius),
			"far away: plenty of room"
		)
		expect.falsy(
			DriveAssist.needsTightTurn(params({ ballPosition = close, steer = -1, throttle = 0 }), radius),
			"only while driving"
		)
	end)

	t.test("letting go of a steering key straightens up quickly", function()
		local steer = 1
		for _ = 1, 6 do
			steer = DriveAssist.smoothKey(steer, 0, DT)
		end
		expect.equal(steer, 0) -- straight again within a tenth of a second
		-- Switching keys goes back through the middle quickly too.
		steer = 1
		for _ = 1, 6 do
			steer = DriveAssist.smoothKey(steer, -1, DT)
		end
		expect.truthy(steer < 0)
	end)

	t.test("aim assist steers toward a ball ahead when you aren't steering", function()
		local steer = DriveAssist.steer(params())
		expect.truthy(steer < -0.3, `turns left toward the ball (steer {steer})`)
		steer = DriveAssist.steer(params({ ballPosition = Vector3.new(25, r, -60) }))
		expect.truthy(steer > 0.3, "and right")
		-- Straight ahead, already lined up with the goal: no need to turn.
		expect.near(DriveAssist.steer(params({ ballPosition = Vector3.new(0, r, -60) })), 0, 0.05)
	end)

	t.test("aim assist leaves you alone when the ball is behind, far away, or you aren't driving", function()
		expect.equal(DriveAssist.steer(params({ ballPosition = Vector3.new(-10, r, 40) })), 0) -- behind
		expect.equal(DriveAssist.steer(params({ ballPosition = Vector3.new(-25, r, -200) })), 0) -- far
		expect.equal(DriveAssist.steer(params({ throttle = 0 })), 0) -- not on the throttle
		expect.equal(DriveAssist.steer(params({ throttle = -1 })), 0) -- reversing
		expect.equal(DriveAssist.steer(params({ grounded = false })), 0) -- in the air
	end)

	t.test("your own steering always wins", function()
		-- Steering hard away from the ball: exactly what you asked for.
		expect.equal(DriveAssist.steer(params({ steer = 1 })), 1)
		-- Steering gently the same way: a bit more, never more than full lock.
		local steer = DriveAssist.steer(params({ steer = -0.5 }))
		expect.truthy(steer <= -0.5 and steer >= -1)
	end)

	t.test("aim assist heads for the side of the ball that knocks it at the goal", function()
		-- The ball is to the right of the goal line, so the car should come at it a little from the right too.
		local target, alignment = DriveAssist.target(params({ ballPosition = Vector3.new(30, r, -80) }))
		expect.truthy(alignment > 0)
		expect.truthy(target.X > 30, "just behind the ball on the line from the goal")
		expect.truthy(target.Z > -80)
		-- A moving ball: aim where it's going to be.
		local moving =
			DriveAssist.target(params({ ballPosition = Vector3.new(0, r, -60), ballVelocity = Vector3.new(30, 0, 0) }))
		expect.truthy(moving.X > 10)
	end)

	t.test("jumping near a ball in the air pulls the jump toward it", function()
		local car = Vector3.new(0, 2.5, 0)
		local pull = DriveAssist.jumpPull(car, Vector3.new(12, 16, -6))
		expect.truthy(pull.X > 5 and pull.Z < 0, "toward the ball")
		expect.equal(pull.Y, 0)
		expect.atMost(pull.Magnitude, DriveAssist.MaxJumpPull + 1e-6)
		-- Not for a ball on the ground, one that's far away, or one right overhead.
		expect.equal(DriveAssist.jumpPull(car, Vector3.new(12, 2.5, -6)), Vector3.zero)
		expect.equal(DriveAssist.jumpPull(car, Vector3.new(80, 16, 0)), Vector3.zero)
		expect.equal(DriveAssist.jumpPull(car, Vector3.new(0.2, 16, 0)), Vector3.zero)
	end)

	t.test("the second jump flips into a ball only when it's close", function()
		expect.truthy(DriveAssist.canFlipAt(Vector3.zero, Vector3.new(10, 5, -10)))
		expect.falsy(DriveAssist.canFlipAt(Vector3.zero, Vector3.new(40, 5, -10)))
	end)

	t.test("each team aims at the other team's goal", function()
		local length = GameConfig.Arena.Length
		local blue = DriveAssist.enemyGoal(GameConfig.Teams.Blue.DefendsSide, length, GameConfig.Arena.GoalHeight)
		local orange = DriveAssist.enemyGoal(GameConfig.Teams.Orange.DefendsSide, length, GameConfig.Arena.GoalHeight)
		expect.equal(blue.Z, length / 2) -- Blue defends -Z, so it scores at +Z
		expect.equal(orange.Z, -length / 2)
		expect.equal(blue.Y, GameConfig.Arena.GoalHeight / 2)
	end)
end
