--!strict
-- The juice: boost flames, name tags over cars, sparks and thumps on hits, goal explosions and screen shake.
--
-- Sounds use sounds that ship with Roblox. For a proper goal horn or crowd cheer, find one in the Creator Store
-- (Toolbox > Audio), copy its ID and paste it into SOUNDS below as "rbxassetid://<number>".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

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
local effectsFolder: Folder

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

local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number, lifetime: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	holder.Parent = effectsFolder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(lifetime + 0.5, function()
		holder:Destroy()
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
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 20
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = effectsFolder
	burst(position, color, 160, 70, 3, 2.5)
	burst(position + Vector3.new(0, 10, 0), Color3.fromRGB(255, 230, 90), 80, 50, 2, 2)
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
			CameraController.shake(1, 0.4)
			EffectsController.play("Whoosh", 1, 0.9)
		end
	end)
end

return EffectsController
