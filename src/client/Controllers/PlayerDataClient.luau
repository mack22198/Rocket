--!strict
-- The client's copy of this player's saved data (Scrap, cars, evolutions, daily quests, style, the season,
-- level, win streak, achievements and title), kept fresh by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Cosmetics = require(Shared.Config.Cosmetics)
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Net.Remotes)
local Season = require(Shared.Config.Season)
local Signal = require(Shared.Util.Signal)

export type Data = {
	scrap: number,
	owned: { [string]: boolean },
	equipped: string,
	stats: { [string]: number },
	carXp: { [string]: number },
	carStage: { [string]: number },
	carLook: { [string]: number },
	daily: Daily.State,
	scrapBoost: number,
	style: Style,
	season: Season.State,
	xp: number, -- level XP (see Levels)
	winStreak: number,
	achievements: { [string]: boolean },
	title: string, -- "" = the best title the level gives
	vip: boolean,
}

-- Hats, horns and goal celebrations (see Cosmetics).
export type Style = {
	owned: { [string]: boolean },
	topper: string,
	horn: string,
	celebration: string,
}

local PlayerDataClient = {}

PlayerDataClient.Changed = Signal.new() :: Signal.Signal<Data>

local current: Data = {
	scrap = 0,
	owned = { [CarCatalog.StarterId] = true },
	equipped = CarCatalog.StarterId,
	stats = {},
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
	winStreak = 0,
	achievements = {},
	title = "",
	vip = false,
}
local loaded = false

local function readStyle(raw: any): Style
	local style: Style = {
		owned = Cosmetics.defaults(),
		topper = Cosmetics.defaultFor("topper"),
		horn = Cosmetics.defaultFor("horn"),
		celebration = Cosmetics.defaultFor("celebration"),
	}
	if type(raw) ~= "table" then
		return style
	end
	if type(raw.owned) == "table" then
		for id, owned in raw.owned do
			if owned == true and type(id) == "string" and Cosmetics.get(id) then
				style.owned[id] = true
			end
		end
	end
	for _, kind in Cosmetics.Kinds do
		local chosen = raw[kind]
		if type(chosen) == "string" and Cosmetics.get(chosen) then
			(style :: any)[kind] = chosen
		end
	end
	return style
end

-- The daily progress from the server (checked, since it came over the network).
local function readDaily(raw: any): Daily.State
	local state = Daily.newState()
	if type(raw) ~= "table" then
		return state
	end
	for _, key in { "day", "streak", "lastLoginDay", "streakClaimedDay" } do
		local value = raw[key]
		if type(value) == "number" then
			(state :: any)[key] = value
		end
	end
	state.chestPicked = raw.chestPicked == true
	if type(raw.quests) == "table" then
		for _, quest in raw.quests do
			if type(quest) == "table" and type(quest.id) == "string" and Daily.quest(quest.id) then
				table.insert(state.quests, {
					id = quest.id,
					progress = if type(quest.progress) == "number" then quest.progress else 0,
					claimed = quest.claimed == true,
				})
			end
		end
	end
	return state
end

local function readSeason(raw: any): Season.State
	local state = Season.newState()
	if type(raw) == "table" then
		for _, key in { "number", "xp", "tier" } do
			if type(raw[key]) == "number" then
				(state :: any)[key] = raw[key]
			end
		end
		state.gold = raw.gold == true
	end
	return state
end

local function apply(raw: any)
	if type(raw) ~= "table" then
		return
	end
	current = {
		scrap = if type(raw.scrap) == "number" then raw.scrap else 0,
		owned = if type(raw.owned) == "table" then raw.owned else { [CarCatalog.StarterId] = true },
		equipped = if type(raw.equipped) == "string" then raw.equipped else CarCatalog.StarterId,
		stats = if type(raw.stats) == "table" then raw.stats else {},
		carXp = if type(raw.carXp) == "table" then raw.carXp else {},
		carStage = if type(raw.carStage) == "table" then raw.carStage else {},
		carLook = if type(raw.carLook) == "table" then raw.carLook else {},
		daily = readDaily(raw.daily),
		scrapBoost = if type(raw.scrapBoost) == "number" then raw.scrapBoost else 0,
		style = readStyle(raw.style),
		season = readSeason(raw.season),
		xp = if type(raw.xp) == "number" then raw.xp else 0,
		winStreak = if type(raw.winStreak) == "number" then raw.winStreak else 0,
		achievements = if type(raw.achievements) == "table" then raw.achievements else {},
		title = if type(raw.title) == "string" then raw.title else "",
		vip = raw.vip == true,
	}
	loaded = true
	PlayerDataClient.Changed:Fire(current)
end

function PlayerDataClient.start()
	Remotes.PlayerData.OnClientEvent:Connect(apply)
	task.spawn(function()
		-- The push from the server may have happened before we connected; ask once to be sure.
		local ok, result = pcall(function()
			return Remotes.GetPlayerData:InvokeServer()
		end)
		if ok and result and not loaded then
			apply(result)
		end
	end)
end

function PlayerDataClient.get(): Data
	return current
end

function PlayerDataClient.isLoaded(): boolean
	return loaded
end

-- Today's day number (see Daily), by the server's clock.
function PlayerDataClient.today(): number
	return Daily.dayNumber(math.floor(workspace:GetServerTimeNow()))
end

return PlayerDataClient
