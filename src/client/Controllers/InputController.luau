--!strict
-- Reads keyboard, gamepad and touch controls and turns them into car input.
--
-- Keyboard: W/S or arrows = drive (and pitch in the air), A/D = steer, Space / right mouse = jump,
--           Shift / left mouse = boost, F = Mega Shot, C = ball cam, Q/E = air roll
-- Gamepad:  RT/LT = drive/brake, left stick = steer + pitch, A = jump, B = boost, X = Mega Shot,
--           Y = ball cam, LB/RB = air roll
-- Touch:    on-screen stick and buttons (see TouchControls)

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared.Physics.CarPhysics)
local Signal = require(Shared.Util.Signal)

local InputController = {}

InputController.MegaPressed = Signal.new() :: Signal.Signal<>
InputController.BallCamToggled = Signal.new() :: Signal.Signal<>

local DEADZONE = 0.15

local touchStick = Vector2.zero
local touchHeld: { [string]: boolean } = {}
local actionsBound = false

local function keyDown(...: Enum.KeyCode): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function deadzone(value: number): number
	if math.abs(value) < DEADZONE then
		return 0
	end
	return math.sign(value) * (math.abs(value) - DEADZONE) / (1 - DEADZONE)
end

function InputController.setTouchStick(value: Vector2)
	touchStick = value
end

function InputController.setTouchButton(name: string, held: boolean)
	touchHeld[name] = held
end

-- The current controls. Returns "no input" while the player is typing in chat.
function InputController.read(): CarPhysics.Input
	if UserInputService:GetFocusedTextBox() then
		return CarPhysics.NoInput
	end

	local throttle, steer, roll = 0, 0, 0
	local pitch: number? = nil
	local boost, jump = false, false

	-- Keyboard and mouse.
	if keyDown(Enum.KeyCode.W, Enum.KeyCode.Up) then
		throttle += 1
	end
	if keyDown(Enum.KeyCode.S, Enum.KeyCode.Down) then
		throttle -= 1
	end
	if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then
		steer += 1
	end
	if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then
		steer -= 1
	end
	if keyDown(Enum.KeyCode.E) then
		roll += 1
	end
	if keyDown(Enum.KeyCode.Q) then
		roll -= 1
	end
	boost = keyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	jump = keyDown(Enum.KeyCode.Space) or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

	-- Gamepad.
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		local pad = Enum.UserInputType.Gamepad1
		local stick = Vector2.zero
		local rightTrigger, leftTrigger = 0, 0
		for _, state in UserInputService:GetGamepadState(pad) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				stick = Vector2.new(deadzone(state.Position.X), deadzone(state.Position.Y))
			elseif state.KeyCode == Enum.KeyCode.ButtonR2 then
				rightTrigger = state.Position.Z
			elseif state.KeyCode == Enum.KeyCode.ButtonL2 then
				leftTrigger = state.Position.Z
			end
		end
		steer += stick.X
		local triggers = rightTrigger - leftTrigger
		-- Triggers drive like Rocket League; pushing the stick forward also works, Roblox-style.
		throttle += if math.abs(triggers) > 0.1 then triggers else stick.Y
		if math.abs(stick.Y) > 0 then
			pitch = stick.Y
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonA) then
			jump = true
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonB) then
			boost = true
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonR1) then
			roll += 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonL1) then
			roll -= 1
		end
	end

	-- Touch.
	if touchStick.Magnitude > 0 then
		steer += touchStick.X
		throttle += touchStick.Y
	end
	boost = boost or touchHeld.boost == true
	jump = jump or touchHeld.jump == true

	return {
		throttle = math.clamp(throttle, -1, 1),
		steer = math.clamp(steer, -1, 1),
		pitch = if pitch then math.clamp(pitch, -1, 1) else nil,
		roll = math.clamp(roll, -1, 1),
		boost = boost,
		jump = jump,
	}
end

-- One-press actions (Mega Shot, ball cam) are bound only while driving, so they don't clash with anything else.
function InputController.setDriving(driving: boolean)
	if driving == actionsBound then
		return
	end
	actionsBound = driving
	if driving then
		ContextActionService:BindActionAtPriority("TurboMega", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				InputController.MegaPressed:Fire()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
		ContextActionService:BindActionAtPriority("TurboBallCam", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				InputController.BallCamToggled:Fire()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.C, Enum.KeyCode.ButtonY)
	else
		ContextActionService:UnbindAction("TurboMega")
		ContextActionService:UnbindAction("TurboBallCam")
		touchStick = Vector2.zero
		table.clear(touchHeld)
	end
end

return InputController
