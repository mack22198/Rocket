--!strict
-- Glowing pads on the floor that refill boost. Big pads fill the tank, small pads give a little.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)

type Pad = {
	position: Vector3,
	big: boolean,
	active: boolean,
	respawnAt: number,
	base: Part,
	orb: Part?,
}

local BoostPadService = {}

local pads: { Pad } = {}
local cfg = GameConfig.BoostPads

local ACTIVE_COLOR = Color3.fromRGB(255, 190, 40)
local USED_COLOR = Color3.fromRGB(90, 80, 60)

local function mirrored(points: { Vector3 }): { Vector3 }
	local list: { Vector3 } = {}
	local seen: { [string]: boolean } = {}
	for _, p in points do
		for _, sx in { 1, -1 } do
			for _, sz in { 1, -1 } do
				local q = Vector3.new(p.X * sx, 0, p.Z * sz)
				local key = `{q.X},{q.Z}`
				if not seen[key] then
					seen[key] = true
					table.insert(list, q)
				end
			end
		end
	end
	return list
end

local function setActive(pad: Pad, active: boolean)
	pad.active = active
	pad.base.Color = if active then ACTIVE_COLOR else USED_COLOR
	pad.base.Material = if active then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if pad.orb then
		pad.orb.Transparency = if active then 0.15 else 1
	end
end

local function build(folder: Instance, position: Vector3, big: boolean): Pad
	local radius = if big then cfg.BigRadius else cfg.SmallRadius
	local base = Instance.new("Part")
	base.Name = if big then "BigBoostPad" else "BoostPad"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.2, radius * 2, radius * 2)
	base.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Parent = folder
	local orb: Part? = nil
	if big then
		local ball = Instance.new("Part")
		ball.Name = "BoostOrb"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(2.5, 2.5, 2.5)
		ball.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		ball.Color = ACTIVE_COLOR
		ball.Material = Enum.Material.Neon
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = ACTIVE_COLOR
		light.Range = 14
		light.Parent = ball
		orb = ball
	end
	local pad: Pad = { position = position, big = big, active = true, respawnAt = 0, base = base, orb = orb }
	setActive(pad, true)
	return pad
end

function BoostPadService.init()
	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local folder = Instance.new("Folder")
	folder.Name = MatchState.Folders.BoostPads
	folder.Parent = matchFolder
	for _, position in mirrored(cfg.Big) do
		table.insert(pads, build(folder, position, true))
	end
	for _, position in mirrored(cfg.Small) do
		table.insert(pads, build(folder, position, false))
	end
end

function BoostPadService.resetAll()
	for _, pad in pads do
		setActive(pad, true)
	end
end

function BoostPadService.update()
	local now = workspace:GetServerTimeNow()
	for _, pad in pads do
		if not pad.active then
			if now >= pad.respawnAt then
				setActive(pad, true)
			end
			continue
		end
		local radius = if pad.big then cfg.BigRadius else cfg.SmallRadius
		for _, p in Roster.all() do
			local chassis = p.chassis
			if chassis and not chassis.Anchored and p.boost < 100 then
				local offset = chassis.Position - pad.position
				if offset.Y < 6 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius + 1.5 then
					CarService.addBoost(p, if pad.big then cfg.BigAmount else cfg.SmallAmount)
					pad.respawnAt = now + (if pad.big then cfg.BigRespawn else cfg.SmallRespawn)
					setActive(pad, false)
					break
				end
			end
		end
	end
end

return BoostPadService
