--!strict
-- The main menu: where you start, and where you come back to after a match. Your car turns on its turntable in
-- the garage showroom in the middle.
--
--   Left:  the logo, PLAY, GARAGE and SHOP, then HOW TO PLAY, COLLECTION and TOP 50, and your player card.
--   Right: INVITE, GIFTS and your Scrap (with the car you're saving up for), today's quests and the daily chest,
--          and how far you are along this season's reward track.
--
-- After PLAY you either drop straight into a match that's already going (taking over from a bot), or wait a few
-- seconds for the next one to start, so friends who press PLAY together end up in the same match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local CarCatalog = require(Shared.Config.CarCatalog)
local Daily = require(Shared.Config.Daily)
local Evolution = require(Shared.Config.Evolution)
local Gifts = require(Shared.Config.Gifts)
local Levels = require(Shared.Config.Levels)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Rewards = require(Shared.Config.Rewards)
local Season = require(Shared.Config.Season)
local Signal = require(Shared.Util.Signal)
local Twists = require(Shared.Config.Twists)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local MainMenu = {}

MainMenu.PlayPressed = Signal.new() :: Signal.Signal<>
MainMenu.CancelPressed = Signal.new() :: Signal.Signal<>
MainMenu.GaragePressed = Signal.new() :: Signal.Signal<>
MainMenu.HowToPlayPressed = Signal.new() :: Signal.Signal<>
MainMenu.CollectionPressed = Signal.new() :: Signal.Signal<>
MainMenu.StreakPressed = Signal.new() :: Signal.Signal<>
MainMenu.ChestPressed = Signal.new() :: Signal.Signal<>
MainMenu.SeasonPressed = Signal.new() :: Signal.Signal<>
MainMenu.ProfilePressed = Signal.new() :: Signal.Signal<>
MainMenu.GiftsPressed = Signal.new() :: Signal.Signal<>
MainMenu.LeaderboardPressed = Signal.new() :: Signal.Signal<>
MainMenu.InvitePressed = Signal.new() :: Signal.Signal<>
MainMenu.ShopPressed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local Phases = MatchState.Phases

local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()

local LEFT_X = 32 -- the left column's edge...
local COLUMN = 400 -- ...and width
local RIGHT_W = 384 -- the right column's width (it hugs the right edge)

local gui: ScreenGui
local left: Frame
local right: Frame
local playButton: TextButton
local queueCard: Frame
local queueTitle: TextLabel
local queueDetail: TextLabel
local spinner: Frame
local statusLine: TextLabel
local garageButton: TextButton
local evolveBadge: TextLabel
local giftsButton: TextButton
local giftBadge: TextLabel
local playerLevel: TextLabel
local playerTitle: TextLabel
local playerStreak: TextLabel
local playerXp: Theme.Bar
local playerXpText: TextLabel
local scrapAmount: Theme.Amount
local boostTag: TextLabel
local nextName: TextLabel
local nextBar: Theme.Bar
local seasonTitle: TextLabel
local seasonDays: TextLabel
local seasonTier: TextLabel
local seasonNext: TextLabel
local seasonBar: Theme.Bar
local seasonXp: TextLabel
-- Daily quests
type QuestRow = {
	frame: Frame,
	text: TextLabel,
	bar: Theme.Bar,
	count: TextLabel,
	reward: Theme.Amount,
	done: TextLabel,
	claim: TextButton,
}
local questRows: { QuestRow } = {}
local streakButton: TextButton
local chestButton: TextButton
local dailyTimer: TextLabel
local toast: TextLabel
local claiming = false
local chestReady = false
local claimReady = false

local queued = false
local evolveReady = false

local function buildLogo(parent: Frame)
	local logo = Instance.new("Frame")
	logo.Name = "Logo"
	logo.Size = UDim2.fromOffset(COLUMN, 168)
	logo.Position = UDim2.fromOffset(LEFT_X + 4, 66)
	logo.BackgroundTransparency = 1
	logo.Rotation = -3
	logo.Parent = parent
	-- Each word twice: a dark copy a little lower makes a hard shadow, like a sticker.
	local function word(name: string, text: string, color: Color3, x: number, y: number)
		for _, shadow in { true, false } do
			local label = Theme.label(logo, {
				name = if shadow then name .. "Shadow" else name,
				size = UDim2.new(1, 0, 0, 88),
				position = UDim2.fromOffset(x, y + (if shadow then 7 else 0)),
				text = text,
				font = Theme.Logo,
				color = if shadow then C.Ink else color,
				scaled = false,
				textSize = 96,
				align = Enum.TextXAlignment.Left,
				stroke = true,
			})
			label.TextYAlignment = Enum.TextYAlignment.Bottom
		end
	end
	word("Turbo", "TURBO", C.Text, 0, 0)
	word("Ball", "BALL", C.Gold, 58, 82)
end

local function buildQueueCard(parent: Frame)
	-- Shown instead of PLAY while you wait for a match.
	queueCard = Theme.slab(parent, "Queue", UDim2.fromOffset(COLUMN, 100), UDim2.fromOffset(LEFT_X, 248))
	queueCard.Visible = false
	spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.Size = UDim2.fromOffset(34, 34)
	spinner.Position = UDim2.fromOffset(42, 47)
	spinner.AnchorPoint = Vector2.new(0.5, 0.5)
	spinner.BackgroundColor3 = C.Gold
	spinner.Parent = queueCard
	Theme.corner(spinner, 8)
	Theme.stroke(spinner, C.Ink, 3)
	queueTitle = Theme.heading(queueCard, {
		name = "Title",
		size = UDim2.fromOffset(220, 36),
		position = UDim2.fromOffset(78, 18),
		text = "FINDING MATCH",
		color = C.Gold,
		textSize = 32,
		align = Enum.TextXAlignment.Left,
	})
	queueDetail = Theme.label(queueCard, {
		name = "Detail",
		size = UDim2.fromOffset(200, 18),
		position = UDim2.fromOffset(80, 58),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		textSize = 15,
		align = Enum.TextXAlignment.Left,
	})
	local cancel = Theme.button(queueCard, {
		name = "Cancel",
		size = UDim2.fromOffset(104, 52),
		position = UDim2.new(1, -16, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		text = "CANCEL",
		color = C.Bad,
	})
	cancel.Activated:Connect(function()
		MainMenu.CancelPressed:Fire()
	end)
end

-- A small dark button (the row under GARAGE and SHOP, and along the top).
local function smallButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextButton
	return Theme.button(parent, {
		name = name,
		size = size,
		position = position,
		text = text,
		color = C.Panel,
		textSize = 18,
	})
end

local function buildPlayerCard(parent: Frame)
	-- You: avatar, level, name, title and how far you are to the next level. Tap it for your profile (stats,
	-- achievements and titles).
	local card = Theme.card(parent, "Player", UDim2.fromOffset(COLUMN, 84), UDim2.fromOffset(LEFT_X, 610))
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromOffset(60, 60)
	avatar.Position = UDim2.fromOffset(10, 9)
	avatar.BackgroundColor3 = C.CardShade
	avatar.Image = `rbxthumb://type=AvatarHeadShot&id={localPlayer.UserId}&w=150&h=150`
	avatar.Parent = card
	Theme.corner(avatar, 14)
	Theme.stroke(avatar, C.Ink, 2)
	playerLevel = Theme.heading(card, {
		name = "Level",
		size = UDim2.fromOffset(34, 28),
		position = UDim2.fromOffset(52, 46),
		text = "1",
		color = C.Ink,
		textSize = 20,
		zIndex = 3,
	})
	playerLevel.BackgroundColor3 = C.Gold
	playerLevel.BackgroundTransparency = 0
	Theme.corner(playerLevel, 9)
	Theme.stroke(playerLevel, C.Ink, 2)
	Theme.label(card, {
		name = "Name",
		size = UDim2.fromOffset(190, 24),
		position = UDim2.fromOffset(86, 10),
		text = localPlayer.DisplayName,
		textSize = 20,
		align = Enum.TextXAlignment.Left,
	})
	playerStreak = Theme.pill(card, {
		name = "Streak",
		size = UDim2.fromOffset(112, 24),
		position = UDim2.new(1, -12, 0, 10),
		anchor = Vector2.new(1, 0),
		text = "",
		background = C.Mega,
	})
	playerTitle = Theme.label(card, {
		name = "Title",
		size = UDim2.fromOffset(200, 16),
		position = UDim2.fromOffset(87, 35),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})
	playerXp = Theme.bar(card, UDim2.fromOffset(200, 12), UDim2.fromOffset(87, 58), C.Gold, C.CardLine)
	playerXpText = Theme.label(card, {
		name = "Xp",
		size = UDim2.fromOffset(96, 16),
		position = UDim2.new(1, -12, 0, 56),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Right,
	})
	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.Size = UDim2.fromScale(1, 1)
	open.BackgroundTransparency = 1
	open.Text = ""
	open.ZIndex = 5
	open.Parent = card
	open.Activated:Connect(function()
		MainMenu.ProfilePressed:Fire()
	end)
end

local function buildLeft()
	left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = UDim2.fromOffset(480, 720)
	left.BackgroundTransparency = 1
	left.Parent = gui
	Theme.scaled(left)

	buildLogo(left)

	playButton = Theme.button(left, {
		name = "Play",
		size = UDim2.fromOffset(COLUMN, 100),
		position = UDim2.fromOffset(LEFT_X, 248),
		text = "PLAY",
		textSize = 54,
	})
	Theme.sweep(playButton, 3.5)
	playButton.Activated:Connect(function()
		MainMenu.PlayPressed:Fire()
	end)
	buildQueueCard(left)

	-- One line about what's on: a match you can jump into, friends here, or this week's twist.
	statusLine = Theme.label(left, {
		name = "Status",
		size = UDim2.fromOffset(COLUMN, 18),
		position = UDim2.fromOffset(LEFT_X + 2, 360),
		text = "",
		font = Theme.Caps,
		color = C.Text,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})

	local half = (COLUMN - 12) / 2
	garageButton = Theme.button(left, {
		name = "Garage",
		size = UDim2.fromOffset(half, 66),
		position = UDim2.fromOffset(LEFT_X, 392),
		text = "GARAGE",
		color = C.Card,
		textSize = 30,
	})
	garageButton.Activated:Connect(function()
		MainMenu.GaragePressed:Fire()
	end)
	evolveBadge = Theme.pill(left, {
		name = "EvolveBadge",
		size = UDim2.fromOffset(92, 26),
		position = UDim2.fromOffset(LEFT_X + half + 10, 392),
		anchor = Vector2.new(1, 0.5),
		text = "EVOLVE!",
		background = C.Evolve,
	})
	evolveBadge.ZIndex = 3
	evolveBadge.Visible = false
	local shopButton = Theme.button(left, {
		name = "Shop",
		size = UDim2.fromOffset(half, 66),
		position = UDim2.fromOffset(LEFT_X + half + 12, 392),
		text = "SHOP",
		color = C.Shop,
		textSize = 30,
	})
	shopButton.Activated:Connect(function()
		MainMenu.ShopPressed:Fire()
	end)

	local third = (COLUMN - 24) / 3
	local small = UDim2.fromOffset(third, 46)
	local howButton = smallButton(left, "HowToPlay", "HOW TO PLAY", small, UDim2.fromOffset(LEFT_X, 474))
	howButton.Activated:Connect(function()
		MainMenu.HowToPlayPressed:Fire()
	end)
	local collectionButton =
		smallButton(left, "Collection", "COLLECTION", small, UDim2.fromOffset(LEFT_X + third + 12, 474))
	collectionButton.Activated:Connect(function()
		MainMenu.CollectionPressed:Fire()
	end)
	local topButton =
		smallButton(left, "Leaderboard", "TOP 50", small, UDim2.fromOffset(LEFT_X + (third + 12) * 2, 474))
	topButton.Activated:Connect(function()
		MainMenu.LeaderboardPressed:Fire()
	end)

	buildPlayerCard(left)
end

-- Along the top right: INVITE, GIFTS and your Scrap (with the car you're saving up for).
local function buildTop(parent: Frame)
	local wallet = Theme.card(parent, "Wallet", UDim2.fromOffset(204, 76), UDim2.new(1, -24, 0, 16), Vector2.new(1, 0))
	scrapAmount = Theme.amount(wallet, 30, UDim2.fromOffset(12, 8))
	boostTag = Theme.pill(wallet, {
		name = "Boost",
		size = UDim2.fromOffset(54, 22),
		position = UDim2.new(1, -10, 0, 12),
		anchor = Vector2.new(1, 0),
		text = "x2",
		background = C.Good,
	})
	boostTag.Visible = false
	nextName = Theme.label(wallet, {
		name = "Next",
		size = UDim2.new(1, -24, 0, 14),
		position = UDim2.fromOffset(12, 42),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Left,
	})
	nextBar = Theme.bar(wallet, UDim2.new(1, -24, 0, 8), UDim2.fromOffset(12, 58), C.Good, C.CardLine)

	giftsButton = smallButton(parent, "Gifts", "GIFTS", UDim2.fromOffset(104, 52), UDim2.new(1, -240, 0, 16))
	giftsButton.AnchorPoint = Vector2.new(1, 0)
	giftsButton.Activated:Connect(function()
		MainMenu.GiftsPressed:Fire()
	end)
	giftBadge = Theme.label(giftsButton, {
		name = "Badge",
		size = UDim2.fromOffset(28, 28),
		position = UDim2.new(1, 22, 0, -18),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Display,
		color = C.Text,
		textSize = 18,
		zIndex = 3,
	})
	giftBadge.BackgroundColor3 = C.Bad
	giftBadge.BackgroundTransparency = 0
	giftBadge.Visible = false
	Theme.corner(giftBadge, 14)
	Theme.stroke(giftBadge, C.Ink, 2)
	local invite = smallButton(parent, "Invite", "INVITE", UDim2.fromOffset(104, 52), UDim2.new(1, -356, 0, 16))
	invite.AnchorPoint = Vector2.new(1, 0)
	invite.Activated:Connect(function()
		MainMenu.InvitePressed:Fire()
	end)
end

local function questRow(daily: Frame, i: number)
	local row = Theme.well(daily, `Quest{i}`, UDim2.new(1, -24, 0, 64), UDim2.fromOffset(12, 62 + (i - 1) * 72))
	local text = Theme.label(row, {
		name = "Text",
		size = UDim2.new(1, -120, 0, 20),
		position = UDim2.fromOffset(14, 11),
		text = "",
		textSize = 16,
		align = Enum.TextXAlignment.Left,
	})
	local bar = Theme.bar(row, UDim2.new(1, -170, 0, 12), UDim2.fromOffset(14, 39), C.Good, C.CardLine)
	local count = Theme.label(row, {
		name = "Count",
		size = UDim2.fromOffset(46, 16),
		position = UDim2.new(1, -150, 0, 37),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	local reward = Theme.amount(row, 22, UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5))
	local done = Theme.pill(row, {
		name = "Done",
		size = UDim2.fromOffset(74, 28),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "DONE",
		background = C.Good,
	})
	done.Visible = false
	local claim = Theme.button(row, {
		name = "Claim",
		size = UDim2.fromOffset(96, 48),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "",
		color = C.Gold,
		textSize = 22,
	})
	claim.Visible = false
	claim.Activated:Connect(function()
		if claiming then
			return
		end
		claiming = true
		local ok, result = pcall(function()
			return Remotes.Daily:InvokeServer("quest", i)
		end)
		claiming = false
		if ok and type(result) == "table" then
			MainMenu.toast(tostring(result.message), result.ok == true)
		end
	end)
	table.insert(questRows, {
		frame = row,
		text = text,
		bar = bar,
		count = count,
		reward = reward,
		done = done,
		claim = claim,
	})
end

local function buildRight()
	right = Instance.new("Frame")
	right.Name = "Right"
	right.Size = UDim2.fromOffset(RIGHT_W + 48, 720)
	right.Position = UDim2.fromScale(1, 0)
	right.AnchorPoint = Vector2.new(1, 0)
	right.BackgroundTransparency = 1
	right.Parent = gui
	Theme.scaled(right)

	buildTop(right)

	-- Today's quests and the daily chest.
	local questsHeight = 62 + Daily.QuestCount * 72 + 62
	local daily = Theme.card(
		right,
		"Daily",
		UDim2.fromOffset(RIGHT_W, questsHeight),
		UDim2.new(1, -24, 0, 112),
		Vector2.new(1, 0)
	)
	Theme.heading(daily, {
		name = "Title",
		size = UDim2.fromOffset(160, 32),
		position = UDim2.fromOffset(16, 14),
		text = "TODAY",
		textSize = 30,
		align = Enum.TextXAlignment.Left,
	})
	streakButton = Theme.button(daily, {
		name = "Streak",
		size = UDim2.fromOffset(150, 40),
		position = UDim2.new(1, -12, 0, 10),
		anchor = Vector2.new(1, 0),
		text = "DAY 1",
		color = C.Mega,
		textSize = 18,
	})
	streakButton.Activated:Connect(function()
		MainMenu.StreakPressed:Fire()
	end)
	for i = 1, Daily.QuestCount do
		questRow(daily, i)
	end
	chestButton = Theme.button(daily, {
		name = "Chest",
		size = UDim2.new(1, -24, 0, 50),
		position = UDim2.new(0, 12, 1, -14),
		anchor = Vector2.new(0, 1),
		text = "",
		color = C.Panel,
		textSize = 20,
	})
	chestButton.Activated:Connect(function()
		MainMenu.ChestPressed:Fire()
	end)
	dailyTimer = Theme.label(right, {
		name = "Timer",
		size = UDim2.fromOffset(RIGHT_W, 16),
		position = UDim2.new(1, -28, 0, 112 + questsHeight + 10),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Text,
		textSize = 12,
		align = Enum.TextXAlignment.Right,
	})

	-- The season: which tier you're on and what's next. Opens the season track.
	local season =
		Theme.card(right, "Season", UDim2.fromOffset(RIGHT_W, 112), UDim2.new(1, -24, 1, -26), Vector2.new(1, 1))
	seasonTitle = Theme.label(season, {
		name = "Title",
		size = UDim2.fromOffset(240, 14),
		position = UDim2.fromOffset(16, 14),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	seasonDays = Theme.label(season, {
		name = "Days",
		size = UDim2.fromOffset(110, 14),
		position = UDim2.new(1, -16, 0, 14),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Right,
	})
	seasonTier = Theme.heading(season, {
		name = "Tier",
		size = UDim2.fromOffset(150, 32),
		position = UDim2.fromOffset(16, 34),
		text = "",
		textSize = 32,
		align = Enum.TextXAlignment.Left,
	})
	seasonNext = Theme.label(season, {
		name = "Next",
		size = UDim2.new(1, -170, 0, 32),
		position = UDim2.new(1, -16, 0, 34),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Body,
		textSize = 14,
		align = Enum.TextXAlignment.Right,
	})
	seasonBar = Theme.bar(season, UDim2.new(1, -120, 0, 14), UDim2.fromOffset(16, 80), C.Gold, C.CardLine)
	seasonXp = Theme.label(season, {
		name = "Xp",
		size = UDim2.fromOffset(92, 16),
		position = UDim2.new(1, -16, 0, 79),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
		align = Enum.TextXAlignment.Right,
	})
	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.Text = ""
	open.Size = UDim2.fromScale(1, 1)
	open.BackgroundTransparency = 1
	open.ZIndex = 5
	open.Parent = season
	open.Activated:Connect(function()
		MainMenu.SeasonPressed:Fire()
	end)
end

-- How many playtime gifts are ready to open (the server keeps the clock in the player's attributes).
local function giftsReady(): number
	local started = localPlayer:GetAttribute(MatchState.PlayerAttr.PlayStart)
	if type(started) ~= "number" then
		return 0
	end
	local opened: { [number]: boolean } = {}
	local list = localPlayer:GetAttribute(MatchState.PlayerAttr.GiftsOpened)
	if type(list) == "string" then
		for index in string.gmatch(list, "%d+") do
			opened[tonumber(index) :: number] = true
		end
	end
	return Gifts.readyCount(workspace:GetServerTimeNow() - started, opened)
end

local function build()
	gui = Theme.screen("TurboMainMenu", 8)
	gui.Enabled = false
	Theme.shade(gui, "Shade", true, 0.5, 0.7)
	Theme.shade(gui, "RightShade", false, 0.34, 0.45)
	buildLeft()
	buildRight()
	toast = Theme.pill(gui, {
		name = "Toast",
		size = UDim2.fromOffset(480, 40),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
	})
	toast.Visible = false
	Theme.scaled(toast)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- A short message along the bottom of the menu.
function MainMenu.toast(text: string, good: boolean)
	text = Theme.noEmoji(text)
	toast.Text = text
	toast.BackgroundColor3 = if good then C.Good else C.Bad
	toast.TextColor3 = C.Text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0
	toast.Visible = true
	task.delay(2.6, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function()
				if toast.Text == text then
					toast.Visible = false
				end
			end)
		end
	end)
end

-- Today's quests, the streak and the chest.
local function refreshDaily(data: PlayerDataClient.Data)
	local daily = data.daily
	claimReady = false
	local done = 0
	for i, row in questRows do
		local quest = daily.quests[i]
		local def = if quest then Daily.quest(quest.id) else nil
		row.frame.Visible = def ~= nil
		if not quest or not def then
			continue
		end
		local finished = quest.progress >= def.Target
		if finished then
			done += 1
		end
		row.text.Text = Daily.describe(def)
		row.bar.set(quest.progress / def.Target)
		row.bar.fill.BackgroundColor3 = if finished then C.Gold else C.Good
		row.count.Text = `{math.min(quest.progress, def.Target)}/{def.Target}`
		local claimable = finished and not quest.claimed
		claimReady = claimReady or claimable
		row.claim.Visible = claimable
		row.claim.Text = `+{def.Reward}`
		row.done.Visible = quest.claimed
		row.reward.frame.Visible = not claimable and not quest.claimed
		row.reward.set(def.Reward)
		row.frame.BackgroundTransparency = if quest.claimed then 0.5 else 0
	end
	local streak = math.max(1, daily.streak)
	streakButton.Text = if streak == 1 then "DAY 1" else `{streak}-DAY STREAK`
	chestReady = Daily.allDone(daily) and not daily.chestPicked
	if daily.chestPicked then
		chestButton.Text = "CHEST OPENED - BACK TOMORROW"
		Theme.setButtonColor(chestButton, C.CardLine, C.InkMuted)
	elseif chestReady then
		chestButton.Text = "OPEN THE DAILY CHEST!"
		Theme.setButtonColor(chestButton, C.Gold)
	else
		chestButton.Text = `DAILY CHEST  {done}/{#daily.quests}`
		Theme.setButtonColor(chestButton, C.Panel)
	end
end

local function refreshData()
	local data = PlayerDataClient.get()
	refreshDaily(data)
	scrapAmount.set(data.scrap)
	boostTag.Visible = data.scrapBoost > 0
	local level, levelXp, levelNeed = Levels.levelFor(data.xp)
	playerLevel.Text = tostring(level)
	local title = Achievements.titleText(if data.title ~= "" then data.title else Achievements.levelTitle(level))
	playerTitle.Text = Theme.noEmoji(title)
	playerStreak.Visible = data.winStreak >= 2
	playerStreak.Text = `{data.winStreak} WINS IN A ROW`
	playerXp.set(levelXp / levelNeed)
	playerXpText.Text = `{levelXp}/{levelNeed} XP`

	local goal = Rewards.nextGoal(data.owned, data.scrap)
	if goal then
		nextName.Text = if goal.canAfford
			then `{string.upper(goal.displayName)}: UNLOCK IT!`
			else `SAVING FOR {string.upper(goal.displayName)}`
		nextName.TextColor3 = if goal.canAfford then C.Good else C.InkMuted
		nextBar.set(goal.have / math.max(goal.price, 1))
		nextBar.fill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
	else
		nextName.Text = "EVERY CAR UNLOCKED!"
		nextBar.set(1)
	end

	-- This season.
	local day = PlayerDataClient.today()
	local info = Season.at(day)
	local current = data.season.number == info.number
	local tier = if current then data.season.tier else 0
	local xp = if current then data.season.xp else 0
	local into = xp - tier * Season.XpPerTier
	seasonTitle.Text = `SEASON {info.number}: {string.upper(info.theme.Name)}`
	local days = Season.daysLeft(day)
	seasonDays.Text = if days <= 1 then "LAST DAY!" else `{days} DAYS LEFT`
	seasonTier.Text = `TIER {tier}`
	local _, text = Season.describe(Season.rewardFor(info.theme, tier + 1))
	seasonNext.Text = `Next: {text}`
	seasonXp.Text = `{Theme.formatNumber(into)}/{Theme.formatNumber(Season.XpPerTier)} XP`
	seasonBar.set(into / Season.XpPerTier)
	seasonBar.fill.BackgroundColor3 = info.theme.Color

	evolveReady = false
	for id in data.owned do
		local owned = CarCatalog.get(id)
		if owned and Evolution.progress(owned, data.carXp[id] or 0, data.carStage[id] or 1).ready then
			evolveReady = true
		end
	end
end

local function numberAttr(name: string): number
	local value = stateObject:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function update()
	if not gui.Enabled then
		return
	end
	local now = workspace:GetServerTimeNow()
	local phase = MatchState.phase(stateObject)
	local live = phase == Phases.Countdown or phase == Phases.Playing or phase == Phases.GoalScored

	playButton.Visible = not queued
	queueCard.Visible = queued
	if queued then
		spinner.Rotation = (os.clock() * 300) % 360
		if phase == Phases.Intermission then
			queueTitle.Text = `STARTING IN {math.ceil(MatchState.phaseSecondsLeft(stateObject, now))}`
			queueDetail.Text = "Get ready to drive!"
		elseif live then
			queueTitle.Text = "YOU'RE NEXT"
			queueDetail.Text = "Waiting for a seat in this match"
		elseif phase == Phases.Results then
			queueTitle.Text = "NEXT MATCH SOON"
			queueDetail.Text = "The last match is just finishing"
		else
			queueTitle.Text = "FINDING MATCH"
			queueDetail.Text = "Friends who press PLAY join you"
		end
	end

	-- What's on, most important first.
	local event = Twists.event(math.floor(now))
	local count = #Players:GetPlayers()
	if live then
		statusLine.Text = `LIVE NOW: BLUE {numberAttr(MatchState.Attr.BlueScore)} - {numberAttr(
			MatchState.Attr.OrangeScore
		)} ORANGE. PRESS PLAY TO JUMP IN!`
		statusLine.TextColor3 = C.Gold
	elseif event then
		statusLine.Text = `{string.upper(event.Name)}: A TWIST EVERY MATCH AND +50% SCRAP!`
		statusLine.TextColor3 = C.Gold
	elseif count > 1 then
		statusLine.Text = `{count} PLAYERS HERE. PRESS PLAY TO TEAM UP!`
		statusLine.TextColor3 = C.Text
	else
		local featured = Twists.featured(math.floor(now))
		statusLine.Text = `TWIST OF THE WEEK: {string.upper(featured.Name)}`
		statusLine.TextColor3 = C.Text
	end

	evolveBadge.Visible = evolveReady
	if evolveReady then
		evolveBadge.Rotation = 6 + math.sin(os.clock() * 5) * 3
	end

	-- Playtime gifts waiting: the button turns green with a count on it, and wiggles.
	local ready = giftsReady()
	giftBadge.Visible = ready > 0
	giftBadge.Text = tostring(ready)
	Theme.setButtonColor(giftsButton, if ready > 0 then C.Good else C.Panel)
	giftsButton.Rotation = if ready > 0 then math.sin(os.clock() * 8) * 3 else 0

	-- Things waiting to be collected pulse.
	local pulse = math.floor(os.clock() * 3) % 2 == 0
	if chestReady then
		Theme.setButtonColor(chestButton, if pulse then C.Gold else rgb(255, 228, 130))
	end
	if claimReady then
		for _, row in questRows do
			if row.claim.Visible then
				Theme.setButtonColor(row.claim, if pulse then C.Gold else rgb(255, 228, 130))
			end
		end
	end
	local untilNew = Daily.secondsUntilNextDay(math.floor(now))
	dailyTimer.Text = `NEW QUESTS IN {untilNew // 3600}H {(untilNew % 3600) // 60}M`
end

function MainMenu.show()
	if gui.Enabled then
		return
	end
	gui.Enabled = true
	refreshData()
	left.Position = UDim2.fromOffset(-60, 0)
	TweenService:Create(left, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()
	right.Position = UDim2.new(1, 60, 0, 0)
	TweenService:Create(right, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(1, 0),
	}):Play()
	Theme.focus(if queued then nil else playButton)
end

function MainMenu.hide()
	gui.Enabled = false
end

function MainMenu.isVisible(): boolean
	return gui.Enabled
end

-- Switches between the PLAY button and the "waiting for a match" card.
function MainMenu.setQueued(isQueued: boolean)
	queued = isQueued
	update()
end

function MainMenu.start()
	build()
	refreshData()
	PlayerDataClient.Changed:Connect(refreshData)
	RunService.RenderStepped:Connect(update)
end

return MainMenu
