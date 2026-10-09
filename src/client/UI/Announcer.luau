--!strict
-- Hype popups for cool moments ("AIR HIT!", "EPIC SAVE!", "CHEESE FLOOD!") plus a small feed on the right
-- (which also tells you who set off their ultimate, who slipped on a banana, who grabbed the charge orb, who
-- demolished whom, and so on).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local Theme = require(script.Parent.Theme)

local Announcer = {}

local localPlayer = Players.LocalPlayer
local ORB_COLOR = Color3.fromRGB(80, 220, 255)
local gui: ScreenGui
local feed: Frame
local popup: TextLabel
local popupOutline: UIStroke
local popupToken = 0

-- "Bolt froze Sparky!" as Sparky sees it: "Bolt froze you!" (and "You froze Sparky!" for Bolt).
local function personal(text: string, me: string): (string, boolean)
	local at = string.find(text, me, 1, true)
	if not at or me == "" then
		return text, false
	end
	local before = string.sub(text, 1, at - 1)
	local you = if string.find(before, "%a") then "you" else "You"
	return before .. you .. string.sub(text, at + #me), true
end

local function addFeedLine(text: string, color: Color3)
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(300, 32)
	line.BackgroundColor3 = Theme.Colors.Panel
	line.LayoutOrder = -math.floor(os.clock() * 1000)
	line.Parent = feed
	Theme.corner(line, 8)
	local outline = Theme.stroke(line, Theme.Colors.Ink, 2)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 8, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = line
	Theme.corner(bar, 4)
	local label = Theme.label(line, {
		size = UDim2.new(1, -24, 1, -8),
		position = UDim2.fromOffset(16, 4),
		text = Theme.noEmoji(text),
		font = Theme.Body,
		color = Theme.Colors.Text,
		textSize = 15,
		align = Enum.TextXAlignment.Left,
	})
	task.delay(3.5, function()
		local fade = TweenInfo.new(0.4)
		TweenService:Create(line, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(outline, fade, { Transparency = 1 }):Play()
		TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
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

-- Adds a line to the feed (quick chat uses this too).
function Announcer.feed(text: string, color: Color3)
	addFeedLine(text, color)
end

function Announcer.popup(text: string, color: Color3)
	-- A goal has the screen to itself (the feed still gets the line).
	if MatchState.phase(MatchState.getObject()) == MatchState.Phases.GoalScored then
		return
	end
	popupToken += 1
	local token = popupToken
	popup.Text = Theme.noEmoji(text)
	popup.TextColor3 = color
	popup.TextTransparency = 0
	popupOutline.Transparency = 0
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
		TweenService:Create(popup, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(popupOutline, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		task.wait(0.35)
		if token == popupToken then
			popup.Visible = false
		end
	end)
end

-- Only shown during matches.
function Announcer.setVisible(on: boolean)
	gui.Enabled = on
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

	popup = Theme.heading(gui, {
		name = "Popup",
		size = UDim2.fromOffset(520, 80),
		position = UDim2.fromScale(0.5, 0.62),
		anchor = Vector2.new(0.5, 0.5),
		text = "",
		zIndex = 4,
	})
	popup.Visible = false
	popup.TextWrapped = false -- long names shrink to fit on one line instead of spilling over the car
	popupOutline = Theme.outline(popup, 4)
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
		if kind == "join" then
			addFeedLine(text, color)
			return
		elseif kind == "ult" then
			-- Someone set off their ultimate ("CHEESE FLOOD"): everyone else gets a popup, so they see it coming.
			-- (Your own gets the HUD's big banner instead.)
			local mine = who ~= nil and who == localPlayer.DisplayName
			addFeedLine(if mine then `You used {text}!` else `{who or "Someone"} used {text}!`, color)
			if not mine then
				Announcer.popup(if who then `{who}: {text}!` else `{text}!`, color)
			end
			return
		elseif kind == "orb" then
			-- "Bolt grabbed the charge orb!" (and a popup when it was you).
			local line, aboutMe = personal(text, localPlayer.DisplayName)
			addFeedLine(line, color)
			if aboutMe then
				Announcer.popup("CHARGE ORB!", ORB_COLOR)
			end
			return
		elseif kind == "power" then
			-- What ultimates did: the text says it all ("Bolt quacked 2 cars into a spin!"), with "you" for you.
			-- Yours get a popup too.
			local line = personal(text, localPlayer.DisplayName)
			addFeedLine(line, color)
			if who ~= nil and who == localPlayer.DisplayName then
				Announcer.popup(line, color)
			end
			return
		elseif kind == "demo" then
			-- Demolitions: a popup whether you did the smashing or got smashed.
			local line, aboutMe = personal(text, localPlayer.DisplayName)
			addFeedLine(line, color)
			if aboutMe then
				Announcer.popup(line, color)
			end
			return
		end
		addFeedLine(if who then `{text}  {who}` else text, color)
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
