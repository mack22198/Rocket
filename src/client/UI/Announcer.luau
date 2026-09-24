--!strict
-- Hype popups for cool moments ("AIR HIT!", "EPIC SAVE!", "MEGA SHOT!") plus a small feed on the right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local Announcer = {}

local localPlayer = Players.LocalPlayer
local gui: ScreenGui
local feed: Frame
local popup: TextLabel
local popupToken = 0

local EMOJI: { [string]: string } = {
	style = "✨",
	save = "🧤",
	mega = "💥",
	bump = "💢",
	join = "👋",
}

local function addFeedLine(text: string, color: Color3)
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(300, 32)
	line.BackgroundColor3 = Theme.Colors.Panel
	line.BackgroundTransparency = 0.25
	line.LayoutOrder = -math.floor(os.clock() * 1000)
	line.Parent = feed
	Theme.corner(line, 8)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 6, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = line
	Theme.corner(bar, 3)
	local label = Theme.label(line, {
		size = UDim2.new(1, -18, 1, -6),
		position = UDim2.fromOffset(12, 3),
		text = text,
		font = Theme.Body,
		align = Enum.TextXAlignment.Left,
	})
	task.delay(3.5, function()
		local fade = TweenInfo.new(0.4)
		TweenService:Create(line, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		line:Destroy()
	end)
	local lines = feed:GetChildren()
	local count = 0
	for _, child in lines do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 5 then
		-- Drop the oldest line.
		local oldest: Frame? = nil
		for _, child in lines do
			if child:IsA("Frame") and (oldest == nil or child.LayoutOrder > (oldest :: Frame).LayoutOrder) then
				oldest = child
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
end

function Announcer.popup(text: string, color: Color3)
	popupToken += 1
	local token = popupToken
	popup.Text = text
	popup.TextColor3 = color
	popup.TextTransparency = 0
	popup.TextStrokeTransparency = 0.3
	popup.Visible = true
	popup.Rotation = -8
	popup.Size = UDim2.fromOffset(300, 40)
	TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(520, 80),
		Rotation = 0,
	}):Play()
	task.delay(1.4, function()
		if token ~= popupToken then
			return
		end
		TweenService:Create(popup, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.35)
		if token == popupToken then
			popup.Visible = false
		end
	end)
end

function Announcer.start()
	gui = Theme.screen("TurboAnnouncer", 6)

	local list = Instance.new("Frame")
	list.Name = "Feed"
	list.Size = UDim2.fromOffset(300, 220)
	list.Position = UDim2.new(1, -16, 0, 90)
	list.AnchorPoint = Vector2.new(1, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = list
	feed = list

	popup = Theme.label(gui, {
		name = "Popup",
		size = UDim2.fromOffset(520, 80),
		position = UDim2.fromScale(0.5, 0.62),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 4,
	})
	popup.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = popup
	Theme.scaled(feed)
	Theme.scaled(popup)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	Remotes.Announce.OnClientEvent:Connect(function(kind: any, text: any, team: any, name: any)
		if type(kind) ~= "string" or type(text) ~= "string" then
			return
		end
		local color = Theme.teamColor(if type(team) == "string" then team else nil)
		local who = if type(name) == "string" and name ~= "" then name else nil
		if kind == "overtime" then
			return -- the HUD shows this one
		end
		local emoji = EMOJI[kind] or "⭐"
		if kind == "join" then
			addFeedLine(`{emoji} {text}`, color)
			return
		end
		addFeedLine(if who then `{emoji} {text}  {who}` else `{emoji} {text}`, color)
		-- Only the big moments get a popup, and your own moments always do.
		local mine = who ~= nil and who == localPlayer.DisplayName
		if kind == "mega" or kind == "save" or mine then
			Announcer.popup(
				if who and not mine then `{text} {who}` else text,
				if kind == "mega" then Theme.Colors.Mega else color
			)
		end
	end)
end

return Announcer
