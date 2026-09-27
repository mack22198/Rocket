--!strict
-- The look of a goal replay: cinema bars top and bottom, a flashing "REPLAY" badge, who scored, and a SKIP
-- button (Space / Enter / A work too).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local Theme = require(script.Parent.Theme)

local ReplayScreen = {}

ReplayScreen.SkipPressed = Signal.new() :: Signal.Signal<>

local C = Theme.Colors
local rgb = Color3.fromRGB
local BAR = 0.11 -- height of each cinema bar, as a share of the screen

local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local badge: TextLabel
local banner: TextLabel
local comboLabel: TextLabel
local skipButton: TextButton
local flash: Frame
local shownAt = 0

local function bar(name: string, top: boolean): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, BAR)
	frame.Position = if top then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 1 - BAR)
	frame.BackgroundColor3 = rgb(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return frame
end

local function build()
	gui = Theme.screen("TurboReplay", 8)
	gui.Enabled = false
	topBar = bar("TopBar", true)
	bottomBar = bar("BottomBar", false)

	badge = Theme.pill(gui, {
		name = "Badge",
		size = UDim2.fromOffset(170, 40),
		position = UDim2.new(0, 24, BAR, 14),
		text = "⟲ REPLAY",
		font = Theme.Caps,
		background = C.Bad,
		transparency = 0,
	})
	Theme.scaled(badge)

	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.Size = UDim2.fromOffset(1280, 80)
	bottom.Position = UDim2.fromScale(0.5, 1)
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.BackgroundTransparency = 1
	bottom.Parent = gui
	Theme.scaled(bottom)
	banner = Theme.label(bottom, {
		name = "Scorer",
		size = UDim2.fromOffset(760, 44),
		position = UDim2.new(0.5, 0, 0, 6),
		anchor = Vector2.new(0.5, 0),
		text = "",
	})
	comboLabel = Theme.label(bottom, {
		name = "Combo",
		size = UDim2.fromOffset(600, 24),
		position = UDim2.new(0.5, 0, 0, 50),
		anchor = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Caps,
		color = C.Gold,
		stroke = false,
	})
	skipButton = Theme.button(bottom, {
		name = "Skip",
		size = UDim2.fromOffset(150, 50),
		position = UDim2.new(1, -24, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "SKIP ▶",
		color = C.PanelLight,
		textColor = C.Text,
	})
	skipButton.Activated:Connect(function()
		ReplayScreen.SkipPressed:Fire()
	end)

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = rgb(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	flash.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function flashWhite()
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

function ReplayScreen.show(scorer: string, team: string, combo: string)
	banner.Text = if scorer ~= ""
		then `⚽ {scorer} scores for {string.upper(team)}!`
		else `⚽ {string.upper(team)} scores!`
	banner.TextColor3 = Theme.teamColor(team)
	comboLabel.Text = combo
	gui.Enabled = true
	shownAt = os.clock()
	flashWhite()
	topBar.Size = UDim2.fromScale(1, 0)
	bottomBar.Size = UDim2.fromScale(1, 0)
	bottomBar.Position = UDim2.fromScale(0, 1)
	local ease = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(topBar, ease, { Size = UDim2.fromScale(1, BAR) }):Play()
	TweenService:Create(bottomBar, ease, { Size = UDim2.fromScale(1, BAR), Position = UDim2.fromScale(0, 1 - BAR) })
		:Play()
	Theme.focus(skipButton)
end

function ReplayScreen.hide()
	if gui.Enabled then
		gui.Enabled = false
		Theme.focus(nil)
	end
end

function ReplayScreen.start()
	build()
	-- The badge blinks.
	task.spawn(function()
		while true do
			task.wait(0.6)
			if gui.Enabled then
				badge.Visible = not badge.Visible
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not gui.Enabled or os.clock() - shownAt < 0.5 then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			ReplayScreen.SkipPressed:Fire()
		end
	end)
end

return ReplayScreen
