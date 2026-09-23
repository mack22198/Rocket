local Rewards = require(Shared.Config.Rewards)
local CarCatalog = require(Shared.Config.CarCatalog)

return function(t)
	local expect = t.expect

	local function stats(overrides: { [string]: number })
		local s = Rewards.emptyStats()
		for k, v in overrides do
			(s :: any)[k] = v
		end
		return s
	end

	t.test("everyone earns Scrap for finishing a match", function()
		local summary = Rewards.compute(Rewards.emptyStats(), "Loss", false)
		expect.equal(summary.total, Rewards.Scrap.Played)
	end)

	t.test("a typical winning match is worth a few hundred Scrap", function()
		local summary = Rewards.compute(stats({ goals = 1, shots = 3, touches = 22, saves = 1 }), "Win", false)
		local s = Rewards.Scrap
		expect.equal(summary.total, s.Played + s.Win + s.Goal + 3 * s.Shot + 4 + s.Save)
		local sum = 0
		for _, line in summary.lines do
			sum += line.amount
		end
		expect.equal(sum, summary.total)
	end)

	t.test("rewards are capped", function()
		local summary = Rewards.compute(stats({ goals = 30, saves = 30, touches = 500 }), "Win", true)
		expect.equal(summary.total, Rewards.Scrap.MatchCap)
	end)

	t.test("the next goal is the cheapest locked car", function()
		local goal = Rewards.nextGoal({ pizza = true }, 250)
		assert(goal)
		expect.equal(goal.carId, "banana")
		expect.equal(goal.remaining, 50)
		expect.falsy(goal.canAfford)
	end)

	t.test("the next goal says when you can afford it", function()
		local goal = Rewards.nextGoal({ pizza = true, banana = true }, 800)
		assert(goal)
		expect.equal(goal.carId, "kart")
		expect.truthy(goal.canAfford)
		expect.equal(goal.have, goal.price)
	end)

	t.test("no next goal when every car is owned", function()
		local owned = {}
		for _, def in CarCatalog.ordered() do
			owned[def.Id] = true
		end
		expect.equal(Rewards.nextGoal(owned, 0), nil)
	end)

	t.test("the starter car is free and every car has sane stats", function()
		local starter = CarCatalog.get(CarCatalog.StarterId)
		assert(starter)
		expect.equal(starter.Price, 0)
		for _, def in CarCatalog.ordered() do
			for name, value in def.Stats do
				expect.truthy(value >= 0.7 and value <= 1.45, `{def.Id}.{name} = {value} is out of balance`)
			end
		end
	end)
end
