--!strict
-- Brings the stadium to life on each player's screen: the big screens show the score and the clock, the adverts
-- scroll along the LED boards (and flash team colours after a goal), the crowd jumps up when someone scores and
-- does a Mexican wave now and then, and the showroom turntables in the VIP lounge slowly spin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local Remotes = require(Shared.Net.Remotes)

local StadiumController = {}

type Screen = { blue: TextLabel, orange: TextLabel, clock: TextLabel, message: TextLabel }
type Turntable = { car: Model, base: CFrame }
type RibbonItem = { label: TextLabel, copy: TextLabel, base: number }
type Ribbon = {
	frame: Frame,
	items: { RibbonItem },
	background: Color3,
	transparency: number,
	speed: number, -- fraction of the board's width per second
}

local P = MatchState.Phases
local A = MatchState.Attr
local GOLD = Color3.fromRGB(255, 205, 64)
local WHITE = Color3.new(1, 1, 1)
local SPIN_SPEED = 0.35 -- radians per second
local CHEER_TIME = 3
local RIBBON_SPEED = 9 -- studs per second
local WAVE_EVERY = 45 -- seconds between Mexican waves while a match is on
local WAVE_TIME = 9 -- how long a wave takes to go all the way round
local WAVE_WIDTH = 0.35 -- radians of stand that are up at once
local TAU = math.pi * 2

local stateObject = MatchState.getObject()
local screens: { Screen } = {}
local turntables: { Turntable } = {}
local fans: { BasePart } = {}
local fanHomes: { CFrame } = {}
local fanPhase: { number } = {}
local fanAngle: { number } = {}
local crowdMoved = false
local waveStarted = -math.huge
local nextWave = os.clock() + 30
local ribbons: { Ribbon } = {}
local lastRibbonUpdate = 0
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
			table.insert(fanAngle, math.atan2(p.X, p.Z))
		end
	end
end

-- Every advert banner becomes a scrolling LED ribbon: each label gets a twin one board-width behind it, so as
-- a label slides off one end its twin is already sliding on at the other.
local function findRibbons(root: Instance)
	for _, gui in root:GetDescendants() do
		if not gui:IsA("SurfaceGui") or gui.Name ~= "Banner" then
			continue
		end
		local frame = gui:FindFirstChild("Background")
		local part = gui.Parent
		if not frame or not frame:IsA("Frame") or not part or not part:IsA("BasePart") then
			continue
		end
		local sideways = gui.Face == Enum.NormalId.Left or gui.Face == Enum.NormalId.Right
		local width = if sideways then part.Size.Z else part.Size.X
		frame.ClipsDescendants = true
		local ribbon: Ribbon = {
			frame = frame,
			items = {},
			background = frame.BackgroundColor3,
			transparency = frame.BackgroundTransparency,
			speed = RIBBON_SPEED / math.max(width, 1),
		}
		for _, child in frame:GetChildren() do
			if child:IsA("TextLabel") then
				local copy = child:Clone()
				copy.Parent = frame
				table.insert(ribbon.items, { label = child, copy = copy, base = child.Position.X.Scale })
			end
		end
		table.insert(ribbons, ribbon)
	end
end

local function updateRibbons(now: number)
	local flashing = now < cheerUntil and math.floor(now * 5) % 2 == 0
	local color = teamColor(goalTeam)
	for _, ribbon in ribbons do
		local shift = now * ribbon.speed
		for _, item in ribbon.items do
			local x = (item.base - shift) % 1
			item.label.Position = UDim2.fromScale(x, 0.5)
			item.copy.Position = UDim2.fromScale(x + 1, 0.5)
		end
		ribbon.frame.BackgroundColor3 = if flashing then color else ribbon.background
		ribbon.frame.BackgroundTransparency = if flashing then 0.15 else ribbon.transparency
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

	if now - lastRibbonUpdate > 1 / 30 then
		lastRibbonUpdate = now
		updateRibbons(now)
	end

	-- The crowd: everyone jumps after a goal, and every so often a Mexican wave runs round the stands.
	if now > nextWave then
		nextWave = now + WAVE_EVERY
		if MatchState.phase(stateObject) == P.Playing then
			waveStarted = now
		end
	end
	local cheering = now < cheerUntil
	local waving = now - waveStarted < WAVE_TIME
	if #fans > 0 and (cheering or waving or crowdMoved) then
		local front = (now - waveStarted) / WAVE_TIME * TAU - math.pi
		local targets: { CFrame } = table.create(#fans)
		for i, home in fanHomes do
			local hop = if cheering then math.abs(math.sin(now * 9 + fanPhase[i])) * 1.4 else 0
			if waving then
				local gap = math.abs((fanAngle[i] - front + math.pi) % TAU - math.pi)
				if gap < WAVE_WIDTH then
					hop = math.max(hop, math.cos(gap / WAVE_WIDTH * math.pi / 2) * 2.4)
				end
			end
			targets[i] = home + Vector3.new(0, hop, 0)
		end
		workspace:BulkMoveTo(fans, targets, Enum.BulkMoveMode.FireCFrameChanged)
		-- One more pass after the last hop puts everyone back in their seat.
		crowdMoved = cheering or waving
	end
end

function StadiumController.start()
	task.spawn(function()
		local stadium = workspace:WaitForChild("Stadium", 60)
		if stadium then
			findScreens(stadium)
			findCrowd(stadium)
			findRibbons(stadium)
		end
		local arena = workspace:WaitForChild(MatchState.Folders.Arena, 60)
		if arena then
			findRibbons(arena)
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
