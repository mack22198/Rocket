--!strict
-- The season's reward track (see Season): every tier in a row you can scroll along, with its free reward on top
-- and its Gold Pass reward underneath - what you've already got, what's next and how far away it is. Rewards pay
-- out on their own after matches; this screen is for looking forward to them (and getting the Gold Pass).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Season = require(Shared.Config.Season)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local SeasonTrack = {}

SeasonTrack.Closed = Signal.new() :: Signal.Signal<>
-- GET THE GOLD PASS was pressed (GameFlow opens the shop).
SeasonTrack.GoldPressed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

local CARD_WIDTH = 132
local CARD_GAP = 10
local FREE_HEIGHT = 170
local GOLD_HEIGHT = 140
local GOLD_CARD = rgb(255, 224, 140) -- the Gold Pass row

type Card = {
	frame: Frame,
	free: Frame,
	stroke: UIStroke,
	tier: TextLabel,
	icon: TextLabel,
	coin: Frame,
	name: TextLabel,
	status: TextLabel,
	ribbon: TextLabel,
	gold: Frame,
	goldStroke: UIStroke,
	goldIcon: TextLabel,
	goldCoin: Frame,
	goldName: TextLabel,
	goldStatus: TextLabel,
	goldRibbon: TextLabel,
}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local descriptionLabel: TextLabel
local daysPill: TextLabel
local tierLabel: TextLabel
local xpBar: Theme.Bar
local xpLabel: TextLabel
local track: ScrollingFrame
local cards: { Card } = {}
local bonusCard: Frame
local bonusText: TextLabel
local goldButton: TextButton
local howItWorks: TextLabel

-- Is this reward Scrap (shown with the Scrap coin rather than a picture)?
local function isScrap(reward: Season.Reward): boolean
	return reward.Kind ~= "boost" and reward.Kind ~= "style"
end

-- The picture, name and status of one reward (the free one or the gold one under it).
local function rewardFace(parent: Frame, top: number): (TextLabel, Frame, TextLabel, TextLabel)
	local icon = Theme.label(parent, {
		name = "Icon",
		size = UDim2.new(1, 0, 0, 50),
		position = UDim2.fromOffset(0, top),
		text = "",
		textSize = 42,
	})
	local coin = Theme.scrapIcon(parent, 44, UDim2.new(0.5, 0, 0, top + 3), Vector2.new(0.5, 0))
	local name = Theme.label(parent, {
		name = "Reward",
		size = UDim2.new(1, -14, 0, 32),
		position = UDim2.fromOffset(7, top + 56),
		text = "",
		textSize = 14,
	})
	local status = Theme.pill(parent, {
		name = "Status",
		size = UDim2.fromOffset(84, 22),
		position = UDim2.new(0.5, 0, 1, -12),
		anchor = Vector2.new(0.5, 1),
		text = "",
	})
	return icon, coin, name, status
end

local function makeCard(order: number): Card
	local column = Instance.new("Frame")
	column.Name = `Tier{order}`
	column.LayoutOrder = order
	column.Size = UDim2.fromOffset(CARD_WIDTH, FREE_HEIGHT + 12 + GOLD_HEIGHT)
	column.BackgroundTransparency = 1
	column.Parent = track
	local free = Theme.well(column, "Free", UDim2.new(1, 0, 0, FREE_HEIGHT), UDim2.new())
	local stroke = Theme.stroke(free, C.Ink, 2)
	local tier = Theme.label(free, {
		name = "Tier",
		size = UDim2.new(1, -12, 0, 14),
		position = UDim2.fromOffset(6, 12),
		text = `TIER {order}`,
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
	})
	local icon, coin, name, status = rewardFace(free, 32)
	local ribbon = Theme.pill(free, {
		name = "Ribbon",
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.new(0.5, 0, 0, -10),
		anchor = Vector2.new(0.5, 0),
		text = "SEASON ONLY",
		background = C.Evolve,
	})
	ribbon.ZIndex = 3

	local gold = Theme.well(column, "Gold", UDim2.new(1, 0, 0, GOLD_HEIGHT), UDim2.fromOffset(0, FREE_HEIGHT + 12))
	gold.BackgroundColor3 = GOLD_CARD
	local goldStroke = Theme.stroke(gold, C.Ink, 2)
	local goldIcon, goldCoin, goldName, goldStatus = rewardFace(gold, 16)
	local goldRibbon = Theme.pill(gold, {
		name = "Ribbon",
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.new(0.5, 0, 0, -10),
		anchor = Vector2.new(0.5, 0),
		text = "GOLD",
		background = C.Gold,
	})
	goldRibbon.ZIndex = 3
	return {
		frame = column,
		free = free,
		stroke = stroke,
		tier = tier,
		icon = icon,
		coin = coin,
		name = name,
		status = status,
		ribbon = ribbon,
		gold = gold,
		goldStroke = goldStroke,
		goldIcon = goldIcon,
		goldCoin = goldCoin,
		goldName = goldName,
		goldStatus = goldStatus,
		goldRibbon = goldRibbon,
	}
end

-- Makes sure there's a card for each of `count` tiers.
local function ensureCards(count: number)
	while #cards < count do
		table.insert(cards, makeCard(#cards + 1))
	end
	for i, card in cards do
		card.frame.Visible = i <= count
	end
	bonusCard.LayoutOrder = count + 1
end

-- Shows a reward on a card: its picture (or the Scrap coin) and its name.
local function showReward(icon: TextLabel, coin: Frame, name: TextLabel, reward: Season.Reward)
	local emoji, text = Season.describe(reward)
	local scrap = isScrap(reward)
	icon.Visible = not scrap
	coin.Visible = scrap
	icon.Text = emoji
	name.Text = Theme.noEmoji(text)
end

local function refresh()
	local data = PlayerDataClient.get()
	local day = PlayerDataClient.today()
	local info = Season.at(day)
	local theme = info.theme
	local state = data.season
	local current = state.number == info.number
	local tier = if current then state.tier else 0
	local xp = if current then state.xp else 0
	local hasGold = current and state.gold

	titleLabel.Text = `SEASON {info.number}: {string.upper(theme.Name)}`
	descriptionLabel.Text = theme.Description
	local days = Season.daysLeft(day)
	daysPill.Text = if days <= 1 then "LAST DAY!" else `{days} DAYS LEFT`
	daysPill.BackgroundColor3 = if days <= 3 then C.Bad else C.Ink

	tierLabel.Text = `TIER {tier}`
	local into = xp - tier * Season.XpPerTier
	xpBar.set(into / Season.XpPerTier)
	xpBar.fill.BackgroundColor3 = theme.Color
	xpLabel.Text = `{Theme.formatNumber(into)}/{Theme.formatNumber(Season.XpPerTier)} XP TO TIER {tier + 1}`

	local count = #theme.Rewards
	ensureCards(count)
	local pulse = math.floor(os.clock() * 2) % 2 == 0
	for i = 1, count do
		local card = cards[i]
		local reward = Season.rewardFor(theme, i)
		local got = i <= tier
		local isNext = i == tier + 1
		showReward(card.icon, card.coin, card.name, reward)
		card.ribbon.Visible = reward.Kind == "style"
		card.free.BackgroundColor3 = if isNext then C.Gold elseif got then C.Card else C.CardShade
		card.stroke.Thickness = if isNext then (if pulse then 4 else 3) else 2
		card.status.Visible = got or isNext
		card.status.Text = if got then "GOT IT" else "NEXT"
		card.status.BackgroundColor3 = if got then C.Good else C.Ink
		card.tier.TextColor3 = if isNext then C.Ink else C.InkMuted
		card.icon.TextTransparency = if got or isNext then 0 else 0.35

		-- The gold reward underneath.
		local goldReward = Season.goldRewardFor(theme, i)
		showReward(card.goldIcon, card.goldCoin, card.goldName, goldReward)
		card.goldRibbon.Text = if goldReward.Kind == "style" then "GOLD ONLY" else "GOLD"
		local goldGot = hasGold and got
		card.gold.BackgroundTransparency = if hasGold then 0 else 0.45
		card.goldStroke.Thickness = if hasGold and isNext then (if pulse then 4 else 3) else 2
		card.goldIcon.TextTransparency = if hasGold then 0 else 0.45
		card.goldName.TextTransparency = if hasGold then 0 else 0.4
		card.goldStatus.Visible = goldGot or not hasGold or isNext
		card.goldStatus.Text = if goldGot then "GOT IT" elseif hasGold then "NEXT" else "GOLD PASS"
		card.goldStatus.BackgroundColor3 = if goldGot then C.Good else C.Ink
	end
	bonusText.Text = `Every tier after {count}: {Season.BonusScrap} Scrap, and {Season.GoldBonusScrap} more with Gold`
	goldButton.Visible = not hasGold
	howItWorks.Size = if hasGold then UDim2.new(1, 0, 0, 40) else UDim2.new(1, -300, 0, 40)
end

local function build()
	gui = Theme.screen("TurboSeason", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(6, 8, 18)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	panel = Theme.card(gui, "Season", UDim2.fromOffset(1000, 616), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 20)
	titleLabel = Theme.heading(panel, {
		name = "Title",
		size = UDim2.fromOffset(600, 42),
		text = "",
		textSize = 40,
		align = Enum.TextXAlignment.Left,
	})
	descriptionLabel = Theme.label(panel, {
		name = "Description",
		size = UDim2.fromOffset(640, 18),
		position = UDim2.fromOffset(2, 48),
		text = "",
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
		SeasonTrack.close()
	end)
	daysPill = Theme.pill(panel, {
		name = "Days",
		size = UDim2.fromOffset(150, 30),
		position = UDim2.new(1, -136, 0, 10),
		anchor = Vector2.new(1, 0),
		text = "",
	})

	-- Your progress this season.
	tierLabel = Theme.heading(panel, {
		name = "Tier",
		size = UDim2.fromOffset(180, 34),
		position = UDim2.fromOffset(0, 80),
		text = "",
		textSize = 34,
		align = Enum.TextXAlignment.Left,
	})
	xpBar = Theme.bar(panel, UDim2.new(1, -200, 0, 18), UDim2.fromOffset(196, 82), C.Gold, C.CardLine)
	xpLabel = Theme.label(panel, {
		name = "Xp",
		size = UDim2.new(1, -200, 0, 14),
		position = UDim2.fromOffset(196, 106),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Left,
	})

	track = Instance.new("ScrollingFrame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, FREE_HEIGHT + GOLD_HEIGHT + 52)
	track.Position = UDim2.fromOffset(0, 138)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollBarThickness = 8
	track.ScrollBarImageColor3 = C.Ink
	track.ScrollingDirection = Enum.ScrollingDirection.X
	track.AutomaticCanvasSize = Enum.AutomaticSize.X
	track.CanvasSize = UDim2.new()
	track.Parent = panel
	local trackPadding = Instance.new("UIPadding")
	trackPadding.PaddingTop = UDim.new(0, 14)
	trackPadding.PaddingLeft = UDim.new(0, 4)
	trackPadding.PaddingRight = UDim.new(0, 4)
	trackPadding.Parent = track
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = track

	bonusCard = Theme.well(track, "Bonus", UDim2.fromOffset(CARD_WIDTH, FREE_HEIGHT + 12 + GOLD_HEIGHT), UDim2.new())
	Theme.stroke(bonusCard, C.Ink, 2)
	Theme.scrapIcon(bonusCard, 56, UDim2.new(0.5, 0, 0, 40), Vector2.new(0.5, 0))
	bonusText = Theme.label(bonusCard, {
		size = UDim2.new(1, -16, 0, 90),
		position = UDim2.fromOffset(8, 110),
		text = "",
		font = Theme.Body,
		textSize = 14,
	})

	howItWorks = Theme.label(panel, {
		name = "HowItWorks",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.new(0, 0, 1, -40),
		text = "Every match earns season XP: as much as the Scrap you win. Rewards arrive on their own the moment "
			.. "you reach a tier. Style marked SEASON ONLY can't be bought with Scrap!",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})
	goldButton = Theme.button(panel, {
		name = "GetGold",
		size = UDim2.fromOffset(280, 56),
		position = UDim2.fromScale(1, 1),
		anchor = Vector2.new(1, 1),
		text = "GET THE GOLD PASS",
		color = C.Gold,
		textSize = 24,
	})
	goldButton.Activated:Connect(function()
		SeasonTrack.GoldPressed:Fire()
	end)
	Theme.sweep(goldButton, 3)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function SeasonTrack.open()
	gui.Enabled = true
	refresh()
	-- Start with the next reward in view.
	local tier = PlayerDataClient.get().season.tier
	track.CanvasPosition = Vector2.new(math.max(0, (tier - 2) * (CARD_WIDTH + CARD_GAP)), 0)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
end

function SeasonTrack.close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		SeasonTrack.Closed:Fire()
	end
end

function SeasonTrack.isOpen(): boolean
	return gui.Enabled
end

function SeasonTrack.start()
	build()
	PlayerDataClient.Changed:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
	-- The next reward's card pulses.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui.Enabled then
				refresh()
			end
		end
	end)
end

return SeasonTrack
