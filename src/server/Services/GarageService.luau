--!strict
-- Unlocking and equipping cars. Prices are fixed and shown up front: no random boxes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local GarageService = {}

type Result = { ok: boolean, message: string }

local lastRequest: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.25 then
		return true
	end
	lastRequest[player] = now
	return false
end

local function handle(player: Player, action: unknown, carId: unknown): Result
	if throttled(player) then
		return { ok = false, message = "Slow down!" }
	end
	if type(carId) ~= "string" then
		return { ok = false, message = "Unknown car." }
	end
	local def = CarCatalog.get(carId)
	if not def then
		return { ok = false, message = "Unknown car." }
	end
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Your garage is still loading..." }
	end

	if action == "unlock" then
		if data.owned[def.Id] then
			return { ok = false, message = "You already own this car." }
		end
		if data.scrap < def.Price then
			return { ok = false, message = `You need {def.Price - data.scrap} more Scrap.` }
		end
		DataService.update(player, function(d)
			d.scrap -= def.Price
			d.owned[def.Id] = true
			d.equipped = def.Id
		end)
		DataService.saveNow(player)
		return { ok = true, message = `{def.Emoji} {def.DisplayName} unlocked! You'll drive it next match.` }
	elseif action == "equip" then
		if not data.owned[def.Id] then
			return { ok = false, message = "Unlock this car first." }
		end
		DataService.update(player, function(d)
			d.equipped = def.Id
		end)
		return { ok = true, message = `{def.DisplayName} equipped! You'll drive it next match.` }
	end
	return { ok = false, message = "Unknown action." }
end

function GarageService.init()
	Remotes.Garage.OnServerInvoke = function(player: Player, action: unknown, carId: unknown)
		return handle(player, action, carId)
	end
	Remotes.GetPlayerData.OnServerInvoke = function(player: Player)
		return DataService.clientView(player)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return GarageService
