-- Easy steering: the car goes where the stick points on the screen.
local EasySteer = require(Shared.Cars.EasySteer)

return function(t)
	local expect = t.expect
	-- A camera behind a car that faces -Z, looking the same way (a little down). (Lune's CFrame.lookAt points the
	-- other way from Roblox's, so these are built from angles.)
	local car = CFrame.new(0, 2, 0)
	local camera = CFrame.new(0, 10, 20) * CFrame.Angles(math.rad(-20), 0, 0)

	t.test("pushing up drives straight ahead", function()
		local throttle, steer = EasySteer.input(Vector2.new(0, 1), car, camera)
		expect.near(throttle, 1, 1e-6)
		expect.near(steer, 0, 1e-3)
	end)

	t.test("pushing right turns right, left turns left", function()
		local throttle, steer = EasySteer.input(Vector2.new(1, 0), car, camera)
		expect.truthy(throttle > 0 and steer > 0.9)
		throttle, steer = EasySteer.input(Vector2.new(-0.5, 0.5), car, camera)
		expect.truthy(throttle > 0 and steer < -0.9)
	end)

	t.test("pulling back reverses", function()
		local throttle, steer = EasySteer.input(Vector2.new(0, -0.8), car, camera)
		expect.near(throttle, -0.8, 1e-6)
		expect.equal(steer, 0)
	end)

	t.test("the car follows the screen, not its own nose", function()
		-- The car faces right (+X) on screen. Pushing up (into the screen, -Z) means turning left.
		local sideways = CFrame.new(0, 2, 0) * CFrame.Angles(0, -math.pi / 2, 0) -- facing +X
		local throttle, steer = EasySteer.input(Vector2.new(0, 1), sideways, camera)
		expect.truthy(throttle > 0, "drives forward")
		expect.truthy(steer < -0.9, "turns left toward the top of the screen")
		-- Pushing right means carrying straight on.
		throttle, steer = EasySteer.input(Vector2.new(1, 0), sideways, camera)
		expect.near(steer, 0, 1e-3)
		-- Pushing up while the ball cam looks behind the car: turn around rather than reverse.
		local turnedAround = CFrame.new(0, 2, 0) * CFrame.Angles(0, math.pi, 0) -- facing +Z
		throttle = EasySteer.input(Vector2.new(0, 1), turnedAround, camera)
		expect.truthy(throttle > 0)
	end)

	t.test("a resting stick does nothing", function()
		local throttle, steer = EasySteer.input(Vector2.new(0.01, 0.01), car, camera)
		expect.equal(throttle, 0)
		expect.equal(steer, 0)
	end)
end
