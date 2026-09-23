local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local arena = ArenaShape.new(GameConfig.Arena)
	local cfg = GameConfig.Ball
	local r = cfg.Radius
	local dt = cfg.FixedStep

	local function run(state, seconds: number, visit: ((any) -> ())?)
		local steps = math.floor(seconds / dt + 0.5)
		for _ = 1, steps do
			BallSim.step(arena, cfg, state, dt)
			if visit then
				visit(state)
			end
		end
		return state
	end

	local function assertInside(pos: Vector3)
		assert(pos.X == pos.X and pos.Y == pos.Y and pos.Z == pos.Z, "ball position became NaN")
		-- Inside the octagon (with a little tolerance for the per-step penetration).
		for _, plane in arena.planes do
			local d = (pos - plane.point):Dot(plane.normal)
			assert(d > r - 1.5, `ball went through a wall: {pos}`)
		end
		if math.abs(pos.Z) > arena.halfLength then
			assert(math.abs(pos.X) < arena.goalHalfWidth - r + 1.5, `ball went through an end wall: {pos}`)
			assert(pos.Y < arena.goalHeight - r + 1.5, `ball went through the crossbar: {pos}`)
			assert(math.abs(pos.Z) < arena.halfLength + arena.goalDepth - r + 1.5, `ball left the goal: {pos}`)
		end
	end

	t.test("a dropped ball bounces and settles on the floor", function()
		local state = BallSim.newState(Vector3.new(0, 40, 0))
		run(state, 12)
		expect.near(state.position.Y, r, 0.05)
		expect.atMost(state.velocity.Magnitude, 0.5)
	end)

	t.test("the first bounce loses energy but still bounces", function()
		local state = BallSim.newState(Vector3.new(0, 40, 0))
		local impact = 0
		local rebound = 0
		local lastVy = 0
		run(state, 3, function(s)
			if lastVy < -1 and s.velocity.Y > 0 and rebound == 0 then
				impact = -lastVy
				rebound = s.velocity.Y
			end
			lastVy = s.velocity.Y
		end)
		expect.atLeast(impact, 30)
		expect.near(rebound / impact, cfg.Restitution, 0.08)
	end)

	t.test("a rolling ball slows down gently", function()
		local state = BallSim.newState(Vector3.new(0, r, 0), Vector3.new(0, 0, 40))
		run(state, 2)
		expect.atLeast(state.velocity.Magnitude, 25)
		expect.atMost(state.velocity.Magnitude, 40)
		expect.near(state.position.Y, r, 0.1)
	end)

	t.test("a fast roll rides up the curved wall and comes back", function()
		local state = BallSim.newState(Vector3.new(0, r, 0), Vector3.new(140, 0, 0))
		local maxY = 0
		run(state, 6, function(s)
			maxY = math.max(maxY, s.position.Y)
			assertInside(s.position)
		end)
		expect.atLeast(maxY, 30)
		expect.atMost(state.position.X, 100)
	end)

	t.test("a shot straight at the goal scores", function()
		local state = BallSim.newState(Vector3.new(0, r, 100), Vector3.new(0, 0, 120))
		local side, when = BallSim.predictGoal(arena, cfg, state, 2)
		expect.equal(side, 1)
		expect.truthy(when and when < 1)
	end)

	t.test("a shot wide of the goal does not score", function()
		local state = BallSim.newState(Vector3.new(60, r, 100), Vector3.new(0, 0, 120))
		local side = BallSim.predictGoal(arena, cfg, state, 2)
		expect.equal(side, nil)
	end)

	t.test("a ball fired over the crossbar bounces back out", function()
		local state = BallSim.newState(Vector3.new(0, 45, 120), Vector3.new(0, 0, 120))
		local side = BallSim.predictGoal(arena, cfg, state, 1)
		expect.equal(side, nil)
	end)

	t.test("simulate does not change the original state", function()
		local state = BallSim.newState(Vector3.new(0, 30, 0), Vector3.new(10, 0, 0))
		BallSim.simulate(arena, cfg, state, 1)
		expect.equal(state.position, Vector3.new(0, 30, 0))
	end)

	t.test("random shots never escape the arena", function()
		math.randomseed(1234)
		local function between(lo: number, hi: number): number
			return lo + (hi - lo) * math.random()
		end
		for _ = 1, 250 do
			local pos = Vector3.new(between(-90, 90), between(r, 80), between(-140, 140))
			pos = arena:resolve(pos, r)
			local dir = Vector3.new(between(-1, 1), between(-1, 1), between(-1, 1))
			if dir.Magnitude < 0.1 then
				dir = Vector3.xAxis
			end
			local state = BallSim.newState(pos, dir.Unit * between(0, cfg.MaxSpeed))
			run(state, 4, function(s)
				assertInside(s.position)
			end)
		end
	end)
end
