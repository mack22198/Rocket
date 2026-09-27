--!strict
-- The daily pop-ups: the login-streak calendar (collect today's Scrap) and the daily chest, where all three
-- prizes are shown face up and you pick the one you want. Nothing is hidden or left to chance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local DailyRewards = {}

-- Fired when a pop-up closes.
DailyRewards.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

type DayCell = { frame: Frame, day: TextLabel, amount: TextLabel, mark: TextLabel, stroke: UIStroke }
type ChestCard = {
	frame: Frame,
	emoji: TextLabel,
	title: TextLabel,
	text: TextLabel,
	button: TextButton,
	stroke: UIStroke,
}

local gui: ScreenGui
local streakPanel: Frame
local streakTitle: TextLabel
local claimButton: TextButton
local dayCells: { DayCell } = {}
local chestPanel: Frame
local chestSubtitle: TextLabel
local chestCards: { ChestCard } = {}
local toast: TextLabel
local busy = false
local shownDay = -1

local function showToast(text: string, good: boolean)
	toast.Text = text
	toast.TextColor3 = if good then C.Good else C.Bad
	toast.Visible = true
	toast.TextTransparency = 0
	task.delay(2.4, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

local function request(action: string, index: number?): boolean
	if busy then
		return false
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.Daily:InvokeServer(action, index)
	end)
	busy = false
	if ok and type(result) == "table" then
		showToast(tostring(result.message), result.ok == true)
		return result.ok == true
	end
	showToast("Couldn't reach the server. Try again!", false)
	return false
end

-- A little shower of Scrap bolts from the middle of the screen.
local function sparkle(from: GuiObject)
	for i = 1, 14 do
		local bolt = Theme.label(gui, {
			size = UDim2.fromOffset(34, 34),
			position = UDim2.fromOffset(from.AbsolutePosition.X + from.AbsoluteSize.X / 2, from.AbsolutePosition.Y),
			anchor = Vector2.new(0.5, 0.5),
			text = if i % 3 == 0 then "✨" else "🔩",
			stroke = false,
			zIndex = 20,
		})
		local angle = i / 14 * math.pi * 2
		TweenService:Create(bolt, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(
				bolt.Position.X.Offset + math.cos(angle) * 220,
				bolt.Position.Y.Offset + math.sin(angle) * 140 - 60
			),
			TextTransparency = 1,
			Rotation = 180,
		}):Play()
		task.delay(1, function()
			bolt:Destroy()
		end)
	end
end

local function close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		DailyRewards.Closed:Fire()
	end
end

local function closeButton(parent: Frame)
	local button = Theme.button(parent, {
		name = "Close",
		size = UDim2.fromOffset(54, 46),
		position = UDim2.new(1, -14, 0, 14),
		anchor = Vector2.new(1, 0),
		text = "✕",
		color = C.PanelLight,
		textColor = C.Text,
	})
	button.Activated:Connect(close)
end

local function buildStreak()
	streakPanel =
		Theme.panel(gui, "Streak", UDim2.fromOffset(820, 380), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	Theme.scaled(streakPanel)
	closeButton(streakPanel)
	streakTitle = Theme.label(streakPanel, {
		name = "Title",
		size = UDim2.fromOffset(640, 52),
		position = UDim2.new(0.5, 0, 0, 22),
		anchor = Vector2.new(0.5, 0),
		text = "",
		color = C.Gold,
	})
	Theme.label(streakPanel, {
		name = "Subtitle",
		size = UDim2.fromOffset(640, 20),
		position = UDim2.new(0.5, 0, 0, 78),
		anchor = Vector2.new(0.5, 0),
		text = "PLAY EVERY DAY - THE REWARD GROWS UNTIL DAY 7!",
		font = Theme.Caps,
		color = C.Muted,
		stroke = false,
	})
	for i = 1, #Daily.StreakRewards do
		local x = 30 + (i - 1) * 110
		local frame = Instance.new("Frame")
		frame.Name = `Day{i}`
		frame.Size = UDim2.fromOffset(100, 130)
		frame.Position = UDim2.fromOffset(x, 118)
		frame.BackgroundColor3 = C.PanelDark
		frame.Parent = streakPanel
		Theme.corner(frame, 14)
		local stroke = Theme.stroke(frame, rgb(255, 255, 255), 2)
		local day = Theme.label(frame, {
			size = UDim2.new(1, 0, 0, 22),
			position = UDim2.fromOffset(0, 10),
			text = if i == #Daily.StreakRewards then `DAY {i}+` else `DAY {i}`,
			font = Theme.Caps,
			stroke = false,
		})
		local amount = Theme.label(frame, {
			size = UDim2.new(1, -10, 0, 30),
			position = UDim2.fromOffset(5, 44),
			text = `🔩{Daily.StreakRewards[i]}`,
			color = C.Scrap,
		})
		amount.TextWrapped = false -- keep the bolt and the number on one line
		local mark = Theme.label(frame, {
			size = UDim2.new(1, 0, 0, 34),
			position = UDim2.fromOffset(0, 84),
			text = "",
			stroke = false,
		})
		table.insert(dayCells, { frame = frame, day = day, amount = amount, mark = mark, stroke = stroke })
	end
	claimButton = Theme.button(streakPanel, {
		name = "Claim",
		size = UDim2.fromOffset(300, 64),
		position = UDim2.new(0.5, 0, 1, -24),
		anchor = Vector2.new(0.5, 1),
		text = "",
		color = C.Gold,
	})
	Theme.sweep(claimButton, 2.5)
	claimButton.Activated:Connect(function()
		local data = PlayerDataClient.get()
		if not Daily.canClaimStreak(data.daily, PlayerDataClient.today()) then
			close()
			return
		end
		if request("streak") then
			sparkle(claimButton)
			task.delay(1.2, close)
		end
	end)
end

local function buildChest()
	chestPanel =
		Theme.panel(gui, "Chest", UDim2.fromOffset(860, 500), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(chestPanel)
	closeButton(chestPanel)
	Theme.label(chestPanel, {
		name = "Title",
		size = UDim2.fromOffset(640, 52),
		position = UDim2.new(0.5, 0, 0, 20),
		anchor = Vector2.new(0.5, 0),
		text = "🎁 DAILY CHEST",
		color = C.Gold,
	})
	chestSubtitle = Theme.label(chestPanel, {
		name = "Subtitle",
		size = UDim2.fromOffset(640, 20),
		position = UDim2.new(0.5, 0, 0, 76),
		anchor = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		stroke = false,
	})
	for i = 1, 3 do
		local frame = Instance.new("Frame")
		frame.Name = `Prize{i}`
		frame.Size = UDim2.fromOffset(250, 330)
		frame.Position = UDim2.fromOffset(30 + (i - 1) * 270, 118)
		frame.BackgroundColor3 = C.PanelDark
		frame.Parent = chestPanel
		Theme.corner(frame, 18)
		local stroke = Theme.stroke(frame, C.Gold, 2)
		stroke.Transparency = 0.5
		local emoji = Theme.label(frame, {
			size = UDim2.fromOffset(110, 110),
			position = UDim2.new(0.5, 0, 0, 20),
			anchor = Vector2.new(0.5, 0),
			text = "",
			stroke = false,
		})
		local title = Theme.label(frame, {
			size = UDim2.new(1, -20, 0, 34),
			position = UDim2.fromOffset(10, 140),
			text = "",
			color = C.Gold,
		})
		local text = Theme.label(frame, {
			size = UDim2.new(1, -30, 0, 50),
			position = UDim2.fromOffset(15, 180),
			text = "",
			font = Theme.Body,
			color = C.Text,
			stroke = false,
			scaled = false,
			textSize = 16,
		})
		local button = Theme.button(frame, {
			name = "Pick",
			size = UDim2.new(1, -40, 0, 56),
			position = UDim2.new(0.5, 0, 1, -18),
			anchor = Vector2.new(0.5, 1),
			text = "PICK THIS",
			color = C.Good,
		})
		local index = i
		button.Activated:Connect(function()
			if request("chest", index) then
				sparkle(button)
				for j, card in chestCards do
					if j == index then
						card.stroke.Transparency = 0
						card.stroke.Thickness = 5
						card.button.Text = "✅ YOURS!"
					else
						card.frame.BackgroundTransparency = 0.6
						card.button.Visible = false
					end
				end
				task.delay(1.8, close)
			end
		end)
		table.insert(
			chestCards,
			{ frame = frame, emoji = emoji, title = title, text = text, button = button, stroke = stroke }
		)
	end
end

local function build()
	gui = Theme.screen("TurboDaily", 42)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui
	buildStreak()
	buildChest()
	toast = Theme.pill(gui, {
		name = "Toast",
		size = UDim2.fromOffset(520, 40),
		position = UDim2.new(0.5, 0, 1, -30),
		anchor = Vector2.new(0.5, 1),
		text = "",
		background = C.PanelDark,
		transparency = 0,
	})
	toast.ZIndex = 10
	toast.Visible = false
	Theme.scaled(toast)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- The streak calendar, with today's reward to collect.
function DailyRewards.openStreak()
	local data = PlayerDataClient.get()
	local today = PlayerDataClient.today()
	local streak = math.max(1, data.daily.streak)
	local claimable = Daily.canClaimStreak(data.daily, today)
	streakTitle.Text = if streak == 1 then "🔥 DAY 1 - WELCOME!" else `🔥 {streak}-DAY STREAK!`
	local current = math.min(streak, #Daily.StreakRewards)
	for i, cell in dayCells do
		local done = i < current or (i == current and not claimable)
		local isToday = i == current
		cell.frame.BackgroundColor3 = if isToday then rgb(70, 58, 20) elseif done then rgb(28, 60, 40) else C.PanelDark
		cell.stroke.Color = if isToday then C.Gold elseif done then C.Good else rgb(255, 255, 255)
		cell.stroke.Transparency = if isToday or done then 0 else 0.85
		cell.stroke.Thickness = if isToday then 4 else 2
		cell.mark.Text = if done then "✅" elseif isToday then "TODAY" else ""
		cell.mark.Font = Theme.Caps
		cell.mark.TextColor3 = if isToday then C.Gold else C.Good
		cell.amount.TextTransparency = if i > current then 0.45 else 0
	end
	claimButton.Text = if claimable then `COLLECT 🔩 {Daily.streakReward(streak)}` else "SEE YOU TOMORROW!"
	Theme.setButtonColor(claimButton, if claimable then C.Gold else C.PanelLight, if claimable then nil else C.Text)
	streakPanel.Visible = true
	chestPanel.Visible = false
	gui.Enabled = true
	shownDay = today
	Theme.focus(claimButton)
end

-- The daily chest: three prizes, face up. Pick one.
function DailyRewards.openChest()
	local data = PlayerDataClient.get()
	local today = PlayerDataClient.today()
	local options = Daily.chestOptions(localPlayer.UserId, today)
	local ready = Daily.allDone(data.daily) and not data.daily.chestPicked
	chestSubtitle.Text = if data.daily.chestPicked
		then "YOU'VE OPENED TODAY'S CHEST - A NEW ONE COMES TOMORROW!"
		elseif ready then "PICK ONE PRIZE - YOU CAN SEE THEM ALL!"
		else "FINISH ALL 3 DAILY QUESTS TO OPEN IT. HERE'S WHAT'S INSIDE TODAY:"
	for i, card in chestCards do
		local option = options[i]
		card.emoji.Text = option.Emoji
		card.title.Text = option.Title
		card.text.Text = option.Text
		card.frame.BackgroundTransparency = 0
		card.stroke.Transparency = 0.5
		card.stroke.Thickness = 2
		card.button.Visible = ready
		card.button.Text = "PICK THIS"
	end
	streakPanel.Visible = false
	chestPanel.Visible = true
	gui.Enabled = true
	Theme.focus(if ready then chestCards[1].button else nil)
end

-- Shows the streak calendar if today's reward hasn't been collected (once per day per visit to the menu).
function DailyRewards.offerStreak(): boolean
	local data = PlayerDataClient.get()
	local today = PlayerDataClient.today()
	if not PlayerDataClient.isLoaded() or shownDay == today or not Daily.canClaimStreak(data.daily, today) then
		return false
	end
	DailyRewards.openStreak()
	return true
end

function DailyRewards.close()
	close()
end

function DailyRewards.isOpen(): boolean
	return gui.Enabled
end

function DailyRewards.start()
	build()
end

return DailyRewards
