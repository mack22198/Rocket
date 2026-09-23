--!strict
-- Chase camera for driving. Ball cam (on by default) keeps the ball in view; press C / Y to switch to a
-- plain behind-the-car view. Outside a match the normal Roblox camera follows your avatar.

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

local DISTANCE = 17
local HEIGHT = 6.5
local FOV = 78

local function update(dt: number)
	local camera = workspace.CurrentCamera
	local chassis = CarController.getChassis()
	if not camera or not chassis or not driving then
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

	local desiredPosition = carPos - heading * DISTANCE + Vector3.new(0, HEIGHT, 0)
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
	camera.FieldOfView = FOV
	camera.CFrame = MathUtil.lookAlong(position + shake, smoothFocus - position, Vector3.yAxis)
end

local function setDriving(on: boolean)
	driving = on
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if on then
		smoothedPosition, smoothedFocus = nil, nil
		local chassis = CarController.getChassis()
		if chassis then
			heading = MathUtil.safeUnit(MathUtil.flat(chassis.CFrame.LookVector), heading)
		end
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
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
