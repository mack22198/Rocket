--!strict
-- The collectible cars. Rarity is about looks and bragging rights, never raw power:
-- every car trades one strength for a weakness so the rarest car is not simply the best.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Fused"

export type CarStats = {
	Speed: number, -- top speed multiplier
	Acceleration: number,
	Handling: number, -- turning multiplier
	Weight: number, -- resists being bumped
	BumpPower: number, -- how hard this car bumps others
	AirControl: number,
	Jump: number,
}

-- A fused car is made from two cars you own (they're kept): the Base gives its shape, the Flavor its colours.
export type Fusion = { Base: string, Flavor: string, Cost: number }

export type CarDef = {
	Id: string,
	DisplayName: string,
	Emoji: string,
	Rarity: Rarity,
	Price: number, -- Scrap cost (0 = starter car, or a fused car)
	Fusion: Fusion?,
	Tagline: string,
	Description: string,
	Hitbox: Vector3, -- width, height, length of the physics box
	DesignHitbox: Vector3?, -- the box the car's look was designed around (Hitbox / Scale; filled in below)
	Stats: CarStats,
	StageNames: { string }, -- the car's name at each evolution stage
}

local CarCatalog = {}

CarCatalog.StarterId = "pizza"

-- Cars are built this much bigger than they were designed: the looks (CarModelBuilder) are drawn around each car's
-- DesignHitbox and scaled up, and the physics box (Hitbox) is the designed box scaled up the same way.
CarCatalog.Scale = 1.2

CarCatalog.Rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(170, 180, 190) },
	Rare = { Order = 2, Color = Color3.fromRGB(60, 150, 255) },
	Epic = { Order = 3, Color = Color3.fromRGB(180, 80, 255) },
	Legendary = { Order = 4, Color = Color3.fromRGB(255, 190, 40) },
	Fused = { Order = 5, Color = Color3.fromRGB(255, 100, 210) },
}

local STANDARD_HITBOX = Vector3.new(5.5, 2.2, 8.5)

local cars: { CarDef } = {
	{
		Id = "pizza",
		DisplayName = "Pizza Car",
		Emoji = "🍕",
		Rarity = "Common",
		Price = 0,
		Tagline = "Balanced",
		Description = "Hot, fresh and good at everything. Extra cheese included.",
		Hitbox = STANDARD_HITBOX,
		StageNames = { "Pizza Car", "Burnt Pizza Car", "Lava Pizza Car", "Galaxy Pizza Car" },
		Stats = { Speed = 1, Acceleration = 1, Handling = 1, Weight = 1, BumpPower = 1, AirControl = 1, Jump = 1 },
	},
	{
		Id = "banana",
		DisplayName = "Banana Car",
		Emoji = "🍌",
		Rarity = "Common",
		Price = 300,
		Tagline = "Slippery turns",
		Description = "Turns on a dime, but gets knocked around easily.",
		Hitbox = Vector3.new(5.2, 2.2, 8.8),
		StageNames = { "Banana Car", "Ripe Banana Car", "Lava Banana Car", "Galaxy Banana Car" },
		Stats = {
			Speed = 1.02,
			Acceleration = 1,
			Handling = 1.12,
			Weight = 0.88,
			BumpPower = 0.9,
			AirControl = 1,
			Jump = 1,
		},
	},
	{
		Id = "kart",
		DisplayName = "Tiny Kart",
		Emoji = "🏎️",
		Rarity = "Common",
		Price = 500,
		Tagline = "Zoom zoom",
		Description = "Incredible acceleration. Very light, so big cars bully it.",
		Hitbox = Vector3.new(5, 1.9, 7.6),
		StageNames = { "Tiny Kart", "Turbo Kart", "Lava Kart", "Galaxy Kart" },
		Stats = {
			Speed = 0.96,
			Acceleration = 1.25,
			Handling = 1.08,
			Weight = 0.75,
			BumpPower = 0.75,
			AirControl = 1.05,
			Jump = 1,
		},
	},
	{
		Id = "shark",
		DisplayName = "Neon Shark",
		Emoji = "🦈",
		Rarity = "Rare",
		Price = 1000,
		Tagline = "Fast hunter",
		Description = "Fast with great turning. Its bumps are more of a nibble.",
		Hitbox = Vector3.new(5.4, 2.2, 9),
		StageNames = { "Neon Shark", "Tiger Shark", "Lava Shark", "Galaxy Shark" },
		Stats = {
			Speed = 1.07,
			Acceleration = 1.02,
			Handling = 1.08,
			Weight = 0.9,
			BumpPower = 0.85,
			AirControl = 1,
			Jump = 1,
		},
	},
	{
		Id = "monster",
		DisplayName = "Monster Truck",
		Emoji = "🛻",
		Rarity = "Rare",
		Price = 1500,
		Tagline = "Heavy hitter",
		Description = "Heavy with huge bumps, but slow to turn.",
		Hitbox = Vector3.new(6, 3, 9.2),
		StageNames = { "Monster Truck", "Mega Monster Truck", "Lava Monster Truck", "Galaxy Monster Truck" },
		Stats = {
			Speed = 0.96,
			Acceleration = 0.95,
			Handling = 0.88,
			Weight = 1.35,
			BumpPower = 1.4,
			AirControl = 0.95,
			Jump = 1,
		},
	},
	{
		Id = "duck",
		DisplayName = "Rubber Duck",
		Emoji = "🦆",
		Rarity = "Rare",
		Price = 900,
		Tagline = "Quack quack!",
		Description = "Squeaky, bouncy and great in the air. Not much of a bumper.",
		Hitbox = Vector3.new(5.4, 2.4, 8.4),
		StageNames = { "Rubber Duck", "Disco Duck", "Lava Duck", "Galaxy Duck" },
		Stats = {
			Speed = 1,
			Acceleration = 1.02,
			Handling = 1.04,
			Weight = 0.9,
			BumpPower = 0.85,
			AirControl = 1.12,
			Jump = 1.06,
		},
	},
	{
		Id = "taco",
		DisplayName = "Taco Truck",
		Emoji = "🌮",
		Rarity = "Rare",
		Price = 1200,
		Tagline = "Food fight!",
		Description = "A big, tough food truck. Serves up bumps with extra salsa, but it's slow to turn.",
		Hitbox = Vector3.new(5.8, 2.6, 9),
		StageNames = { "Taco Truck", "Spicy Taco Truck", "Lava Taco Truck", "Galaxy Taco Truck" },
		Stats = {
			Speed = 0.97,
			Acceleration = 0.96,
			Handling = 0.92,
			Weight = 1.22,
			BumpPower = 1.25,
			AirControl = 0.95,
			Jump = 1,
		},
	},
	{
		Id = "hotdog",
		DisplayName = "Hot Dog",
		Emoji = "🌭",
		Rarity = "Epic",
		Price = 2000,
		Tagline = "Relish the win",
		Description = "Long and super fast in a straight line, but it takes a while to turn.",
		Hitbox = Vector3.new(5, 2.2, 9.8),
		StageNames = { "Hot Dog", "Chili Dog", "Lava Dog", "Galaxy Dog" },
		Stats = {
			Speed = 1.08,
			Acceleration = 1,
			Handling = 0.9,
			Weight = 1.05,
			BumpPower = 1.05,
			AirControl = 0.95,
			Jump = 1,
		},
	},
	{
		Id = "ufo",
		DisplayName = "UFO",
		Emoji = "🛸",
		Rarity = "Epic",
		Price = 3000,
		Tagline = "Floaty flyer",
		Description = "Out of this world air control and bouncy jumps. Not great at bumping.",
		Hitbox = Vector3.new(6.6, 2.2, 7.8),
		StageNames = { "UFO", "Golden UFO", "Lava UFO", "Galaxy UFO" },
		Stats = {
			Speed = 1,
			Acceleration = 1.03,
			Handling = 1.02,
			Weight = 0.95,
			BumpPower = 0.9,
			AirControl = 1.2,
			Jump = 1.08,
		},
	},
}

-- Fused cars: shape from the Base, colours from the Flavor, stats halfway between the two.
local FUSIONS = {
	{
		Id = "pizzashark",
		DisplayName = "Pizza Shark",
		Emoji = "🦈",
		Base = "shark",
		Flavor = "pizza",
		Tagline = "Hungry hunter",
		Description = "A Neon Shark with extra cheese. Dives through defenders and leaves cheese behind.",
		StageNames = { "Pizza Shark", "Deluxe Pizza Shark", "Lava Pizza Shark", "Galaxy Pizza Shark" },
	},
	{
		Id = "ducksaucer",
		DisplayName = "Duck Saucer",
		Emoji = "🛸",
		Base = "ufo",
		Flavor = "duck",
		Tagline = "Quack from space",
		Description = "A UFO piloted by a rubber duck. Its beam lifts the ball with a mighty QUACK.",
		StageNames = { "Duck Saucer", "Disco Saucer", "Lava Saucer", "Galaxy Saucer" },
	},
	{
		Id = "monstertaco",
		DisplayName = "Monster Taco",
		Emoji = "🛻",
		Base = "monster",
		Flavor = "taco",
		Tagline = "Spicy stomper",
		Description = "A Monster Truck from the taco stand. Its Ground Pound comes with hot sauce.",
		StageNames = { "Monster Taco", "Spicy Monster Taco", "Lava Monster Taco", "Galaxy Monster Taco" },
	},
}

local byId: { [string]: CarDef } = {}
for _, def in cars do
	byId[def.Id] = def
end
for _, recipe in FUSIONS do
	local base, flavor = byId[recipe.Base], byId[recipe.Flavor]
	assert(base and flavor, `fusion {recipe.Id} needs {recipe.Base} and {recipe.Flavor}`)
	local stats = table.clone(base.Stats)
	for key, value in stats do
		(stats :: any)[key] = (value + (flavor.Stats :: any)[key]) / 2
	end
	local def: CarDef = {
		Id = recipe.Id,
		DisplayName = recipe.DisplayName,
		Emoji = recipe.Emoji,
		Rarity = "Fused",
		Price = 0,
		Fusion = { Base = recipe.Base, Flavor = recipe.Flavor, Cost = 1000 },
		Tagline = recipe.Tagline,
		Description = recipe.Description,
		Hitbox = base.Hitbox,
		Stats = stats,
		StageNames = recipe.StageNames,
	}
	table.insert(cars, def)
	byId[def.Id] = def
end

for _, def in cars do
	def.DesignHitbox = def.Hitbox
	def.Hitbox = def.Hitbox * CarCatalog.Scale
end

-- The box a car's look was designed around (its Hitbox before scaling).
function CarCatalog.designHitbox(def: CarDef): Vector3
	return def.DesignHitbox or def.Hitbox / CarCatalog.Scale
end

function CarCatalog.get(id: string): CarDef?
	return byId[id]
end

-- Starter car first, then by price, and the fused cars at the end.
function CarCatalog.ordered(): { CarDef }
	local list = table.clone(cars)
	table.sort(list, function(a, b)
		local fusedA, fusedB = a.Fusion ~= nil, b.Fusion ~= nil
		if fusedA ~= fusedB then
			return fusedB
		end
		if a.Price == b.Price then
			return a.DisplayName < b.DisplayName
		end
		return a.Price < b.Price
	end)
	return list
end

-- The two cars a fused car is made from (nil for ordinary cars).
function CarCatalog.parents(def: CarDef): (CarDef?, CarDef?)
	local fusion = def.Fusion
	if not fusion then
		return nil, nil
	end
	return byId[fusion.Base], byId[fusion.Flavor]
end

-- Can a player with these cars and this much Scrap fuse this car? If not, says why.
function CarCatalog.canFuse(def: CarDef, owned: { [string]: boolean }, scrap: number): (boolean, string?)
	local fusion = def.Fusion
	if not fusion then
		return false, "That car can't be fused."
	elseif owned[def.Id] then
		return false, "You already have this car."
	end
	local base, flavor = CarCatalog.parents(def)
	for _, parent in { base, flavor } do
		if parent and not owned[parent.Id] then
			return false, `You need the {parent.DisplayName} first.`
		end
	end
	if scrap < fusion.Cost then
		return false, `You need {fusion.Cost - scrap} more Scrap.`
	end
	return true, nil
end

-- The car's name at an evolution stage (1 = as unlocked).
function CarCatalog.stageName(def: CarDef, stage: number): string
	return def.StageNames[math.clamp(stage, 1, #def.StageNames)] or def.DisplayName
end

function CarCatalog.isValidId(id: unknown): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return CarCatalog
