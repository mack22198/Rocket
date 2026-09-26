-- The menu showroom: its polished-floor "reflection" really is a mirror image, every part of the room gets
-- one, and the cars on the turntable stand on the floor with their reflections touching them from below.
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

local ShowroomBuilder = harness.require(harness.Client.Showroom.ShowroomBuilder)
local CarCatalog = require(Shared.Config.CarCatalog)

return function(t)
	local expect = t.expect

	local function determinant(cf: CFrame): number
		return cf.XVector:Dot(cf.YVector:Cross(cf.ZVector))
	end

	t.test("a reflection is a proper rotation that mirrors every corner", function()
		local floorY = 1
		local cf = CFrame.new(3, 7, -2) * CFrame.Angles(0.4, 1.1, -0.3)
		local mirrored = ShowroomBuilder.reflect(cf, floorY)
		expect.near(determinant(mirrored), 1, 1e-5)
		local half = Vector3.new(2, 3, 4) / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = cf * (half * Vector3.new(sx, sy, sz))
					local image = Vector3.new(corner.X, 2 * floorY - corner.Y, corner.Z)
					-- The copy's own X axis is flipped, so this corner is its (-x, y, z) corner.
					local copyCorner = mirrored * (half * Vector3.new(-sx, sy, sz))
					expect.near((copyCorner - image).Magnitude, 0, 1e-4)
				end
			end
		end
		local back = ShowroomBuilder.reflect(mirrored, floorY)
		expect.near((back.Position - cf.Position).Magnitude, 0, 1e-5)
	end)

	t.test("every part above the floor has a reflection below it", function()
		local showroom = ShowroomBuilder.build()
		local room = showroom.folder:FindFirstChild("Room")
		local reflection = showroom.folder:FindFirstChild("Reflection")
		assert(room and reflection, "the showroom has a room and a reflection")
		local above, below = 0, 0
		for _, d in room:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("NoMirror") ~= true then
				above += 1
			end
		end
		for _, d in reflection:GetChildren() do
			if d:IsA("BasePart") then
				below += 1
				expect.truthy(
					d.CFrame.Position.Y <= showroom.origin.Y + 0.01,
					`{d.Name}'s reflection is above the floor`
				)
				expect.falsy(d:FindFirstChildWhichIsA("SurfaceGui"), "reflections don't carry text")
			end
		end
		expect.equal(below, above)
		expect.atLeast(#showroom.rings, 40)
	end)

	t.test("cars stand on the floor, touching their reflections", function()
		local showroom = ShowroomBuilder.build()
		local floorY = showroom.origin.Y
		for _, def in CarCatalog.ordered() do
			local display = ShowroomBuilder.display(showroom, def, 2, Color3.new(1, 1, 1))
			display.place(0.7, 0)
			local lowest, highest = math.huge, -math.huge
			for _, d in display.car:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Wheel" then
					lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
				end
			end
			for _, d in display.reflection:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Wheel" then
					highest = math.max(highest, d.CFrame.Position.Y + d.Size.Y / 2)
				end
			end
			if lowest < math.huge then
				expect.near(lowest, floorY, 0.02, `{def.Id}'s wheels touch the floor`)
				expect.near(highest, floorY, 0.02, `{def.Id}'s reflected wheels touch the floor`)
			end
			display.destroy()
		end
	end)
end
