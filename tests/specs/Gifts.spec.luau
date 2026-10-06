-- Playtime gifts and the weekly leaderboard: gifts unlock in order and only once, every prize is real, and weeks
-- start on Mondays at the daily reset.
local Daily = require(Shared.Config.Daily)
local Gifts = require(Shared.Config.Gifts)
local Leaderboard = require(Shared.Config.Leaderboard)

return function(t)
	local expect = t.expect

	t.test("gifts unlock in order, each once", function()
		local last = 0
		for index, gift in Gifts.Ladder do
			expect.truthy(gift.Minutes > last, `gift {index} comes after the one before`)
			last = gift.Minutes
			expect.truthy(gift.Amount > 0)
			expect.truthy(gift.Kind == "scrap" or gift.Kind == "boost", `gift {index} is a known prize`)
			local emoji, text = Gifts.describe(gift)
			expect.truthy(emoji ~= "" and text ~= "")
		end
		local opened: { [number]: boolean } = {}
		expect.equal(Gifts.readyCount(0, opened), 0)
		expect.falsy(Gifts.ready(1, Gifts.Ladder[1].Minutes * 60 - 1, opened))
		expect.truthy(Gifts.ready(1, Gifts.Ladder[1].Minutes * 60, opened))
		expect.equal(Gifts.readyCount(Gifts.Ladder[3].Minutes * 60, opened), 3)
		opened[1] = true
		expect.falsy(Gifts.ready(1, 99999, opened), "an opened gift can't be opened again")
		expect.equal(Gifts.readyCount(Gifts.Ladder[3].Minutes * 60, opened), 2)
		expect.falsy(Gifts.ready(99, 99999, opened))
		expect.equal(Gifts.nextIn(0, {}), Gifts.Ladder[1].Minutes * 60)
		local all: { [number]: boolean } = {}
		for index in Gifts.Ladder do
			all[index] = true
		end
		expect.equal(Gifts.nextIn(0, all), nil)
	end)

	t.test("weeks start on Mondays at the daily reset", function()
		-- Monday 6 October 2025, 05:00 UTC.
		local monday = 1759726800
		local week = Leaderboard.week(monday)
		expect.equal(Leaderboard.week(monday - 1), week - 1, "a second before is last week")
		expect.equal(Leaderboard.week(monday + 7 * 86400 - 1), week, "the whole week")
		expect.equal(Leaderboard.week(monday + 7 * 86400), week + 1)
		expect.equal(Leaderboard.secondsLeft(monday), 7 * 86400)
		expect.equal(Leaderboard.secondsLeft(monday + 3600), 7 * 86400 - 3600)
		expect.equal(Daily.dayNumber(monday) % 7, 4, "(day 4 of the epoch was a Monday too)")
		expect.truthy(Leaderboard.storeName(week) ~= Leaderboard.storeName(week + 1))
	end)
end
