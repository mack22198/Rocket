--!strict
-- The match's public state lives as attributes on ReplicatedStorage.MatchState, so every client (including
-- players who join late) always sees the current score, clock and phase without extra messages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchState = {}

MatchState.Phases = {
	Waiting = "Waiting", -- nobody here yet
	Intermission = "Intermission", -- lobby / garage time between matches
	Countdown = "Countdown", -- 3-2-1 before a kickoff
	Playing = "Playing",
	GoalScored = "GoalScored", -- celebration pause
	Results = "Results", -- end of match screen
}

-- Attributes on the MatchState object.
MatchState.Attr = {
	Phase = "Phase",
	PhaseEndsAt = "PhaseEndsAt", -- server time when the current phase timer runs out
	MatchId = "MatchId",
	BlueScore = "BlueScore",
	OrangeScore = "OrangeScore",
	ClockRunning = "ClockRunning",
	ClockRemaining = "ClockRemaining", -- seconds left when the clock was last paused
	ClockEndsAt = "ClockEndsAt", -- server time when the clock hits zero (while running)
	Overtime = "Overtime",
	OvertimeStartedAt = "OvertimeStartedAt",
	OvertimeElapsed = "OvertimeElapsed",
	WaitingForBall = "WaitingForBall", -- 0:00 but the ball is still in the air
	Banner = "Banner", -- short status text shown in the lobby
}

-- Attributes on every car model.
MatchState.CarAttr = {
	OwnerUserId = "OwnerUserId", -- 0 for bots
	IsBot = "IsBot",
	DriverName = "DriverName",
	Team = "Team",
	CarId = "CarId",
	Boost = "Boost",
	Boosting = "Boosting",
	Mega = "Mega",
	MegaArmed = "MegaArmed",
}

-- Names of the folders the server puts in Workspace.
MatchState.Folders = {
	Arena = "Arena",
	Lobby = "Lobby",
	Match = "Match",
	Cars = "Cars",
	BoostPads = "BoostPads",
}

local OBJECT_NAME = "MatchState"

function MatchState.getObject(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(OBJECT_NAME)
		if existing then
			return existing
		end
		local object = Instance.new("Configuration")
		object.Name = OBJECT_NAME
		object:SetAttribute(MatchState.Attr.Phase, MatchState.Phases.Waiting)
		object:SetAttribute(MatchState.Attr.MatchId, 0)
		object:SetAttribute(MatchState.Attr.BlueScore, 0)
		object:SetAttribute(MatchState.Attr.OrangeScore, 0)
		object:SetAttribute(MatchState.Attr.ClockRunning, false)
		object:SetAttribute(MatchState.Attr.ClockRemaining, 0)
		object:SetAttribute(MatchState.Attr.ClockEndsAt, 0)
		object:SetAttribute(MatchState.Attr.Overtime, false)
		object:SetAttribute(MatchState.Attr.OvertimeElapsed, 0)
		object:SetAttribute(MatchState.Attr.WaitingForBall, false)
		object:SetAttribute(MatchState.Attr.PhaseEndsAt, 0)
		object:SetAttribute(MatchState.Attr.Banner, "")
		object.Parent = ReplicatedStorage
		return object
	end
	return ReplicatedStorage:WaitForChild(OBJECT_NAME)
end

local function numberAttr(object: Instance, name: string): number
	local value = object:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Seconds to show on the scoreboard clock. In overtime this counts up.
function MatchState.clockSeconds(object: Instance, serverNow: number): number
	if object:GetAttribute(MatchState.Attr.Overtime) == true then
		local elapsed = numberAttr(object, MatchState.Attr.OvertimeElapsed)
		if object:GetAttribute(MatchState.Attr.ClockRunning) == true then
			elapsed += serverNow - numberAttr(object, MatchState.Attr.OvertimeStartedAt)
		end
		return math.max(0, elapsed)
	end
	if object:GetAttribute(MatchState.Attr.ClockRunning) == true then
		return math.max(0, numberAttr(object, MatchState.Attr.ClockEndsAt) - serverNow)
	end
	return math.max(0, numberAttr(object, MatchState.Attr.ClockRemaining))
end

function MatchState.phase(object: Instance): string
	local value = object:GetAttribute(MatchState.Attr.Phase)
	return if type(value) == "string" then value else MatchState.Phases.Waiting
end

function MatchState.phaseSecondsLeft(object: Instance, serverNow: number): number
	return math.max(0, numberAttr(object, MatchState.Attr.PhaseEndsAt) - serverNow)
end

function MatchState.formatClock(seconds: number): string
	local whole = math.ceil(seconds)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return MatchState
