local ArenaShape = require(Shared.Arena.ArenaShape)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local arena = ArenaShape.new(GameConfig.Arena)
	local r = GameConfig.Ball.Radius

	t.test("ball floating mid-field touches nothing", function()
		local n = arena:deepestContact(Vector3.new(0, 30, 0), r)
		expect.equal(n, nil)
	end)

	t.test("floor pushes straight up", function()
		local n, depth = arena:deepestContact(Vector3.new(0, 3, 0), r)
		expect.truthy(n)
		expect.near(n.Y, 1, 1e-6)
		expect.near(depth, 3, 1e-6)
	end)

	t.test("side wall pushes back into the field", function()
		local n, depth = arena:deepestContact(Vector3.new(107, 50, 0), r)
		expect.truthy(n)
		expect.near(n.X, -1, 1e-6)
		expect.near(depth, 3, 1e-6)
	end)

	t.test("curved ramp pushes toward the middle of the curve", function()
		-- 10 studs from the side wall, 5 studs up: inside the ramp's reach
		local n, depth = arena:deepestContact(Vector3.new(100, 5, 0), r)
		expect.truthy(n)
		local len = math.sqrt(10 * 10 + 15 * 15)
		expect.near(depth, r - (20 - len), 1e-4)
		expect.near(n.X, -10 / len, 1e-4)
		expect.near(n.Y, 15 / len, 1e-4)
	end)

	t.test("ball resting on the ramp surface is in balance", function()
		-- A point exactly (R - r) from the curve's axis touches the ramp with zero depth.
		local R = GameConfig.Arena.CurveRadius
		local angle = math.rad(40)
		local axis = Vector3.new(110 - R, R, 0)
		local pos = axis + Vector3.new(math.sin(angle), -math.cos(angle), 0) * (R - r)
		local _, depth = arena:deepestContact(pos, r)
		expect.near(depth, 0, 1e-3)
	end)

	t.test("corner walls are solid", function()
		-- Right at the (+x, +z) corner, which the 45 degree wall cuts off.
		local n = arena:deepestContact(Vector3.new(100, 50, 150), r)
		expect.truthy(n)
		expect.truthy(n.X < 0 and n.Z < 0)
	end)

	t.test("end wall beside the goal is solid", function()
		local n, depth = arena:deepestContact(Vector3.new(60, 50, 157), r)
		expect.truthy(n)
		expect.near(n.Z, -1, 1e-6)
		expect.near(depth, 3, 1e-6)
	end)

	t.test("the goal mouth is open", function()
		local n = arena:deepestContact(Vector3.new(0, 14, 165), r)
		expect.equal(n, nil)
	end)

	t.test("goal post edge gives a rounded push", function()
		local halfGoal = GameConfig.Arena.GoalWidth / 2
		local n = arena:deepestContact(Vector3.new(halfGoal - 3, 23, 157), r)
		expect.truthy(n)
		expect.near(n.X, -math.sqrt(0.5), 1e-4)
		expect.near(n.Z, -math.sqrt(0.5), 1e-4)
	end)

	t.test("crossbar blocks from above", function()
		local n = arena:deepestContact(Vector3.new(0, GameConfig.Arena.GoalHeight + 3, 163), r)
		expect.truthy(n)
		expect.near(n.Y, -1, 1e-6)
	end)

	t.test("ramp next to the goal has a flat end face", function()
		local halfGoal = GameConfig.Arena.GoalWidth / 2
		local n, depth = arena:deepestContact(Vector3.new(halfGoal - 3, 7, 157), r)
		expect.truthy(n)
		expect.truthy(depth > 0)
		-- The ball sits in front of the ramp's end, so it must not be launched upward by the curve.
		expect.atMost(n.Y, 0.5)
	end)

	t.test("goalSide only counts a ball fully over the line", function()
		expect.equal(arena:goalSide(Vector3.new(0, 10, 160 + r + 1), r), 1)
		expect.equal(arena:goalSide(Vector3.new(0, 10, -(160 + r + 1)), r), -1)
		expect.equal(arena:goalSide(Vector3.new(0, 10, 160 + r - 1), r), nil)
		expect.equal(arena:goalSide(Vector3.new(0, 10, 0), r), nil)
	end)

	t.test("clampInside keeps points inside the octagon", function()
		local p = arena:clampInside(Vector3.new(500, 500, 500), 5)
		expect.truthy(arena:contains(p, 4.9))
	end)

	t.test("wallDistance measures to the nearest wall", function()
		expect.near(arena:wallDistance(Vector3.new(100, 20, 0)), 10, 1e-6)
		expect.near(arena:wallDistance(Vector3.new(60, 40, 150)), 10, 1e-6)
	end)
end
