-- Goal replays: they fit inside the goal celebration, the clip plays from start to finish without jumping
-- backwards, the shot itself is in slow motion, and frames are picked and blended correctly.
local GameConfig = require(Shared.Config.GameConfig)
local Replay = require(Shared.Match.Replay)

return function(t)
	local expect = t.expect

	local function frames(times: { number }): { Replay.Frame }
		local list = {}
		for _, time in times do
			table.insert(list, { t = time, ball = Vector3.new(time * 10, 6, 0), cars = {}, boosting = {} })
		end
		return list
	end

	t.test("a replay finishes before the next kickoff", function()
		local total = Replay.StartDelay + Replay.duration(Replay.ClipLength) + 0.4
		expect.atMost(total, GameConfig.Match.GoalCelebration)
	end)

	t.test("the clip plays through once, in order, ending exactly on the goal", function()
		local length = Replay.ClipLength
		local duration = Replay.duration(length)
		local previous = -1
		for i = 0, 200 do
			local shown = Replay.clipTime(duration * i / 200, length)
			expect.truthy(shown >= previous, "never jumps backwards")
			previous = shown
		end
		expect.near(Replay.clipTime(0, length), 0, 1e-9)
		expect.near(Replay.clipTime(duration, length), length, 1e-6)
		expect.near(Replay.clipTime(duration + 5, length), length, 1e-9)
	end)

	t.test("the shot plays in slow motion", function()
		local length = Replay.ClipLength
		local duration = Replay.duration(length)
		local early = Replay.clipTime(0.6, length) - Replay.clipTime(0.5, length)
		local late = Replay.clipTime(duration - 0.1, length) - Replay.clipTime(duration - 0.2, length)
		expect.truthy(late < early * 0.6, "the last moments move slower than the build-up")
		expect.atMost(late / 0.1, 0.5)
	end)

	t.test("frames are picked and blended by time", function()
		local list = frames({ 0, 1, 2, 3 })
		local a, b, alpha = Replay.sample(list, 1.25)
		expect.equal(a.t, 1)
		expect.equal(b.t, 2)
		expect.near(alpha, 0.25, 1e-9)
		local first, _, before = Replay.sample(list, -1)
		expect.equal(first.t, 0)
		expect.equal(before, 0)
		local last, lastToo = Replay.sample(list, 9)
		expect.equal(last.t, 3)
		expect.equal(lastToo.t, 3)
	end)

	t.test("trimming keeps just the last few seconds", function()
		local list = frames({ 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5 })
		local clip = Replay.trim(list, 3)
		expect.equal(clip[#clip].t, 5)
		expect.atMost(clip[1].t, 2)
		expect.truthy(clip[2].t > 2, "only one frame from before the cut")
		expect.equal(#Replay.trim({}, 3), 0)
	end)
end
