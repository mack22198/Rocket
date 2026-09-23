--!strict
-- Every tuning number for the game lives here, so the game can be balanced without touching any logic.
-- Distances are in studs, times in seconds, speeds in studs/second.

local GameConfig = {}

GameConfig.GameName = "Turbo Ball"

GameConfig.Match = {
	TeamSize = 3, -- 3v3; empty seats are filled with bots
	Length = 300, -- 5:00 of regulation play
	OvertimeLength = 120, -- golden-goal overtime; still tied after this = draw
	Intermission = 20, -- time between matches (garage time)
	CountdownLength = 3, -- 3-2-1-GO before every kickoff
	GoalCelebration = 4, -- pause between a goal and the next kickoff
	ResultsLength = 12, -- how long the results screen stays up
	ZeroSecondsMaxWait = 8, -- at 0:00 play continues until the ball touches the floor (at most this long)
}

GameConfig.Arena = {
	Width = 220, -- x axis
	Length = 320, -- z axis, goal line to goal line
	Height = 90, -- floor to ceiling
	CornerCut = 40, -- 45 degree corner walls cut this much off each axis
	CurveRadius = 20, -- radius of the curved ramp between the floor and the walls
	CurveSegments = 8, -- how many flat parts approximate each curved ramp
	GoalWidth = 72,
	GoalHeight = 28,
	GoalDepth = 20,
	WallThickness = 6,
}

GameConfig.Ball = {
	Radius = 6,
	Gravity = 70,
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
	RideHeight = 1.2, -- gap between the chassis bottom and the ground when resting
	SuspensionReach = 1.0, -- how far past ride height the wheels still count as touching
	SpringStrength = 220,
	SpringDamping = 18,
	AlignStrength = 14, -- how quickly the car tilts to match the surface under it
	WallStick = 35, -- pushes the car onto walls and ramps so it can drive on them
	MaxSpeed = 85,
	MaxReverseSpeed = 40,
	Acceleration = 70,
	BrakeDeceleration = 150,
	CoastDeceleration = 18,
	Grip = 10, -- how quickly sideways sliding is cancelled
	TurnRate = 3.0, -- radians per second
	TurnSpeedRamp = 12, -- the car needs this much speed before it turns at full rate
	HighSpeedTurnFactor = 0.45, -- turning is this much weaker at top speed
	SteerResponse = 15,
	BoostAcceleration = 85,
	MaxBoostedSpeed = 150,
	BoostDrainPerSecond = 33.3, -- a full tank lasts 3 seconds
	StartingBoost = 33,
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
	MaxAngularSpeed = 12,
	AutoRightDelay = 0.8, -- stuck on the roof this long -> hop back onto the wheels
}

GameConfig.Bump = {
	MinSpeed = 18, -- approach speed needed for a bump to count
	Knockback = 0.55,
	Pop = 14, -- upward kick on a bumped car
	AttackerSlowdown = 0.2,
	Cooldown = 0.6,
	BigBumpSpeed = 60, -- announce bumps faster than this
}

GameConfig.BoostPads = {
	BigAmount = 100,
	BigRespawn = 10,
	BigRadius = 5,
	SmallAmount = 12,
	SmallRespawn = 4,
	SmallRadius = 3.5,
	-- Pad positions are mirrored into all four quarters of the field unless they sit on an axis.
	Big = {
		Vector3.new(75, 0, 115),
		Vector3.new(85, 0, 0),
	},
	Small = {
		Vector3.new(0, 0, 60),
		Vector3.new(50, 0, 30),
		Vector3.new(60, 0, 90),
		Vector3.new(25, 0, 125),
		Vector3.new(0, 0, 138),
	},
}

GameConfig.Mega = {
	Max = 100,
	PerTouch = 10,
	PerStyleTouch = 18,
	PerShot = 12,
	PerSave = 25,
	ArmedDuration = 10, -- an armed Mega Shot fizzles if the ball isn't touched in time
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
	Skill = 0.55, -- 0 = sleepy, 1 = sweaty. Kids should be able to beat the default bots.
	ThinkRate = 12, -- decisions per second
	CarIds = { "pizza", "banana", "kart", "shark", "monster", "ufo" },
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

GameConfig.Lobby = {
	Center = Vector3.new(185, 36, 0), -- top of the viewing deck beside the arena
	Size = Vector3.new(80, 2, 180),
}

GameConfig.Data = {
	StoreName = "TurboBall_PlayerData_v1",
	AutosaveInterval = 90,
	SessionLockTimeout = 300,
}

GameConfig.Debug = {
	-- Shorter waits while testing in Roblox Studio. Set to nil to use the normal values.
	StudioIntermission = 6 :: number?,
	StudioMatchLength = nil :: number?,
	-- Scrap given to every player when testing in Studio without saved data (handy for testing the garage).
	StudioStartingScrap = 0,
	LogHitRejections = false,
}

return GameConfig
