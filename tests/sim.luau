-- A tiny stand-in for the Roblox physics engine, just enough to drive cars with CarPhysics in tests:
-- gravity, integration, a flat floor, and walls that keep cars inside the arena.
-- (The ball uses the real BallSim, which never needed Roblox physics in the first place.)

return function(Shared)
	local require = harness.require
	local CarPhysics = require(Shared.Physics.CarPhysics)
	local GameConfig = require(Shared.Config.GameConfig)

	local Sim = {}

	local WORLD_GRAVITY = 196.2
	local cfg = GameConfig.Car

	local function rotationOnly(cf: CFrame): CFrame
		return CFrame.fromMatrix(Vector3.zero, cf.RightVector, cf.UpVector)
	end

	function Sim.newCar(def, cframe: CFrame?, arena)
		local car = {
			def = def,
			hitbox = def.Hitbox,
			cframe = cframe or CFrame.new(0, def.Hitbox.Y / 2 + cfg.RideHeight, 0),
			velocity = Vector3.zero,
			angular = Vector3.zero,
			state = CarPhysics.newState(),
			hasBoost = true,
			lastResult = nil :: any,
		}
		local half = def.Hitbox / 2
		local mounts = CarPhysics.wheelMounts(def.Hitbox)
		local reach = CarPhysics.rayLength(cfg)

		local function probe()
			local hits = {}
			local down = -car.cframe.UpVector
			for _, mount in mounts do
				local origin = car.cframe:PointToWorldSpace(mount)
				if down.Y < -0.2 then
					local distance = origin.Y / -down.Y
					if distance >= 0 and distance <= reach then
						table.insert(hits, { distance = distance, normal = Vector3.yAxis })
					end
				end
			end
			return CarPhysics.groundFromHits(cfg, hits)
		end

		function car.step(input, dt: number)
			local result = CarPhysics.step({
				config = cfg,
				stats = def.Stats,
				state = car.state,
				input = input,
				cframe = car.cframe,
				velocity = car.velocity,
				angularVelocity = car.angular,
				ground = probe(),
				dt = dt,
				worldGravity = WORLD_GRAVITY,
				hasBoost = car.hasBoost,
			})
			car.lastResult = result
			if result.teleport then
				car.cframe = result.teleport
			end
			local v = result.velocity + Vector3.new(0, -WORLD_GRAVITY * dt, 0)
			local w = result.angularVelocity
			local rot = rotationOnly(car.cframe)
			if w.Magnitude > 1e-6 then
				rot = CFrame.fromAxisAngle(w.Unit, w.Magnitude * dt) * rot
			end
			local position = car.cframe.Position + v * dt
			-- Walls: keep the car's centre inside the arena (a little in from the real walls).
			if arena then
				for _, plane in arena.sidePlanes do
					local d = (position - plane.point):Dot(plane.normal)
					if d < half.Z then
						position += plane.normal * (half.Z - d)
						local into = v:Dot(plane.normal)
						if into < 0 then
							v -= plane.normal * into
						end
					end
				end
				local limit = arena.halfLength - half.Z
				if math.abs(position.Z) > limit and math.abs(position.X) > arena.goalHalfWidth - half.X then
					position = Vector3.new(position.X, position.Y, math.sign(position.Z) * limit)
					v = Vector3.new(v.X, v.Y, 0)
				end
			end
			local cf = CFrame.new(position) * rot
			-- Floor collision for the chassis box.
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
			car.cframe = cf
			car.velocity = v
			car.angular = w
		end

		return car
	end

	return Sim
end
