--!strict
-- Decides what's on screen: the main menu or the garage (both over the 3D showroom), or the match.
-- The server says where you are - the Status attribute on your Player: "Menu", "Queued" (pressed PLAY and
-- waiting) or "Playing" - and the garage is opened on top of the menu from here. Switching between the
-- showroom and the stadium fades through black.
-- In a match it also runs the big moments: goal replays (the HUD steps aside) and, at the final whistle, the
-- winners' podium followed by the results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local UI = script.Parent.Parent.UI
local Announcer = require(UI.Announcer)
local Coach = require(UI.Coach)
local QuickChatPanel = require(UI.QuickChatPanel)
local CollectionBook = require(UI.CollectionBook)
local DailyRewards = require(UI.DailyRewards)
local Garage = require(UI.Garage)
local HowToPlay = require(UI.HowToPlay)
local HUD = require(UI.HUD)
local MainMenu = require(UI.MainMenu)
local PauseMenu = require(UI.PauseMenu)
local ProfilePanel = require(UI.ProfilePanel)
local ReplayScreen = require(UI.ReplayScreen)
local ResultsScreen = require(UI.ResultsScreen)
local SeasonTrack = require(UI.SeasonTrack)
local TouchControls = require(UI.TouchControls)
local Transition = require(UI.Transition)

local InputController = require(script.Parent.InputController)
local PlayerDataClient = require(script.Parent.PlayerDataClient)
local PodiumController = require(script.Parent.PodiumController)
local ReplayController = require(script.Parent.ReplayController)
local ShowroomController = require(script.Parent.ShowroomController)
local SoundController = require(script.Parent.SoundController)
local TwistController = require(script.Parent.TwistController)

local GameFlow = {}

export type Screen = string -- "Menu", "Garage" or "Match"

local localPlayer = Players.LocalPlayer
local Status = MatchState.Status

local screen: Screen? = nil
local garageWanted = false
local garageCar: string? = nil
local pauseOpen = false
local replaying = false
local resultsToken = 0

-- How long the podium shows on its own before the results panel slides in.
local PODIUM_SECONDS = 4.5

-- The car gets no input while a menu or a replay is on screen.
local function updateBlocked()
	InputController.setBlocked(pauseOpen or replaying)
end

-- Is one of the menu's pop-up screens open (so the streak reward shouldn't pop up over it)?
local function overlayOpen(): boolean
	return HowToPlay.isOpen() or CollectionBook.isOpen() or SeasonTrack.isOpen() or ProfilePanel.isOpen()
end

-- The match HUD, the announcer feed and the touch buttons, together.
local function setMatchOverlay(on: boolean)
	HUD.setVisible(on)
	Announcer.setVisible(on)
	Coach.setVisible(on)
	QuickChatPanel.setVisible(on)
	TouchControls.setHidden(not on)
end

local function showEquippedCar()
	local data = PlayerDataClient.get()
	local def = CarCatalog.get(data.equipped) or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
	ShowroomController.showCar(def, data.carLook[def.Id] or 1, data.style.topper)
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
	-- Whatever was left over from the last match (a replay, the podium) goes away.
	resultsToken += 1
	PodiumController.stop()
	ReplayController.setEnabled(inMatch)
	ReplayScreen.hide()
	ResultsScreen.hide()
	-- The showroom and a Neon Night twist both change the lighting; each hands it back before the other starts.
	if inMatch then
		ShowroomController.setActive(false)
		TwistController.setInMatch(true)
	else
		TwistController.setInMatch(false)
		ShowroomController.setActive(true)
	end
	setMatchOverlay(inMatch)
	SoundController.setScene(if inMatch then "match" else "menu")
	if inMatch then
		garageWanted = false
		MainMenu.hide()
		Garage.close()
		HowToPlay.close()
		DailyRewards.close()
		CollectionBook.close()
		SeasonTrack.close()
		ProfilePanel.close()
		return
	end
	PauseMenu.close()
	if target == "Garage" then
		ShowroomController.setMode("garage")
		MainMenu.hide()
		Garage.open(garageCar)
	else
		ShowroomController.setMode("menu")
		Garage.close()
		showEquippedCar()
		MainMenu.show()
		-- First visit to the menu today: here's your streak reward.
		task.delay(0.8, function()
			if screen == "Menu" and not overlayOpen() then
				DailyRewards.offerStreak()
			end
		end)
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
	elseif DailyRewards.isOpen() then
		DailyRewards.close()
	elseif CollectionBook.isOpen() then
		CollectionBook.close()
	elseif SeasonTrack.isOpen() then
		SeasonTrack.close()
	elseif ProfilePanel.isOpen() then
		ProfilePanel.close()
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
	MainMenu.CollectionPressed:Connect(function()
		CollectionBook.open()
	end)
	MainMenu.SeasonPressed:Connect(function()
		SeasonTrack.open()
	end)
	MainMenu.ProfilePressed:Connect(function()
		ProfilePanel.open()
	end)
	MainMenu.StreakPressed:Connect(function()
		DailyRewards.openStreak()
	end)
	MainMenu.ChestPressed:Connect(function()
		DailyRewards.openChest()
	end)
	Garage.BackPressed:Connect(closeGarage)

	HUD.MenuRequested:Connect(function()
		PauseMenu.open()
	end)
	PauseMenu.Toggled:Connect(function(open: boolean)
		pauseOpen = open
		updateBlocked()
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
	-- Goal replays: the HUD steps aside while one plays (and SKIP ends it).
	ReplayController.Started:Connect(function(scorer: string, team: string, combo: string)
		replaying = true
		updateBlocked()
		setMatchOverlay(false)
		ReplayScreen.show(scorer, team, combo)
	end)
	ReplayController.Finished:Connect(function()
		replaying = false
		updateBlocked()
		ReplayScreen.hide()
		if screen == "Match" and not PodiumController.isShowing() then
			setMatchOverlay(true)
		end
	end)
	ReplayScreen.SkipPressed:Connect(ReplayController.stop)

	-- The final whistle: the winners' podium with a big headline, then the results panel.
	Remotes.MatchResults.OnClientEvent:Connect(function(payload: unknown)
		PauseMenu.close()
		if type(payload) ~= "table" or screen ~= "Match" then
			return
		end
		local results = payload :: { [string]: any }
		ReplayController.stop()
		setMatchOverlay(false)
		resultsToken += 1
		local token = resultsToken
		PodiumController.show(results.podium, results.winner)
		local delay = if PodiumController.isShowing() then PODIUM_SECONDS else 0
		if delay > 0 then
			ResultsScreen.showHeadline(results)
		end
		task.delay(delay, function()
			if token == resultsToken and screen == "Match" then
				ResultsScreen.show(results)
			end
		end)
	end)

	-- The car on the turntable follows the car you drive (while the garage isn't choosing one).
	PlayerDataClient.Changed:Connect(function()
		if screen == "Menu" then
			showEquippedCar()
			if not DailyRewards.isOpen() and not overlayOpen() then
				DailyRewards.offerStreak()
			end
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
