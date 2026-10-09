--!strict
-- The charge orb: a glowing orb that turns up on the halfway line every so often (see GameConfig.Orb). Drive
-- through it and your ultimate meter fills a good chunk. There's only ever one, so the pitch stays clear, and
-- every time it appears it's a race. The server owns it; every client makes it float and glow (PowerVisuals).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local PropBuilder = require(script.Parent.Parent.Arena.PropBuilder)
local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)
local StatsService = require(script.Parent.StatsService)

local OrbService = {}

local O = GameConfig.Orb
local folder: Folder
local orb: Model? = nil
local orbPosition: Vector3? = nil -- the middle of the orb, while there is one
local expiresAt = 0
local nextAt = math.huge
local lastSpot = 0
local rng = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function remove()
	if orb then
		orb:Destroy()
	end
	orb = nil
	orbPosition = nil
end

local function appear(now: number)
	-- Somewhere new along the halfway line.
	local index = rng:NextInteger(1, #O.Spots)
	if index == lastSpot and #O.Spots > 1 then
		index = index % #O.Spots + 1
	end
	lastSpot = index
	local spot = O.Spots[index]
	local position = Vector3.new(spot.X, O.Height, spot.Z)
	orb = PropBuilder.chargeOrb(folder, position)
	orbPosition = position
	expiresAt = now + O.Lifetime
	Remotes.PowerFx:FireAllClients("orb", position, "", nil)
end

-- Where the orb is (nil when there isn't one), for the bots.
function OrbService.position(): Vector3?
	return orbPosition
end

-- A kickoff: any orb goes, and the next one comes a little while after the ball is in play.
function OrbService.reset()
	remove()
	nextAt = serverNow() + GameConfig.Match.CountdownLength + O.FirstDelay
end

-- The match is over.
function OrbService.clear()
	remove()
	nextAt = math.huge
end

-- Runs every frame while the ball is in play.
function OrbService.update()
	local now = serverNow()
	local position = orbPosition
	if not position then
		if now >= nextAt then
			appear(now)
		end
		return
	end
	for _, p in Roster.all() do
		local chassis = p.chassis
		if not chassis or chassis.Anchored then
			continue
		end
		local offset = chassis.CFrame.Position - position
		if math.abs(offset.Y) < 10 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= O.PickupRadius then
			p.stats.orbs += 1
			CarService.chargeUlt(p, GameConfig.Ultimate.Orb)
			Remotes.PowerFx:FireAllClients("orbtaken", position, p.team, p.car)
			StatsService.announce("orb", `{p.name} grabbed the charge orb!`, p.team, p.name)
			remove()
			nextAt = now + O.Every
			return
		end
	end
	if now >= expiresAt then
		Remotes.PowerFx:FireAllClients("orbgone", position, "", nil)
		remove()
		nextAt = now + O.Every / 2
	end
end

function OrbService.init()
	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local created = Instance.new("Folder")
	created.Name = MatchState.Folders.Orbs
	created.Parent = matchFolder
	folder = created
end

return OrbService
