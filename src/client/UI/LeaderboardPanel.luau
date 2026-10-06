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

local MEDALS = { "🥇", "🥈", "🥉" }

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

local function addRow(order: number, rank: string, name: string, score: string, isMe: boolean)
	local row = Instance.new("Frame")
	row.Name = `Row{order}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 36)
	row.BackgroundColor3 = if isMe then C.Gold elseif order % 2 == 0 then C.PanelLight else C.PanelDark
	row.BackgroundTransparency = if isMe then 0.55 else 0.35
	row.Parent = list
	Theme.corner(row, 8)
	Theme.label(row, {
		name = "Rank",
		size = UDim2.fromOffset(60, 28),
		position = UDim2.fromOffset(8, 4),
		text = rank,
		color = if order <= 3 then C.Gold else C.Muted,
	})
	Theme.label(row, {
		name = "Name",
		size = UDim2.new(1, -230, 0, 26),
		position = UDim2.fromOffset(78, 5),
		text = name,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(row, {
		name = "Score",
		size = UDim2.fromOffset(140, 26),
		position = UDim2.new(1, -150, 0, 5),
		text = score,
		color = C.Scrap,
		align = Enum.TextXAlignment.Right,
	})
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
		message.Text = "Nobody's on the board yet this week - win a match to be first!"
		for order, entry in top do
			local isMe = entry.userId == localPlayer.UserId
			addRow(
				order,
				MEDALS[order] or `#{order}`,
				tostring(entry.name),
				`🔩 {Theme.formatNumber(tonumber(entry.score) or 0)}`,
				isMe
			)
		end
		mineLabel.Text = `YOU THIS WEEK: 🔩 {Theme.formatNumber(tonumber(board.mine) or 0)}`
		if type(board.secondsLeft) == "number" then
			endsLabel.Text = `⏳ NEW WEEK IN {timeLeft(board.secondsLeft)}`
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
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = gui

	panel =
		Theme.panel(gui, "Leaderboard", UDim2.fromOffset(720, 600), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 18)
	Theme.label(panel, {
		name = "Title",
		size = UDim2.fromOffset(480, 46),
		text = "🏆 TOP 50 THIS WEEK",
		color = C.Gold,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, {
		name = "Subtitle",
		size = UDim2.fromOffset(520, 20),
		position = UDim2.fromOffset(2, 48),
		text = "Win Scrap in matches to climb. Everyone starts again on Monday!",
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
		LeaderboardPanel.close()
	end)
	mineLabel = Theme.pill(panel, {
		name = "Mine",
		size = UDim2.fromOffset(330, 32),
		position = UDim2.fromOffset(0, 80),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		transparency = 0.3,
	})
	endsLabel = Theme.pill(panel, {
		name = "Ends",
		size = UDim2.fromOffset(260, 32),
		position = UDim2.new(1, 0, 0, 80),
		anchor = Vector2.new(1, 0),
		text = "",
		font = Theme.Caps,
		color = C.Text,
		transparency = 0.3,
	})

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 1, -126)
	list.Position = UDim2.fromOffset(0, 126)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
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
		color = C.Muted,
		stroke = false,
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
