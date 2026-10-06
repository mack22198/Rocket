-- Demolitions: only a full-boost smash into the other team counts, and bots leave brand-new players alone.
local Demolition = require(Shared.Match.Demolition)
local GameConfig = require(Shared.Config.GameConfig)
local Rewards = require(Shared.Config.Rewards)

return function(t)
	local expect = t.expect
	local fast = GameConfig.Bump.DemoSpeed + 5
	local veteran = GameConfig.Bots.RookieMatches

	local function player(team: string, matches: number?): Demolition.Side
		return { team = team, bot = false, matches = matches or veteran }
	end
	local function bot(team: string): Demolition.Side
		return { team = team, bot = true, matches = 0 }
	end

	t.test("only boosting is fast enough", function()
		local cfg = GameConfig.Bump
		expect.truthy(cfg.DemoSpeed > GameConfig.Car.MaxSpeed, "driving flat out without boost isn't enough")
		expect.truthy(cfg.DemoSpeed < GameConfig.Car.MaxBoostedSpeed - 20, "boosting gets you there")
		expect.truthy(cfg.DemoSpeed > cfg.BigBumpSpeed)
		expect.truthy(cfg.DemoRespawn >= 1 and cfg.DemoRespawn <= 3, "back in the game quickly")
	end)

	t.test("a fast smash into the other team is a demolition", function()
		expect.truthy(Demolition.check(player("Blue"), player("Orange"), fast))
		expect.falsy(Demolition.check(player("Blue"), player("Orange"), GameConfig.Bump.DemoSpeed - 1))
		expect.truthy(Demolition.check(player("Blue"), bot("Orange"), fast))
		expect.truthy(Demolition.check(bot("Blue"), bot("Orange"), fast))
	end)

	t.test("never your own team", function()
		expect.falsy(Demolition.check(player("Blue"), player("Blue"), fast * 2))
		expect.falsy(Demolition.check(bot("Orange"), player("Orange"), fast * 2))
	end)

	t.test("bots leave players in their first few matches alone", function()
		expect.falsy(Demolition.check(bot("Blue"), player("Orange", 0), fast))
		expect.falsy(Demolition.check(bot("Blue"), player("Orange", veteran - 1), fast))
		expect.truthy(Demolition.check(bot("Blue"), player("Orange", veteran), fast))
		expect.truthy(Demolition.check(player("Blue"), player("Orange", 0), fast), "players can still get each other")
	end)

	t.test("demolitions pay a little Scrap", function()
		local stats = Rewards.emptyStats()
		stats.demos = 2
		local summary = Rewards.compute(stats, "Loss", false)
		expect.equal(summary.total, Rewards.Scrap.Played + 2 * Rewards.Scrap.Demo)
		expect.equal(summary.lines[2].label, "Demolitions x2")
	end)
end
