-- Style items: every kind has a free default, every hat can actually be built, horns have a sound and a word,
-- and season rewards can't be bought.
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local Cosmetics = require(Shared.Config.Cosmetics)

return function(t)
	local expect = t.expect

	t.test("every kind has one free default everyone owns", function()
		local defaults = Cosmetics.defaults()
		for _, kind in Cosmetics.Kinds do
			local id = Cosmetics.defaultFor(kind)
			local def = Cosmetics.get(id)
			assert(def, `{kind} has a default`)
			expect.equal(def.Kind, kind)
			expect.equal(def.Price, 0)
			expect.truthy(defaults[id])
		end
	end)

	t.test("every hat can be built, and nothing else pretends to be one", function()
		local buildable: { [string]: boolean } = {}
		for _, id in CarModelBuilder.hats() do
			buildable[id] = true
		end
		for _, def in Cosmetics.ofKind("topper") do
			if def.Id ~= "none" then
				expect.truthy(buildable[def.Id], `{def.Id} has a builder`)
			end
		end
	end)

	t.test("horns have a sound and a word, and prices make sense", function()
		local ids: { [string]: boolean } = {}
		for _, def in Cosmetics.List do
			expect.falsy(ids[def.Id], `{def.Id} is listed twice`)
			ids[def.Id] = true
			if def.Kind == "horn" then
				expect.truthy(def.Sound ~= nil and def.Word ~= nil, `{def.Id} can be heard`)
			end
			if def.Season or def.Vip then
				expect.falsy(Cosmetics.forSale(def), `{def.Id} is a season reward or comes with VIP`)
			elseif not def.Default then
				expect.truthy(Cosmetics.forSale(def))
				expect.atLeast(def.Price, 100, `{def.Id} costs something`)
			end
		end
	end)
end
