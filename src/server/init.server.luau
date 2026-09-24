--!strict
-- Server entry point: builds the stadium and the world around it, starts every service, then runs the match
-- loop forever.

local Services = script:WaitForChild("Services")
local Arena = script:WaitForChild("Arena")

local ArenaBuilder = require(Arena.ArenaBuilder)
local EnvironmentBuilder = require(Arena.EnvironmentBuilder)
local LobbyBuilder = require(Arena.LobbyBuilder)
local StadiumBuilder = require(Arena.StadiumBuilder)

local BallService = require(Services.BallService)
local BoostPadService = require(Services.BoostPadService)
local CarService = require(Services.CarService)
local DataService = require(Services.DataService)
local GarageService = require(Services.GarageService)
local MatchService = require(Services.MatchService)
local StatsService = require(Services.StatsService)

local arenaFolder, arenaShape = ArenaBuilder.build()
StadiumBuilder.build()
LobbyBuilder.build()

DataService.start()
GarageService.init()
CarService.init(arenaFolder)
BallService.init(arenaShape)
StatsService.init(arenaShape)
BoostPadService.init()
MatchService.start()

-- The scenery outside the stadium takes a moment to fill in, and nothing in the game needs it, so it comes last.
task.defer(EnvironmentBuilder.build)

print("[Turbo Ball] Server ready!")
