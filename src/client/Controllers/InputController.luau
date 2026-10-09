--!strict
-- Reads keyboard, gamepad and touch controls and turns them into car input.
--
-- Keyboard: W/S or arrows = drive (and pitch in the air), A/D = steer, Space / right mouse = jump,
--           Shift / left mouse = boost, F = Mega Shot, R = use item, G = car power, H = horn,
--           C = ball cam, Q/E = air roll, M = menu, T = quick chat list, 1-8 = say a quick chat phrase
-- Gamepad:  RT/LT = drive/brake, left stick = steer + pitch, A = jump, B = boost, X = Mega Shot,
--           RB = use item, LB = car power, D-pad up = horn, D-pad left/right/down = quick chat,
--           Y = ball cam, View/Back = menu
-- Touch:    on-screen stick and buttons (see TouchControls). With easy steering (on by default) you push the
--           stick toward where you want to go on the screen (see EasySteer); in the air it tips the car.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared.Physics.CarPhysics)
local DriveAssist = require(Shared.Cars.DriveAssist)
local EasySteer = require(Shared.Cars.EasySteer)
local MatchState = require(Shared.Match.MatchState)
local QuickChat = require(Shared.Config.QuickChat)
local Signal = require(Shared.Util.Signal)

local InputController = {}

InputController.MegaPressed = Signal.new() :: Signal.Signal<>
InputController.ItemPressed = Signal.new() :: Signal.Signal<>
InputController.PowerPressed = Signal.new() :: Signal.Signal<>
InputController.HornPressed = Signal.new() :: Signal.Signal<>
InputController.BallCamToggled = Signal.new() :: Signal.Signal<>
InputController.MenuPressed = Signal.new() :: Signal.Signal<>
-- A quick chat key: the phrase to say (see QuickChat), or 0 to open/close the list.
InputController.ChatPressed = Signal.new() :: Signal.Signal<number>

local DEADZONE = 0.15

local touchStick = Vector2.zero
local touchHeld: { [string]: boolean } = {}
local actionsBound = false
local blocked = false
local easySteer = true
local last: CarPhysics.Input = CarPhysics.NoInput
local keySteer = 0 -- keyboard steering, eased in and out (with driving help on)
local lastRead = os.clock()

-- What the car needs to know to turn the touch stick into steering.
export type Context = { carCFrame: CFrame, grounded: boolean }

-- Is this a phone or tablet (touch, no keyboard)?
function InputController.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Easy steering for the touch stick: point where you want to go (on), or steer + drive like a gamepad (off).
function InputController.setEasySteer(on: boolean)
	easySteer = on
end

function InputController.easySteer(): boolean
	return easySteer
end

-- The controls most recently read for the car (for the wheels' steering animation).
function InputController.last(): CarPhysics.Input
	return last
end

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

-- Is driving help on? (It is unless the player has switched it off; see DriveAssist.)
function InputController.assist(): boolean
	return Players.LocalPlayer:GetAttribute(MatchState.PlayerAttr.Assist) ~= false
end

-- The current controls. Returns "no input" while the player is typing in chat or a menu is open.
function InputController.read(context: Context?): CarPhysics.Input
	local now = os.clock()
	local dt = math.clamp(now - lastRead, 0, 0.1)
	lastRead = now
	if blocked or UserInputService:GetFocusedTextBox() then
		keySteer = 0
		last = CarPhysics.NoInput
		return last
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
	local keys = 0
	if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then
		keys += 1
	end
	if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then
		keys -= 1
	end
	-- With driving help, a tap is a gentle nudge and holding the key builds up to a full turn.
	keySteer = if InputController.assist() then DriveAssist.smoothKey(keySteer, keys, dt) else keys
	steer += keySteer
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
		local camera = workspace.CurrentCamera
		if easySteer and context and context.grounded and camera then
			local driveThrottle, driveSteer = EasySteer.input(touchStick, context.carCFrame, camera.CFrame)
			throttle += driveThrottle
			steer += driveSteer
		else
			steer += touchStick.X
			throttle += touchStick.Y
		end
	end
	boost = boost or touchHeld.boost == true
	jump = jump or touchHeld.jump == true

	last = {
		throttle = math.clamp(throttle, -1, 1),
		steer = math.clamp(steer, -1, 1),
		pitch = if pitch then math.clamp(pitch, -1, 1) else nil,
		roll = math.clamp(roll, -1, 1),
		boost = boost,
		jump = jump,
	}
	return last
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

-- Quick chat keys and what they do (0 = open/close the list of phrases).
local CHAT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.T] = 0,
	[Enum.KeyCode.DPadLeft] = QuickChat.indexOf(QuickChat.Gamepad.Left) or 1,
	[Enum.KeyCode.DPadRight] = QuickChat.indexOf(QuickChat.Gamepad.Right) or 1,
	[Enum.KeyCode.DPadDown] = QuickChat.indexOf(QuickChat.Gamepad.Down) or 1,
}
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
}
for index = 1, math.min(#NUMBER_KEYS, #QuickChat.Phrases) do
	CHAT_KEYS[NUMBER_KEYS[index]] = index
end

-- One-press actions (Mega Shot, items, powers, ball cam, quick chat) are bound only while driving, so they don't
-- clash with anything else.
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
	if driving then
		local keys: { Enum.KeyCode } = {}
		for key in CHAT_KEYS do
			table.insert(keys, key)
		end
		ContextActionService:BindActionAtPriority("TurboChat", function(_, inputState, input)
			local slot = CHAT_KEYS[input.KeyCode]
			if inputState == Enum.UserInputState.Begin and not blocked and slot then
				InputController.ChatPressed:Fire(slot)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	else
		ContextActionService:UnbindAction("TurboChat")
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
