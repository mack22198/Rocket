--!strict
-- Reasons to come back every day, without any gambling:
--   * a login streak: Scrap for every day in a row you play (it grows up to day 7)
--   * three daily quests ("Score 2 goals", "Grab 2 charge orbs"...), each worth Scrap
--   * a daily chest once all three are done: you see all three prizes and pick the one you want
-- Everything is worked out from the player's id and the day, so the server (and the tests) always agree on
-- what today's quests and prizes are.

local Daily = {}

Daily.ResetHourUtc = 5 -- a new day starts at 05:00 UTC (midnight on the US east coast)

-- Scrap for each day of a streak; day 7 and every day after it pays the most.
Daily.StreakRewards = { 50, 75, 100, 125, 150, 200, 300 }

export type QuestDef = {
	Id: string,
	Stat: string, -- what counts: a match stat, or "wins" / "matches"
	Target: number,
	Reward: number, -- Scrap
	Text: string, -- %d is replaced with the target
	Emoji: string,
	Easy: boolean?, -- every day has at least one easy quest
}

Daily.Quests = {
	{
		Id = "matches",
		Stat = "matches",
		Target = 3,
		Reward = 60,
		Text = "Play %d matches",
		Emoji = "🎮",
		Easy = true,
	},
	{
		Id = "touches",
		Stat = "touches",
		Target = 40,
		Reward = 50,
		Text = "Hit the ball %d times",
		Emoji = "👟",
		Easy = true,
	},
	{ Id = "orbs", Stat = "orbs", Target = 2, Reward = 50, Text = "Grab %d charge orbs", Emoji = "🔮", Easy = true },
	{
		Id = "powers",
		Stat = "powers",
		Target = 3,
		Reward = 50,
		Text = "Use your ultimate %d times",
		Emoji = "⚡",
		Easy = true,
	},
	{ Id = "goals", Stat = "goals", Target = 2, Reward = 70, Text = "Score %d goals", Emoji = "⚽" },
	{ Id = "saves", Stat = "saves", Target = 3, Reward = 70, Text = "Make %d saves", Emoji = "🧤" },
	{ Id = "shots", Stat = "shots", Target = 5, Reward = 60, Text = "Take %d shots at goal", Emoji = "🎯" },
	{ Id = "assists", Stat = "assists", Target = 2, Reward = 70, Text = "Get %d assists", Emoji = "🤝" },
	{ Id = "style", Stat = "styleTouches", Target = 3, Reward = 70, Text = "Do %d air or wall hits", Emoji = "✨" },
	{ Id = "wins", Stat = "wins", Target = 1, Reward = 80, Text = "Win a match", Emoji = "🏆" },
} :: { QuestDef }

Daily.QuestCount = 3

export type ChestOption = {
	Kind: string, -- "scrap", "xp" (for the car you're driving) or "boost" (double Scrap for a few matches)
	Amount: number,
	Emoji: string,
	Title: string,
	Text: string,
}

local questsById: { [string]: QuestDef } = {}
for _, quest in Daily.Quests do
	questsById[quest.Id] = quest
end

function Daily.quest(id: string): QuestDef?
	return questsById[id]
end

-- What a quest asks for, in words.
function Daily.describe(quest: QuestDef): string
	if string.find(quest.Text, "%d", 1, true) then
		return string.format(quest.Text, quest.Target)
	end
	return quest.Text
end

-- Which day it is (days since 1970, turning over at ResetHourUtc).
function Daily.dayNumber(unixTime: number): number
	return (unixTime - Daily.ResetHourUtc * 3600) // 86400
end

-- Seconds until the next day starts.
function Daily.secondsUntilNextDay(unixTime: number): number
	local start = (Daily.dayNumber(unixTime) + 1) * 86400 + Daily.ResetHourUtc * 3600
	return math.max(0, start - unixTime)
end

-- The Scrap for day `streak` of a streak.
function Daily.streakReward(streak: number): number
	local rewards = Daily.StreakRewards
	return rewards[math.clamp(streak, 1, #rewards)]
end

-- A tiny random number maker that always gives the same numbers for the same seed, everywhere (the "MINSTD"
-- generator). Seeded from the player and the day, so everyone's quests differ but never change during a day.
type Dice = { integer: (low: number, high: number) -> number }

local function dice(userId: number, day: number, salt: number): Dice
	local state = ((math.abs(userId) % 1000003) * 7919 + day * 104729 + salt * 15485863) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function nextFraction(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	-- Stir a few times so nearby seeds don't start out alike.
	for _ = 1, 4 do
		nextFraction()
	end
	return {
		integer = function(low: number, high: number): number
			return math.min(high, low + math.floor(nextFraction() * (high - low + 1)))
		end,
	}
end

-- Today's quests for a player: one easy one, then two different others.
function Daily.questsFor(userId: number, day: number): { string }
	local rng = dice(userId, day, 1)
	local easy: { string } = {}
	local rest: { string } = {}
	for _, quest in Daily.Quests do
		table.insert(if quest.Easy then easy else rest, quest.Id)
	end
	local picked = { easy[rng.integer(1, #easy)] }
	local pool: { string } = {}
	for _, id in easy do
		if id ~= picked[1] then
			table.insert(pool, id)
		end
	end
	for _, id in rest do
		table.insert(pool, id)
	end
	while #picked < Daily.QuestCount and #pool > 0 do
		table.insert(picked, table.remove(pool, rng.integer(1, #pool)) :: string)
	end
	return picked
end

-- How much a finished match counts toward a quest stat.
function Daily.amount(stat: string, matchStats: { [string]: any }, outcome: string): number
	if stat == "matches" then
		return 1
	elseif stat == "wins" then
		return if outcome == "Win" then 1 else 0
	end
	local value = matchStats[stat]
	return if type(value) == "number" then value else 0
end

-- Today's three chest prizes, all shown before you pick one.
function Daily.chestOptions(userId: number, day: number): { ChestOption }
	local rng = dice(userId, day, 2)
	local scrap = 200 + rng.integer(0, 4) * 25
	local xp = 300 + rng.integer(0, 4) * 50
	local boost = rng.integer(2, 3)
	return {
		{
			Kind = "scrap",
			Amount = scrap,
			Emoji = "🔩",
			Title = `{scrap} SCRAP`,
			Text = "Straight into your pocket.",
		},
		{
			Kind = "xp",
			Amount = xp,
			Emoji = "✨",
			Title = `+{xp} CAR XP`,
			Text = "For the car you're driving - evolve it sooner!",
		},
		{
			Kind = "boost",
			Amount = boost,
			Emoji = "🚀",
			Title = "DOUBLE SCRAP",
			Text = `Your next {boost} matches pay double Scrap.`,
		},
	}
end

export type QuestState = { id: string, progress: number, claimed: boolean }

-- A player's saved daily progress.
export type State = {
	day: number, -- the day `quests` and `chestPicked` belong to (0 = never)
	quests: { QuestState },
	chestPicked: boolean,
	streak: number, -- days in a row
	lastLoginDay: number,
	streakClaimedDay: number, -- the last day the streak reward was collected
}

function Daily.newState(): State
	return { day = 0, quests = {}, chestPicked = false, streak = 0, lastLoginDay = 0, streakClaimedDay = 0 }
end

-- Brings a player's daily progress up to `today`: new quests and a fresh chest on a new day, and the streak
-- grows (played yesterday too) or starts again (missed a day). Returns true if anything changed.
function Daily.rollover(state: State, userId: number, today: number): boolean
	local changed = false
	if state.day ~= today then
		state.day = today
		state.quests = {}
		for _, id in Daily.questsFor(userId, today) do
			table.insert(state.quests, { id = id, progress = 0, claimed = false })
		end
		state.chestPicked = false
		changed = true
	end
	if state.lastLoginDay ~= today then
		state.streak = if state.lastLoginDay == today - 1 then state.streak + 1 else 1
		state.lastLoginDay = today
		changed = true
	end
	-- A quest that's been retired (in an update) is swapped for one that's still around.
	for i, quest in state.quests do
		if not Daily.quest(quest.id) then
			for _, def in Daily.Quests do
				local taken = false
				for _, other in state.quests do
					taken = taken or other.id == def.Id
				end
				if not taken then
					state.quests[i] = { id = def.Id, progress = 0, claimed = false }
					changed = true
					break
				end
			end
		end
	end
	return changed
end

-- Does today's list still have a quest that's been retired (see rollover)?
function Daily.hasRetired(state: State): boolean
	for _, quest in state.quests do
		if not Daily.quest(quest.id) then
			return true
		end
	end
	return false
end

function Daily.isDone(quest: QuestState): boolean
	local def = Daily.quest(quest.id)
	return def ~= nil and quest.progress >= def.Target
end

-- All of today's quests are done: the daily chest can be opened.
function Daily.allDone(state: State): boolean
	if #state.quests == 0 then
		return false
	end
	for _, quest in state.quests do
		if not Daily.isDone(quest) then
			return false
		end
	end
	return true
end

-- Counts a finished match toward today's quests. Returns the quests it just finished.
function Daily.record(state: State, matchStats: { [string]: any }, outcome: string): { QuestState }
	local finished: { QuestState } = {}
	for _, quest in state.quests do
		local def = Daily.quest(quest.id)
		if def and quest.progress < def.Target then
			quest.progress = math.min(def.Target, quest.progress + Daily.amount(def.Stat, matchStats, outcome))
			if quest.progress >= def.Target then
				table.insert(finished, quest)
			end
		end
	end
	return finished
end

function Daily.canClaimStreak(state: State, today: number): boolean
	return state.lastLoginDay == today and state.streakClaimedDay ~= today and state.streak > 0
end

return Daily
