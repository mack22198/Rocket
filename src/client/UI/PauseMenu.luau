--!strict
-- The in-match menu (☰ MENU button, M key or the gamepad's View button). The match keeps going - it's online -
-- so your car just rolls to a stop while this is open. From here you can read how to play or leave the match
-- (a bot takes over your car, and you go back to the main menu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Signal = require(Shared.Util.Signal)

local HowToPlay = require(script.Parent.HowToPlay)
local Theme = require(script.Parent.Theme)

local PauseMenu = {}

-- Fired when the player confirms they want to leave the match.
PauseMenu.LeaveRequested = Signal.new() :: Signal.Signal<>
-- Fired when the menu opens (true) or closes (false).
PauseMenu.Toggled = Signal.new() :: Signal.Signal<boolean>

local C = Theme.Colors
local rgb = Color3.fromRGB

local gui: ScreenGui
local panel: Frame
local scoreLine: TextLabel
local mainButtons: Frame
local confirm: Frame
local resumeButton: TextButton
local stayButton: TextButton
local stateObject = MatchState.getObject()

local function showConfirm(on: boolean)
	mainButtons.Visible = not on
	confirm.Visible = on
	Theme.focus(if on then stayButton else resumeButton)
end

local function build()
	gui = Theme.screen("TurboPauseMenu", 30)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = gui
	dim.Activated:Connect(function()
		PauseMenu.close()
	end)

	panel = Theme.panel(gui, "Menu", UDim2.fromOffset(460, 430), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 22)
	Theme.label(panel, {
		name = "Heading",
		size = UDim2.new(1, 0, 0, 44),
		text = "MATCH MENU",
	})
	scoreLine = Theme.label(panel, {
		name = "Score",
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 48),
		text = "",
		font = Theme.Caps,
		color = C.Muted,
		stroke = false,
	})

	mainButtons = Instance.new("Frame")
	mainButtons.Name = "Buttons"
	mainButtons.Size = UDim2.new(1, 0, 1, -90)
	mainButtons.Position = UDim2.fromOffset(0, 90)
	mainButtons.BackgroundTransparency = 1
	mainButtons.Parent = panel
	resumeButton = Theme.button(mainButtons, {
		name = "Resume",
		size = UDim2.new(1, 0, 0, 74),
		text = "▶  RESUME",
	})
	resumeButton.Activated:Connect(function()
		PauseMenu.close()
	end)
	local howButton = Theme.button(mainButtons, {
		name = "HowToPlay",
		size = UDim2.new(1, 0, 0, 58),
		position = UDim2.fromOffset(0, 88),
		text = "❓  HOW TO PLAY",
		color = C.PanelLight,
		textColor = C.Text,
	})
	howButton.Activated:Connect(function()
		HowToPlay.open(function()
			Theme.focus(resumeButton)
		end)
	end)
	local leaveButton = Theme.button(mainButtons, {
		name = "Leave",
		size = UDim2.new(1, 0, 0, 58),
		position = UDim2.fromOffset(0, 160),
		text = "🏠  LEAVE MATCH",
		color = C.Bad,
		textColor = C.Text,
	})
	leaveButton.Activated:Connect(function()
		showConfirm(true)
	end)
	Theme.label(mainButtons, {
		name = "Hint",
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.new(0, 0, 1, -16),
		text = "The match keeps going while this menu is open!",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})

	confirm = Instance.new("Frame")
	confirm.Name = "Confirm"
	confirm.Size = mainButtons.Size
	confirm.Position = mainButtons.Position
	confirm.BackgroundTransparency = 1
	confirm.Visible = false
	confirm.Parent = panel
	Theme.label(confirm, {
		name = "Question",
		size = UDim2.new(1, 0, 0, 40),
		text = "Leave this match?",
		color = C.Gold,
	})
	Theme.label(confirm, {
		name = "Explain",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 46),
		text = "A bot will drive your car for the rest of the match, and you won't get Scrap for it.",
		font = Theme.Body,
		color = C.Text,
		stroke = false,
	})
	stayButton = Theme.button(confirm, {
		name = "Stay",
		size = UDim2.new(0.5, -8, 0, 66),
		position = UDim2.fromOffset(0, 116),
		text = "KEEP PLAYING",
		color = C.Good,
	})
	stayButton.Activated:Connect(function()
		showConfirm(false)
	end)
	local reallyLeave = Theme.button(confirm, {
		name = "ReallyLeave",
		size = UDim2.new(0.5, -8, 0, 66),
		position = UDim2.new(0.5, 8, 0, 116),
		text = "LEAVE",
		color = C.Bad,
		textColor = C.Text,
	})
	reallyLeave.Activated:Connect(function()
		PauseMenu.close()
		PauseMenu.LeaveRequested:Fire()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function refreshScore()
	if not gui.Enabled then
		return
	end
	local blue = stateObject:GetAttribute(MatchState.Attr.BlueScore)
	local orange = stateObject:GetAttribute(MatchState.Attr.OrangeScore)
	local seconds = MatchState.clockSeconds(stateObject, workspace:GetServerTimeNow())
	local overtime = stateObject:GetAttribute(MatchState.Attr.Overtime) == true
	local clock = MatchState.formatClock(seconds)
	scoreLine.Text =
		`BLUE {blue or 0}  -  {orange or 0} ORANGE   ·   {if overtime then "OVERTIME +" .. clock else clock}`
end

function PauseMenu.open()
	if gui.Enabled then
		return
	end
	gui.Enabled = true
	showConfirm(false)
	refreshScore()
	panel.Position = UDim2.fromScale(0.5, 0.54)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.5) })
		:Play()
	PauseMenu.Toggled:Fire(true)
end

function PauseMenu.close()
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	HowToPlay.close()
	Theme.focus(nil)
	PauseMenu.Toggled:Fire(false)
end

function PauseMenu.toggle()
	if gui.Enabled then
		PauseMenu.close()
	else
		PauseMenu.open()
	end
end

function PauseMenu.isOpen(): boolean
	return gui.Enabled
end

function PauseMenu.start()
	build()
	RunService.Heartbeat:Connect(refreshScore)
end

return PauseMenu
