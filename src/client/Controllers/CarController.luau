--!strict
-- Finds this player's car and drives it every physics step. The server gives each player physics ownership
-- of their own car, so steering and jumping respond instantly on their screen.
-- Ultimates are the server's call, but the ones that launch your own car (Nitro Rocket, Shark Dive and the
-- Pizza Shark's Cheesy Dive) launch it here the moment you press the button, and the server tells this car when
-- it has been spun out or slowed down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarDriver = require(Shared.Cars.CarDriver)
local CarPhysics = require(Shared.Physics.CarPhysics)
local DriveAssist = require(Shared.Cars.DriveAssist)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local InputController = require(script.Parent.InputController)

local CarController = {}

CarController.CarChanged = Signal.new() :: Signal.Signal<Model?>
CarController.Jumped = Signal.new() :: Signal.Signal<>
-- Fired when the server spins out, slows down or freezes your car: (effect, seconds).
CarController.EffectApplied = Signal.new() :: Signal.Signal<string, number>

local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()
local A = MatchState.CarAttr

-- Where the ball is and how big it is (BallView hands this over, since it requires this module).
local ballInfo: (() -> (Vector3, Vector3, number, boolean))? = nil

local myCar: Model? = nil
local driver: CarDriver.CarDriver? = nil
-- When you last set off your ultimate, so a second press can't sneak in before the server's answer arrives.
local ultUsedAt = -math.huge

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function setCar(model: Model?)
	if model == myCar then
		return
	end
	myCar = model
	driver = nil
	if not model then
		InputController.setDriving(false)
		CarController.CarChanged:Fire(nil)
		return
	end
	-- The car's parts can arrive a moment after the model itself, so wait for the chassis first.
	task.spawn(function()
		local chassis = model:WaitForChild("Chassis", 10)
		local arena = workspace:WaitForChild(MatchState.Folders.Arena)
		local carId = model:GetAttribute(A.CarId)
		local def = if type(carId) == "string" then CarCatalog.get(carId) else nil
		if myCar ~= model or not chassis or not def then
			return
		end
		driver = CarDriver.new(model, def, arena)
		InputController.setDriving(true)
		CarController.CarChanged:Fire(model)
	end)
end

local function isMine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute(A.OwnerUserId) == localPlayer.UserId
end

local function step(dt: number)
	local car, d = myCar, driver
	if not car or not d then
		return
	end
	local phase = MatchState.phase(stateObject)
	local canDrive = phase == MatchState.Phases.Playing or phase == MatchState.Phases.GoalScored
	local input = if canDrive
		then InputController.read({ carCFrame = d.chassis.CFrame, grounded = d:isGrounded() })
		else CarPhysics.NoInput
	-- Driving help: steer toward the ball when it's ahead, jump toward it and flip into it, stay level in the air.
	local assist: CarPhysics.Assist? = nil
	local info = ballInfo
	if canDrive and info and InputController.assist() then
		local ballPosition, ballVelocity, radius, visible = info()
		local team = car:GetAttribute(A.Team)
		assist = { ball = if visible then ballPosition else nil, level = true }
		if visible and (team == "Blue" or team == "Orange") then
			local goal = DriveAssist.enemyGoal(
				GameConfig.Teams[team :: string].DefendsSide,
				GameConfig.Arena.Length,
				GameConfig.Arena.GoalHeight
			)
			local steer = DriveAssist.steer({
				carCFrame = d.chassis.CFrame,
				carVelocity = d.chassis.AssemblyLinearVelocity,
				grounded = d:isGrounded(),
				throttle = input.throttle,
				steer = input.steer,
				ballPosition = ballPosition,
				ballVelocity = ballVelocity,
				ballRadius = radius,
				enemyGoal = goal,
			})
			if steer ~= input.steer then
				local steered = table.clone(input)
				steered.steer = steer
				input = steered
			end
		end
	end
	local result = d:step(dt, input, false, assist)
	if result and (result.jumped or result.dodged) then
		CarController.Jumped:Fire()
	end
end

function CarController.start()
	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local carsFolder = matchFolder:WaitForChild(MatchState.Folders.Cars)

	carsFolder.ChildAdded:Connect(function(child)
		if isMine(child) then
			setCar(child :: Model)
		end
	end)
	carsFolder.ChildRemoved:Connect(function(child)
		if child == myCar then
			setCar(nil)
		end
	end)
	for _, child in carsFolder:GetChildren() do
		if isMine(child) then
			setCar(child :: Model)
		end
	end

	RunService.PreSimulation:Connect(step)

	Remotes.Bumped.OnClientEvent:Connect(function(change: unknown)
		if driver and typeof(change) == "Vector3" then
			driver:addVelocity(change)
		end
	end)
	Remotes.CarEffect.OnClientEvent:Connect(function(effect: unknown, duration: unknown, direction: unknown)
		local d = driver
		if d and type(effect) == "string" and type(duration) == "number" then
			d:applyEffect(effect, math.clamp(duration, 0, 10), if type(direction) == "number" then direction else 1)
			CarController.EffectApplied:Fire(effect, duration)
		end
	end)
	InputController.UltimatePressed:Connect(CarController.useUltimate)
	InputController.HornPressed:Connect(function()
		if myCar then
			Remotes.Horn:FireServer()
		end
	end)
end

-- How full your ultimate meter is (0 to GameConfig.Ultimate.Max), and whether it's ready to go.
function CarController.ultCharge(): (number, boolean)
	local car = myCar
	local charge = if car then numberAttribute(car, A.Ult) else 0
	return charge, charge >= GameConfig.Ultimate.Max
end

-- Sets off your car's ultimate (E / X / ULT), if the meter is full and the ball is in play.
function CarController.useUltimate()
	local car, d = myCar, driver
	local _, ready = CarController.ultCharge()
	if not car or not d or not ready or d.chassis.Anchored then
		return
	end
	if MatchState.phase(stateObject) ~= MatchState.Phases.Playing or os.clock() - ultUsedAt < 1 then
		return
	end
	ultUsedAt = os.clock()
	local power = car:GetAttribute(A.Power)
	local def = if type(power) == "string" then Powers.power(power) else nil
	if def then
		-- The ultimates that launch your car launch it now, so it feels instant.
		for _, part in Powers.components(def) do
			local change = Powers.launch(part.Id, d.chassis.CFrame)
			if change then
				d:addVelocity(change)
			end
		end
	end
	Remotes.UseUltimate:FireServer()
end

-- Is your car dashing right now (a Nitro Rocket or Shark Dive)?
function CarController.isDashing(): boolean
	local car = myCar
	return car ~= nil and car:GetAttribute(A.Dashing) == true
end

-- What's happening to your car: seconds left spinning out, stuck in goo and frozen.
function CarController.effects(): (number, number, number)
	local d = driver
	if not d then
		return 0, 0, 0
	end
	return d.state.spinTimer, d.state.slowTimer, d.state.freezeTimer
end

-- Your car, once it's fully ready to drive (nil in the lobby).
function CarController.getCar(): Model?
	return if driver then myCar else nil
end

function CarController.getChassis(): BasePart?
	local d = driver
	return if d and myCar then d.chassis else nil
end

-- BallView tells the car where the ball is, for driving help: (position, velocity, radius, visible).
function CarController.setBallInfo(provider: () -> (Vector3, Vector3, number, boolean))
	ballInfo = provider
end

-- Used by BallView to give the car the small push back from hitting the ball.
function CarController.addVelocity(change: Vector3)
	if driver then
		driver:addVelocity(change)
	end
end

function CarController.isGrounded(): boolean
	return driver ~= nil and (driver :: CarDriver.CarDriver):isGrounded()
end

return CarController
