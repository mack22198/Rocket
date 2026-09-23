--!strict
-- Saves each player's Scrap, cars and lifetime stats with DataStores.
--
-- A simple session lock stops two servers from overwriting each other's saves when a player hops servers quickly.
-- In Roblox Studio, DataStores only work after the place is published and "Enable Studio Access to API Services"
-- is turned on (Game Settings > Security). Without that, progress is kept in memory for the test session only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)

export type LifetimeStats = {
	matches: number,
	wins: number,
	goals: number,
	assists: number,
	saves: number,
	shots: number,
	megaShots: number,
	scrapEarned: number,
}

export type SavedData = {
	version: number,
	scrap: number,
	owned: { [string]: boolean },
	equipped: string,
	stats: LifetimeStats,
}

type Profile = {
	data: SavedData,
	persistent: boolean, -- false = don't save (DataStores unavailable)
	dirty: boolean,
}

local DataService = {}

local DATA_VERSION = 1
local LOAD_ATTEMPTS = 6
local LOAD_RETRY_DELAY = 3

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local store: DataStore? = nil
local storeUsable = true

local function defaultData(): SavedData
	return {
		version = DATA_VERSION,
		scrap = 0,
		owned = { [CarCatalog.StarterId] = true },
		equipped = CarCatalog.StarterId,
		stats = { matches = 0, wins = 0, goals = 0, assists = 0, saves = 0, shots = 0, megaShots = 0, scrapEarned = 0 },
	}
end

local function number(value: any, fallback: number): number
	if type(value) == "number" and value == value and value >= 0 and value < 1e12 then
		return math.floor(value)
	end
	return fallback
end

-- Turns whatever was saved (possibly old or damaged) into a valid SavedData.
local function sanitize(raw: any): SavedData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	data.scrap = number(raw.scrap, 0)
	if type(raw.owned) == "table" then
		for id, owned in raw.owned do
			if owned == true and CarCatalog.isValidId(id) then
				data.owned[id] = true
			end
		end
	end
	if CarCatalog.isValidId(raw.equipped) and data.owned[raw.equipped] then
		data.equipped = raw.equipped
	end
	if type(raw.stats) == "table" then
		for name, value in data.stats do
			(data.stats :: any)[name] = number(raw.stats[name], value :: number)
		end
	end
	return data
end

local function serialize(data: SavedData, withSession: boolean): { [string]: any }
	local copy: { [string]: any } = {
		version = DATA_VERSION,
		scrap = data.scrap,
		owned = table.clone(data.owned),
		equipped = data.equipped,
		stats = table.clone(data.stats),
	}
	if withSession then
		copy.session = { jobId = game.JobId, time = os.time() }
	end
	return copy
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function isStudioAccessError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studio", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "api services", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
end

local function markStoreUnusable(reason: string)
	if storeUsable then
		storeUsable = false
		warn(
			`[Data] DataStores are unavailable ({reason}). Progress will NOT be saved this session. `
				.. "Publish the place and enable Studio Access to API Services to test saving."
		)
	end
end

local function clientView(data: SavedData): { [string]: any }
	return {
		scrap = data.scrap,
		owned = table.clone(data.owned),
		equipped = data.equipped,
		stats = table.clone(data.stats),
	}
end

local function push(player: Player)
	local profile = profiles[player]
	if profile and player.Parent then
		Remotes.PlayerData:FireClient(player, clientView(profile.data))
	end
end

-- Returns (data, persistent). Tries to take the session lock; after several tries it takes it over anyway.
local function loadFromStore(player: Player): (SavedData, boolean)
	if not store or not storeUsable then
		return defaultData(), false
	end
	local key = keyFor(player)
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local loaded: SavedData? = nil
		local force = attempt == LOAD_ATTEMPTS
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old: any)
				lockedElsewhere = false
				if not force and type(old) == "table" and type(old.session) == "table" then
					local session = old.session
					local fresh = type(session.time) == "number"
						and os.time() - session.time < GameConfig.Data.SessionLockTimeout
					if session.jobId ~= game.JobId and fresh then
						lockedElsewhere = true
						return nil -- leave it alone; another server still has this player
					end
				end
				local data = sanitize(old)
				loaded = data
				return serialize(data, true)
			end)
		end)
		if ok and loaded then
			return loaded, true
		end
		if not ok then
			local message = tostring(err)
			if isStudioAccessError(message) then
				markStoreUnusable(message)
				return defaultData(), false
			end
			warn(`[Data] Load attempt {attempt} for {player.Name} failed: {message}`)
		end
		if not player.Parent then
			break
		end
		if lockedElsewhere or not ok then
			task.wait(LOAD_RETRY_DELAY)
		end
	end
	warn(`[Data] Could not load {player.Name}'s data. Their progress will not be saved this session.`)
	return defaultData(), false
end

local function saveToStore(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.persistent or not store or not storeUsable then
		return
	end
	local snapshot = serialize(profile.data, not release)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old: any)
			if type(old) == "table" and type(old.session) == "table" and old.session.jobId ~= game.JobId then
				return nil -- another server took over this player; never overwrite its newer data
			end
			return snapshot
		end)
	end)
	if ok then
		profile.dirty = false
	else
		warn(`[Data] Saving {player.Name} failed: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	local data, persistent = loadFromStore(player)
	loading[player] = nil
	if not player.Parent then
		return
	end
	if not persistent and RunService:IsStudio() and data.scrap == 0 then
		data.scrap = GameConfig.Debug.StudioStartingScrap
	end
	profiles[player] = { data = data, persistent = persistent, dirty = false }
	push(player)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		saveToStore(player, true)
		profiles[player] = nil
	end
end

function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok then
		store = result
	else
		markStoreUnusable(tostring(result))
	end

	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	game:BindToClose(function()
		if not store or not storeUsable then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveToStore(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player, profile in profiles do
				if profile.persistent then
					task.spawn(saveToStore, player, false)
				end
			end
		end
	end)
end

-- The player's data, or nil while it's still loading.
function DataService.get(player: Player): SavedData?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

-- Waits (up to `timeout` seconds) for the player's data to finish loading.
function DataService.waitFor(player: Player, timeout: number): SavedData?
	local deadline = os.clock() + timeout
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Changes a player's data. Saves soon after and tells their client.
function DataService.update(player: Player, change: (SavedData) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	change(profile.data)
	profile.dirty = true
	push(player)
end

-- Save right away (used after spending Scrap so a crash can't undo a purchase).
function DataService.saveNow(player: Player)
	task.spawn(saveToStore, player, false)
end

function DataService.clientView(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then clientView(profile.data) else nil
end

return DataService
