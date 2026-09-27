-- Items and car powers: every car has a power, losing teams get the better items, pulls really do bring the
-- ball in and hold it, launches and ground pounds push the right way, and traps catch the right cars.
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local Powers = require(Shared.Config.Powers)

return function(t)
	local expect = t.expect
	local T = Powers.Tuning

	local function chance(standing: string, item: string): number
		local weights = Powers.ItemWeights[standing]
		local total = 0
		for _, id in Powers.ItemOrder do
			total += weights[id]
		end
		return weights[item] / total
	end

	t.test("every car has its own power", function()
		local seen: { [string]: boolean } = {}
		for _, def in CarCatalog.ordered() do
			local power = Powers.CarPowers[def.Id]
			assert(power, `{def.Id} has no power`)
			expect.falsy(seen[power.Id], `{power.Id} is used by two cars`)
			seen[power.Id] = true
			expect.atLeast(power.Cooldown, 5)
			expect.truthy(#power.Description > 10)
		end
		for _, id in GameConfig.Bots.CarIds do
			expect.truthy(Powers.CarPowers[id] ~= nil, `bot car {id} has a power`)
		end
	end)

	t.test("every item has a weight for every standing", function()
		for _, standing in { "ahead", "level", "behind" } do
			for _, id in Powers.ItemOrder do
				assert(Powers.Items[id], `{id} is defined`)
				expect.atLeast(Powers.ItemWeights[standing][id], 1, `{id} can turn up when {standing}`)
			end
		end
	end)

	t.test("a team that's behind gets the comeback items more often", function()
		for _, item in { "magnet", "freeze", "mega" } do
			expect.truthy(chance("behind", item) > chance("level", item), `{item}: behind > level`)
			expect.truthy(chance("level", item) > chance("ahead", item), `{item}: level > ahead`)
		end
		expect.equal(Powers.standing(1, 3), "behind")
		expect.equal(Powers.standing(2, 2), "level")
		expect.equal(Powers.standing(4, 0), "ahead")
	end)

	t.test("picking an item follows the weights", function()
		local counts: { [string]: number } = {}
		local samples = 10000
		for i = 0, samples - 1 do
			local id = Powers.pickItem("behind", (i + 0.5) / samples)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, id in Powers.ItemOrder do
			expect.near((counts[id] or 0) / samples, chance("behind", id), 0.002, `{id} share`)
		end
		expect.equal(Powers.pickItem("level", 0), Powers.ItemOrder[1])
		expect.equal(Powers.pickItem("level", 1), Powers.ItemOrder[#Powers.ItemOrder])
	end)

	local arena = ArenaShape.new(GameConfig.Arena)
	local ballCfg = GameConfig.Ball

	-- Runs the ball with a pull toward the car at `carCFrame` for `seconds`.
	local function pulled(kind: string, carCFrame: CFrame, start: Vector3, seconds: number)
		local ball = BallSim.newState(start)
		local target = Powers.pullTarget(kind, carCFrame)
		local dt = ballCfg.FixedStep
		for _ = 1, math.floor(seconds / dt) do
			ball.velocity = Powers.applyPull(kind, ball.position, ball.velocity, target, ballCfg.Gravity, dt)
			BallSim.step(arena, ballCfg, ball, dt)
		end
		return ball, target
	end

	t.test("a magnet drags the ball to the front of the car and holds it there", function()
		local car = CFrame.new(0, 2.3, 0) -- facing -Z
		local ball, target = pulled("magnet", car, Vector3.new(30, ballCfg.Radius, -40), 4)
		expect.atMost((ball.position - Vector3.new(target.X, ball.position.Y, target.Z)).Magnitude, 3)
		expect.atMost(ball.velocity.Magnitude, 8, "it settles instead of orbiting")
		expect.truthy(ball.position.Z < 0, "in front of the car")
	end)

	t.test("a tractor beam lifts the ball up in front of the car", function()
		local car = CFrame.new(0, 2.3, 0)
		local ball, target = pulled("beam", car, Vector3.new(-20, ballCfg.Radius, -25), 2.5)
		expect.atMost((ball.position - target).Magnitude, 4)
		expect.atLeast(ball.position.Y, ballCfg.Radius + 6, "the ball is off the ground")
	end)

	t.test("a pull does nothing to a ball out of range", function()
		local car = CFrame.new(0, 2.3, 0)
		local far = Vector3.new(0, ballCfg.Radius, T.MagnetRange + 40)
		local velocity = Vector3.new(3, 0, 0)
		local target = Powers.pullTarget("magnet", car)
		expect.equal(Powers.applyPull("magnet", far, velocity, target, ballCfg.Gravity, 1 / 60), velocity)
	end)

	t.test("launches go the right way", function()
		local car = CFrame.new(0, 2.3, 0) * CFrame.Angles(0, math.rad(90), 0) -- facing -X
		local falling = Vector3.new(0, -30, 0)
		local spring = Powers.launch("spring", car, falling)
		assert(spring)
		expect.near((falling + spring).Y, T.SpringLaunch, 1e-4, "same bounce even when falling")
		local nitro = Powers.launch("nitro", car, Vector3.zero)
		assert(nitro)
		expect.near(nitro.X, -T.NitroBurst, 1e-3)
		expect.equal(Powers.launch("magnet", car, Vector3.zero), nil)
	end)

	t.test("a ground pound shoves things away, harder up close", function()
		local centre = Vector3.new(0, 2, 0)
		local near = Powers.poundPush(centre, Vector3.new(5, 2, 0), 30, 70, 30)
		local far = Powers.poundPush(centre, Vector3.new(25, 2, 0), 30, 70, 30)
		assert(near and far)
		expect.atLeast(near.X, 50)
		expect.truthy(near.X > far.X, "fades with distance")
		expect.atLeast(far.Y, 1, "pops things up")
		expect.equal(Powers.poundPush(centre, Vector3.new(40, 2, 0), 30, 70, 30), nil)
	end)

	t.test("traps catch cars that drive over them, on the floor and on walls", function()
		local floor = Vector3.new(10, 0, 10)
		expect.truthy(Powers.inHazard("cheese", floor, Vector3.yAxis, Vector3.new(15, 2.3, 14)))
		expect.falsy(Powers.inHazard("cheese", floor, Vector3.yAxis, Vector3.new(30, 2.3, 10)))
		expect.falsy(Powers.inHazard("peel", floor, Vector3.yAxis, Vector3.new(10, 20, 10)), "flying over it")
		expect.truthy(Powers.inHazard("peel", floor, Vector3.yAxis, Vector3.new(12, 2.3, 11)))
		-- A peel on the +X wall, facing -X: a car driving along the wall 2 studs out.
		local wall = Vector3.new(110, 20, 0)
		expect.truthy(Powers.inHazard("peel", wall, -Vector3.xAxis, Vector3.new(108, 22, 1)))
		expect.falsy(Powers.inHazard("peel", wall, -Vector3.xAxis, Vector3.new(80, 22, 1)))
		-- A ketchup slick is long and thin: it catches cars along its length, not beside it.
		local slick = Vector3.new(0, 0, 0)
		local along = Vector3.zAxis
		expect.truthy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(0.5, 2.3, 8), along))
		expect.falsy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(6, 2.3, 0), along))
		expect.falsy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(0, 2.3, 14), along))
	end)

	t.test("bots use items and powers when they make sense", function()
		local view: Powers.BotView = {
			role = "attack",
			ballDistance = 30,
			ballHeight = 6,
			ballInFront = true,
			shotLinedUp = true,
			nearestEnemy = 100,
			enemyBehind = false,
			heldFor = 0,
		}
		expect.truthy(Powers.botWantsItem("magnet", view))
		expect.falsy(Powers.botWantsItem("freeze", view), "nobody close to freeze")
		expect.falsy(Powers.botWantsItem("spring", view), "ball's on the ground")
		expect.falsy(Powers.botWantsPower("peel", view), "nobody behind to trip")
		expect.truthy(Powers.botWantsPower("beam", view))
		local chased = table.clone(view)
		chased.enemyBehind = true
		chased.nearestEnemy = 20
		expect.truthy(Powers.botWantsPower("cheese", chased))
		expect.truthy(Powers.botWantsItem("freeze", chased))
		expect.truthy(Powers.botWantsItem("shield", chased))
		local bored = table.clone(view)
		bored.role = "defend"
		bored.heldFor = 9
		expect.truthy(Powers.botWantsItem("rocket", bored), "uses it eventually")
	end)
end
