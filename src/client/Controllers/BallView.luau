--!strict
-- The ball you see. The server sends the real ball ~30 times a second; in between, this runs the same
-- BallSim so the ball moves smoothly, and small corrections are blended in instead of snapping.
-- When YOUR car touches the ball, the hit is applied here immediately (so it feels instant) and sent to the
-- server to be confirmed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallModelBuilder = require(Shared.Ball.BallModelBuilder)
local BallSim = require(Shared.Physics.BallSim)
local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local CarController = require(script.Parent.CarController)

local BallView = {}

-- Fired with (position, strength 0..1, isMine) whenever the ball gets hit, for sounds and sparks.
BallView.Hit = Signal.new() :: Signal.Signal<Vector3, number, boolean>

local cfg = GameConfig.Ball
local STEP = cfg.FixedStep
local RADIUS = cfg.Radius
local A = MatchState.CarAttr

local arena = ArenaShape.new(GameConfig.Arena)
local sim = BallSim.newState(Vector3.new(0, RADIUS, 0))
local simTime = 0
local visualOffset = Vector3.zero
local lastSnapshotTime = -math.huge
local frozen = true
local hidden = false
local hitId = 0
local pendingHitId: number? = nil
local pendingSince = 0
local acceptAfter = -math.huge -- ignore snapshots older than our confirmed hit
local nextLocalHit = 0
local rotation = CFrame.new()
local spin = Vector3.zero
local fireUntil = 0

local ballModel: Model
local ballPart: Part
local shadow: Part
local trail: Trail
local fire: ParticleEmitter
local light: PointLight

local TEAM_TRAIL = {
	[0] = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
	[1] = ColorSequence.new(GameConfig.Teams.Blue.Color),
	[2] = ColorSequence.new(GameConfig.Teams.Orange.Color),
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function hasFlag(flags: number, flag: number): boolean
	return bit32.band(flags, flag) ~= 0
end

local function buildBall()
	local model = BallModelBuilder.build()
	local part = model.PrimaryPart :: Part

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, RADIUS * 0.6, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -RADIUS * 0.6, 0)
	bottom.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = top
	t.Attachment1 = bottom
	t.Lifetime = 0.35
	t.LightEmission = 0.6
	t.Transparency = NumberSequence.new(0.2, 1)
	t.FaceCamera = true
	t.Color = TEAM_TRAIL[0]
	t.Parent = part

	local flames = Instance.new("ParticleEmitter")
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 70, 20))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 0) })
	flames.Lifetime = NumberRange.new(0.3, 0.5)
	flames.Rate = 120
	flames.Speed = NumberRange.new(2, 6)
	flames.SpreadAngle = Vector2.new(180, 180)
	flames.Enabled = false
	flames.Parent = part

	local glow = Instance.new("PointLight")
	glow.Range = 16
	glow.Brightness = 1
	glow.Color = Color3.fromRGB(255, 255, 255)
	glow.Parent = part

	-- A soft shadow on the floor under the ball helps judge how high it is.
	local s = Instance.new("Part")
	s.Name = "BallShadow"
	s.Shape = Enum.PartType.Cylinder
	s.Size = Vector3.new(0.05, RADIUS * 2, RADIUS * 2)
	s.Color = Color3.fromRGB(10, 10, 20)
	s.Material = Enum.Material.SmoothPlastic
	s.Transparency = 0.5
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false

	model.PrimaryPart = part
	local container = workspace.CurrentCamera or workspace
	model.Parent = container
	s.Parent = container
	ballModel, ballPart, shadow, trail, fire, light = model, part, s, t, flames, glow
end

local function onSnapshot(t: number, position: Vector3, velocity: Vector3, flags: number, touchTeam: number)
	if t < lastSnapshotTime then
		return -- arrived out of order
	end
	lastSnapshotTime = t
	local snap = hasFlag(flags, Remotes.BallFlags.Snap)
	hidden = hasFlag(flags, Remotes.BallFlags.Hidden)
	frozen = hasFlag(flags, Remotes.BallFlags.Frozen)
	trail.Color = TEAM_TRAIL[touchTeam] or TEAM_TRAIL[0]

	if snap then
		pendingHitId = nil
		acceptAfter = -math.huge
	end
	if pendingHitId then
		-- Our own hit is still on its way to the server; older snapshots would undo it.
		if os.clock() - pendingSince < 1 then
			return
		end
		pendingHitId = nil
	end
	if t < acceptAfter then
		return
	end

	local now = serverNow()
	local corrected = BallSim.newState(position, velocity)
	local correctedTime = now
	if not frozen then
		local ahead = math.clamp(now - t, 0, 0.5)
		corrected = BallSim.simulate(arena, cfg, corrected, ahead)
		correctedTime = t + ahead
	end

	-- Someone else hit the ball (the path changed a lot): make a thump.
	local predictedVelocity = sim.velocity
	if not snap and not frozen and (corrected.velocity - predictedVelocity).Magnitude > 35 then
		BallView.Hit:Fire(
			corrected.position,
			math.clamp((corrected.velocity - predictedVelocity).Magnitude / 150, 0, 1),
			false
		)
	end

	local shownBefore = sim.position + visualOffset
	sim = corrected
	simTime = correctedTime
	local correction = shownBefore - corrected.position
	if snap or hidden or frozen or correction.Magnitude > 25 then
		visualOffset = Vector3.zero
	else
		visualOffset = correction
	end
end

local function tryLocalHit()
	local car = CarController.getCar()
	local chassis = CarController.getChassis()
	if not car or not chassis or chassis.Anchored or os.clock() < nextLocalHit then
		return
	end
	local carCFrame = chassis.CFrame
	local contact = HitModel.findContact(carCFrame, chassis.Size / 2, sim.position, RADIUS)
	if not contact then
		return
	end
	local carVelocity = chassis.AssemblyLinearVelocity
	local mega = car:GetAttribute(A.MegaArmed) == true
	local before = BallSim.copy(sim)
	local result = HitModel.resolve(
		GameConfig.Hit,
		carCFrame,
		carVelocity,
		before.position,
		before.velocity,
		RADIUS,
		contact,
		mega,
		cfg.MaxSpeed
	)
	hitId += 1
	pendingHitId = hitId
	pendingSince = os.clock()
	nextLocalHit = os.clock() + GameConfig.Hit.Cooldown
	Remotes.BallHit:FireServer(hitId, simTime, carCFrame, carVelocity, before.position, before.velocity)

	sim.position = result.ballPosition
	sim.velocity = result.ballVelocity
	visualOffset = Vector3.zero
	CarController.addVelocity(result.carVelocityChange)
	BallView.Hit:Fire(result.ballPosition, math.clamp(result.impactSpeed / 120, 0.1, 1), true)
	if mega then
		BallView.setOnFire(2.5)
	end
end

local function update(dt: number)
	local now = serverNow()
	if not frozen and not hidden then
		local steps = 0
		while simTime + STEP <= now and steps < 12 do
			BallSim.step(arena, cfg, sim, STEP)
			simTime += STEP
			steps += 1
		end
		if now - simTime > 0.25 then
			simTime = now
		end
		tryLocalHit()
	end

	visualOffset *= math.exp(-10 * dt)
	local ahead = if frozen then 0 else math.clamp(now - simTime, 0, STEP)
	local shown = sim.position + sim.velocity * ahead + visualOffset

	-- Roll when touching the floor, keep spinning in the air.
	local horizontal = Vector3.new(sim.velocity.X, 0, sim.velocity.Z)
	if shown.Y < RADIUS + 1 and horizontal.Magnitude > 0.5 then
		-- Rolling spin axis = up x velocity.
		spin = Vector3.new(horizontal.Z, 0, -horizontal.X) / RADIUS
	end
	if spin.Magnitude > 1e-3 then
		rotation = CFrame.fromAxisAngle(spin.Unit, spin.Magnitude * dt) * rotation
	end

	local visible = not hidden
	for _, part in ballModel:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
		end
	end
	trail.Enabled = visible
	light.Enabled = visible
	fire.Enabled = visible and os.clock() < fireUntil
	ballModel:PivotTo(CFrame.new(shown) * rotation)

	local height = math.max(0, shown.Y - RADIUS)
	shadow.Transparency = if visible then math.clamp(0.45 + height / 80, 0.45, 0.95) else 1
	shadow.CFrame = CFrame.new(shown.X, 0.08, shown.Z) * CFrame.Angles(0, 0, math.rad(90))
end

function BallView.start()
	buildBall()
	Remotes.BallState.OnClientEvent:Connect(function(t: any, position: any, velocity: any, flags: any, touchTeam: any)
		if type(t) == "number" and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
			onSnapshot(
				t,
				position,
				velocity,
				if type(flags) == "number" then flags else 0,
				if type(touchTeam) == "number" then touchTeam else 0
			)
		end
	end)
	Remotes.BallHitResult.OnClientEvent:Connect(function(id: any, accepted: any, serverTime: any)
		if id ~= pendingHitId then
			return
		end
		pendingHitId = nil
		if accepted == true and type(serverTime) == "number" then
			acceptAfter = serverTime
		else
			acceptAfter = -math.huge -- rejected: the next snapshot puts the ball back where it really is
		end
	end)
	RunService.Heartbeat:Connect(update)
end

-- Where the ball is drawn right now (used by the camera).
function BallView.getPosition(): Vector3
	return ballPart.Position
end

function BallView.isVisible(): boolean
	return not hidden
end

function BallView.setOnFire(seconds: number)
	fireUntil = math.max(fireUntil, os.clock() + seconds)
end

return BallView
