--!strict
-- Every tuning number for the game lives here, so the game can be balanced without touching any logic.
-- Distances are in studs, times in seconds, speeds in studs/second.

local GameConfig = {}

GameConfig.GameName = "Turbo Ball"

GameConfig.Match = {
	TeamSize = 2, -- 2v2; empty seats are filled with bots
	Length = 180, -- 3:00 of regulation play: short enough for "just one more"
	OvertimeLength = 90, -- golden-goal overtime; still tied after this = draw
	Intermission = 5, -- after someone presses PLAY, wait this long so friends can hop into the same match
	CountdownLength = 3, -- 3-2-1-GO before every kickoff
	GoalCelebration = 6.5, -- pause between a goal and the next kickoff (long enough for the replay)
	ResultsLength = 16, -- how long the podium and results screen stay up
	ZeroSecondsMaxWait = 8, -- at 0:00 play continues until the ball touches the floor (at most this long)
}

GameConfig.Arena = {
	Width = 220, -- x axis
	Length = 320, -- z axis, goal line to goal line
	Height = 90, -- floor to ceiling
	CornerCut = 40, -- 45 degree corner walls cut this much off each axis
	CurveRadius = 20, -- radius of the curved ramp between the floor and the walls
	CurveSegments = 8, -- how many flat parts approximate each curved ramp
	GoalWidth = 88,
	GoalHeight = 32,
	GoalDepth = 24,
	WallThickness = 6,
}

GameConfig.Ball = {
	Radius = 8, -- big and easy to hit (about one and a half car lengths across)
	Gravity = 62, -- a little floatier than the cars, so there's time to get under it
	AirDrag = 0.03, -- fraction of speed lost per second
	Restitution = 0.62, -- bounciness against the arena
	RestThreshold = 6, -- impacts slower than this don't bounce (lets the ball settle)
	SurfaceFriction = 0.3, -- how much a bounce grips and slows the ball's sliding
	RollingFriction = 4, -- slowdown while rolling
	MaxSpeed = 230,
	FixedStep = 1 / 60, -- the ball is simulated with this exact step on the server and every client
	SnapshotRate = 30, -- server -> client ball updates per second
}

GameConfig.Hit = {
	Cooldown = 0.1, -- a car can't touch the ball twice within this window
	CarMassShare = 0.85, -- car mass / (car mass + ball mass): how much of the bump goes into the ball
	Restitution = 0.5,
	-- Extra "kick" on top of the physical bump (tuned after how Rocket League feels): kick = relativeSpeed * scale
	KickScaleSlow = 0.65,
	KickScaleMid = 0.55,
	KickScaleFast = 0.3,
	KickMidSpeed = 150,
	KickFastSpeed = 300,
	VerticalBias = 0.35, -- squashes the vertical part of the kick direction
	ForwardBias = 0.35, -- reduces how much the kick follows the car's nose
	MegaSpeedMultiplier = 1.8,
	MegaMinSpeed = 175,
	MegaAimAssist = 0.6, -- how much a mega shot bends toward where the car is pointing
	ShotAssist = 0.55, -- driving help: hits bend this much of the way toward the goal...
	ShotAssistCone = math.rad(75), -- ...when they're already going within this angle of it
}

-- Server checks on "I hit the ball" messages from players (see HitValidation).
GameConfig.HitValidation = {
	MaxClaimAge = 0.75,
	MaxClaimLead = 0.1,
	CarPositionTolerance = 12,
	CarPositionLatencyFactor = 0.3, -- extra tolerance per stud/s of car speed
	BallPositionTolerance = 8,
	BallPositionLatencyFactor = 0.08,
	BallVelocityTolerance = 12,
	BallVelocityLatencyFactor = 0.2,
	OverlapSlack = 1.5,
	MinInterval = 0.08,
	MaxCarSpeedFactor = 1.3,
}

GameConfig.Car = {
	Gravity = 70,
	RideHeight = 1.44, -- gap between the chassis bottom and the ground when resting (cars are built 1.2x their design)
	SuspensionReach = 1.2, -- how far past ride height the wheels still count as touching
	SpringStrength = 220,
	SpringDamping = 18,
	AlignStrength = 14, -- how quickly the car tilts to match the surface under it
	WallStick = 35, -- pushes the car onto walls and ramps so it can drive on them
	MaxSpeed = 100, -- there's no boost, so cars are quick to begin with
	MaxReverseSpeed = 40,
	Acceleration = 85,
	BrakeDeceleration = 150,
	CoastDeceleration = 18,
	Grip = 10, -- how quickly sideways sliding is cancelled
	TurnRate = 3.0, -- radians per second
	TurnSpeedRamp = 12, -- the car needs this much speed before it turns at full rate
	HighSpeedTurnFactor = 0.45, -- turning is this much weaker at top speed
	SteerResponse = 15,
	-- (The car physics can still boost, but nothing in the game uses it any more.)
	BoostAcceleration = 85,
	MaxBoostedSpeed = 150, -- the fastest any car can go (a Nitro Rocket gets close)
	OverSpeedDecay = 30, -- going faster than top speed (after a dash), a car slows back down this quickly
	JumpSpeed = 36,
	JumpSuspensionPause = 0.2,
	DoubleJumpSpeed = 24,
	DodgeSpeed = 34,
	DodgeSpinRate = 9,
	DodgeDuration = 0.55,
	SecondJumpWindow = 1.5,
	AirPitchRate = 4.5,
	AirYawRate = 3.5,
	AirRollRate = 4.5,
	AirControlResponse = 8,
	AirSpinDamping = 1.5,
	AutoLevel = 2.2, -- with no air controls held, the car turns back upright this fast (0 = off)...
	AutoLevelResponse = 2.5, -- ...easing in at this rate
	MaxAngularSpeed = 12,
	AutoRightDelay = 0.8, -- stuck on the roof this long -> hop back onto the wheels
	-- What ultimates do to a car.
	SlowFactor = 0.45, -- top speed while stuck in cheese
	SpinRate = 11, -- radians per second while spinning out on a banana
	SpinGrip = 0.15, -- tyre grip while spinning out (the car slides)
	FreezeDamping = 4, -- how quickly a frozen car skids to a stop
}

GameConfig.Bump = {
	MinSpeed = 18, -- approach speed needed for a bump to count
	Knockback = 0.55,
	Pop = 14, -- upward kick on a bumped car
	AttackerSlowdown = 0.2,
	Cooldown = 0.6,
	BigBumpSpeed = 60, -- announce bumps faster than this
	DemoSpeed = 125, -- smashing into the other team this fast (only a Nitro Rocket gets you there) demolishes them...
	DemoRespawn = 2, -- ...and they pop back in at their own goal this many seconds later
}

-- Ultimates: every car has one (see Powers). The meter fills up by itself, faster when you play the ball, and
-- with the charge orb (see OrbService). When it's full, one button sets it off.
GameConfig.Ultimate = {
	Max = 100,
	Start = 25, -- how full it is at the start of a match
	PerSecond = 0.85, -- fills by itself: a full meter in about two minutes...
	PerTouch = 3, -- ...and faster when you play
	PerStyleTouch = 6, -- an air or wall hit
	TouchGap = 1, -- seconds before a car's touches charge it again (pushing the ball along is lots of touches)
	PerShot = 5,
	PerSave = 12,
	PerGoal = 15,
	PerAssist = 10,
	Orb = 30, -- grabbing the charge orb
	BehindBonus = 0.5, -- a team that's behind fills 50% faster by itself, so matches stay close
}

-- The charge orb (see OrbService): one at a time, somewhere along the halfway line, so it's a fair race.
GameConfig.Orb = {
	FirstDelay = 12, -- seconds after a kickoff before the first one turns up...
	Every = 18, -- ...and between one going and the next one appearing
	Lifetime = 15, -- it fades away if nobody grabs it
	PickupRadius = 8,
	Height = 5.5, -- how high it floats (cars drive through the bottom of it)
	Spots = {
		Vector3.new(0, 0, 0),
		Vector3.new(45, 0, 0),
		Vector3.new(-45, 0, 0),
		Vector3.new(80, 0, 0),
		Vector3.new(-80, 0, 0),
	},
}

-- Points decide the MVP and the scoreboard (not Scrap; see Rewards).
GameConfig.Points = {
	Goal = 100,
	Assist = 50,
	Save = 50,
	Shot = 20,
	Touch = 2,
	Style = 15,
	MegaShot = 10,
	Demo = 15,
}

GameConfig.Style = {
	AirHitHeight = 12, -- car must be this high (and off the walls) for an AIR HIT
	WallHitHeight = 8, -- car must be this high and hugging a wall for a WALL HIT
	WallHitDistance = 7,
	ComboWindow = 5, -- touches within this many seconds chain into a combo
	AssistWindow = 6,
	ShotLookahead = 3, -- seconds of ball path to check when deciding shots and saves
}

GameConfig.Bots = {
	Names = { "Sparky", "Nitro Nell", "Bolt", "Zippy", "Rusty", "Turbo Tom", "Pickles", "Dash", "Comet", "Blip" },
	Skill = 0.45, -- 0 = sleepy, 1 = sweaty. Kids should be able to beat the default bots.
	-- Bots playing against players adjust so matches stay close (see BotBrain.adaptiveSkill).
	SkillPerGoal = 0.08, -- harder for every goal the players are ahead, easier for every goal behind
	MinSkill = 0.15,
	MaxSkill = 0.8,
	RookieMatches = 8, -- players who've finished fewer matches than this get easier bots...
	RookieEase = 0.2, -- ...by this much
	ThinkRate = 12, -- decisions per second
	CarIds = { "pizza", "banana", "kart", "shark", "monster", "ufo", "duck", "taco", "hotdog" },
	-- Now and then a bot turns up in a fused car, to show what's possible.
	FusedCarIds = { "pizzashark", "ducksaucer", "monstertaco" },
	FusedChance = 0.12,
}

GameConfig.Teams = {
	Blue = {
		Name = "Blue",
		Color = Color3.fromRGB(45, 135, 255),
		DarkColor = Color3.fromRGB(20, 60, 140),
		DefendsSide = -1, -- the goal at negative z
	},
	Orange = {
		Name = "Orange",
		Color = Color3.fromRGB(255, 140, 30),
		DarkColor = Color3.fromRGB(150, 70, 10),
		DefendsSide = 1, -- the goal at positive z
	},
}

-- Cars power up as you play with them. Evolving changes how a car looks, never how it drives.
GameConfig.Evolution = {
	Stages = 4,
	-- Car XP needed to reach each stage. A car earns as much XP as the Scrap you win while driving it.
	Xp = { 0, 500, 1500, 3500 },
	-- How often bots show up in each stage (so players see what their cars can become).
	BotStageWeights = { 5, 3, 2, 1 },
}

-- The lobby is a VIP deck built into the stands on the +X side, looking out over the pitch.
GameConfig.Lobby = {
	Center = Vector3.new(194, 52, 0), -- middle of the deck's floor, on its top surface
	Size = Vector3.new(92, 2, 192),
}

GameConfig.Data = {
	StoreName = "TurboBall_PlayerData_v1",
	AutosaveInterval = 90,
	SessionLockTimeout = 300,
}

GameConfig.Debug = {
	-- Shorter waits while testing in Roblox Studio. Set to nil to use the normal values.
	StudioIntermission = 3 :: number?,
	StudioMatchLength = nil :: number?,
	-- Scrap given to every player when testing in Studio without saved data (handy for testing the garage).
	StudioStartingScrap = 0,
	LogHitRejections = false,
}

return GameConfig
