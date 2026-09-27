--!strict
-- The client's copy of this player's saved data (Scrap, cars, evolutions, daily quests), kept fresh by the
-- server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Net.Remotes)
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
}
local loaded = false

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
