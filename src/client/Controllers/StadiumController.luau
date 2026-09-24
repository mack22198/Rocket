--!strict
-- Brings the stadium to life on each player's screen: the big screens show the score and the clock, the
-- showroom turntables in the lobby slowly spin, and the crowd jumps up when someone scores.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local StadiumController = {}

type Screen = { blue: TextLabel, orange: TextLabel, clock: TextLabel, message: TextLabel }
type Turntable = { car: Model, base: CFrame }

local P = MatchState.Phases
local A = MatchState.Attr
local GOLD = Color3.fromRGB(255, 205, 64)
local WHITE = Color3.new(1, 1, 1)
local SPIN_SPEED = 0.35 -- radians per second
local CHEER_TIME = 3

local stateObject = MatchState.getObject()
local screens: { Screen } = {}
local turntables: { Turntable } = {}
local fans: { BasePart } = {}
local fanHomes: { CFrame } = {}
local fanPhase: { number } = {}
local cheerUntil = 0
local goalTeam: string? = nil
local lastScreenUpdate = 0

local function teamColor(team: string?): Color3
	if team == "Blue" then
		return GameConfig.Teams.Blue.Color
	elseif team == "Orange" then
		return GameConfig.Teams.Orange.Color
	end
	return WHITE
end

local function findScreens(stadium: Instance)
	local folder = stadium:WaitForChild("Screens", 10)
	if not folder then
		return
	end
	for _, part in folder:GetChildren() do
		local gui = part:FindFirstChild("Screen")
		local frame = if gui then gui:FindFirstChild("Background") else nil
		if part.Name == "Jumbotron" and frame then
			local blue = frame:FindFirstChild("BlueScore")
			local orange = frame:FindFirstChild("OrangeScore")
			local clock = frame:FindFirstChild("Clock")
			local message = frame:FindFirstChild("Message")
			if
				blue
				and blue:IsA("TextLabel")
				and orange
				and orange:IsA("TextLabel")
				and clock
				and clock:IsA("TextLabel")
				and message
				and message:IsA("TextLabel")
			then
				table.insert(screens, { blue = blue, orange = orange, clock = clock, message = message })
			end
		end
	end
end

local function findCrowd(stadium: Instance)
	local crowd = stadium:WaitForChild("Crowd", 10)
	if not crowd then
		return
	end
	for _, part in crowd:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(fans, part)
			table.insert(fanHomes, part.CFrame)
			-- A fan's body and head share a phase, so they bounce together.
			local p = part.Position
			table.insert(fanPhase, ((math.floor(p.X) * 7 + math.floor(p.Z) * 13) % 17) / 17 * math.pi * 2)
		end
	end
end

local function findTurntables()
	local lobby = workspace:WaitForChild(MatchState.Folders.Lobby, 30)
	local showroom = lobby and lobby:WaitForChild("Showroom", 10)
	if not showroom then
		return
	end
	for _, stand in showroom:GetChildren() do
		local car = stand:WaitForChild("Car", 5)
		if car and car:IsA("Model") then
			table.insert(turntables, { car = car, base = car:GetPivot() })
		end
	end
end

local function screenText(): (string, string, Color3)
	local phase = MatchState.phase(stateObject)
	local now = workspace:GetServerTimeNow()
	local clock = MatchState.formatClock(MatchState.clockSeconds(stateObject, now))
	if phase == P.Waiting then
		return "--:--", "WAITING FOR PLAYERS", GOLD
	elseif phase == P.Intermission then
		return MatchState.formatClock(MatchState.phaseSecondsLeft(stateObject, now)), "NEXT MATCH", GOLD
	elseif phase == P.Countdown then
		return clock, "GET READY!", GOLD
	elseif phase == P.GoalScored then
		local flash = math.floor(os.clock() * 4) % 2 == 0
		return clock, "GOAL!!!", if flash then teamColor(goalTeam) else WHITE
	elseif phase == P.Results then
		local blue = stateObject:GetAttribute(A.BlueScore)
		local orange = stateObject:GetAttribute(A.OrangeScore)
		if type(blue) == "number" and type(orange) == "number" and blue ~= orange then
			local winner = if blue > orange then "Blue" else "Orange"
			return clock, `{string.upper(winner)} WINS!`, teamColor(winner)
		end
		return clock, "IT'S A DRAW!", GOLD
	end
	if stateObject:GetAttribute(A.WaitingForBall) == true then
		return clock, "LAST CHANCE!", GOLD
	elseif stateObject:GetAttribute(A.Overtime) == true then
		return `+{clock}`, "OVERTIME!", GOLD
	end
	return clock, "TURBO BALL", GOLD
end

local function updateScreens()
	local clock, message, color = screenText()
	local blue = stateObject:GetAttribute(A.BlueScore)
	local orange = stateObject:GetAttribute(A.OrangeScore)
	for _, screen in screens do
		screen.blue.Text = tostring(if type(blue) == "number" then blue else 0)
		screen.orange.Text = tostring(if type(orange) == "number" then orange else 0)
		screen.clock.Text = clock
		screen.message.Text = message
		screen.message.TextColor3 = color
	end
end

local function update()
	local now = os.clock()
	if now - lastScreenUpdate > 0.2 then
		lastScreenUpdate = now
		updateScreens()
	end

	for _, turntable in turntables do
		local angle = (now * SPIN_SPEED) % (math.pi * 2)
		turntable.car:PivotTo(turntable.base * CFrame.Angles(0, angle, 0))
	end

	if #fans > 0 and (now < cheerUntil or cheerUntil > 0) then
		local cheering = now < cheerUntil
		local targets: { CFrame } = table.create(#fans)
		for i, home in fanHomes do
			local hop = if cheering then math.abs(math.sin(now * 9 + fanPhase[i])) * 1.4 else 0
			targets[i] = home + Vector3.new(0, hop, 0)
		end
		workspace:BulkMoveTo(fans, targets, Enum.BulkMoveMode.FireCFrameChanged)
		if not cheering then
			cheerUntil = 0 -- everyone is back in their seat
		end
	end
end

function StadiumController.start()
	task.spawn(function()
		local stadium = workspace:WaitForChild("Stadium", 60)
		if stadium then
			findScreens(stadium)
			findCrowd(stadium)
		end
	end)
	task.spawn(findTurntables)

	Remotes.GoalScored.OnClientEvent:Connect(function(team: unknown)
		goalTeam = if type(team) == "string" then team else nil
		cheerUntil = os.clock() + CHEER_TIME
	end)
	RunService.Heartbeat:Connect(update)
end

return StadiumController
