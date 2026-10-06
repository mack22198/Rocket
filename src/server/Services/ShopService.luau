--!strict
-- The Robux shop (see Shop): Scrap packs and the Gold Season Pass (Developer Products), VIP (a Game Pass), and the
-- Premium bonus.
--
-- Developer Product purchases come through ProcessReceipt. Each one is handed out once: the purchase id is saved
-- with the player's data in the same save as what they bought, and Roblox is only told the purchase is done once
-- that save is safely stored. If anything goes wrong (the save fails, the player has left), Roblox asks again
-- later, and the saved purchase id stops it being handed out twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Shop = require(Shared.Config.Shop)

local DataService = require(script.Parent.DataService)
local ProgressService = require(script.Parent.ProgressService)
local SeasonService = require(script.Parent.SeasonService)

type SavedData = DataService.SavedData

local ShopService = {}

local prices: { [string]: number } = {} -- product / pass id -> the price Roblox says it has

-- Hands a product over. Returns what they got, in a few words. (Call inside DataService.update.)
local function grant(data: SavedData, product: Shop.Product): string
	if product.Kind == "goldpass" then
		local paid = SeasonService.unlockGold(data)
		if not paid then
			data.scrap += Shop.GoldPassRefund
			return `You already had the Gold Pass, so here's 🔩 {Shop.GoldPassRefund} Scrap instead!`
		end
		return if #paid > 0
			then `🏆 Gold Season Pass! {#paid} gold rewards unlocked straight away!`
			else "🏆 Gold Season Pass! Every tier now has a gold reward too."
	end
	data.scrap += product.Amount
	return `{product.Emoji} +{product.Amount} Scrap!`
end

-- Gives VIP (and its hat) when they have the Game Pass.
local function setVip(player: Player, vip: boolean)
	player:SetAttribute(MatchState.PlayerAttr.Vip, vip)
	if not DataService.get(player) then
		return
	end
	DataService.update(player, function(data)
		data.vip = vip
		local hat = Cosmetics.get(Shop.Vip.Hat)
		if vip and hat then
			data.style.owned[hat.Id] = true
		end
	end)
	if vip then
		task.defer(ProgressService.check, player)
	end
end

local function checkVip(player: Player)
	if Shop.Vip.PassId <= 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Shop.Vip.PassId)
	end)
	if ok then
		setVip(player, owns == true)
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = Shop.fromProductId(receipt.ProductId)
	if not player or not product then
		if not product then
			warn(`[Shop] A purchase of product {receipt.ProductId} doesn't match anything in Shop.luau.`)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if data.purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- handed out already
	end
	local studio = RunService:IsStudio()
	if not DataService.isPersistent(player) and not studio then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- can't save it right now; Roblox will ask again
	end
	local message = ""
	DataService.update(player, function(saved)
		message = grant(saved, product)
		saved.purchases[purchaseId] = os.time()
		Shop.trimReceipts(saved.purchases)
	end)
	if DataService.isPersistent(player) and not DataService.saveAndWait(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Remotes.Purchased:FireClient(player, product.Id, message)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Scrap bonuses for every match: VIP and Roblox Premium.
function ShopService.matchBonuses(player: Player): { { label: string, fraction: number } }
	local list = {}
	local data = DataService.get(player)
	if data and data.vip then
		table.insert(list, { label = `{Shop.Vip.Emoji} VIP bonus!`, fraction = Shop.Vip.ScrapBonus })
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		table.insert(list, { label = "⭐ Premium bonus!", fraction = Shop.PremiumBonus })
	end
	return list
end

-- The real Robux prices of everything that's set up (Roblox knows them; the config only has the plan).
local function readPrices()
	for _, product in Shop.Products do
		if product.ProductId > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(product.ProductId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[product.Id] = info.PriceInRobux
			end
		end
	end
	if Shop.Vip.PassId > 0 then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(Shop.Vip.PassId, Enum.InfoType.GamePass)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			prices.vip = info.PriceInRobux
		end
	end
end

local function onShop(player: Player, action: unknown, id: unknown): { [string]: any }
	if action == "prices" then
		return { ok = true, prices = prices }
	elseif action == "studioGrant" and RunService:IsStudio() then
		-- Only in Studio: items that aren't set up yet are handed over so the shop can be tried out.
		if id == "vip" then
			setVip(player, true)
			return { ok = true, message = "💎 You're VIP! (Studio test - nothing was charged.)" }
		end
		local product = Shop.get(if type(id) == "string" then id else nil)
		if not product or not DataService.get(player) then
			return { ok = false }
		end
		local message = ""
		DataService.update(player, function(data)
			message = grant(data, product)
		end)
		return { ok = true, message = `{message} (Studio test - nothing was charged.)` }
	end
	return { ok = false }
end

function ShopService.init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if bought and passId == Shop.Vip.PassId then
			setVip(player, true)
			Remotes.Purchased:FireClient(player, "vip", "💎 Welcome to VIP!")
		end
	end)
	Remotes.Shop.OnServerInvoke = onShop
	DataService.Loaded:Connect(function(player: Player)
		local data = DataService.get(player)
		player:SetAttribute(MatchState.PlayerAttr.Vip, data ~= nil and data.vip)
		task.spawn(checkVip, player)
	end)
	task.spawn(readPrices)
end

return ShopService
