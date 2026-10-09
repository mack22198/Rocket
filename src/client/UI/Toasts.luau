--!strict
-- Little cards that slide in at the top of the screen when you reach a new level or finish an achievement (with
-- the Scrap it paid and any title it unlocked). They queue up, so a match that finishes several shows them one
-- after another.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Theme)

local Toasts = {}

export type Toast = {
	badge: string, -- what's in the square on the left: a level number, or an achievement's picture
	picture: boolean?, -- (true when the badge is an emoji picture rather than a number)
	title: string,
	text: string,
	reward: number?,
	color: Color3,
}

local C = Theme.Colors
local SHOW_FOR = 3.2
local HIDDEN = UDim2.new(0.5, 0, 0, -120)
local SHOWN = UDim2.new(0.5, 0, 0, 16)

local gui: ScreenGui
local card: Frame
local badge: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local reward: Theme.Amount
local queue: { Toast } = {}
local running = false

local function present(toast: Toast)
	badge.Text = toast.badge
	badge.Font = if toast.picture then Theme.Title else Theme.Display
	badge.BackgroundColor3 = toast.color
	titleLabel.Text = toast.title
	textLabel.Text = toast.text
	reward.frame.Visible = toast.reward ~= nil and toast.reward > 0
	reward.set(toast.reward or 0, "+")
	gui.Enabled = true
	card.Position = HIDDEN
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = SHOWN,
	}):Play()
	SoundController.play("Fanfare", 0.7, 1.1)
	task.wait(SHOW_FOR)
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = HIDDEN,
	}):Play()
	task.wait(0.35)
end

local function run()
	running = true
	while #queue > 0 do
		present(table.remove(queue, 1) :: Toast)
	end
	gui.Enabled = false
	running = false
end

function Toasts.push(toast: Toast)
	table.insert(queue, toast)
	if not running then
		task.spawn(run)
	end
end

-- An achievement the server says is done: { emoji, name, text, reward, title? }.
function Toasts.achievement(info: { [string]: any })
	local title = if type(info.title) == "string" then ` New title: {Theme.noEmoji(info.title)}!` else ""
	Toasts.push({
		badge = tostring(info.emoji or "?"),
		picture = true,
		title = `ACHIEVEMENT: {string.upper(tostring(info.name or ""))}`,
		text = `{info.text or ""}.{title}`,
		reward = if type(info.reward) == "number" then info.reward else nil,
		color = C.Gold,
	})
end

-- A level reached: { level, scrap, title? }.
function Toasts.levelUp(info: { [string]: any })
	Toasts.push({
		badge = tostring(info.level or "?"),
		title = `LEVEL UP! YOU'RE LEVEL {info.level or "?"}`,
		text = if type(info.title) == "string"
			then `New title: {Theme.noEmoji(info.title)}!`
			else "Keep playing to reach the next one!",
		reward = if type(info.scrap) == "number" then info.scrap else nil,
		color = C.Evolve,
	})
end

function Toasts.start()
	gui = Theme.screen("TurboToasts", 60)
	gui.Enabled = false
	card = Theme.card(gui, "Toast", UDim2.fromOffset(580, 88), HIDDEN, Vector2.new(0.5, 0))
	Theme.scaled(card)
	badge = Theme.heading(card, {
		name = "Badge",
		size = UDim2.fromOffset(62, 62),
		position = UDim2.fromOffset(12, 10),
		text = "",
		color = C.Text,
		textSize = 40,
		stroke = true,
	})
	badge.BackgroundTransparency = 0
	Theme.corner(badge, 14)
	Theme.stroke(badge, C.Ink, 3)
	titleLabel = Theme.heading(card, {
		name = "Title",
		size = UDim2.fromOffset(370, 26),
		position = UDim2.fromOffset(88, 14),
		text = "",
		textSize = 24,
		align = Enum.TextXAlignment.Left,
	})
	titleLabel.TextWrapped = false
	textLabel = Theme.label(card, {
		name = "Text",
		size = UDim2.fromOffset(370, 34),
		position = UDim2.fromOffset(88, 44),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		scaled = false,
		textSize = 14,
		align = Enum.TextXAlignment.Left,
	})
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	reward = Theme.amount(card, 28, UDim2.new(1, -16, 0.5, -3), Vector2.new(1, 0.5))
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Achievements finished outside a match (in the garage, from the daily rewards...). A match's own level-ups
	-- and achievements come with the results (see ResultsScreen).
	Remotes.Progress.OnClientEvent:Connect(function(kind: unknown, info: unknown)
		if kind == "achievement" and type(info) == "table" then
			Toasts.achievement(info :: { [string]: any })
		end
	end)
end

return Toasts
