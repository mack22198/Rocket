--!strict
-- Connects CarPhysics to a real car model: casts the wheel rays and applies the resulting velocities.
-- Players' cars are driven by their own client (the client owns the car's physics); bots are driven by the server.

local CarCatalog = require(script.Parent.Parent.Config.CarCatalog)
local CarPhysics = require(script.Parent.Parent.Physics.CarPhysics)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local CarDriver = {}
CarDriver.__index = CarDriver

export type CarDriver = typeof(setmetatable(
	{} :: {
		model: Model,
		chassis: BasePart,
		def: CarCatalog.CarDef,
		state: CarPhysics.State,
		mounts: { Vector3 },
		rayLength: number,
		rayParams: RaycastParams,
		pendingVelocity: Vector3,
		lastResult: CarPhysics.StepResult?,
	},
	CarDriver
))

function CarDriver.new(model: Model, def: CarCatalog.CarDef, arenaFolder: Instance): CarDriver
	local found = model.PrimaryPart or model:FindFirstChild("Chassis")
	assert(found and found:IsA("BasePart"), "Car model needs a Chassis part")
	local chassis: BasePart = found
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arenaFolder }
	params.IgnoreWater = true
	local self = {
		model = model,
		chassis = chassis,
		def = def,
		state = CarPhysics.newState(),
		mounts = CarPhysics.wheelMounts(chassis.Size),
		rayLength = CarPhysics.rayLength(GameConfig.Car),
		rayParams = params,
		pendingVelocity = Vector3.zero,
		lastResult = nil,
	}
	return setmetatable(self, CarDriver)
end

-- Queue an instant velocity change (a bump or the push back from hitting the ball).
function CarDriver.addVelocity(self: CarDriver, change: Vector3)
	self.pendingVelocity += change
end

function CarDriver.probeGround(self: CarDriver, cframe: CFrame): CarPhysics.Ground
	local down = -cframe.UpVector * self.rayLength
	local hits: { CarPhysics.WheelHit } = {}
	for _, mount in self.mounts do
		local result = workspace:Raycast(cframe:PointToWorldSpace(mount), down, self.rayParams)
		if result then
			table.insert(hits, { distance = result.Distance, normal = result.Normal })
		end
	end
	return CarPhysics.groundFromHits(GameConfig.Car, hits)
end

function CarDriver.isGrounded(self: CarDriver): boolean
	return self.state.grounded
end

-- Runs one physics tick. Call it every frame from RunService.PreSimulation.
function CarDriver.step(self: CarDriver, dt: number, input: CarPhysics.Input, hasBoost: boolean): CarPhysics.StepResult?
	local chassis = self.chassis
	if chassis.Anchored or not chassis:IsDescendantOf(workspace) then
		self.pendingVelocity = Vector3.zero
		return nil
	end
	local cframe = chassis.CFrame
	local result = CarPhysics.step({
		config = GameConfig.Car,
		stats = self.def.Stats,
		state = self.state,
		input = input,
		cframe = cframe,
		velocity = chassis.AssemblyLinearVelocity + self.pendingVelocity,
		angularVelocity = chassis.AssemblyAngularVelocity,
		ground = self:probeGround(cframe),
		dt = math.min(dt, 1 / 20),
		worldGravity = workspace.Gravity,
		hasBoost = hasBoost,
	})
	self.pendingVelocity = Vector3.zero
	if result.teleport then
		chassis.CFrame = result.teleport
	end
	chassis.AssemblyLinearVelocity = result.velocity
	chassis.AssemblyAngularVelocity = result.angularVelocity
	self.lastResult = result
	return result
end

-- Resets jump/flip state, e.g. after a kickoff teleport.
function CarDriver.reset(self: CarDriver)
	self.state = CarPhysics.newState()
	self.pendingVelocity = Vector3.zero
end

return CarDriver
