--!strict
-- The weekly leaderboard (see Leaderboard): every match adds the Scrap a player won to their score for the week in
-- an OrderedDataStore, and each server reads the top of it every couple of minutes for the menu to show. It needs
-- DataStores, so until the game is published (with API access on in Studio) it simply says so.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leaderboard = require(Shared.Config.Leaderboard)
local Remotes = require(Shared.Net.Remotes)

local LeaderboardService = {}

export type Entry = { rank: number, userId: number, name: string, score: number }

local available = true
local cached: { Entry } = {}
local cachedWeek = -1
local cachedAt = -math.huge
local refreshing = false
-- This week's score for each player in this server (read once, then kept up to date here).
local mine: { [Player]: { week: number, score: number } } = {}

local function now(): number
	return os.time()
end

local function store(week: number): OrderedDataStore?
	if not available then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Leaderboard.storeName(week))
	end)
	if not ok then
		available = false
		warn(`[Leaderboard] Not available: {result}`)
		return nil
	end
	return result
end

-- Display names for a list of user ids (falls back to "Player" if Roblox can't say).
local function namesFor(ids: { number }): { [number]: string }
	local names: { [number]: string } = {}
	if #ids == 0 then
		return names
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(ids)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				names[info.Id] = if type(info.DisplayName) == "string"
					then info.DisplayName
					else tostring(info.Username)
			end
		end
	end
	return names
end

local function refresh()
	if refreshing then
		return
	end
	refreshing = true
	local week = Leaderboard.week(now())
	local board = store(week)
	if board then
		local ok, pages = pcall(function()
			return (board :: OrderedDataStore):GetSortedAsync(false, Leaderboard.Size)
		end)
		if ok and pages then
			local list: { Entry } = {}
			local ids: { number } = {}
			for rank, item in (pages :: DataStorePages):GetCurrentPage() do
				local userId = tonumber(item.key)
				if userId then
					table.insert(list, { rank = rank, userId = userId, name = "Player", score = item.value })
					table.insert(ids, userId)
				end
			end
			local names = namesFor(ids)
			for _, entry in list do
				entry.name = names[entry.userId] or entry.name
			end
			cached = list
			cachedWeek = week
			cachedAt = os.clock()
		elseif not ok then
			warn(`[Leaderboard] Couldn't read the leaderboard: {pages}`)
			if string.find(string.lower(tostring(pages)), "studio", 1, true) then
				available = false
			end
		end
	end
	refreshing = false
end

-- Adds a match's Scrap to the player's score for this week.
function LeaderboardService.record(player: Player, amount: number)
	if amount <= 0 or not available then
		return
	end
	local week = Leaderboard.week(now())
	local known = mine[player]
	local before = if known and known.week == week then known.score else 0
	mine[player] = { week = week, score = before + amount }
	task.spawn(function()
		local board = store(week)
		if not board then
			return
		end
		local ok, result = pcall(function(): any
			local total = (board :: OrderedDataStore):IncrementAsync(tostring(player.UserId), math.floor(amount))
			return total
		end)
		if ok and type(result) == "number" then
			mine[player] = { week = week, score = result }
		elseif not ok then
			warn(`[Leaderboard] Couldn't add {player.Name}'s score: {result}`)
		end
	end)
end

local function myScore(player: Player): number
	local week = Leaderboard.week(now())
	local known = mine[player]
	if known and known.week == week then
		return known.score
	end
	local board = store(week)
	local score = 0
	if board then
		local ok, result = pcall(function(): any
			local saved = (board :: OrderedDataStore):GetAsync(tostring(player.UserId))
			return saved
		end)
		if ok and type(result) == "number" then
			score = result
		end
	end
	mine[player] = { week = week, score = score }
	return score
end

function LeaderboardService.init()
	Remotes.Leaderboard.OnServerInvoke = function(player: Player)
		local week = Leaderboard.week(now())
		if available and (week ~= cachedWeek or os.clock() - cachedAt > Leaderboard.RefreshSeconds) then
			refresh()
		end
		if not available then
			return { available = false }
		end
		return {
			available = true,
			top = if cachedWeek == week then cached else {},
			mine = myScore(player),
			secondsLeft = Leaderboard.secondsLeft(now()),
		}
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		mine[player] = nil
	end)
end

return LeaderboardService
