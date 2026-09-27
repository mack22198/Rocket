-- Car fusion: every fused car is made from two real cars, sits halfway between them, gets both their powers
-- as a combo, and can only be made when you own both parts and have the Scrap.
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local Powers = require(Shared.Config.Powers)

return function(t)
	local expect = t.expect

	local fused: { CarCatalog.CarDef } = {}
	for _, def in CarCatalog.ordered() do
		if def.Fusion then
			table.insert(fused, def)
		end
	end

	t.test("there are fused cars, listed after all the others", function()
		expect.atLeast(#fused, 3)
		local seenFused = false
		for _, def in CarCatalog.ordered() do
			if def.Fusion then
				seenFused = true
			else
				expect.falsy(seenFused, `{def.Id} comes after a fused car`)
			end
		end
	end)

	for _, def in fused do
		t.test(`{def.Id} is made from two different cars and sits between them`, function()
			local base, flavor = CarCatalog.parents(def)
			assert(base and flavor, "both parts exist")
			expect.truthy(base.Id ~= flavor.Id)
			expect.falsy(base.Fusion ~= nil or flavor.Fusion ~= nil, "fused cars can't be fused again")
			expect.equal(def.Rarity, "Fused")
			expect.equal(def.Price, 0, "fused, not bought")
			expect.atMost((def.Hitbox - base.Hitbox).Magnitude, 1e-6, "the base car's shape")
			for key, value in def.Stats :: any do
				local a, b = (base.Stats :: any)[key], (flavor.Stats :: any)[key]
				expect.atLeast(value, math.min(a, b) - 1e-9, `{key} isn't below both parts`)
				expect.atMost(value, math.max(a, b) + 1e-9, `{key} isn't above both parts`)
			end
			expect.equal(#def.StageNames, 4)
		end)

		t.test(`{def.Id}'s power does both its parts' powers`, function()
			local base, flavor = CarCatalog.parents(def)
			assert(base and flavor)
			local power = Powers.forCar(def.Id)
			expect.truthy(power.Combo ~= nil, "a combo power")
			local parts = Powers.components(power)
			expect.equal(#parts, 2)
			local ids = { [parts[1].Id] = true, [parts[2].Id] = true }
			expect.truthy(ids[Powers.forCar(base.Id).Id], "has the base car's power")
			expect.truthy(ids[Powers.forCar(flavor.Id).Id], "has the flavor car's power")
			for _, part in parts do
				expect.truthy(power.Cooldown > part.Cooldown, "a combo takes longer to recharge")
			end
			expect.equal(Powers.power(power.Id), power)
		end)
	end

	t.test("fusing needs both cars and enough Scrap", function()
		local def = CarCatalog.get("pizzashark")
		assert(def and def.Fusion)
		local cost = def.Fusion.Cost
		local ok, reason = CarCatalog.canFuse(def, { pizza = true }, 99999)
		expect.falsy(ok)
		expect.truthy(reason ~= nil and string.find(reason, "Neon Shark", 1, true) ~= nil, "says which car is missing")
		ok = CarCatalog.canFuse(def, { pizza = true, shark = true }, cost - 1)
		expect.falsy(ok, "not enough Scrap")
		ok, reason = CarCatalog.canFuse(def, { pizza = true, shark = true }, cost)
		expect.truthy(ok)
		expect.equal(reason, nil)
		ok = CarCatalog.canFuse(def, { pizza = true, shark = true, pizzashark = true }, cost)
		expect.falsy(ok, "already made")
		local plain = CarCatalog.get("shark")
		assert(plain)
		ok = CarCatalog.canFuse(plain, { pizza = true, shark = true }, 99999)
		expect.falsy(ok, "only fused cars can be fused")
	end)

	t.test("bots can turn up in fused cars", function()
		expect.truthy(GameConfig.Bots.FusedChance > 0 and GameConfig.Bots.FusedChance < 0.5)
		for _, id in GameConfig.Bots.FusedCarIds do
			local def = CarCatalog.get(id)
			expect.truthy(def ~= nil and def.Fusion ~= nil, `{id} is a fused car`)
		end
	end)

	t.test("an ordinary power is made of just itself", function()
		local cheese = Powers.forCar("pizza")
		local parts = Powers.components(cheese)
		expect.equal(#parts, 1)
		expect.equal(parts[1], cheese)
	end)

	t.test("bots use a combo when either half would help", function()
		local view: Powers.BotView = {
			role = "defend",
			ballDistance = 80,
			ballHeight = 0,
			ballInFront = false,
			shotLinedUp = false,
			nearestEnemy = 200,
			enemyBehind = true,
			heldFor = 0,
		}
		expect.falsy(Powers.botWantsPower("dive", view))
		expect.truthy(Powers.botWantsPower("cheese", view))
		expect.truthy(Powers.botWantsPower("cheesydive", view), "the cheese half is worth it")
		view.enemyBehind = false
		expect.falsy(Powers.botWantsPower("cheesydive", view))
	end)
end
