-- The Robux shop: every product is set up sensibly, bigger packs are better value, nothing is random, the VIP
-- items exist, and purchase receipts are kept short without losing new ones.
local Achievements = require(Shared.Config.Achievements)
local Cosmetics = require(Shared.Config.Cosmetics)
local Shop = require(Shared.Config.Shop)

return function(t)
	local expect = t.expect

	t.test("every product makes sense", function()
		local ids: { [string]: boolean } = {}
		local gold = 0
		for _, product in Shop.Products do
			expect.falsy(ids[product.Id], `{product.Id} is listed twice`)
			ids[product.Id] = true
			expect.truthy(product.Robux > 0, `{product.Id} has a price`)
			expect.truthy(product.ProductId >= 0)
			expect.truthy(product.Kind == "scrap" or product.Kind == "goldpass", `{product.Id} is a known kind`)
			if product.Kind == "scrap" then
				expect.truthy(product.Amount > 0)
			else
				gold += 1
			end
			expect.truthy(Shop.get(product.Id) == product)
		end
		expect.equal(gold, 1, "one Gold Season Pass")
		expect.equal(Shop.get("nope"), nil)
		expect.equal(Shop.fromProductId(0), nil, "items that aren't set up can't be bought")
	end)

	t.test("bigger Scrap packs are better value", function()
		local last = 0
		for _, product in Shop.Products do
			if product.Kind == "scrap" then
				local value = Shop.scrapPerRobux(product)
				expect.truthy(value > last, `{product.Id} gives more Scrap for each Robux`)
				last = value
			end
		end
	end)

	t.test("VIP comes with a real hat and title", function()
		local hat = Cosmetics.get(Shop.Vip.Hat)
		assert(hat, "the VIP hat exists")
		expect.truthy(hat.Vip)
		expect.falsy(Cosmetics.forSale(hat), "and can't be bought with Scrap")
		local title = Achievements.title(Shop.Vip.Title)
		assert(title, "the VIP title exists")
		expect.truthy(title.Vip)
		expect.truthy(Shop.Vip.ScrapBonus > 0 and Shop.Vip.ScrapBonus <= 0.25)
		expect.truthy(Shop.PremiumBonus > 0 and Shop.PremiumBonus <= Shop.Vip.ScrapBonus)
	end)

	t.test("old receipts are forgotten, newest kept", function()
		local receipts: { [string]: number } = {}
		for i = 1, Shop.ReceiptHistory + 20 do
			receipts[`p{i}`] = 1000 + i
		end
		Shop.trimReceipts(receipts)
		local count = 0
		for _ in receipts do
			count += 1
		end
		expect.equal(count, Shop.ReceiptHistory)
		expect.truthy(receipts[`p{Shop.ReceiptHistory + 20}`] ~= nil, "the newest is kept")
		expect.equal(receipts.p1, nil, "the oldest goes")
	end)
end
