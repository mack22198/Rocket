-- Ultimates: every car has its own, the meter fills at a sensible pace, the Tractor Beam really brings the
-- ball in and holds it, launches and ground pounds push the right way, and traps catch the right cars.
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local Powers = require(Shared.Config.Powers)

return function(t)
	local expect = t.expect
	local T = Powers.Tuning
	local U = GameConfig.Ultimate

	t.test("every car has its own ultimate", function()
		local seen: { [string]: boolean } = {}
		for _, def in CarCatalog.ordered() do
			local power = Powers.CarPowers[def.Id]
			assert(power, `{def.Id} has no ultimate`)
			expect.falsy(seen[power.Id], `{power.Id} is used by two cars`)
			seen[power.Id] = true
			expect.atLeast(power.Duration, 0)
			expect.truthy(#power.Description > 10)
			-- A fused car's combo does two ultimates at once, so its meter fills a little slower.
			local rate = Powers.chargeRate(power)
			if power.Combo then
				expect.equal(#Powers.components(power), 2, `{power.Id} is two ultimates`)
				expect.truthy(rate < 1 and rate >= 0.6, `{power.Id} charges a little slower`)
			else
				expect.equal(rate, 1)
			end
		end
		for _, id in GameConfig.Bots.CarIds do
			expect.truthy(Powers.CarPowers[id] ~= nil, `bot car {id} has an ultimate`)
		end
	end)

	t.test("the meter fills at a sensible pace", function()
		-- By itself, about once every minute and a half; playing the ball makes it come much sooner.
		local alone = (U.Max - U.Start) / U.PerSecond
		expect.atLeast(alone, 60)
		expect.atMost(alone, 120)
		expect.truthy(alone / (1 + U.BehindBonus) < alone * 0.8, "a team that's behind charges faster")
		local busy = (U.Max - U.Start - 8 * U.PerTouch - U.Orb) / U.PerSecond
		expect.atMost(busy, alone * 0.5, "eight touches and an orb halve the wait")
		expect.truthy(U.Orb < U.Max / 2, "an orb is a big chunk, not a whole ultimate")
		expect.truthy(U.PerStyleTouch > U.PerTouch and U.PerGoal > U.PerShot, "better plays charge more")
		expect.atLeast(U.TouchGap, 0.5, "pushing the ball along can't fill it in a flash")
	end)

	local arena = ArenaShape.new(GameConfig.Arena)
	local ballCfg = GameConfig.Ball

	-- Runs the ball with a Tractor Beam from the car at `carCFrame` for `seconds`.
	local function pulled(carCFrame: CFrame, start: Vector3, seconds: number)
		local ball = BallSim.newState(start)
		local target = Powers.pullTarget(carCFrame)
		local dt = ballCfg.FixedStep
		for _ = 1, math.floor(seconds / dt) do
			ball.velocity = Powers.applyPull(ball.position, ball.velocity, target, ballCfg.Gravity, dt)
			BallSim.step(arena, ballCfg, ball, dt)
		end
		return ball, target
	end

	t.test("a tractor beam lifts the ball up in front of the car and holds it there", function()
		local car = CFrame.new(0, 2.3, 0) -- facing -Z
		local ball, target = pulled(car, Vector3.new(-20, ballCfg.Radius, -25), 2.5)
		expect.atMost((ball.position - target).Magnitude, 4)
		expect.atLeast(ball.position.Y, ballCfg.Radius + 6, "the ball is off the ground")
		expect.truthy(ball.position.Z < 0, "in front of the car")
		local settled = pulled(car, Vector3.new(30, ballCfg.Radius, -40), 4)
		expect.atMost(settled.velocity.Magnitude, 8, "it settles instead of orbiting")
	end)

	t.test("a tractor beam does nothing to a ball out of range", function()
		local car = CFrame.new(0, 2.3, 0)
		local far = Vector3.new(0, ballCfg.Radius, T.BeamRange + 40)
		local velocity = Vector3.new(3, 0, 0)
		local target = Powers.pullTarget(car)
		expect.equal(Powers.applyPull(far, velocity, target, ballCfg.Gravity, 1 / 60), velocity)
	end)

	t.test("launches go the right way", function()
		local car = CFrame.new(0, 2.3, 0) * CFrame.Angles(0, math.rad(90), 0) -- facing -X
		local nitro = Powers.launch("nitro", car)
		assert(nitro)
		expect.near(nitro.X, -T.NitroBurst, 1e-3)
		local dive = Powers.launch("dive", car)
		assert(dive)
		expect.near(dive.X, -T.DiveBurst, 1e-3)
		expect.equal(Powers.launch("cheese", car), nil)
	end)

	t.test("only a Nitro Rocket is fast enough to demolish", function()
		local fastest = 0
		for _, def in CarCatalog.ordered() do
			fastest = math.max(fastest, GameConfig.Car.MaxSpeed * def.Stats.Speed)
		end
		expect.truthy(GameConfig.Bump.DemoSpeed > fastest, "driving flat out isn't enough")
		local rocket = math.min(GameConfig.Car.MaxSpeed + T.NitroBurst, GameConfig.Car.MaxBoostedSpeed)
		expect.truthy(rocket > GameConfig.Bump.DemoSpeed + 10, "a Nitro Rocket gets there")
	end)

	t.test("a banana storm spreads its peels side to side", function()
		local offsets = Powers.peelOffsets()
		expect.equal(#offsets, T.PeelCount)
		local sum = 0
		for i, offset in offsets do
			sum += offset
			if i > 1 then
				expect.near(offset - offsets[i - 1], T.PeelSpread, 1e-6)
			end
		end
		expect.near(sum, 0, 1e-6, "centred behind the car")
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
		local halfLength = T.KetchupLength / 2
		expect.truthy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(0.5, 2.3, halfLength - 2), along))
		expect.falsy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(6, 2.3, 0), along))
		expect.falsy(Powers.inHazard("ketchup", slick, Vector3.yAxis, Vector3.new(0, 2.3, halfLength + 3), along))
	end)

	t.test("bots use their ultimate when it makes sense", function()
		local view: Powers.BotView = {
			role = "attack",
			ballDistance = 30,
			ballHeight = 6,
			ballInFront = true,
			shotLinedUp = true,
			nearestEnemy = 100,
			enemyBehind = false,
			readyFor = 0,
		}
		expect.falsy(Powers.botWantsPower("peel", view), "nobody behind to trip")
		expect.falsy(Powers.botWantsPower("quack", view), "nobody close to quack at")
		expect.truthy(Powers.botWantsPower("beam", view))
		expect.truthy(Powers.botWantsPower("hotsauce", view))
		local chased = table.clone(view)
		chased.enemyBehind = true
		chased.nearestEnemy = 20
		expect.truthy(Powers.botWantsPower("cheese", chased))
		expect.truthy(Powers.botWantsPower("quack", chased))
		local bored = table.clone(view)
		bored.role = "defend"
		bored.readyFor = 13
		expect.truthy(Powers.botWantsPower("peel", bored), "uses it eventually")
	end)
end
