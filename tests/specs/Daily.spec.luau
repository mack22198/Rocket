-- Daily rewards: quests are fair and steady (the same all day, different between days and players), streaks
-- grow and reset properly, matches count toward quests, and the chest's three prizes are known in advance.
local Daily = require(Shared.Config.Daily)

return function(t)
	local expect = t.expect

	local DAY = 20000 -- some day

	local function stats(overrides: { [string]: number }?): { [string]: number }
		local s = {
			goals = 0,
			assists = 0,
			saves = 0,
			shots = 0,
			touches = 0,
			styleTouches = 0,
			megaShots = 0,
			points = 0,
			items = 0,
			powers = 0,
			demos = 0,
		}
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	t.test("every quest makes sense", function()
		local ids: { [string]: boolean } = {}
		for _, quest in Daily.Quests do
			expect.falsy(ids[quest.Id], `{quest.Id} is listed twice`)
			ids[quest.Id] = true
			expect.atLeast(quest.Target, 1)
			expect.atLeast(quest.Reward, 1)
			expect.falsy(string.find(Daily.describe(quest), "%", 1, true), `{quest.Id} text is filled in`)
		end
	end)

	t.test("three different quests a day, starting with an easy one, the same all day", function()
		for userId = 1, 40 do
			local quests = Daily.questsFor(userId * 977, DAY)
			expect.equal(#quests, Daily.QuestCount)
			local first = Daily.quest(quests[1])
			assert(first)
			expect.truthy(first.Easy, "the first quest is an easy one")
			expect.truthy(quests[1] ~= quests[2] and quests[2] ~= quests[3] and quests[1] ~= quests[3])
			local again = Daily.questsFor(userId * 977, DAY)
			expect.equal(table.concat(again, ","), table.concat(quests, ","))
		end
	end)

	t.test("quests change from day to day", function()
		local seen: { [string]: boolean } = {}
		local different = 0
		for day = DAY, DAY + 29 do
			local key = table.concat(Daily.questsFor(123456, day), ",")
			if not seen[key] then
				different += 1
				seen[key] = true
			end
		end
		expect.atLeast(different, 10)
	end)

	t.test("a new day brings new quests and a new chest, and the streak grows", function()
		local state = Daily.newState()
		expect.truthy(Daily.rollover(state, 55, DAY))
		expect.equal(state.streak, 1)
		expect.equal(#state.quests, 3)
		expect.truthy(Daily.canClaimStreak(state, DAY))
		state.streakClaimedDay = DAY
		state.chestPicked = true
		expect.falsy(Daily.canClaimStreak(state, DAY))
		expect.falsy(Daily.rollover(state, 55, DAY), "nothing changes later the same day")

		expect.truthy(Daily.rollover(state, 55, DAY + 1))
		expect.equal(state.streak, 2)
		expect.falsy(state.chestPicked)
		expect.truthy(Daily.canClaimStreak(state, DAY + 1))
		for _, quest in state.quests do
			expect.equal(quest.progress, 0)
			expect.falsy(quest.claimed)
		end

		Daily.rollover(state, 55, DAY + 4) -- missed two days
		expect.equal(state.streak, 1)
	end)

	t.test("streak rewards grow to day 7 and stay there", function()
		expect.equal(Daily.streakReward(1), Daily.StreakRewards[1])
		for day = 2, 7 do
			expect.truthy(Daily.streakReward(day) > Daily.streakReward(day - 1))
		end
		expect.equal(Daily.streakReward(30), Daily.StreakRewards[7])
	end)

	t.test("matches count toward quests, and finishing them unlocks the chest", function()
		local state = Daily.newState()
		state.day = DAY
		state.quests = {
			{ id = "matches", progress = 0, claimed = false },
			{ id = "goals", progress = 0, claimed = false },
			{ id = "wins", progress = 0, claimed = false },
		}
		local finished = Daily.record(state, stats({ goals = 1 }), "Loss")
		expect.equal(#finished, 0)
		expect.equal(state.quests[1].progress, 1)
		expect.equal(state.quests[2].progress, 1)
		expect.equal(state.quests[3].progress, 0, "a loss isn't a win")
		finished = Daily.record(state, stats({ goals = 5 }), "Win")
		expect.equal(#finished, 2)
		expect.equal(state.quests[2].progress, 2, "progress stops at the target")
		expect.falsy(Daily.allDone(state))
		Daily.record(state, stats(), "Draw")
		expect.truthy(Daily.allDone(state))
		expect.equal(#Daily.record(state, stats({ goals = 3 }), "Win"), 0, "nothing finishes twice")
	end)

	t.test("the chest's three prizes are known in advance", function()
		local options = Daily.chestOptions(99, DAY)
		expect.equal(#options, 3)
		local kinds = {}
		for _, option in options do
			kinds[option.Kind] = true
			expect.atLeast(option.Amount, 1)
			expect.truthy(#option.Title > 0 and #option.Text > 0)
		end
		expect.truthy(kinds.scrap and kinds.xp and kinds.boost)
		local again = Daily.chestOptions(99, DAY)
		for i, option in options do
			expect.equal(again[i].Amount, option.Amount)
		end
	end)

	t.test("the day turns over at the reset hour", function()
		local midnightUtc = 1790000000 - 1790000000 % 86400 -- some 00:00 UTC
		local reset = midnightUtc + Daily.ResetHourUtc * 3600
		expect.equal(Daily.dayNumber(reset - 1) + 1, Daily.dayNumber(reset))
		expect.equal(Daily.secondsUntilNextDay(reset - 10), 10)
		expect.equal(Daily.secondsUntilNextDay(reset), 86400)
	end)
end
