--!strict
-- The game loop:  lobby/garage -> 3v3 match (kickoff, 5:00 clock, goals, overtime) -> results + Scrap -> repeat.
-- Empty seats are filled with bots. Players who join mid-match take over a bot's seat straight away,
-- and a bot takes over for anyone who leaves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local MathUtil = require(Shared.Util.MathUtil)
local Remotes = require(Shared.Net.Remotes)
local Rewards = require(Shared.Config.Rewards)

local Roster = require(script.Parent.Parent.Match.Roster)
local BallService = require(script.Parent.BallService)
local BotService = require(script.Parent.BotService)
local BoostPadService = require(script.Parent.BoostPadService)
local BumpService = require(script.Parent.BumpService)
local CarService = require(script.Parent.CarService)
local DataService = require(script.Parent.DataService)
local StatsService = require(script.Parent.StatsService)

type Participant = Roster.Participant
type Team = Roster.Team

local MatchService = {}

local Phases = MatchState.Phases
local Attr = MatchState.Attr
local M = GameConfig.Match
local TEAMS: { Team } = { "Blue", "Orange" }

local stateObject = MatchState.getObject()
local rng = Random.new()

local blueScore, orangeScore = 0, 0
local overtime = false
local clockRemaining = 0
local clockRunning = false
local clockEndsAt = 0
local overtimeElapsed = 0
local overtimeStartedAt = 0
local matchRunning = false
local pendingGoal: { side: number, position: Vector3 }? = nil
local botCounter = 0
local inMatch: { [Player]: boolean } = {}

-- Kickoff spots for one team, as (x, distance from the centre line). Mirrored for the other team.
local KICKOFF_SPOTS = {
	Vector2.new(-48, 70),
	Vector2.new(48, 70),
	Vector2.new(0, 125),
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function set(name: string, value: any)
	stateObject:SetAttribute(name, value)
end

local function setPhase(phase: string, duration: number?)
	set(Attr.Phase, phase)
	set(Attr.PhaseEndsAt, if duration then serverNow() + duration else 0)
end

local function matchLength(): number
	if RunService:IsStudio() and GameConfig.Debug.StudioMatchLength then
		return GameConfig.Debug.StudioMatchLength
	end
	return M.Length
end

local function intermissionLength(): number
	if RunService:IsStudio() and GameConfig.Debug.StudioIntermission then
		return GameConfig.Debug.StudioIntermission
	end
	return M.Intermission
end

---------------------------------------------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------------------------------------------

local function startClock()
	if clockRunning then
		return
	end
	clockRunning = true
	if overtime then
		overtimeStartedAt = serverNow()
		set(Attr.OvertimeStartedAt, overtimeStartedAt)
	else
		clockEndsAt = serverNow() + clockRemaining
		set(Attr.ClockEndsAt, clockEndsAt)
	end
	set(Attr.ClockRunning, true)
end

local function stopClock()
	if not clockRunning then
		return
	end
	clockRunning = false
	if overtime then
		overtimeElapsed += serverNow() - overtimeStartedAt
		set(Attr.OvertimeElapsed, overtimeElapsed)
	else
		clockRemaining = math.max(0, clockEndsAt - serverNow())
		set(Attr.ClockRemaining, clockRemaining)
	end
	set(Attr.ClockRunning, false)
end

local function regulationLeft(): number
	if clockRunning and not overtime then
		return math.max(0, clockEndsAt - serverNow())
	end
	return clockRemaining
end

local function overtimeTotal(): number
	return overtimeElapsed + (if clockRunning and overtime then serverNow() - overtimeStartedAt else 0)
end

---------------------------------------------------------------------------------------------------------------
-- People
---------------------------------------------------------------------------------------------------------------

local function spawnHeight(def: CarCatalog.CarDef): number
	return def.Hitbox.Y / 2 + GameConfig.Car.RideHeight + 0.3
end

local function kickoffCFrame(p: Participant): CFrame
	local side = GameConfig.Teams[p.team].DefendsSide
	local spot = KICKOFF_SPOTS[(p.slot - 1) % #KICKOFF_SPOTS + 1]
	local position = Vector3.new(spot.X * side, spawnHeight(p.def), spot.Y * side)
	return MathUtil.lookAlong(position, Vector3.new(-position.X, 0, -position.Z))
end

local function safeSpawnCFrame(p: Participant): CFrame
	local side = GameConfig.Teams[p.team].DefendsSide
	local position = Vector3.new(rng:NextNumber(-25, 25), spawnHeight(p.def), side * (GameConfig.Arena.Length / 2 - 45))
	return MathUtil.lookAlong(position, Vector3.new(0, 0, -side))
end

local function equippedCar(player: Player): CarCatalog.CarDef
	local data = DataService.get(player)
	local def = if data then CarCatalog.get(data.equipped) else nil
	return def or (CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef)
end

local function makeBot(team: Team, slot: number): Participant
	botCounter += 1
	local names = GameConfig.Bots.Names
	local carIds = GameConfig.Bots.CarIds
	local def = CarCatalog.get(carIds[rng:NextInteger(1, #carIds)])
		or CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef
	return Roster.newParticipant({
		key = `bot:{botCounter}`,
		player = nil,
		name = `{names[(botCounter - 1) % #names + 1]} (bot)`,
		team = team,
		slot = slot,
		def = def,
	})
end

local function makePlayerParticipant(player: Player, team: Team, slot: number): Participant
	return Roster.newParticipant({
		key = `player:{player.UserId}`,
		player = player,
		name = player.DisplayName,
		team = team,
		slot = slot,
		def = equippedCar(player),
	})
end

-- Players drive cars instead of walking around, so their character is removed during a match.
local function removeCharacter(player: Player)
	inMatch[player] = true
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end

local function respawn(player: Player)
	inMatch[player] = nil
	player:SetAttribute("Team", nil)
	if player.Parent == Players then
		task.spawn(function()
			local ok, err = pcall(function()
				player:LoadCharacterAsync()
			end)
			if not ok then
				warn(`[Match] Could not respawn {player.Name}: {err}`)
			end
		end)
	end
end

local function isLivePhase(): boolean
	local phase = MatchState.phase(stateObject)
	return phase == Phases.Playing or phase == Phases.GoalScored
end

-- A player joins a match that's already going: they take over a bot's seat on the team that needs them most.
local function joinInProgress(player: Player): boolean
	if not matchRunning or Roster.byPlayer(player) then
		return false
	end
	local phase = MatchState.phase(stateObject)
	if phase == Phases.Results then
		return false
	end
	local seat: Participant? = nil
	local fewestHumans = math.huge
	for _, team: Team in TEAMS do
		local humans = 0
		local bot: Participant? = nil
		for _, p in Roster.onTeam(team) do
			if p.isBot then
				bot = bot or p
			else
				humans += 1
			end
		end
		if bot and humans < fewestHumans then
			seat, fewestHumans = bot, humans
		end
	end
	if not seat then
		return false
	end
	local botChassis = seat.chassis
	local cframe = if botChassis then botChassis.CFrame else kickoffCFrame(seat)
	CarService.despawn(seat)
	StatsService.forget(seat)
	Roster.remove(seat)

	local p = makePlayerParticipant(player, seat.team, seat.slot)
	p.boost = math.max(seat.boost, GameConfig.Car.StartingBoost)
	Roster.add(p)
	removeCharacter(player)
	player:SetAttribute("Team", p.team)
	if phase == Phases.Countdown then
		CarService.spawn(p, kickoffCFrame(p))
	else
		CarService.spawn(p, if phase == Phases.Playing then safeSpawnCFrame(p) else cframe)
		if isLivePhase() then
			CarService.release(p)
		end
	end
	StatsService.announce("join", `{player.DisplayName} joined {string.upper(p.team)}!`, p.team, player.DisplayName)
	return true
end

-- A player leaves (or quits) mid-match: a bot takes over their seat.
local function replaceWithBot(p: Participant)
	local chassis = p.chassis
	local cframe = if chassis then chassis.CFrame else kickoffCFrame(p)
	CarService.despawn(p)
	StatsService.forget(p)
	Roster.remove(p)
	if not matchRunning then
		return
	end
	local bot = makeBot(p.team, p.slot)
	bot.boost = p.boost
	Roster.add(bot)
	CarService.spawn(bot, cframe)
	if isLivePhase() then
		CarService.release(bot)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Match flow
---------------------------------------------------------------------------------------------------------------

local function setupMatch()
	Roster.clear()
	StatsService.resetMatch()
	BotService.reset()
	blueScore, orangeScore = 0, 0
	overtime = false
	clockRemaining = matchLength()
	clockRunning = false
	overtimeElapsed = 0
	pendingGoal = nil
	set(Attr.MatchId, (stateObject:GetAttribute(Attr.MatchId) or 0) :: number + 1)
	set(Attr.BlueScore, 0)
	set(Attr.OrangeScore, 0)
	set(Attr.Overtime, false)
	set(Attr.OvertimeElapsed, 0)
	set(Attr.ClockRemaining, clockRemaining)
	set(Attr.ClockRunning, false)
	set(Attr.WaitingForBall, false)
	set(Attr.Banner, "")

	-- First come, first served for the six seats; the rest watch from the deck and play next time.
	local humans: { Player } = {}
	for _, player in Players:GetPlayers() do
		if #humans < M.TeamSize * 2 then
			table.insert(humans, player)
		end
	end
	for i = #humans, 2, -1 do
		local j = rng:NextInteger(1, i)
		humans[i], humans[j] = humans[j], humans[i]
	end

	local seats: { [Team]: number } = { Blue = 0, Orange = 0 }
	for i, player in humans do
		local team: Team = if i % 2 == 1 then "Blue" else "Orange"
		seats[team] += 1
		Roster.add(makePlayerParticipant(player, team, seats[team]))
	end
	for _, team: Team in TEAMS do
		while seats[team] < M.TeamSize do
			seats[team] += 1
			Roster.add(makeBot(team, seats[team]))
		end
	end

	for _, p in Roster.all() do
		if p.player then
			removeCharacter(p.player)
			p.player:SetAttribute("Team", p.team)
		end
		CarService.spawn(p, kickoffCFrame(p))
	end
	matchRunning = true
end

local function kickoff()
	pendingGoal = nil
	BallService.reset(Vector3.new(0, GameConfig.Ball.Radius, 0))
	BoostPadService.resetAll()
	BumpService.reset()
	for _, p in Roster.all() do
		CarService.freezeAt(p, kickoffCFrame(p))
		CarService.resetForKickoff(p)
	end
	setPhase(Phases.Countdown, M.CountdownLength)
	task.wait(M.CountdownLength)
	for _, p in Roster.all() do
		CarService.release(p)
	end
	BallService.setLive(true)
	setPhase(Phases.Playing)
	startClock()
end

-- Plays until a goal, the clock runs out, or everybody leaves.
local function play(): string
	local zeroSince: number? = nil
	while true do
		if pendingGoal then
			return "goal"
		end
		if #Roster.humans() == 0 then
			return "empty"
		end
		if overtime then
			if overtimeTotal() >= M.OvertimeLength then
				return "time"
			end
		elseif regulationLeft() <= 0 then
			-- 0:00 - keep playing until the ball touches the floor (last-second goals count!)
			if not zeroSince then
				zeroSince = serverNow()
				set(Attr.WaitingForBall, true)
			end
			if BallService.isOnGround() or serverNow() - (zeroSince :: number) >= M.ZeroSecondsMaxWait then
				return "time"
			end
		end
		task.wait()
	end
end

local function celebrate(goal: { side: number, position: Vector3 })
	stopClock()
	local ballSpeed = BallService.getState().velocity.Magnitude
	local summary = StatsService.goal(goal.side, ballSpeed)
	if summary.team == "Blue" then
		blueScore += 1
	else
		orangeScore += 1
	end
	set(Attr.BlueScore, blueScore)
	set(Attr.OrangeScore, orangeScore)
	Remotes.GoalScored:FireAllClients(
		summary.team,
		if summary.scorer then summary.scorer.name else "",
		if summary.assist then summary.assist.name else "",
		goal.position,
		summary.comboText or ""
	)
	setPhase(Phases.GoalScored, M.GoalCelebration)
	task.wait(M.GoalCelebration)
end

local function scoreboard(): { { [string]: any } }
	local rows = {}
	for _, p in Roster.all() do
		table.insert(rows, {
			name = p.name,
			team = p.team,
			isBot = p.isBot,
			points = p.stats.points,
			goals = p.stats.goals,
			assists = p.stats.assists,
			saves = p.stats.saves,
			shots = p.stats.shots,
		})
	end
	table.sort(rows, function(a, b)
		return a.points > b.points
	end)
	return rows
end

local function finishMatch(aborted: boolean)
	matchRunning = false
	BallService.hide()
	local winner: Team? = if blueScore > orangeScore then "Blue" elseif orangeScore > blueScore then "Orange" else nil
	local mvp: Participant? = nil
	for _, p in Roster.all() do
		if
			(winner == nil or p.team == winner) and (mvp == nil or p.stats.points > (mvp :: Participant).stats.points)
		then
			mvp = p
		end
	end
	local board = scoreboard()

	if not aborted then
		for _, p in Roster.humans() do
			local player = p.player
			if not player or player.Parent ~= Players then
				continue
			end
			local outcome: Rewards.Outcome = if winner == nil then "Draw" elseif winner == p.team then "Win" else "Loss"
			local summary = Rewards.compute(p.stats, outcome, mvp == p)
			local scrap: number? = nil
			local owned: { [string]: boolean } = {}
			DataService.update(player, function(data)
				data.scrap += summary.total
				data.stats.matches += 1
				if outcome == "Win" then
					data.stats.wins += 1
				end
				data.stats.goals += p.stats.goals
				data.stats.assists += p.stats.assists
				data.stats.saves += p.stats.saves
				data.stats.shots += p.stats.shots
				data.stats.megaShots += p.stats.megaShots
				data.stats.scrapEarned += summary.total
				scrap = data.scrap
				owned = table.clone(data.owned)
			end)
			Remotes.MatchResults:FireClient(player, {
				outcome = outcome,
				team = p.team,
				blueScore = blueScore,
				orangeScore = orangeScore,
				mvp = if mvp then mvp.name else "",
				youAreMvp = mvp == p,
				lines = summary.lines,
				total = summary.total,
				scrap = scrap,
				nextGoal = if scrap then Rewards.nextGoal(owned, scrap) else nil,
				scoreboard = board,
				stats = p.stats,
			})
		end
		setPhase(Phases.Results, M.ResultsLength)
		task.wait(M.ResultsLength)
	end

	for _, p in Roster.all() do
		CarService.despawn(p)
		if p.player then
			respawn(p.player)
		end
	end
	Roster.clear()
	StatsService.resetMatch()
end

local function runMatch()
	setupMatch()
	local aborted = false
	while true do
		kickoff()
		local reason = play()
		set(Attr.WaitingForBall, false)
		stopClock()
		if reason == "empty" then
			aborted = true
			break
		elseif reason == "goal" then
			celebrate(pendingGoal :: { side: number, position: Vector3 })
			if overtime or regulationLeft() <= 0 then
				break -- golden goal, or a goal scored at 0:00
			end
		elseif blueScore == orangeScore and not overtime then
			overtime = true
			set(Attr.Overtime, true)
			set(Attr.OvertimeElapsed, 0)
			BallService.hide()
			StatsService.announce("overtime", "OVERTIME! Next goal wins!", nil, nil)
			task.wait(2)
		else
			break
		end
	end
	finishMatch(aborted)
end

-- Lobby time between matches. Returns false if everyone left.
local function intermission(): boolean
	if #Players:GetPlayers() == 0 then
		setPhase(Phases.Waiting)
		set(Attr.Banner, "Waiting for players...")
		while #Players:GetPlayers() == 0 do
			task.wait(1)
		end
	end
	local duration = intermissionLength()
	setPhase(Phases.Intermission, duration)
	set(Attr.Banner, "Next match starting soon - check out the Garage!")
	local endsAt = serverNow() + duration
	while serverNow() < endsAt do
		if #Players:GetPlayers() == 0 then
			return false
		end
		task.wait(0.25)
	end
	return true
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				task.wait(3)
				if player.Parent == Players and not inMatch[player] and player.Character == character then
					respawn(player)
				end
			end)
		end
	end)
	-- Give their saved data a moment so they drive their own equipped car.
	DataService.waitFor(player, 6)
	if player.Parent ~= Players then
		return
	end
	if not joinInProgress(player) and not inMatch[player] then
		respawn(player)
	end
end

local function onPlayerRemoving(player: Player)
	inMatch[player] = nil
	local p = Roster.byPlayer(player)
	if p then
		replaceWithBot(p)
	end
end

function MatchService.start()
	BallService.GoalScored:Connect(function(side: number, position: Vector3)
		pendingGoal = { side = side, position = position }
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	RunService.PreSimulation:Connect(function(dt: number)
		BotService.update(dt, MatchState.phase(stateObject) == Phases.Playing)
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		BallService.update(dt)
		local phase = MatchState.phase(stateObject)
		local live = phase == Phases.Playing
		CarService.tick(dt, live or phase == Phases.GoalScored)
		if live then
			BoostPadService.update()
			BumpService.update()
		end
	end)

	task.spawn(function()
		while true do
			if intermission() then
				local ok, err = pcall(function()
					runMatch()
				end)
				if not ok then
					warn(`[Match] The match crashed: {err}`)
					matchRunning = false
					for _, p in Roster.all() do
						CarService.despawn(p)
						if p.player then
							respawn(p.player)
						end
					end
					Roster.clear()
					task.wait(2)
				end
			end
		end
	end)
end

return MatchService
