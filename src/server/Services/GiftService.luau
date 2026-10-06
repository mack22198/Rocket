--!strict
-- Playtime gifts (see Gifts): the clock starts when a player joins, and each gift can be opened once it's been
-- long enough. The player's PlayStart attribute (server time) lets their screen count down, and GiftsOpened lists
-- the gifts already opened ("1,2,3").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gifts = require(Shared.Config.Gifts)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local DataService = require(script.Parent.DataService)

local GiftService = {}

local startedAt: { [Player]: number } = {}
local opened: { [Player]: { [number]: boolean } } = {}

local function publish(player: Player)
	local list = {}
	local mine: { [number]: boolean } = opened[player] or {}
	for index in mine do
		table.insert(list, tostring(index))
	end
	table.sort(list)
	player:SetAttribute(MatchState.PlayerAttr.GiftsOpened, table.concat(list, ","))
end

local function open(player: Player, index: unknown): { [string]: any }
	local started = startedAt[player]
	local mine = opened[player]
	if type(index) ~= "number" or not started or not mine or not DataService.get(player) then
		return { ok = false }
	end
	local played = workspace:GetServerTimeNow() - started
	if not Gifts.ready(index, played, mine) then
		return { ok = false }
	end
	local gift = Gifts.Ladder[index]
	mine[index] = true
	DataService.update(player, function(data)
		if gift.Kind == "boost" then
			data.scrapBoost = math.min(data.scrapBoost + gift.Amount, 10)
		else
			data.scrap += gift.Amount
		end
	end)
	publish(player)
	local emoji, text = Gifts.describe(gift)
	return { ok = true, emoji = emoji, text = text }
end

function GiftService.init()
	local function onPlayerAdded(player: Player)
		startedAt[player] = workspace:GetServerTimeNow()
		opened[player] = {}
		player:SetAttribute(MatchState.PlayerAttr.PlayStart, startedAt[player])
		publish(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		startedAt[player] = nil
		opened[player] = nil
	end)
	Remotes.Gift.OnServerInvoke = open
end

return GiftService
