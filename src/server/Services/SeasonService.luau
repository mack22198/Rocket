--!strict
-- The server side of seasons (see Season): every match adds season XP, and each tier's reward is paid out the
-- moment it's reached - nothing to claim. With this season's Gold Pass (see ShopService), each tier pays its gold
-- reward too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Daily = require(Shared.Config.Daily)
local Season = require(Shared.Config.Season)

local DataService = require(script.Parent.DataService)

local SeasonService = {}

-- What the results screen shows about the season after a match.
export type Summary = {
	number: number,
	name: string,
	emoji: string,
	tier: number,
	xp: number, -- into the current tier
	need: number, -- XP the tier takes
	gained: number,
	rewards: { string }, -- the tiers reached this match ("⭐ Tier 5: 🎺 Champion Fanfare!")
	nextReward: string,
}

local MAX_BOOST = 10

local function today(): number
	return Daily.dayNumber(os.time())
end

-- Hands a reward over (a style item you already have is paid in Scrap instead). Returns what it was.
local function grant(data: DataService.SavedData, reward: Season.Reward): string
	local emoji, text = Season.describe(reward)
	if reward.Kind == "boost" then
		data.scrapBoost = math.min(data.scrapBoost + reward.Amount, MAX_BOOST)
		return `{emoji} {text}`
	end
	local item = if reward.Kind == "style" then Cosmetics.get(reward.Id) else nil
	if item and not data.style.owned[item.Id] then
		data.style.owned[item.Id] = true
		return `{emoji} {text}!`
	end
	data.scrap += reward.Amount
	data.stats.scrapEarned += reward.Amount
	return `🔩 +{reward.Amount} Scrap`
end

-- A new season starts everyone from zero.
function SeasonService.refresh(player: Player)
	local data = DataService.get(player)
	if data and data.season.number ~= Season.at(today()).number then
		DataService.update(player, function(d)
			Season.rollover(d.season, today())
		end)
	end
end

-- Adds a match's season XP, pays out any tiers reached, and says how the season is going.
function SeasonService.recordMatch(player: Player, xp: number): Summary?
	local day = today()
	local info = Season.at(day)
	local summary: Summary? = nil
	DataService.update(player, function(data)
		local rewards: { string } = {}
		for _, reached in Season.addXp(data.season, xp, day) do
			table.insert(rewards, `⭐ Tier {reached.tier}: {grant(data, reached.reward)}`)
			if data.season.gold then
				local gold = Season.goldRewardFor(info.theme, reached.tier)
				table.insert(rewards, `🏆 Gold Tier {reached.tier}: {grant(data, gold)}`)
			end
		end
		local into, need = Season.tierProgress(data.season)
		local nextEmoji, nextText = Season.describe(Season.rewardFor(info.theme, data.season.tier + 1))
		summary = {
			number = info.number,
			name = info.theme.Name,
			emoji = info.theme.Emoji,
			tier = data.season.tier,
			xp = into,
			need = need,
			gained = math.max(0, math.floor(xp)),
			rewards = rewards,
			nextReward = `{nextEmoji} {nextText}`,
		}
	end)
	if summary and #summary.rewards > 0 then
		DataService.saveNow(player)
	end
	return summary
end

-- Gives `data` this season's Gold Pass and pays the gold rewards of every tier already reached. Returns what was
-- paid, or nil if they already had it. (Call inside DataService.update.)
function SeasonService.unlockGold(data: DataService.SavedData): { string }?
	local day = today()
	Season.rollover(data.season, day)
	if data.season.gold then
		return nil
	end
	data.season.gold = true
	local theme = Season.at(day).theme
	local paid: { string } = {}
	for tier = 1, data.season.tier do
		table.insert(paid, `🏆 Gold Tier {tier}: {grant(data, Season.goldRewardFor(theme, tier))}`)
	end
	return paid
end

function SeasonService.init()
	DataService.Loaded:Connect(SeasonService.refresh)
	-- A new season can start while people are playing.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				SeasonService.refresh(player)
			end
		end
	end)
end

return SeasonService
