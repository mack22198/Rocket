--!strict
-- Quick chat in matches (see QuickChat). A message is only ever one of the preset phrases, from someone in the
-- match, not too often, and only from a player whose Roblox settings allow chat. It's shown to everyone in the
-- match whose settings allow them to see chat from that player. Bots say something now and then when a goal
-- goes in or a team-mate makes a save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared.Match.MatchState)
local QuickChat = require(Shared.Config.QuickChat)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)

type Participant = Roster.Participant

local QuickChatService = {}

local rng = Random.new()
local history: { [Player]: { number } } = {}
local canChat: { [Player]: boolean } = {}
local canSeeCache: { [string]: boolean } = {}
local lastBotLine = -math.huge
local BOT_GAP = 3 -- seconds between two bot messages
local LEEWAY = 0.3 -- players' own screens keep to the limits; this allows for messages bunching up on the way

-- If Roblox can't tell us (it can't in Studio), Studio says yes so it can be tested; a live game says no.
local function ask(question: () -> boolean): boolean
	local ok, answer = pcall(question)
	if ok then
		return answer == true
	end
	return RunService:IsStudio()
end

local function allowedToChat(player: Player): boolean
	local known = canChat[player]
	if known ~= nil then
		return known
	end
	local allowed = ask(function()
		return TextChatService:CanUserChatAsync(player.UserId)
	end)
	canChat[player] = allowed
	player:SetAttribute(MatchState.PlayerAttr.QuickChat, allowed)
	return allowed
end

-- Can `to` see a message from `from` (nil = a bot)?
local function canSee(from: Player?, to: Player): boolean
	if not allowedToChat(to) then
		return false
	elseif from == nil or from == to then
		return true
	end
	local key = `{from.UserId}>{to.UserId}`
	local known = canSeeCache[key]
	if known == nil then
		known = ask(function()
			return TextChatService:CanUsersChatAsync(from.UserId, to.UserId)
		end)
		canSeeCache[key] = known
	end
	return known == true
end

local function deliver(p: Participant, index: number)
	local car = p.car
	if not car then
		return
	end
	for _, other in Roster.humans() do
		local player = other.player
		if player and player.Parent == Players and canSee(p.player, player) then
			Remotes.QuickChatShown:FireClient(player, car, index, p.name, p.team)
		end
	end
end

local function onQuickChat(player: Player, index: unknown)
	if type(index) ~= "number" or not QuickChat.phrase(index) then
		return
	end
	local p = Roster.byPlayer(player)
	if not p or not p.car or not allowedToChat(player) then
		return
	end
	local mine = history[player] or {}
	history[player] = mine
	if QuickChat.allow(mine, os.clock(), LEEWAY) then
		deliver(p, index)
	end
end

-- Something happened that a bot might chat about: "goal" (`team` scored), "conceded" (`team` was scored on) or
-- "save" (someone on `team` made a save). One of the team's bots - not `except`, who did it - may say something.
function QuickChatService.react(event: string, team: Roster.Team, except: Participant?)
	local now = os.clock()
	if now - lastBotLine < BOT_GAP then
		return
	end
	local speakers: { Participant } = {}
	for _, other in Roster.onTeam(team) do
		if other.isBot and other.car and other ~= except then
			table.insert(speakers, other)
		end
	end
	local index = QuickChat.botLine(event, rng:NextNumber(), rng:NextNumber())
	if #speakers == 0 or not index then
		return
	end
	lastBotLine = now
	local speaker = speakers[rng:NextInteger(1, #speakers)]
	task.delay(rng:NextNumber(0.3, 0.8), function()
		if speaker.car then
			deliver(speaker, index)
		end
	end)
end

function QuickChatService.init()
	Remotes.QuickChat.OnServerEvent:Connect(onQuickChat)
	local function onPlayerAdded(player: Player)
		allowedToChat(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		history[player] = nil
		canChat[player] = nil
	end)
end

return QuickChatService
