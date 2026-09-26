--!strict
-- Decides what's on screen: the main menu or the garage (both over the 3D showroom), or the match.
-- The server says where you are - the Status attribute on your Player: "Menu", "Queued" (pressed PLAY and
-- waiting) or "Playing" - and the garage is opened on top of the menu from here. Switching between the
-- showroom and the stadium fades through black.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local UI = script.Parent.Parent.UI
local Announcer = require(UI.Announcer)
local Garage = require(UI.Garage)
local HowToPlay = require(UI.HowToPlay)
local HUD = require(UI.HUD)
local MainMenu = require(UI.MainMenu)
local PauseMenu = require(UI.PauseMenu)
local ResultsScreen = require(UI.ResultsScreen)
local Transition = require(UI.Transition)

local InputController = require(script.Parent.InputController)
local PlayerDataClient = require(script.Parent.PlayerDataClient)
local ShowroomController = require(script.Parent.ShowroomController)

local GameFlow = {}

export type Screen = string -- "Menu", "Garage" or "Match"

local localPlayer = Players.LocalPlayer
local Status = MatchState.Status

local screen: Screen? = nil
local garageWanted = false
local garageCar: string? = nil

local function showEquippedCar()
	local data = PlayerDataClient.get()
	local def = CarCatalog.get(data.equipped) or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
	ShowroomController.showCar(def, data.carLook[def.Id] or 1)
end

local function wantedScreen(): Screen
	if MatchState.statusOf(localPlayer) == Status.Playing then
		return "Match"
	end
	return if garageWanted then "Garage" else "Menu"
end

-- Puts every screen in the right state for `target`.
local function apply(target: Screen)
	local inMatch = target == "Match"
	ShowroomController.setActive(not inMatch)
	HUD.setVisible(inMatch)
	Announcer.setVisible(inMatch)
	if inMatch then
		garageWanted = false
		MainMenu.hide()
		Garage.close()
		HowToPlay.close()
		return
	end
	PauseMenu.close()
	ResultsScreen.hide()
	if target == "Garage" then
		ShowroomController.setMode("garage")
		MainMenu.hide()
		Garage.open(garageCar)
	else
		ShowroomController.setMode("menu")
		Garage.close()
		showEquippedCar()
		MainMenu.show()
	end
end

local function refresh()
	MainMenu.setQueued(MatchState.statusOf(localPlayer) == Status.Queued)
	local target = wantedScreen()
	if target == screen then
		return
	end
	local previous = screen
	screen = target
	if previous == nil or (previous == "Match") ~= (target == "Match") then
		-- Between the showroom and the stadium: fade through black and set up whatever is wanted by then.
		Transition.fade(function()
			apply(wantedScreen())
		end)
	else
		apply(target)
	end
end

local function openGarage(carId: string?)
	garageWanted = true
	garageCar = carId
	refresh()
end

local function closeGarage()
	garageWanted = false
	garageCar = nil
	refresh()
end

-- The menu key: opens / closes the match menu, or goes "back" in the menus.
local function onMenuKey()
	if HowToPlay.isOpen() then
		HowToPlay.close()
	elseif screen == "Match" then
		if not ResultsScreen.isOpen() then
			PauseMenu.toggle()
		end
	elseif screen == "Garage" then
		closeGarage()
	end
end

function GameFlow.screen(): Screen?
	return screen
end

function GameFlow.start()
	MainMenu.PlayPressed:Connect(function()
		Remotes.Play:FireServer()
	end)
	MainMenu.CancelPressed:Connect(function()
		Remotes.LeaveMatch:FireServer()
	end)
	MainMenu.GaragePressed:Connect(function()
		openGarage(nil)
	end)
	MainMenu.HowToPlayPressed:Connect(function()
		HowToPlay.open()
	end)
	Garage.BackPressed:Connect(closeGarage)

	HUD.MenuRequested:Connect(function()
		PauseMenu.open()
	end)
	PauseMenu.Toggled:Connect(function(open: boolean)
		InputController.setBlocked(open)
	end)
	PauseMenu.LeaveRequested:Connect(function()
		garageWanted = false
		Remotes.LeaveMatch:FireServer()
	end)
	InputController.MenuPressed:Connect(onMenuKey)

	ResultsScreen.Chosen:Connect(function(choice: string, carId: string?)
		if choice == "again" then
			garageWanted = false
			Remotes.Play:FireServer()
		elseif choice == "garage" then
			garageWanted = true
			garageCar = carId
			Remotes.LeaveMatch:FireServer()
		else
			garageWanted = false
			Remotes.LeaveMatch:FireServer()
		end
	end)
	Remotes.MatchResults.OnClientEvent:Connect(function()
		PauseMenu.close()
	end)

	-- The car on the turntable follows the car you drive (while the garage isn't choosing one).
	PlayerDataClient.Changed:Connect(function()
		if screen == "Menu" then
			showEquippedCar()
		end
	end)
	localPlayer:GetAttributeChangedSignal(MatchState.PlayerAttr.Status):Connect(refresh)

	-- The game opens on a black screen; build the menu behind it, then fade in.
	local first = wantedScreen()
	screen = first
	local ok, err = pcall(function()
		apply(first)
	end)
	if not ok then
		warn(`[Turbo Ball] Couldn't open the menu: {err}`)
	end
	Transition.reveal()
end

return GameFlow
