--!strict
-- On-screen controls for phones and tablets: a thumbstick on the left (steer + drive) and big buttons on the right.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local Theme = require(script.Parent.Theme)

local TouchControls = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer
local STICK_RADIUS = 70

local gui: ScreenGui
local stickInput: InputObject? = nil
local stickOrigin = Vector2.zero
local stickBase: Frame
local stickKnob: Frame

local function releaseStick()
	stickInput = nil
	InputController.setTouchStick(Vector2.zero)
	stickBase.Visible = false
end

-- Buttons are placed in pixels from the bottom-right corner of a 1280x720 screen, then scaled to fit.
local placements: { { button: TextButton, fromRight: number, fromBottom: number } } = {}

local function placeAll(scale: number)
	for _, placement in placements do
		placement.button.Position = UDim2.new(1, -placement.fromRight * scale, 1, -placement.fromBottom * scale)
	end
end

local function makeButton(
	name: string,
	text: string,
	color: Color3,
	size: number,
	fromRight: number,
	fromBottom: number
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(size, size)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	table.insert(placements, { button = button, fromRight = fromRight, fromBottom = fromBottom })
	Theme.scaled(button)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.15
	button.Text = text
	button.Font = Theme.Title
	button.TextScaled = true
	button.TextColor3 = C.Text
	button.AutoButtonColor = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	Theme.stroke(button, Color3.new(1, 1, 1), 3).Transparency = 0.4
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.25, 0)
	padding.PaddingBottom = UDim.new(0.25, 0)
	padding.PaddingLeft = UDim.new(0.12, 0)
	padding.PaddingRight = UDim.new(0.12, 0)
	padding.Parent = button
	return button
end

-- A button that counts as "held" from touch start until that same finger lifts, even if it slides off.
local function holdButton(button: TextButton, onChange: (boolean) -> ())
	local active: InputObject? = nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not active then
			active = input
			button.BackgroundTransparency = 0
			onChange(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == active then
			active = nil
			button.BackgroundTransparency = 0.15
			onChange(false)
		end
	end)
end

local function build()
	gui = Theme.screen("TurboTouch", 4)
	gui.Enabled = false
	-- Touch positions are measured below the top bar, so this GUI must use the same space.
	gui.IgnoreGuiInset = false

	-- Left half of the screen: touch anywhere to place the stick.
	local stickZone = Instance.new("Frame")
	stickZone.Name = "StickZone"
	stickZone.Size = UDim2.fromScale(0.45, 0.7)
	stickZone.Position = UDim2.fromScale(0, 0.3)
	stickZone.BackgroundTransparency = 1
	stickZone.Active = true
	stickZone.Parent = gui

	stickBase = Instance.new("Frame")
	stickBase.Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2)
	stickBase.AnchorPoint = Vector2.new(0.5, 0.5)
	stickBase.BackgroundColor3 = Color3.new(0, 0, 0)
	stickBase.BackgroundTransparency = 0.6
	stickBase.Visible = false
	stickBase.Parent = gui
	Theme.scaled(stickBase)
	local baseCorner = Instance.new("UICorner")
	baseCorner.CornerRadius = UDim.new(0.5, 0)
	baseCorner.Parent = stickBase
	stickKnob = Instance.new("Frame")
	stickKnob.Size = UDim2.fromOffset(60, 60)
	stickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	stickKnob.Position = UDim2.fromScale(0.5, 0.5)
	stickKnob.BackgroundColor3 = Color3.new(1, 1, 1)
	stickKnob.BackgroundTransparency = 0.2
	stickKnob.Parent = stickBase
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent = stickKnob

	stickZone.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not stickInput then
			stickInput = input
			stickOrigin = Vector2.new(input.Position.X, input.Position.Y)
			stickBase.Position = UDim2.fromOffset(stickOrigin.X, stickOrigin.Y)
			stickKnob.Position = UDim2.fromScale(0.5, 0.5)
			stickBase.Visible = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == stickInput then
			local offset = Vector2.new(input.Position.X, input.Position.Y) - stickOrigin
			local radius = STICK_RADIUS * Theme.getScale()
			if offset.Magnitude > radius then
				offset = offset.Unit * radius
			end
			local value = offset / radius
			stickKnob.Position = UDim2.new(0.5, value.X * STICK_RADIUS, 0.5, value.Y * STICK_RADIUS)
			-- Screen Y grows downward; pushing the stick up means "drive forward".
			InputController.setTouchStick(Vector2.new(value.X, -value.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == stickInput then
			releaseStick()
		end
	end)

	local boost = makeButton("Boost", "BOOST", Color3.fromRGB(255, 140, 30), 120, 95, 110)
	holdButton(boost, function(held)
		InputController.setTouchButton("boost", held)
	end)
	local jump = makeButton("Jump", "JUMP", Color3.fromRGB(60, 160, 255), 100, 215, 70)
	holdButton(jump, function(held)
		InputController.setTouchButton("jump", held)
	end)
	local mega = makeButton("Mega", "MEGA", Color3.fromRGB(230, 60, 60), 80, 85, 245)
	mega.Activated:Connect(function()
		InputController.MegaPressed:Fire()
	end)
	local cam = makeButton("BallCam", "CAM", Color3.fromRGB(90, 90, 120), 60, 190, 190)
	cam.Activated:Connect(function()
		CameraController.toggleBallCam()
	end)
	placeAll(Theme.getScale())
	Theme.onScaleChanged(placeAll)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function TouchControls.start()
	if not UserInputService.TouchEnabled then
		return
	end
	build()
	CarController.CarChanged:Connect(function(car)
		gui.Enabled = car ~= nil
		if not car then
			releaseStick()
		end
	end)
	gui.Enabled = CarController.getCar() ~= nil
end

return TouchControls
