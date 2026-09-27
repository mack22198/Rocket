--!strict
-- Goal replays. While the ball is in play this keeps the last few seconds of what's on your screen (where the
-- ball and every car were). When someone scores, stand-in copies of the cars and ball act those seconds out
-- again - the shot itself in slow motion - with a TV-style camera chasing the ball into the net. The real cars
-- are hidden meanwhile, and you can skip it (see ReplayScreen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaShape = require(Shared.Arena.ArenaShape)
local BallModelBuilder = require(Shared.Ball.BallModelBuilder)
local GameConfig = require(Shared.Config.GameConfig)
local MatchState = require(Shared.Match.MatchState)
local MathUtil = require(Shared.Util.MathUtil)
local Remotes = require(Shared.Net.Remotes)
local Replay = require(Shared.Match.Replay)
local Signal = require(Shared.Util.Signal)

local BallView = require(script.Parent.BallView)
local CameraController = require(script.Parent.CameraController)
local CarController = require(script.Parent.CarController)
local LocalHide = require(script.Parent.LocalHide)

local ReplayController = {}

-- (scorer name, team, combo text) when a replay starts, and nothing when it ends.
ReplayController.Started = Signal.new() :: Signal.Signal<string, string, string>
ReplayController.Finished = Signal.new() :: Signal.Signal<>

type Frame = Replay.Frame

local A = MatchState.CarAttr
local Phases = MatchState.Phases
local RECORD_INTERVAL = 1 / 45
local arena = ArenaShape.new(GameConfig.Arena)
local stateObject = MatchState.getObject()

local carsFolder: Instance? = nil
local enabled = false
local frames: { Frame } = {}
local playing = false
local token = 0
local holder: Folder? = nil
local connection: RBXScriptConnection? = nil
local cameraFrame: ((dt: number) -> (CFrame?, number))? = nil

local function recordFrame()
	local folder = carsFolder
	if not enabled or not folder or playing then
		return
	end
	if MatchState.phase(stateObject) ~= Phases.Playing or not BallView.isVisible() then
		return
	end
	local now = os.clock()
	local last = frames[#frames]
	if last and now - last.t < RECORD_INTERVAL then
		return
	end
	local cars: { [any]: CFrame } = {}
	local boosting: { [any]: boolean } = {}
	local mine = CarController.getCar()
	for _, model in folder:GetChildren() do
		local chassis = model:FindFirstChild("Chassis")
		if model:IsA("Model") and chassis and chassis:IsA("BasePart") then
			cars[model] = chassis.CFrame
			boosting[model] = if model == mine
				then CarController.isBoosting()
				else model:GetAttribute(A.Boosting) == true
		end
	end
	table.insert(frames, { t = now, ball = BallView.getPosition(), cars = cars, boosting = boosting })
	while #frames > 2 and now - frames[1].t > Replay.ClipLength + 0.5 do
		table.remove(frames, 1)
	end
end

-- A stand-in copy of a car that can be moved around freely.
local function standIn(model: Model, parent: Instance): Model?
	local ok, copy = pcall(function()
		return model:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	copy:SetAttribute("HiddenLocally", nil)
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Beam") or d:IsA("Trail") or d:IsA("ParticleEmitter") then
			(d :: any).Enabled = false
		elseif d:IsA("BillboardGui") then
			d.Enabled = true
		end
	end
	copy.Parent = parent
	return copy
end

-- The copy's boost trails and flames, on or off.
local function setBoosting(copy: Model, on: boolean)
	for _, d in copy:GetDescendants() do
		if (d:IsA("Trail") and d.Name == "BoostTrail") or (d:IsA("ParticleEmitter") and d.Name == "BoostFlames") then
			(d :: any).Enabled = on
		end
	end
end

-- A gold "⚽ name" tag over the scorer's car.
local function scorerTag(copy: Model, scorer: string)
	local chassis = copy:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "ScorerTag"
	tag.Size = UDim2.fromOffset(220, 40)
	tag.StudsOffset = Vector3.new(0, 7.5, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = chassis
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 90)
	label.TextStrokeTransparency = 0.1
	label.Text = `⚽ {scorer}`
	label.Parent = tag
	tag.Parent = chassis
end

local function buildBall(parent: Instance, team: string): Model
	local ball = BallModelBuilder.build()
	local part = ball.PrimaryPart :: BasePart
	for _, d in ball:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local radius = GameConfig.Ball.Radius
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, radius * 0.6, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -radius * 0.6, 0)
	bottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.LightEmission = 0.7
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.FaceCamera = true
	local teamInfo = (GameConfig.Teams :: any)[team]
	trail.Color = ColorSequence.new(if teamInfo then teamInfo.Color else Color3.new(1, 1, 1))
	trail.Parent = part
	ball.Parent = parent
	return ball
end

function ReplayController.isPlaying(): boolean
	return playing
end

-- Ends the replay now (it ended, was skipped, or the game moved on).
function ReplayController.stop()
	if not playing then
		return
	end
	playing = false
	token += 1
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if holder then
		holder:Destroy()
		holder = nil
	end
	if cameraFrame then
		CameraController.releaseProvider(cameraFrame)
		cameraFrame = nil
	end
	if carsFolder then
		LocalHide.setAll(carsFolder, false)
	end
	ReplayController.Finished:Fire()
end

local function play(clip: { Frame }, scorer: string, team: string, combo: string, goalSide: number)
	local folder = carsFolder
	if playing or not folder or #clip < 8 then
		return
	end
	playing = true
	token += 1
	local myToken = token

	local replayFolder = Instance.new("Folder")
	replayFolder.Name = "Replay"
	replayFolder.Parent = workspace.CurrentCamera or workspace
	holder = replayFolder

	-- Every car seen in the clip gets a stand-in (if it's still in the game to copy).
	local copies: { [any]: Model } = {}
	for _, frame in clip do
		for model in frame.cars do
			if not copies[model] and typeof(model) == "Instance" and model:IsA("Model") and model.Parent then
				local copy = standIn(model, replayFolder)
				if copy then
					copies[model] = copy
					if scorer ~= "" and model:GetAttribute(A.DriverName) == scorer then
						scorerTag(copy, scorer)
					end
				end
			end
		end
	end
	local ball = buildBall(replayFolder, team)
	LocalHide.setAll(folder, true)

	local startT = clip[1].t
	local clipLength = clip[#clip].t - startT
	local duration = Replay.duration(clipLength)
	local started = os.clock()
	local ballPosition = clip[1].ball
	local lastBall = ballPosition
	local rotation = CFrame.identity
	local shown: { [any]: boolean } = {}

	-- The TV camera: behind the ball and off to one side, looking down the pitch toward the goal.
	local goalPoint = Vector3.new(0, 10, goalSide * (arena.halfLength + GameConfig.Arena.GoalDepth + 40))
	local cameraPosition: Vector3? = nil
	local function frameCamera(dt: number): (CFrame?, number)
		local toGoal = MathUtil.safeUnit(MathUtil.flat(goalPoint - ballPosition), Vector3.new(0, 0, goalSide))
		local side = toGoal:Cross(Vector3.yAxis)
		local wanted = arena:clampInside(ballPosition - toGoal * 34 + side * 12 + Vector3.new(0, 14, 0), 4)
		local current = cameraPosition
		local position = if current then current:Lerp(wanted, MathUtil.expDecay(3.5, dt)) else wanted
		cameraPosition = position
		local focus = ballPosition + toGoal * 6
		return MathUtil.lookAlong(position, focus - position, Vector3.yAxis), 60
	end
	cameraFrame = frameCamera
	CameraController.setProvider(frameCamera)

	connection = RunService.RenderStepped:Connect(function()
		if myToken ~= token then
			return
		end
		local elapsed = os.clock() - started
		local a, b, alpha = Replay.sample(clip, startT + Replay.clipTime(elapsed, clipLength))
		for model, copy in copies do
			local from, to = a.cars[model], b.cars[model]
			local cframe = if from and to then from:Lerp(to, alpha) else from or to
			if cframe then
				copy:PivotTo(cframe)
				local boosting = a.boosting[model] == true
				if shown[model] ~= boosting then
					shown[model] = boosting
					setBoosting(copy, boosting)
				end
			end
		end
		ballPosition = a.ball:Lerp(b.ball, alpha)
		-- Spin the ball the way it's rolling.
		local moved = ballPosition - lastBall
		lastBall = ballPosition
		local flat = MathUtil.flat(moved)
		if flat.Magnitude > 1e-3 then
			local axis = Vector3.new(flat.Z, 0, -flat.X).Unit
			rotation = CFrame.fromAxisAngle(axis, flat.Magnitude / GameConfig.Ball.Radius) * rotation
		end
		ball:PivotTo(CFrame.new(ballPosition) * rotation)
		if elapsed >= duration + 0.4 then
			ReplayController.stop()
		end
	end)
	ReplayController.Started:Fire(scorer, team, combo)
end

-- Replays only play while you're in a match (GameFlow switches this on and off).
function ReplayController.setEnabled(on: boolean)
	enabled = on
	if not on then
		table.clear(frames)
		ReplayController.stop()
	end
end

function ReplayController.start()
	task.spawn(function()
		carsFolder = workspace:WaitForChild(MatchState.Folders.Match):WaitForChild(MatchState.Folders.Cars)
	end)
	RunService.Heartbeat:Connect(recordFrame)

	Remotes.GoalScored.OnClientEvent:Connect(
		function(team: unknown, scorer: unknown, _assist: unknown, position: unknown, combo: unknown)
			if not enabled then
				return
			end
			local clip = Replay.trim(frames, Replay.ClipLength)
			frames = {}
			local goalSide = if typeof(position) == "Vector3" and position.Z < 0 then -1 else 1
			task.delay(Replay.StartDelay, function()
				if enabled and MatchState.phase(stateObject) == Phases.GoalScored then
					play(
						clip,
						if type(scorer) == "string" then scorer else "",
						if type(team) == "string" then team else "",
						if type(combo) == "string" then combo else "",
						goalSide
					)
				end
			end)
		end
	)
	-- Kickoff (or anything else) coming up: the replay is over.
	stateObject:GetAttributeChangedSignal(MatchState.Attr.Phase):Connect(function()
		if MatchState.phase(stateObject) ~= Phases.GoalScored then
			ReplayController.stop()
		end
	end)
end

return ReplayController
