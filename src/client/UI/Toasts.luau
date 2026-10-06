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

export type Toast = { emoji: string, title: string, text: string, reward: number?, color: Color3 }

local C = Theme.Colors
local SHOW_FOR = 3.2
local HIDDEN = UDim2.new(0.5, 0, 0, -110)
local SHOWN = UDim2.new(0.5, 0, 0, 14)

local gui: ScreenGui
local card: Frame
local stroke: UIStroke
local icon: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local rewardLabel: TextLabel
local queue: { Toast } = {}
local running = false

local function present(toast: Toast)
	icon.Text = toast.emoji
	icon.BackgroundColor3 = toast.color
	titleLabel.Text = toast.title
	titleLabel.TextColor3 = toast.color
	textLabel.Text = toast.text
	rewardLabel.Visible = toast.reward ~= nil and toast.reward > 0
	rewardLabel.Text = `+🔩{Theme.formatNumber(toast.reward or 0)}`
	stroke.Color = toast.color
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
	local title = if type(info.title) == "string" then `   ·   New title: {info.title}` else ""
	Toasts.push({
		emoji = tostring(info.emoji or "🏅"),
		title = `ACHIEVEMENT: {string.upper(tostring(info.name or ""))}`,
		text = `{info.text or ""}{title}`,
		reward = if type(info.reward) == "number" then info.reward else nil,
		color = C.Gold,
	})
end

-- A level reached: { level, scrap, title? }.
function Toasts.levelUp(info: { [string]: any })
	Toasts.push({
		emoji = "⭐",
		title = `LEVEL UP! YOU'RE LEVEL {info.level or "?"}`,
		text = if type(info.title) == "string"
			then `New title: {info.title}`
			else "Keep playing to reach the next one!",
		reward = if type(info.scrap) == "number" then info.scrap else nil,
		color = C.Evolve,
	})
end

function Toasts.start()
	gui = Theme.screen("TurboToasts", 60)
	gui.Enabled = false
	card = Theme.panel(gui, "Toast", UDim2.fromOffset(560, 84), HIDDEN, Vector2.new(0.5, 0))
	Theme.scaled(card)
	stroke = Theme.stroke(card, C.Gold, 3)
	icon = Theme.label(card, {
		name = "Icon",
		size = UDim2.fromOffset(64, 64),
		position = UDim2.fromOffset(10, 10),
		text = "",
		stroke = false,
	})
	icon.BackgroundTransparency = 0.6
	Theme.corner(icon, 32)
	titleLabel = Theme.label(card, {
		name = "Title",
		size = UDim2.fromOffset(360, 30),
		position = UDim2.fromOffset(86, 10),
		text = "",
		align = Enum.TextXAlignment.Left,
	})
	textLabel = Theme.label(card, {
		name = "Text",
		size = UDim2.fromOffset(360, 34),
		position = UDim2.fromOffset(86, 42),
		text = "",
		font = Theme.Body,
		color = C.Text,
		align = Enum.TextXAlignment.Left,
		stroke = false,
		scaled = false,
		textSize = 15,
	})
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	rewardLabel = Theme.label(card, {
		name = "Reward",
		size = UDim2.fromOffset(100, 36),
		position = UDim2.new(1, -110, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = "",
		color = C.Scrap,
	})
	rewardLabel.TextWrapped = false
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
