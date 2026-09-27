--!strict
-- The podium moment at the end of a match: the real cars step out of the picture, the top three appear on
-- the winners' podium in the middle of the pitch (MVP on top), the camera drifts in front of it and confetti and
-- fireworks go off. It lasts until you leave the match screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)

local PodiumBuilder = require(script.Parent.Parent.Showroom.PodiumBuilder)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local LocalHide = require(script.Parent.LocalHide)

local PodiumController = {}

local holder: Folder? = nil
local cameraFrame: ((dt: number) -> (CFrame?, number))? = nil

local function carsFolder(): Instance?
	local match = workspace:FindFirstChild(MatchState.Folders.Match)
	return if match then match:FindFirstChild(MatchState.Folders.Cars) else nil
end

-- Reads the podium list from the match results (it came over the network, so check everything).
local function entriesFrom(list: unknown): { PodiumBuilder.Entry }
	local entries: { PodiumBuilder.Entry } = {}
	if type(list) ~= "table" then
		return entries
	end
	for _, item in list :: { any } do
		if type(item) == "table" and type(item.name) == "string" and type(item.carId) == "string" then
			table.insert(entries, {
				name = item.name,
				team = if type(item.team) == "string" then item.team else "",
				carId = item.carId,
				stage = if type(item.stage) == "number" then item.stage else 1,
				points = if type(item.points) == "number" then item.points else 0,
				topper = if type(item.topper) == "string" and item.topper ~= "" then item.topper else nil,
			})
		end
		if #entries == 3 then
			break
		end
	end
	return entries
end

function PodiumController.isShowing(): boolean
	return holder ~= nil
end

function PodiumController.show(podium: unknown, winner: unknown)
	PodiumController.stop()
	local entries = entriesFrom(podium)
	if #entries == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Podium"
	folder.Parent = workspace.CurrentCamera or workspace
	holder = folder
	PodiumBuilder.build(folder, entries)
	local cars = carsFolder()
	if cars then
		LocalHide.setAll(cars, true)
	end

	local started = os.clock()
	local function frameCamera(_dt: number): (CFrame?, number)
		return PodiumBuilder.cameraCFrame(os.clock() - started), 55
	end
	cameraFrame = frameCamera
	CameraController.setProvider(frameCamera)

	local teamInfo = if type(winner) == "string" then (GameConfig.Teams :: any)[winner] else nil
	local color = if teamInfo then teamInfo.Color else Color3.fromRGB(255, 214, 90)
	EffectsController.party(PodiumBuilder.Origin + Vector3.new(0, 6, 0), color)
	-- A second round of fireworks a little later.
	task.delay(2.5, function()
		if holder == folder then
			EffectsController.party(PodiumBuilder.Origin + Vector3.new(0, 6, 0), color)
		end
	end)
end

function PodiumController.stop()
	if cameraFrame then
		CameraController.releaseProvider(cameraFrame)
		cameraFrame = nil
	end
	if holder then
		holder:Destroy()
		holder = nil
		local cars = carsFolder()
		if cars then
			LocalHide.setAll(cars, false)
		end
	end
end

function PodiumController.start()
	-- Cars that turn up while the podium is showing stay hidden too.
	RunService.Heartbeat:Connect(function()
		local cars = if holder then carsFolder() else nil
		if cars then
			LocalHide.setAll(cars, true)
		end
	end)
end

return PodiumController
