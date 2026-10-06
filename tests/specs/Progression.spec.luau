-- Levels, win streaks, achievements and titles: the first level comes after one match, levels never stop, streaks
-- pay a capped bonus, achievements finish once and make sense, and every title can be earned.
local Achievements = require(Shared.Config.Achievements)
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local Levels = require(Shared.Config.Levels)
local Rewards = require(Shared.Config.Rewards)

return function(t)
	local expect = t.expect

	t.test("levels start quick and keep going", function()
		local level, into, need = Levels.levelFor(0)
		expect.equal(level, 1)
		expect.equal(into, 0)
		expect.equal(need, Levels.FirstLevelXp)
		local typicalMatch = Rewards.Scrap.Played + Rewards.Scrap.Win + Rewards.Scrap.Goal + Rewards.Scrap.Save
		expect.atLeast((Levels.levelFor(typicalMatch)), 2, "your first match takes you to level 2")
		expect.equal((Levels.levelFor(Levels.FirstLevelXp - 1)), 1)
		expect.equal((Levels.levelFor(Levels.FirstLevelXp)), 2)
		-- Every level needs at least as much as the one before, up to the cap.
		local total = 0
		for l = 1, 60 do
			expect.atLeast(Levels.need(l + 1), Levels.need(l))
			expect.atMost(Levels.need(l), Levels.MaxXpPerLevel)
			total += Levels.need(l)
			local reached, left = Levels.levelFor(total)
			expect.equal(reached, l + 1, `{total} XP is level {l + 1}`)
			expect.equal(left, 0)
		end
		-- Huge numbers don't take forever.
		local big = Levels.levelFor(1e11)
		expect.atLeast(big, 1e7)
		for l = 1, 100 do
			expect.truthy(Levels.reward(l) > 0 and Levels.reward(l) <= 300)
		end
	end)

	t.test("win streaks pay a capped bonus", function()
		expect.equal(Rewards.streakBonus(0), 0)
		expect.equal(Rewards.streakBonus(1), 0, "one win isn't a streak")
		expect.near(Rewards.streakBonus(2), Rewards.Scrap.StreakStep, 1e-9)
		expect.near(Rewards.streakBonus(3), 2 * Rewards.Scrap.StreakStep, 1e-9)
		expect.equal(Rewards.streakBonus(50), Rewards.Scrap.StreakMax)
		for s = 1, 20 do
			expect.atLeast(Rewards.streakBonus(s + 1), Rewards.streakBonus(s))
		end
	end)

	t.test("every achievement makes sense and is listed once", function()
		local seen: { [string]: boolean } = {}
		local stats = { "matches", "wins", "goals", "assists", "saves", "shots", "megaShots", "demos", "mvps" }
		local known: { [string]: boolean } = {
			styleTouches = true,
			items = true,
			powers = true,
			bestStreak = true,
			level = true,
			carsOwned = true,
			evolvedCars = true,
			fusedCars = true,
			loginStreak = true,
			matchGoals = true,
			cleanSheetWin = true,
			comebackWin = true,
		}
		for _, name in stats do
			known[name] = true
		end
		for _, def in Achievements.List do
			expect.falsy(seen[def.Id], `{def.Id} is listed twice`)
			seen[def.Id] = true
			expect.truthy(known[def.Stat], `{def.Id} counts a known number ({def.Stat})`)
			expect.truthy(def.Target >= 1 and def.Reward > 0, `{def.Id} has a target and a reward`)
			expect.truthy(def.Name ~= "" and def.Text ~= "" and def.Emoji ~= "")
			expect.truthy(Achievements.get(def.Id) == def)
		end
		expect.atLeast(#Achievements.List, 20)
		expect.atMost(#CarCatalog.ordered(), 99) -- (the garage achievements count real cars)
	end)

	t.test("achievements finish once, when the numbers get there", function()
		local done: { [string]: boolean } = {}
		local view = Achievements.viewOf({ goals = 1, wins = 0 }, { pizza = true }, {}, 1, 0)
		local finished = Achievements.newlyDone(done, view)
		local ids: { [string]: boolean } = {}
		for _, def in finished do
			ids[def.Id] = true
		end
		expect.truthy(ids.first_goal)
		expect.falsy(ids.first_win)
		done.first_goal = true
		for _, def in Achievements.newlyDone(done, view) do
			expect.truthy(def.Id ~= "first_goal", "not twice")
		end
		-- One match's numbers.
		view.matchGoals = 3
		view.comebackWin = 1
		local matchIds: { [string]: boolean } = {}
		for _, def in Achievements.newlyDone(done, view) do
			matchIds[def.Id] = true
		end
		expect.truthy(matchIds.hat_trick)
		expect.truthy(matchIds.comeback)
		expect.falsy(matchIds.clean_sheet)
		local progress, target = Achievements.progress(Achievements.get("saves_25") :: any, { saves = 400 })
		expect.equal(progress, target, "progress stops at the target")
	end)

	t.test("the garage counts cars, evolutions and fusions", function()
		local owned: { [string]: boolean } = {}
		local stage: { [string]: number } = {}
		for _, def in CarCatalog.ordered() do
			owned[def.Id] = true
		end
		local fusions = 0
		for _, def in CarCatalog.ordered() do
			if def.Fusion then
				fusions += 1
			end
		end
		stage.pizza = GameConfig.Evolution.Stages
		local view = Achievements.viewOf({}, owned, stage, 7, 5000)
		expect.equal(view.carsOwned, #CarCatalog.ordered())
		expect.equal(view.fusedCars, fusions)
		expect.equal(view.evolvedCars, 1)
		expect.equal(view.loginStreak, 7)
		expect.equal(view.level, (Levels.levelFor(5000)))
	end)

	t.test("every title can be earned, and levels give the best one automatically", function()
		local ids: { [string]: boolean } = {}
		for _, title in Achievements.Titles do
			expect.falsy(ids[title.Id], `{title.Id} is listed twice`)
			ids[title.Id] = true
			expect.truthy(title.Level ~= nil or title.Achievement ~= nil, `{title.Id} can be earned`)
			expect.truthy(Achievements.titleText(title.Id) ~= "")
			expect.truthy(Achievements.howToUnlock(title.Id) ~= "")
		end
		expect.truthy(Achievements.ownsTitle(Achievements.DefaultTitle, 1, {}), "everyone has the first title")
		expect.equal(Achievements.levelTitle(1), Achievements.DefaultTitle)
		expect.equal(Achievements.levelTitle(10), "speedster")
		expect.equal(Achievements.levelTitle(999), "legend")
		expect.falsy(Achievements.ownsTitle("saves_25", 99, {}))
		expect.truthy(Achievements.ownsTitle("saves_25", 1, { saves_25 = true }))
		expect.falsy(Achievements.ownsTitle("speedster", 9, {}))
		expect.truthy(Achievements.ownsTitle("speedster", 10, {}))
		expect.falsy(Achievements.ownsTitle("nope", 99, {}))
		expect.equal(Achievements.titleText("nope"), "")
	end)
end
