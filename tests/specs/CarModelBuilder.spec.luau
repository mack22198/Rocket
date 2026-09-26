-- Builds every car with real (Lune) Roblox instances, which rejects unknown properties or bad values.
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)

return function(t)
	local expect = t.expect

	for _, def in CarCatalog.ordered() do
		t.test(`{def.Id} builds a driveable model`, function()
			local model = CarModelBuilder.build(def, { teamColor = Color3.fromRGB(255, 0, 0) })
			local chassis = model.PrimaryPart
			assert(chassis, "missing PrimaryPart")
			expect.equal(chassis.Name, "Chassis")
			expect.atMost((chassis.Size - def.Hitbox).Magnitude, 1e-3)
			expect.truthy(chassis.CanCollide)
			local parts, hubs, wheelParts = 0, 0, 0
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and child ~= chassis then
					parts += 1
					expect.truthy(child.Massless, `{child.Name} should be massless`)
					expect.falsy(child.CanCollide, `{child.Name} should not collide`)
					if child.Name == "WheelHub" then
						-- Wheels turn on a motor attached to the chassis.
						hubs += 1
						local motor = child:FindFirstChildOfClass("Motor6D")
						assert(motor, "wheel hub has no motor")
						expect.equal(motor.Part0, chassis)
						expect.equal(motor.Part1, child)
					else
						local weld = child:FindFirstChildOfClass("WeldConstraint")
						assert(weld, `{child.Name} is not welded`)
						local anchor = weld.Part0
						expect.truthy(
							anchor == chassis or (anchor ~= nil and anchor.Name == "WheelHub"),
							`{child.Name} is welded to {anchor}`
						)
						if anchor ~= chassis then
							wheelParts += 1
						end
					end
				end
			end
			expect.atLeast(parts, 8)
			if def.Id ~= "ufo" then
				expect.equal(hubs, 4, "four turning wheels")
				expect.atLeast(wheelParts, 12)
			end
			local exhaust = chassis:FindFirstChild("Exhaust")
			assert(exhaust, "missing exhaust attachment")
			expect.truthy(exhaust:FindFirstChild("BoostFlames"))
			expect.truthy(chassis:FindFirstChild("MegaGlow"))
		end)

		t.test(`{def.Id} builds a preview model`, function()
			local model = CarModelBuilder.build(def, { preview = true })
			for _, child in model:GetDescendants() do
				if child:IsA("BasePart") then
					expect.truthy(child.Anchored)
				end
				expect.falsy(child:IsA("WeldConstraint"))
			end
		end)
	end
end
