-- Builds the real stadium parts (with Lune's Roblox instances) and checks they line up with the math shape
-- the ball uses, so the ball never bounces off thin air or sinks into a ramp.
local roblox = require("@lune/roblox")

local dataModel = roblox.Instance.new("DataModel")
local fakeReplicatedStorage = {
	WaitForChild = function(_, name: string)
		assert(name == "Shared", `unexpected WaitForChild({name})`)
		return Shared
	end,
}
harness.globals.workspace = dataModel:GetService("Workspace")
harness.globals.game = {
	GetService = function(_, name: string)
		if name == "ReplicatedStorage" then
			return fakeReplicatedStorage
		end
		return dataModel:GetService(name)
	end,
}

local ArenaBuilder = harness.require(Server.Arena.ArenaBuilder)
local GameConfig = require(Shared.Config.GameConfig)

return function(t)
	local expect = t.expect
	local arenaFolder, shape = ArenaBuilder.build()

	local function parts(name: string?)
		local list = {}
		for _, d in arenaFolder:GetDescendants() do
			if d:IsA("BasePart") and (name == nil or d.Name == name) then
				table.insert(list, d)
			end
		end
		return list
	end

	t.test("builds a solid arena", function()
		local all = parts()
		expect.atLeast(#all, 100)
		for _, part in all do
			expect.truthy(part.Anchored, `{part.Name} must be anchored`)
			local p = part.CFrame.Position
			expect.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z, `{part.Name} has a NaN position`)
		end
	end)

	t.test("every ramp strip lies on the curved surface the ball uses", function()
		local ramps = parts("Ramp")
		expect.equal(#ramps, #shape.ramps * GameConfig.Arena.CurveSegments)
		for _, part in ramps do
			local cf = part.CFrame
			local surfaceCentre = cf * Vector3.new(0, part.Size.Y / 2, 0)
			local normal, depth = shape:deepestContact(surfaceCentre, 0.3)
			assert(normal, `ramp strip at {surfaceCentre} is floating in the air`)
			expect.atLeast(depth, 0.1, `ramp strip at {surfaceCentre} sits off the curve`)
			expect.atMost(depth, 0.45, `ramp strip at {surfaceCentre} is buried in the curve`)
			expect.atLeast(normal:Dot(cf.UpVector), 0.9, `ramp strip at {surfaceCentre} faces the wrong way`)
		end
	end)

	t.test("floor top is at height 0", function()
		for _, part in parts("Floor") do
			expect.near(part.CFrame.Position.Y + part.Size.Y / 2, 0, 1e-4)
		end
	end)

	local function corners(part: BasePart): { Vector3 }
		local list = {}
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(list, part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				end
			end
		end
		return list
	end

	t.test("side walls' inner faces match the arena edges", function()
		local checked = 0
		for _, name in { "Wall", "Boards" } do
			for _, part in parts(name) do
				local centre = part.CFrame.Position
				if math.abs(centre.Z) < 70 and math.abs(centre.X) > 100 then
					local nearest = math.huge
					for _, corner in corners(part) do
						nearest = math.min(nearest, math.abs(corner.X))
					end
					expect.near(nearest, GameConfig.Arena.Width / 2, 1e-3)
					checked += 1
				end
			end
		end
		expect.atLeast(checked, 6)
	end)

	t.test("no solid part pokes into the playing space", function()
		for _, part in parts() do
			for _, corner in corners(part) do
				expect.falsy(shape:contains(corner, 0.02), `{part.Name} corner {corner} sticks into the field`)
			end
		end
	end)

	t.test("the goal mouth is clear of parts", function()
		local halfGoal = GameConfig.Arena.GoalWidth / 2
		for _, part in parts() do
			local cf, size = part.CFrame, part.Size
			for _, probe in
				{
					Vector3.new(0, 10, GameConfig.Arena.Length / 2 + 2),
					Vector3.new(halfGoal - 7, 20, -GameConfig.Arena.Length / 2 - 5),
				}
			do
				local localPoint = cf:PointToObjectSpace(probe)
				local inside = math.abs(localPoint.X) < size.X / 2
					and math.abs(localPoint.Y) < size.Y / 2
					and math.abs(localPoint.Z) < size.Z / 2
				expect.falsy(inside, `{part.Name} blocks the goal mouth at {probe}`)
			end
		end
	end)
end
