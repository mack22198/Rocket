local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)

return function(t)
	local expect = t.expect
	local cfg = GameConfig.Hit
	local r = GameConfig.Ball.Radius
	local maxBall = GameConfig.Ball.MaxSpeed
	local half = Vector3.new(5.5, 2.2, 8.5) / 2
	local carCFrame = CFrame.new(0, 2, 0) -- facing -Z

	local function hit(carVelocity: Vector3, ballPosition: Vector3, ballVelocity: Vector3?, mega: boolean?)
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
			maxBall
		)
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

	t.test("the car gets a small push back", function()
		local result = hit(Vector3.new(0, 0, -80), Vector3.new(0, 2, -(half.Z + r - 0.5)))
		expect.truthy(result.carVelocityChange.Z > 0)
		expect.atMost(result.carVelocityChange.Magnitude, 30)
	end)
end
