--!strict
-- Item boxes and car powers: what each one is called, what it does and how often it turns up.
--
-- Items come out of the spinning "?" boxes on the pitch. You hold one at a time and use it whenever you like
-- (R / RB / ITEM). A team that's behind gets the better items more often, so matches stay close.
-- Powers belong to cars: every car has its own (G / LB / POWER), which recharges after each use. A fused car
-- (see CarCatalog) gets a combo: both its parents' powers at once, with a longer recharge.
--
-- This is plain data plus a few pure helpers, so the server, the clients and the tests all agree.

local Powers = {}

local rgb = Color3.fromRGB

export type ItemDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Color: Color3,
	Description: string,
	Duration: number, -- seconds the effect lasts (0 = instant)
}

export type PowerDef = {
	Id: string,
	Name: string,
	Emoji: string,
	Color: Color3,
	Description: string,
	Cooldown: number,
	Duration: number,
	Combo: { string }?, -- a fused car's power: the ids of the two powers it does at once
}

export type Standing = "ahead" | "level" | "behind"

Powers.Items = {
	magnet = {
		Id = "magnet",
		Name = "Magnet",
		Emoji = "🧲",
		Color = rgb(255, 80, 90),
		Description = "Pulls the ball to the front of your car for a few seconds.",
		Duration = 4,
	},
	freeze = {
		Id = "freeze",
		Name = "Freeze Ray",
		Emoji = "❄️",
		Color = rgb(120, 220, 255),
		Description = "Freezes the closest car on the other team.",
		Duration = 2.5,
	},
	spring = {
		Id = "spring",
		Name = "Super Spring",
		Emoji = "🦘",
		Color = rgb(120, 230, 110),
		Description = "Bounces you way up into the air.",
		Duration = 0,
	},
	rocket = {
		Id = "rocket",
		Name = "Rocket Fuel",
		Emoji = "🚀",
		Color = rgb(255, 170, 40),
		Description = "A full tank of boost that doesn't run out for a few seconds.",
		Duration = 5,
	},
	shield = {
		Id = "shield",
		Name = "Bubble Shield",
		Emoji = "🛡️",
		Color = rgb(110, 170, 255),
		Description = "Nothing can bump, freeze or trip you up.",
		Duration = 6,
	},
	mega = {
		Id = "mega",
		Name = "Mega Charge",
		Emoji = "💥",
		Color = rgb(255, 120, 40),
		Description = "Your next hit is a Mega Shot!",
		Duration = 0,
	},
} :: { [string]: ItemDef }

-- Every item, in a fixed order (for picking and for showing them).
Powers.ItemOrder = { "magnet", "freeze", "spring", "rocket", "shield", "mega" }

-- How likely each item is, depending on how your team is doing.
Powers.ItemWeights = {
	ahead = { magnet = 2, freeze = 1, spring = 4, rocket = 4, shield = 3, mega = 1 },
	level = { magnet = 3, freeze = 2, spring = 3, rocket = 3, shield = 2, mega = 2 },
	behind = { magnet = 4, freeze = 4, spring = 1, rocket = 2, shield = 1, mega = 4 },
} :: { [string]: { [string]: number } }

Powers.CarPowers = {
	pizza = {
		Id = "cheese",
		Name = "Cheese Trap",
		Emoji = "🧀",
		Color = rgb(255, 204, 64),
		Description = "Drops a gooey cheese puddle behind you. Cars in it slow right down.",
		Cooldown = 14,
		Duration = 8,
	},
	banana = {
		Id = "peel",
		Name = "Banana Peel",
		Emoji = "🍌",
		Color = rgb(255, 226, 70),
		Description = "Drops a banana peel. Anyone who drives over it spins out!",
		Cooldown = 11,
		Duration = 15,
	},
	kart = {
		Id = "nitro",
		Name = "Nitro Dash",
		Emoji = "🔥",
		Color = rgb(255, 110, 40),
		Description = "A huge burst of speed, right now.",
		Cooldown = 8,
		Duration = 0.6,
	},
	shark = {
		Id = "dive",
		Name = "Shark Dive",
		Emoji = "🌊",
		Color = rgb(60, 200, 255),
		Description = "Dive like a ghost: a burst of speed, and nothing can touch you.",
		Cooldown = 13,
		Duration = 1.6,
	},
	monster = {
		Id = "pound",
		Name = "Ground Pound",
		Emoji = "💢",
		Color = rgb(255, 80, 60),
		Description = "A shockwave that knocks nearby cars flying and blasts the ball away.",
		Cooldown = 12,
		Duration = 0,
	},
	taco = {
		Id = "hotsauce",
		Name = "Hot Sauce",
		Emoji = "🌶️",
		Color = rgb(255, 70, 40),
		Description = "Hit the ball in the next few seconds and it's a Mega Shot!",
		Cooldown = 16,
		Duration = 4,
	},
	duck = {
		Id = "quack",
		Name = "Quack Attack",
		Emoji = "🦆",
		Color = rgb(255, 214, 46),
		Description = "A mighty QUACK that spins out nearby cars on the other team.",
		Cooldown = 13,
		Duration = 0,
	},
	hotdog = {
		Id = "ketchup",
		Name = "Ketchup Slick",
		Emoji = "🌭",
		Color = rgb(235, 44, 40),
		Description = "Squirts a long ketchup trail behind you. Other cars that drive through it spin out!",
		Cooldown = 14,
		Duration = 7,
	},
	ufo = {
		Id = "beam",
		Name = "Tractor Beam",
		Emoji = "🛸",
		Color = rgb(130, 255, 110),
		Description = "Lifts the ball up in front of you. Line up the perfect shot!",
		Cooldown = 14,
		Duration = 2.5,
	},
	-- Fused cars
	pizzashark = {
		Id = "cheesydive",
		Name = "Cheesy Dive",
		Emoji = "🧀",
		Color = rgb(255, 170, 60),
		Description = "A Shark Dive that leaves a Cheese Trap behind you!",
		Cooldown = 17,
		Duration = 1.6,
		Combo = { "dive", "cheese" },
	},
	ducksaucer = {
		Id = "quackbeam",
		Name = "Quack Beam",
		Emoji = "🛸",
		Color = rgb(200, 240, 80),
		Description = "A Tractor Beam with a mighty QUACK that spins out cars nearby.",
		Cooldown = 17,
		Duration = 2.5,
		Combo = { "beam", "quack" },
	},
	monstertaco = {
		Id = "spicypound",
		Name = "Spicy Pound",
		Emoji = "🌶️",
		Color = rgb(255, 96, 50),
		Description = "A Ground Pound, then Hot Sauce: hit the ball straight after and it's a Mega Shot!",
		Cooldown = 18,
		Duration = 4,
		Combo = { "pound", "hotsauce" },
	},
} :: { [string]: PowerDef }

local powersById: { [string]: PowerDef } = {}
for _, def in Powers.CarPowers do
	powersById[def.Id] = def
end

Powers.Tuning = {
	-- Item boxes
	BoxRespawn = 10,
	BoxPickupRadius = 7.5,
	BoxHeight = 4,
	Roulette = 1.2, -- the item spins in your slot this long before you can use it
	-- Eight boxes, mirrored across the pitch (clear of the boost pads).
	BoxPositions = {
		Vector3.new(45, 0, 0),
		Vector3.new(-45, 0, 0),
		Vector3.new(70, 0, 55),
		Vector3.new(-70, 0, 55),
		Vector3.new(70, 0, -55),
		Vector3.new(-70, 0, -55),
		Vector3.new(0, 0, 100),
		Vector3.new(0, 0, -100),
	},
	-- Items
	MagnetRange = 75,
	MagnetPull = 70,
	MagnetDamping = 1.6,
	MagnetReach = 13, -- the ball is held this far in front of the car...
	MagnetLift = 4, -- ...and this high
	FreezeRange = 120,
	SpringLaunch = 72,
	SpringForward = 16,
	-- Powers
	CheeseRadius = 11,
	CheeseSlowTime = 0.5,
	HazardDrop = 7, -- cheese and peels land this far behind the car
	PeelRadius = 5,
	SpinTime = 1.2,
	NitroBurst = 60,
	DiveBurst = 45,
	PoundRadius = 30,
	PoundKnockback = 70,
	PoundPop = 30,
	PoundBallRadius = 28,
	PoundBallSpeed = 90,
	BeamRange = 60,
	BeamPull = 95,
	BeamDamping = 2.4,
	BeamLift = 13,
	BeamReach = 11,
	QuackRadius = 26,
	QuackSpin = 1.1,
	KetchupLength = 18,
	KetchupWidth = 4.6,
	KetchupSpin = 0.8,
}

function Powers.item(id: string): ItemDef?
	return Powers.Items[id]
end

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

-- Is your team ahead, level or behind?
function Powers.standing(ourScore: number, theirScore: number): Standing
	if ourScore > theirScore then
		return "ahead"
	elseif ourScore < theirScore then
		return "behind"
	end
	return "level"
end

-- Picks an item for a team's standing from a random number between 0 and 1.
function Powers.pickItem(standing: Standing, roll: number): string
	local weights = Powers.ItemWeights[standing] or Powers.ItemWeights.level
	local total = 0
	for _, id in Powers.ItemOrder do
		total += weights[id] or 0
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	for _, id in Powers.ItemOrder do
		target -= weights[id] or 0
		if target < 0 then
			return id
		end
	end
	return Powers.ItemOrder[#Powers.ItemOrder]
end

local function flatForward(carCFrame: CFrame): Vector3
	local forward = Vector3.new(carCFrame.LookVector.X, 0, carCFrame.LookVector.Z)
	return if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
end

-- Where a pull (a Magnet or a Tractor Beam) drags the ball to, for a car at `carCFrame`.
function Powers.pullTarget(kind: string, carCFrame: CFrame): Vector3
	local t = Powers.Tuning
	local forward = flatForward(carCFrame)
	if kind == "beam" then
		return carCFrame.Position + forward * t.BeamReach + Vector3.new(0, t.BeamLift, 0)
	end
	return carCFrame.Position + forward * t.MagnetReach + Vector3.new(0, t.MagnetLift, 0)
end

-- The push a car gives itself with a Super Spring, Nitro Dash or Shark Dive (nil for anything else).
-- The spring always sends you up at the same speed, even if you were falling.
function Powers.launch(kind: string, carCFrame: CFrame, velocity: Vector3): Vector3?
	local t = Powers.Tuning
	if kind == "spring" then
		local up = math.max(0, t.SpringLaunch - velocity.Y)
		return Vector3.new(0, up, 0) + flatForward(carCFrame) * t.SpringForward
	elseif kind == "nitro" then
		return carCFrame.LookVector * t.NitroBurst
	elseif kind == "dive" then
		return carCFrame.LookVector * t.DiveBurst
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

-- Nudges a ball's velocity toward a pull's target for one step of `dt` seconds. Used by the server's ball and
-- by every client's prediction of it, so they stay in step. Returns the new velocity.
function Powers.applyPull(
	kind: string,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	target: Vector3,
	gravity: number,
	dt: number
): Vector3
	local t = Powers.Tuning
	local beam = kind == "beam"
	local range = if beam then t.BeamRange else t.MagnetRange
	local offset = target - ballPosition
	local distance = offset.Magnitude
	if distance > range then
		return ballVelocity
	end
	local strength = if beam then t.BeamPull else t.MagnetPull
	local damping = if beam then t.BeamDamping else t.MagnetDamping
	local velocity = ballVelocity
	if distance > 1e-3 then
		-- Pull harder when far away, gently when close, and bleed off speed so the ball settles.
		velocity += offset / distance * (strength * math.clamp(distance / 10, 0.25, 1) * dt)
	end
	velocity *= math.max(0, 1 - damping * dt)
	if beam then
		velocity += Vector3.new(0, gravity * dt, 0) -- the beam holds the ball up
	end
	return velocity
end

-- What a bot knows when deciding whether to use its item or power.
export type BotView = {
	role: string, -- "attack", "support" or "defend"
	ballDistance: number, -- flat distance to the ball
	ballHeight: number,
	ballInFront: boolean,
	shotLinedUp: boolean, -- the ball is between the bot and the other team's goal
	nearestEnemy: number, -- distance to the closest car on the other team
	enemyBehind: boolean, -- a car on the other team is right behind
	heldFor: number, -- seconds the bot has been holding its item
}

function Powers.botWantsItem(item: string, v: BotView): boolean
	if v.heldFor > 8 then
		return true -- don't sit on it all match
	elseif item == "magnet" then
		return v.role == "attack" and v.ballDistance < 45
	elseif item == "freeze" then
		return v.nearestEnemy < 70
	elseif item == "spring" then
		return v.ballInFront and v.ballHeight > 14 and v.ballDistance < 24
	elseif item == "rocket" then
		return v.role == "attack" and v.ballDistance > 50
	elseif item == "shield" then
		return v.nearestEnemy < 25
	end
	return v.heldFor > 1.5 -- Mega Charge (and anything new): just use it
end

function Powers.botWantsPower(power: string, v: BotView): boolean
	local t = Powers.Tuning
	if power == "cheese" or power == "peel" or power == "ketchup" then
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
