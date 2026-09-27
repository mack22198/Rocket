--!strict
-- Server entry point: builds the stadium and the world around it, starts every service, then runs the match
-- loop forever.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script:WaitForChild("Services")
local Arena = script:WaitForChild("Arena")
local CarModelBuilder = require(ReplicatedStorage:WaitForChild("Shared").Cars.CarModelBuilder)

local ArenaBuilder = require(Arena.ArenaBuilder)
local EnvironmentBuilder = require(Arena.EnvironmentBuilder)
local LobbyBuilder = require(Arena.LobbyBuilder)
local StadiumBuilder = require(Arena.StadiumBuilder)

local BallService = require(Services.BallService)
local BoostPadService = require(Services.BoostPadService)
local CarService = require(Services.CarService)
local DailyService = require(Services.DailyService)
local DataService = require(Services.DataService)
local GarageService = require(Services.GarageService)
local ItemService = require(Services.ItemService)
local MatchService = require(Services.MatchService)
local PowerService = require(Services.PowerService)
local SeasonService = require(Services.SeasonService)
local StatsService = require(Services.StatsService)

-- The smooth car bodies from Blender (assets/meshes/TurboBallCars.fbx), if they've been imported in Studio. Imported
-- into the Workspace, they're moved to ReplicatedStorage so they're out of sight and every player can use them.
local carMeshes = ReplicatedStorage:FindFirstChild("CarMeshes") or ReplicatedStorage:FindFirstChild("TurboBallCars")
if not carMeshes then
	local imported = workspace:FindFirstChild("TurboBallCars") or workspace:FindFirstChild("CarMeshes")
	if imported then
		imported.Parent = ReplicatedStorage
		carMeshes = imported
	end
end
CarModelBuilder.setMeshLibrary(carMeshes)
print(
	if carMeshes then "[Turbo Ball] Smooth car meshes found." else "[Turbo Ball] No car meshes imported; using parts."
)

local arenaFolder, arenaShape = ArenaBuilder.build()
StadiumBuilder.build()
LobbyBuilder.build()

DataService.start()
GarageService.init()
DailyService.init()
SeasonService.init()
CarService.init(arenaFolder)
BallService.init(arenaShape)
StatsService.init(arenaShape)
BoostPadService.init()
ItemService.init()
PowerService.init(arenaFolder)
MatchService.start()

-- The scenery outside the stadium takes a moment to fill in, and nothing in the game needs it, so it comes last.
task.defer(EnvironmentBuilder.build)

print("[Turbo Ball] Server ready!")
