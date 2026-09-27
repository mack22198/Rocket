--!strict
-- The spinning "?" item boxes on the pitch. Drive through one to grab a random item (see Powers.Items); you
-- hold one item at a time. A team that's behind gets the better items more often, so matches stay close.
-- The server owns the boxes; every client spins and bobs them (see PowerVisuals).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)

local PropBuilder = require(script.Parent.Parent.Arena.PropBuilder)
local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)

type Participant = Roster.Participant

type Box = {
	position: Vector3,
	model: Model,
	active: boolean,
	respawnAt: number,
}

local ItemService = {}

local T = Powers.Tuning
local boxes: { Box } = {}
local respawn = T.BoxRespawn -- (the Mega Madness twist makes boxes come back sooner)
local rng = Random.new()
local stateObject = MatchState.getObject()

-- How see-through each part of a box is while it's there, and once it's been taken.
local SHOWN = { Box = 0.25, Core = 0.1, Spot = 0.55 }
local TAKEN = { Box = 1, Core = 1, Spot = 0.82 }

local function setActive(box: Box, active: boolean)
	box.active = active
	box.model:SetAttribute("Active", active)
	for _, d in box.model:GetDescendants() do
		if d:IsA("BasePart") then
			local transparency = if active then SHOWN[d.Name] else TAKEN[d.Name]
			if transparency then
				d.Transparency = transparency
			end
		elseif d:IsA("SurfaceGui") or d:IsA("PointLight") then
			(d :: any).Enabled = active
		end
	end
end

local function scores(): (number, number)
	local blue = stateObject:GetAttribute(MatchState.Attr.BlueScore)
	local orange = stateObject:GetAttribute(MatchState.Attr.OrangeScore)
	return if type(blue) == "number" then blue else 0, if type(orange) == "number" then orange else 0
end

-- Picks an item for `p`, with better odds the further behind their team is.
local function rollItem(p: Participant): string
	local blue, orange = scores()
	local ours, theirs = if p.team == "Blue" then blue else orange, if p.team == "Blue" then orange else blue
	return Powers.pickItem(Powers.standing(ours, theirs), rng:NextNumber())
end

local function tryPickup(box: Box, now: number)
	for _, p in Roster.all() do
		local chassis = p.chassis
		if p.item or not chassis or chassis.Anchored then
			continue
		end
		local offset = chassis.CFrame.Position - box.position
		if offset.Y < 9 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= T.BoxPickupRadius then
			p.item = rollItem(p)
			p.itemReadyAt = now + T.Roulette
			CarService.sync(p)
			box.respawnAt = now + respawn
			setActive(box, false)
			Remotes.PowerFx:FireAllClients("box", box.position + Vector3.new(0, T.BoxHeight, 0), p.team, p.car)
			return
		end
	end
end

function ItemService.init()
	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local folder = Instance.new("Folder")
	folder.Name = MatchState.Folders.ItemBoxes
	folder.Parent = matchFolder
	for i, position in T.BoxPositions do
		local box: Box =
			{ position = position, model = PropBuilder.itemBox(folder, position, i), active = true, respawnAt = 0 }
		table.insert(boxes, box)
	end
end

-- How long a box takes to come back after it's picked up.
function ItemService.setRespawn(seconds: number)
	respawn = seconds
end

-- Every box back for a kickoff.
function ItemService.resetAll()
	for _, box in boxes do
		setActive(box, true)
	end
end

-- Runs every frame while the ball is in play.
function ItemService.update()
	local now = workspace:GetServerTimeNow()
	for _, box in boxes do
		if not box.active then
			if now >= box.respawnAt then
				setActive(box, true)
			end
			continue
		end
		tryPickup(box, now)
	end
end

return ItemService
