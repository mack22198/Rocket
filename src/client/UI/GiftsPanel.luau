--!strict
-- Playtime gifts (see Gifts): the whole ladder of free gifts for this visit, each with its prize showing, a
-- countdown until it's ready and an OPEN! button when it is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gifts = require(Shared.Config.Gifts)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local GiftsPanel = {}

GiftsPanel.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

type Card = { frame: Frame, stroke: UIStroke, icon: TextLabel, button: TextButton }

local gui: ScreenGui
local panel: Frame
local cards: { Card } = {}
local opening = false

-- (seconds played this visit, gifts opened)
local function state(): (number, { [number]: boolean })
	local opened: { [number]: boolean } = {}
	local list = localPlayer:GetAttribute(MatchState.PlayerAttr.GiftsOpened)
	if type(list) == "string" then
		for index in string.gmatch(list, "%d+") do
			opened[tonumber(index) :: number] = true
		end
	end
	local started = localPlayer:GetAttribute(MatchState.PlayerAttr.PlayStart)
	local played = if type(started) == "number" then workspace:GetServerTimeNow() - started else 0
	return played, opened
end

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function open(index: number)
	if opening then
		return
	end
	opening = true
	local ok, result = pcall(function()
		return Remotes.Gift:InvokeServer(index)
	end)
	opening = false
	if ok and type(result) == "table" and result.ok then
		Toasts.push({
			emoji = "🎁",
			title = "GIFT OPENED!",
			text = `{result.emoji or ""} {result.text or ""}`,
			color = C.Good,
		})
	else
		SoundController.play("Click", 0.5, 0.7)
	end
end

local function refresh()
	local played, opened = state()
	for index, card in cards do
		local gift = Gifts.Ladder[index]
		local ready = Gifts.ready(index, played, opened)
		if opened[index] then
			card.button.Text = "✅ OPENED"
			Theme.setButtonColor(card.button, C.PanelLight, C.Muted)
			card.stroke.Transparency = 0.8
			card.icon.TextTransparency = 0.5
		elseif ready then
			card.button.Text = "OPEN!"
			local pulse = math.floor(os.clock() * 3) % 2 == 0
			Theme.setButtonColor(card.button, if pulse then C.Good else rgb(140, 240, 160))
			card.stroke.Transparency = 0
			card.icon.TextTransparency = 0
			card.icon.Rotation = math.sin(os.clock() * 8 + index) * 8
		else
			card.button.Text = `⏳ {clock(gift.Minutes * 60 - played)}`
			Theme.setButtonColor(card.button, C.PanelLight, C.Text)
			card.stroke.Transparency = 0.6
			card.icon.TextTransparency = 0
			card.icon.Rotation = 0
		end
	end
end

local function build()
	gui = Theme.screen("TurboGifts", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = gui

	panel = Theme.panel(gui, "Gifts", UDim2.fromOffset(820, 500), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)
	Theme.label(panel, {
		name = "Title",
		size = UDim2.fromOffset(500, 46),
		text = "🎁 PLAYTIME GIFTS",
		color = C.Good,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, {
		name = "Subtitle",
		size = UDim2.fromOffset(600, 20),
		position = UDim2.fromOffset(2, 48),
		text = "Free gifts for playing! They start again next time you join.",
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
		GiftsPanel.close()
	end)

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, -86)
	grid.Position = UDim2.fromOffset(0, 86)
	grid.BackgroundTransparency = 1
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.25, -9, 0.5, -6)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, gift in Gifts.Ladder do
		local frame = Instance.new("Frame")
		frame.Name = `Gift{index}`
		frame.LayoutOrder = index
		frame.BackgroundColor3 = C.PanelDark
		frame.Parent = grid
		Theme.corner(frame, 14)
		local stroke = Theme.stroke(frame, C.Good, 2)
		Theme.label(frame, {
			name = "When",
			size = UDim2.new(1, -16, 0, 18),
			position = UDim2.fromOffset(8, 8),
			text = `{gift.Minutes} MIN`,
			font = Theme.Caps,
			color = C.Muted,
			stroke = false,
		})
		local emoji, text = Gifts.describe(gift)
		local icon = Theme.label(frame, {
			name = "Icon",
			size = UDim2.fromOffset(60, 52),
			position = UDim2.new(0.5, 0, 0, 30),
			anchor = Vector2.new(0.5, 0),
			text = emoji,
			stroke = false,
		})
		Theme.label(frame, {
			name = "Prize",
			size = UDim2.new(1, -16, 0, 24),
			position = UDim2.fromOffset(8, 86),
			text = text,
			color = if gift.Kind == "boost" then C.Evolve else C.Scrap,
		})
		local button = Theme.button(frame, {
			name = "Open",
			size = UDim2.new(1, -20, 0, 40),
			position = UDim2.new(0.5, 0, 1, -10),
			anchor = Vector2.new(0.5, 1),
			text = "",
			color = C.PanelLight,
			textColor = C.Text,
		})
		button.Activated:Connect(function()
			open(index)
		end)
		table.insert(cards, { frame = frame, stroke = stroke, icon = icon, button = button })
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function GiftsPanel.open()
	gui.Enabled = true
	refresh()
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
	Theme.focus(cards[1] and cards[1].button)
end

function GiftsPanel.close()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
		GiftsPanel.Closed:Fire()
	end
end

function GiftsPanel.isOpen(): boolean
	return gui.Enabled
end

function GiftsPanel.start()
	build()
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
end

return GiftsPanel
