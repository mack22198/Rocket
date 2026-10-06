--!strict
-- The Robux shop. Everything in it is optional - every car, hat and reward in Turbo Ball can be earned by playing -
-- and nothing is random: you always see exactly what you get.
--
-- The items are made on the Creator Dashboard (see the README): the Scrap packs and the Gold Season Pass are
-- Developer Products (they can be bought again; the Gold Pass once per season), and VIP is a Game Pass (bought
-- once, kept forever). Paste each one's ID below. Until an item has an ID it shows as "coming soon" - except in
-- Studio, where BUY simply hands it over so the shop can be tried out.
--
-- Roblox Premium members get +10% Scrap after every match, free.

local Shop = {}

export type Product = {
	Id: string,
	Kind: string, -- "scrap" (a pack of Scrap) or "goldpass" (this season's Gold Season Pass)
	Name: string,
	Emoji: string,
	Amount: number, -- Scrap in a pack
	Bonus: string?, -- the ribbon on its card
	Robux: number, -- the price to set on the Creator Dashboard (the shop shows Roblox's real price once it knows it)
	ProductId: number, -- the Developer Product's ID (0 = not set up yet)
}

Shop.Products = {
	{ Id = "scrap1", Kind = "scrap", Name = "Bag of Scrap", Emoji = "🔩", Amount = 1000, Robux = 49, ProductId = 0 },
	{
		Id = "scrap2",
		Kind = "scrap",
		Name = "Box of Scrap",
		Emoji = "📦",
		Amount = 2500,
		Bonus = "+25% EXTRA",
		Robux = 99,
		ProductId = 0,
	},
	{
		Id = "scrap3",
		Kind = "scrap",
		Name = "Crate of Scrap",
		Emoji = "🧰",
		Amount = 6000,
		Bonus = "+50% EXTRA",
		Robux = 199,
		ProductId = 0,
	},
	{
		Id = "scrap4",
		Kind = "scrap",
		Name = "Truckload of Scrap",
		Emoji = "🚚",
		Amount = 15000,
		Bonus = "+60% EXTRA",
		Robux = 449,
		ProductId = 0,
	},
	{
		Id = "goldpass",
		Kind = "goldpass",
		Name = "Gold Season Pass",
		Emoji = "🏆",
		Amount = 0,
		Robux = 399,
		ProductId = 0,
	},
} :: { Product }

-- VIP: a Game Pass, kept forever.
Shop.Vip = {
	Name = "VIP",
	Emoji = "💎",
	Robux = 249,
	PassId = 0, -- the Game Pass's ID (0 = not set up yet)
	ScrapBonus = 0.2, -- +20% Scrap after every match
	Hat = "diamond", -- a VIP-only hat (see Cosmetics)
	Title = "vip", -- a VIP-only title (see Achievements)
}

Shop.PremiumBonus = 0.1 -- +10% Scrap after every match for Roblox Premium members

-- If someone manages to buy this season's Gold Pass twice, the second one is paid back in Scrap.
Shop.GoldPassRefund = 4000

-- How many past purchases each player's save remembers (so none is ever handed out twice).
Shop.ReceiptHistory = 50

local byId: { [string]: Product } = {}
local byProductId: { [number]: Product } = {}
for _, product in Shop.Products do
	byId[product.Id] = product
	if product.ProductId > 0 then
		byProductId[product.ProductId] = product
	end
end

function Shop.get(id: string?): Product?
	return if id then byId[id] else nil
end

-- The product a Roblox Developer Product ID belongs to.
function Shop.fromProductId(productId: number): Product?
	return byProductId[productId]
end

-- How much Scrap each Robux buys in a pack (bigger packs give more for each Robux).
function Shop.scrapPerRobux(product: Product): number
	return product.Amount / product.Robux
end

-- Keeps only the newest `Shop.ReceiptHistory` purchases (each is purchase id -> when it was handed out).
function Shop.trimReceipts(receipts: { [string]: number })
	local list: { { id: string, time: number } } = {}
	for id, time in receipts do
		table.insert(list, { id = id, time = time })
	end
	if #list <= Shop.ReceiptHistory then
		return
	end
	table.sort(list, function(a, b)
		return a.time > b.time
	end)
	for i = Shop.ReceiptHistory + 1, #list do
		receipts[list[i].id] = nil
	end
end

return Shop
