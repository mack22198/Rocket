--!strict
-- Unlocking, equipping and evolving cars. Prices are fixed and shown up front: no random boxes.
-- Evolving is free once a car has earned enough XP; players can also switch back to any look they've unlocked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Evolution = require(Shared.Config.Evolution)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local GarageService = {}

type Result = { ok: boolean, message: string, evolved: boolean? }

local lastRequest: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.25 then
		return true
	end
	lastRequest[player] = now
	return false
end

local function handle(player: Player, action: unknown, carId: unknown, extra: unknown): Result
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
		local look = data.carLook[def.Id] or 1
		return { ok = true, message = `{CarCatalog.stageName(def, look)} equipped! You'll drive it next match.` }
	elseif action == "evolve" then
		if not data.owned[def.Id] then
			return { ok = false, message = "Unlock this car first." }
		end
		local stage = data.carStage[def.Id] or 1
		local progress = Evolution.progress(def, data.carXp[def.Id] or 0, stage)
		if not progress.nextStage then
			return { ok = false, message = `The {CarCatalog.stageName(def, stage)} is fully evolved!` }
		elseif not progress.ready then
			return { ok = false, message = `{progress.xpForNext - progress.xp} more XP to evolve. Keep driving it!` }
		end
		local newStage = stage + 1
		DataService.update(player, function(d)
			d.carStage[def.Id] = newStage
			d.carLook[def.Id] = newStage
		end)
		DataService.saveNow(player)
		return {
			ok = true,
			evolved = true,
			message = `✨ It evolved into the {CarCatalog.stageName(def, newStage)}! ✨`,
		}
	elseif action == "look" then
		if not data.owned[def.Id] then
			return { ok = false, message = "Unlock this car first." }
		end
		local reached = data.carStage[def.Id] or 1
		if type(extra) ~= "number" or extra ~= math.floor(extra) or extra < 1 or extra > reached then
			return { ok = false, message = "Evolve this car to unlock that look." }
		end
		DataService.update(player, function(d)
			d.carLook[def.Id] = extra
		end)
		return { ok = true, message = `Looking good! {CarCatalog.stageName(def, extra)} selected.` }
	end
	return { ok = false, message = "Unknown action." }
end

function GarageService.init()
	Remotes.Garage.OnServerInvoke = function(player: Player, action: unknown, carId: unknown, extra: unknown)
		return handle(player, action, carId, extra)
	end
	Remotes.GetPlayerData.OnServerInvoke = function(player: Player)
		return DataService.clientView(player)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return GarageService
