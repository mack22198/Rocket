--!strict
-- Seasons: a reward track that changes every six weeks. Every match earns season XP (as much as the Scrap you
-- win), and each tier you reach pays out straight away - Scrap, matches of double Scrap, and a few style items you
-- can only get from that season. The free track is for everyone. The Gold Season Pass (see Shop) adds a second,
-- gold reward to every tier - with the season's gold-only items - and pays the gold rewards of the tiers you've
-- already reached the moment you get it. Nothing is random, and every reward is shown up front.
--
-- Seasons run back to back from `FirstDay`, taking their theme from `Themes` in turn (add a theme to give a
-- season new rewards). A reward you already own turns into Scrap.

local Cosmetics = require(script.Parent.Cosmetics)

local Season = {}

export type Reward = {
	Kind: string, -- "scrap", "boost" (matches of double Scrap) or "style" (a Cosmetics item)
	Amount: number, -- Scrap or matches (for "style": the Scrap you get instead if you already own it)
	Id: string?, -- the style item
}

export type Theme = {
	Id: string,
	Name: string,
	Emoji: string,
	Description: string,
	Color: Color3,
	Rewards: { Reward }, -- one for each tier, in order
	GoldRewards: { Reward }, -- the Gold Season Pass's reward for each tier
}

export type Info = {
	number: number, -- Season 1, 2, 3...
	theme: Theme,
	startDay: number, -- Daily.dayNumber of its first day
	endDay: number, -- the first day of the next season
}

-- A player's progress this season: which season it is, their XP, how many tiers have paid out, and whether they
-- have this season's Gold Pass.
export type State = { number: number, xp: number, tier: number, gold: boolean }

-- A tier that just paid out.
export type Reached = { tier: number, reward: Reward }

Season.FirstDay = 20724 -- Monday 28 September 2026 (see Daily.dayNumber)
Season.Days = 42 -- six weeks
Season.XpPerTier = 250
Season.BonusScrap = 100 -- every tier past the end of the track...
Season.GoldBonusScrap = 100 -- ...and as much again on the gold track

local function scrap(amount: number): Reward
	return { Kind = "scrap", Amount = amount }
end

local function boost(matches: number): Reward
	return { Kind = "boost", Amount = matches }
end

local function style(id: string, instead: number): Reward
	return { Kind = "style", Amount = instead, Id = id }
end

Season.Themes = {
	{
		Id = "foodfight",
		Name = "Food Fight",
		Emoji = "🍔",
		Description = "Pizza, tacos and hot dogs everywhere! Earn a Golden Crown by the end of the season.",
		Color = Color3.fromRGB(255, 150, 50),
		Rewards = {
			scrap(100),
			boost(2),
			scrap(150),
			scrap(150),
			style("fanfare", 300),
			scrap(200),
			boost(3),
			scrap(200),
			scrap(250),
			style("rainbow", 400),
			scrap(250),
			boost(3),
			scrap(300),
			scrap(300),
			scrap(350),
			boost(4),
			scrap(400),
			scrap(400),
			scrap(500),
			style("crown", 600),
		},
		GoldRewards = {
			scrap(200),
			boost(2),
			scrap(250),
			scrap(250),
			style("airhorn", 500),
			scrap(300),
			boost(3),
			scrap(300),
			scrap(350),
			scrap(350),
			scrap(400),
			style("goldrush", 700),
			scrap(400),
			boost(4),
			scrap(450),
			scrap(450),
			scrap(500),
			boost(5),
			scrap(600),
			style("trophy", 1000),
		},
	},
} :: { Theme }

local themesById: { [string]: Theme } = {}
for _, theme in Season.Themes do
	themesById[theme.Id] = theme
end

function Season.theme(id: string?): Theme?
	return if id then themesById[id] else nil
end

-- The season running on `day` (a Daily.dayNumber). Before the first season starts, that's Season 1.
function Season.at(day: number): Info
	local index = math.max(0, (day - Season.FirstDay) // Season.Days)
	local startDay = Season.FirstDay + index * Season.Days
	return {
		number = index + 1,
		theme = Season.Themes[index % #Season.Themes + 1],
		startDay = startDay,
		endDay = startDay + Season.Days,
	}
end

function Season.newState(): State
	return { number = 0, xp = 0, tier = 0, gold = false }
end

-- A new season starts everyone from zero (and a Gold Pass is for one season).
function Season.rollover(state: State, day: number)
	local number = Season.at(day).number
	if state.number ~= number then
		state.number = number
		state.xp = 0
		state.tier = 0
		state.gold = false
	end
end

-- The reward for a tier (past the end of the track, every tier is worth some bonus Scrap).
function Season.rewardFor(theme: Theme, tier: number): Reward
	return theme.Rewards[tier] or scrap(Season.BonusScrap)
end

-- The Gold Season Pass's reward for a tier.
function Season.goldRewardFor(theme: Theme, tier: number): Reward
	return theme.GoldRewards[tier] or scrap(Season.GoldBonusScrap)
end

-- How many tiers this much XP reaches.
function Season.tierFor(xp: number): number
	return xp // Season.XpPerTier
end

-- Adds a match's season XP. Returns the tiers that were just reached, in order, with their rewards.
function Season.addXp(state: State, amount: number, day: number): { Reached }
	Season.rollover(state, day)
	local theme = Season.at(day).theme
	state.xp += math.max(0, math.floor(amount))
	local reached: { Reached } = {}
	local target = Season.tierFor(state.xp)
	while state.tier < target do
		state.tier += 1
		table.insert(reached, { tier = state.tier, reward = Season.rewardFor(theme, state.tier) })
	end
	return reached
end

-- How a reward looks on screen: an emoji and a few words.
function Season.describe(reward: Reward): (string, string)
	if reward.Kind == "boost" then
		return "🚀", `Double Scrap x{reward.Amount}`
	elseif reward.Kind == "style" then
		local item = Cosmetics.get(reward.Id)
		if item then
			return item.Emoji, item.Name
		end
	end
	return "🔩", `{reward.Amount} Scrap`
end

-- Days left in the season running on `day` (1 on its last day).
function Season.daysLeft(day: number): number
	return math.max(1, Season.at(day).endDay - math.max(day, Season.FirstDay))
end

-- How far into the current tier a player is: (XP into it, XP it takes).
function Season.tierProgress(state: State): (number, number)
	return state.xp - state.tier * Season.XpPerTier, Season.XpPerTier
end

return Season
