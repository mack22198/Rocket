--!strict
-- The collectible cars. Rarity is about looks and bragging rights, never raw power:
-- every car trades one strength for a weakness so the rarest car is not simply the best.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type CarStats = {
	Speed: number, -- top speed multiplier
	Acceleration: number,
	Handling: number, -- turning multiplier
	Weight: number, -- resists being bumped
	BumpPower: number, -- how hard this car bumps others
	AirControl: number,
	Jump: number,
}

export type CarDef = {
	Id: string,
	DisplayName: string,
	Emoji: string,
	Rarity: Rarity,
	Price: number, -- Scrap cost (0 = starter car)
	Tagline: string,
	Description: string,
	Hitbox: Vector3, -- width, height, length of the physics box
	Stats: CarStats,
}

local CarCatalog = {}

CarCatalog.StarterId = "pizza"

CarCatalog.Rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(170, 180, 190) },
	Rare = { Order = 2, Color = Color3.fromRGB(60, 150, 255) },
	Epic = { Order = 3, Color = Color3.fromRGB(180, 80, 255) },
	Legendary = { Order = 4, Color = Color3.fromRGB(255, 190, 40) },
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
		Id = "ufo",
		DisplayName = "UFO",
		Emoji = "🛸",
		Rarity = "Epic",
		Price = 3000,
		Tagline = "Floaty flyer",
		Description = "Out of this world air control and bouncy jumps. Not great at bumping.",
		Hitbox = Vector3.new(6.6, 2.2, 7.8),
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

local byId: { [string]: CarDef } = {}
for _, def in cars do
	byId[def.Id] = def
end

function CarCatalog.get(id: string): CarDef?
	return byId[id]
end

-- Starter car first, then by price.
function CarCatalog.ordered(): { CarDef }
	local list = table.clone(cars)
	table.sort(list, function(a, b)
		if a.Price == b.Price then
			return a.DisplayName < b.DisplayName
		end
		return a.Price < b.Price
	end)
	return list
end

function CarCatalog.isValidId(id: unknown): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return CarCatalog
