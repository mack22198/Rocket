-- Builds every car with real (Lune) Roblox instances, which rejects unknown properties or bad values.
-- Fused cars are built from their base car's design, so they're checked here too.
local BallModelBuilder = require(Shared.Ball.BallModelBuilder)
local CarCatalog = require(Shared.Config.CarCatalog)
local CarMeshes = require(Shared.Cars.CarMeshes)
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
			-- (Saucers hover on pads instead of wheels.)
			local shape = if def.Fusion then def.Fusion.Base else def.Id
			if shape ~= "ufo" then
				expect.equal(hubs, 4, "four turning wheels")
				expect.atLeast(wheelParts, 12)
			end
			local exhaust = chassis:FindFirstChild("Exhaust")
			assert(exhaust, "missing exhaust attachment")
			expect.truthy(exhaust:FindFirstChild("BoostFlames"))
			expect.truthy(chassis:FindFirstChild("MegaGlow"))
		end)

		t.test(`{def.Id} wears every hat`, function()
			for _, hat in CarModelBuilder.hats() do
				local model = CarModelBuilder.build(def, { teamColor = Color3.fromRGB(0, 0, 255), topper = hat })
				local count = 0
				local lowest = math.huge
				for _, child in model:GetChildren() do
					if child:IsA("BasePart") and string.sub(child.Name, 1, 3) == "Hat" then
						count += 1
						expect.truthy(child:FindFirstChildOfClass("WeldConstraint") ~= nil, `{hat} part is welded`)
						lowest = math.min(lowest, child.CFrame.Position.Y - child.Size.Y / 2)
					end
				end
				expect.atLeast(count, 2, `{def.Id} has a {hat}`)
				expect.atMost(lowest, def.Hitbox.Y / 2 + 2.5, `{def.Id}'s {hat} sits on the car`)
			end
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

	t.test("the smooth meshes fit the cars they're made for", function()
		for id, set in CarMeshes.Cars do
			local def = CarCatalog.get(id)
			assert(def, `{id} is a car`)
			local names: { [string]: boolean } = {}
			for _, spec in CarModelBuilder.specs(def, 1) do
				names[spec.name] = true
			end
			for name in set.replaces do
				expect.truthy(names[name], `{id} has parts called {name} for the meshes to replace`)
			end
			for _, info in set.meshes do
				expect.truthy(info.size.X > 0.1 and info.size.Y > 0.1 and info.size.Z > 0.1, `{info.name} has a size`)
				expect.atMost(info.center.Magnitude, def.Hitbox.Magnitude, `{info.name} sits on the car`)
			end
		end
	end)

	t.test("with the meshes imported, every car swaps its blocky shell for them", function()
		local library = Instance.new("Folder")
		local function add(info: CarMeshes.MeshInfo)
			if not library:FindFirstChild(info.name) then
				local mesh = Instance.new("MeshPart")
				mesh.Name = info.name
				mesh.Anchored = true -- like Studio's importer leaves them
				mesh.Parent = library
			end
		end
		for _, set in CarMeshes.Cars do
			for _, info in set.meshes do
				add(info)
			end
		end
		for _, info in CarMeshes.Shared do
			add(info)
		end
		CarModelBuilder.setMeshLibrary(library)
		for id, set in CarMeshes.Cars do
			local def = CarCatalog.get(id)
			assert(def)
			expect.truthy(CarModelBuilder.usesMeshes(def), `{id} uses its meshes`)
			for stage = 1, 4 do
				local model = CarModelBuilder.build(def, { teamColor = Color3.fromRGB(255, 0, 0), stage = stage })
				local meshes, tires, hubs = 0, 0, 0
				for _, child in model:GetChildren() do
					expect.falsy(set.replaces[child.Name], `{id}: the {child.Name} parts were swapped out`)
					expect.truthy(child.Name ~= "Sidewall", "the tyres have their own sidewalls")
					if child.Name == "WheelHub" then
						hubs += 1
					elseif child:IsA("MeshPart") then
						expect.truthy(child.Massless and not child.CanCollide, `{child.Name} is just for looks`)
						expect.falsy(child.Anchored, `{child.Name} moves with the car`)
						local weld = child:FindFirstChildOfClass("WeldConstraint")
						assert(weld, `{child.Name} is welded`)
						if child.Name == "Wheel" then
							tires += 1
							local hub = weld.Part0
							expect.truthy(hub ~= nil and hub.Name == "WheelHub", "tyres turn with their hubs")
						else
							meshes += 1
						end
					end
				end
				expect.equal(meshes, #set.meshes, `{id} at stage {stage} has all its meshes`)
				expect.equal(tires, hubs, `{id}'s wheels all have treaded tyres`)
			end
		end
		-- A car whose meshes aren't all there stays built from parts.
		local someCar = next(CarMeshes.Cars)
		if someCar then
			local def = CarCatalog.get(someCar)
			assert(def)
			local first = library:FindFirstChild(CarMeshes.Cars[someCar].meshes[1].name)
			if first then
				first:Destroy()
			end
			CarModelBuilder.setMeshLibrary(library)
			expect.falsy(CarModelBuilder.usesMeshes(def), "half-imported cars stay parts")
		end
		-- The ball: crisp pentagons and stitching instead of round caps.
		local ball = BallModelBuilder.build(3)
		local patch = ball:FindFirstChild("Patch")
		assert(patch and patch:IsA("MeshPart"), "pentagon patches")
		expect.truthy(ball:FindFirstChild("Seam") ~= nil, "stitching")
		expect.near(patch.Size.X, CarMeshes.Shared.ball_patches.size.X * 6, 1e-3)
		CarModelBuilder.setMeshLibrary(nil)
		expect.truthy(BallModelBuilder.build(3):FindFirstChild("Seam") == nil, "back to the plain ball")
	end)
end
