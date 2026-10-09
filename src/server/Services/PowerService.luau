--!strict
-- Ultimates (every car has its own; a fused car's does two at once) and everything they leave lying around:
-- cheese, banana peels and ketchup. What each one does is described in Powers; how the meter fills is in
-- CarService and GameConfig.Ultimate.
--
-- The server decides everything, then tells the cars: a player's own client drives their car, so spin-outs and
-- slow-downs are sent to it (CarService.applyEffect), and it launches itself straight away when its player sets
-- off a Nitro Rocket or Shark Dive so that feels instant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)

local PropBuilder = require(script.Parent.Parent.Arena.PropBuilder)
local Roster = require(script.Parent.Parent.Match.Roster)
local BallService = require(script.Parent.BallService)
local CarService = require(script.Parent.CarService)
local StatsService = require(script.Parent.StatsService)

type Participant = Roster.Participant
type Team = Roster.Team

type Hazard = {
	kind: string, -- "cheese", "peel" or "ketchup"
	ownerKey: string,
	ownerName: string,
	team: Team,
	position: Vector3,
	normal: Vector3,
	forward: Vector3, -- the way a ketchup slick runs along the surface
	expiresAt: number,
	model: Model,
	hit: { [string]: number }, -- participant key -> when this hazard last got them
}

local PowerService = {}

local T = Powers.Tuning
local MAX_HAZARDS_EACH = 4
local SLOW_RESEND = 0.25 -- while a car sits in cheese, its slow-down is topped up this often

local stateObject = MatchState.getObject()
local rng = Random.new()
local hazardsFolder: Folder
local rayParams = RaycastParams.new()
local hazards: { Hazard } = {}
local slowedAt: { [Participant]: number } = {}
local KETCHUP_REHIT = 1.4 -- a car stays in a ketchup slick a while; it spins again only after this long

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- The car, if it can set off its ultimate right now (not during kickoffs).
local function readyChassis(p: Participant): BasePart?
	local chassis = p.chassis
	if not chassis or chassis.Anchored then
		return nil
	end
	if MatchState.phase(stateObject) ~= MatchState.Phases.Playing then
		return nil
	end
	return chassis
end

local function setEffect(p: Participant, name: string, duration: number, now: number)
	p.effects[name] = math.max(p.effects[name] or 0, now + duration)
end

-- Diving sharks shrug off the other team's ultimates.
local function protected(p: Participant, now: number): boolean
	return Roster.hasEffect(p, "ghost", now)
end

local function fx(kind: string, position: Vector3, team: Team, extra: any?)
	Remotes.PowerFx:FireAllClients(kind, position, team, extra)
end

-- Bots are pushed here; a player's own client already launched their car when they pressed the button.
local function launch(p: Participant, kind: string, chassis: BasePart)
	local change = Powers.launch(kind, chassis.CFrame)
	if change and p.driver then
		p.driver:addVelocity(change)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Cheese puddles and banana peels
---------------------------------------------------------------------------------------------------------------

local function removeHazard(index: number)
	local hazard = table.remove(hazards, index)
	if hazard then
		hazard.model:Destroy()
	end
end

local function clearHazards()
	for i = #hazards, 1, -1 do
		removeHazard(i)
	end
	table.clear(slowedAt)
end

-- Where something dropped behind `chassis` lands (`back` studs behind it, `side` studs to the right): on
-- whatever surface is under there.
local function dropSpot(chassis: BasePart, back: number, side: number): (Vector3?, Vector3?)
	local cframe = chassis.CFrame
	local origin = cframe:PointToWorldSpace(Vector3.new(side, 0, back))
	local hit = workspace:Raycast(origin, -cframe.UpVector * 12, rayParams)
		or workspace:Raycast(origin, Vector3.new(0, -80, 0), rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

local function dropHazard(p: Participant, kind: string, chassis: BasePart, duration: number, now: number, side: number?)
	-- A ketchup slick starts just behind the car and runs back from there.
	local back = if kind == "ketchup" then T.HazardDrop + T.KetchupLength / 2 - 3 else T.HazardDrop
	local position, normal = dropSpot(chassis, back, side or 0)
	if not position or not normal then
		return
	end
	-- Each car can only have a few lying around; the oldest one goes.
	local count = 0
	for _, hazard in hazards do
		if hazard.ownerKey == p.key then
			count += 1
		end
	end
	if count >= MAX_HAZARDS_EACH then
		for i, hazard in hazards do
			if hazard.ownerKey == p.key then
				removeHazard(i)
				break
			end
		end
	end
	-- Lie flat on the surface, lined up with the car (any direction along the surface will do if that fails).
	local right = normal:Cross(chassis.CFrame.LookVector)
	if right.Magnitude < 1e-3 then
		right = normal:Cross(if math.abs(normal.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis)
	end
	local surface = CFrame.fromMatrix(position, right.Unit, normal)
	local forward = surface.ZVector
	local model = PropBuilder.hazard(kind, surface, GameConfig.Teams[p.team].Color)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Team", p.team)
	model.Parent = hazardsFolder
	table.insert(hazards, {
		kind = kind,
		ownerKey = p.key,
		ownerName = p.name,
		team = p.team,
		position = position,
		normal = normal,
		forward = forward,
		expiresAt = now + duration,
		model = model,
		hit = {},
	})
	fx(kind, position, p.team)
end

---------------------------------------------------------------------------------------------------------------
-- Ultimates
---------------------------------------------------------------------------------------------------------------

local function groundPound(p: Participant, chassis: BasePart, now: number)
	local centre = chassis.CFrame.Position
	local hits = 0
	for _, other in Roster.all() do
		local otherChassis = other.chassis
		if other.team == p.team or not otherChassis or otherChassis.Anchored or protected(other, now) then
			continue
		end
		local push = Powers.poundPush(centre, otherChassis.CFrame.Position, T.PoundRadius, T.PoundKnockback, T.PoundPop)
		if push then
			CarService.push(other, push / math.max(other.def.Stats.Weight, 0.5))
			hits += 1
		end
	end
	local ball = BallService.getState()
	local shove = Powers.poundPush(centre, ball.position, T.PoundBallRadius, T.PoundBallSpeed, T.PoundBallSpeed * 0.35)
	if shove then
		BallService.nudge(p, shove)
	end
	if hits > 0 then
		local cars = if hits == 1 then "a car" else `{hits} cars`
		StatsService.announce("power", `{p.name} pounded {cars}!`, p.team, p.name)
	end
end

-- Quack Attack: every car on the other team close enough spins out.
local function quack(p: Participant, chassis: BasePart, now: number)
	local centre = chassis.CFrame.Position
	local hits = 0
	for _, other in Roster.all() do
		local otherChassis = other.chassis
		if other.team == p.team or not otherChassis or otherChassis.Anchored or protected(other, now) then
			continue
		end
		if (otherChassis.CFrame.Position - centre).Magnitude <= T.QuackRadius then
			CarService.applyEffect(other, "spin", T.QuackSpin, if rng:NextNumber() < 0.5 then -1 else 1)
			fx("slip", otherChassis.CFrame.Position, p.team, other.car)
			hits += 1
		end
	end
	if hits > 0 then
		local cars = if hits == 1 then "a car" else `{hits} cars`
		StatsService.announce("power", `{p.name} quacked {cars} into a spin!`, p.team, p.name)
	end
end

-- Does one ultimate (a fused car's combo does two of these at once).
local function doPower(p: Participant, power: Powers.PowerDef, chassis: BasePart, now: number)
	local id = power.Id
	if id == "cheese" or id == "ketchup" then
		dropHazard(p, id, chassis, power.Duration, now)
		return -- (the drop shows its own effect)
	elseif id == "peel" then
		for _, side in Powers.peelOffsets() do
			dropHazard(p, id, chassis, power.Duration, now, side)
		end
		return
	elseif id == "hotsauce" then
		setEffect(p, "hotsauce", power.Duration, now)
	elseif id == "quack" then
		quack(p, chassis, now)
	elseif id == "nitro" then
		launch(p, "nitro", chassis)
		setEffect(p, "dash", power.Duration, now)
	elseif id == "dive" then
		launch(p, "dive", chassis)
		setEffect(p, "ghost", power.Duration, now)
		setEffect(p, "dash", power.Duration, now)
	elseif id == "pound" then
		groundPound(p, chassis, now)
	elseif id == "beam" then
		setEffect(p, "beam", power.Duration, now)
	end
	fx(id, chassis.CFrame.Position, p.team, p.car)
end

-- Sets off `p`'s ultimate, if its meter is full.
function PowerService.useUltimate(p: Participant)
	local now = serverNow()
	local chassis = readyChassis(p)
	if not chassis or not CarService.spendUlt(p) then
		return
	end
	local power = Powers.forCar(p.def.Id)
	p.stats.powers += 1
	StatsService.announce("ult", string.upper(power.Name), p.team, p.name)
	fx("ult", chassis.CFrame.Position, p.team, p.car)
	for _, part in Powers.components(power) do
		doPower(p, part, chassis, now)
	end
	CarService.sync(p)
end

---------------------------------------------------------------------------------------------------------------
-- Bots
---------------------------------------------------------------------------------------------------------------

-- A bot thinking about its ultimate (a dozen times a second; it reacts after a short moment).
function PowerService.botThink(p: Participant, view: Powers.BotView)
	if p.ult >= GameConfig.Ultimate.Max and rng:NextNumber() < 0.3 then
		if Powers.botWantsPower(Powers.forCar(p.def.Id).Id, view) then
			PowerService.useUltimate(p)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------------------------------------------

-- Runs every frame while the ball is in play: cheese slows, peels trip, and old ones melt away.
function PowerService.update()
	local now = serverNow()
	for i = #hazards, 1, -1 do
		local hazard = hazards[i]
		if now >= hazard.expiresAt then
			removeHazard(i)
			continue
		end
		for _, p in Roster.all() do
			local chassis = p.chassis
			if p.team == hazard.team or not chassis or chassis.Anchored or protected(p, now) then
				continue
			end
			local position = chassis.CFrame.Position
			if not Powers.inHazard(hazard.kind, hazard.position, hazard.normal, position, hazard.forward) then
				continue
			end
			if hazard.kind == "cheese" then
				if now - (slowedAt[p] or -math.huge) >= SLOW_RESEND then
					slowedAt[p] = now
					CarService.applyEffect(p, "slow", T.CheeseSlowTime)
				end
			elseif hazard.kind == "ketchup" then
				-- A slick stays down and can catch several cars (each one only every so often).
				local last = hazard.hit[p.key]
				if not last or now - last >= KETCHUP_REHIT then
					hazard.hit[p.key] = now
					CarService.applyEffect(p, "spin", T.KetchupSpin, if rng:NextNumber() < 0.5 then -1 else 1)
					fx("slip", position, hazard.team, p.car)
					if not last then
						StatsService.announce("power", `{p.name} skidded on ketchup!`, hazard.team, hazard.ownerName)
					end
				end
			else
				CarService.applyEffect(p, "spin", T.SpinTime, if rng:NextNumber() < 0.5 then -1 else 1)
				fx("slip", chassis.CFrame.Position, hazard.team, p.car)
				StatsService.announce("power", `{p.name} slipped on a banana!`, hazard.team, hazard.ownerName)
				removeHazard(i)
				break
			end
		end
	end
end

-- A fresh start for a kickoff: effects wear off and traps are swept away. (Ultimate meters keep their charge.)
function PowerService.resetForKickoff()
	clearHazards()
	for _, p in Roster.all() do
		table.clear(p.effects)
		CarService.sync(p)
	end
end

-- The match is over.
function PowerService.clear()
	clearHazards()
end

function PowerService.init(arena: Instance)
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { arena }
	rayParams.IgnoreWater = true

	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local folder = Instance.new("Folder")
	folder.Name = MatchState.Folders.Hazards
	folder.Parent = matchFolder
	hazardsFolder = folder

	Remotes.UseUltimate.OnServerEvent:Connect(function(player: Player)
		local p = Roster.byPlayer(player)
		if p then
			PowerService.useUltimate(p)
		end
	end)
end

return PowerService
