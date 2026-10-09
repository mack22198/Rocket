--!strict
-- The in-match menu (the MENU button, M key or the gamepad's View button). The match keeps going - it's online -
-- so your car just rolls to a stop while this is open. From here you can read how to play, switch driving help
-- and easy steering (phones and tablets) on or off, or leave the match (a bot takes over your car, and you go back
-- to the menu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local InputController = require(script.Parent.Parent.Controllers.InputController)
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

-- A setting you switch on and off: its name and what it does on the left, a switch on the right.
local function switchRow(
	parent: Instance,
	name: string,
	title: string,
	detail: string,
	y: number
): (TextButton, (boolean) -> ())
	local row = Instance.new("TextButton")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 64)
	row.Position = UDim2.fromOffset(0, y)
	row.BackgroundColor3 = C.CardShade
	row.AutoButtonColor = true
	row.Text = ""
	row.Parent = parent
	Theme.corner(row, 12)
	Theme.label(row, {
		name = "Title",
		size = UDim2.new(1, -110, 0, 22),
		position = UDim2.fromOffset(16, 11),
		text = title,
		textSize = 19,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(row, {
		name = "Detail",
		size = UDim2.new(1, -110, 0, 16),
		position = UDim2.fromOffset(16, 36),
		text = detail,
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 13,
		align = Enum.TextXAlignment.Left,
	})
	local track = Instance.new("Frame")
	track.Name = "Switch"
	track.Size = UDim2.fromOffset(72, 36)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Parent = row
	Theme.corner(track, 18)
	Theme.stroke(track, C.Ink, 3)
	local state = Theme.label(track, {
		name = "State",
		size = UDim2.fromOffset(36, 36),
		text = "",
		font = Theme.Caps,
		color = C.Text,
		textSize = 12,
	})
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(26, 26)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = C.Card
	knob.Parent = track
	Theme.corner(knob, 13)
	Theme.stroke(knob, C.Ink, 3)
	local function set(on: boolean)
		track.BackgroundColor3 = if on then C.Good else C.CardLine
		knob.Position = UDim2.new(if on then 1 else 0, if on then -18 else 18, 0.5, 0)
		state.Text = if on then "ON" else "OFF"
		state.TextColor3 = if on then C.Text else C.InkMuted
		state.Position = UDim2.fromOffset(if on then 4 else 32, 0)
	end
	return row, set
end

local function build()
	gui = Theme.screen("TurboPauseMenu", 30)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(6, 8, 18)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui
	dim.Activated:Connect(function()
		PauseMenu.close()
	end)

	local touch = InputController.isTouch()
	panel = Theme.card(
		gui,
		"Menu",
		UDim2.fromOffset(460, if touch then 546 else 474),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	Theme.scaled(panel)
	Theme.padding(panel, 22)
	Theme.heading(panel, {
		name = "Heading",
		size = UDim2.new(1, 0, 0, 40),
		text = "MATCH MENU",
		textSize = 40,
	})
	scoreLine = Theme.label(panel, {
		name = "Score",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 46),
		text = "",
		font = Theme.Caps,
		color = C.InkMuted,
		textSize = 15,
	})

	mainButtons = Instance.new("Frame")
	mainButtons.Name = "Buttons"
	mainButtons.Size = UDim2.new(1, 0, 1, -82)
	mainButtons.Position = UDim2.fromOffset(0, 82)
	mainButtons.BackgroundTransparency = 1
	mainButtons.Parent = panel
	resumeButton = Theme.button(mainButtons, {
		name = "Resume",
		size = UDim2.new(1, 0, 0, 72),
		text = "RESUME",
		textSize = 36,
	})
	resumeButton.Activated:Connect(function()
		PauseMenu.close()
	end)
	local howButton = Theme.button(mainButtons, {
		name = "HowToPlay",
		size = UDim2.new(1, 0, 0, 54),
		position = UDim2.fromOffset(0, 86),
		text = "HOW TO PLAY",
		color = C.Panel,
		textSize = 24,
	})
	howButton.Activated:Connect(function()
		HowToPlay.open(function()
			Theme.focus(resumeButton)
		end)
	end)

	-- Driving help on or off (see DriveAssist): aim assist, smoother keyboard steering and jump help.
	local helpRow, setHelp =
		switchRow(mainButtons, "DrivingHelp", "Driving help", "Helps you aim, steer and jump at the ball", 154)
	local function refreshHelp()
		setHelp(InputController.assist())
	end
	refreshHelp()
	Players.LocalPlayer:GetAttributeChangedSignal(MatchState.PlayerAttr.Assist):Connect(refreshHelp)
	helpRow.Activated:Connect(function()
		local wanted = not InputController.assist()
		setHelp(wanted) -- straight away; the server saves it and the attribute follows
		task.spawn(function()
			pcall(function()
				Remotes.Settings:InvokeServer("assist", wanted)
			end)
		end)
	end)

	-- Phones and tablets: easy steering on or off.
	local leaveY = 232
	if touch then
		local steerRow, setSteer =
			switchRow(mainButtons, "EasySteer", "Easy steering", "The car drives where you drag", 228)
		setSteer(InputController.easySteer())
		steerRow.Activated:Connect(function()
			InputController.setEasySteer(not InputController.easySteer())
			setSteer(InputController.easySteer())
		end)
		leaveY = 306
	end
	local leaveButton = Theme.button(mainButtons, {
		name = "Leave",
		size = UDim2.new(1, 0, 0, 54),
		position = UDim2.fromOffset(0, leaveY),
		text = "LEAVE MATCH",
		color = C.Bad,
		textSize = 24,
	})
	leaveButton.Activated:Connect(function()
		showConfirm(true)
	end)
	Theme.label(mainButtons, {
		name = "Hint",
		size = UDim2.new(1, 0, 0, 16),
		position = UDim2.new(0, 0, 1, -14),
		text = "The match keeps going while this menu is open.",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 13,
	})

	confirm = Instance.new("Frame")
	confirm.Name = "Confirm"
	confirm.Size = mainButtons.Size
	confirm.Position = mainButtons.Position
	confirm.BackgroundTransparency = 1
	confirm.Visible = false
	confirm.Parent = panel
	Theme.heading(confirm, {
		name = "Question",
		size = UDim2.new(1, 0, 0, 36),
		text = "LEAVE THIS MATCH?",
		color = C.Bad,
		textSize = 32,
	})
	Theme.label(confirm, {
		name = "Explain",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 48),
		text = "Someone else takes your seat for the rest of the match, and you won't get Scrap for it.",
		font = Theme.Body,
		textSize = 16,
	})
	stayButton = Theme.button(confirm, {
		name = "Stay",
		size = UDim2.new(0.5, -8, 0, 66),
		position = UDim2.fromOffset(0, 116),
		text = "KEEP PLAYING",
		color = C.Good,
		textSize = 24,
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
		textSize = 24,
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
	scoreLine.Text = `BLUE {blue or 0} - {orange or 0} ORANGE, {if overtime then "OVERTIME +" .. clock else clock}`
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
