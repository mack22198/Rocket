--!strict
-- Quick chat (see QuickChat). The CHAT button next to MENU opens a list of friendly phrases: tap one to say
-- it. Keys 1-8 say them straight away (T opens the list) and the gamepad's D-pad has three of them. Whatever
-- anyone says pops up in a speech bubble over their car and in the feed. It's only there for players whose
-- Roblox settings allow chat (the server says so with the player's QuickChat attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local QuickChat = require(Shared.Config.QuickChat)
local Remotes = require(Shared.Net.Remotes)

local InputController = require(script.Parent.Parent.Controllers.InputController)
local LocalHide = require(script.Parent.Parent.Controllers.LocalHide)
local SoundController = require(script.Parent.Parent.Controllers.SoundController)
local Announcer = require(script.Parent.Announcer)
local Theme = require(script.Parent.Theme)

local QuickChatPanel = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

local ROW_HEIGHT = 34
local ROW_GAP = 4
local LIST_WIDTH = 270

type Bubble = { gui: BillboardGui, car: Model, expires: number }

local gui: ScreenGui
local buttonHolder: Frame
local list: Frame
local keyLabels: { TextLabel } = {}
local gamepadHint: TextLabel
local visible = false
local history: { number } = {}
local bubbles: { [Model]: Bubble } = {}
local bubbleFolder: Folder

-- The list is a little taller when there's room for the gamepad's shortcuts at the bottom.
local function listHeight(gamepad: boolean): number
	return 44 + #QuickChat.Phrases * (ROW_HEIGHT + ROW_GAP) + (if gamepad then 30 else 6)
end

local function allowed(): boolean
	return localPlayer:GetAttribute(MatchState.PlayerAttr.QuickChat) == true
end

local function refresh()
	buttonHolder.Visible = visible and allowed()
	if not buttonHolder.Visible then
		list.Visible = false
	end
end

local function setOpen(open: boolean)
	list.Visible = open and visible and allowed()
	if list.Visible then
		-- Number keys on a keyboard; the D-pad shortcuts on a gamepad.
		local keyboard = UserInputService.KeyboardEnabled
		for _, label in keyLabels do
			label.Visible = keyboard
		end
		gamepadHint.Visible = UserInputService.GamepadEnabled
		list.Size = UDim2.fromOffset(LIST_WIDTH, listHeight(gamepadHint.Visible))
	end
end

local function say(index: number)
	setOpen(false)
	if not visible or not allowed() or not QuickChat.phrase(index) then
		return
	end
	if QuickChat.allow(history, os.clock()) then
		Remotes.QuickChat:FireServer(index)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Speech bubbles
---------------------------------------------------------------------------------------------------------------

local function removeBubble(car: Model)
	local bubble = bubbles[car]
	if bubble then
		bubble.gui:Destroy()
		bubbles[car] = nil
	end
end

local function showBubble(car: Model, text: string, team: string)
	local chassis = car:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return
	end
	removeBubble(car)
	local tag = Instance.new("BillboardGui")
	tag.Name = "ChatBubble"
	tag.Size = UDim2.fromOffset(260, 48)
	tag.StudsOffset = Vector3.new(0, 8.5, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 320
	tag.Adornee = chassis

	local box = Instance.new("Frame")
	box.Name = "Bubble"
	box.AutomaticSize = Enum.AutomaticSize.X
	box.Size = UDim2.fromOffset(0, 40)
	box.Position = UDim2.fromScale(0.5, 0.42)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = C.Card
	box.Parent = tag
	Theme.corner(box, 16)
	Theme.stroke(box, Theme.teamColor(team), 4)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Title
	label.TextSize = 24
	label.TextColor3 = C.Ink
	label.Text = text
	label.Parent = box
	-- The little tail pointing down at the car.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Position = UDim2.new(0.5, 0, 1, -2)
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Rotation = 45
	tail.BackgroundColor3 = C.Card
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = box

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = box
	tag.Parent = bubbleFolder
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	bubbles[car] = { gui = tag, car = car, expires = os.clock() + QuickChat.BubbleTime }
end

local function updateBubbles()
	local now = os.clock()
	for car, bubble in bubbles do
		if now >= bubble.expires or not car.Parent then
			removeBubble(car)
		else
			-- Out of sight while the car is (replays, the podium, a demolition).
			bubble.gui.Enabled = not LocalHide.isHidden(car)
		end
	end
end

local function onShown(car: unknown, index: unknown, name: unknown, team: unknown)
	if typeof(car) ~= "Instance" or not car:IsA("Model") or type(index) ~= "number" then
		return
	end
	local phrase = QuickChat.phrase(index)
	if not phrase or not allowed() then
		return
	end
	local side = if type(team) == "string" then team else ""
	showBubble(car, `{phrase.Emoji} {phrase.Text}`, side)
	local mine = car:GetAttribute(MatchState.CarAttr.OwnerUserId) == localPlayer.UserId
	local who = if mine then "You" elseif type(name) == "string" then name else "?"
	Announcer.feed(`{who}: {phrase.Text}`, Theme.teamColor(side))
	SoundController.play("Click", 0.35, if mine then 1.1 else 1.4)
end

---------------------------------------------------------------------------------------------------------------
-- The button and the list
---------------------------------------------------------------------------------------------------------------

local function buildList()
	list = Theme.panel(gui, "QuickChatList", UDim2.fromOffset(LIST_WIDTH, listHeight(false)), UDim2.fromOffset(16, 116))
	list.Visible = false
	Theme.scaled(list)
	Theme.heading(list, {
		name = "Title",
		size = UDim2.new(1, -24, 0, 26),
		position = UDim2.fromOffset(14, 12),
		text = "QUICK CHAT",
		textSize = 24,
		align = Enum.TextXAlignment.Left,
	})
	for index, phrase in QuickChat.Phrases do
		local row = Instance.new("TextButton")
		row.Name = `Phrase{index}`
		row.Size = UDim2.new(1, -20, 0, ROW_HEIGHT)
		row.Position = UDim2.fromOffset(10, 44 + (index - 1) * (ROW_HEIGHT + ROW_GAP))
		row.BackgroundColor3 = C.CardShade
		row.AutoButtonColor = true
		row.Text = ""
		row.Parent = list
		Theme.corner(row, 10)
		local key = Theme.label(row, {
			name = "Key",
			size = UDim2.fromOffset(24, 24),
			position = UDim2.fromOffset(6, 5),
			text = tostring(index),
			font = Theme.Caps,
			color = C.Text,
			textSize = 14,
		})
		key.BackgroundColor3 = C.Ink
		key.BackgroundTransparency = 0
		Theme.corner(key, 6)
		table.insert(keyLabels, key)
		local text = Theme.label(row, {
			name = "Text",
			size = UDim2.new(1, -46, 1, 0),
			position = UDim2.fromOffset(38, 0),
			text = phrase.Text,
			align = Enum.TextXAlignment.Left,
			scaled = false,
			textSize = 18,
		})
		text.TextWrapped = false
		row.Activated:Connect(function()
			say(index)
		end)
	end
	local function keyFor(id: string): string
		local index = QuickChat.indexOf(id)
		return if index then tostring(index) else "?"
	end
	local pad = QuickChat.Gamepad
	gamepadHint = Theme.label(list, {
		name = "Gamepad",
		size = UDim2.new(1, -24, 0, 18),
		position = UDim2.new(0, 12, 1, -30),
		text = `D-PAD: LEFT {keyFor(pad.Left)}, RIGHT {keyFor(pad.Right)}, DOWN {keyFor(pad.Down)}`,
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 12,
	})
end

function QuickChatPanel.setVisible(on: boolean)
	visible = on
	gui.Enabled = on
	refresh()
end

function QuickChatPanel.isOpen(): boolean
	return list.Visible
end

function QuickChatPanel.start()
	gui = Theme.screen("TurboQuickChat", 7)
	gui.Enabled = false

	buttonHolder = Instance.new("Frame")
	buttonHolder.Name = "Chat"
	buttonHolder.Size = UDim2.fromOffset(104, 46)
	buttonHolder.Position = UDim2.fromOffset(132, 64)
	buttonHolder.BackgroundTransparency = 1
	buttonHolder.Parent = gui
	Theme.scaled(buttonHolder)
	local button = Theme.button(buttonHolder, {
		name = "ChatButton",
		size = UDim2.fromScale(1, 1),
		text = "CHAT",
		color = C.Panel,
		textSize = 20,
	})
	button.Activated:Connect(function()
		setOpen(not list.Visible)
	end)
	buildList()

	local folder = Instance.new("Folder")
	folder.Name = "ChatBubbles"
	folder.Parent = workspace.CurrentCamera or workspace
	bubbleFolder = folder

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	localPlayer:GetAttributeChangedSignal(MatchState.PlayerAttr.QuickChat):Connect(refresh)
	refresh()

	InputController.ChatPressed:Connect(function(slot: number)
		if slot == 0 then
			setOpen(not list.Visible)
		else
			say(slot)
		end
	end)
	Remotes.QuickChatShown.OnClientEvent:Connect(onShown)
	RunService.Heartbeat:Connect(updateBubbles)
end

return QuickChatPanel
