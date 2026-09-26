--!strict
-- The juice: boost flames, name tags over cars, sparks and thumps on hits, screen shake, and a proper party
-- for every goal - a shockwave and fireball in the net, confetti over the goal and fireworks above the stands.
--
-- Sounds use sounds that ship with Roblox. For a proper goal horn or crowd cheer, find one in the Creator Store
-- (Toolbox > Audio), copy its ID and paste it into SOUNDS below as "rbxassetid://<number>".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local BallView = require(script.Parent.BallView)
local CameraController = require(script.Parent.CameraController)
local CarController = require(script.Parent.CarController)
local InputController = require(script.Parent.InputController)

local EffectsController = {}

local SOUNDS = {
	Jump = "rbxasset://sounds/action_jump.mp3",
	Hit = "rbxasset://sounds/action_jump_land.mp3",
	Goal = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
	Whoosh = "rbxasset://sounds/swoosh.wav",
}

local localPlayer = Players.LocalPlayer
local A = MatchState.CarAttr
local rgb = Color3.fromRGB
local effectsFolder: Folder
local rng = Random.new()

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local CONFETTI_COLORS = {
	rgb(255, 84, 84),
	rgb(255, 205, 64),
	rgb(80, 200, 255),
	rgb(120, 230, 120),
	rgb(220, 120, 255),
	rgb(255, 255, 255),
}

function EffectsController.play(name: string, volume: number?, speed: number?)
	local id = (SOUNDS :: { [string]: string })[name]
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- An invisible anchored part to hang effects on; it tidies itself away after `lifetime` seconds.
local function holder(position: Vector3, size: Vector3?, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = "Effect"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.one
	part.CFrame = CFrame.new(position)
	part.Parent = effectsFolder
	task.delay(lifetime, function()
		part:Destroy()
	end)
	return part
end

local function burst(
	position: Vector3,
	color: Color3,
	count: number,
	speed: number,
	size: number,
	lifetime: number,
	gravity: number?
)
	local part = holder(position, nil, lifetime + 0.5)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 2
	emitter.Acceleration = Vector3.new(0, -(gravity or 0), 0)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count)
end

-- A bubble of energy that bursts outwards and fades.
local function shockwave(position: Vector3, color: Color3, radius: number, duration: number)
	local bubble = holder(position, Vector3.one * 2, duration + 0.1)
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = color
	bubble.Transparency = 0
	TweenService:Create(bubble, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
end

-- A flash of light that lights up everything nearby for a moment.
local function flash(position: Vector3, color: Color3, range: number, brightness: number, duration: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(range, 60)
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder(position, nil, duration + 0.1)
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Brightness = 0,
	}):Play()
end

-- A ball of team-coloured fire with smoke rolling off it.
local function fireball(position: Vector3, color: Color3)
	local part = holder(position, nil, 3)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 250, 220)),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.6)),
	})
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.4, 9),
		NumberSequenceKeypoint.new(1, 2),
	})
	fire.Transparency = NumberSequence.new(0, 1)
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Speed = NumberRange.new(25, 55)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Drag = 4
	fire.RotSpeed = NumberRange.new(-120, 120)
	fire.Rate = 0
	fire.Parent = part
	fire:Emit(45)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(96, 96, 108))
	smoke.Size = NumberSequence.new(6, 16)
	smoke.Transparency = NumberSequence.new(0.45, 1)
	smoke.Lifetime = NumberRange.new(1.4, 2.4)
	smoke.Speed = NumberRange.new(8, 20)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 2
	smoke.Acceleration = Vector3.new(0, 6, 0)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Rate = 0
	smoke.Parent = part
	smoke:Emit(18)
end

-- Glittering confetti that pops up out of a box of air and flutters down.
local function confetti(centre: Vector3, area: Vector3, perColour: number)
	local part = holder(centre, area, 8)
	for _, color in CONFETTI_COLORS do
		pcall(function()
			local e = Instance.new("ParticleEmitter")
			e.Texture = SPARKLE
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.Color = ColorSequence.new(color)
			e.LightEmission = 0.4
			e.Size = NumberSequence.new(1)
			e.Squash = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.25, 1.2),
				NumberSequenceKeypoint.new(0.5, -1.2),
				NumberSequenceKeypoint.new(0.75, 1.2),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.85, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Lifetime = NumberRange.new(4, 6.5)
			e.Speed = NumberRange.new(6, 16)
			e.SpreadAngle = Vector2.new(50, 50)
			e.EmissionDirection = Enum.NormalId.Top
			e.Acceleration = Vector3.new(0, -9, 0)
			e.Drag = 0.7
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-260, 260)
			e.Rate = 0
			e.Parent = part
			e:Emit(perColour)
		end)
	end
end

-- One firework: a rocket streaks up and bursts into sparks.
local function firework(target: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local rocket = holder(target - Vector3.new(0, 55, 0), Vector3.one * 0.8, 2)
		rocket.Shape = Enum.PartType.Ball
		rocket.Material = Enum.Material.Neon
		rocket.Color = rgb(255, 232, 180)
		rocket.Transparency = 0
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 0.3, 0)
		top.Parent = rocket
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -0.3, 0)
		bottom.Parent = rocket
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(rgb(255, 232, 180), color)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Lifetime = 0.4
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = rocket
		TweenService:Create(rocket, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(target),
		}):Play()
		task.wait(0.7)
		rocket.Transparency = 1
		burst(target, color, 110, 75, 2.4, 1.9, 22)
		burst(target, rgb(255, 255, 255), 40, 40, 1.2, 1.2, 22)
		flash(target, color, 60, 5, 0.7)
	end)
end

local function teamColor(team: unknown): Color3
	if team == "Blue" then
		return GameConfig.Teams.Blue.Color
	elseif team == "Orange" then
		return GameConfig.Teams.Orange.Color
	end
	return Color3.fromRGB(255, 255, 255)
end

local function decorateCar(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local chassis = model.PrimaryPart or model:WaitForChild("Chassis", 5)
	if not chassis or not chassis:IsA("BasePart") then
		return
	end
	local isMine = model:GetAttribute(A.OwnerUserId) == localPlayer.UserId

	if not isMine then
		local tag = Instance.new("BillboardGui")
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(170, 34)
		tag.StudsOffset = Vector3.new(0, 5.5, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 260
		tag.LightInfluence = 0
		tag.Adornee = chassis
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		local name = model:GetAttribute(A.DriverName)
		label.Text = if type(name) == "string" then name else "Driver"
		label.TextColor3 = teamColor(model:GetAttribute(A.Team))
		label.Parent = tag
		tag.Parent = chassis
	end

	local exhaust = chassis:WaitForChild("Exhaust", 5)
	local flames = if exhaust then exhaust:WaitForChild("BoostFlames", 5) else nil
	local megaGlow = chassis:WaitForChild("MegaGlow", 5)
	local function refresh()
		if flames and flames:IsA("ParticleEmitter") and not isMine then
			flames.Enabled = model:GetAttribute(A.Boosting) == true
		end
		if megaGlow and megaGlow:IsA("ParticleEmitter") then
			megaGlow.Enabled = model:GetAttribute(A.MegaArmed) == true
		end
	end
	model:GetAttributeChangedSignal(A.Boosting):Connect(refresh)
	model:GetAttributeChangedSignal(A.MegaArmed):Connect(refresh)
	refresh()
end

-- Your own flames react to your key presses instantly instead of waiting for the server.
local function updateMyFlames()
	local car = CarController.getCar()
	local chassis = CarController.getChassis()
	if not car or not chassis then
		return
	end
	local exhaust = chassis:FindFirstChild("Exhaust")
	local flames = if exhaust then exhaust:FindFirstChild("BoostFlames") else nil
	if flames and flames:IsA("ParticleEmitter") then
		local boost = car:GetAttribute(A.Boost)
		local phase = MatchState.phase(MatchState.getObject())
		local canDrive = phase == MatchState.Phases.Playing or phase == MatchState.Phases.GoalScored
		flames.Enabled = canDrive
			and not chassis.Anchored
			and InputController.read().boost
			and type(boost) == "number"
			and boost > 0
	end
end

local function onGoal(team: unknown, _scorer: unknown, _assist: unknown, position: unknown, _combo: unknown)
	if typeof(position) ~= "Vector3" then
		return
	end
	local color = teamColor(team)
	local side = if position.Z >= 0 then 1 else -1
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 20
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = effectsFolder
	shockwave(position, color, 55, 0.9)
	flash(position, color, 60, 10, 1.4)
	fireball(position, color)
	burst(position, color, 160, 70, 3, 2.5)
	burst(position + Vector3.new(0, 10, 0), rgb(255, 230, 90), 80, 50, 2, 2)
	-- Confetti over the goal mouth, and fireworks above the stand behind the goal.
	local goalZ = side * GameConfig.Arena.Length / 2
	confetti(Vector3.new(0, 34, goalZ - side * 24), Vector3.new(80, 4, 36), 45)
	for i = 1, 7 do
		local target = Vector3.new(
			(i - 4) * 36 + rng:NextNumber(-8, 8),
			rng:NextNumber(128, 165),
			goalZ + side * rng:NextNumber(70, 120)
		)
		local fireworkColor = if i % 3 == 0 then rgb(255, 214, 90) elseif i % 3 == 1 then color else rgb(255, 255, 255)
		firework(target, fireworkColor, 0.2 + ((i * 5) % 7) * 0.22)
	end
	CameraController.shake(1.8, 0.9)
	EffectsController.play("Goal", 1, 0.8)
	EffectsController.play("Whoosh", 0.8, 0.7)
end

function EffectsController.start()
	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = workspace.CurrentCamera or workspace
	effectsFolder = folder

	local cars = workspace:WaitForChild(MatchState.Folders.Match):WaitForChild(MatchState.Folders.Cars)
	cars.ChildAdded:Connect(function(child)
		task.defer(decorateCar, child)
	end)
	for _, child in cars:GetChildren() do
		task.defer(decorateCar, child)
	end

	RunService.Heartbeat:Connect(updateMyFlames)

	BallView.Hit:Connect(function(position: Vector3, strength: number, mine: boolean)
		burst(position, Color3.fromRGB(255, 255, 255), math.floor(6 + strength * 18), 25 + strength * 40, 1.2, 0.5)
		if strength > 0.7 then
			shockwave(position, rgb(235, 245, 255), 6 + strength * 8, 0.3)
		end
		EffectsController.play("Hit", 0.3 + strength * 0.5, 1.4 - strength * 0.4)
		if mine and strength > 0.6 then
			CameraController.shake(0.5 * strength, 0.25)
		end
	end)

	CarController.Jumped:Connect(function()
		EffectsController.play("Jump", 0.35, 1.1)
	end)

	Remotes.GoalScored.OnClientEvent:Connect(onGoal)
	Remotes.Announce.OnClientEvent:Connect(function(kind: unknown)
		if kind == "mega" then
			BallView.setOnFire(2.5)
			shockwave(BallView.getPosition(), rgb(255, 140, 40), 22, 0.5)
			flash(BallView.getPosition(), rgb(255, 150, 60), 50, 6, 0.6)
			CameraController.shake(1, 0.4)
			EffectsController.play("Whoosh", 1, 0.9)
		end
	end)
end

return EffectsController
