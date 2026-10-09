--!strict
-- Plays the game's sounds (see Sounds): one-off effects, the music and crowd that loop in the background (menu
-- music in the menus; the crowd and match music in the stadium), the referee's whistle at kickoffs and full
-- time, the crowd's cheer after a goal, and your own car's engine (higher the faster you go) and dash roar.
-- Sounds without an ID yet are simply skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local Sounds = require(Shared.Config.Sounds)

local CarController = require(script.Parent.CarController)

local SoundController = {}

local Phases = MatchState.Phases
local loops: { [string]: Sound } = {}
local scene = ""

-- Plays a sound once. `volume` and `speed` are on top of the sound's own settings.
function SoundController.play(name: string, volume: number?, speed: number?)
	local id = Sounds.idFor(name)
	local def = Sounds.List[name]
	if id == "" or not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = (volume or 0.6) * def.Volume
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function setLoop(name: string, on: boolean)
	local playing = loops[name]
	if on and not playing then
		local id = Sounds.idFor(name)
		local def = Sounds.List[name]
		if id == "" or not def then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = def.Volume
		sound.Parent = SoundService
		sound:Play()
		loops[name] = sound
	elseif not on and playing then
		playing:Destroy()
		loops[name] = nil
	end
end

-- Which background sounds loop: "menu" or "match".
function SoundController.setScene(newScene: string)
	scene = newScene
	setLoop("MenuMusic", newScene == "menu")
	setLoop("MatchMusic", newScene == "match")
	setLoop("Crowd", newScene == "match")
end

-- Your car's engine (and its roar while it dashes), every frame while you're driving.
local engine: Sound? = nil
local roar: Sound? = nil
local function looped(name: string, parent: Instance): Sound?
	local id = Sounds.idFor(name)
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = parent
	sound:Play()
	return sound
end

local function updateCar(dt: number)
	local chassis = CarController.getChassis()
	if not chassis or scene ~= "match" then
		if engine then
			engine:Destroy()
			engine = nil
		end
		if roar then
			roar:Destroy()
			roar = nil
		end
		return
	end
	if not engine or engine.Parent ~= chassis then
		if engine then
			engine:Destroy()
		end
		if roar then
			roar:Destroy()
		end
		engine, roar = looped("Engine", chassis), looped("DashLoop", chassis)
	end
	local speed = chassis.AssemblyLinearVelocity.Magnitude / GameConfig.Car.MaxSpeed
	local blend = math.min(1, dt * 8)
	local e = engine
	if e then
		e.PlaybackSpeed += (0.75 + math.min(speed, 1.6) * 0.6 - e.PlaybackSpeed) * blend
		e.Volume += (Sounds.List.Engine.Volume * (0.5 + math.min(speed, 1) * 0.5) - e.Volume) * blend
	end
	local r = roar
	if r then
		local wanted = if CarController.isDashing() then Sounds.List.DashLoop.Volume else 0
		r.Volume += (wanted - r.Volume) * math.min(1, dt * 12)
	end
end

function SoundController.start()
	game:GetService("RunService").Heartbeat:Connect(updateCar)
	Remotes.Bumped.OnClientEvent:Connect(function()
		if scene == "match" then
			SoundController.play("Bump", 0.7)
		end
	end)
	local stateObject = MatchState.getObject()
	local lastPhase = MatchState.phase(stateObject)
	stateObject:GetAttributeChangedSignal(MatchState.Attr.Phase):Connect(function()
		local phase = MatchState.phase(stateObject)
		if scene == "match" then
			if phase == Phases.Playing and lastPhase == Phases.Countdown then
				SoundController.play("Whistle", 1)
			elseif phase == Phases.Results then
				SoundController.play("Whistle", 1, 0.85)
			end
		end
		lastPhase = phase
	end)
	Remotes.GoalScored.OnClientEvent:Connect(function()
		if scene == "match" then
			SoundController.play("Cheer", 1)
		end
	end)
end

return SoundController
