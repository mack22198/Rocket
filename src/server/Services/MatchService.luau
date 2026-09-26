--!strict
-- The game loop. Everyone starts in the main menu. Pressing PLAY puts you in the queue; a match starts a few
-- seconds after someone is waiting (3v3, 5:00 clock, goals, overtime), then results + Scrap, then back to the
-- menu (or straight into the next match with PLAY AGAIN).
-- Empty seats are filled with bots. Pressing PLAY while a match is on takes over a bot's seat straight away,
-- and a bot takes over for anyone who leaves the match or the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local Evolution = require(Shared.Config.Evolution)
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
local Status = MatchState.Status
local PlayerAttr = MatchState.PlayerAttr
-- Players who pressed PLAY, first come first served.
local queue: { Player } = {}

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

-- Moves a player between the menu, the queue and the match (the client shows the right screen for each).
local function setStatus(player: Player, status: string)
	player:SetAttribute(PlayerAttr.Status, status)
	local index = table.find(queue, player)
	if status == Status.Queued then
		if not index then
			table.insert(queue, player)
		end
	elseif index then
		table.remove(queue, index)
	end
	if status ~= Status.Playing then
		player:SetAttribute(PlayerAttr.Team, nil)
	end
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

-- The car a player drives, and which evolution look it shows.
local function equippedCar(player: Player): (CarCatalog.CarDef, number)
	local data = DataService.get(player)
	local def = if data then CarCatalog.get(data.equipped) else nil
	if data and def then
		return def, data.carLook[def.Id] or 1
	end
	return CarCatalog.get(CarCatalog.StarterId) :: CarCatalog.CarDef, 1
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
		stage = Evolution.botStage(rng:NextNumber()),
	})
end

local function makePlayerParticipant(player: Player, team: Team, slot: number): Participant
	local def, stage = equippedCar(player)
	return Roster.newParticipant({
		key = `player:{player.UserId}`,
		player = player,
		name = player.DisplayName,
		team = team,
		slot = slot,
		def = def,
		stage = stage,
	})
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
	setStatus(player, Status.Playing)
	player:SetAttribute(PlayerAttr.Team, p.team)
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

	-- First come, first served for the six seats; anyone else keeps waiting and gets the next free seat.
	local humans: { Player } = {}
	for _, player in queue do
		if #humans < M.TeamSize * 2 and player.Parent == Players then
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
			setStatus(p.player, Status.Playing)
			p.player:SetAttribute(PlayerAttr.Team, p.team)
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
			local carXp, carStage = 0, 1
			DataService.update(player, function(data)
				-- The car they drove earns as much XP as the Scrap they won.
				carXp = (data.carXp[p.def.Id] or 0) + summary.total
				data.carXp[p.def.Id] = carXp
				carStage = data.carStage[p.def.Id] or 1
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
				car = {
					id = p.def.Id,
					name = CarCatalog.stageName(p.def, p.stage),
					emoji = p.def.Emoji,
					xpGained = summary.total,
					progress = Evolution.progress(p.def, carXp, carStage),
				},
			})
		end
		-- The results stay up until everyone has picked PLAY AGAIN or MENU (or the time runs out).
		setPhase(Phases.Results, M.ResultsLength)
		local endsAt = serverNow() + M.ResultsLength
		while serverNow() < endsAt do
			local deciding = false
			for _, p in Roster.humans() do
				local player = p.player
				if player and player.Parent == Players and MatchState.statusOf(player) == Status.Playing then
					deciding = true
				end
			end
			if not deciding then
				break
			end
			task.wait(0.2)
		end
	end

	for _, p in Roster.all() do
		CarService.despawn(p)
		local player = p.player
		if player and MatchState.statusOf(player) == Status.Playing then
			setStatus(player, Status.Menu)
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

-- Waits until someone presses PLAY, then gives friends a few seconds to hop into the same match.
-- Returns false if everyone waiting changed their mind.
local function waitForPlayers(): boolean
	if #queue == 0 then
		setPhase(Phases.Waiting)
		while #queue == 0 do
			task.wait(0.2)
		end
	end
	local duration = intermissionLength()
	setPhase(Phases.Intermission, duration)
	local endsAt = serverNow() + duration
	while serverNow() < endsAt do
		if #queue == 0 then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Gives free bot seats in the running match to people waiting in the queue.
local function fillFromQueue()
	for _, player in table.clone(queue) do
		if not joinInProgress(player) then
			break
		end
	end
end

-- PLAY from the menu (or PLAY AGAIN from the results screen).
local function requestPlay(player: Player)
	if not DataService.get(player) then
		-- Wait for their save to load, so they drive their own car.
		DataService.waitFor(player, 6)
	end
	if player.Parent ~= Players then
		return
	end
	local status = MatchState.statusOf(player)
	local phase = MatchState.phase(stateObject)
	if status == Status.Playing then
		if phase == Phases.Results then
			setStatus(player, Status.Queued) -- play again
		end
		return
	end
	setStatus(player, Status.Queued)
	fillFromQueue()
end

-- Back to the menu: out of the queue, or out of the match (a bot takes over the car).
local function leaveMatch(player: Player)
	local p = Roster.byPlayer(player)
	if p and MatchState.phase(stateObject) ~= Phases.Results then
		setStatus(player, Status.Menu)
		replaceWithBot(p)
		fillFromQueue()
	else
		setStatus(player, Status.Menu)
	end
end

local function onPlayerAdded(player: Player)
	setStatus(player, Status.Menu)
end

local function onPlayerRemoving(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
	local p = Roster.byPlayer(player)
	if p then
		replaceWithBot(p)
		fillFromQueue()
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

	Remotes.Play.OnServerEvent:Connect(requestPlay)
	Remotes.LeaveMatch.OnServerEvent:Connect(leaveMatch)

	task.spawn(function()
		while true do
			if waitForPlayers() then
				local ok, err = pcall(function()
					runMatch()
				end)
				if not ok then
					warn(`[Match] The match crashed: {err}`)
					matchRunning = false
					for _, p in Roster.all() do
						CarService.despawn(p)
						if p.player and MatchState.statusOf(p.player) == Status.Playing then
							setStatus(p.player, Status.Menu)
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
