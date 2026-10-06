--!strict
-- Client entry point: starts every controller and screen. You begin in the main menu (see GameFlow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

-- The black cover goes up first, so the menu can be built behind it and faded in.
local Transition = require(UI.Transition)
Transition.start()

local PlayerDataClient = require(Controllers.PlayerDataClient)
local InputController = require(Controllers.InputController)
local CarController = require(Controllers.CarController)
local BallView = require(Controllers.BallView)
local CameraController = require(Controllers.CameraController)
local CarVisuals = require(Controllers.CarVisuals)
local EffectsController = require(Controllers.EffectsController)
local SoundController = require(Controllers.SoundController)
local PowerVisuals = require(Controllers.PowerVisuals)
local ReplayController = require(Controllers.ReplayController)
local TwistController = require(Controllers.TwistController)
local PodiumController = require(Controllers.PodiumController)
local StadiumController = require(Controllers.StadiumController)
local ShowroomController = require(Controllers.ShowroomController)
local GameFlow = require(Controllers.GameFlow)

local HUD = require(UI.HUD)
local Announcer = require(UI.Announcer)
local Coach = require(UI.Coach)
local QuickChatPanel = require(UI.QuickChatPanel)
local ResultsScreen = require(UI.ResultsScreen)
local Garage = require(UI.Garage)
local MainMenu = require(UI.MainMenu)
local PauseMenu = require(UI.PauseMenu)
local HowToPlay = require(UI.HowToPlay)
local DailyRewards = require(UI.DailyRewards)
local CollectionBook = require(UI.CollectionBook)
local SeasonTrack = require(UI.SeasonTrack)
local ProfilePanel = require(UI.ProfilePanel)
local GiftsPanel = require(UI.GiftsPanel)
local LeaderboardPanel = require(UI.LeaderboardPanel)
local Toasts = require(UI.Toasts)
local ReplayScreen = require(UI.ReplayScreen)
local TouchControls = require(UI.TouchControls)

-- There's no avatar to reset (you drive a car), so hide Roblox's reset option.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
end)

-- The smooth car bodies from Blender, if they've been imported (they can turn up a moment after we start).
local CarModelBuilder = require(ReplicatedStorage:WaitForChild("Shared").Cars.CarModelBuilder)
local function useCarMeshes()
	CarModelBuilder.setMeshLibrary(
		ReplicatedStorage:FindFirstChild("CarMeshes") or ReplicatedStorage:FindFirstChild("TurboBallCars")
	)
end
useCarMeshes()
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "CarMeshes" or child.Name == "TurboBallCars" then
		task.wait(1) -- let all of its meshes arrive
		useCarMeshes()
		ShowroomController.rebuild()
	end
end)

PlayerDataClient.start()
InputController.start()
CarController.start()
BallView.start()
CameraController.start()
CarVisuals.start()
EffectsController.start()
SoundController.start()
PowerVisuals.start()
ReplayController.start()
TwistController.start()
PodiumController.start()
StadiumController.start()
ShowroomController.start()

HUD.start()
Announcer.start()
Coach.start()
QuickChatPanel.start()
ResultsScreen.start()
Garage.start()
MainMenu.start()
PauseMenu.start()
HowToPlay.start()
DailyRewards.start()
CollectionBook.start()
SeasonTrack.start()
ProfilePanel.start()
GiftsPanel.start()
LeaderboardPanel.start()
Toasts.start()
ReplayScreen.start()
TouchControls.start()

GameFlow.start()

print(`[Turbo Ball] Welcome, {Players.LocalPlayer.DisplayName}!`)
