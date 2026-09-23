--!strict
-- Finds this player's car and drives it every physics step. The server gives each player physics ownership
-- of their own car, so steering and jumping respond instantly on their screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarDriver = require(Shared.Cars.CarDriver)
local CarPhysics = require(Shared.Physics.CarPhysics)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local InputController = require(script.Parent.InputController)

local CarController = {}

CarController.CarChanged = Signal.new() :: Signal.Signal<Model?>
CarController.Jumped = Signal.new() :: Signal.Signal<>

local localPlayer = Players.LocalPlayer
local stateObject = MatchState.getObject()
local A = MatchState.CarAttr

local myCar: Model? = nil
local driver: CarDriver.CarDriver? = nil
local sentBoosting = false

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
	sentBoosting = false
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
	local input = if canDrive then InputController.read() else CarPhysics.NoInput
	local hasBoost = numberAttribute(car, A.Boost) > 0
	local result = d:step(dt, input, hasBoost)
	local boosting = canDrive and input.boost and hasBoost
	if boosting ~= sentBoosting then
		sentBoosting = boosting
		Remotes.SetBoosting:FireServer(boosting)
	end
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

	InputController.MegaPressed:Connect(function()
		local car = myCar
		if car and numberAttribute(car, A.Mega) >= GameConfig.Mega.Max and car:GetAttribute(A.MegaArmed) ~= true then
			Remotes.ActivateMega:FireServer()
		end
	end)
end

-- Your car, once it's fully ready to drive (nil in the lobby).
function CarController.getCar(): Model?
	return if driver then myCar else nil
end

function CarController.getChassis(): BasePart?
	local d = driver
	return if d and myCar then d.chassis else nil
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
