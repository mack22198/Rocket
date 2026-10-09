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

type DayCell = { frame: Frame, day: TextLabel, amount: Theme.Amount, mark: TextLabel, stroke: UIStroke }
type ChestCard = {
	frame: Frame,
	emoji: TextLabel,
	coin: Frame,
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
	text = Theme.noEmoji(text)
	toast.Text = text
	toast.BackgroundColor3 = if good then C.Good else C.Bad
	toast.TextColor3 = C.Text
	toast.Visible = true
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0
	task.delay(2.4, function()
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

-- A little shower of Scrap coins from a button.
local function sparkle(from: GuiObject)
	local scale = math.max(Theme.getScale(), 0.01)
	for i = 1, 14 do
		local coin = Theme.scrapIcon(
			gui,
			math.floor(30 * scale),
			UDim2.fromOffset(from.AbsolutePosition.X + from.AbsoluteSize.X / 2, from.AbsolutePosition.Y),
			Vector2.new(0.5, 0.5)
		)
		coin.ZIndex = 20
		local angle = i / 14 * math.pi * 2
		TweenService:Create(coin, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(
				coin.Position.X.Offset + math.cos(angle) * 220 * scale,
				coin.Position.Y.Offset + (math.sin(angle) * 140 - 60) * scale
			),
			Size = UDim2.fromOffset(0, 0),
			Rotation = 180,
		}):Play()
		task.delay(1, function()
			coin:Destroy()
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
		size = UDim2.fromOffset(52, 48),
		position = UDim2.new(1, -16, 0, 16),
		anchor = Vector2.new(1, 0),
		text = "X",
		color = C.Panel,
		textSize = 26,
	})
	button.Activated:Connect(close)
end

local function buildStreak()
	streakPanel =
		Theme.card(gui, "Streak", UDim2.fromOffset(824, 392), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	Theme.scaled(streakPanel)
	closeButton(streakPanel)
	streakTitle = Theme.heading(streakPanel, {
		name = "Title",
		size = UDim2.fromOffset(640, 48),
		position = UDim2.new(0.5, 0, 0, 24),
		anchor = Vector2.new(0.5, 0),
		text = "",
		textSize = 46,
	})
	Theme.label(streakPanel, {
		name = "Subtitle",
		size = UDim2.fromOffset(640, 20),
		position = UDim2.new(0.5, 0, 0, 78),
		anchor = Vector2.new(0.5, 0),
		text = "Play every day. The reward grows until day 7!",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 17,
	})
	for i = 1, #Daily.StreakRewards do
		local x = 32 + (i - 1) * 110
		local frame = Theme.well(streakPanel, `Day{i}`, UDim2.fromOffset(100, 134), UDim2.fromOffset(x, 118))
		local stroke = Theme.stroke(frame, C.Ink, 2)
		local day = Theme.label(frame, {
			size = UDim2.new(1, 0, 0, 16),
			position = UDim2.fromOffset(0, 12),
			text = if i == #Daily.StreakRewards then `DAY {i}+` else `DAY {i}`,
			font = Theme.Caps,
			textSize = 14,
		})
		local amount = Theme.amount(frame, 26, UDim2.new(0.5, 0, 0, 44), Vector2.new(0.5, 0))
		amount.set(Daily.StreakRewards[i])
		local mark = Theme.pill(frame, {
			size = UDim2.fromOffset(76, 24),
			position = UDim2.new(0.5, 0, 1, -14),
			anchor = Vector2.new(0.5, 1),
			text = "",
		})
		table.insert(dayCells, { frame = frame, day = day, amount = amount, mark = mark, stroke = stroke })
	end
	claimButton = Theme.button(streakPanel, {
		name = "Claim",
		size = UDim2.fromOffset(340, 66),
		position = UDim2.new(0.5, 0, 1, -26),
		anchor = Vector2.new(0.5, 1),
		text = "",
		color = C.Gold,
		textSize = 30,
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
	chestPanel = Theme.card(gui, "Chest", UDim2.fromOffset(864, 512), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(chestPanel)
	closeButton(chestPanel)
	Theme.heading(chestPanel, {
		name = "Title",
		size = UDim2.fromOffset(640, 48),
		position = UDim2.new(0.5, 0, 0, 22),
		anchor = Vector2.new(0.5, 0),
		text = "DAILY CHEST",
		textSize = 46,
	})
	chestSubtitle = Theme.label(chestPanel, {
		name = "Subtitle",
		size = UDim2.fromOffset(640, 20),
		position = UDim2.new(0.5, 0, 0, 76),
		anchor = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 17,
	})
	for i = 1, 3 do
		local frame =
			Theme.well(chestPanel, `Prize{i}`, UDim2.fromOffset(250, 336), UDim2.fromOffset(32 + (i - 1) * 274, 118))
		local stroke = Theme.stroke(frame, C.Ink, 2)
		local emoji = Theme.label(frame, {
			size = UDim2.fromOffset(110, 110),
			position = UDim2.new(0.5, 0, 0, 22),
			anchor = Vector2.new(0.5, 0),
			text = "",
			textSize = 90,
		})
		local coin = Theme.scrapIcon(frame, 92, UDim2.new(0.5, 0, 0, 30), Vector2.new(0.5, 0))
		coin.Visible = false
		local title = Theme.heading(frame, {
			size = UDim2.new(1, -20, 0, 32),
			position = UDim2.fromOffset(10, 146),
			text = "",
			textSize = 28,
		})
		local text = Theme.label(frame, {
			size = UDim2.new(1, -30, 0, 50),
			position = UDim2.fromOffset(15, 184),
			text = "",
			font = Theme.Body,
			color = C.InkMuted,
			scaled = false,
			textSize = 15,
		})
		local button = Theme.button(frame, {
			name = "Pick",
			size = UDim2.new(1, -36, 0, 58),
			position = UDim2.new(0.5, 0, 1, -18),
			anchor = Vector2.new(0.5, 1),
			text = "PICK THIS",
			color = C.Good,
			textSize = 26,
		})
		local index = i
		button.Activated:Connect(function()
			if request("chest", index) then
				sparkle(button)
				for j, card in chestCards do
					if j == index then
						card.frame.BackgroundColor3 = C.Gold
						card.stroke.Thickness = 4
						card.button.Text = "YOURS!"
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
			{ frame = frame, emoji = emoji, coin = coin, title = title, text = text, button = button, stroke = stroke }
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
	dim.BackgroundColor3 = rgb(6, 8, 18)
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
	streakTitle.Text = if streak == 1 then "DAY 1: WELCOME!" else `{streak}-DAY STREAK!`
	local current = math.min(streak, #Daily.StreakRewards)
	for i, cell in dayCells do
		local done = i < current or (i == current and not claimable)
		local isToday = i == current
		cell.frame.BackgroundColor3 = if isToday then C.Gold else C.CardShade
		cell.stroke.Thickness = if isToday then 4 else 2
		cell.mark.Visible = done or isToday
		cell.mark.Text = if done then "DONE" else "TODAY"
		cell.mark.BackgroundColor3 = if done then C.Good else C.Ink
		cell.mark.TextColor3 = C.Text
		cell.amount.label.TextTransparency = if i > current then 0.5 else 0
		cell.day.TextTransparency = if i > current then 0.5 else 0
	end
	claimButton.Text = if claimable then `COLLECT {Daily.streakReward(streak)} SCRAP` else "SEE YOU TOMORROW!"
	Theme.setButtonColor(claimButton, if claimable then C.Gold else C.Panel)
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
		then "You've opened today's chest. A new one comes tomorrow!"
		elseif ready then "Pick one prize. You can see them all!"
		else "Finish all 3 daily quests to open it. Here's what's inside today:"
	for i, card in chestCards do
		local option = options[i]
		local scrap = option.Kind == "scrap"
		card.coin.Visible = scrap
		card.emoji.Visible = not scrap
		card.emoji.Text = option.Emoji
		card.title.Text = Theme.noEmoji(option.Title)
		card.text.Text = option.Text
		card.frame.BackgroundColor3 = C.CardShade
		card.frame.BackgroundTransparency = 0
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
