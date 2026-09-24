-- Car evolution rules: XP thresholds, progress toward the next look, and bot looks.
local CarCatalog = require(Shared.Config.CarCatalog)
local Evolution = require(Shared.Config.Evolution)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local cfg = GameConfig.Evolution
	local pizza = CarCatalog.get("pizza")
	assert(pizza)

	t.test("every car has a name for every stage", function()
		for _, def in CarCatalog.ordered() do
			expect.equal(#def.StageNames, cfg.Stages, `{def.Id} stage names`)
			expect.equal(CarCatalog.stageName(def, 1), def.DisplayName)
		end
		expect.equal(CarCatalog.stageName(pizza, 2), "Burnt Pizza Car")
		expect.equal(CarCatalog.stageName(pizza, 99), "Galaxy Pizza Car")
	end)

	t.test("XP thresholds only go up", function()
		expect.equal(cfg.Xp[1], 0)
		for stage = 2, cfg.Stages do
			expect.truthy(cfg.Xp[stage] > cfg.Xp[stage - 1], `stage {stage} needs more XP than stage {stage - 1}`)
		end
	end)

	t.test("XP decides how far a car may evolve", function()
		expect.equal(Evolution.stageAllowed(0), 1)
		expect.equal(Evolution.stageAllowed(cfg.Xp[2] - 1), 1)
		expect.equal(Evolution.stageAllowed(cfg.Xp[2]), 2)
		expect.equal(Evolution.stageAllowed(cfg.Xp[cfg.Stages] * 10), cfg.Stages)
	end)

	t.test("progress counts toward the next stage and says when it's ready", function()
		local halfway = (cfg.Xp[1] + cfg.Xp[2]) / 2
		local p = Evolution.progress(pizza, halfway, 1)
		expect.equal(p.nextStage, 2)
		expect.equal(p.nextName, "Burnt Pizza Car")
		expect.near(p.fraction, 0.5, 1e-6)
		expect.falsy(p.ready)

		local ready = Evolution.progress(pizza, cfg.Xp[2], 1)
		expect.truthy(ready.ready)
		expect.equal(ready.fraction, 1)

		-- XP beyond the next stage doesn't skip a stage: you evolve one step at a time.
		local lots = Evolution.progress(pizza, cfg.Xp[cfg.Stages], 1)
		expect.equal(lots.nextStage, 2)
		expect.truthy(lots.ready)
	end)

	t.test("a fully evolved car has nothing left to do", function()
		local p = Evolution.progress(pizza, 0, cfg.Stages)
		expect.equal(p.nextStage, nil)
		expect.falsy(p.ready)
		expect.equal(p.fraction, 1)
	end)

	t.test("bots mostly drive plain cars but sometimes show off evolved ones", function()
		local seen = {}
		for i = 0, 999 do
			local stage = Evolution.botStage(i / 1000)
			expect.truthy(stage >= 1 and stage <= cfg.Stages)
			seen[stage] = (seen[stage] or 0) + 1
		end
		for stage = 1, cfg.Stages do
			expect.truthy((seen[stage] or 0) > 0, `bots never use stage {stage}`)
		end
		expect.truthy(seen[1] > seen[cfg.Stages], "plain cars should be the most common")
	end)
end
