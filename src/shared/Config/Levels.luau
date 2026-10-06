--!strict
-- Your player level: every match earns as much level XP as the Scrap you win, and every level you reach pays
-- some Scrap. The first levels come quickly (finishing your first match takes you to level 2, and level 10 is
-- about ten matches away), later ones take a few matches each, and there's no top level. Some levels also
-- unlock a title to show under your name (see Achievements.Titles).

local Levels = {}

Levels.FirstLevelXp = 50 -- XP from level 1 to level 2 (any finished match earns at least this)...
Levels.XpGrowth = 50 -- ...each level after that needs this much more...
Levels.MaxXpPerLevel = 1000 -- ...but never more than this

-- XP needed to go from `level` to the next one.
function Levels.need(level: number): number
	return math.min(Levels.FirstLevelXp + Levels.XpGrowth * (level - 1), Levels.MaxXpPerLevel)
end

-- The level `xp` (all the level XP ever earned) gets you to, the XP into that level, and the XP it needs.
function Levels.levelFor(xp: number): (number, number, number)
	local level = 1
	local left = math.max(0, math.floor(xp))
	while true do
		local need = Levels.need(level)
		if left < need then
			return level, left, need
		elseif need >= Levels.MaxXpPerLevel then
			-- Every level from here on needs the same, so skip straight there.
			local more = math.floor(left / need)
			return level + more, left - more * need, need
		end
		left -= need
		level += 1
	end
end

-- Scrap for reaching `level`.
function Levels.reward(level: number): number
	return math.min(50 + 10 * level, 300)
end

return Levels
