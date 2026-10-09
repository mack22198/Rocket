--!strict
-- The ball you see. The server sends the real ball ~30 times a second; in between, this runs the same
-- BallSim so the ball moves smoothly, and small corrections are blended in instead of snapping.
-- When YOUR car touches the ball, the hit is applied here immediately (so it feels instant) and sent to the
-- server to be confirmed. A UFO's Tractor Beam (a car's Pull attribute) tugs the ball here too, just like on
-- the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallModelBuilder = require(Shared.Ball.BallModelBuilder)
local BallSim = require(Shared.Physics.BallSim)
local DriveAssist = require(Shared.Cars.DriveAssist)
local GameConfig = require(Shared.Config.GameConfig)
local HitModel = require(Shared.Physics.HitModel)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local CarController = require(script.Parent.CarController)

local BallView = {}

-- Fired with (position, strength 0..1, isMine) whenever the ball gets hit, for sounds and sparks.
BallView.Hit = Signal.new() :: Signal.Signal<Vector3, number, boolean>

local cfg = GameConfig.Ball -- (a match twist can swap in a changed copy; see setConfig)
local STEP = cfg.FixedStep
local A = MatchState.CarAttr

local arena = ArenaShape.new(GameConfig.Arena)
local sim = BallSim.newState(Vector3.new(0, cfg.Radius, 0))
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

local carsFolder: Instance? = nil
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
	local model = BallModelBuilder.build(cfg.Radius)
	local part = model.PrimaryPart :: Part

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, cfg.Radius * 0.6, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -cfg.Radius * 0.6, 0)
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
	s.Size = Vector3.new(0.05, cfg.Radius * 2, cfg.Radius * 2)
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
	local contact = HitModel.findContact(carCFrame, chassis.Size / 2, sim.position, cfg.Radius)
	if not contact then
		return
	end
	local carVelocity = chassis.AssemblyLinearVelocity
	local mega = car:GetAttribute(A.MegaArmed) == true
	local before = BallSim.copy(sim)
	-- Driving help's shot assist (the server does exactly the same).
	local team = car:GetAttribute(A.Team)
	local aim = if Players.LocalPlayer:GetAttribute(MatchState.PlayerAttr.Assist) ~= false
			and (team == "Blue" or team == "Orange")
		then DriveAssist.enemyGoal(
			GameConfig.Teams[team :: string].DefendsSide,
			GameConfig.Arena.Length,
			GameConfig.Arena.GoalHeight
		)
		else nil
	local result = HitModel.resolve(
		GameConfig.Hit,
		carCFrame,
		carVelocity,
		before.position,
		before.velocity,
		cfg.Radius,
		contact,
		mega,
		cfg.MaxSpeed,
		aim
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

-- The cars holding the ball in a Tractor Beam right now.
local function activePulls(): { BasePart }
	local list = {}
	local folder = carsFolder
	if not folder then
		return list
	end
	for _, car in folder:GetChildren() do
		if car:GetAttribute(A.Pull) == "beam" then
			local chassis = car:FindFirstChild("Chassis")
			if chassis and chassis:IsA("BasePart") then
				table.insert(list, chassis)
			end
		end
	end
	return list
end

local function update(dt: number)
	local now = serverNow()
	if not frozen and not hidden then
		local steps = 0
		local pulls = activePulls()
		while simTime + STEP <= now and steps < 12 do
			for _, chassis in pulls do
				local target = Powers.pullTarget(chassis.CFrame)
				sim.velocity = Powers.applyPull(sim.position, sim.velocity, target, cfg.Gravity, STEP)
			end
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
	if shown.Y < cfg.Radius + 1 and horizontal.Magnitude > 0.5 then
		-- Rolling spin axis = up x velocity.
		spin = Vector3.new(horizontal.Z, 0, -horizontal.X) / cfg.Radius
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

	local height = math.max(0, shown.Y - cfg.Radius)
	shadow.Transparency = if visible then math.clamp(0.45 + height / 80, 0.45, 0.95) else 1
	shadow.CFrame = CFrame.new(shown.X, 0.08, shown.Z) * CFrame.Angles(0, 0, math.rad(90))
end

function BallView.start()
	buildBall()
	task.spawn(function()
		carsFolder = workspace:WaitForChild(MatchState.Folders.Match):WaitForChild(MatchState.Folders.Cars)
	end)
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
	-- Driving help steers toward the ball and jumps at it (see DriveAssist).
	CarController.setBallInfo(function()
		return sim.position, sim.velocity, cfg.Radius, not hidden and not frozen
	end)
end

-- Where the ball is drawn right now (used by the camera).
function BallView.getPosition(): Vector3
	return ballPart.Position
end

-- The ball's main part (effects hang beams off it). It's replaced when a twist changes the ball's size.
function BallView.getPart(): BasePart
	return ballPart
end

-- The ball's settings for this match (a twist can change its size, gravity and bounce). A new size means a
-- new ball model.
function BallView.setConfig(newConfig: typeof(GameConfig.Ball))
	local resized = newConfig.Radius ~= cfg.Radius
	cfg = newConfig
	if resized and ballModel then
		ballModel:Destroy()
		shadow:Destroy()
		buildBall()
	end
end

function BallView.radius(): number
	return cfg.Radius
end

function BallView.isVisible(): boolean
	return not hidden
end

function BallView.setOnFire(seconds: number)
	fireUntil = math.max(fireUntil, os.clock() + seconds)
end

return BallView
