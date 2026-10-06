--!strict
-- What items and powers look like: the "?" boxes spinning and bobbing on the pitch, a bubble around shielded
-- cars, a block of ice around frozen ones, see-through diving sharks, rocket-fuel flames, the glowing beam of a
-- Magnet or Tractor Beam reaching for the ball, and a burst of effects whenever an item or power goes off.
-- Demolitions too: the POOF, the car vanishing, and the sparkle when it pops back in at its goal.
-- It's all just for looks; the server decides what actually happens (see PowerService and DemolitionService).

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
	bubble: Part,
	ice: Part,
	nose: Attachment,
	pullBeam: Beam,
	rocketFire: ParticleEmitter?,
	ghostParts: { BasePart },
	ghosted: boolean?, -- nil = needs setting again (after the car was hidden for a replay)
}

type Box = { model: Model, home: Vector3, shell: BasePart?, core: BasePart?, phase: number }

local A = MatchState.CarAttr
local T = Powers.Tuning
local rgb = Color3.fromRGB

local folder: Folder
local cars: { [Model]: CarLook } = {}
local boxes: { Box } = {}
local ballAttachment: Attachment? = nil

local PULL_COLORS = {
	magnet = ColorSequence.new(rgb(255, 80, 90), rgb(90, 140, 255)),
	beam = ColorSequence.new(rgb(170, 255, 140), rgb(60, 220, 120)),
}

local function effectPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = folder
	return part
end

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
	local size = chassis.Size
	local bubble =
		effectPart("ShieldBubble", Enum.PartType.Ball, Vector3.one * (math.max(size.X, size.Z) + 3), rgb(110, 170, 255))
	bubble.Material = Enum.Material.ForceField
	local ice = effectPart("IceBlock", Enum.PartType.Block, size + Vector3.new(1.6, 2.4, 1.6), rgb(170, 226, 255))
	ice.Material = Enum.Material.Glass
	ice.Reflectance = 0.25

	local nose = Instance.new("Attachment")
	nose.Name = "PullNose"
	nose.Position = Vector3.new(0, 0.6, -size.Z / 2)
	nose.Parent = chassis
	local beam = Instance.new("Beam")
	beam.Name = "PullBeam"
	beam.Attachment0 = nose
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

	-- Rocket Fuel: a bigger, hotter flame out of the exhaust.
	local rocketFire: ParticleEmitter? = nil
	local exhaust = chassis:FindFirstChild("Exhaust")
	if exhaust and exhaust:IsA("Attachment") then
		local ok, emitter = pcall(function()
			local e = Instance.new("ParticleEmitter")
			e.Name = "RocketFuel"
			e.Texture = "rbxasset://textures/particles/fire_main.dds"
			e.Color = ColorSequence.new(rgb(255, 250, 200), rgb(255, 60, 200))
			e.LightEmission = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 0.2) })
			e.Transparency = NumberSequence.new(0.1, 1)
			e.Lifetime = NumberRange.new(0.25, 0.4)
			e.Speed = NumberRange.new(20, 30)
			e.EmissionDirection = Enum.NormalId.Back
			e.SpreadAngle = Vector2.new(12, 12)
			e.Rate = 90
			e.Enabled = false
			e.Parent = exhaust
			return e
		end)
		if ok then
			rocketFire = emitter
		end
	end

	local ghostParts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(ghostParts, d)
		end
	end
	cars[model] = {
		model = model,
		chassis = chassis,
		bubble = bubble,
		ice = ice,
		nose = nose,
		pullBeam = beam,
		rocketFire = rocketFire,
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
	local look = cars[model]
	if look then
		look.bubble:Destroy()
		look.ice:Destroy()
		cars[model] = nil
	end
	LocalHide.forget(model)
end

local function updateCar(look: CarLook, ballPosition: Vector3, ballShown: boolean)
	local model, chassis = look.model, look.chassis
	local frame = chassis.CFrame
	local t = os.clock()

	if LocalHide.isHidden(model) then
		-- A replay or the podium is showing a stand-in; keep everything of the real car out of sight.
		look.bubble.Transparency = 1
		look.ice.Transparency = 1
		look.pullBeam.Enabled = false
		if look.rocketFire then
			look.rocketFire.Enabled = false
		end
		look.ghosted = nil
		return
	end

	local shield = model:GetAttribute(A.Shield) == true
	look.bubble.Transparency = if shield then 0 else 1
	if shield then
		local pulse = 1 + math.sin(t * 6) * 0.03
		look.bubble.CFrame = frame
		look.bubble.Size = Vector3.one * (math.max(chassis.Size.X, chassis.Size.Z) + 3) * pulse
	end

	local frozen = model:GetAttribute(A.Frozen) == true
	if model == CarController.getCar() then
		local _, _, freezeLeft = CarController.effects()
		frozen = frozen or freezeLeft > 0
	end
	look.ice.Transparency = if frozen then 0.3 else 1
	if frozen then
		look.ice.CFrame = frame
	end

	local ghost = model:GetAttribute(A.Ghost) == true
	if ghost ~= look.ghosted then
		look.ghosted = ghost
		for _, part in look.ghostParts do
			part.LocalTransparencyModifier = if ghost then 0.6 else 0
		end
	end

	if look.rocketFire then
		look.rocketFire.Enabled = model:GetAttribute(A.Rocket) == true
	end

	local pull = model:GetAttribute(A.Pull)
	local beam = look.pullBeam
	local range = if pull == "beam" then T.BeamRange elseif pull == "magnet" then T.MagnetRange else 0
	local target = if range > 0 then Powers.pullTarget(pull :: string, frame) else nil
	local reaching = target ~= nil and ballShown and (ballPosition - target).Magnitude <= range
	if reaching and ballAttachment then
		beam.Attachment1 = ballAttachment
		beam.Color = PULL_COLORS[pull :: string] or PULL_COLORS.magnet
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

---------------------------------------------------------------------------------------------------------------
-- Item boxes
---------------------------------------------------------------------------------------------------------------

local function addBox(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local home = model:GetAttribute("Home")
	if typeof(home) ~= "Vector3" then
		return
	end
	local shell = model:WaitForChild("Box", 5)
	local core = model:WaitForChild("Core", 5)
	local box: Box = {
		model = model,
		home = home,
		shell = if shell and shell:IsA("BasePart") then shell else nil,
		core = if core and core:IsA("BasePart") then core else nil,
		phase = #boxes * 0.9,
	}
	table.insert(boxes, box)
	model:GetAttributeChangedSignal("Active"):Connect(function()
		if model:GetAttribute("Active") == true then
			EffectsController.burst(home, rgb(170, 220, 255), 16, 14, 1, 0.6)
		end
	end)
end

-- The beams reach for an attachment inside the ball (made again if the ball is rebuilt for a twist).
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

local function updateBoxes()
	local t = os.clock()
	for _, box in boxes do
		local spin = t * 1.8 + box.phase
		local bob = math.sin(t * 2.4 + box.phase) * 0.45
		local centre = CFrame.new(box.home + Vector3.new(0, bob, 0))
		if box.shell then
			box.shell.CFrame = centre * CFrame.Angles(0, spin, 0) * CFrame.Angles(math.rad(12), 0, math.rad(12))
		end
		if box.core then
			box.core.CFrame = centre * CFrame.Angles(spin * 1.6, -spin, 0)
			box.core.Color = Color3.fromHSV((t * 0.25 + box.phase * 0.1) % 1, 0.55, 1)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- One-off effects
---------------------------------------------------------------------------------------------------------------

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

-- A zap of light from one point to another (the Freeze Ray).
local function zap(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local ray = effectPart("Zap", Enum.PartType.Cylinder, Vector3.new(length, 1.2, 1.2), color)
	ray.Material = Enum.Material.Neon
	ray.Transparency = 0.1
	ray.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	TweenService:Create(ray, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(length, 0.2, 0.2) }):Play()
	task.delay(0.45, function()
		ray:Destroy()
	end)
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
	if kind == "box" then
		E.burst(position, rgb(255, 230, 120), 30, 26, 1.4, 0.7)
		E.burst(position, rgb(140, 210, 255), 20, 18, 1, 0.6)
		if mine then
			E.play("Pickup", 0.8, 1.3)
		end
	elseif kind == "magnet" then
		E.burst(at, rgb(255, 90, 100), 24, 20, 1.2, 0.6)
		E.shockwave(at, rgb(255, 120, 130), 8, 0.35)
		E.play("Whoosh", 0.5, 1.4)
	elseif kind == "freeze" then
		zap(position, at, rgb(170, 235, 255))
		E.burst(at, rgb(200, 240, 255), 50, 30, 1.6, 1, 10)
		E.shockwave(at, rgb(170, 230, 255), 10, 0.4)
		E.play("Whoosh", 0.7, 1.8)
	elseif kind == "spring" then
		E.shockwave(at - Vector3.new(0, 1.5, 0), rgb(130, 240, 120), 11, 0.35)
		E.burst(at, rgb(160, 255, 140), 20, 30, 1.2, 0.5)
		E.play("Jump", 0.7, 0.7)
	elseif kind == "rocket" or kind == "nitro" then
		E.burst(at, rgb(255, 170, 60), 36, 36, 1.8, 0.6)
		E.flash(at, rgb(255, 160, 60), 30, 4, 0.4)
		E.play("Whoosh", 0.8, 1)
	elseif kind == "shield" then
		E.burst(at, rgb(140, 190, 255), 30, 18, 1.3, 0.6)
		E.play("Click", 0.6, 0.8)
	elseif kind == "mega" then
		E.flash(at, rgb(255, 140, 50), 40, 5, 0.5)
		E.burst(at, rgb(255, 150, 60), 40, 30, 1.6, 0.7)
		E.play("Whoosh", 0.8, 0.8)
	elseif kind == "cheese" or kind == "peel" then
		E.burst(position + Vector3.new(0, 1, 0), rgb(255, 214, 70), 18, 16, 1.2, 0.5, 30)
		E.play("Hit", 0.4, 0.7)
	elseif kind == "ketchup" then
		E.burst(position + Vector3.new(0, 1, 0), rgb(230, 30, 30), 30, 22, 1.4, 0.6, 30)
		E.play("Hit", 0.5, 0.6)
	elseif kind == "hotsauce" then
		E.burst(at, rgb(255, 80, 30), 44, 32, 1.8, 0.7)
		E.flash(at, rgb(255, 80, 40), 40, 5, 0.5)
		shout(extra, "🌶️ HOT!", rgb(255, 110, 40))
		E.play("Whoosh", 0.9, 0.8)
	elseif kind == "quack" then
		E.shockwave(at, rgb(255, 224, 80), T.QuackRadius, 0.5)
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
		E.shockwave(position, color:Lerp(rgb(255, 90, 60), 0.5), T.PoundRadius, 0.55)
		E.burst(position, rgb(170, 140, 110), 60, 45, 2.2, 0.9, 30)
		E.flash(position, rgb(255, 120, 80), 50, 6, 0.4)
		E.play("Hit", 1, 0.5)
		if nearMe(position, T.PoundRadius * 1.6) then
			CameraController.shake(1.2, 0.45)
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
	if mine and kind ~= "box" then
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
		local boxFolder = matchFolder:WaitForChild(MatchState.Folders.ItemBoxes)
		boxFolder.ChildAdded:Connect(function(child)
			task.spawn(addBox, child)
		end)
		for _, child in boxFolder:GetChildren() do
			task.spawn(addBox, child)
		end
	end)

	RunService.RenderStepped:Connect(function()
		ensureBallAttachment()
		updateBoxes()
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
		elseif effect == "freeze" then
			EffectsController.play("Hit", 0.8, 1.6)
		end
	end)
end

return PowerVisuals
