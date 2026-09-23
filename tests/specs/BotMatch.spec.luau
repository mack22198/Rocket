-- End-to-end check of the gameplay logic without Roblox: six bots drive with CarPhysics, touch the ball with
-- HitModel, the ball moves with BallSim, and goals are detected by ArenaShape. If the bots can't find the ball
-- or never score, something in that chain is broken.
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local BotBrain = require(Shared.Bots.BotBrain)
local CarCatalog = require(Shared.Config.CarCatalog)
local CarPhysics = require(Shared.Physics.CarPhysics)
local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)
local MathUtil = require(Shared.Util.MathUtil)
local Sim = harness.loadFile("tests/sim.luau")(Shared)

return function(t)
	local expect = t.expect

	t.test("six bots play a match: they chase, touch and score", function()
		local arena = ArenaShape.new(GameConfig.Arena)
		local ballCfg = GameConfig.Ball
		local dt = ballCfg.FixedStep
		local THINK = 1 / 8
		local SECONDS = 75
		local KICKOFF = { Vector2.new(-48, 70), Vector2.new(48, 70), Vector2.new(0, 125) }

		local ball = BallSim.newState(Vector3.new(0, ballCfg.Radius, 0))
		local bots = {}
		for _, team in { "Blue", "Orange" } do
			local side = GameConfig.Teams[team].DefendsSide
			for slot = 1, 3 do
				local ids = GameConfig.Bots.CarIds
				local def = CarCatalog.get(ids[(slot + (if team == "Blue" then 0 else 3) - 1) % #ids + 1])
				table.insert(bots, {
					key = `{team}{slot}`,
					team = team,
					side = side,
					slot = slot,
					def = def,
					car = nil,
					memory = BotBrain.newMemory(),
					input = CarPhysics.NoInput,
					lastHit = -math.huge,
					boost = GameConfig.Car.StartingBoost,
				})
			end
		end

		local function kickoff()
			ball = BallSim.newState(Vector3.new(0, ballCfg.Radius, 0))
			for _, bot in bots do
				local spot = KICKOFF[bot.slot]
				local position = Vector3.new(spot.X * bot.side, bot.def.Hitbox.Y / 2 + 1.2, spot.Y * bot.side)
				bot.car =
					Sim.newCar(bot.def, MathUtil.lookAlong(position, Vector3.new(-position.X, 0, -position.Z)), arena)
				bot.memory = BotBrain.newMemory()
				bot.boost = GameConfig.Car.StartingBoost
			end
		end
		kickoff()

		local function forecast()
			local samples = { ball.position }
			BallSim.simulate(arena, ballCfg, ball, 1.6, function(s, elapsed)
				local index = math.floor(elapsed / 0.05 + 0.5)
				if index == #samples and math.abs(elapsed - index * 0.05) < dt / 2 then
					samples[index + 1] = s.position
				end
				return false
			end)
			return function(seconds: number): Vector3
				local f = math.clamp(seconds / 0.05, 0, #samples - 1)
				local i = math.floor(f)
				local a = samples[i + 1]
				local b = samples[math.min(i + 2, #samples)] or a
				return a:Lerp(b, f - i)
			end
		end

		local touches, goals = 0, { Blue = 0, Orange = 0 }
		local time, thinkTimer = 0, 0
		local lastAttacker = {}
		for _ = 1, math.floor(SECONDS / dt) do
			time += dt
			thinkTimer += dt
			if thinkTimer >= THINK then
				thinkTimer = 0
				local predict = forecast()
				for _, team in { "Blue", "Orange" } do
					local members = {}
					for _, bot in bots do
						if bot.team == team then
							table.insert(members, { key = bot.key, position = bot.car.cframe.Position })
						end
					end
					local side = GameConfig.Teams[team].DefendsSide
					local roles =
						BotBrain.assignRoles(members, ball.position, side, arena.halfLength, lastAttacker[team])
					for key, role in roles do
						if role == "attack" then
							lastAttacker[team] = key
						end
					end
					for _, bot in bots do
						if bot.team == team then
							bot.input = BotBrain.decide({
								carCFrame = bot.car.cframe,
								carVelocity = bot.car.velocity,
								grounded = bot.car.state.grounded,
								boost = bot.boost,
								megaReady = false,
								ballPosition = ball.position,
								ballVelocity = ball.velocity,
								predict = predict,
								defendsSide = side,
								role = roles[bot.key] or "support",
								skill = GameConfig.Bots.Skill,
								arena = arena,
								aimOffset = Vector3.zero,
							}, bot.memory, THINK)
						end
					end
				end
			end

			for _, bot in bots do
				bot.car.hasBoost = bot.boost > 0
				bot.car.step(bot.input, dt)
				if bot.car.lastResult.boosting then
					bot.boost = math.max(0, bot.boost - GameConfig.Car.BoostDrainPerSecond * dt)
				end
				bot.boost = math.min(100, bot.boost + 8 * dt) -- stands in for the boost pads
			end

			BallSim.step(arena, ballCfg, ball, dt)
			for _, bot in bots do
				if time - bot.lastHit >= GameConfig.Hit.Cooldown then
					local contact =
						HitModel.findContact(bot.car.cframe, bot.def.Hitbox / 2, ball.position, ballCfg.Radius)
					if contact then
						local result = HitModel.resolve(
							GameConfig.Hit,
							bot.car.cframe,
							bot.car.velocity,
							ball.position,
							ball.velocity,
							ballCfg.Radius,
							contact,
							false,
							ballCfg.MaxSpeed
						)
						ball.position = result.ballPosition
						ball.velocity = result.ballVelocity
						bot.car.velocity += result.carVelocityChange
						bot.lastHit = time
						touches += 1
					end
				end
			end

			local side = arena:goalSide(ball.position, ballCfg.Radius)
			if side then
				local scorer = if side == GameConfig.Teams.Blue.DefendsSide then "Orange" else "Blue"
				goals[scorer] += 1
				kickoff()
			end
		end

		print(`    bot match: {touches} touches, Blue {goals.Blue} - {goals.Orange} Orange in {SECONDS}s`)
		expect.atLeast(touches, 25, `bots barely touched the ball ({touches} touches)`)
		expect.atLeast(goals.Blue + goals.Orange, 1, "nobody scored in a whole match")
	end)
end
