--!strict
-- Spawns and removes cars, hands players physics ownership of their own car, and runs the server side of
-- boost and Mega Shot (the server decides how much boost you have; your client just asks to use it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarDriver = require(Shared.Cars.CarDriver)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)

type Participant = Roster.Participant

local CarService = {}

local carsFolder: Folder
local arenaFolder: Instance

local A = MatchState.CarAttr

local function teamColor(team: Roster.Team): Color3
	return GameConfig.Teams[team].Color
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
	if car:GetAttribute(A.MegaArmed) ~= p.megaArmed then
		car:SetAttribute(A.MegaArmed, p.megaArmed)
	end
	local boosting = p.boosting and p.boost > 0
	if car:GetAttribute(A.Boosting) ~= boosting then
		car:SetAttribute(A.Boosting, boosting)
	end
end

function CarService.init(arena: Instance)
	arenaFolder = arena
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
end

-- Builds the participant's car at `cframe`, frozen in place until release() is called.
function CarService.spawn(p: Participant, cframe: CFrame)
	CarService.despawn(p)
	local model = CarModelBuilder.build(p.def, { teamColor = teamColor(p.team) })
	model.Name = p.name
	model:SetAttribute(A.OwnerUserId, if p.player then p.player.UserId else 0)
	model:SetAttribute(A.IsBot, p.isBot)
	model:SetAttribute(A.DriverName, p.name)
	model:SetAttribute(A.Team, p.team)
	model:SetAttribute(A.CarId, p.def.Id)
	local chassis = model.PrimaryPart :: BasePart
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

-- Drains boost for anyone holding the boost button, and times out unused Mega Shots.
function CarService.tick(dt: number, live: boolean)
	local now = workspace:GetServerTimeNow()
	for _, p in Roster.all() do
		if live and p.boosting and p.boost > 0 then
			p.boost = math.max(0, p.boost - GameConfig.Car.BoostDrainPerSecond * dt)
		end
		if p.megaArmed and now > p.megaArmedUntil then
			p.megaArmed = false -- fizzled, but the meter stays full so it can be armed again
		end
		syncAttributes(p)
	end
end

function CarService.carsFolder(): Folder
	return carsFolder
end

return CarService
