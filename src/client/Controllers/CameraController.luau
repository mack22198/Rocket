--!strict
-- The one place that moves the camera. While driving it's a chase camera: ball cam (on by default) keeps the
-- ball in view; press C / Y for a plain behind-the-car view. It leans back and widens at top speed and when you
-- dash, for a feeling of speed. In the menus the showroom provides the shots (see setProvider), and if there's nothing to
-- follow at all it slowly circles the stadium.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local GameConfig = require(Shared.Config.GameConfig)
local MathUtil = require(Shared.Util.MathUtil)
local Signal = require(Shared.Util.Signal)

local BallView = require(script.Parent.BallView)
local CarController = require(script.Parent.CarController)
local InputController = require(script.Parent.InputController)

local CameraController = {}

CameraController.BallCamChanged = Signal.new() :: Signal.Signal<boolean>

local arena = ArenaShape.new(GameConfig.Arena)
local ballCam = true
local driving = false
local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil
local heading = Vector3.new(0, 0, -1)
local shakeUntil = 0
local shakeStrength = 0

local DISTANCE = 18.5
local HEIGHT = 7.2
local FOV = 78
local DASH_FOV = 8 -- extra field of view at full dash speed
local DASH_PULL = 2.5 -- extra distance at full dash speed

-- Something else that wants to place the camera (the menu showroom). Returns nil when it has nothing to show.
type Provider = (dt: number) -> (CFrame?, number)
local provider: Provider? = nil
local speedFeel = 0

-- Nothing to follow (e.g. between the menu and your car appearing): a slow flight around the stadium.
local function overview(camera: Camera)
	local t = os.clock() * 0.05
	local position = Vector3.new(math.cos(t) * 250, 105, math.sin(t) * 250)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55
	camera.CFrame = MathUtil.lookAlong(position, Vector3.new(0, 10, 0) - position, Vector3.yAxis)
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local p = provider
	if p then
		local cframe, fov = p(dt)
		if cframe then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = cframe
			camera.FieldOfView = fov
			return
		end
	end
	local chassis = CarController.getChassis()
	if not chassis or not driving then
		overview(camera)
		return
	end
	local carPos = chassis.Position
	local velocity = chassis.AssemblyLinearVelocity
	local flatVelocity = MathUtil.flat(velocity)

	-- Which way to look: at the ball (ball cam) or where the car is going.
	local wanted: Vector3
	if ballCam and BallView.isVisible() then
		wanted = MathUtil.safeUnit(MathUtil.flat(BallView.getPosition() - carPos), heading)
	elseif flatVelocity.Magnitude > 12 then
		wanted = flatVelocity.Unit
	else
		wanted = MathUtil.safeUnit(MathUtil.flat(chassis.CFrame.LookVector), heading)
	end
	heading = MathUtil.safeUnit(heading:Lerp(wanted, MathUtil.expDecay(8, dt)), wanted)

	-- The faster you go (dashing especially), the further back the camera sits and the wider it sees.
	local wantedFeel = math.clamp((flatVelocity.Magnitude - GameConfig.Car.MaxSpeed * 0.8) / 60, 0, 1)
	if CarController.isDashing() then
		wantedFeel = math.max(wantedFeel, 0.6)
	end
	speedFeel = MathUtil.lerp(speedFeel, wantedFeel, MathUtil.expDecay(if wantedFeel > speedFeel then 4 else 2, dt))

	local desiredPosition = carPos - heading * (DISTANCE + DASH_PULL * speedFeel) + Vector3.new(0, HEIGHT, 0)
	desiredPosition = arena:clampInside(desiredPosition, 2.5)
	local focus: Vector3
	if ballCam and BallView.isVisible() then
		local ball = BallView.getPosition()
		-- Look between the car and the ball, leaning toward the ball.
		focus = carPos:Lerp(ball, 0.55) + Vector3.new(0, 2, 0)
		local maxRise = 28
		if focus.Y - carPos.Y > maxRise then
			focus = Vector3.new(focus.X, carPos.Y + maxRise, focus.Z)
		end
	else
		focus = carPos + heading * 12 + Vector3.new(0, 2, 0)
	end

	local blend = MathUtil.expDecay(14, dt)
	local position = if smoothedPosition then smoothedPosition:Lerp(desiredPosition, blend) else desiredPosition
	local smoothFocus = if smoothedFocus then smoothedFocus:Lerp(focus, MathUtil.expDecay(18, dt)) else focus
	smoothedPosition, smoothedFocus = position, smoothFocus

	local shake = Vector3.zero
	if os.clock() < shakeUntil then
		local s = shakeStrength * (shakeUntil - os.clock())
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * s
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV + DASH_FOV * speedFeel
	camera.CFrame = MathUtil.lookAlong(position + shake, smoothFocus - position, Vector3.yAxis)
end

local function setDriving(on: boolean)
	driving = on
	if on then
		smoothedPosition, smoothedFocus = nil, nil
		speedFeel = 0
		local chassis = CarController.getChassis()
		if chassis then
			heading = MathUtil.safeUnit(MathUtil.flat(chassis.CFrame.LookVector), heading)
		end
	end
end

function CameraController.start()
	CarController.CarChanged:Connect(function(car)
		setDriving(car ~= nil)
	end)
	InputController.BallCamToggled:Connect(function()
		ballCam = not ballCam
		CameraController.BallCamChanged:Fire(ballCam)
	end)
	RunService:BindToRenderStep("TurboBallCamera", Enum.RenderPriority.Camera.Value + 1, update)
	setDriving(CarController.getCar() ~= nil)
end

-- Lets something else (the menu showroom) place the camera; nil hands it back.
function CameraController.setProvider(newProvider: Provider?)
	provider = newProvider
	if not newProvider then
		-- Snap straight to the car instead of gliding in from the showroom.
		smoothedPosition, smoothedFocus = nil, nil
	end
end

-- Hands the camera back, but only if `oldProvider` is still the one placing it.
function CameraController.releaseProvider(oldProvider: Provider)
	if provider == oldProvider then
		CameraController.setProvider(nil)
	end
end

function CameraController.toggleBallCam()
	ballCam = not ballCam
	CameraController.BallCamChanged:Fire(ballCam)
end

function CameraController.isBallCam(): boolean
	return ballCam
end

function CameraController.shake(strength: number, duration: number)
	shakeStrength = strength / math.max(duration, 0.01)
	shakeUntil = os.clock() + duration
end

return CameraController
