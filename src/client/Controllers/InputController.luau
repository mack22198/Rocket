--!strict
-- Reads keyboard, gamepad and touch controls and turns them into car input.
--
-- Keyboard: W/S or arrows = drive (and pitch in the air), A/D = steer, Space / right mouse = jump,
--           Shift / left mouse = boost, F = Mega Shot, R = use item, G = car power, H = horn,
--           C = ball cam, Q/E = air roll, M = menu
-- Gamepad:  RT/LT = drive/brake, left stick = steer + pitch, A = jump, B = boost, X = Mega Shot,
--           RB = use item, LB = car power, D-pad up = horn, Y = ball cam, View/Back = menu
-- Touch:    on-screen stick and buttons (see TouchControls)

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared.Physics.CarPhysics)
local Signal = require(Shared.Util.Signal)

local InputController = {}

InputController.MegaPressed = Signal.new() :: Signal.Signal<>
InputController.ItemPressed = Signal.new() :: Signal.Signal<>
InputController.PowerPressed = Signal.new() :: Signal.Signal<>
InputController.HornPressed = Signal.new() :: Signal.Signal<>
InputController.BallCamToggled = Signal.new() :: Signal.Signal<>
InputController.MenuPressed = Signal.new() :: Signal.Signal<>

local DEADZONE = 0.15

local touchStick = Vector2.zero
local touchHeld: { [string]: boolean } = {}
local actionsBound = false
local blocked = false

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

-- While a menu is open over the match, the car gets no input (it just rolls to a stop).
function InputController.setBlocked(isBlocked: boolean)
	blocked = isBlocked
	if isBlocked then
		touchStick = Vector2.zero
		table.clear(touchHeld)
	end
end

-- The current controls. Returns "no input" while the player is typing in chat or a menu is open.
function InputController.read(): CarPhysics.Input
	if blocked or UserInputService:GetFocusedTextBox() then
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

-- One-press actions: (action name, signal, keys).
local PRESS_ACTIONS: { { name: string, signal: Signal.Signal<>, keys: { Enum.KeyCode } } } = {
	{ name = "TurboMega", signal = InputController.MegaPressed, keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonX } },
	{ name = "TurboItem", signal = InputController.ItemPressed, keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonR1 } },
	{ name = "TurboPower", signal = InputController.PowerPressed, keys = { Enum.KeyCode.G, Enum.KeyCode.ButtonL1 } },
	{ name = "TurboHorn", signal = InputController.HornPressed, keys = { Enum.KeyCode.H, Enum.KeyCode.DPadUp } },
	{
		name = "TurboBallCam",
		signal = InputController.BallCamToggled,
		keys = { Enum.KeyCode.C, Enum.KeyCode.ButtonY },
	},
}

-- One-press actions (Mega Shot, items, powers, ball cam) are bound only while driving, so they don't clash with
-- anything else.
function InputController.setDriving(driving: boolean)
	if driving == actionsBound then
		return
	end
	actionsBound = driving
	for _, action in PRESS_ACTIONS do
		if driving then
			local signal = action.signal
			ContextActionService:BindActionAtPriority(action.name, function(_, inputState)
				if inputState == Enum.UserInputState.Begin and not blocked then
					signal:Fire()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, table.unpack(action.keys))
		else
			ContextActionService:UnbindAction(action.name)
		end
	end
	if not driving then
		touchStick = Vector2.zero
		table.clear(touchHeld)
	end
end

-- The menu key works everywhere (it opens the pause menu during a match).
function InputController.start()
	ContextActionService:BindActionAtPriority("TurboMenu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			InputController.MenuPressed:Fire()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect)
end

return InputController
