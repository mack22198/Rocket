--!strict
-- Scrap rewards. There is one currency on purpose: Scrap buys cars directly, no loot boxes.
-- Everyone who finishes a match earns something, and style is rewarded along with winning.

local CarCatalog = require(script.Parent.CarCatalog)

export type MatchStats = {
	goals: number,
	assists: number,
	saves: number,
	shots: number,
	touches: number,
	styleTouches: number,
	megaShots: number,
	points: number,
	orbs: number, -- charge orbs grabbed
	powers: number, -- ultimates used
	demos: number, -- cars demolished
}

export type Outcome = "Win" | "Loss" | "Draw"

export type RewardLine = { label: string, amount: number }

export type RewardSummary = { lines: { RewardLine }, total: number }

export type NextGoal = {
	carId: string,
	displayName: string,
	emoji: string,
	price: number,
	have: number,
	remaining: number,
	canAfford: boolean,
}

local Rewards = {}

-- Tuned for 3-minute matches (daily quests and the daily chest add more on top).
Rewards.Scrap = {
	Played = 50,
	Win = 50,
	Draw = 25,
	Goal = 25,
	Assist = 15,
	Save = 20,
	Shot = 5,
	TouchesPerScrap = 5, -- 1 Scrap for every 5 touches...
	TouchCap = 20, -- ...up to this much
	Style = 5,
	MegaShot = 5,
	Demo = 5,
	Mvp = 20,
	MatchCap = 350,
	FriendBonus = 0.25, -- +25% when one of your Roblox friends is in the match too
	StreakStep = 0.1, -- every win in a row after the first adds 10%...
	StreakMax = 0.5, -- ...up to +50%
}

function Rewards.emptyStats(): MatchStats
	return {
		goals = 0,
		assists = 0,
		saves = 0,
		shots = 0,
		touches = 0,
		styleTouches = 0,
		megaShots = 0,
		points = 0,
		orbs = 0,
		powers = 0,
		demos = 0,
	}
end

function Rewards.compute(stats: MatchStats, outcome: Outcome, isMvp: boolean): RewardSummary
	local s = Rewards.Scrap
	local lines: { RewardLine } = {}
	local function add(label: string, amount: number)
		if amount > 0 then
			table.insert(lines, { label = label, amount = amount })
		end
	end

	add("Played a match", s.Played)
	if outcome == "Win" then
		add("Victory!", s.Win)
	elseif outcome == "Draw" then
		add("Draw", s.Draw)
	end
	add(`Goals x{stats.goals}`, stats.goals * s.Goal)
	add(`Assists x{stats.assists}`, stats.assists * s.Assist)
	add(`Saves x{stats.saves}`, stats.saves * s.Save)
	add(`Shots x{stats.shots}`, stats.shots * s.Shot)
	add(`Ball touches x{stats.touches}`, math.min(math.floor(stats.touches / s.TouchesPerScrap), s.TouchCap))
	add(`Style moves x{stats.styleTouches}`, stats.styleTouches * s.Style)
	add(`Mega Shots x{stats.megaShots}`, stats.megaShots * s.MegaShot)
	add(`Demolitions x{stats.demos}`, stats.demos * s.Demo)
	if isMvp then
		add("MVP!", s.Mvp)
	end

	local total = 0
	for _, line in lines do
		total += line.amount
	end
	if total > s.MatchCap then
		table.insert(lines, { label = "Match cap", amount = s.MatchCap - total })
		total = s.MatchCap
	end
	return { lines = lines, total = total }
end

-- The extra Scrap (as a fraction, 0.2 = +20%) for winning `streak` matches in a row.
function Rewards.streakBonus(streak: number): number
	if streak < 2 then
		return 0
	end
	return math.min((streak - 1) * Rewards.Scrap.StreakStep, Rewards.Scrap.StreakMax)
end

-- The car a player is saving up for: the cheapest car they don't own yet.
function Rewards.nextGoal(owned: { [string]: boolean }, scrap: number): NextGoal?
	for _, def in CarCatalog.ordered() do
		if not owned[def.Id] and def.Price > 0 then
			return {
				carId = def.Id,
				displayName = def.DisplayName,
				emoji = def.Emoji,
				price = def.Price,
				have = math.min(scrap, def.Price),
				remaining = math.max(0, def.Price - scrap),
				canAfford = scrap >= def.Price,
			}
		end
	end
	return nil
end

return Rewards
