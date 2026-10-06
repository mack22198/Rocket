--!strict
-- The server side of daily rewards (see Daily): keeps each player's streak and quests up to date, counts
-- finished matches toward the quests, and hands out rewards when they're claimed (streak Scrap, quest Scrap
-- and the daily chest prize the player picked).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)
local ProgressService = require(script.Parent.ProgressService)

local DailyService = {}

type Result = { ok: boolean, message: string }

local lastRequest: { [Player]: number } = {}

local function today(): number
	return Daily.dayNumber(os.time())
end

-- Brings the player's daily progress up to today (new quests, streak).
function DailyService.refresh(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local day = today()
	if data.daily.day ~= day or data.daily.lastLoginDay ~= day then
		DataService.update(player, function(d)
			Daily.rollover(d.daily, player.UserId, day)
		end)
	end
end

-- Counts a finished match toward today's quests. Returns what the quests that just got finished asked for.
function DailyService.recordMatch(player: Player, stats: { [string]: any }, outcome: string): { string }
	DailyService.refresh(player)
	local finished: { string } = {}
	DataService.update(player, function(d)
		for _, quest in Daily.record(d.daily, stats, outcome) do
			local def = Daily.quest(quest.id)
			if def then
				table.insert(finished, `{def.Emoji} {Daily.describe(def)}`)
			end
		end
	end)
	return finished
end

local function validIndex(value: unknown, count: number): number?
	if type(value) == "number" and value == math.floor(value) and value >= 1 and value <= count then
		return value
	end
	return nil
end

local function handle(player: Player, action: unknown, index: unknown): Result
	local clock = os.clock()
	if clock - (lastRequest[player] or 0) < 0.3 then
		return { ok = false, message = "Slow down!" }
	end
	lastRequest[player] = clock
	DailyService.refresh(player)
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Still loading..." }
	end
	local day = today()
	local daily = data.daily

	if action == "streak" then
		if not Daily.canClaimStreak(daily, day) then
			return { ok = false, message = "You've got today's streak reward. Come back tomorrow!" }
		end
		local streak = daily.streak
		local amount = Daily.streakReward(streak)
		DataService.update(player, function(d)
			d.scrap += amount
			d.stats.scrapEarned += amount
			d.daily.streakClaimedDay = day
		end)
		DataService.saveNow(player)
		return { ok = true, message = `🔥 Day {streak} streak! +{amount} Scrap` }
	elseif action == "quest" then
		local i = validIndex(index, #daily.quests)
		local quest = if i then daily.quests[i] else nil
		local def = if quest then Daily.quest(quest.id) else nil
		if not i or not quest or not def then
			return { ok = false, message = "Unknown quest." }
		elseif quest.claimed then
			return { ok = false, message = "You already collected that one." }
		elseif not Daily.isDone(quest) then
			return { ok = false, message = "Not finished yet - keep playing!" }
		end
		DataService.update(player, function(d)
			d.scrap += def.Reward
			d.stats.scrapEarned += def.Reward
			d.daily.quests[i].claimed = true
		end)
		DataService.saveNow(player)
		return { ok = true, message = `✅ Quest done! +{def.Reward} Scrap` }
	elseif action == "chest" then
		local options = Daily.chestOptions(player.UserId, day)
		local i = validIndex(index, #options)
		if not Daily.allDone(daily) then
			return { ok = false, message = "Finish all 3 quests to open the chest!" }
		elseif daily.chestPicked then
			return { ok = false, message = "You opened today's chest. A new one comes tomorrow!" }
		elseif not i then
			return { ok = false, message = "Pick one of the three prizes." }
		end
		local option = options[i]
		local carName = ""
		DataService.update(player, function(d)
			d.daily.chestPicked = true
			if option.Kind == "scrap" then
				d.scrap += option.Amount
				d.stats.scrapEarned += option.Amount
			elseif option.Kind == "xp" then
				d.carXp[d.equipped] = (d.carXp[d.equipped] or 0) + option.Amount
				local def = CarCatalog.get(d.equipped)
				carName = if def then def.DisplayName else ""
			elseif option.Kind == "boost" then
				d.scrapBoost = math.min(d.scrapBoost + option.Amount, 10)
			end
		end)
		DataService.saveNow(player)
		local message = if option.Kind == "xp"
			then `✨ +{option.Amount} XP for your {carName}!`
			elseif option.Kind == "boost" then `🚀 Double Scrap for your next {option.Amount} matches!`
			else `🔩 +{option.Amount} Scrap!`
		return { ok = true, message = message }
	end
	return { ok = false, message = "Unknown action." }
end

function DailyService.init()
	DataService.Loaded:Connect(DailyService.refresh)
	Remotes.Daily.OnServerInvoke = function(player: Player, action: unknown, index: unknown)
		local result = handle(player, action, index)
		if result.ok then
			task.defer(ProgressService.check, player) -- e.g. "Play 7 days in a row"
		end
		return result
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
	-- A new day can start while people are playing.
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				DailyService.refresh(player)
			end
		end
	end)
end

return DailyService
