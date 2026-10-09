--!strict
-- Finds this player's car and drives it every physics step. The server gives each player physics ownership
-- of their own car, so steering and jumping respond instantly on their screen.
-- Items and powers are the server's call, but the ones that launch your own car (Super Spring, Nitro Dash,
-- Shark Dive and the Pizza Shark's Cheesy Dive) launch it here the moment you press the button, and the
-- server tells this car when it has been spun out, slowed down or frozen.

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
local sentBoosting = false
local boosting = false
-- Your own record of when you last used your item and power, so a second press can't sneak in before the
-- server's answer arrives.
local itemUsedAt = -math.huge
local powerUsedAt = -math.huge
local megaAskedAt = -math.huge

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

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
	boosting = false
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
	local hasBoost = numberAttribute(car, A.Boost) > 0
	local result = d:step(dt, input, hasBoost, assist)
	boosting = canDrive and result ~= nil and result.boosting
	if boosting ~= sentBoosting then
		sentBoosting = boosting
		Remotes.SetBoosting:FireServer(boosting)
	end
	if result and (result.jumped or result.dodged) then
		CarController.Jumped:Fire()
	end
	-- On phones and tablets the Mega Shot arms itself as soon as the meter is full (one button fewer).
	if
		canDrive
		and InputController.isTouch()
		and numberAttribute(car, A.Mega) >= GameConfig.Mega.Max
		and car:GetAttribute(A.MegaArmed) ~= true
		and os.clock() - megaAskedAt > 1
	then
		megaAskedAt = os.clock()
		Remotes.ActivateMega:FireServer()
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
	InputController.ItemPressed:Connect(CarController.useItem)
	InputController.PowerPressed:Connect(CarController.usePower)
	InputController.HornPressed:Connect(function()
		if myCar then
			Remotes.Horn:FireServer()
		end
	end)

	InputController.MegaPressed:Connect(function()
		local car = myCar
		if car and numberAttribute(car, A.Mega) >= GameConfig.Mega.Max and car:GetAttribute(A.MegaArmed) ~= true then
			Remotes.ActivateMega:FireServer()
		end
	end)
end

-- Can your car use an item or power right now? (Returns the chassis if so.)
local function readyToAct(): BasePart?
	local car, d = myCar, driver
	if not car or not d or d.chassis.Anchored or car:GetAttribute(A.Frozen) == true or d.state.freezeTimer > 0 then
		return nil
	end
	if MatchState.phase(stateObject) ~= MatchState.Phases.Playing then
		return nil
	end
	return d.chassis
end

-- Launches your own car straight away for the items and powers that do that.
local function launchNow(kind: string, chassis: BasePart)
	local change = Powers.launch(kind, chassis.CFrame, chassis.AssemblyLinearVelocity)
	if change and driver then
		(driver :: CarDriver.CarDriver):addVelocity(change)
	end
end

-- Uses the item you're holding (R / RB / ITEM).
function CarController.useItem()
	local car = myCar
	local chassis = readyToAct()
	local item = if car then car:GetAttribute(A.Item) else nil
	if not car or not chassis or type(item) ~= "string" or item == "" then
		return
	end
	local now = serverNow()
	if now < numberAttribute(car, A.ItemReadyAt) or now - itemUsedAt < 0.5 then
		return
	end
	itemUsedAt = now
	launchNow(item, chassis)
	Remotes.UseItem:FireServer()
end

-- Uses your car's power (G / LB / POWER).
function CarController.usePower()
	local car = myCar
	local chassis = readyToAct()
	local power = if car then car:GetAttribute(A.Power) else nil
	if not car or not chassis or type(power) ~= "string" then
		return
	end
	local now = serverNow()
	if now < numberAttribute(car, A.PowerReadyAt) or now - powerUsedAt < 1 then
		return
	end
	powerUsedAt = now
	local def = Powers.power(power)
	if def then
		for _, part in Powers.components(def) do
			launchNow(part.Id, chassis)
		end
	end
	Remotes.UsePower:FireServer()
end

-- Is your car boosting right now (after spin-outs and goo have had their say)?
function CarController.isBoosting(): boolean
	return boosting
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
