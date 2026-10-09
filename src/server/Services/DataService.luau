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
local Achievements = require(Shared.Config.Achievements)
local CarCatalog = require(Shared.Config.CarCatalog)
local Cosmetics = require(Shared.Config.Cosmetics)
local Daily = require(Shared.Config.Daily)
local GameConfig = require(Shared.Config.GameConfig)
local Levels = require(Shared.Config.Levels)
local Remotes = require(Shared.Net.Remotes)
local Season = require(Shared.Config.Season)
local Signal = require(Shared.Util.Signal)

export type LifetimeStats = {
	matches: number,
	wins: number,
	goals: number,
	assists: number,
	saves: number,
	shots: number,
	megaShots: number,
	scrapEarned: number,
	demos: number,
	mvps: number,
	styleTouches: number,
	items: number,
	powers: number,
	bestStreak: number, -- most wins in a row
	friendMatches: number, -- matches played with a Roblox friend
}

-- The login streak, today's quests and the daily chest (see Daily).
type DailyData = Daily.State
type QuestState = Daily.QuestState

-- Hats, horns and goal celebrations: what you own and what you're using (see Cosmetics).
export type StyleData = {
	owned: { [string]: boolean },
	topper: string,
	horn: string,
	celebration: string,
}

export type SavedData = {
	version: number,
	scrap: number,
	owned: { [string]: boolean },
	equipped: string,
	stats: LifetimeStats,
	carXp: { [string]: number }, -- XP each car has earned (see Evolution)
	carStage: { [string]: number }, -- how far each car has evolved (1 = not yet)
	carLook: { [string]: number }, -- which unlocked stage each car shows off
	daily: DailyData,
	scrapBoost: number, -- matches left that pay double Scrap (a daily chest or season prize)
	style: StyleData,
	season: Season.State, -- this season's XP and the tiers that have paid out (see Season)
	xp: number, -- all the level XP ever earned (see Levels)
	levelPaid: number, -- the highest level whose reward has been paid
	winStreak: number, -- wins in a row right now
	achievements: { [string]: boolean }, -- the ones done (see Achievements)
	title: string, -- the title under your name ("" = the best one your level gives)
	vip: boolean, -- has the VIP Game Pass (checked again every time they join)
	purchases: { [string]: number }, -- Robux purchases already handed out: purchase id -> when (see Shop)
	settings: Settings,
}

-- Choices a player makes that the server needs to know about.
export type Settings = {
	assist: boolean, -- driving help (see DriveAssist)
}

type Profile = {
	data: SavedData,
	persistent: boolean, -- false = don't save (DataStores unavailable)
	dirty: boolean,
}

local DataService = {}

-- Fired once a player's data has loaded (before it's sent to them), so other services can bring it up to date.
DataService.Loaded = Signal.new() :: Signal.Signal<Player>

local DATA_VERSION = 8
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
		stats = {
			matches = 0,
			wins = 0,
			goals = 0,
			assists = 0,
			saves = 0,
			shots = 0,
			megaShots = 0,
			scrapEarned = 0,
			demos = 0,
			mvps = 0,
			styleTouches = 0,
			items = 0,
			powers = 0,
			bestStreak = 0,
			friendMatches = 0,
		},
		carXp = {},
		carStage = {},
		carLook = {},
		daily = Daily.newState(),
		scrapBoost = 0,
		style = {
			owned = Cosmetics.defaults(),
			topper = Cosmetics.defaultFor("topper"),
			horn = Cosmetics.defaultFor("horn"),
			celebration = Cosmetics.defaultFor("celebration"),
		},
		season = Season.newState(),
		xp = 0,
		levelPaid = 1,
		winStreak = 0,
		achievements = {},
		title = "",
		vip = false,
		purchases = {},
		settings = { assist = true },
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
	-- Evolution progress (added in version 2; older saves simply start from zero).
	local maxStage = GameConfig.Evolution.Stages
	for _, field in { "carXp", "carStage", "carLook" } do
		if type(raw[field]) ~= "table" then
			continue
		end
		for id, value in raw[field] do
			if CarCatalog.isValidId(id) then
				(data :: any)[field][id] = number(value, 0)
			end
		end
	end
	for id, stage in data.carStage do
		data.carStage[id] = math.clamp(stage, 1, maxStage)
	end
	for id, look in data.carLook do
		data.carLook[id] = math.clamp(look, 1, data.carStage[id] or 1)
	end
	-- Daily streak, quests and chest (added in version 3).
	local daily = raw.daily
	if type(daily) == "table" then
		data.daily.day = number(daily.day, 0)
		data.daily.streak = number(daily.streak, 0)
		data.daily.lastLoginDay = number(daily.lastLoginDay, 0)
		data.daily.streakClaimedDay = number(daily.streakClaimedDay, 0)
		data.daily.chestPicked = daily.chestPicked == true
		if type(daily.quests) == "table" then
			for _, quest in daily.quests do
				if #data.daily.quests >= Daily.QuestCount then
					break
				end
				if type(quest) == "table" and type(quest.id) == "string" and Daily.quest(quest.id) then
					table.insert(data.daily.quests, {
						id = quest.id,
						progress = number(quest.progress, 0),
						claimed = quest.claimed == true,
					})
				end
			end
		end
	end
	data.scrapBoost = math.min(number(raw.scrapBoost, 0), 10)
	-- Style (added in version 4).
	local style = raw.style
	if type(style) == "table" then
		if type(style.owned) == "table" then
			for id, owned in style.owned do
				if owned == true and type(id) == "string" and Cosmetics.get(id) then
					data.style.owned[id] = true
				end
			end
		end
		for _, kind in Cosmetics.Kinds do
			local chosen = style[kind]
			local def = if type(chosen) == "string" then Cosmetics.get(chosen) else nil
			if def and def.Kind == kind and data.style.owned[def.Id] then
				(data.style :: any)[kind] = def.Id
			end
		end
	end
	-- Season progress (added in version 5).
	local season = raw.season
	if type(season) == "table" then
		data.season.number = number(season.number, 0)
		data.season.xp = number(season.xp, 0)
		data.season.tier = math.min(number(season.tier, 0), Season.tierFor(data.season.xp))
		data.season.gold = season.gold == true
	end
	-- Levels, streaks, achievements and titles (added in version 6). Older saves start with as much level XP as
	-- all the Scrap they've ever won in matches, without paying out the levels they skip.
	if type(raw.xp) == "number" then
		data.xp = number(raw.xp, 0)
		data.levelPaid = math.max(1, number(raw.levelPaid, 1))
	else
		data.xp = data.stats.scrapEarned
		data.levelPaid = (Levels.levelFor(data.xp))
	end
	data.winStreak = number(raw.winStreak, 0)
	-- VIP and Robux purchases (added in version 7).
	data.vip = raw.vip == true
	if type(raw.purchases) == "table" then
		for id, time in raw.purchases do
			if type(id) == "string" and type(time) == "number" then
				data.purchases[id] = time
			end
		end
	end
	if type(raw.achievements) == "table" then
		for id, done in raw.achievements do
			if done == true and type(id) == "string" and Achievements.get(id) then
				data.achievements[id] = true
			end
		end
	end
	-- Settings (added in version 8).
	if type(raw.settings) == "table" then
		data.settings.assist = raw.settings.assist ~= false
	end
	local level = Levels.levelFor(data.xp)
	if type(raw.title) == "string" and Achievements.ownsTitle(raw.title, level, data.achievements, data.vip) then
		data.title = raw.title
	end
	return data
end

local function copyStyle(style: StyleData): StyleData
	local copy = table.clone(style)
	copy.owned = table.clone(style.owned)
	return copy
end

local function copyDaily(daily: DailyData): DailyData
	local quests: { QuestState } = {}
	for _, quest in daily.quests do
		table.insert(quests, table.clone(quest))
	end
	local copy = table.clone(daily)
	copy.quests = quests
	return copy
end

local function serialize(data: SavedData, withSession: boolean): { [string]: any }
	local copy: { [string]: any } = {
		version = DATA_VERSION,
		scrap = data.scrap,
		owned = table.clone(data.owned),
		equipped = data.equipped,
		stats = table.clone(data.stats),
		carXp = table.clone(data.carXp),
		carStage = table.clone(data.carStage),
		carLook = table.clone(data.carLook),
		daily = copyDaily(data.daily),
		scrapBoost = data.scrapBoost,
		style = copyStyle(data.style),
		season = table.clone(data.season),
		xp = data.xp,
		levelPaid = data.levelPaid,
		winStreak = data.winStreak,
		achievements = table.clone(data.achievements),
		title = data.title,
		vip = data.vip,
		purchases = table.clone(data.purchases),
		settings = table.clone(data.settings),
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
		carXp = table.clone(data.carXp),
		carStage = table.clone(data.carStage),
		carLook = table.clone(data.carLook),
		daily = copyDaily(data.daily),
		scrapBoost = data.scrapBoost,
		style = copyStyle(data.style),
		season = table.clone(data.season),
		xp = data.xp,
		winStreak = data.winStreak,
		achievements = table.clone(data.achievements),
		title = data.title,
		vip = data.vip,
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

local function saveToStore(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not profile.persistent or not store or not storeUsable then
		return false
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
	return ok
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
	DataService.Loaded:Fire(player)
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

-- Saves right away and waits for it. True once the save is safely stored.
function DataService.saveAndWait(player: Player): boolean
	return saveToStore(player, false)
end

-- Is this player's progress being saved? (Not in Studio without API access, or if loading it failed.)
function DataService.isPersistent(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.persistent
end

function DataService.clientView(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then clientView(profile.data) else nil
end

return DataService
