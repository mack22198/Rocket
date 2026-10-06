--!strict
-- Achievements: goals to work toward ("Make 25 saves", "Score a hat trick", "Fuse a car"), each paying Scrap once,
-- and some unlocking a title to show under your name. Titles also come with player levels. Every achievement can
-- award a Roblox badge too: make the badge on the Creator Dashboard and paste its ID as the achievement's Badge.
--
-- What counts is a flat table of numbers (a "view"): lifetime stats (wins, goals...), collection counts (cars
-- owned...), your level, and - at the end of a match - a few numbers about that match.

local CarCatalog = require(script.Parent.CarCatalog)
local GameConfig = require(script.Parent.GameConfig)
local Levels = require(script.Parent.Levels)

local Achievements = {}

export type AchievementDef = {
	Id: string,
	Emoji: string,
	Name: string,
	Text: string,
	Stat: string, -- the number in the view that counts (see below)
	Target: number,
	Reward: number, -- Scrap
	Title: string?, -- the title it unlocks, if any
	Badge: number?, -- a Roblox badge ID to award as well (nil or 0 = none)
}

export type TitleDef = {
	Id: string,
	Emoji: string,
	Text: string,
	Level: number?, -- unlocked by reaching this level...
	Achievement: string?, -- ...or by this achievement
}

export type View = { [string]: number }

-- A badge for everyone the first time they play (0 = none).
Achievements.WelcomeBadge = 0

-- View numbers: matches, wins, goals, assists, saves, shots, megaShots, demos, mvps, styleTouches, items, powers,
-- bestStreak (wins in a row), friendMatches, level, carsOwned, evolvedCars (fully evolved), fusedCars, loginStreak, and at the end
-- of a match: matchGoals, cleanSheetWin (1 = won without letting a goal in), comebackWin (1 = won after being
-- 2 goals behind).
Achievements.List = {
	-- First steps
	{
		Id = "first_goal",
		Emoji = "⚽",
		Name = "First Goal",
		Text = "Score a goal",
		Stat = "goals",
		Target = 1,
		Reward = 50,
	},
	{
		Id = "first_win",
		Emoji = "🏆",
		Name = "First Win",
		Text = "Win a match",
		Stat = "wins",
		Target = 1,
		Reward = 50,
	},
	{
		Id = "first_mvp",
		Emoji = "⭐",
		Name = "MVP!",
		Text = "Be the MVP of a match",
		Stat = "mvps",
		Target = 1,
		Reward = 100,
	},
	{
		Id = "first_demo",
		Emoji = "💥",
		Name = "POOF!",
		Text = "Demolish a car",
		Stat = "demos",
		Target = 1,
		Reward = 50,
	},
	-- In one match
	{
		Id = "hat_trick",
		Emoji = "🎩",
		Name = "Hat Trick",
		Text = "Score 3 goals in one match",
		Stat = "matchGoals",
		Target = 3,
		Reward = 200,
		Title = "Hat Trick Hero",
	},
	{
		Id = "clean_sheet",
		Emoji = "🧱",
		Name = "Clean Sheet",
		Text = "Win without letting a goal in",
		Stat = "cleanSheetWin",
		Target = 1,
		Reward = 150,
	},
	{
		Id = "comeback",
		Emoji = "↩️",
		Name = "Comeback Kid",
		Text = "Win after being 2 goals behind",
		Stat = "comebackWin",
		Target = 1,
		Reward = 250,
		Title = "Comeback Kid",
	},
	-- Streaks
	{
		Id = "streak_3",
		Emoji = "🔥",
		Name = "On Fire",
		Text = "Win 3 matches in a row",
		Stat = "bestStreak",
		Target = 3,
		Reward = 150,
	},
	{
		Id = "streak_5",
		Emoji = "🔥",
		Name = "Unstoppable",
		Text = "Win 5 matches in a row",
		Stat = "bestStreak",
		Target = 5,
		Reward = 300,
		Title = "Unstoppable",
	},
	{
		Id = "squad",
		Emoji = "👋",
		Name = "Squad Up",
		Text = "Play a match with a Roblox friend",
		Stat = "friendMatches",
		Target = 1,
		Reward = 150,
		Title = "Squad",
	},
	{
		Id = "login_7",
		Emoji = "📅",
		Name = "Every Day",
		Text = "Play 7 days in a row",
		Stat = "loginStreak",
		Target = 7,
		Reward = 200,
	},
	-- Getting good
	{
		Id = "goals_50",
		Emoji = "⚽",
		Name = "Goal Machine",
		Text = "Score 50 goals",
		Stat = "goals",
		Target = 50,
		Reward = 300,
		Title = "Goal Machine",
	},
	{
		Id = "saves_25",
		Emoji = "🧤",
		Name = "Brick Wall",
		Text = "Make 25 saves",
		Stat = "saves",
		Target = 25,
		Reward = 250,
		Title = "Brick Wall",
	},
	{
		Id = "assists_25",
		Emoji = "🤝",
		Name = "Team Player",
		Text = "Get 25 assists",
		Stat = "assists",
		Target = 25,
		Reward = 250,
		Title = "Team Player",
	},
	{
		Id = "demos_25",
		Emoji = "💥",
		Name = "Wrecking Ball",
		Text = "Demolish 25 cars",
		Stat = "demos",
		Target = 25,
		Reward = 250,
		Title = "Wrecking Ball",
	},
	{
		Id = "style_25",
		Emoji = "✨",
		Name = "Air Ace",
		Text = "Do 25 air or wall hits",
		Stat = "styleTouches",
		Target = 25,
		Reward = 250,
		Title = "Air Ace",
	},
	{
		Id = "mega_10",
		Emoji = "🔥",
		Name = "Mega Blaster",
		Text = "Hit 10 Mega Shots",
		Stat = "megaShots",
		Target = 10,
		Reward = 200,
	},
	{
		Id = "items_50",
		Emoji = "🎁",
		Name = "Gadget Fan",
		Text = "Use 50 items",
		Stat = "items",
		Target = 50,
		Reward = 150,
	},
	{
		Id = "powers_50",
		Emoji = "⚡",
		Name = "Power Player",
		Text = "Use your car's power 50 times",
		Stat = "powers",
		Target = 50,
		Reward = 150,
	},
	{
		Id = "wins_25",
		Emoji = "🏆",
		Name = "Winner",
		Text = "Win 25 matches",
		Stat = "wins",
		Target = 25,
		Reward = 250,
		Title = "Winner",
	},
	{
		Id = "mvps_25",
		Emoji = "⭐",
		Name = "Superstar",
		Text = "Be the MVP 25 times",
		Stat = "mvps",
		Target = 25,
		Reward = 400,
		Title = "Superstar",
	},
	{
		Id = "matches_100",
		Emoji = "🎮",
		Name = "Regular",
		Text = "Play 100 matches",
		Stat = "matches",
		Target = 100,
		Reward = 400,
		Title = "Regular",
	},
	{
		Id = "wins_100",
		Emoji = "👑",
		Name = "Champion",
		Text = "Win 100 matches",
		Stat = "wins",
		Target = 100,
		Reward = 600,
		Title = "Champion",
	},
	-- The garage
	{
		Id = "cars_5",
		Emoji = "🚗",
		Name = "Collector",
		Text = "Own 5 cars",
		Stat = "carsOwned",
		Target = 5,
		Reward = 200,
		Title = "Collector",
	},
	{
		Id = "evolved",
		Emoji = "🧬",
		Name = "Evolution!",
		Text = "Evolve a car all the way",
		Stat = "evolvedCars",
		Target = 1,
		Reward = 300,
		Title = "Evolver",
	},
	{
		Id = "fused",
		Emoji = "🧪",
		Name = "Mad Scientist",
		Text = "Fuse two cars into a new one",
		Stat = "fusedCars",
		Target = 1,
		Reward = 300,
		Title = "Mad Scientist",
	},
} :: { AchievementDef }

-- Titles that come with levels (the first one everybody has).
local LEVEL_TITLES: { TitleDef } = {
	{ Id = "rookie", Emoji = "🚗", Text = "Rookie", Level = 1 },
	{ Id = "driver", Emoji = "🛞", Text = "Driver", Level = 5 },
	{ Id = "speedster", Emoji = "⚡", Text = "Speedster", Level = 10 },
	{ Id = "pro", Emoji = "🏅", Text = "Pro", Level = 20 },
	{ Id = "ace", Emoji = "💎", Text = "Ace", Level = 30 },
	{ Id = "legend", Emoji = "👑", Text = "Legend", Level = 50 },
}

Achievements.DefaultTitle = "rookie"
Achievements.Titles = {} :: { TitleDef }

local byId: { [string]: AchievementDef } = {}
local titlesById: { [string]: TitleDef } = {}
for _, title in LEVEL_TITLES do
	table.insert(Achievements.Titles, title)
end
for _, def in Achievements.List do
	byId[def.Id] = def
	if def.Title then
		table.insert(Achievements.Titles, { Id = def.Id, Emoji = def.Emoji, Text = def.Title, Achievement = def.Id })
	end
end
for _, title in Achievements.Titles do
	titlesById[title.Id] = title
end

function Achievements.get(id: string): AchievementDef?
	return byId[id]
end

-- The view of someone's saved progress: their lifetime `stats`, the cars they own and how far each has evolved,
-- their daily login streak and their level XP.
function Achievements.viewOf(
	stats: { [string]: number },
	owned: { [string]: boolean },
	carStage: { [string]: number },
	loginStreak: number,
	xp: number
): View
	local view: View = table.clone(stats)
	local cars, evolved, fused = 0, 0, 0
	for id, have in owned do
		local def = CarCatalog.get(id)
		if def and have then
			cars += 1
			if def.Fusion then
				fused += 1
			end
		end
	end
	for _, stage in carStage do
		if stage >= GameConfig.Evolution.Stages then
			evolved += 1
		end
	end
	view.carsOwned = cars
	view.evolvedCars = evolved
	view.fusedCars = fused
	view.loginStreak = loginStreak
	view.level = (Levels.levelFor(xp))
	return view
end

-- How far along an achievement is: (progress, target), with progress never past the target.
function Achievements.progress(def: AchievementDef, view: View): (number, number)
	local value = view[def.Stat]
	local current = if type(value) == "number" then value else 0
	return math.clamp(math.floor(current), 0, def.Target), def.Target
end

-- The achievements `view` completes that aren't in `done` yet, in list order.
function Achievements.newlyDone(done: { [string]: boolean }, view: View): { AchievementDef }
	local list: { AchievementDef } = {}
	for _, def in Achievements.List do
		if not done[def.Id] then
			local progress, target = Achievements.progress(def, view)
			if progress >= target then
				table.insert(list, def)
			end
		end
	end
	return list
end

function Achievements.title(id: string): TitleDef?
	return titlesById[id]
end

-- "🧤 Brick Wall" (or "" for an unknown title).
function Achievements.titleText(id: string): string
	local title = titlesById[id]
	return if title then `{title.Emoji} {title.Text}` else ""
end

-- Has someone at `level` with these achievements unlocked this title?
function Achievements.ownsTitle(id: string, level: number, done: { [string]: boolean }): boolean
	local title = titlesById[id]
	if not title then
		return false
	elseif title.Level then
		return level >= title.Level
	end
	return title.Achievement ~= nil and done[title.Achievement] == true
end

-- What unlocks a title, for the ones you haven't got yet ("Reach level 10", "Brick Wall: Make 25 saves").
function Achievements.howToUnlock(id: string): string
	local title = titlesById[id]
	if not title then
		return ""
	elseif title.Level then
		return `Reach level {title.Level}`
	end
	local def = if title.Achievement then byId[title.Achievement] else nil
	return if def then `{def.Name}: {def.Text}` else ""
end

-- The level title someone at `level` gets automatically (the best one they've reached).
function Achievements.levelTitle(level: number): string
	local best = Achievements.DefaultTitle
	for _, title in LEVEL_TITLES do
		if title.Level and level >= title.Level then
			best = title.Id
		end
	end
	return best
end

return Achievements
