--!strict
-- All RemoteEvents/RemoteFunctions in one place. The server creates them; clients wait for them.
--
-- Client -> Server
--   BallHit(id, time, carCFrame, carVelocity, ballPosition, ballVelocity)   "my car just touched the ball"
--   SetBoosting(isBoosting)                                                  boost button held / released
--   ActivateMega()                                                           arm a full Mega Shot
--   Garage(action, carId) -> result                                          unlock / equip cars
--   GetPlayerData() -> data                                                  initial profile snapshot
-- Server -> Client
--   BallState(time, position, velocity, flags, lastTouchTeam)  (unreliable, ~30/s)
--   BallHitResult(id, accepted, serverTime)                    answer to BallHit
--   Bumped(velocityChange)                                     your car got bumped
--   Announce(kind, text, team, extra)                          big text popups ("AIR HIT!", "SAVE!")
--   GoalScored(team, scorerName, assistName, position, comboText)
--   MatchResults(payload)                                      end of match summary + rewards
--   PlayerData(data)                                           Scrap / owned cars changed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(className: string, name: string): Instance
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	local remote = folder:WaitForChild(name, 30)
	assert(remote, `Remote {name} never appeared`)
	return remote
end

local function event(name: string): RemoteEvent
	return get("RemoteEvent", name) :: RemoteEvent
end

local function unreliable(name: string): UnreliableRemoteEvent
	return get("UnreliableRemoteEvent", name) :: UnreliableRemoteEvent
end

local function func(name: string): RemoteFunction
	return get("RemoteFunction", name) :: RemoteFunction
end

local Remotes = {
	BallHit = event("BallHit"),
	SetBoosting = event("SetBoosting"),
	ActivateMega = event("ActivateMega"),
	Garage = func("Garage"),
	GetPlayerData = func("GetPlayerData"),

	BallState = unreliable("BallState"),
	BallHitResult = event("BallHitResult"),
	Bumped = event("Bumped"),
	Announce = event("Announce"),
	GoalScored = event("GoalScored"),
	MatchResults = event("MatchResults"),
	PlayerData = event("PlayerData"),
}

-- Bit flags sent with BallState.
Remotes.BallFlags = {
	Snap = 1, -- teleport the ball (kickoff); don't blend
	Hidden = 2, -- ball exploded after a goal
	Frozen = 4, -- ball is paused (countdown)
}

return Remotes
