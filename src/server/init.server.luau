--!strict
-- Server entry point: builds the stadium, starts every service, then runs the match loop forever.

local Services = script:WaitForChild("Services")
local Arena = script:WaitForChild("Arena")

local ArenaBuilder = require(Arena.ArenaBuilder)
local LobbyBuilder = require(Arena.LobbyBuilder)

local BallService = require(Services.BallService)
local BoostPadService = require(Services.BoostPadService)
local CarService = require(Services.CarService)
local DataService = require(Services.DataService)
local GarageService = require(Services.GarageService)
local MatchService = require(Services.MatchService)
local StatsService = require(Services.StatsService)

local arenaFolder, arenaShape = ArenaBuilder.build()
LobbyBuilder.build()

DataService.start()
GarageService.init()
CarService.init(arenaFolder)
BallService.init(arenaShape)
StatsService.init(arenaShape)
BoostPadService.init()
MatchService.start()

print("[Turbo Ball] Server ready!")
