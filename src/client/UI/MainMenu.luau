--!strict
-- The main menu: where you start, and where you come back to after a match. Your car turns on its turntable in
-- the garage showroom behind it; the big buttons are on the left - PLAY, GARAGE, HOW TO PLAY and COLLECTION -
-- and on the right are your Scrap, the car you're saving up for, today's quests, the daily chest and how far
-- you are along this season's reward track.
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

local gui: ScreenGui
local left: Frame
local right: Frame
local playButton: TextButton
local queueCard: Frame
local queueTitle: TextLabel
local queueDetail: TextLabel
local spinner: TextLabel
local garageButton: TextButton
local evolveBadge: TextLabel
local statusPill: TextLabel
local eventPill: TextLabel
local giftsButton: TextButton
local giftBadge: TextLabel
local playerLevel: TextLabel
local playerTitle: TextLabel
local playerXp: Theme.Bar
local playerXpText: TextLabel
local playerBadges: TextLabel
local scrapPill: TextLabel
local nextName: TextLabel
local nextAmount: TextLabel
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
	icon: TextLabel,
	text: TextLabel,
	bar: Theme.Bar,
	count: TextLabel,
	reward: TextLabel,
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

-- Shown under the buttons, a new one every few seconds.
local TIPS = {
	"💡 TIP: JUMP TWICE TO FLIP INTO THE BALL",
	"💡 TIP: LOSING? ITEM BOXES GIVE YOU BETTER ITEMS",
	"💡 TIP: EVERY CAR HAS ITS OWN POWER - TRY THEM ALL",
	"💡 TIP: FRIENDS WHO PRESS PLAY JOIN YOUR TEAM",
	"💡 TIP: DRIVE A CAR TO MAKE IT EVOLVE",
	"💡 TIP: HIT THE BALL IN THE AIR FOR STYLE POINTS",
	"💡 TIP: BOOST INTO THE OTHER TEAM TO DEMOLISH THEM",
}

local function buildLogo(parent: Frame)
	local logo = Instance.new("Frame")
	logo.Name = "Logo"
	logo.Size = UDim2.fromOffset(430, 176)
	logo.Position = UDim2.fromOffset(40, 62)
	logo.BackgroundTransparency = 1
	logo.Rotation = -3
	logo.Parent = parent
	local turbo = Theme.label(logo, {
		name = "Turbo",
		size = UDim2.new(1, 0, 0, 92),
		text = "TURBO",
		font = Theme.Logo,
		color = rgb(255, 255, 255),
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	Theme.stroke(turbo, rgb(40, 18, 0), 5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local gold = Instance.new("UIGradient")
	gold.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 244, 150)),
		ColorSequenceKeypoint.new(0.5, rgb(255, 200, 50)),
		ColorSequenceKeypoint.new(1, rgb(255, 130, 30)),
	})
	gold.Rotation = 90
	gold.Parent = turbo
	local ball = Theme.label(logo, {
		name = "Ball",
		size = UDim2.new(1, 0, 0, 84),
		position = UDim2.fromOffset(62, 84),
		text = "BALL ⚽",
		font = Theme.Logo,
		color = rgb(255, 255, 255),
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	Theme.stroke(ball, rgb(10, 16, 40), 5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local cool = Instance.new("UIGradient")
	cool.Color = ColorSequence.new(rgb(255, 255, 255), rgb(170, 214, 255))
	cool.Rotation = 90
	cool.Parent = ball
end

local function buildLeft()
	left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = UDim2.fromOffset(520, 720)
	left.BackgroundTransparency = 1
	left.Parent = gui
	Theme.scaled(left)

	buildLogo(left)
	Theme.label(left, {
		name = "Tagline",
		size = UDim2.fromOffset(400, 20),
		position = UDim2.fromOffset(46, 244),
		text = "3 VS 3 CAR SOCCER",
		font = Theme.Caps,
		color = rgb(190, 205, 240),
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})

	playButton = Theme.button(left, {
		name = "Play",
		size = UDim2.fromOffset(400, 94),
		position = UDim2.fromOffset(44, 278),
		text = "▶  PLAY",
	})
	Theme.sweep(playButton, 3.5)
	playButton.Activated:Connect(function()
		MainMenu.PlayPressed:Fire()
	end)

	-- Shown instead of PLAY while you wait for a match.
	queueCard = Theme.panel(left, "Queue", UDim2.fromOffset(400, 94), UDim2.fromOffset(44, 278))
	queueCard.BackgroundColor3 = rgb(30, 40, 78)
	queueCard.Visible = false
	Theme.stroke(queueCard, C.Gold, 3)
	spinner = Theme.label(queueCard, {
		name = "Spinner",
		size = UDim2.fromOffset(52, 52),
		position = UDim2.fromOffset(20, 21),
		text = "⚽",
		stroke = false,
	})
	queueTitle = Theme.label(queueCard, {
		name = "Title",
		size = UDim2.fromOffset(190, 34),
		position = UDim2.fromOffset(86, 16),
		text = "FINDING MATCH",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	queueDetail = Theme.label(queueCard, {
		name = "Detail",
		size = UDim2.fromOffset(190, 18),
		position = UDim2.fromOffset(88, 54),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	local cancel = Theme.button(queueCard, {
		name = "Cancel",
		size = UDim2.fromOffset(92, 46),
		position = UDim2.new(1, -16, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "CANCEL",
		color = C.Bad,
		textColor = C.Text,
	})
	cancel.Activated:Connect(function()
		MainMenu.CancelPressed:Fire()
	end)

	garageButton = Theme.button(left, {
		name = "Garage",
		size = UDim2.fromOffset(400, 70),
		position = UDim2.fromOffset(44, 386),
		text = "🚗  GARAGE",
		color = C.Blue,
		textColor = C.Text,
	})
	garageButton.Activated:Connect(function()
		MainMenu.GaragePressed:Fire()
	end)
	evolveBadge = Theme.pill(left, {
		name = "EvolveBadge",
		size = UDim2.fromOffset(190, 30),
		position = UDim2.fromOffset(440, 380),
		anchor = Vector2.new(1, 0.5),
		text = "✨ READY TO EVOLVE!",
		background = C.Evolve,
		transparency = 0,
		font = Theme.Caps,
	})
	evolveBadge.ZIndex = 3
	evolveBadge.Visible = false

	local howButton = Theme.button(left, {
		name = "HowToPlay",
		size = UDim2.fromOffset(195, 58),
		position = UDim2.fromOffset(44, 470),
		text = "❓ HOW TO PLAY",
		color = C.PanelLight,
		textColor = C.Text,
	})
	howButton.Activated:Connect(function()
		MainMenu.HowToPlayPressed:Fire()
	end)
	local collectionButton = Theme.button(left, {
		name = "Collection",
		size = UDim2.fromOffset(195, 58),
		position = UDim2.fromOffset(249, 470),
		text = "📖 COLLECTION",
		color = C.Evolve,
		textColor = C.Text,
	})
	collectionButton.Activated:Connect(function()
		MainMenu.CollectionPressed:Fire()
	end)

	statusPill = Theme.pill(left, {
		name = "Status",
		size = UDim2.fromOffset(400, 30),
		position = UDim2.fromOffset(44, 542),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		transparency = 0.35,
	})

	-- What's on: the weekend event, or this week's featured twist.
	eventPill = Theme.pill(left, {
		name = "Event",
		size = UDim2.fromOffset(400, 30),
		position = UDim2.fromOffset(44, 580),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		transparency = 0.25,
	})

	-- You: avatar, level, name, title and how far you are to the next level. Tap it for your profile (stats,
	-- achievements and titles).
	local card = Theme.panel(left, "Player", UDim2.fromOffset(400, 76), UDim2.fromOffset(44, 620))
	card.BackgroundTransparency = 0.2
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromOffset(60, 60)
	avatar.Position = UDim2.fromOffset(8, 8)
	avatar.BackgroundColor3 = C.PanelLight
	avatar.Image = `rbxthumb://type=AvatarHeadShot&id={localPlayer.UserId}&w=150&h=150`
	avatar.Parent = card
	Theme.corner(avatar, 30)
	Theme.stroke(avatar, C.Gold, 2)
	playerLevel = Theme.label(card, {
		name = "Level",
		size = UDim2.fromOffset(30, 30),
		position = UDim2.fromOffset(46, 44),
		text = "1",
		color = C.Ink,
		stroke = false,
		zIndex = 3,
	})
	playerLevel.BackgroundColor3 = C.Gold
	playerLevel.BackgroundTransparency = 0
	Theme.corner(playerLevel, 15)
	Theme.stroke(playerLevel, C.Ink, 2)
	Theme.label(card, {
		name = "Name",
		size = UDim2.fromOffset(210, 26),
		position = UDim2.fromOffset(82, 6),
		text = localPlayer.DisplayName,
		align = Enum.TextXAlignment.Left,
	})
	playerBadges = Theme.label(card, {
		name = "Achievements",
		size = UDim2.fromOffset(96, 20),
		position = UDim2.fromOffset(294, 8),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	playerTitle = Theme.label(card, {
		name = "Title",
		size = UDim2.fromOffset(306, 16),
		position = UDim2.fromOffset(83, 34),
		text = "",
		font = Theme.Body,
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	playerXp = Theme.bar(card, UDim2.fromOffset(212, 10), UDim2.fromOffset(83, 57), C.Gold)
	playerXpText = Theme.label(card, {
		name = "Xp",
		size = UDim2.fromOffset(94, 16),
		position = UDim2.fromOffset(300, 54),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
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

local function buildRight()
	right = Instance.new("Frame")
	right.Name = "Right"
	right.Size = UDim2.fromOffset(440, 720)
	right.Position = UDim2.fromScale(1, 0)
	right.AnchorPoint = Vector2.new(1, 0)
	right.BackgroundTransparency = 1
	right.Parent = gui
	Theme.scaled(right)

	scrapPill = Theme.pill(right, {
		name = "Scrap",
		size = UDim2.fromOffset(200, 46),
		position = UDim2.fromOffset(416, 64),
		anchor = Vector2.new(1, 0),
		text = "🔩 0",
		color = C.Scrap,
	})

	local nextCard =
		Theme.panel(right, "NextCar", UDim2.fromOffset(300, 78), UDim2.fromOffset(416, 120), Vector2.new(1, 0))
	nextCard.BackgroundTransparency = 0.2
	Theme.label(nextCard, {
		size = UDim2.fromOffset(200, 14),
		position = UDim2.fromOffset(14, 10),
		text = "SAVING UP FOR",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	nextName = Theme.label(nextCard, {
		name = "Name",
		size = UDim2.new(1, -28, 0, 24),
		position = UDim2.fromOffset(14, 26),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	nextBar = Theme.bar(nextCard, UDim2.new(1, -118, 0, 12), UDim2.fromOffset(14, 56), C.Good)
	nextAmount = Theme.label(nextCard, {
		name = "Amount",
		size = UDim2.fromOffset(92, 16),
		position = UDim2.new(1, -100, 0, 54),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})

	-- Today's quests and the daily chest.
	local daily = Theme.panel(right, "Daily", UDim2.fromOffset(380, 318), UDim2.fromOffset(416, 210), Vector2.new(1, 0))
	daily.BackgroundTransparency = 0.2
	Theme.label(daily, {
		size = UDim2.fromOffset(170, 16),
		position = UDim2.fromOffset(16, 14),
		text = "📅 DAILY QUESTS",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	streakButton = Theme.button(daily, {
		name = "Streak",
		size = UDim2.fromOffset(150, 32),
		position = UDim2.new(1, -12, 0, 8),
		anchor = Vector2.new(1, 0),
		text = "🔥 DAY 1",
		color = rgb(255, 120, 60),
		textColor = C.Text,
	})
	streakButton.Activated:Connect(function()
		MainMenu.StreakPressed:Fire()
	end)
	for i = 1, Daily.QuestCount do
		local row = Instance.new("Frame")
		row.Name = `Quest{i}`
		row.Size = UDim2.new(1, -24, 0, 62)
		row.Position = UDim2.fromOffset(12, 46 + (i - 1) * 68)
		row.BackgroundColor3 = C.PanelDark
		row.BackgroundTransparency = 0.3
		row.Parent = daily
		Theme.corner(row, 12)
		local icon = Theme.label(row, {
			name = "Icon",
			size = UDim2.fromOffset(38, 38),
			position = UDim2.fromOffset(8, 12),
			text = "",
			stroke = false,
		})
		local text = Theme.label(row, {
			name = "Text",
			size = UDim2.fromOffset(200, 20),
			position = UDim2.fromOffset(54, 9),
			text = "",
			font = Theme.Body,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
		local bar = Theme.bar(row, UDim2.fromOffset(150, 10), UDim2.fromOffset(54, 38), C.Good)
		local count = Theme.label(row, {
			name = "Count",
			size = UDim2.fromOffset(46, 16),
			position = UDim2.fromOffset(210, 35),
			text = "",
			font = Theme.Body,
			color = C.Muted,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
		local reward = Theme.label(row, {
			name = "Reward",
			size = UDim2.fromOffset(84, 24),
			position = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			text = "",
			color = C.Scrap,
			align = Enum.TextXAlignment.Right,
		})
		local claim = Theme.button(row, {
			name = "Claim",
			size = UDim2.fromOffset(92, 44),
			position = UDim2.new(1, -8, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			text = "",
			color = C.Gold,
		})
		claim.Visible = false
		local index = i
		claim.Activated:Connect(function()
			if claiming then
				return
			end
			claiming = true
			local ok, result = pcall(function()
				return Remotes.Daily:InvokeServer("quest", index)
			end)
			claiming = false
			if ok and type(result) == "table" then
				MainMenu.toast(tostring(result.message), result.ok == true)
			end
		end)
		table.insert(questRows, {
			frame = row,
			icon = icon,
			text = text,
			bar = bar,
			count = count,
			reward = reward,
			claim = claim,
		})
	end
	chestButton = Theme.button(daily, {
		name = "Chest",
		size = UDim2.new(1, -24, 0, 46),
		position = UDim2.new(0, 12, 1, -12),
		anchor = Vector2.new(0, 1),
		text = "",
		color = C.PanelLight,
		textColor = C.Text,
	})
	chestButton.Activated:Connect(function()
		MainMenu.ChestPressed:Fire()
	end)
	dailyTimer = Theme.label(daily, {
		name = "Timer",
		size = UDim2.fromOffset(200, 14),
		position = UDim2.new(1, -16, 1, 4),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})

	-- The season: which tier you're on and what's next. Opens the season track.
	local season =
		Theme.panel(right, "Season", UDim2.fromOffset(380, 100), UDim2.fromOffset(416, 696), Vector2.new(1, 1))
	season.BackgroundTransparency = 0.2
	seasonTitle = Theme.label(season, {
		name = "Title",
		size = UDim2.fromOffset(250, 14),
		position = UDim2.fromOffset(16, 10),
		text = "",
		font = Theme.Caps,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	seasonDays = Theme.label(season, {
		name = "Days",
		size = UDim2.fromOffset(110, 14),
		position = UDim2.new(1, -16, 0, 10),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	seasonTier = Theme.label(season, {
		name = "Tier",
		size = UDim2.fromOffset(140, 28),
		position = UDim2.fromOffset(16, 26),
		text = "",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	seasonNext = Theme.label(season, {
		name = "Next",
		size = UDim2.new(1, -170, 0, 22),
		position = UDim2.new(1, -16, 0, 30),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Body,
		align = Enum.TextXAlignment.Right,
		stroke = false,
	})
	seasonXp = Theme.label(season, {
		name = "Xp",
		size = UDim2.new(1, -32, 0, 14),
		position = UDim2.fromOffset(16, 58),
		text = "",
		font = Theme.Body,
		color = C.Muted,
		align = Enum.TextXAlignment.Left,
		stroke = false,
	})
	seasonBar = Theme.bar(season, UDim2.new(1, -32, 0, 10), UDim2.fromOffset(16, 76), C.Gold)
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

-- Along the top: playtime gifts, this week's leaderboard, inviting friends and the shop.
local function buildDock()
	local dock = Instance.new("Frame")
	dock.Name = "Dock"
	dock.Size = UDim2.fromOffset(640, 46)
	dock.Position = UDim2.new(0.5, 0, 0, 12)
	dock.AnchorPoint = Vector2.new(0.5, 0)
	dock.BackgroundTransparency = 1
	dock.Parent = gui
	Theme.scaled(dock)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dock
	local function dockButton(order: number, name: string, text: string, color: Color3, textColor: Color3?)
		local button = Theme.button(dock, {
			name = name,
			size = UDim2.fromOffset(150, 46),
			text = text,
			color = color,
			textColor = textColor,
		})
		button.LayoutOrder = order
		return button
	end
	giftsButton = dockButton(1, "Gifts", "🎁 GIFTS", C.Good)
	giftsButton.Activated:Connect(function()
		MainMenu.GiftsPressed:Fire()
	end)
	giftBadge = Theme.label(giftsButton, {
		name = "Badge",
		size = UDim2.fromOffset(26, 26),
		position = UDim2.new(1, 12, 0, -12),
		anchor = Vector2.new(1, 0),
		text = "",
		color = C.Text,
		stroke = false,
		zIndex = 3,
	})
	giftBadge.BackgroundColor3 = C.Bad
	giftBadge.BackgroundTransparency = 0
	giftBadge.Visible = false
	Theme.corner(giftBadge, 13)
	local top = dockButton(2, "Leaderboard", "🏆 TOP 50", C.Gold)
	top.Activated:Connect(function()
		MainMenu.LeaderboardPressed:Fire()
	end)
	local invite = dockButton(3, "Invite", "👋 INVITE", C.Blue, C.Text)
	invite.Activated:Connect(function()
		MainMenu.InvitePressed:Fire()
	end)
	local shop = dockButton(4, "Shop", "🛒 SHOP", C.Evolve, C.Text)
	shop.Activated:Connect(function()
		MainMenu.ShopPressed:Fire()
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
	Theme.shade(gui, "Shade", true, 0.55, 0.78)
	Theme.shade(gui, "RightShade", false, 0.36, 0.5)
	buildLeft()
	buildRight()
	buildDock()
	toast = Theme.pill(gui, {
		name = "Toast",
		size = UDim2.fromOffset(460, 38),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
		background = C.PanelDark,
		transparency = 0,
	})
	toast.Visible = false
	Theme.scaled(toast)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- A short message along the bottom of the menu.
function MainMenu.toast(text: string, good: boolean)
	toast.Text = text
	toast.TextColor3 = if good then C.Good else C.Bad
	toast.TextTransparency = 0
	toast.Visible = true
	task.delay(2.6, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
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
		row.icon.Text = def.Emoji
		row.text.Text = Daily.describe(def)
		row.bar.set(quest.progress / def.Target)
		row.bar.fill.BackgroundColor3 = if finished then C.Gold else C.Good
		row.count.Text = `{math.min(quest.progress, def.Target)}/{def.Target}`
		local claimable = finished and not quest.claimed
		claimReady = claimReady or claimable
		row.claim.Visible = claimable
		row.claim.Text = `+{def.Reward}`
		row.reward.Visible = not claimable
		row.reward.Text = if quest.claimed then "✅" else `🔩{def.Reward}`
		row.frame.BackgroundTransparency = if quest.claimed then 0.6 else 0.3
	end
	local streak = math.max(1, daily.streak)
	streakButton.Text = if streak == 1 then "🔥 DAY 1" else `🔥 {streak} DAYS`
	chestReady = Daily.allDone(daily) and not daily.chestPicked
	if daily.chestPicked then
		chestButton.Text = "✅ CHEST OPENED - SEE YOU TOMORROW"
		Theme.setButtonColor(chestButton, C.PanelLight, C.Muted)
	elseif chestReady then
		chestButton.Text = "🎁 OPEN THE DAILY CHEST!"
		Theme.setButtonColor(chestButton, C.Gold)
	else
		chestButton.Text = `🎁 DAILY CHEST · {done}/{#daily.quests} QUESTS DONE`
		Theme.setButtonColor(chestButton, C.PanelLight, C.Text)
	end
end

local function refreshData()
	local data = PlayerDataClient.get()
	refreshDaily(data)
	scrapPill.Text = if data.scrapBoost > 0
		then `🔩 {Theme.formatNumber(data.scrap)}  🚀x2`
		else `🔩 {Theme.formatNumber(data.scrap)}`
	local level, levelXp, levelNeed = Levels.levelFor(data.xp)
	playerLevel.Text = tostring(level)
	local title = Achievements.titleText(if data.title ~= "" then data.title else Achievements.levelTitle(level))
	playerTitle.Text = if data.winStreak >= 2 then `{title}   ·   🔥 {data.winStreak} WIN STREAK` else title
	playerXp.set(levelXp / levelNeed)
	playerXpText.Text = `{levelXp}/{levelNeed} XP`
	local done = 0
	for _ in data.achievements do
		done += 1
	end
	playerBadges.Text = `🏅 {done}/{#Achievements.List}`

	local goal = Rewards.nextGoal(data.owned, data.scrap)
	if goal then
		nextName.Text = `{goal.emoji} {goal.displayName}`
		nextAmount.Text = if goal.canAfford
			then "UNLOCK IT!"
			else `{Theme.formatNumber(goal.have)} / {Theme.formatNumber(goal.price)}`
		nextAmount.TextColor3 = if goal.canAfford then C.Gold else C.Muted
		nextBar.set(goal.have / math.max(goal.price, 1))
		nextBar.fill.BackgroundColor3 = if goal.canAfford then C.Gold else C.Good
	else
		nextName.Text = "🏆 Every car unlocked!"
		nextAmount.Text = ""
		nextBar.set(1)
	end

	-- This season.
	local day = PlayerDataClient.today()
	local info = Season.at(day)
	local current = data.season.number == info.number
	local tier = if current then data.season.tier else 0
	local xp = if current then data.season.xp else 0
	local into = xp - tier * Season.XpPerTier
	seasonTitle.Text = `{info.theme.Emoji} SEASON {info.number} · {string.upper(info.theme.Name)}`
	seasonTitle.TextColor3 = info.theme.Color
	local days = Season.daysLeft(day)
	seasonDays.Text = if days <= 1 then "LAST DAY!" else `⏳ {days} DAYS LEFT`
	seasonTier.Text = `⭐ TIER {tier}`
	local emoji, text = Season.describe(Season.rewardFor(info.theme, tier + 1))
	seasonNext.Text = `NEXT: {emoji} {text}`
	seasonXp.Text = `{Theme.formatNumber(into)} / {Theme.formatNumber(Season.XpPerTier)} XP · TAP TO SEE EVERY REWARD`
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
		spinner.Rotation = (os.clock() * 240) % 360
		if phase == Phases.Intermission then
			queueTitle.Text = `STARTING IN {math.ceil(MatchState.phaseSecondsLeft(stateObject, now))}`
			queueDetail.Text = "Get ready to drive!"
		elseif live then
			queueTitle.Text = "WAITING FOR A SEAT"
			queueDetail.Text = "This match is full - you're next!"
		elseif phase == Phases.Results then
			queueTitle.Text = "NEXT MATCH SOON"
			queueDetail.Text = "The last match is just finishing"
		else
			local dots = string.rep(".", math.floor(os.clock() * 2) % 4)
			queueTitle.Text = "FINDING MATCH" .. dots
			queueDetail.Text = "Friends who press PLAY now join you"
		end
	end

	if live then
		statusPill.Text = `🔴 LIVE  BLUE {numberAttr(MatchState.Attr.BlueScore)} - {numberAttr(
			MatchState.Attr.OrangeScore
		)} ORANGE  ·  PLAY TO JUMP IN!`
		statusPill.TextColor3 = C.Text
	else
		-- With others here, invite them to team up; on your own, a tip (never "1 player online").
		local count = #Players:GetPlayers()
		if count > 1 then
			statusPill.Text = `👋 {count} PLAYERS HERE · PRESS PLAY TO TEAM UP!`
			statusPill.TextColor3 = C.Text
		else
			statusPill.Text = TIPS[math.floor(os.clock() / 6) % #TIPS + 1]
			statusPill.TextColor3 = C.Muted
		end
	end

	local event = Twists.event(math.floor(now))
	if event then
		eventPill.Text = `{event.Emoji} {string.upper(event.Name)}: A TWIST EVERY MATCH + 50% SCRAP!`
		eventPill.TextColor3 = if math.floor(os.clock() * 2) % 2 == 0 then C.Gold else C.Text
	else
		local featured = Twists.featured(math.floor(now))
		eventPill.Text = `⭐ TWIST OF THE WEEK: {featured.Emoji} {string.upper(featured.Name)}`
		eventPill.TextColor3 = C.Gold
	end

	evolveBadge.Visible = evolveReady
	if evolveReady then
		evolveBadge.Rotation = 4 + math.sin(os.clock() * 5) * 3
	end

	-- Playtime gifts waiting: a red count on the button, which wiggles.
	local ready = giftsReady()
	giftBadge.Visible = ready > 0
	giftBadge.Text = tostring(ready)
	giftsButton.Rotation = if ready > 0 then math.sin(os.clock() * 8) * 3 else 0

	-- Things waiting to be collected pulse.
	local pulse = math.floor(os.clock() * 3) % 2 == 0
	if chestReady then
		Theme.setButtonColor(chestButton, if pulse then C.Gold else rgb(255, 232, 140))
	end
	if claimReady then
		for _, row in questRows do
			if row.claim.Visible then
				Theme.setButtonColor(row.claim, if pulse then C.Gold else rgb(255, 232, 140))
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
