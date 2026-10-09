local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)

return function(t)
	local expect = t.expect
	local cfg = GameConfig.Hit
	local r = GameConfig.Ball.Radius
	local maxBall = GameConfig.Ball.MaxSpeed
	local half = Vector3.new(5.5, 2.2, 8.5) / 2
	local carCFrame = CFrame.new(0, 2, 0) -- facing -Z

	local function hit(
		carVelocity: Vector3,
		ballPosition: Vector3,
		ballVelocity: Vector3?,
		mega: boolean?,
		aim: Vector3?
	)
		local contact = HitModel.findContact(carCFrame, half, ballPosition, r)
		assert(contact, "expected the car to touch the ball")
		return HitModel.resolve(
			cfg,
			carCFrame,
			carVelocity,
			ballPosition,
			ballVelocity or Vector3.zero,
			r,
			contact,
			mega == true,
			maxBall,
			aim
		)
	end

	-- How far a velocity heads off to the side of straight ahead (-Z), in radians.
	local function sideAngle(v: Vector3): number
		return math.atan2(v.X, -v.Z)
	end

	t.test("no contact when the ball is far away", function()
		expect.equal(HitModel.findContact(carCFrame, half, Vector3.new(0, 2, -30), r), nil)
	end)

	t.test("driving into the ball sends it forward, faster than the car", function()
		local result = hit(Vector3.new(0, 0, -80), Vector3.new(0, 2, -(half.Z + r - 0.5)))
		expect.truthy(result.ballVelocity.Z < -80)
		expect.atMost(math.abs(result.ballVelocity.X), 1)
	end)

	t.test("faster cars hit harder", function()
		local ballPos = Vector3.new(0, 2, -(half.Z + r - 0.5))
		local slow = hit(Vector3.new(0, 0, -30), ballPos).ballVelocity.Magnitude
		local fast = hit(Vector3.new(0, 0, -90), ballPos).ballVelocity.Magnitude
		expect.truthy(fast > slow + 30)
	end)

	t.test("hitting the ball off-centre sends it sideways", function()
		local result = hit(Vector3.new(0, 0, -60), Vector3.new(3, 2, -(half.Z + r - 1)))
		expect.truthy(result.ballVelocity.X > 5)
	end)

	t.test("a ball on the roof pops up when the car jumps", function()
		local result = hit(Vector3.new(0, 30, 0), Vector3.new(0, 2 + half.Y + r - 0.5, 0))
		expect.truthy(result.ballVelocity.Y > 20)
	end)

	t.test("the ball is moved out of the car", function()
		local result = hit(Vector3.new(0, 0, -60), Vector3.new(0, 2, -(half.Z + r - 3)))
		expect.equal(HitModel.findContact(carCFrame, half, result.ballPosition, r), nil)
	end)

	t.test("mega shots are very fast", function()
		local result = hit(Vector3.new(0, 0, -20), Vector3.new(0, 2, -(half.Z + r - 0.5)), nil, true)
		expect.atLeast(result.ballVelocity.Magnitude, cfg.MegaMinSpeed - 0.01)
		expect.truthy(result.ballVelocity.Z < 0)
	end)

	t.test("ball speed is capped", function()
		local result =
			hit(Vector3.new(0, 0, -150), Vector3.new(0, 2, -(half.Z + r - 0.5)), Vector3.new(0, 0, 200), true)
		expect.atMost(result.ballVelocity.Magnitude, maxBall + 1e-6)
	end)

	t.test("a ball stuck inside the car is pushed clear without NaNs", function()
		local contact = HitModel.findContact(carCFrame, half, Vector3.new(0, 2, -1), r)
		assert(contact)
		local result = HitModel.resolve(
			cfg,
			carCFrame,
			Vector3.zero,
			Vector3.new(0, 2, -1),
			Vector3.zero,
			r,
			contact,
			false,
			maxBall
		)
		local p = result.ballPosition
		expect.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z)
		expect.equal(HitModel.findContact(carCFrame, half, p, r), nil)
	end)

	t.test("driving help bends a hit part of the way toward the goal", function()
		local goal = Vector3.new(0, 16, -300)
		local ballPos = Vector3.new(3, 2, -(half.Z + r - 1)) -- hit off-centre: it goes off to the right
		local plain = hit(Vector3.new(0, 0, -60), ballPos).ballVelocity
		local helped = hit(Vector3.new(0, 0, -60), ballPos, nil, false, goal).ballVelocity
		expect.truthy(sideAngle(plain) > 0.1)
		expect.near(sideAngle(helped), sideAngle(plain) * (1 - cfg.ShotAssist), 0.02)
		-- Same speed and the same height: only the direction changes.
		local flat = function(v: Vector3)
			return Vector3.new(v.X, 0, v.Z).Magnitude
		end
		expect.near(flat(helped), flat(plain), 1e-3)
		expect.near(helped.Y, plain.Y, 1e-6)
		-- Mega shots aim themselves already.
		local mega = hit(Vector3.new(0, 0, -60), ballPos, nil, true).ballVelocity
		local megaHelped = hit(Vector3.new(0, 0, -60), ballPos, nil, true, goal).ballVelocity
		expect.near((mega - megaHelped).Magnitude, 0, 1e-6)
	end)

	t.test("shot help only bends shots already heading roughly at the goal", function()
		local toward = Vector3.new(0, 0, -100)
		local cone = cfg.ShotAssistCone
		local amount = cfg.ShotAssist
		-- Going left of the goal: bent right, toward it.
		local bent = HitModel.bendToward(Vector3.new(-40, 10, -60), toward, amount, cone)
		expect.truthy(bent.X > -40 and bent.X < 0)
		expect.equal(bent.Y, 10)
		-- Going backwards, away from the goal: left alone.
		local back = Vector3.new(5, 10, 60)
		expect.equal(HitModel.bendToward(back, toward, amount, cone), back)
		-- Going straight up: left alone.
		local up = Vector3.new(0, 50, 0)
		expect.equal(HitModel.bendToward(up, toward, amount, cone), up)
	end)

	t.test("the car gets a small push back", function()
		local result = hit(Vector3.new(0, 0, -80), Vector3.new(0, 2, -(half.Z + r - 0.5)))
		expect.truthy(result.carVelocityChange.Z > 0)
		expect.atMost(result.carVelocityChange.Magnitude, 30)
	end)
end
