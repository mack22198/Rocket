local GameConfig = require(Shared.Config.GameConfig)
local HitValidation = require(Shared.Match.HitValidation)

return function(t)
	local expect = t.expect
	local cfg = GameConfig.HitValidation
	local half = Vector3.new(5.5, 2.2, 8.5) / 2
	local r = GameConfig.Ball.Radius

	local function goodClaim()
		return {
			time = 100,
			carCFrame = CFrame.new(0, 2, 0),
			carVelocity = Vector3.new(0, 0, -60),
			ballPosition = Vector3.new(0, 3, -(half.Z + r - 1)),
			ballVelocity = Vector3.new(0, 0, 5),
		}
	end

	local function goodView()
		return {
			now = 100.08,
			carPosition = Vector3.new(0, 2, 4), -- the server sees the car a little behind (lag)
			carVelocity = Vector3.new(0, 0, -60),
			ballPositionAtClaim = Vector3.new(0, 3, -(half.Z + r - 1.5)),
			ballVelocityAtClaim = Vector3.new(0, 0, 5),
			lastAcceptedHit = 90,
			carHalfSize = half,
			ballRadius = r,
			maxCarSpeed = GameConfig.Car.MaxBoostedSpeed,
		}
	end

	t.test("a normal hit is accepted", function()
		local ok, reason = HitValidation.check(cfg, goodClaim(), goodView())
		expect.truthy(ok, reason)
	end)

	t.test("old claims are rejected", function()
		local view = goodView()
		view.now = 102
		expect.falsy((HitValidation.check(cfg, goodClaim(), view)))
	end)

	t.test("claims from the future are rejected", function()
		local claim = goodClaim()
		claim.time = 101
		expect.falsy((HitValidation.check(cfg, claim, goodView())))
	end)

	t.test("a car far from where the server sees it is rejected", function()
		local view = goodView()
		view.carPosition = Vector3.new(80, 2, 0)
		expect.falsy((HitValidation.check(cfg, goodClaim(), view)))
	end)

	t.test("a ball far from where the server had it is rejected", function()
		local view = goodView()
		view.ballPositionAtClaim = Vector3.new(50, 3, -20)
		expect.falsy((HitValidation.check(cfg, goodClaim(), view)))
	end)

	t.test("a car that is not actually touching the ball is rejected", function()
		local claim = goodClaim()
		claim.ballPosition = Vector3.new(0, 3, -30)
		local view = goodView()
		view.ballPositionAtClaim = claim.ballPosition
		expect.falsy((HitValidation.check(cfg, claim, view)))
	end)

	t.test("impossible speeds are rejected", function()
		local claim = goodClaim()
		claim.carVelocity = Vector3.new(0, 0, -1000)
		expect.falsy((HitValidation.check(cfg, claim, goodView())))
	end)

	t.test("NaN values are rejected", function()
		local claim = goodClaim()
		claim.ballVelocity = Vector3.new(0 / 0, 0, 0)
		expect.falsy((HitValidation.check(cfg, claim, goodView())))
	end)

	t.test("spamming hits is rejected", function()
		local view = goodView()
		view.lastAcceptedHit = 99.99
		expect.falsy((HitValidation.check(cfg, goodClaim(), view)))
	end)
end
