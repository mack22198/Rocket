--!strict
-- What ultimates look like. Every one goes off with a flash, a ring racing across the ground and a burst in its
-- colour, and the car glows in that colour while it lasts. Then each does its own thing where you can see it:
-- the cheese floods out from under the car, banana peels fly through the air and land in front of you, ketchup
-- squirts forward, the Monster Truck leaps and slams down, diving sharks go see-through and the Tractor Beam
-- reaches for the ball. Cars stuck in cheese drip with it. The charge orb too: it bobs and glows on the pitch
-- under a beam of light, with a tag saying what it's worth, so you can spot it from anywhere. And demolitions:
-- the POOF, the car vanishing, and the sparkle when it pops back in at its goal.
-- It's all just for looks; the server decides what actually happens (see PowerService, OrbService and
-- DemolitionService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Powers = require(Shared.Config.Powers)
local Remotes = require(Shared.Net.Remotes)

local BallView = require(script.Parent.BallView)
local CameraController = require(script.Parent.CameraController)
local CarController = require(script.Parent.CarController)
local EffectsController = require(script.Parent.EffectsController)
local LocalHide = require(script.Parent.LocalHide)

local PowerVisuals = {}

type CarLook = {
	model: Model,
	chassis: BasePart,
	pullBeam: Beam,
	aura: ParticleEmitter, -- sparks in the ultimate's colour while it's going...
	auraLight: PointLight, -- ...and a glow
	goo: ParticleEmitter, -- cheese dripping off a car stuck in a Cheese Flood
	ghostParts: { BasePart },
	ghosted: boolean?, -- nil = needs setting again (after the car was hidden for a replay)
}

-- The charge orb, as this screen animates it.
type Orb = { home: Vector3, shell: BasePart?, core: BasePart?, beacon: BasePart?, tag: BillboardGui }

local A = MatchState.CarAttr
local T = Powers.Tuning
local rgb = Color3.fromRGB
local ORB_COLOR = rgb(80, 220, 255)
local ORB_CORE_SIZE = 4.6 -- (as PropBuilder.chargeOrb builds it)
local SPREAD_SPEED = 80 -- studs a second a new trap spreads out from where it came from
local CHEESE = rgb(255, 204, 64)

local folder: Folder
local cars: { [Model]: CarLook } = {}
local orbs: { [Model]: Orb } = {}
local ballAttachment: Attachment? = nil

---------------------------------------------------------------------------------------------------------------
-- Cars
---------------------------------------------------------------------------------------------------------------

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local found = model:WaitForChild("Chassis", 10)
	if not found or not found:IsA("BasePart") or not model.Parent then
		return
	end
	local chassis: BasePart = found
	local nose = Instance.new("Attachment")
	nose.Name = "PullNose"
	nose.Position = Vector3.new(0, 0.6, -chassis.Size.Z / 2)
	nose.Parent = chassis
	local beam = Instance.new("Beam")
	beam.Name = "PullBeam"
	beam.Attachment0 = nose
	beam.Color = ColorSequence.new(rgb(170, 255, 140), rgb(60, 220, 120))
	beam.Width0 = 1.6
	beam.Width1 = 0.6
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 12
	beam.CurveSize0 = 3
	beam.CurveSize1 = -3
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 4
	beam.TextureSpeed = -3
	beam.Transparency = NumberSequence.new(0.15, 0.4)
	beam.Enabled = false
	beam.Parent = chassis

	-- While its ultimate is going, the car sparkles and glows in the ultimate's colour.
	local powerId = model:GetAttribute(A.Power)
	local power = if type(powerId) == "string" then Powers.power(powerId) else nil
	local color = if power then power.Color else rgb(255, 255, 255)
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "UltAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	aura.LightEmission = 1
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new(0.15, 1)
	aura.Lifetime = NumberRange.new(0.5, 0.9)
	aura.Speed = NumberRange.new(3, 8)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Rate = 50
	aura.Enabled = false
	aura.Parent = chassis
	local auraLight = Instance.new("PointLight")
	auraLight.Name = "UltGlow"
	auraLight.Color = color
	auraLight.Range = 16
	auraLight.Brightness = 2
	auraLight.Shadows = false
	auraLight.Enabled = false
	auraLight.Parent = chassis
	-- Stuck in a Cheese Flood: blobs of cheese drip off the car.
	local goo = Instance.new("ParticleEmitter")
	goo.Name = "CheeseDrip"
	goo.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	goo.Color = ColorSequence.new(CHEESE, rgb(255, 170, 30))
	goo.LightEmission = 0.3
	goo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.4) })
	goo.Lifetime = NumberRange.new(0.5, 0.8)
	goo.Speed = NumberRange.new(1, 3)
	goo.Acceleration = Vector3.new(0, -40, 0)
	goo.Rate = 30
	goo.Enabled = false
	goo.Parent = chassis

	local ghostParts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(ghostParts, d)
		end
	end
	cars[model] = {
		model = model,
		chassis = chassis,
		pullBeam = beam,
		aura = aura,
		auraLight = auraLight,
		goo = goo,
		ghostParts = ghostParts,
		ghosted = false,
	}

	-- A demolished car is gone from every screen until it's back.
	local function syncDemolished()
		LocalHide.set(model, model:GetAttribute(A.Demolished) == true, "demo")
	end
	model:GetAttributeChangedSignal(A.Demolished):Connect(syncDemolished)
	syncDemolished()
end

local function untrack(model: Model)
	cars[model] = nil
	LocalHide.forget(model)
end

local function updateCar(look: CarLook, ballPosition: Vector3, ballShown: boolean)
	local model = look.model
	if LocalHide.isHidden(model) then
		-- A replay or the podium is showing a stand-in; keep everything of the real car out of sight.
		look.pullBeam.Enabled = false
		look.aura.Enabled = false
		look.auraLight.Enabled = false
		look.goo.Enabled = false
		look.ghosted = nil
		return
	end

	local glowing = model:GetAttribute(A.UltActive) == true
	look.aura.Enabled = glowing
	look.auraLight.Enabled = glowing
	look.goo.Enabled = model:GetAttribute(A.Goo) == true

	-- Shark Dive: the car goes see-through.
	local ghost = model:GetAttribute(A.Ghost) == true
	if ghost ~= look.ghosted then
		look.ghosted = ghost
		for _, part in look.ghostParts do
			part.LocalTransparencyModifier = if ghost then 0.6 else 0
		end
	end

	-- Tractor Beam: a glowing beam reaches for the ball while it's close enough to hold.
	local beam = look.pullBeam
	local target = if model:GetAttribute(A.Pull) == "beam" then Powers.pullTarget(look.chassis.CFrame) else nil
	if target and ballShown and ballAttachment and (ballPosition - target).Magnitude <= T.BeamRange then
		beam.Attachment1 = ballAttachment
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

-- The beam reaches for an attachment inside the ball (made again if the ball is rebuilt for a twist).
local function ensureBallAttachment()
	local ball = BallView.getPart()
	local current = ballAttachment
	if current and current.Parent == ball then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PullTarget"
	attachment.Parent = ball
	ballAttachment = attachment
end

---------------------------------------------------------------------------------------------------------------
-- The charge orb
---------------------------------------------------------------------------------------------------------------

local function removeOrb(model: Model)
	local orb = orbs[model]
	if orb then
		orb.tag:Destroy()
		orbs[model] = nil
	end
end

local function addOrb(model: Instance)
	if not model:IsA("Model") or orbs[model] then
		return
	end
	local home = model:GetAttribute("Home")
	if typeof(home) ~= "Vector3" then
		return
	end
	local shell = model:WaitForChild("Shell", 5)
	local core = model:WaitForChild("Core", 5)
	local beacon = model:WaitForChild("Beacon", 5)
	if not model.Parent or not core or not core:IsA("BasePart") then
		return
	end
	-- A tag over it saying what it's worth.
	local tag = Instance.new("BillboardGui")
	tag.Name = "OrbTag"
	tag.Size = UDim2.fromOffset(124, 36)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = core
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = rgb(16, 18, 34)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = ORB_COLOR
	label.Text = `ULT +{math.floor(GameConfig.Ultimate.Orb / GameConfig.Ultimate.Max * 100)}%`
	label.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local outline = Instance.new("UIStroke")
	outline.Color = ORB_COLOR
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.Parent = label
	tag.Parent = folder
	orbs[model] = {
		home = home,
		shell = if shell and shell:IsA("BasePart") then shell else nil,
		core = core,
		beacon = if beacon and beacon:IsA("BasePart") then beacon else nil,
		tag = tag,
	}
end

-- The orb bobs, spins and pulses.
local function updateOrbs()
	local t = os.clock()
	for model, orb in orbs do
		if not model.Parent then
			removeOrb(model)
			continue
		end
		local centre = CFrame.new(orb.home + Vector3.new(0, math.sin(t * 2.4) * 0.6, 0))
		if orb.shell then
			orb.shell.CFrame = centre * CFrame.Angles(0, t * 1.5, math.rad(15))
		end
		if orb.core then
			orb.core.CFrame = centre
			orb.core.Size = Vector3.one * ORB_CORE_SIZE * (1 + math.sin(t * 6) * 0.08)
		end
		if orb.beacon then
			orb.beacon.Transparency = 0.72 + math.sin(t * 3) * 0.08
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Cheese, banana peels and ketchup
---------------------------------------------------------------------------------------------------------------

-- A new trap appears the way it was made: it spreads out from where it came from (the car), so a Cheese Flood
-- floods outwards and a Ketchup Slick squirts forwards. (A thrown peel just lands.)
local function spreadOut(model: Instance)
	if not model:IsA("Model") then
		return
	end
	task.wait() -- (its parts can arrive a moment after the model)
	local from = model:GetAttribute("From")
	local origin = if typeof(from) == "Vector3" then from else model:GetPivot().Position
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local size = part.Size
			part.LocalTransparencyModifier = 1
			part.Size = size * 0.15
			task.delay((part.Position - origin).Magnitude / SPREAD_SPEED, function()
				if part.Parent then
					part.LocalTransparencyModifier = 0
					TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Size = size,
					}):Play()
				end
			end)
		end
	end
end

-- A banana peel flying in an arc from the car that threw it to where it lands.
local function tossPeel(thrower: unknown, landing: Vector3)
	local start = landing
	if typeof(thrower) == "Instance" and thrower:IsA("Model") then
		local chassis = thrower:FindFirstChild("Chassis")
		if chassis and chassis:IsA("BasePart") then
			start = chassis.CFrame.Position + Vector3.new(0, 3, 0)
		end
	end
	local peel = Instance.new("Part")
	peel.Name = "FlyingPeel"
	peel.Size = Vector3.new(1.6, 1.6, 3.4)
	peel.Color = rgb(255, 222, 60)
	peel.Anchored = true
	peel.CanCollide = false
	peel.CanQuery = false
	peel.CanTouch = false
	peel.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = peel
	peel.Parent = folder
	local height = 8 + (landing - start).Magnitude * 0.3
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / T.PeelFlight, 0, 1)
		local position = start:Lerp(landing, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
		peel.CFrame = CFrame.new(position) * CFrame.Angles(t * 11, t * 7, 0)
		if t >= 1 then
			connection:Disconnect()
			peel:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- One-off effects
---------------------------------------------------------------------------------------------------------------

-- The ultimate a car has (from its Power attribute).
local function powerOf(car: unknown): Powers.PowerDef?
	if typeof(car) == "Instance" then
		local id = car:GetAttribute(A.Power)
		return if type(id) == "string" then Powers.power(id) else nil
	end
	return nil
end

local function teamColor(team: unknown): Color3
	if team == "Blue" or team == "Orange" then
		return GameConfig.Teams[team :: string].Color
	end
	return rgb(255, 255, 255)
end

local function carPosition(extra: unknown, fallback: Vector3): Vector3
	if typeof(extra) == "Instance" and extra:IsA("Model") then
		local chassis = extra:FindFirstChild("Chassis")
		if chassis and chassis:IsA("BasePart") then
			return chassis.CFrame.Position
		end
	end
	return fallback
end

-- A word bursting out over a car ("QUACK!").
local function shout(extra: unknown, text: string, color: Color3)
	if typeof(extra) ~= "Instance" or not extra:IsA("Model") then
		return
	end
	local chassis = extra:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "Shout"
	tag.Size = UDim2.fromOffset(160, 60)
	tag.StudsOffset = Vector3.new(0, 6, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = chassis
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = tag
	tag.Parent = folder
	TweenService:Create(tag, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(300, 110),
		StudsOffset = Vector3.new(0, 10, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		tag:Destroy()
	end)
end

local function nearMe(position: Vector3, distance: number): boolean
	local chassis = CarController.getChassis()
	return chassis ~= nil and (chassis.CFrame.Position - position).Magnitude < distance
end

local function onPowerFx(kind: unknown, position: unknown, team: unknown, extra: unknown)
	if type(kind) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	local color = teamColor(team)
	local at = carPosition(extra, position)
	local mine = typeof(extra) == "Instance" and extra == CarController.getCar()
	local E = EffectsController
	local ground = at - Vector3.new(0, 2, 0)
	if kind == "ult" then
		-- Someone set off their ultimate: a flash, a ring racing across the ground and a burst, all in the
		-- ultimate's colour (then the ultimate's own effects). Your own also kicks the camera.
		local power = powerOf(extra)
		local glow = if power then power.Color else color
		E.flash(at, glow, 60, 8, 0.6)
		E.shockwave(at, glow, 16, 0.45)
		E.ring(ground, glow, 30, 0.7)
		E.burst(at, glow, 70, 40, 2, 0.7)
		E.play("Ultimate", 1, 1)
		if mine then
			CameraController.punch(14, 0.8)
			CameraController.shake(0.7, 0.35)
		end
		return
	elseif kind == "peeltoss" then
		tossPeel(extra, position)
		return
	elseif kind == "orb" then
		E.burst(position, ORB_COLOR, 30, 22, 1.4, 0.7)
		E.shockwave(position, ORB_COLOR, 8, 0.4)
		E.play("Orb", 0.8, 1)
		return
	elseif kind == "orbtaken" then
		E.burst(position, ORB_COLOR, 50, 34, 1.8, 0.7)
		E.shockwave(position, color, 12, 0.4)
		E.flash(position, ORB_COLOR, 40, 5, 0.4)
		if mine then
			E.play("Pickup", 0.9, 1.2)
		end
		return
	elseif kind == "orbgone" then
		E.burst(position, ORB_COLOR, 16, 10, 1, 0.5)
		return
	elseif kind == "nitro" then
		E.burst(at, rgb(255, 170, 60), 36, 36, 1.8, 0.6)
		E.flash(at, rgb(255, 160, 60), 30, 4, 0.4)
		E.play("Whoosh", 0.8, 1)
	elseif kind == "cheese" then
		-- A wave of cheese: goo splashes up everywhere as the puddle floods out.
		E.burst(position + Vector3.new(0, 2, 0), CHEESE, 110, 45, 2.6, 1.1, 60)
		E.ring(position, CHEESE, T.CheeseRadius + 3, 0.5)
		E.play("Hit", 0.8, 0.5)
	elseif kind == "peel" then
		-- A peel landing.
		E.burst(position + Vector3.new(0, 1, 0), rgb(255, 214, 70), 16, 14, 1.1, 0.4, 30)
		E.play("Click", 0.4, 1.4)
		return
	elseif kind == "ketchup" then
		-- `position` is the car's nose: ketchup sprays out of it.
		E.burst(position + Vector3.new(0, 1, 0), rgb(230, 30, 30), 70, 36, 1.6, 0.7, 40)
		E.play("Whoosh", 0.8, 0.6)
	elseif kind == "hotsauce" then
		E.burst(at, rgb(255, 80, 30), 44, 32, 1.8, 0.7)
		E.flash(at, rgb(255, 80, 40), 40, 5, 0.5)
		shout(extra, "HOT!", rgb(255, 110, 40))
		E.play("Whoosh", 0.9, 0.8)
	elseif kind == "quack" then
		E.shockwave(at, rgb(255, 224, 80), T.QuackRadius, 0.5)
		E.ring(ground, rgb(255, 224, 80), T.QuackRadius, 0.5)
		shout(extra, "QUACK!", rgb(255, 220, 60))
		E.play("Click", 1, 0.45)
		if nearMe(at, T.QuackRadius * 1.5) then
			CameraController.shake(0.8, 0.35)
		end
	elseif kind == "dive" then
		E.burst(at, rgb(90, 210, 255), 50, 34, 1.6, 0.7, 40)
		E.shockwave(at, rgb(120, 220, 255), 9, 0.35)
		E.play("Whoosh", 0.8, 1.2)
	elseif kind == "pound" then
		-- The slam: a shockwave, a ring of dust racing out and the ground shaking.
		local slam = color:Lerp(rgb(255, 90, 60), 0.5)
		E.shockwave(position, slam, T.PoundRadius, 0.55)
		E.ring(position - Vector3.new(0, 2, 0), slam, T.PoundRadius, 0.5)
		E.burst(position, rgb(170, 140, 110), 90, 50, 2.6, 1, 30)
		E.flash(position, rgb(255, 120, 80), 50, 7, 0.4)
		E.play("Hit", 1, 0.45)
		E.play("Poof", 0.8, 0.8)
		if nearMe(position, T.PoundRadius * 1.6) then
			CameraController.shake(1.4, 0.5)
		end
	elseif kind == "beam" then
		E.burst(at, rgb(150, 255, 130), 28, 16, 1.2, 0.7)
		E.play("Click", 0.6, 1.6)
	elseif kind == "slip" then
		E.burst(at + Vector3.new(0, 3, 0), rgb(255, 236, 90), 30, 18, 1.4, 0.8)
		E.play("Whoosh", 0.7, 1.6)
	elseif kind == "demo" then
		-- `position` is where the car was smashed (it's hidden there until it respawns).
		E.poof(position, color)
		shout(extra, "POOF!", rgb(255, 236, 110))
		E.play("Poof", 1, 1)
		E.play("Whoosh", 0.8, 0.6)
		if mine then
			CameraController.shake(1.4, 0.5)
		elseif nearMe(position, 45) then
			CameraController.shake(0.7, 0.3)
		end
		return
	elseif kind == "respawn" then
		E.burst(position, color, 40, 24, 1.5, 0.7)
		E.burst(position, rgb(255, 255, 255), 20, 16, 1, 0.5)
		E.shockwave(position, color, 9, 0.35)
		if mine then
			E.play("Pickup", 0.8, 0.9)
		end
	end
	if mine then
		CameraController.shake(0.35, 0.2)
	end
end

function PowerVisuals.start()
	local holder = Instance.new("Folder")
	holder.Name = "PowerVisuals"
	holder.Parent = workspace.CurrentCamera or workspace
	folder = holder

	ensureBallAttachment()

	local matchFolder = workspace:WaitForChild(MatchState.Folders.Match)
	local carsFolder = matchFolder:WaitForChild(MatchState.Folders.Cars)
	carsFolder.ChildAdded:Connect(function(child)
		task.spawn(track, child)
	end)
	carsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			untrack(child)
		end
	end)
	for _, child in carsFolder:GetChildren() do
		task.spawn(track, child)
	end

	task.spawn(function()
		local hazardFolder = matchFolder:WaitForChild(MatchState.Folders.Hazards)
		hazardFolder.ChildAdded:Connect(function(child)
			task.spawn(spreadOut, child)
		end)
	end)

	task.spawn(function()
		local orbFolder = matchFolder:WaitForChild(MatchState.Folders.Orbs)
		orbFolder.ChildAdded:Connect(function(child)
			task.spawn(addOrb, child)
		end)
		orbFolder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				removeOrb(child)
			end
		end)
		for _, child in orbFolder:GetChildren() do
			task.spawn(addOrb, child)
		end
	end)

	RunService.RenderStepped:Connect(function()
		ensureBallAttachment()
		updateOrbs()
		local ballPosition = BallView.getPosition()
		local ballShown = BallView.isVisible()
		for model, look in cars do
			if not model.Parent then
				untrack(model)
				continue
			end
			updateCar(look, ballPosition, ballShown)
		end
	end)

	Remotes.PowerFx.OnClientEvent:Connect(onPowerFx)
	CarController.EffectApplied:Connect(function(effect: string)
		if effect == "spin" then
			EffectsController.play("Whoosh", 0.8, 1.5)
		end
	end)
end

return PowerVisuals
