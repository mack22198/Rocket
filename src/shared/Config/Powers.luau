--!strict
-- Ultimates: every car has its own big move (the Pizza Car floods the pitch with cheese, the Rubber Duck QUACKs
-- everyone into a spin...). The ultimate meter fills mostly from playing - touching the ball, shots, saves,
-- goals, big bumps and the charge orb - and a little by itself (see GameConfig.Ultimate); when it's full, one
-- button sets it off (E / X / ULT). Each car's meter fills at its own pace (ChargeRate), and a fused car (see
-- CarCatalog) gets a combo: both its parents' ultimates at once, with a meter that fills a little slower.
--
-- Every ultimate is made to be seen from your own seat (the camera sits behind your car, looking ahead): the
-- cheese floods out all around you, peels and ketchup go out in front, the Monster Truck leaps up before it
-- slams down.
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
	ChargeRate: number?, -- how fast its meter fills compared with the others (1 when not given), so cars' ultimates
	-- aren't all ready at once
	Combo: { string }?, -- a fused car's ultimate: the ids of the two it does at once
}

Powers.CarPowers = {
	pizza = {
		Id = "cheese",
		Name = "Cheese Flood",
		Emoji = "🧀",
		Color = rgb(255, 204, 64),
		Description = "Floods the pitch all around you with gooey cheese. Cars on the other team get stuck in it!",
		Duration = 12,
	},
	banana = {
		Id = "peel",
		Name = "Banana Storm",
		Emoji = "🍌",
		Color = rgb(255, 226, 70),
		Description = "Throws five banana peels out in front of you. Anyone who drives over one spins out!",
		Duration = 20,
		ChargeRate = 1.1,
	},
	kart = {
		Id = "nitro",
		Name = "Nitro Rocket",
		Emoji = "🔥",
		Color = rgb(255, 110, 40),
		Description = "A rocket-powered dash. Smash into a car on the other team and it goes POOF!",
		Duration = 1.2,
		ChargeRate = 0.9,
	},
	shark = {
		Id = "dive",
		Name = "Shark Dive",
		Emoji = "🌊",
		Color = rgb(60, 200, 255),
		Description = "Dive like a ghost: a burst of speed, and nothing can touch you.",
		Duration = 2.4,
		ChargeRate = 1.05,
	},
	monster = {
		Id = "pound",
		Name = "Ground Pound",
		Emoji = "💢",
		Color = rgb(255, 80, 60),
		Description = "Leaps up and slams down: a huge shockwave knocks nearby cars flying and blasts the ball away.",
		Duration = 0,
		ChargeRate = 0.9,
	},
	taco = {
		Id = "hotsauce",
		Name = "Hot Sauce",
		Emoji = "🌶️",
		Color = rgb(255, 70, 40),
		Description = "Sets your car on fire: hit the ball in the next 6 seconds and it's a flaming Mega Shot!",
		Duration = 6,
	},
	duck = {
		Id = "quack",
		Name = "Quack Attack",
		Emoji = "🦆",
		Color = rgb(255, 214, 46),
		Description = "A mighty QUACK that spins out every car on the other team nearby.",
		Duration = 0,
		ChargeRate = 0.95,
	},
	hotdog = {
		Id = "ketchup",
		Name = "Ketchup Slick",
		Emoji = "🌭",
		Color = rgb(235, 44, 40),
		Description = "Squirts a long ketchup slick out in front of you. Cars on the other team that cross it spin out!",
		Duration = 12,
		ChargeRate = 1.1,
	},
	ufo = {
		Id = "beam",
		Name = "Tractor Beam",
		Emoji = "🛸",
		Color = rgb(130, 255, 110),
		Description = "Grabs the ball from far away and lifts it up in front of you. Line up the perfect shot!",
		Duration = 3.5,
		ChargeRate = 0.95,
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
	CheeseRadius = 18, -- the cheese floods out this far all around the car
	CheeseSlowTime = 0.5,
	PeelRadius = 6,
	PeelFlight = 0.5, -- seconds a thrown peel is in the air
	SpinTime = 1.2,
	NitroBurst = 75,
	DiveBurst = 55,
	PoundHop = 32, -- the Monster Truck leaps up this fast...
	PoundSlamAt = 0.38, -- ...is thrown back down this long after...
	PoundSlam = 85, -- ...this hard...
	PoundDelay = 0.55, -- ...and the shockwave goes off when it lands, this long after the leap
	PoundRadius = 38,
	PoundKnockback = 75,
	PoundPop = 32,
	PoundBallRadius = 34,
	PoundBallSpeed = 95,
	BeamRange = 100,
	BeamPull = 110,
	BeamDamping = 2.4,
	BeamLift = 13,
	BeamReach = 11,
	QuackRadius = 34,
	QuackSpin = 1.4,
	KetchupLength = 32,
	KetchupWidth = 5.5,
	KetchupAhead = 3, -- the slick starts this far in front of the car's nose
	KetchupSpin = 0.8,
}

-- Where a Banana Storm's peels land, from the car: (studs to the right, studs ahead). A fan out in front.
Powers.PeelSpots = {
	Vector2.new(-20, 18),
	Vector2.new(-10, 28),
	Vector2.new(0, 36),
	Vector2.new(10, 28),
	Vector2.new(20, 18),
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

-- The push a car gives itself with a Nitro Rocket or Shark Dive, or the Monster Truck's leap before its Ground
-- Pound (nil for anything else).
function Powers.launch(kind: string, carCFrame: CFrame): Vector3?
	local t = Powers.Tuning
	if kind == "nitro" then
		return carCFrame.LookVector * t.NitroBurst
	elseif kind == "dive" then
		return carCFrame.LookVector * t.DiveBurst
	elseif kind == "pound" then
		return Vector3.new(0, t.PoundHop, 0)
	end
	return nil
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
	enemyAhead: boolean, -- a car on the other team is a little way ahead
	readyFor: number, -- seconds the bot's ultimate has been ready
}

-- Would a bot set off this ultimate now? (After holding it a while it just goes for it.)
function Powers.botWantsPower(power: string, v: BotView): boolean
	local t = Powers.Tuning
	if v.readyFor > 12 then
		return true
	elseif power == "cheese" then
		return v.nearestEnemy < t.CheeseRadius or v.enemyBehind
	elseif power == "peel" or power == "ketchup" then
		return v.enemyAhead
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
