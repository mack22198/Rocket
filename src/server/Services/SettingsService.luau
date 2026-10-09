--!strict
-- Player settings the server needs: driving help (see DriveAssist), which the server's hit maths uses too. Saved
-- with the player's progress, and shared as the player's Assist attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local SettingsService = {}

local function apply(player: Player)
	local data = DataService.get(player)
	if data then
		player:SetAttribute(MatchState.PlayerAttr.Assist, data.settings.assist)
	end
end

function SettingsService.init()
	DataService.Loaded:Connect(apply)
	Remotes.Settings.OnServerInvoke = function(player: Player, key: unknown, value: unknown)
		if key ~= "assist" or type(value) ~= "boolean" or not DataService.get(player) then
			return { ok = false }
		end
		DataService.update(player, function(data)
			data.settings.assist = value
		end)
		apply(player)
		return { ok = true }
	end
end

return SettingsService
