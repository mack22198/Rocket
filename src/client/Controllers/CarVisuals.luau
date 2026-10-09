--!strict
-- Makes the cars look alive on your screen: wheels roll as fast as the car moves and the front ones steer,
-- a team-coloured light trail streams from the back of any car that's dashing (a Nitro Rocket or Shark Dive),
-- wind streaks rush past your own car when it dashes, tyres smoke when a car slides sideways, and dust puffs up
-- when a car lands from a big jump. None of this touches the physics - it's all just for looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local MathUtil = require(Shared.Util.MathUtil)

local CameraController = require(script.Parent.CameraController)
local CarController = require(script.Parent.CarController)
local InputController = require(script.Parent.InputController)
local LocalHide = require(script.Parent.LocalHide)

local CarVisuals = {}

type Wheel = { motor: Motor6D, radius: number, front: boolean, spin: number }
type Car = {
	model: Model,
	chassis: BasePart,
	wheels: { Wheel },
	trails: { Trail },
	streaks: { ParticleEmitter },
	smoke: { ParticleEmitter },
	steer: number,
	mine: boolean,
	grounded: boolean,
	airTime: number, -- seconds since its wheels last touched anything
	fallSpeed: number, -- how fast it was coming down just before landing
}

local A = MatchState.CarAttr
local MAX_STEER = math.rad(28)
local TAU = math.pi * 2

local localPlayer = Players.LocalPlayer
local cars: { [Model]: Car } = {}
local SLIDE_SPEED = 22 -- sideways speed that makes the tyres smoke
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local groundRay: RaycastParams? = nil

-- What counts as ground: the arena (found once it exists).
local function groundParams(): RaycastParams?
	if groundRay then
		return groundRay
	end
	local arena = workspace:FindFirstChild(MatchState.Folders.Arena)
	if not arena then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arena }
	groundRay = params
	return params
end

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
		trail.Name = "DashTrail"
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

-- Streaks of wind rushing past the sides of your car while you dash.
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

-- Tyre smoke from the two back wheels, switched on while the car slides.
local function makeSmoke(chassis: BasePart): { ParticleEmitter }
	local size = chassis.Size
	local list = {}
	for _, side in { -1, 1 } do
		local point =
			attachment(chassis, "TyreSmoke", Vector3.new(side * (size.X / 2 - 0.4), -size.Y / 2, size.Z / 2 - 1.2))
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "TyreSmoke"
		emitter.Texture = SMOKE_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
		emitter.Size = NumberSequence.new(1.2, 4)
		emitter.Transparency = NumberSequence.new(0.55, 1)
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Acceleration = Vector3.new(0, 3, 0)
		emitter.Drag = 2
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.Rate = 28
		emitter.Enabled = false
		emitter.Parent = point
		table.insert(list, emitter)
	end
	return list
end

-- A ring of dust where a car lands from a big jump.
local function landingDust(position: Vector3, strength: number)
	local point = Instance.new("Attachment")
	point.WorldPosition = position + Vector3.new(0, 0.5, 0)
	point.Parent = workspace.Terrain
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(226, 230, 214))
	dust.Size = NumberSequence.new(1.5, 5)
	dust.Transparency = NumberSequence.new(0.45, 1)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Speed = NumberRange.new(10 * strength, 18 * strength)
	dust.SpreadAngle = Vector2.new(180, 8)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Drag = 4
	dust.Rate = 0
	dust.Parent = point
	dust:Emit(math.floor(10 + 14 * strength))
	task.delay(1.5, function()
		point:Destroy()
	end)
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
		smoke = makeSmoke(chassis),
		steer = 0,
		mine = mine,
		grounded = true,
		airTime = 0,
		fallSpeed = 0,
	}
end

local function isDashing(car: Car): boolean
	return car.model:GetAttribute(A.Dashing) == true
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
			target = -InputController.last().steer * MAX_STEER
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

		local dashing = isDashing(car) and not LocalHide.isHidden(model)
		for _, trail in car.trails do
			trail.Enabled = dashing
		end
		for _, streak in car.streaks do
			streak.Enabled = dashing and forward > 40
		end

		-- Landing from a big jump kicks up dust; sliding sideways makes the tyres smoke.
		local params = groundParams()
		local hit = if params
			then workspace:Raycast(frame.Position, -frame.UpVector * (chassis.Size.Y / 2 + 2.6), params)
			else nil
		local grounded = hit ~= nil
		local hidden = LocalHide.isHidden(model)
		if grounded and not car.grounded and car.airTime > 0.35 and car.fallSpeed > 18 and not hidden then
			local strength = math.clamp(car.fallSpeed / 60, 0.4, 1.2)
			landingDust((hit :: RaycastResult).Position, strength)
			if car.mine then
				CameraController.shake(0.25 * strength, 0.15)
			end
		end
		car.airTime = if grounded then 0 else car.airTime + dt
		car.fallSpeed = if grounded then 0 else math.max(car.fallSpeed, -velocity.Y)
		car.grounded = grounded
		local sliding = grounded and math.abs(velocity:Dot(frame.RightVector)) > SLIDE_SPEED and not hidden
		for _, smoke in car.smoke do
			smoke.Enabled = sliding
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
