--!strict
-- Spawns and removes cars, hands players physics ownership of their own car, and runs the server side of
-- boost and Mega Shot (the server decides how much boost you have; your client just asks to use it).
-- It also keeps each car's attributes in step with the match (boost, Mega, item, power, active effects), which
-- is how every client knows what to draw.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarDriver = require(Shared.Cars.CarDriver)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)

type Participant = Roster.Participant

local CarService = {}

local carsFolder: Folder
local arenaFolder: Instance
local unlimitedBoost = false -- the Turbo Mode twist
local lastHonk: { [string]: number } = {}
local HONK_GAP = 1.2 -- seconds between honks

local A = MatchState.CarAttr

-- Cars bump into each other, except a car that's diving like a ghost (Shark Dive), which passes through.
local CAR_GROUP = "TurboCars"
local GHOST_GROUP = "TurboGhosts"

local function teamColor(team: Roster.Team): Color3
	return GameConfig.Teams[team].Color
end

local function setIfChanged(car: Model, name: string, value: any)
	if car:GetAttribute(name) ~= value then
		car:SetAttribute(name, value)
	end
end

local function syncAttributes(p: Participant)
	local car = p.car
	if not car then
		return
	end
	local boost = math.floor(p.boost + 0.5)
	if car:GetAttribute(A.Boost) ~= boost then
		car:SetAttribute(A.Boost, boost)
	end
	local mega = math.floor(p.mega + 0.5)
	if car:GetAttribute(A.Mega) ~= mega then
		car:SetAttribute(A.Mega, mega)
	end
	-- Hot Sauce (the Taco Truck's power) arms a Mega Shot for a few seconds too.
	local armed = p.megaArmed or Roster.hasEffect(p, "hotsauce", workspace:GetServerTimeNow())
	if car:GetAttribute(A.MegaArmed) ~= armed then
		car:SetAttribute(A.MegaArmed, armed)
	end
	local boosting = p.boosting and p.boost > 0
	if car:GetAttribute(A.Boosting) ~= boosting then
		car:SetAttribute(A.Boosting, boosting)
	end

	local now = workspace:GetServerTimeNow()
	setIfChanged(car, A.Item, p.item or "")
	setIfChanged(car, A.ItemReadyAt, p.itemReadyAt)
	setIfChanged(car, A.PowerReadyAt, p.powerReadyAt)
	setIfChanged(car, A.Shield, Roster.hasEffect(p, "shield", now))
	setIfChanged(car, A.Frozen, Roster.hasEffect(p, "frozen", now))
	setIfChanged(car, A.Rocket, Roster.hasEffect(p, "rocket", now))
	local ghost = Roster.hasEffect(p, "ghost", now)
	setIfChanged(car, A.Ghost, ghost)
	local pull = if Roster.hasEffect(p, "beam", now)
		then "beam"
		elseif Roster.hasEffect(p, "magnet", now) then "magnet"
		else ""
	setIfChanged(car, A.Pull, pull)
	local chassis = p.chassis
	local group = if ghost then GHOST_GROUP else CAR_GROUP
	if chassis and chassis.CollisionGroup ~= group then
		chassis.CollisionGroup = group
	end
end

local function registerCollisionGroups()
	local ok, err = pcall(function()
		for _, name in { CAR_GROUP, GHOST_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, CAR_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, GHOST_GROUP, false)
	end)
	if not ok then
		warn(`[Cars] Couldn't set up collision groups: {err}`)
	end
end

function CarService.init(arena: Instance)
	arenaFolder = arena
	registerCollisionGroups()
	local matchFolder = workspace:FindFirstChild(MatchState.Folders.Match)
	if not matchFolder then
		local created = Instance.new("Folder")
		created.Name = MatchState.Folders.Match
		created.Parent = workspace
		matchFolder = created
	end
	local cars = Instance.new("Folder")
	cars.Name = MatchState.Folders.Cars
	cars.Parent = matchFolder
	carsFolder = cars

	Remotes.SetBoosting.OnServerEvent:Connect(function(player: Player, boosting: unknown)
		local p = Roster.byPlayer(player)
		if p and type(boosting) == "boolean" then
			p.boosting = boosting
			syncAttributes(p)
		end
	end)

	Remotes.ActivateMega.OnServerEvent:Connect(function(player: Player)
		local p = Roster.byPlayer(player)
		if p then
			CarService.activateMega(p)
		end
	end)

	Remotes.Horn.OnServerEvent:Connect(function(player: Player)
		local p = Roster.byPlayer(player)
		if p then
			CarService.honk(p)
		end
	end)
end

-- Builds the participant's car at `cframe`, frozen in place until release() is called.
function CarService.spawn(p: Participant, cframe: CFrame)
	CarService.despawn(p)
	local model = CarModelBuilder.build(p.def, { teamColor = teamColor(p.team), stage = p.stage, topper = p.topper })
	model.Name = p.name
	model:SetAttribute(A.OwnerUserId, if p.player then p.player.UserId else 0)
	model:SetAttribute(A.IsBot, p.isBot)
	model:SetAttribute(A.DriverName, p.name)
	model:SetAttribute(A.Team, p.team)
	model:SetAttribute(A.CarId, p.def.Id)
	model:SetAttribute(A.Power, Powers.forCar(p.def.Id).Id)
	local chassis = model.PrimaryPart :: BasePart
	chassis.CollisionGroup = CAR_GROUP
	chassis.Anchored = true
	model:PivotTo(cframe)
	model.Parent = carsFolder
	p.car = model
	p.chassis = chassis
	if p.isBot then
		p.driver = CarDriver.new(model, p.def, arenaFolder)
	end
	syncAttributes(p)
end

function CarService.despawn(p: Participant)
	if p.car then
		p.car:Destroy()
	end
	p.car = nil
	p.chassis = nil
	p.driver = nil
	p.boosting = false
end

-- Teleports the car and holds it still (kickoff countdown).
function CarService.freezeAt(p: Participant, cframe: CFrame)
	local car, chassis = p.car, p.chassis
	if not car or not chassis then
		return
	end
	chassis.Anchored = true
	car:PivotTo(cframe)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	if p.driver then
		p.driver:reset()
	end
end

-- Lets the car move. Players get physics ownership so driving feels instant on their screen.
function CarService.release(p: Participant)
	local chassis = p.chassis
	if not chassis then
		return
	end
	chassis.Anchored = false
	local owner: Player? = nil
	if p.player and p.player.Parent == Players then
		owner = p.player
	end
	local ok, err = pcall(function()
		chassis:SetNetworkOwner(owner)
	end)
	if not ok then
		warn(`[Cars] Could not set network owner for {p.name}: {err}`)
	end
end

function CarService.activateMega(p: Participant)
	if p.car and not p.megaArmed and p.mega >= GameConfig.Mega.Max then
		p.megaArmed = true
		p.megaArmedUntil = workspace:GetServerTimeNow() + GameConfig.Mega.ArmedDuration
		syncAttributes(p)
	end
end

-- Called when a Mega Shot hits the ball.
function CarService.consumeMega(p: Participant)
	p.megaArmed = false
	p.mega = 0
	syncAttributes(p)
end

function CarService.addMega(p: Participant, amount: number)
	if p.megaArmed then
		return
	end
	p.mega = math.clamp(p.mega + amount, 0, GameConfig.Mega.Max)
	syncAttributes(p)
end

function CarService.addBoost(p: Participant, amount: number)
	p.boost = math.clamp(p.boost + amount, 0, 100)
	syncAttributes(p)
end

function CarService.resetForKickoff(p: Participant)
	p.boost = GameConfig.Car.StartingBoost
	p.boosting = false
	syncAttributes(p)
end

-- Drains boost for anyone holding the boost button (unless they're on Rocket Fuel), and times out unused
-- Mega Shots.
function CarService.tick(dt: number, live: boolean)
	local now = workspace:GetServerTimeNow()
	for _, p in Roster.all() do
		if unlimitedBoost or Roster.hasEffect(p, "rocket", now) then
			p.boost = 100
		elseif live and p.boosting and p.boost > 0 then
			p.boost = math.max(0, p.boost - GameConfig.Car.BoostDrainPerSecond * dt)
		end
		if p.megaArmed and now > p.megaArmedUntil then
			p.megaArmed = false -- fizzled, but the meter stays full so it can be armed again
		end
		syncAttributes(p)
	end
end

-- Honks the car's horn for everyone to hear (not too often).
function CarService.honk(p: Participant)
	local car = p.car
	local now = os.clock()
	if not car or now - (lastHonk[p.key] or -math.huge) < HONK_GAP then
		return
	end
	lastHonk[p.key] = now
	Remotes.HornPlayed:FireAllClients(car, p.horn)
end

-- Turbo Mode: boost never runs out.
function CarService.setUnlimitedBoost(on: boolean)
	unlimitedBoost = on
end

-- Pushes this car's attributes out now (after an item or power changed something).
function CarService.sync(p: Participant)
	syncAttributes(p)
end

-- Gives a car a sudden change of speed. Players' cars are driven by their own client, so it's sent there.
function CarService.push(p: Participant, change: Vector3)
	if p.driver then
		p.driver:addVelocity(change)
	elseif p.player then
		Remotes.Bumped:FireClient(p.player, change)
	end
end

-- Spins a car out, slows it down or freezes it (see CarPhysics.applyEffect), wherever it's being driven.
function CarService.applyEffect(p: Participant, effect: string, duration: number, direction: number?)
	if p.driver then
		p.driver:applyEffect(effect, duration, direction)
	elseif p.player then
		Remotes.CarEffect:FireClient(p.player, effect, duration, direction or 1)
	end
end

function CarService.carsFolder(): Folder
	return carsFolder
end

return CarService
