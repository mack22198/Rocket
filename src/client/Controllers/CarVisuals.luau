--!strict
-- Makes the cars look alive on your screen: wheels roll as fast as the car moves and the front ones steer,
-- a team-coloured light trail streams from the back of any car that's boosting, and wind streaks rush past
-- your own car when it boosts. None of this touches the physics - it's all just for looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local MathUtil = require(Shared.Util.MathUtil)

local CarController = require(script.Parent.CarController)
local InputController = require(script.Parent.InputController)

local CarVisuals = {}

type Wheel = { motor: Motor6D, radius: number, front: boolean, spin: number }
type Car = {
	model: Model,
	chassis: BasePart,
	wheels: { Wheel },
	trails: { Trail },
	streaks: { ParticleEmitter },
	steer: number,
	mine: boolean,
}

local A = MatchState.CarAttr
local MAX_STEER = math.rad(28)
local TAU = math.pi * 2

local localPlayer = Players.LocalPlayer
local cars: { [Model]: Car } = {}

local function teamColor(team: unknown): Color3
	if team == "Blue" then
		return GameConfig.Teams.Blue.Color
	elseif team == "Orange" then
		return GameConfig.Teams.Orange.Color
	end
	return Color3.new(1, 1, 1)
end

local function attachment(parent: BasePart, name: string, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

-- Two light trails from the back corners, like taillights streaking.
local function makeTrails(chassis: BasePart, color: Color3): { Trail }
	local size = chassis.Size
	local trails = {}
	for _, side in { -1, 1 } do
		local x = side * size.X * 0.36
		local z = size.Z / 2 + 0.2
		local trail = Instance.new("Trail")
		trail.Name = "BoostTrail"
		trail.Attachment0 = attachment(chassis, "TrailTop", Vector3.new(x, 0.25, z))
		trail.Attachment1 = attachment(chassis, "TrailBottom", Vector3.new(x, -0.45, z))
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0.3)
		trail.Lifetime = 0.45
		trail.LightEmission = 0.8
		trail.FaceCamera = true
		trail.Enabled = false
		trail.Parent = chassis
		table.insert(trails, trail)
	end
	return trails
end

-- Streaks of wind rushing past the sides of your car while you boost.
local function makeStreaks(chassis: BasePart): { ParticleEmitter }
	local size = chassis.Size
	local list = {}
	for _, side in { -1, 1 } do
		local point = attachment(chassis, "Streaks", Vector3.new(side * (size.X / 2 + 1.2), 0.8, -size.Z / 2 - 2))
		local ok, emitter = pcall(function()
			local e = Instance.new("ParticleEmitter")
			e.Name = "WindStreaks"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(230, 244, 255))
			e.LightEmission = 0.5
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
			e.Size = NumberSequence.new(0.35)
			e.Squash = NumberSequence.new(2.5)
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Lifetime = NumberRange.new(0.18, 0.3)
			e.Speed = NumberRange.new(70, 110)
			e.EmissionDirection = Enum.NormalId.Back
			e.SpreadAngle = Vector2.new(18, 18)
			e.Rate = 45
			e.Enabled = false
			e.Parent = point
			return e
		end)
		if ok and emitter then
			table.insert(list, emitter)
		end
	end
	return list
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local chassis = model:WaitForChild("Chassis", 10)
	if not chassis or not chassis:IsA("BasePart") or not model.Parent then
		return
	end
	local wheels: { Wheel } = {}
	for _, hub in model:GetChildren() do
		if hub.Name == "WheelHub" and hub:IsA("BasePart") then
			local motor = hub:FindFirstChildOfClass("Motor6D") or hub:WaitForChild("WheelMotor", 5)
			if motor and motor:IsA("Motor6D") then
				local radius = hub:GetAttribute("Radius")
				table.insert(wheels, {
					motor = motor,
					radius = if type(radius) == "number" and radius > 0 then radius else 1,
					front = hub:GetAttribute("Front") == true,
					spin = 0,
				})
			end
		end
	end
	local mine = model:GetAttribute(A.OwnerUserId) == localPlayer.UserId
	cars[model] = {
		model = model,
		chassis = chassis,
		wheels = wheels,
		trails = makeTrails(chassis, teamColor(model:GetAttribute(A.Team))),
		streaks = if mine then makeStreaks(chassis) else {},
		steer = 0,
		mine = mine,
	}
end

local function isBoosting(car: Car): boolean
	if not car.mine then
		return car.model:GetAttribute(A.Boosting) == true
	end
	-- Your own car reacts to your key presses at once instead of waiting for the server.
	return CarController.isBoosting()
end

local function step(dt: number)
	for model, car in cars do
		if not model.Parent then
			cars[model] = nil
			continue
		end
		local chassis = car.chassis
		local frame = chassis.CFrame
		local velocity = chassis.AssemblyLinearVelocity
		local forward = velocity:Dot(frame.LookVector)

		-- Steering: your own input, or (for everyone else) worked out from how fast the car is turning.
		local target: number
		if car.mine and CarController.getCar() == model then
			target = -InputController.read().steer * MAX_STEER
		else
			local yawRate = chassis.AssemblyAngularVelocity:Dot(frame.UpVector)
			target = if math.abs(forward) > 3
				then math.clamp(yawRate * 0.35 * math.sign(forward), -MAX_STEER, MAX_STEER)
				else 0
		end
		car.steer = MathUtil.lerp(car.steer, target, MathUtil.expDecay(12, dt))

		for _, wheel in car.wheels do
			wheel.spin = (wheel.spin - forward / wheel.radius * dt) % TAU
			local turn = if wheel.front then CFrame.Angles(0, car.steer, 0) else CFrame.identity
			wheel.motor.Transform = turn * CFrame.Angles(wheel.spin, 0, 0)
		end

		local boosting = isBoosting(car)
		for _, trail in car.trails do
			trail.Enabled = boosting
		end
		for _, streak in car.streaks do
			streak.Enabled = boosting and forward > 40
		end
	end
end

function CarVisuals.start()
	local carsFolder = workspace:WaitForChild(MatchState.Folders.Match):WaitForChild(MatchState.Folders.Cars)
	carsFolder.ChildAdded:Connect(function(child)
		task.spawn(track, child)
	end)
	carsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			cars[child] = nil
		end
	end)
	for _, child in carsFolder:GetChildren() do
		task.spawn(track, child)
	end
	-- Joint transforms are set before each physics step, so they're in place when the frame is drawn.
	RunService.PreSimulation:Connect(step)
end

return CarVisuals
