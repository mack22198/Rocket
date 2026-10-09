--!strict
-- The juice: dash flames, name tags over cars, sparks and thumps on hits, screen shake, and a proper party
-- for every goal - a shockwave and fireball in the net, confetti over the goal and fireworks above the stands.
--
-- Every sound is listed in Sounds (paste Toolbox sound IDs there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local BallView = require(script.Parent.BallView)
local CameraController = require(script.Parent.CameraController)
local CarController = require(script.Parent.CarController)
local LocalHide = require(script.Parent.LocalHide)
local SoundController = require(script.Parent.SoundController)

local EffectsController = {}

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

-- Plays one of the sounds in Sounds (see SoundController).
function EffectsController.play(name: string, volume: number?, speed: number?)
	SoundController.play(name, volume, speed)
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

-- For other effects code (items and powers) to use: burst(position, color, count, speed, size, lifetime,
-- gravity?), shockwave(position, color, radius, duration), flash(position, color, range, brightness, duration).
EffectsController.burst = burst
EffectsController.shockwave = shockwave
EffectsController.flash = flash

-- Toy-car bits (panels in the car's colour, dark tyres) that fly out of a demolition, tumble and fade.
local function flyingBits(position: Vector3, color: Color3)
	local bits: { { part: Part, velocity: Vector3, spin: Vector3 } } = {}
	for i = 1, 9 do
		local tyre = i % 3 == 0
		local bit = holder(position, nil, 1.6)
		bit.Shape = if tyre then Enum.PartType.Cylinder else Enum.PartType.Block
		bit.Size = if tyre
			then Vector3.new(0.7, 1.6, 1.6)
			else Vector3.new(rng:NextNumber(0.8, 1.8), 0.4, rng:NextNumber(0.8, 1.6))
		bit.Color = if tyre then rgb(40, 42, 48) else color
		bit.Material = Enum.Material.SmoothPlastic
		bit.Transparency = 0
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = rng:NextNumber(14, 30)
		table.insert(bits, {
			part = bit,
			velocity = Vector3.new(math.cos(angle) * out, rng:NextNumber(26, 44), math.sin(angle) * out),
			spin = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)),
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		if t > 1.4 then
			connection:Disconnect()
			return
		end
		for _, b in bits do
			local at = position + b.velocity * t + Vector3.new(0, -60, 0) * (t * t / 2)
			b.part.CFrame = CFrame.new(at) * CFrame.Angles(b.spin.X * t, b.spin.Y * t, b.spin.Z * t)
			b.part.Transparency = math.clamp((t - 0.9) / 0.5, 0, 1)
		end
	end)
end

-- A cartoon demolition: a fluffy white POOF of cloud, a ring of stars and sparkles in the car's colour, a pop of
-- confetti and toy-car bits flying everywhere. Nobody gets hurt - it's a toy!
function EffectsController.poof(position: Vector3, color: Color3)
	local part = holder(position, nil, 2.5)
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = "rbxasset://textures/particles/smoke_main.dds"
	cloud.Color = ColorSequence.new(rgb(255, 255, 255), rgb(226, 230, 244))
	cloud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.25, 9),
		NumberSequenceKeypoint.new(1, 12),
	})
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	cloud.Lifetime = NumberRange.new(0.7, 1.2)
	cloud.Speed = NumberRange.new(16, 30)
	cloud.SpreadAngle = Vector2.new(180, 180)
	cloud.Drag = 5
	cloud.Rotation = NumberRange.new(0, 360)
	cloud.RotSpeed = NumberRange.new(-60, 60)
	cloud.Rate = 0
	cloud.Parent = part
	cloud:Emit(28)
	burst(position, rgb(255, 228, 90), 40, 46, 2.2, 0.9, 25)
	burst(position, color, 50, 38, 1.6, 0.8, 25)
	shockwave(position, rgb(255, 255, 255), 15, 0.35)
	flash(position, rgb(255, 240, 210), 50, 6, 0.4)
	confetti(position + Vector3.new(0, 3, 0), Vector3.new(6, 2, 6), 10)
	flyingBits(position, color)
end

-- A party over a spot (the podium): confetti raining down and fireworks going off overhead.
function EffectsController.party(centre: Vector3, color: Color3)
	confetti(centre + Vector3.new(0, 26, 0), Vector3.new(46, 4, 26), 40)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local target = centre + Vector3.new(math.cos(angle) * 34, rng:NextNumber(46, 64), math.sin(angle) * 22 + 20)
		local fireworkColor = if i % 2 == 0 then color else rgb(255, 214, 90)
		firework(target, fireworkColor, 0.3 + i * 0.35)
	end
	EffectsController.play("Goal", 0.8, 1.1)
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

	-- Everyone else's name over their car: their level, their name and (smaller) their title.
	if not isMine then
		local tag = Instance.new("BillboardGui")
		tag.Name = "NameTag"
		tag.Size = UDim2.fromOffset(190, 48)
		tag.StudsOffset = Vector3.new(0, 5.8, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 260
		tag.LightInfluence = 0
		tag.Adornee = chassis
		local label = Instance.new("TextLabel")
		label.Name = "Name"
		label.Size = UDim2.fromScale(1, 0.64)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.RichText = true
		local outline = Instance.new("UIStroke")
		outline.Color = Color3.fromRGB(16, 18, 34)
		outline.Thickness = 2
		outline.Parent = label
		local name = model:GetAttribute(A.DriverName)
		local level = model:GetAttribute(A.Level)
		local shown = if type(name) == "string" then name else "Driver"
		shown = string.gsub(string.gsub(string.gsub(shown, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		if model:GetAttribute(A.Vip) == true then
			shown = `<font color="#FF56A4">VIP</font> {shown}`
		end
		label.Text = if type(level) == "number" then `<font color="#FFCC33">{level}</font>  {shown}` else shown
		label.TextColor3 = teamColor(model:GetAttribute(A.Team))
		label.Parent = tag
		local title = model:GetAttribute(A.Title)
		if type(title) == "string" and title ~= "" then
			local titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "Title"
			titleLabel.Size = UDim2.fromScale(1, 0.36)
			titleLabel.Position = UDim2.fromScale(0, 0.64)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Font = Enum.Font.GothamBold
			titleLabel.TextScaled = true
			local titleOutline = Instance.new("UIStroke")
			titleOutline.Color = Color3.fromRGB(16, 18, 34)
			titleOutline.Thickness = 1.5
			titleOutline.Parent = titleLabel
			titleLabel.TextColor3 = Color3.fromRGB(255, 226, 150)
			titleLabel.Text = title
			titleLabel.Parent = tag
		end
		tag.Parent = chassis
	end

	local exhaust = chassis:WaitForChild("Exhaust", 5)
	local flames = if exhaust then exhaust:WaitForChild("DashFlames", 5) else nil
	local megaGlow = chassis:WaitForChild("MegaGlow", 5)
	local function refresh()
		local shown = not LocalHide.isHidden(model)
		if flames and flames:IsA("ParticleEmitter") then
			flames.Enabled = shown and model:GetAttribute(A.Dashing) == true
		end
		if megaGlow and megaGlow:IsA("ParticleEmitter") then
			megaGlow.Enabled = shown and model:GetAttribute(A.MegaArmed) == true
		end
	end
	model:GetAttributeChangedSignal(A.Dashing):Connect(refresh)
	model:GetAttributeChangedSignal(A.MegaArmed):Connect(refresh)
	model:GetAttributeChangedSignal("HiddenLocally"):Connect(refresh)
	refresh()
end

---------------------------------------------------------------------------------------------------------------
-- Horns and goal celebrations (see Cosmetics)
---------------------------------------------------------------------------------------------------------------

-- A word popping up over a car ("HONK!").
local function wordBubble(chassis: BasePart, text: string, color: Color3)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Word"
	tag.Size = UDim2.fromOffset(150, 56)
	tag.StudsOffset = Vector3.new(0, 5.5, 0)
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
	tag.Parent = effectsFolder
	TweenService:Create(tag, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(240, 90),
		StudsOffset = Vector3.new(0, 8.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.9, function()
		tag:Destroy()
	end)
end

local function onHorn(car: unknown, hornId: unknown)
	if typeof(car) ~= "Instance" or not car:IsA("Model") then
		return
	end
	local horn = Cosmetics.get(if type(hornId) == "string" then hornId else nil)
	local chassis = car:FindFirstChild("Chassis")
	if not horn or horn.Kind ~= "horn" or not chassis or not chassis:IsA("BasePart") then
		return
	end
	if horn.Sound then
		local sound = Instance.new("Sound")
		sound.SoundId = horn.Sound
		sound.PlaybackSpeed = horn.Pitch or 1
		sound.Volume = 1
		sound.RollOffMaxDistance = 300
		sound.Parent = chassis
		sound:Play()
		task.delay(4, function()
			sound:Destroy()
		end)
	end
	wordBubble(chassis, horn.Word or "HONK!", teamColor(car:GetAttribute(A.Team)):Lerp(rgb(255, 255, 255), 0.35))
end

-- Things raining down on the pitch in front of a goal: `make` builds one (at the origin) from anchored parts.
local function rain(goalZ: number, side: number, count: number, make: (Folder) -> Model)
	local holderFolder = Instance.new("Folder")
	holderFolder.Name = "Rain"
	holderFolder.Parent = effectsFolder
	for i = 1, count do
		task.delay(i * 0.05, function()
			local thing = make(holderFolder)
			local landing = Vector3.new(rng:NextNumber(-60, 60), 1.2, goalZ - side * rng:NextNumber(8, 70))
			local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			thing:PivotTo(CFrame.new(landing + Vector3.new(0, rng:NextNumber(60, 90), 0)) * spin)
			local fall = rng:NextNumber(1.1, 1.8)
			local start = os.clock()
			local from = thing:GetPivot()
			local to = CFrame.new(landing) * spin
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - start) / fall, 0, 1)
				-- Falls, then a couple of little bounces.
				local eased = TweenService:GetValue(t, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
				thing:PivotTo(from:Lerp(to, eased))
				if t >= 1 then
					connection:Disconnect()
				end
			end)
		end)
	end
	task.delay(6, function()
		holderFolder:Destroy()
	end)
end

local function part(parent: Instance, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function rubberDuck(parent: Instance): Model
	local model = Instance.new("Model")
	local yellow = rgb(255, 216, 50)
	local body = part(model, Enum.PartType.Ball, Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, 0, 0), yellow)
	part(model, Enum.PartType.Ball, Vector3.one * 1.4, CFrame.new(0, 1.3, -0.6), yellow)
	part(model, Enum.PartType.Ball, Vector3.new(0.7, 0.35, 0.7), CFrame.new(0, 1.2, -1.35), rgb(255, 136, 30))
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

local function coin(parent: Instance): Model
	local model = Instance.new("Model")
	local face = part(model, Enum.PartType.Cylinder, Vector3.new(0.35, 2.4, 2.4), CFrame.new(), rgb(255, 200, 50))
	face.Material = Enum.Material.Metal
	face.Reflectance = 0.25
	local star = part(model, Enum.PartType.Ball, Vector3.new(0.3, 0.9, 0.9), CFrame.new(0.15, 0, 0), rgb(255, 240, 160))
	star.Material = Enum.Material.Neon
	model.PrimaryPart = face
	model.Parent = parent
	return model
end

local function taco(parent: Instance): Model
	local model = Instance.new("Model")
	local shell =
		part(model, Enum.PartType.Cylinder, Vector3.new(0.9, 2.8, 2.8), CFrame.new(0, 0, 0), rgb(240, 184, 72))
	part(model, Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 1.1, 0.4), rgb(104, 190, 64))
	part(model, Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 1.1, -0.4), rgb(230, 52, 40))
	model.PrimaryPart = shell
	model.Parent = parent
	return model
end

-- A rainbow arching over the goal mouth.
local function rainbow(goalZ: number, side: number)
	local folder = Instance.new("Folder")
	folder.Name = "Rainbow"
	folder.Parent = effectsFolder
	local colors = {
		rgb(255, 60, 60),
		rgb(255, 150, 40),
		rgb(255, 230, 60),
		rgb(80, 220, 90),
		rgb(60, 160, 255),
		rgb(150, 90, 255),
	}
	local segments = 12
	for band, color in colors do
		local radius = 52 - band * 2.2
		for k = 0, segments - 1 do
			local a0 = k / segments * math.pi
			local a1 = (k + 1) / segments * math.pi
			local p0 = Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, goalZ - side * 30)
			local p1 = Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, goalZ - side * 30)
			local piece = part(
				folder,
				Enum.PartType.Block,
				Vector3.new(2.3, 1.2, (p1 - p0).Magnitude + 0.3),
				CFrame.lookAt((p0 + p1) / 2, p1),
				color
			)
			piece.Material = Enum.Material.Neon
			piece.Transparency = 1
			TweenService:Create(piece, TweenInfo.new(0.6), { Transparency = 0.15 }):Play()
			task.delay(3.4, function()
				TweenService:Create(piece, TweenInfo.new(1), { Transparency = 1 }):Play()
			end)
		end
	end
	task.delay(4.6, function()
		folder:Destroy()
	end)
end

-- Gold stars falling over the goal.
local function starShower(goalZ: number, side: number)
	local area = holder(Vector3.new(0, 75, goalZ - side * 35), Vector3.new(110, 2, 60), 6)
	pcall(function()
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARKLE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Color = ColorSequence.new(rgb(255, 236, 140), rgb(255, 190, 40))
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.6) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2.5, 3.5)
		e.Speed = NumberRange.new(2, 6)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Acceleration = Vector3.new(0, -22, 0)
		e.RotSpeed = NumberRange.new(-180, 180)
		e.Rate = 0
		e.Parent = area
		e:Emit(260)
	end)
end

-- The scorer's celebration (the stadium fireworks are the classic).
local function celebration(kind: string, goalZ: number, side: number, color: Color3)
	if kind == "confetti" then
		confetti(Vector3.new(0, 55, goalZ - side * 50), Vector3.new(190, 4, 110), 90)
		confetti(Vector3.new(0, 40, goalZ - side * 24), Vector3.new(80, 4, 36), 45)
	elseif kind == "stars" then
		starShower(goalZ, side)
	elseif kind == "ducks" then
		rain(goalZ, side, 28, rubberDuck)
	elseif kind == "tacos" then
		rain(goalZ, side, 28, taco)
	elseif kind == "goldrush" then
		rain(goalZ, side, 36, coin)
		flash(Vector3.new(0, 30, goalZ - side * 30), rgb(255, 210, 90), 60, 5, 0.6)
	elseif kind == "rainbow" then
		rainbow(goalZ, side)
		confetti(Vector3.new(0, 34, goalZ - side * 24), Vector3.new(80, 4, 36), 30)
	else
		-- Fireworks above the stand behind the goal.
		for i = 1, 7 do
			local target = Vector3.new(
				(i - 4) * 36 + rng:NextNumber(-8, 8),
				rng:NextNumber(128, 165),
				goalZ + side * rng:NextNumber(70, 120)
			)
			local fireworkColor = if i % 3 == 0
				then rgb(255, 214, 90)
				elseif i % 3 == 1 then color
				else rgb(255, 255, 255)
			firework(target, fireworkColor, 0.2 + ((i * 5) % 7) * 0.22)
		end
		confetti(Vector3.new(0, 34, goalZ - side * 24), Vector3.new(80, 4, 36), 45)
	end
end

local function onGoal(
	team: unknown,
	_scorer: unknown,
	_assist: unknown,
	position: unknown,
	_combo: unknown,
	celebrationId: unknown
)
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
	-- Then the scorer's own celebration.
	local goalZ = side * GameConfig.Arena.Length / 2
	celebration(if type(celebrationId) == "string" then celebrationId else "fireworks", goalZ, side, color)
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
	Remotes.HornPlayed.OnClientEvent:Connect(onHorn)
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
