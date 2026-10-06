-- Seasons: they run back to back, XP moves you up the track and pays out each tier once, a new season starts
-- from zero, the track can be finished by playing about a match a day, and every season-only item is on a track.
local Cosmetics = require(Shared.Config.Cosmetics)
local Rewards = require(Shared.Config.Rewards)
local Season = require(Shared.Config.Season)

return function(t)
	local expect = t.expect
	local first = Season.FirstDay

	t.test("seasons run back to back", function()
		expect.equal(Season.at(first - 30).number, 1, "before the first season, it's Season 1")
		expect.equal(Season.at(first).number, 1)
		expect.equal(Season.at(first + Season.Days - 1).number, 1)
		local second = Season.at(first + Season.Days)
		expect.equal(second.number, 2)
		expect.equal(second.startDay, first + Season.Days)
		expect.equal(second.endDay, first + 2 * Season.Days)
		expect.equal(Season.daysLeft(first), Season.Days)
		expect.equal(Season.daysLeft(first + Season.Days - 1), 1)
		expect.equal(Season.daysLeft(first - 5), Season.Days, "the countdown starts when the season does")
	end)

	t.test("XP pays out each tier once, in order", function()
		local state = Season.newState()
		local theme = Season.at(first).theme
		local reached = Season.addXp(state, Season.XpPerTier - 1, first)
		expect.equal(#reached, 0)
		reached = Season.addXp(state, 1, first)
		expect.equal(#reached, 1)
		expect.equal(reached[1].tier, 1)
		expect.equal(reached[1].reward, theme.Rewards[1])
		reached = Season.addXp(state, Season.XpPerTier * 2 + 10, first)
		expect.equal(#reached, 2)
		expect.equal(reached[1].tier, 2)
		expect.equal(reached[2].tier, 3)
		expect.equal(state.tier, 3)
		local into, need = Season.tierProgress(state)
		expect.equal(into, 10)
		expect.equal(need, Season.XpPerTier)
		expect.equal(#Season.addXp(state, 0, first), 0)
		expect.equal(#Season.addXp(state, -500, first), 0, "XP never goes down")
		expect.equal(state.tier, 3)
	end)

	t.test("past the end of the track, every tier is bonus Scrap", function()
		local state = Season.newState()
		local theme = Season.at(first).theme
		local reached = Season.addXp(state, (#theme.Rewards + 2) * Season.XpPerTier, first)
		expect.equal(#reached, #theme.Rewards + 2)
		local last = reached[#reached].reward
		expect.equal(last.Kind, "scrap")
		expect.equal(last.Amount, Season.BonusScrap)
	end)

	t.test("a new season starts from zero", function()
		local state = Season.newState()
		Season.addXp(state, Season.XpPerTier * 5, first)
		expect.equal(state.tier, 5)
		local reached = Season.addXp(state, Season.XpPerTier, first + Season.Days)
		expect.equal(state.number, 2)
		expect.equal(state.tier, 1, "only this season's XP counts")
		expect.equal(reached[1].tier, 1)
	end)

	t.test("a match a day finishes the track", function()
		local typicalMatch = Rewards.Scrap.Played + Rewards.Scrap.Draw + Rewards.Scrap.Goal + Rewards.Scrap.Save
		for _, theme in Season.Themes do
			local needed = #theme.Rewards * Season.XpPerTier
			expect.atMost(needed, Season.Days * typicalMatch, `{theme.Id} can be finished`)
			expect.atLeast(#theme.Rewards, 10, `{theme.Id} has a proper track`)
		end
	end)

	t.test("every reward is real, and every season-only item is on its track", function()
		local onTrack: { [string]: string } = {}
		for _, theme in Season.Themes do
			expect.equal(#theme.GoldRewards, #theme.Rewards, `{theme.Id}'s gold track has a reward for every tier`)
			for _, track in { { rewards = theme.Rewards, gold = false }, { rewards = theme.GoldRewards, gold = true } } do
				for tier, reward in track.rewards do
					expect.truthy(reward.Amount > 0, `{theme.Id} tier {tier} is worth something`)
					local emoji, text = Season.describe(reward)
					expect.truthy(emoji ~= "" and text ~= "")
					if reward.Kind == "style" then
						local item = Cosmetics.get(reward.Id)
						assert(item, `{theme.Id} tier {tier}: {reward.Id} exists`)
						expect.equal(item.Season, theme.Id, `{item.Id} belongs to {theme.Id}`)
						expect.equal(item.Gold == true, track.gold, `{item.Id} is on the right track`)
						onTrack[item.Id] = theme.Id
					else
						expect.truthy(
							reward.Kind == "scrap" or reward.Kind == "boost",
							`{reward.Kind} is a known reward`
						)
					end
				end
			end
		end
		for _, item in Cosmetics.List do
			if item.Season then
				expect.truthy(onTrack[item.Id] ~= nil, `{item.Id} can be earned`)
				expect.truthy(Season.theme(item.Season) ~= nil, `{item.Id}'s season exists`)
			end
		end
	end)

	t.test("the Gold Pass lasts one season and adds a reward to every tier", function()
		local state = Season.newState()
		expect.equal(state.gold, false)
		Season.addXp(state, Season.XpPerTier * 3, first)
		state.gold = true
		Season.addXp(state, 10, first + 1)
		expect.truthy(state.gold, "it lasts the whole season")
		Season.addXp(state, 10, first + Season.Days)
		expect.equal(state.gold, false, "a new season needs a new pass")
		local theme = Season.at(first).theme
		expect.truthy(Season.goldRewardFor(theme, 1) == theme.GoldRewards[1])
		expect.equal(Season.goldRewardFor(theme, #theme.GoldRewards + 5).Amount, Season.GoldBonusScrap)
		-- The gold track is worth more than the free one.
		local free, gold = 0, 0
		for tier = 1, #theme.Rewards do
			local f, g = theme.Rewards[tier], theme.GoldRewards[tier]
			free += if f.Kind == "scrap" then f.Amount else 0
			gold += if g.Kind == "scrap" then g.Amount else 0
		end
		expect.truthy(gold > free)
	end)
end
