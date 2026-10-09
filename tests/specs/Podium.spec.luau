-- The winners' podium: the right cars on the right steps, standing on them (not floating or sunk), the MVP
-- highest, and a camera that stays in front of the stage looking at it.
local fakeReplicatedStorage = {
	WaitForChild = function(_, name: string)
		assert(name == "Shared", `unexpected WaitForChild({name})`)
		return Shared
	end,
}
harness.globals.game = {
	GetService = function(_, name: string)
		assert(name == "ReplicatedStorage", `unexpected GetService({name})`)
		return fakeReplicatedStorage
	end,
}

local PodiumBuilder = harness.require(harness.Client.Showroom.PodiumBuilder)

return function(t)
	local expect = t.expect

	local entries = {
		{ name = "Player1", team = "Blue", carId = "monster", stage = 3, points = 420 },
		{ name = "TurboTaco9", team = "Orange", carId = "ufo", stage = 1, points = 250 },
		{ name = "PixelPanda22", team = "Blue", carId = "kart", stage = 4, points = 180 },
	}

	local function lowestWheel(car: Model): number
		local lowest = math.huge
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Wheel" then
				lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
			end
		end
		return lowest
	end

	t.test("each car stands on its own step, MVP on top", function()
		local folder = Instance.new("Folder")
		local podium = PodiumBuilder.build(folder, entries)
		expect.equal(#podium.cars, 3)
		local heights = {}
		for rank, car in podium.cars do
			local step = PodiumBuilder.Steps[rank]
			local plate = podium.model:FindFirstChild(`Plate{rank}`)
			assert(plate and plate:IsA("BasePart"), "each step has a plate")
			local plateTop = plate.CFrame.Position.Y + plate.Size.Y / 2
			local wheel = lowestWheel(car)
			if wheel < math.huge then -- (the UFO hovers: it has no wheels)
				expect.near(wheel, plateTop, 0.05, `car {rank} rests on its step`)
			end
			local chassis = car.PrimaryPart :: BasePart
			expect.near(chassis.CFrame.Position.X, step.x, 0.01)
			heights[rank] = chassis.CFrame.Position.Y
			expect.truthy(chassis:FindFirstChild("PodiumTag") ~= nil, "name tag")
		end
		expect.truthy(heights[1] > heights[2] and heights[2] > heights[3], "1st above 2nd above 3rd")
	end)

	t.test("fewer than three players still makes a podium", function()
		local podium = PodiumBuilder.build(Instance.new("Folder"), { entries[1] })
		expect.equal(#podium.cars, 1)
	end)

	t.test("the camera stays in front of the stage, looking at it", function()
		for i = 0, 40 do
			local position, focus = PodiumBuilder.camera(i * 0.5)
			expect.truthy(position.Z < -PodiumBuilder.StageRadius * 0.9, "in front of the stage")
			expect.atLeast((position - focus).Magnitude, 25)
			expect.near(focus.X, 0, 1e-6)
		end
	end)
end
