--!strict
-- Client entry point: starts every controller and screen.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

local PlayerDataClient = require(Controllers.PlayerDataClient)
local CarController = require(Controllers.CarController)
local BallView = require(Controllers.BallView)
local CameraController = require(Controllers.CameraController)
local EffectsController = require(Controllers.EffectsController)
local StadiumController = require(Controllers.StadiumController)

local HUD = require(UI.HUD)
local Announcer = require(UI.Announcer)
local ResultsScreen = require(UI.ResultsScreen)
local Garage = require(UI.Garage)
local TouchControls = require(UI.TouchControls)

-- Resetting your character does nothing useful in this game (you drive a car), so hide that option.
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

PlayerDataClient.start()
CarController.start()
BallView.start()
CameraController.start()
EffectsController.start()
StadiumController.start()

HUD.start()
Announcer.start()
ResultsScreen.start()
Garage.start()
TouchControls.start()

HUD.GarageRequested:Connect(Garage.open)
ResultsScreen.GarageRequested:Connect(Garage.open)

print(`[Turbo Ball] Welcome, {Players.LocalPlayer.DisplayName}!`)
