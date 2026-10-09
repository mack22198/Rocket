--!strict
-- The Robux shop (see Shop): this season's Gold Season Pass and VIP side by side at the top, the Scrap packs along
-- the bottom, and a reminder that everything can also be earned by playing. Each card says exactly what you get.
-- Buying opens Roblox's own purchase window; items that aren't set up yet say "coming soon" (in Studio they're
-- handed over for free so the shop can be tried out).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Season = require(Shared.Config.Season)
local Shop = require(Shared.Config.Shop)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local ShopPanel = {}

ShopPanel.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer
local ROBUX = utf8.char(0xE002) -- Roblox draws this as the Robux icon

local gui: ScreenGui
local panel: Frame
local goldButton: TextButton
local goldSeason: TextLabel
local vipButton: TextButton
local packButtons: { [string]: TextButton } = {}
local message: TextLabel
local prices: { [string]: number } = {}
local busy = false

local function priceOf(id: string, planned: number): number
	return prices[id] or planned
end

local function say(text: string, good: boolean)
	message.Text = Theme.noEmoji(text)
	message.TextColor3 = if good then C.GoodText else C.InkMuted
end

local function isVip(): boolean
	return localPlayer:GetAttribute(MatchState.PlayerAttr.Vip) == true or PlayerDataClient.get().vip
end

local function hasGold(): boolean
	local data = PlayerDataClient.get()
	return data.season.gold and data.season.number == Season.at(PlayerDataClient.today()).number
end

-- Not set up on the Creator Dashboard yet: in Studio it's handed over so the shop can be tried; otherwise it's
-- coming soon.
local function notSetUp(id: string)
	if not RunService:IsStudio() then
		say("Coming soon!", false)
		return
	end
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.Shop:InvokeServer("studioGrant", id)
	end)
	busy = false
	if ok and type(result) == "table" and result.ok then
		Toasts.push({
			badge = "R$",
			title = "STUDIO TEST",
			text = Theme.noEmoji(tostring(result.message)),
			color = C.Good,
		})
	end
end

local function buy(product: Shop.Product)
	if product.Kind == "goldpass" and hasGold() then
		say("You have this season's Gold Pass. Enjoy the gold rewards!", true)
		return
	end
	if product.ProductId <= 0 then
		notSetUp(product.Id)
		return
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
	end)
end

local function buyVip()
	if isVip() then
		say("You're already VIP. Thank you!", true)
		return
	end
	if Shop.Vip.PassId <= 0 then
		notSetUp("vip")
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(localPlayer, Shop.Vip.PassId)
	end)
end

local function refresh()
	local gold = Shop.get("goldpass")
	if gold then
		if hasGold() then
			goldButton.Text = "ACTIVE THIS SEASON"
			Theme.setButtonColor(goldButton, C.CardLine, C.GoodText)
		else
			goldButton.Text = `{ROBUX} {priceOf(gold.Id, gold.Robux)}`
			Theme.setButtonColor(goldButton, C.Gold)
		end
	end
	local info = Season.at(PlayerDataClient.today())
	local days = Season.daysLeft(PlayerDataClient.today())
	goldSeason.Text = `SEASON {info.number}: {string.upper(info.theme.Name)}, {days} DAYS LEFT`
	if isVip() then
		vipButton.Text = "YOU'RE VIP"
		Theme.setButtonColor(vipButton, C.CardLine, C.GoodText)
	else
		vipButton.Text = `{ROBUX} {priceOf("vip", Shop.Vip.Robux)}`
		Theme.setButtonColor(vipButton, C.Sky)
	end
	for id, button in packButtons do
		local product = Shop.get(id)
		if product then
			button.Text = `{ROBUX} {priceOf(id, product.Robux)}`
		end
	end
end

-- One line of what you get, with a little square in front.
local function bullet(parent: Instance, y: number, text: string)
	local dot = Instance.new("Frame")
	dot.Name = "Bullet"
	dot.Size = UDim2.fromOffset(8, 8)
	dot.Position = UDim2.fromOffset(18, y + 7)
	dot.Rotation = 45
	dot.BackgroundColor3 = C.Ink
	dot.BorderSizePixel = 0
	dot.Parent = parent
	Theme.label(parent, {
		size = UDim2.new(1, -50, 0, 22),
		position = UDim2.fromOffset(36, y),
		text = text,
		font = Theme.Body,
		align = Enum.TextXAlignment.Left,
		scaled = false,
		textSize = 15,
	})
end

local function bigCard(name: string, size: UDim2, position: UDim2, color: Color3): Frame
	local card = Theme.well(panel, name, size, position)
	card.BackgroundColor3 = color
	Theme.stroke(card, C.Ink, 3)
	return card
end

-- A price button (Roblox draws the Robux icon in Gotham, so price buttons use it).
local function priceButton(parent: Instance, width: number, height: number, color: Color3): TextButton
	return Theme.button(parent, {
		name = "Buy",
		size = UDim2.fromOffset(width, height),
		position = UDim2.new(0.5, 0, 1, -14),
		anchor = Vector2.new(0.5, 1),
		text = "",
		color = color,
		font = Theme.Title,
		textSize = math.floor(height * 0.44),
	})
end

local function build()
	gui = Theme.screen("TurboShop", 42)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(6, 8, 18)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	panel = Theme.card(gui, "Shop", UDim2.fromOffset(1000, 624), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 20)
	Theme.heading(panel, {
		name = "Title",
		size = UDim2.fromOffset(300, 46),
		text = "SHOP",
		textSize = 46,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, {
		name = "Subtitle",
		size = UDim2.fromOffset(700, 18),
		position = UDim2.fromOffset(2, 50),
		text = "Everything in Turbo Ball can also be earned by playing. Ask a grown-up before you buy!",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 15,
		align = Enum.TextXAlignment.Left,
	})
	local close = Theme.button(panel, {
		name = "Close",
		size = UDim2.fromOffset(120, 50),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "BACK",
		color = C.Panel,
		textSize = 22,
	})
	close.Activated:Connect(function()
		ShopPanel.close()
	end)

	-- The Gold Season Pass.
	local gold = bigCard("GoldPass", UDim2.new(0.6, -6, 0, 276), UDim2.fromOffset(0, 84), rgb(255, 232, 160))
	Theme.heading(gold, {
		size = UDim2.new(1, -32, 0, 32),
		position = UDim2.fromOffset(16, 14),
		text = "GOLD SEASON PASS",
		textSize = 32,
		align = Enum.TextXAlignment.Left,
	})
	goldSeason = Theme.label(gold, {
		size = UDim2.new(1, -32, 0, 14),
		position = UDim2.fromOffset(17, 50),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	local function itemName(id: string): string
		local item = Cosmetics.get(id)
		return if item then item.Name else id
	end
	bullet(gold, 74, "A gold reward on every tier, on top of the free one")
	bullet(gold, 98, `Gold-only: {itemName("airhorn")}, {itemName("goldrush")}, {itemName("trophy")}`)
	local extraScrap, extraBoosts = 0, 0
	for _, reward in Season.at(PlayerDataClient.today()).theme.GoldRewards do
		if reward.Kind == "scrap" then
			extraScrap += reward.Amount
		elseif reward.Kind == "boost" then
			extraBoosts += reward.Amount
		end
	end
	bullet(gold, 122, `{Theme.formatNumber(extraScrap)} extra Scrap and {extraBoosts} Double Scrap matches`)
	bullet(gold, 146, "Tiers you've already reached pay their gold rewards right away")
	bullet(gold, 170, "Lasts this whole season (each season has its own pass)")
	goldButton = priceButton(gold, 260, 56, C.Gold)
	goldButton.Activated:Connect(function()
		local product = Shop.get("goldpass")
		if product then
			buy(product)
		end
	end)
	Theme.sweep(goldButton, 3)

	-- VIP.
	local vip = bigCard("Vip", UDim2.new(0.4, -6, 0, 276), UDim2.new(0.6, 6, 0, 84), rgb(206, 234, 255))
	Theme.heading(vip, {
		size = UDim2.new(1, -32, 0, 32),
		position = UDim2.fromOffset(16, 14),
		text = "VIP",
		textSize = 32,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(vip, {
		size = UDim2.new(1, -32, 0, 14),
		position = UDim2.fromOffset(17, 50),
		text = "YOURS FOREVER",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	bullet(vip, 74, `+{math.floor(Shop.Vip.ScrapBonus * 100)}% Scrap after every match`)
	bullet(vip, 98, `The {itemName(Shop.Vip.Hat)} hat`)
	bullet(vip, 122, "The VIP title by your name")
	vipButton = priceButton(vip, 220, 56, C.Sky)
	vipButton.Activated:Connect(buyVip)

	-- Scrap packs.
	local row = Instance.new("Frame")
	row.Name = "Packs"
	row.Size = UDim2.new(1, 0, 0, 176)
	row.Position = UDim2.fromOffset(0, 378)
	row.BackgroundTransparency = 1
	row.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.25, -9, 1, 0)
	layout.CellPadding = UDim2.fromOffset(12, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for order, product in Shop.Products do
		if product.Kind ~= "scrap" then
			continue
		end
		local card = Theme.well(row, product.Id, UDim2.new(), UDim2.new())
		card.LayoutOrder = order
		Theme.stroke(card, C.Ink, 2)
		Theme.label(card, {
			size = UDim2.fromOffset(60, 44),
			position = UDim2.new(0.5, 0, 0, 14),
			anchor = Vector2.new(0.5, 0),
			text = product.Emoji,
			textSize = 38,
		})
		local amount = Theme.amount(card, 26, UDim2.new(0.5, 0, 0, 62), Vector2.new(0.5, 0))
		amount.set(product.Amount)
		Theme.label(card, {
			size = UDim2.new(1, -16, 0, 14),
			position = UDim2.fromOffset(8, 92),
			text = product.Name,
			font = Theme.Body,
			color = C.InkMuted,
			textSize = 13,
		})
		if product.Bonus then
			local ribbon = Theme.pill(card, {
				size = UDim2.new(1, -28, 0, 22),
				position = UDim2.new(0.5, 0, 0, -11),
				anchor = Vector2.new(0.5, 0),
				text = product.Bonus,
				background = C.Good,
			})
			ribbon.ZIndex = 3
		end
		local button = priceButton(card, 160, 48, C.Good)
		button.Size = UDim2.new(1, -24, 0, 48)
		button.Activated:Connect(function()
			buy(product)
		end)
		packButtons[product.Id] = button
	end

	message = Theme.label(panel, {
		name = "Message",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.new(0, 0, 1, -18),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 15,
	})
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local function loadPrices()
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.Shop:InvokeServer("prices")
		end)
		if ok and type(result) == "table" and type(result.prices) == "table" then
			for id, price in result.prices do
				if type(id) == "string" and type(price) == "number" then
					prices[id] = price
				end
			end
			if gui.Enabled then
				refresh()
			end
		end
	end)
end

function ShopPanel.open()
	gui.Enabled = true
	say(`Roblox Premium members get +{math.floor(Shop.PremiumBonus * 100)}% Scrap after every match.`, false)
	refresh()
	loadPrices()
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
	Theme.focus(goldButton)
end

function ShopPanel.close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		ShopPanel.Closed:Fire()
	end
end

function ShopPanel.isOpen(): boolean
	return gui.Enabled
end

function ShopPanel.start()
	build()
	PlayerDataClient.Changed:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
	localPlayer:GetAttributeChangedSignal(MatchState.PlayerAttr.Vip):Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
	-- A purchase went through: say thanks and what they got.
	Remotes.Purchased.OnClientEvent:Connect(function(_id: unknown, text: unknown)
		Toasts.push({
			badge = "R$",
			title = "THANK YOU!",
			text = if type(text) == "string" then Theme.noEmoji(text) else "Your purchase is ready.",
			color = C.Good,
		})
		if gui.Enabled then
			refresh()
		end
	end)
end

return ShopPanel
