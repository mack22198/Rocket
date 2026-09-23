--!strict
-- Turns ball touches into stats, style moves, combos, saves and shots, and announces the cool moments.
-- A kid who loses 8-3 should still walk away thinking "I did that sick aerial".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallSim = require(Shared.Physics.BallSim)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)

local Roster = require(script.Parent.Parent.Match.Roster)
local CarService = require(script.Parent.CarService)
local BallService = require(script.Parent.BallService)

type Participant = Roster.Participant
type Team = Roster.Team

export type GoalSummary = {
	team: Team,
	scorer: Participant?,
	assist: Participant?,
	comboText: string?,
	ownGoal: boolean,
}

type TouchRecord = { participant: Participant, time: number }
type Chain = { elements: { [string]: boolean }, lastTime: number }

local StatsService = {}

local arena: ArenaShape.Arena
local touches: { TouchRecord } = {}
local chains: { [Team]: Chain } = {
	Blue = { elements = {}, lastTime = -math.huge },
	Orange = { elements = {}, lastTime = -math.huge },
}

local S = GameConfig.Style
local P = GameConfig.Points

local function announce(kind: string, text: string, team: Team?, name: string?)
	Remotes.Announce:FireAllClients(kind, text, team or "", name or "")
end

local function resetChain(team: Team)
	chains[team] = { elements = {}, lastTime = -math.huge }
end

local function styleOf(info: BallService.TouchInfo): string?
	local position = info.carCFrame.Position
	local wallDistance = arena:wallDistance(position)
	if position.Y >= S.AirHitHeight and wallDistance > S.WallHitDistance * 1.5 then
		return "AIR"
	elseif position.Y >= S.WallHitHeight and wallDistance <= S.WallHitDistance then
		return "WALL"
	end
	return nil
end

local function onTouch(info: BallService.TouchInfo)
	local p = info.participant
	local stats = p.stats
	local team: Team = p.team
	local now = info.time

	stats.touches += 1
	stats.points += P.Touch

	-- Style moves.
	local style = styleOf(info)
	if style then
		stats.styleTouches += 1
		stats.points += P.Style
		announce("style", if style == "AIR" then "AIR HIT!" else "WALL HIT!", team, p.name)
	end
	if info.mega then
		stats.megaShots += 1
		stats.points += P.MegaShot
		announce("mega", "MEGA SHOT!", team, p.name)
	end

	-- Shots and saves: where was the ball heading before and after this touch?
	local ballCfg = GameConfig.Ball
	local ownSide = GameConfig.Teams[team].DefendsSide
	local before = BallSim.predictGoal(arena, ballCfg, info.before, S.ShotLookahead)
	local after = BallSim.predictGoal(arena, ballCfg, info.after, S.ShotLookahead)
	local megaGain = if style then GameConfig.Mega.PerStyleTouch else GameConfig.Mega.PerTouch
	if before == ownSide and after ~= ownSide then
		stats.saves += 1
		stats.points += P.Save
		megaGain += GameConfig.Mega.PerSave
		local epic = info.before.velocity.Magnitude > 120
		announce("save", if epic then "EPIC SAVE!" else "SAVE!", team, p.name)
	elseif after == -ownSide and before ~= -ownSide then
		stats.shots += 1
		stats.points += P.Shot
		megaGain += GameConfig.Mega.PerShot
	end
	if not info.mega then
		CarService.addMega(p, megaGain)
	end

	-- Combos: consecutive touches by one team chain together.
	local chain = chains[team]
	if now - chain.lastTime > S.ComboWindow then
		resetChain(team)
		chain = chains[team]
	end
	local last = touches[#touches]
	if last and last.participant ~= p and last.participant.team == team and now - last.time <= S.ComboWindow then
		chain.elements.PASS = true
	end
	if style then
		chain.elements[style] = true
	end
	if info.mega then
		chain.elements.MEGA = true
	end
	chain.lastTime = now
	resetChain(Roster.otherTeam(team))

	table.insert(touches, { participant = p, time = now })
	while #touches > 40 do
		table.remove(touches, 1)
	end
end

local function comboText(chain: Chain, ballSpeed: number): string?
	local count = 0
	for _ in chain.elements do
		count += 1
	end
	if count >= 2 then
		return `🔥 {count + 1}X COMBO!`
	elseif chain.elements.MEGA then
		return "💥 MEGA GOAL!"
	elseif chain.elements.AIR then
		return "🔥 AIR COMBO!"
	elseif chain.elements.WALL then
		return "🚀 WALL SHOT!"
	elseif chain.elements.PASS then
		return "🤝 TEAM GOAL!"
	elseif ballSpeed > 160 then
		return "💥 SUPER GOAL!"
	end
	return nil
end

-- Works out who scored (the last toucher on the scoring team) and who assisted.
function StatsService.goal(side: number, ballSpeed: number): GoalSummary
	local team: Team = if GameConfig.Teams.Blue.DefendsSide == side then "Orange" else "Blue"
	local scorer: TouchRecord? = nil
	local assist: TouchRecord? = nil
	for i = #touches, 1, -1 do
		local touch = touches[i]
		if touch.participant.team == team then
			if not scorer then
				scorer = touch
			elseif touch.participant ~= scorer.participant then
				if scorer.time - touch.time <= S.AssistWindow then
					assist = touch
				end
				break
			end
		end
	end

	local chain = chains[team]
	local text = if scorer and scorer.time - chain.lastTime <= S.ComboWindow then comboText(chain, ballSpeed) else nil
	if scorer then
		local stats = scorer.participant.stats
		stats.goals += 1
		stats.points += P.Goal
		if text then
			stats.styleTouches += 1
			stats.points += P.Style
		end
	end
	if assist then
		assist.participant.stats.assists += 1
		assist.participant.stats.points += P.Assist
	end
	resetChain("Blue")
	resetChain("Orange")
	table.clear(touches)
	return {
		team = team,
		scorer = if scorer then scorer.participant else nil,
		assist = if assist then assist.participant else nil,
		comboText = text,
		ownGoal = scorer == nil,
	}
end

function StatsService.announce(kind: string, text: string, team: Team?, name: string?)
	announce(kind, text, team, name)
end

function StatsService.resetMatch()
	table.clear(touches)
	resetChain("Blue")
	resetChain("Orange")
end

-- Forget the touch history of someone who left (they can't be credited any more).
function StatsService.forget(p: Participant)
	for i = #touches, 1, -1 do
		if touches[i].participant == p then
			table.remove(touches, i)
		end
	end
end

function StatsService.init(shape: ArenaShape.Arena)
	arena = shape
	BallService.Touched:Connect(onTouch)
end

return StatsService
