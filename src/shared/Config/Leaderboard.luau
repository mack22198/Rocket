--!strict
-- The weekly leaderboard: the top drivers by level XP earned this week (as much as the Scrap they won in matches).
-- A new week starts every Monday when the daily rewards reset, with everyone back on zero.

local Daily = require(script.Parent.Daily)

local Leaderboard = {}

Leaderboard.Size = 50 -- how many names it shows
Leaderboard.RefreshSeconds = 120 -- how often each server reads it again

-- The week number for `time` (seconds since 1970). Weeks start on Mondays at the daily reset.
function Leaderboard.week(time: number): number
	return (Daily.dayNumber(time) + 3) // 7 -- day 4 (Monday 5 January 1970) starts week 1
end

-- Seconds until the next week starts.
function Leaderboard.secondsLeft(time: number): number
	local nextDay = (Leaderboard.week(time) + 1) * 7 - 3 -- the first day of next week
	return math.max(0, nextDay * 86400 + Daily.ResetHourUtc * 3600 - time)
end

-- The DataStore that keeps one week's scores.
function Leaderboard.storeName(week: number): string
	return `WeeklyXp_{week}`
end

return Leaderboard
