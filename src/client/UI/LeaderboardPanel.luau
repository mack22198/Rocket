--!strict
-- This week's top 50 drivers (see Leaderboard): rank, name and the Scrap they've won in matches this week, with
-- your own score and when the week ends. It's read from the server each time it opens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)

local LeaderboardPanel = {}

LeaderboardPanel.Closed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

-- Gold, silver and bronze for the top three.
local MEDALS = { rgb(255, 202, 40), rgb(200, 208, 222), rgb(222, 140, 76) }

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local mineLabel: TextLabel
local endsLabel: TextLabel
local message: TextLabel
local loadToken = 0

local function clearRows()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function addRow(order: number, name: string, score: number, isMe: boolean)
	local row = Instance.new("Frame")
	row.Name = `Row{order}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -10, 0, 40)
	row.BackgroundColor3 = if isMe then C.Gold elseif order % 2 == 0 then C.Card else C.CardShade
	row.Parent = list
	Theme.corner(row, 10)
	if isMe then
		Theme.stroke(row, C.Ink, 2)
	end
	local medal = MEDALS[order]
	local rank = Theme.heading(row, {
		name = "Rank",
		size = UDim2.fromOffset(if medal then 30 else 56, 30),
		position = UDim2.fromOffset(if medal then 14 else 4, 5),
		text = if medal then tostring(order) else `#{order}`,
		color = C.Ink,
		textSize = if medal then 20 else 18,
	})
	if medal then
		rank.BackgroundColor3 = medal
		rank.BackgroundTransparency = 0
		Theme.corner(rank, 15)
		Theme.stroke(rank, C.Ink, 2)
	end
	Theme.label(row, {
		name = "Name",
		size = UDim2.new(1, -230, 0, 20),
		position = UDim2.fromOffset(70, 10),
		text = name,
		textSize = 17,
		align = Enum.TextXAlignment.Left,
	})
	Theme.amount(row, 24, UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5)).set(score)
end

local function timeLeft(seconds: number): string
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	if days > 0 then
		return `{days}d {hours}h`
	end
	return `{hours}h {(seconds % 3600) // 60}m`
end

local function load()
	loadToken += 1
	local token = loadToken
	clearRows()
	message.Text = "Loading..."
	message.Visible = true
	mineLabel.Text = ""
	endsLabel.Text = ""
	task.spawn(function()
		local ok, board = pcall(function()
			return Remotes.Leaderboard:InvokeServer()
		end)
		if token ~= loadToken then
			return
		end
		if not ok or type(board) ~= "table" or board.available ~= true then
			message.Text = "The leaderboard starts once the game is published. Go win some matches!"
			return
		end
		local top = if type(board.top) == "table" then board.top else {}
		message.Visible = #top == 0
		message.Text = "Nobody's on the board yet this week. Win a match to be first!"
		for order, entry in top do
			local isMe = entry.userId == localPlayer.UserId
			addRow(order, tostring(entry.name), tonumber(entry.score) or 0, isMe)
		end
		mineLabel.Text = `YOU THIS WEEK: {Theme.formatNumber(tonumber(board.mine) or 0)} SCRAP`
		if type(board.secondsLeft) == "number" then
			endsLabel.Text = `NEW WEEK IN {string.upper(timeLeft(board.secondsLeft))}`
		end
	end)
end

local function build()
	gui = Theme.screen("TurboLeaderboard", 41)
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(6, 8, 18)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	panel =
		Theme.card(gui, "Leaderboard", UDim2.fromOffset(720, 610), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 20)
	Theme.heading(panel, {
		name = "Title",
		size = UDim2.fromOffset(480, 46),
		text = "TOP 50 THIS WEEK",
		textSize = 44,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, {
		name = "Subtitle",
		size = UDim2.fromOffset(520, 18),
		position = UDim2.fromOffset(2, 50),
		text = "Win Scrap in matches to climb. Everyone starts again on Monday!",
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
		LeaderboardPanel.close()
	end)
	mineLabel = Theme.pill(panel, {
		name = "Mine",
		size = UDim2.fromOffset(320, 30),
		position = UDim2.fromOffset(0, 84),
		text = "",
		background = C.Gold,
	})
	endsLabel = Theme.pill(panel, {
		name = "Ends",
		size = UDim2.fromOffset(240, 30),
		position = UDim2.new(1, 0, 0, 84),
		anchor = Vector2.new(1, 0),
		text = "",
	})

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 1, -130)
	list.Position = UDim2.fromOffset(0, 130)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = C.Ink
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	message = Theme.label(panel, {
		name = "Message",
		size = UDim2.new(1, -40, 0, 60),
		position = UDim2.new(0.5, 0, 0.5, 40),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 18,
	})
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function LeaderboardPanel.open()
	gui.Enabled = true
	load()
	panel.Position = UDim2.fromScale(0.5, 0.56)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) })
		:Play()
	Theme.focus(nil)
end

function LeaderboardPanel.close()
	if gui.Enabled then
		gui.Enabled = false
		LeaderboardPanel.Closed:Fire()
	end
end

function LeaderboardPanel.isOpen(): boolean
	return gui.Enabled
end

function LeaderboardPanel.start()
	build()
end

return LeaderboardPanel
