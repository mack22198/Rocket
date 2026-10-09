--!strict
-- Spawns and removes cars, hands players physics ownership of their own car, and fills each car's ultimate
-- meter (see GameConfig.Ultimate): by itself as the match goes on, and when StatsService and OrbService say so.
-- It also keeps each car's attributes in step with the match (the meter, active effects), which is how every
-- client knows what to draw.

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
local ultMultiplier = 1 -- the Ultimate Rush twist fills meters faster
local lastHonk: { [string]: number } = {}
local stateObject = MatchState.getObject()
local U = GameConfig.Ultimate
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
	local now = workspace:GetServerTimeNow()
	setIfChanged(car, A.Ult, math.floor(p.ult))
	setIfChanged(car, A.Dashing, Roster.hasEffect(p, "dash", now))
	-- Hot Sauce (the Taco Truck's ultimate) makes the next hit a Mega Shot.
	setIfChanged(car, A.MegaArmed, Roster.hasEffect(p, "hotsauce", now))
	local ghost = Roster.hasEffect(p, "ghost", now)
	setIfChanged(car, A.Ghost, ghost)
	setIfChanged(car, A.Pull, if Roster.hasEffect(p, "beam", now) then "beam" else "")
	setIfChanged(car, A.UltActive, Roster.hasEffect(p, "ult", now))
	setIfChanged(car, A.Goo, Roster.hasEffect(p, "goo", now))
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
	model:SetAttribute(A.Level, p.level)
	model:SetAttribute(A.Title, p.title)
	model:SetAttribute(A.Vip, p.player ~= nil and p.player:GetAttribute(MatchState.PlayerAttr.Vip) == true)
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

-- How much `amount` of charge is worth to this car: a fused car's combo fills slower, and the Ultimate Rush
-- twist makes everyone's faster.
local function scaled(p: Participant, amount: number): number
	return amount * Powers.chargeRate(Powers.forCar(p.def.Id)) * ultMultiplier
end

-- Fills `p`'s ultimate meter by `amount` (before the car's own rate and the twist are counted).
function CarService.chargeUlt(p: Participant, amount: number)
	if p.ult >= U.Max then
		return
	end
	p.ult = math.min(U.Max, p.ult + scaled(p, amount))
	if p.ult >= U.Max then
		p.ultReadyAt = workspace:GetServerTimeNow()
	end
	syncAttributes(p)
end

-- Empties a full ultimate meter to set the ultimate off. Returns false if it isn't full.
function CarService.spendUlt(p: Participant): boolean
	if p.ult < U.Max then
		return false
	end
	p.ult = 0
	p.ultReadyAt = math.huge
	syncAttributes(p)
	return true
end

local function score(team: Roster.Team): number
	local value =
		stateObject:GetAttribute(if team == "Blue" then MatchState.Attr.BlueScore else MatchState.Attr.OrangeScore)
	return if type(value) == "number" then value else 0
end

-- Fills every ultimate meter a little while the ball is in play (faster for a team that's behind; the rest comes
-- from playing), and keeps the cars' attributes in step as effects wear off.
function CarService.tick(dt: number, live: boolean)
	local blue, orange = score("Blue"), score("Orange")
	for _, p in Roster.all() do
		if live and p.chassis and p.ult < U.Max then
			local behind = if p.team == "Blue" then blue < orange else orange < blue
			CarService.chargeUlt(p, U.PerSecond * dt * (if behind then 1 + U.BehindBonus else 1))
		else
			syncAttributes(p)
		end
	end
end

-- The Ultimate Rush twist: meters fill this many times faster.
function CarService.setUltMultiplier(multiplier: number)
	ultMultiplier = multiplier
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

-- Pushes this car's attributes out now (after an ultimate changed something).
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
