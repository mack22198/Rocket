--!strict
-- The season's free reward track (see Season): every tier and its reward in a row you can scroll along, what
-- you've already got, what's next and how far away it is. Rewards pay out on their own after matches - this
-- screen is just for looking forward to them.

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

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

local CARD_WIDTH = 132
local CARD_GAP = 10

type Card = {
	frame: Frame,
	stroke: UIStroke,
	tier: TextLabel,
	icon: TextLabel,
	name: TextLabel,
	status: TextLabel,
	ribbon: TextLabel,
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

local function makeCard(order: number): Card
	local frame = Instance.new("Frame")
	frame.Name = `Tier{order}`
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(CARD_WIDTH, 196)
	frame.BackgroundColor3 = C.PanelLight
	frame.Parent = track
	Theme.corner(frame, 12)
	local stroke = Theme.stroke(frame, C.Muted, 2)
	local tier = Theme.label(frame, {
		name = "Tier",
		size = UDim2.new(1, -12, 0, 18),
		position = UDim2.fromOffset(6, 8),
		text = `TIER {order}`,
		font = Theme.Caps,
		color = C.Muted,
		stroke = false,
	})
	local icon = Theme.label(frame, {
		name = "Icon",
		size = UDim2.new(1, 0, 0, 58),
		position = UDim2.fromOffset(0, 32),
		text = "",
	})
	local name = Theme.label(frame, {
		name = "Reward",
		size = UDim2.new(1, -14, 0, 40),
		position = UDim2.fromOffset(7, 96),
		text = "",
		font = Theme.Body,
	})
	local status = Theme.label(frame, {
		name = "Status",
		size = UDim2.new(1, -14, 0, 18),
		position = UDim2.new(0, 7, 1, -30),
		text = "",
		font = Theme.Caps,
		stroke = false,
	})
	local ribbon = Theme.pill(frame, {
		name = "Ribbon",
		size = UDim2.new(1, -16, 0, 18),
		position = UDim2.new(0.5, 0, 0, -9),
		anchor = Vector2.new(0.5, 0),
		text = "SEASON ONLY",
		font = Theme.Caps,
		color = C.Ink,
		background = C.Evolve,
		transparency = 0,
	})
	ribbon.ZIndex = 3
	return { frame = frame, stroke = stroke, tier = tier, icon = icon, name = name, status = status, ribbon = ribbon }
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

local function refresh()
	local data = PlayerDataClient.get()
	local day = PlayerDataClient.today()
	local info = Season.at(day)
	local theme = info.theme
	local state = data.season
	local current = state.number == info.number
	local tier = if current then state.tier else 0
	local xp = if current then state.xp else 0

	titleLabel.Text = `{theme.Emoji} SEASON {info.number}: {string.upper(theme.Name)}`
	titleLabel.TextColor3 = theme.Color
	descriptionLabel.Text = theme.Description
	local days = Season.daysLeft(day)
	daysPill.Text = if days <= 1 then "⏳ LAST DAY!" else `⏳ {days} DAYS LEFT`
	daysPill.TextColor3 = if days <= 3 then C.Bad else C.Text

	tierLabel.Text = `⭐ TIER {tier}`
	local into = xp - tier * Season.XpPerTier
	xpBar.set(into / Season.XpPerTier)
	xpBar.fill.BackgroundColor3 = theme.Color
	xpLabel.Text = `{Theme.formatNumber(into)} / {Theme.formatNumber(Season.XpPerTier)} XP TO TIER {tier + 1}`

	local count = #theme.Rewards
	ensureCards(count)
	local pulse = math.floor(os.clock() * 2) % 2 == 0
	for i = 1, count do
		local card = cards[i]
		local reward = Season.rewardFor(theme, i)
		local emoji, text = Season.describe(reward)
		local exclusive = reward.Kind == "style"
		local got = i <= tier
		local isNext = i == tier + 1
		card.icon.Text = emoji
		card.name.Text = text
		card.ribbon.Visible = exclusive
		card.frame.BackgroundColor3 = if got then rgb(34, 70, 60) elseif isNext then rgb(70, 60, 30) else C.PanelLight
		card.frame.BackgroundTransparency = if got then 0.15 else 0
		card.stroke.Color = if isNext then C.Gold elseif exclusive then C.Evolve elseif got then C.Good else C.Muted
		card.stroke.Thickness = if isNext then (if pulse then 4 else 3) else 2
		card.stroke.Transparency = if isNext or exclusive then 0 else 0.5
		card.status.Text = if got then "✅ GOT IT" elseif isNext then "⭐ NEXT" else "🔒"
		card.status.TextColor3 = if got then C.Good elseif isNext then C.Gold else C.Muted
		card.tier.TextColor3 = if isNext then C.Gold else C.Muted
		card.icon.TextTransparency = if got or isNext then 0 else 0.35
	end
	bonusText.Text = `Every tier after {count}: 🔩 {Season.BonusScrap} Scrap`
end

local function build()
	gui = Theme.screen("TurboSeason", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = gui

	panel = Theme.panel(gui, "Season", UDim2.fromOffset(1000, 460), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)
	titleLabel = Theme.label(panel, {
		name = "Title",
		size = UDim2.fromOffset(640, 44),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	descriptionLabel = Theme.label(panel, {
		name = "Description",
		size = UDim2.fromOffset(640, 20),
		position = UDim2.fromOffset(2, 48),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	local close = Theme.button(panel, {
		name = "Close",
		size = UDim2.fromOffset(140, 48),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "◀ BACK",
		color = C.PanelLight,
		textColor = C.Text,
	})
	close.Activated:Connect(function()
		SeasonTrack.close()
	end)
	daysPill = Theme.pill(panel, {
		name = "Days",
		size = UDim2.fromOffset(180, 32),
		position = UDim2.new(1, -156, 0, 8),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		transparency = 0.2,
	})

	-- Your progress this season.
	tierLabel = Theme.label(panel, {
		name = "Tier",
		size = UDim2.fromOffset(180, 36),
		position = UDim2.fromOffset(0, 82),
		text = "",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	xpBar = Theme.bar(panel, UDim2.new(1, -200, 0, 16), UDim2.fromOffset(196, 86), C.Gold)
	xpLabel = Theme.label(panel, {
		name = "Xp",
		size = UDim2.new(1, -200, 0, 16),
		position = UDim2.fromOffset(196, 106),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})

	track = Instance.new("ScrollingFrame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 236)
	track.Position = UDim2.fromOffset(0, 140)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ScrollBarThickness = 8
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

	bonusCard = Instance.new("Frame")
	bonusCard.Name = "Bonus"
	bonusCard.Size = UDim2.fromOffset(CARD_WIDTH, 196)
	bonusCard.BackgroundColor3 = C.PanelDark
	bonusCard.BackgroundTransparency = 0.2
	bonusCard.Parent = track
	Theme.corner(bonusCard, 12)
	Theme.stroke(bonusCard, C.Scrap, 2).Transparency = 0.4
	Theme.label(bonusCard, {
		size = UDim2.new(1, 0, 0, 58),
		position = UDim2.fromOffset(0, 32),
		text = "🔩",
	})
	bonusText = Theme.label(bonusCard, {
		size = UDim2.new(1, -14, 0, 60),
		position = UDim2.fromOffset(7, 96),
		text = "",
		font = Theme.Body,
		color = C.Scrap,
	})

	Theme.label(panel, {
		name = "HowItWorks",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.new(0, 0, 1, -40),
		text = "Every match earns season XP - as much as the Scrap you win. Rewards are free and arrive on their own "
			.. "the moment you reach a tier. Style items marked SEASON ONLY can't be bought in the shop!",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})

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
