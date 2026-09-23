--!strict
-- The client's copy of this player's saved data (Scrap, owned cars, equipped car), kept fresh by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

export type Data = {
	scrap: number,
	owned: { [string]: boolean },
	equipped: string,
	stats: { [string]: number },
}

local PlayerDataClient = {}

PlayerDataClient.Changed = Signal.new() :: Signal.Signal<Data>

local current: Data = {
	scrap = 0,
	owned = { [CarCatalog.StarterId] = true },
	equipped = CarCatalog.StarterId,
	stats = {},
}
local loaded = false

local function apply(raw: any)
	if type(raw) ~= "table" then
		return
	end
	current = {
		scrap = if type(raw.scrap) == "number" then raw.scrap else 0,
		owned = if type(raw.owned) == "table" then raw.owned else { [CarCatalog.StarterId] = true },
		equipped = if type(raw.equipped) == "string" then raw.equipped else CarCatalog.StarterId,
		stats = if type(raw.stats) == "table" then raw.stats else {},
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

return PlayerDataClient
