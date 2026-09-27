--!strict
-- Plays the game's sounds (see Sounds): one-off effects, the music and crowd that loop in the background (menu
-- music in the menus; the crowd and match music in the stadium), the referee's whistle at kickoffs and full
-- time, and the crowd's cheer after a goal. Sounds without an ID yet are simply skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)
local Sounds = require(Shared.Config.Sounds)

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

function SoundController.start()
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
