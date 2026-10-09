--!strict
-- Ultimates: every car has its own big move (the Pizza Car floods the pitch with cheese, the Rubber Duck QUACKs
-- everyone into a spin...). The ultimate meter fills up by itself, faster when you play the ball, and with the
-- charge orb (see GameConfig.Ultimate); when it's full, one button sets it off (E / X / ULT). A fused car (see
-- CarCatalog) gets a combo: both its parents' ultimates at once, but its meter fills a little slower.
--
-- (In the code an ultimate is a "power", the name it had before it charged up like this.)
--
-- This is plain data plus a few pure helpers, so the server, the clients and the tests all agree.

local Powers = {}

local rgb = Color3.fromRGB

export type PowerDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Color: Color3,
	Description: string,
	Duration: number, -- seconds the effect lasts (0 = instant)
	ChargeRate: number?, -- how fast its meter fills compared with the others (1 when not given)
	Combo: { string }?, -- a fused car's ultimate: the ids of the two it does at once
}

Powers.CarPowers = {
	pizza = {
		Id = "cheese",
		Name = "Cheese Flood",
		Emoji = "🧀",
		Color = rgb(255, 204, 64),
		Description = "Floods the pitch behind you with gooey cheese. Cars in it slow right down.",
		Duration = 10,
	},
	banana = {
		Id = "peel",
		Name = "Banana Storm",
		Emoji = "🍌",
		Color = rgb(255, 226, 70),
		Description = "Drops three banana peels behind you. Anyone who drives over one spins out!",
		Duration = 15,
	},
	kart = {
		Id = "nitro",
		Name = "Nitro Rocket",
		Emoji = "🔥",
		Color = rgb(255, 110, 40),
		Description = "A rocket-powered dash. Smash into a car on the other team and it goes POOF!",
		Duration = 1.2,
	},
	shark = {
		Id = "dive",
		Name = "Shark Dive",
		Emoji = "🌊",
		Color = rgb(60, 200, 255),
		Description = "Dive like a ghost: a burst of speed, and nothing can touch you.",
		Duration = 2.4,
	},
	monster = {
		Id = "pound",
		Name = "Ground Pound",
		Emoji = "💢",
		Color = rgb(255, 80, 60),
		Description = "A huge shockwave that knocks nearby cars flying and blasts the ball away.",
		Duration = 0,
	},
	taco = {
		Id = "hotsauce",
		Name = "Hot Sauce",
		Emoji = "🌶️",
		Color = rgb(255, 70, 40),
		Description = "Hit the ball in the next 6 seconds and it's a flaming Mega Shot!",
		Duration = 6,
	},
	duck = {
		Id = "quack",
		Name = "Quack Attack",
		Emoji = "🦆",
		Color = rgb(255, 214, 46),
		Description = "A mighty QUACK that spins out every car on the other team nearby.",
		Duration = 0,
	},
	hotdog = {
		Id = "ketchup",
		Name = "Ketchup Slick",
		Emoji = "🌭",
		Color = rgb(235, 44, 40),
		Description = "Squirts a long ketchup trail behind you. Other cars that drive through it spin out!",
		Duration = 9,
	},
	ufo = {
		Id = "beam",
		Name = "Tractor Beam",
		Emoji = "🛸",
		Color = rgb(130, 255, 110),
		Description = "Lifts the ball up in front of you. Line up the perfect shot!",
		Duration = 3.5,
	},
	-- Fused cars
	pizzashark = {
		Id = "cheesydive",
		Name = "Cheesy Dive",
		Emoji = "🧀",
		Color = rgb(255, 170, 60),
		Description = "A Shark Dive that floods the pitch with cheese behind you!",
		Duration = 2.4,
		ChargeRate = 0.8,
		Combo = { "dive", "cheese" },
	},
	ducksaucer = {
		Id = "quackbeam",
		Name = "Quack Beam",
		Emoji = "🛸",
		Color = rgb(200, 240, 80),
		Description = "A Tractor Beam with a mighty QUACK that spins out cars nearby.",
		Duration = 3.5,
		ChargeRate = 0.8,
		Combo = { "beam", "quack" },
	},
	monstertaco = {
		Id = "spicypound",
		Name = "Spicy Pound",
		Emoji = "🌶️",
		Color = rgb(255, 96, 50),
		Description = "A Ground Pound, then Hot Sauce: hit the ball straight after and it's a Mega Shot!",
		Duration = 6,
		ChargeRate = 0.8,
		Combo = { "pound", "hotsauce" },
	},
} :: { [string]: PowerDef }

local powersById: { [string]: PowerDef } = {}
for _, def in Powers.CarPowers do
	powersById[def.Id] = def
end

Powers.Tuning = {
	CheeseRadius = 15,
	CheeseSlowTime = 0.5,
	HazardDrop = 7, -- cheese and peels land this far behind the car
	PeelRadius = 5,
	PeelCount = 3, -- a Banana Storm drops this many peels...
	PeelSpread = 10, -- ...this far apart, side to side
	SpinTime = 1.2,
	NitroBurst = 75,
	DiveBurst = 55,
	PoundRadius = 38,
	PoundKnockback = 75,
	PoundPop = 32,
	PoundBallRadius = 34,
	PoundBallSpeed = 95,
	BeamRange = 60,
	BeamPull = 95,
	BeamDamping = 2.4,
	BeamLift = 13,
	BeamReach = 11,
	QuackRadius = 34,
	QuackSpin = 1.4,
	KetchupLength = 26,
	KetchupWidth = 4.6,
	KetchupSpin = 0.8,
}

-- The power that comes with a car (every car has one).
function Powers.forCar(carId: string): PowerDef
	return Powers.CarPowers[carId] or Powers.CarPowers.kart
end

-- The car power with this id (a combo too), or nil.
function Powers.power(id: string): PowerDef?
	return powersById[id]
end

-- The powers a power is made of: a combo's two halves, or just the power itself.
function Powers.components(power: PowerDef): { PowerDef }
	local combo = power.Combo
	if not combo then
		return { power }
	end
	local parts = {}
	for _, id in combo do
		local part = powersById[id]
		if part then
			table.insert(parts, part)
		end
	end
	return parts
end

local function flatForward(carCFrame: CFrame): Vector3
	local forward = Vector3.new(carCFrame.LookVector.X, 0, carCFrame.LookVector.Z)
	return if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
end

-- How fast an ultimate's meter fills, compared with the others (a fused car's combo is slower).
function Powers.chargeRate(power: PowerDef): number
	return power.ChargeRate or 1
end

-- Where a Tractor Beam holds the ball, for a car at `carCFrame`.
function Powers.pullTarget(carCFrame: CFrame): Vector3
	local t = Powers.Tuning
	return carCFrame.Position + flatForward(carCFrame) * t.BeamReach + Vector3.new(0, t.BeamLift, 0)
end

-- The push a car gives itself with a Nitro Rocket or Shark Dive (nil for anything else).
function Powers.launch(kind: string, carCFrame: CFrame): Vector3?
	local t = Powers.Tuning
	if kind == "nitro" then
		return carCFrame.LookVector * t.NitroBurst
	elseif kind == "dive" then
		return carCFrame.LookVector * t.DiveBurst
	end
	return nil
end

-- Where each banana peel of a Banana Storm lands, side to side (studs to the right of the car).
function Powers.peelOffsets(): { number }
	local t = Powers.Tuning
	local offsets = {}
	for i = 1, t.PeelCount do
		table.insert(offsets, (i - (t.PeelCount + 1) / 2) * t.PeelSpread)
	end
	return offsets
end

-- The shove a Ground Pound at `centre` gives something at `position` (a car or the ball): strongest close
-- in, fading to half at the edge. Nil when it's out of reach.
function Powers.poundPush(centre: Vector3, position: Vector3, radius: number, strength: number, pop: number): Vector3?
	local offset = position - centre
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance > radius or math.abs(offset.Y) > radius then
		return nil
	end
	local direction = if distance > 1e-3 then flat / distance else Vector3.xAxis
	local falloff = 1 - 0.5 * (distance / radius)
	return (direction * strength + Vector3.new(0, pop, 0)) * falloff
end

-- Is a car at `carPosition` touching a cheese puddle, banana peel or ketchup slick lying at `hazardPosition`
-- on a surface facing `normal` (the floor, a ramp or a wall)? A ketchup slick is long: `forward` is the way it
-- points along the surface.
function Powers.inHazard(
	kind: string,
	hazardPosition: Vector3,
	normal: Vector3,
	carPosition: Vector3,
	forward: Vector3?
): boolean
	local t = Powers.Tuning
	local offset = carPosition - hazardPosition
	local height = offset:Dot(normal)
	if height <= -2 or height >= 6 then
		return false
	end
	if kind == "ketchup" and forward then
		local side = forward:Cross(normal)
		return math.abs(offset:Dot(forward)) <= t.KetchupLength / 2 + 1
			and math.abs(offset:Dot(side)) <= t.KetchupWidth / 2 + 1.5
	end
	local radius = if kind == "cheese" then t.CheeseRadius else t.PeelRadius + 2.5
	local across = (offset - normal * height).Magnitude
	return across <= radius
end

-- Nudges a ball's velocity toward a Tractor Beam's target for one step of `dt` seconds. Used by the server's
-- ball and by every client's prediction of it, so they stay in step. Returns the new velocity.
function Powers.applyPull(
	ballPosition: Vector3,
	ballVelocity: Vector3,
	target: Vector3,
	gravity: number,
	dt: number
): Vector3
	local t = Powers.Tuning
	local offset = target - ballPosition
	local distance = offset.Magnitude
	if distance > t.BeamRange then
		return ballVelocity
	end
	local velocity = ballVelocity
	if distance > 1e-3 then
		-- Pull harder when far away, gently when close, and bleed off speed so the ball settles.
		velocity += offset / distance * (t.BeamPull * math.clamp(distance / 10, 0.25, 1) * dt)
	end
	velocity *= math.max(0, 1 - t.BeamDamping * dt)
	return velocity + Vector3.new(0, gravity * dt, 0) -- the beam holds the ball up
end

-- What a bot knows when deciding whether to set off its ultimate.
export type BotView = {
	role: string, -- "attack", "support" or "defend"
	ballDistance: number, -- flat distance to the ball
	ballHeight: number,
	ballInFront: boolean,
	shotLinedUp: boolean, -- the ball is between the bot and the other team's goal
	nearestEnemy: number, -- distance to the closest car on the other team
	enemyBehind: boolean, -- a car on the other team is right behind
	readyFor: number, -- seconds the bot's ultimate has been ready
}

-- Would a bot set off this ultimate now? (After holding it a while it just goes for it.)
function Powers.botWantsPower(power: string, v: BotView): boolean
	local t = Powers.Tuning
	if v.readyFor > 12 then
		return true
	elseif power == "cheese" or power == "peel" or power == "ketchup" then
		return v.enemyBehind
	elseif power == "hotsauce" then
		return v.role == "attack" and v.ballInFront and v.ballDistance < 35
	elseif power == "quack" then
		return v.nearestEnemy < t.QuackRadius * 0.7
	elseif power == "nitro" or power == "dive" then
		return v.role == "attack" and v.ballInFront and v.ballDistance > 30 and v.ballDistance < 90
	elseif power == "pound" then
		return v.nearestEnemy < t.PoundRadius * 0.6 or (v.shotLinedUp and v.ballDistance < t.PoundBallRadius * 0.7)
	elseif power == "beam" then
		return v.role == "attack" and v.ballInFront and v.ballDistance < 40
	end
	local combo = powersById[power]
	if combo and combo.Combo then
		-- A combo is worth using whenever either half would be.
		for _, part in Powers.components(combo) do
			if Powers.botWantsPower(part.Id, v) then
				return true
			end
		end
	end
	return false
end

return Powers
