--!strict
-- Player levels, achievements and titles (see Levels and Achievements). At the end of each match a player gets as
-- much level XP as the Scrap they won (every level reached pays Scrap), and their achievements are checked; the
-- garage and the daily rewards check them too (owning 5 cars, a 7-day streak...). A finished achievement pays its
-- Scrap, may unlock a title, and awards its Roblox badge if one has been set up.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Levels = require(Shared.Config.Levels)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

type SavedData = DataService.SavedData

export type LevelUp = { level: number, scrap: number, title: string? }
export type Unlocked = { id: string, emoji: string, name: string, text: string, reward: number, title: string? }
export type MatchProgress = {
	level: number,
	into: number, -- XP into the level...
	need: number, -- ...out of this much
	gained: number,
	levelUps: { LevelUp },
	achievements: { Unlocked },
}

local ProgressService = {}

local function awardBadge(player: Player, badge: number?)
	if not badge or badge <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badge) then
				BadgeService:AwardBadge(player.UserId, badge)
			end
		end)
		if not ok then
			warn(`[Progress] Couldn't award badge {badge} to {player.Name}: {err}`)
		end
	end)
end

-- Everything the achievements look at (plus this match's numbers, if there are any).
local function viewOf(data: SavedData, match: Achievements.View?): Achievements.View
	local view = Achievements.viewOf(data.stats :: any, data.owned, data.carStage, data.daily.streak, data.xp)
	if match then
		for name, value in match do
			view[name] = value
		end
	end
	return view
end

-- Marks every achievement `data` has now finished as done and pays it out. (Call inside DataService.update.)
local function unlock(data: SavedData, match: Achievements.View?): { Achievements.AchievementDef }
	local finished = Achievements.newlyDone(data.achievements, viewOf(data, match))
	for _, def in finished do
		data.achievements[def.Id] = true
		data.scrap += def.Reward
	end
	return finished
end

local function describe(def: Achievements.AchievementDef): Unlocked
	return {
		id = def.Id,
		emoji = def.Emoji,
		name = def.Name,
		text = def.Text,
		reward = def.Reward,
		title = if def.Title then Achievements.titleText(def.Id) else nil,
	}
end

function ProgressService.level(data: SavedData): number
	return (Levels.levelFor(data.xp))
end

-- The title to show under the player's name.
function ProgressService.titleText(data: SavedData): string
	local id = if data.title ~= "" then data.title else Achievements.levelTitle(ProgressService.level(data))
	return Achievements.titleText(id)
end

-- The end of a match: `xp` level XP, and this match's numbers for the achievements (matchGoals, cleanSheetWin,
-- comebackWin). Returns what to show on the results screen.
function ProgressService.recordMatch(player: Player, xp: number, match: Achievements.View): MatchProgress?
	local result: MatchProgress? = nil
	local finished: { Achievements.AchievementDef } = {}
	DataService.update(player, function(data)
		local before = ProgressService.level(data)
		data.xp += math.max(0, math.floor(xp))
		local level, into, need = Levels.levelFor(data.xp)
		local levelUps: { LevelUp } = {}
		for reached = math.max(data.levelPaid, before) + 1, level do
			local scrap = Levels.reward(reached)
			data.scrap += scrap
			local title = Achievements.levelTitle(reached)
			local fresh = Achievements.title(title)
			table.insert(levelUps, {
				level = reached,
				scrap = scrap,
				title = if fresh and fresh.Level == reached then Achievements.titleText(title) else nil,
			})
		end
		data.levelPaid = math.max(data.levelPaid, level)
		finished = unlock(data, match)
		local unlocked: { Unlocked } = {}
		for _, def in finished do
			table.insert(unlocked, describe(def))
		end
		result = {
			level = level,
			into = into,
			need = need,
			gained = math.max(0, math.floor(xp)),
			levelUps = levelUps,
			achievements = unlocked,
		}
	end)
	for _, def in finished do
		awardBadge(player, def.Badge)
	end
	return result
end

-- Checks the achievements outside a match (after unlocking, fusing or evolving a car, or a daily streak) and tells
-- the player about any they've just finished.
function ProgressService.check(player: Player)
	local finished: { Achievements.AchievementDef } = {}
	DataService.update(player, function(data)
		finished = unlock(data, nil)
	end)
	for _, def in finished do
		awardBadge(player, def.Badge)
		Remotes.Progress:FireClient(player, "achievement", describe(def))
	end
end

function ProgressService.init()
	-- Choosing the title under your name ("" = the best one your level gives).
	Remotes.Profile.OnServerInvoke = function(player: Player, action: unknown, id: unknown)
		if action ~= "title" or type(id) ~= "string" then
			return { ok = false }
		end
		local data = DataService.get(player)
		if not data then
			return { ok = false }
		end
		if id ~= "" and not Achievements.ownsTitle(id, ProgressService.level(data), data.achievements) then
			return { ok = false, message = Achievements.howToUnlock(id) }
		end
		DataService.update(player, function(saved)
			saved.title = id
		end)
		return { ok = true }
	end

	-- Achievements finished while away (or added since) and the welcome badge.
	DataService.Loaded:Connect(function(player: Player)
		task.defer(ProgressService.check, player)
		awardBadge(player, Achievements.WelcomeBadge)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			task.defer(ProgressService.check, player)
		end
	end
end

return ProgressService
