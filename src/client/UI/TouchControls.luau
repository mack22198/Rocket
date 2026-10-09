--!strict
-- On-screen controls for phones and tablets: a thumbstick wherever your left thumb lands (with easy steering,
-- point where you want to go) and two big buttons on the right - JUMP, and ULT, which fills up like the
-- ultimate meter and glows when it's ready - plus small CAM and HORN buttons out of the way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local GameConfig = require(Shared.Config.GameConfig)

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CarController = require(script.Parent.Parent.Controllers.CarController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local Theme = require(script.Parent.Theme)

local TouchControls = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer
local STICK_RADIUS = 70

local gui: ScreenGui? = nil
local hidden = false -- replays and the podium hide the controls
local stickInput: InputObject? = nil
local stickOrigin = Vector2.zero
local stickBase: Frame
local stickKnob: Frame
local stickHint: Frame

local function releaseStick()
	stickInput = nil
	InputController.setTouchStick(Vector2.zero)
	stickBase.Visible = false
	stickHint.Visible = true
end

-- Buttons are placed in pixels from the bottom-right corner of a 1280x720 screen, then scaled to fit.
local placements: { { button: TextButton, fromRight: number, fromBottom: number } } = {}

local function placeAll(scale: number)
	for _, placement in placements do
		placement.button.Position = UDim2.new(1, -placement.fromRight * scale, 1, -placement.fromBottom * scale)
	end
	stickHint.Position = UDim2.new(0, 170 * scale, 1, -170 * scale)
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
	button.BackgroundTransparency = 0.1
	button.Text = text
	button.Font = Theme.Display
	button.TextScaled = true
	button.TextColor3 = C.Text
	button.AutoButtonColor = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	Theme.stroke(button, C.Ink, 3)
	Theme.outline(button, 2)
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
			button.BackgroundTransparency = 0.1
			onChange(false)
		end
	end)
end

local function build()
	local screen = Theme.screen("TurboTouch", 4)
	gui = screen
	screen.Enabled = false
	-- Touch positions are measured below the top bar, so this GUI must use the same space.
	screen.IgnoreGuiInset = false

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

	-- Where to put your thumb, until you do.
	stickHint = Instance.new("Frame")
	stickHint.Name = "StickHint"
	stickHint.Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2)
	stickHint.AnchorPoint = Vector2.new(0.5, 0.5)
	stickHint.BackgroundColor3 = Color3.new(0, 0, 0)
	stickHint.BackgroundTransparency = 0.75
	stickHint.Parent = gui
	Theme.scaled(stickHint)
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0.5, 0)
	hintCorner.Parent = stickHint
	Theme.stroke(stickHint, Color3.new(1, 1, 1), 3).Transparency = 0.55
	local hintDot = Instance.new("Frame")
	hintDot.Size = UDim2.fromOffset(46, 46)
	hintDot.AnchorPoint = Vector2.new(0.5, 0.5)
	hintDot.Position = UDim2.fromScale(0.5, 0.5)
	hintDot.BackgroundColor3 = Color3.new(1, 1, 1)
	hintDot.BackgroundTransparency = 0.6
	hintDot.Parent = stickHint
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = hintDot
	Theme.label(stickHint, {
		name = "Caption",
		size = UDim2.new(1.6, 0, 0, 22),
		position = UDim2.new(0.5, 0, 1, 10),
		anchor = Vector2.new(0.5, 0),
		text = "DRAG TO DRIVE",
		font = Theme.Caps,
		color = C.Text,
		stroke = true,
	})

	stickZone.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not stickInput then
			stickInput = input
			stickOrigin = Vector2.new(input.Position.X, input.Position.Y)
			stickBase.Position = UDim2.fromOffset(stickOrigin.X, stickOrigin.Y)
			stickKnob.Position = UDim2.fromScale(0.5, 0.5)
			stickBase.Visible = true
			stickHint.Visible = false
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

	local jump = makeButton("Jump", "JUMP", C.Sky, 132, 104, 122)
	holdButton(jump, function(held)
		InputController.setTouchButton("jump", held)
	end)

	-- ULT: a ring around it fills up with the ultimate meter; when it's full the button glows in the
	-- ultimate's colour and shows its picture. It goes off the moment you touch it.
	local ult = makeButton("Ultimate", "0%", C.Panel, 104, 262, 120)
	local ring = Theme.ring(ult, 20, 64, Vector2.new(8, 16))
	-- (The button's padding makes its inside 76% as wide and 50% as tall as the button.)
	local ultName = Theme.label(ult, {
		name = "Caption",
		size = UDim2.fromScale(1.9, 0.42),
		position = UDim2.fromScale(0.5, 1.9),
		anchor = Vector2.new(0.5, 0),
		text = "",
		font = Theme.Caps,
		color = C.Text,
		stroke = true,
	})
	ultName.ZIndex = 2
	ult.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			InputController.UltimatePressed:Fire()
		end
	end)
	local lastCharge = -1
	RunService.RenderStepped:Connect(function()
		local car = CarController.getCar()
		if not car then
			lastCharge = -1
			return
		end
		local carId = car:GetAttribute(MatchState.CarAttr.CarId)
		local power = Powers.forCar(if type(carId) == "string" then carId else "")
		local charge, ready = CarController.ultCharge()
		local pulse = math.floor(os.clock() * 4) % 2 == 0
		ultName.Text = string.upper(power.Name)
		if ready then
			ring.set(1, if pulse then C.Gold else C.Text)
			ult.Text = power.Emoji
			ult.Font = Theme.Title
			ult.BackgroundColor3 = if pulse then power.Color else power.Color:Lerp(C.Gold, 0.4)
		else
			ring.set(charge / GameConfig.Ultimate.Max, power.Color)
			ult.Text = `{math.floor(charge / GameConfig.Ultimate.Max * 100)}%`
			ult.Font = Theme.Display
			ult.BackgroundColor3 = C.Panel
		end
		if lastCharge >= 0 and charge - lastCharge >= 2 then
			Theme.floatText(
				ult,
				`+{math.floor(charge - lastCharge)}`,
				UDim2.new(0.5, 0, 0, -50),
				Vector2.new(0.5, 1),
				40
			)
		end
		lastCharge = charge
	end)

	local cam = makeButton("BallCam", "CAM", C.Panel, 54, 62, 395)
	cam.Activated:Connect(function()
		CameraController.toggleBallCam()
	end)
	local horn = makeButton("Horn", "HORN", C.Panel, 54, 130, 395)
	horn.Activated:Connect(function()
		InputController.HornPressed:Fire()
	end)
	placeAll(Theme.getScale())
	Theme.onScaleChanged(placeAll)

	screen.Parent = localPlayer:WaitForChild("PlayerGui")
end

function TouchControls.start()
	if not UserInputService.TouchEnabled then
		return
	end
	build()
	CarController.CarChanged:Connect(function(car)
		if gui then
			gui.Enabled = car ~= nil and not hidden
		end
		if not car then
			releaseStick()
		end
	end)
	if gui then
		gui.Enabled = CarController.getCar() ~= nil and not hidden
	end
end

-- Hides the controls while a replay or the podium is on screen.
function TouchControls.setHidden(on: boolean)
	hidden = on
	if gui then
		gui.Enabled = not on and CarController.getCar() ~= nil
		if on then
			releaseStick()
		end
	end
end

return TouchControls
