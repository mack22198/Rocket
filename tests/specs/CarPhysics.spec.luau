-- Drives a car on a flat floor with a tiny stand-in physics engine (gravity, integration, floor collision)
-- to check the handling does what the controls say.
local CarPhysics = require(Shared.Physics.CarPhysics)
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local cfg = GameConfig.Car
	local def = CarCatalog.get("pizza")
	assert(def)
	local hitbox = def.Hitbox
	local half = hitbox / 2
	local WORLD_GRAVITY = 196.2
	local DT = 1 / 60

	local function input(overrides: { [string]: any }?)
		local i = { throttle = 0, steer = 0, roll = 0, boost = false, jump = false }
		for k, v in overrides or {} do
			i[k] = v
		end
		return i
	end

	local function rotationOnly(cf: CFrame): CFrame
		return CFrame.fromMatrix(Vector3.zero, cf.RightVector, cf.UpVector)
	end

	-- Returns a sim object; call sim.run(seconds, inputFn) to advance.
	local function newSim(startCFrame: CFrame?, startVelocity: Vector3?)
		local sim = {
			cframe = startCFrame or CFrame.new(0, half.Y + cfg.RideHeight, 0),
			velocity = startVelocity or Vector3.zero,
			angular = Vector3.zero,
			state = CarPhysics.newState(),
			hasBoost = true,
			assist = nil :: CarPhysics.Assist?,
			lastResult = nil :: any,
		}
		local mounts = CarPhysics.wheelMounts(hitbox)
		local reach = CarPhysics.rayLength(cfg)

		local function probe()
			local hits = {}
			local down = -sim.cframe.UpVector
			for _, mount in mounts do
				local origin = sim.cframe:PointToWorldSpace(mount)
				if down.Y < -0.2 then
					local distance = origin.Y / -down.Y
					if distance >= 0 and distance <= reach then
						table.insert(hits, { distance = distance, normal = Vector3.yAxis })
					end
				end
			end
			return CarPhysics.groundFromHits(cfg, hits)
		end

		function sim.step(i)
			local result = CarPhysics.step({
				config = cfg,
				stats = def.Stats,
				state = sim.state,
				input = i,
				cframe = sim.cframe,
				velocity = sim.velocity,
				angularVelocity = sim.angular,
				ground = probe(),
				dt = DT,
				worldGravity = WORLD_GRAVITY,
				hasBoost = sim.hasBoost,
				assist = sim.assist,
			})
			sim.lastResult = result
			if result.teleport then
				sim.cframe = result.teleport
			end
			local v = result.velocity + Vector3.new(0, -WORLD_GRAVITY * DT, 0)
			local w = result.angularVelocity
			local rot = rotationOnly(sim.cframe)
			if w.Magnitude > 1e-6 then
				rot = CFrame.fromAxisAngle(w.Unit, w.Magnitude * DT) * rot
			end
			local cf = CFrame.new(sim.cframe.Position + v * DT) * rot
			-- Crude floor collision for the chassis box.
			local lowest = math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						lowest =
							math.min(lowest, cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)).Y)
					end
				end
			end
			if lowest < 0 then
				cf = cf + Vector3.new(0, -lowest, 0)
				if v.Y < 0 then
					v = Vector3.new(v.X, 0, v.Z)
				end
			end
			sim.cframe = cf
			sim.velocity = v
			sim.angular = w
		end

		function sim.run(seconds: number, inputFn: ((number) -> any)?)
			local steps = math.floor(seconds / DT + 0.5)
			for n = 1, steps do
				sim.step(if inputFn then inputFn(n * DT) else input())
			end
		end

		return sim
	end

	local function flatSpeed(v: Vector3): number
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end

	t.test("a parked car settles at its ride height", function()
		local sim = newSim()
		sim.run(2)
		local bottomGap = sim.cframe.Position.Y - half.Y
		expect.near(bottomGap, cfg.RideHeight - cfg.Gravity / cfg.SpringStrength, 0.15)
		expect.atMost(sim.velocity.Magnitude, 0.5)
		expect.truthy(sim.state.grounded)
	end)

	t.test("full throttle reaches top speed but not beyond", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(5, function()
			return input({ throttle = 1 })
		end)
		local speed = flatSpeed(sim.velocity)
		expect.atLeast(speed, cfg.MaxSpeed * 0.95)
		expect.atMost(speed, cfg.MaxSpeed * 1.01)
		-- It drove forward (-Z is the car's front at the start).
		expect.truthy(sim.cframe.Position.Z < -200)
	end)

	t.test("letting go of throttle coasts to a stop", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(2, function()
			return input({ throttle = 1 })
		end)
		sim.run(8)
		expect.atMost(flatSpeed(sim.velocity), 0.5)
	end)

	t.test("steering right turns the car to the right", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(1, function()
			return input({ throttle = 1, steer = 1 })
		end)
		expect.atLeast(sim.cframe.LookVector.X, 0.3)
	end)

	t.test("a car can't spin in place without moving", function()
		local sim = newSim()
		sim.run(0.5)
		local before = sim.cframe.LookVector
		sim.run(1, function()
			return input({ steer = 1 })
		end)
		expect.atLeast(sim.cframe.LookVector:Dot(before), 0.99)
	end)

	t.test("reverse drives backwards slowly", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(4, function()
			return input({ throttle = -1 })
		end)
		expect.truthy(sim.cframe.Position.Z > 20)
		expect.atMost(flatSpeed(sim.velocity), cfg.MaxReverseSpeed * 1.01)
	end)

	t.test("boosting goes faster than top speed", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(3, function()
			return input({ throttle = 1, boost = true })
		end)
		local speed = sim.velocity.Magnitude
		expect.atLeast(speed, cfg.MaxSpeed + 30)
		expect.atMost(speed, cfg.MaxBoostedSpeed + 0.01)
	end)

	t.test("no boost in the tank means no boost", function()
		local sim = newSim()
		sim.hasBoost = false
		sim.run(0.5)
		sim.run(3, function()
			return input({ throttle = 1, boost = true })
		end)
		expect.atMost(flatSpeed(sim.velocity), cfg.MaxSpeed * 1.01)
	end)

	t.test("jumping launches the car into the air", function()
		local sim = newSim()
		sim.run(1)
		local restY = sim.cframe.Position.Y
		local peak = restY
		for n = 1, 90 do
			sim.step(input({ jump = n <= 3 }))
			peak = math.max(peak, sim.cframe.Position.Y)
		end
		local expected = (cfg.JumpSpeed ^ 2) / (2 * cfg.Gravity)
		expect.atLeast(peak - restY, expected * 0.7)
		expect.atMost(peak - restY, expected * 1.3)
	end)

	t.test("a double jump goes higher than a single jump", function()
		local function peakWith(secondJump: boolean): number
			local sim = newSim()
			sim.run(1)
			local restY = sim.cframe.Position.Y
			local peak = restY
			for n = 1, 120 do
				local pressed = n <= 3 or (secondJump and n >= 20 and n <= 22)
				sim.step(input({ jump = pressed }))
				peak = math.max(peak, sim.cframe.Position.Y)
			end
			return peak - restY
		end
		expect.atLeast(peakWith(true), peakWith(false) + 3)
	end)

	t.test("dodging forward adds a burst of speed and flips the car", function()
		local sim = newSim()
		sim.run(1)
		for n = 1, 20 do
			sim.step(input({ jump = n <= 3 }))
		end
		local before = flatSpeed(sim.velocity)
		sim.step(input({ jump = true, throttle = 1 }))
		expect.truthy(sim.lastResult.dodged)
		expect.atLeast(flatSpeed(sim.velocity) - before, cfg.DodgeSpeed * 0.9)
		sim.run(0.2, function()
			return input({ throttle = 1 })
		end)
		expect.atMost(sim.cframe.LookVector.Y, -0.3) -- nose going down: a front flip
	end)

	t.test("driving help: jumping under a ball in the air leans toward it", function()
		local function sideways(withHelp: boolean): number
			local sim = newSim()
			sim.run(1)
			local ball = sim.cframe.Position + Vector3.new(12, 14, -6)
			sim.assist = if withHelp then { ball = ball, level = true } else nil
			sim.step(input({ jump = true }))
			return sim.velocity.X
		end
		expect.near(sideways(false), 0, 0.5)
		expect.atLeast(sideways(true), 5)
	end)

	t.test("driving help: the second jump flips into a nearby ball", function()
		local sim = newSim()
		sim.run(1)
		sim.assist = { ball = nil, level = true }
		for n = 1, 20 do
			sim.step(input({ jump = n <= 3 }))
		end
		-- The ball is ahead and to the right. No direction held: the flip goes at the ball anyway.
		sim.assist = { ball = sim.cframe.Position + Vector3.new(8, 2, -8), level = true }
		local before = sim.velocity
		sim.step(input({ jump = true }))
		expect.truthy(sim.lastResult.dodged)
		local change = sim.velocity - before
		expect.truthy(change.X > 10 and change.Z < -10, "toward the ball")
		-- Without driving help, the same second jump is just a double jump.
		local plain = newSim()
		plain.run(1)
		for n = 1, 20 do
			plain.step(input({ jump = n <= 3 }))
		end
		plain.step(input({ jump = true }))
		expect.falsy(plain.lastResult.dodged)
	end)

	t.test("driving help: holding the throttle in the air keeps the car level", function()
		local sim = newSim(CFrame.new(0, 60, 0))
		sim.assist = { ball = nil, level = true }
		sim.run(0.5, function()
			return input({ throttle = 1 })
		end)
		expect.atLeast(sim.cframe.LookVector.Y, -0.1)
		-- A real pitch control (a gamepad stick) still tips the nose.
		local stick = newSim(CFrame.new(0, 60, 0))
		stick.assist = { ball = nil, level = true }
		stick.run(0.5, function()
			return input({ throttle = 1, pitch = 1 })
		end)
		expect.atMost(stick.cframe.LookVector.Y, -0.3)
	end)

	t.test("in the air, pushing forward tips the nose down", function()
		local sim = newSim(CFrame.new(0, 60, 0))
		sim.run(0.5, function()
			return input({ throttle = 1 })
		end)
		expect.atMost(sim.cframe.LookVector.Y, -0.3)
	end)

	t.test("air roll rolls the car", function()
		local sim = newSim(CFrame.new(0, 60, 0))
		sim.run(0.3, function()
			return input({ roll = 1 })
		end)
		expect.atMost(sim.cframe.RightVector.Y, -0.3) -- rolling right drops the right side
	end)

	t.test("hands off in the air, a tipped car turns back upright", function()
		local tipped = CFrame.new(0, 80, 0) * CFrame.Angles(math.rad(50), 0, math.rad(40))
		local sim = newSim(tipped)
		sim.run(1.2)
		expect.atLeast(sim.cframe.UpVector.Y, 0.93)
		-- Even upside down.
		sim = newSim(CFrame.new(0, 120, 0) * CFrame.Angles(0, 0, math.pi))
		sim.run(2)
		expect.atLeast(sim.cframe.UpVector.Y, 0.8)
	end)

	t.test("a car stuck on its roof flips back onto its wheels", function()
		local upsideDown = CFrame.new(0, half.Y + 0.1, 0) * CFrame.Angles(0, 0, math.pi)
		local sim = newSim(upsideDown)
		sim.run(2.5)
		expect.atLeast(sim.cframe.UpVector.Y, 0.9)
	end)

	t.test("a banana spin-out takes over the car, then hands it back", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(1.5, function()
			return input({ throttle = 1 })
		end)
		CarPhysics.applyEffect(sim.state, "spin", 1.2, 1)
		local before = sim.cframe.LookVector
		local turned = 0
		sim.run(1.2, function()
			local look = sim.cframe.LookVector
			turned += math.acos(math.clamp(look:Dot(before), -1, 1))
			before = look
			return input({ throttle = 1, steer = -1 }) -- ignored while spinning
		end)
		expect.atLeast(turned, math.pi * 2, "the car spins round at least once")
		expect.near(sim.state.spinTimer, 0, 1e-6)
		-- Control is back: steering right turns right again.
		sim.run(2, function()
			return input({ throttle = 1 })
		end)
		local heading = sim.cframe.LookVector
		sim.run(0.6, function()
			return input({ throttle = 1, steer = 1 })
		end)
		expect.truthy(heading:Cross(sim.cframe.LookVector).Y < -0.2, "steers right after the spin")
	end)

	t.test("after a dash the car eases back down to its top speed", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(4, function()
			return input({ throttle = 1 })
		end)
		local top = cfg.MaxSpeed * def.Stats.Speed
		expect.near(flatSpeed(sim.velocity), top, top * 0.05, "flat out without boost")
		sim.velocity += sim.cframe.LookVector * 50 -- a Nitro Rocket
		sim.run(0.3, function()
			return input({ throttle = 1 })
		end)
		expect.atLeast(flatSpeed(sim.velocity), top + 30, "still flying just after")
		sim.run(3, function()
			return input({ throttle = 1 })
		end)
		expect.atMost(flatSpeed(sim.velocity), top * 1.03, "back to top speed")
	end)

	t.test("cheese slows a car right down, and it speeds back up after", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(4, function()
			return input({ throttle = 1, boost = true })
		end)
		expect.atLeast(flatSpeed(sim.velocity), cfg.MaxSpeed)
		sim.run(2, function()
			CarPhysics.applyEffect(sim.state, "slow", 0.5)
			return input({ throttle = 1, boost = true })
		end)
		local slowCap = cfg.MaxSpeed * def.Stats.Speed * cfg.SlowFactor
		expect.atMost(flatSpeed(sim.velocity), slowCap * 1.05, "stuck in the goo")
		expect.falsy(sim.lastResult.boosting, "no boosting out of the cheese")
		sim.run(4, function()
			return input({ throttle = 1 })
		end)
		expect.atLeast(flatSpeed(sim.velocity), cfg.MaxSpeed * 0.95)
	end)

	t.test("a frozen car skids to a stop and ignores the controls", function()
		local sim = newSim()
		sim.run(0.5)
		sim.run(2, function()
			return input({ throttle = 1 })
		end)
		CarPhysics.applyEffect(sim.state, "freeze", 2.5)
		sim.run(2, function()
			return input({ throttle = 1, boost = true, jump = true })
		end)
		expect.atMost(flatSpeed(sim.velocity), 2, "stopped")
		expect.truthy(sim.state.grounded, "didn't jump")
		CarPhysics.clearEffects(sim.state)
		sim.run(2, function()
			return input({ throttle = 1 })
		end)
		expect.atLeast(flatSpeed(sim.velocity), 40, "drives again once thawed")
	end)
end
