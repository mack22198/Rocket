--!strict
-- Collectible style: hats that sit on your car's roof, horns you honk in a match (H), and the celebration that
-- goes off when YOU score. Only looks and sounds - nothing here changes how a car drives.
-- Prices are fixed and shown up front in the garage's STYLE tab; a few come only from a season's reward track
-- (see Season) - the free one, or the Gold Season Pass's - and one comes with VIP (see Shop).

local Cosmetics = {}

export type Kind = "topper" | "horn" | "celebration"

export type CosmeticDef = {
	Id: string,
	Kind: Kind,
	Name: string,
	Emoji: string,
	Description: string,
	Price: number, -- Scrap (0 = free)
	Default: boolean?, -- everyone starts with it
	Season: string?, -- only from the reward track of the season with this theme (see Season.Themes)...
	Gold: boolean?, -- ...the Gold Season Pass's track
	Vip: boolean?, -- comes with VIP (see Shop)
	Sound: string?, -- horns: which sound, and how high it plays
	Pitch: number?,
	Word: string?, -- horns: the word that pops up over your car
}

Cosmetics.List = {
	-- Hats
	{
		Id = "none",
		Kind = "topper",
		Name = "No Hat",
		Emoji = "🚫",
		Description = "Keep it clean.",
		Price = 0,
		Default = true,
	},
	{ Id = "cap", Kind = "topper", Name = "Racing Cap", Emoji = "🧢", Description = "A sporty cap.", Price = 250 },
	{
		Id = "party",
		Kind = "topper",
		Name = "Party Hat",
		Emoji = "🥳",
		Description = "Every match is a party.",
		Price = 300,
	},
	{
		Id = "cone",
		Kind = "topper",
		Name = "Traffic Cone",
		Emoji = "🚧",
		Description = "Caution: winner ahead.",
		Price = 350,
	},
	{ Id = "tophat", Kind = "topper", Name = "Top Hat", Emoji = "🎩", Description = "Very fancy.", Price = 400 },
	{ Id = "chick", Kind = "topper", Name = "Baby Chick", Emoji = "🐣", Description = "Cheep cheep!", Price = 500 },
	{
		Id = "unicorn",
		Kind = "topper",
		Name = "Unicorn Horn",
		Emoji = "🦄",
		Description = "Pure magic.",
		Price = 700,
	},
	{
		Id = "crown",
		Kind = "topper",
		Name = "Golden Crown",
		Emoji = "👑",
		Description = "The top prize of the Food Fight season.",
		Price = 0,
		Season = "foodfight",
	},
	{
		Id = "trophy",
		Kind = "topper",
		Name = "Gold Trophy",
		Emoji = "🏆",
		Description = "The top prize of the Food Fight Gold Pass.",
		Price = 0,
		Season = "foodfight",
		Gold = true,
	},
	{
		Id = "diamond",
		Kind = "topper",
		Name = "Diamond Crown",
		Emoji = "💎",
		Description = "Sparkly! For VIPs only.",
		Price = 0,
		Vip = true,
	},
	-- Horns
	{
		Id = "beep",
		Kind = "horn",
		Name = "Beep Beep",
		Emoji = "📢",
		Description = "A friendly little beep.",
		Price = 0,
		Default = true,
		Sound = "rbxasset://sounds/electronicpingshort.wav",
		Pitch = 1.4,
		Word = "BEEP!",
	},
	{
		Id = "honk",
		Kind = "horn",
		Name = "Big Honk",
		Emoji = "📯",
		Description = "A big, deep honk.",
		Price = 150,
		Sound = "rbxasset://sounds/electronicpingshort.wav",
		Pitch = 0.5,
		Word = "HONK!",
	},
	{
		Id = "boing",
		Kind = "horn",
		Name = "Boing",
		Emoji = "🪀",
		Description = "Bouncy!",
		Price = 200,
		Sound = "rbxasset://sounds/action_jump.mp3",
		Pitch = 0.8,
		Word = "BOING!",
	},
	{
		Id = "whoosh",
		Kind = "horn",
		Name = "Whoosh",
		Emoji = "💨",
		Description = "Gone with the wind.",
		Price = 250,
		Sound = "rbxasset://sounds/swoosh.wav",
		Pitch = 0.8,
		Word = "WHOOSH!",
	},
	{
		Id = "oof",
		Kind = "horn",
		Name = "Oof",
		Emoji = "😵",
		Description = "A classic.",
		Price = 300,
		Sound = "rbxasset://sounds/uuhhh.mp3",
		Pitch = 1,
		Word = "OOF!",
	},
	{
		Id = "fanfare",
		Kind = "horn",
		Name = "Champion Fanfare",
		Emoji = "🎺",
		Description = "A winning tune from the Food Fight season.",
		Price = 0,
		Season = "foodfight",
		Sound = "rbxasset://sounds/electronicpingshort.wav",
		Pitch = 1.9,
		Word = "TA-DA!",
	},
	{
		Id = "airhorn",
		Kind = "horn",
		Name = "Stadium Air Horn",
		Emoji = "📣",
		Description = "The loudest horn in the stadium, from the Food Fight Gold Pass.",
		Price = 0,
		Season = "foodfight",
		Gold = true,
		Sound = "rbxasset://sounds/electronicpingshort.wav",
		Pitch = 0.75,
		Word = "BWAAAP!",
	},
	-- Goal celebrations
	{
		Id = "fireworks",
		Kind = "celebration",
		Name = "Fireworks",
		Emoji = "🎆",
		Description = "Fireworks over the stands.",
		Price = 0,
		Default = true,
	},
	{
		Id = "confetti",
		Kind = "celebration",
		Name = "Confetti Storm",
		Emoji = "🎊",
		Description = "A blizzard of confetti over the whole pitch.",
		Price = 300,
	},
	{
		Id = "stars",
		Kind = "celebration",
		Name = "Star Shower",
		Emoji = "⭐",
		Description = "Golden stars rain from the sky.",
		Price = 400,
	},
	{
		Id = "ducks",
		Kind = "celebration",
		Name = "Duck Rain",
		Emoji = "🦆",
		Description = "It's raining rubber ducks!",
		Price = 500,
	},
	{
		Id = "tacos",
		Kind = "celebration",
		Name = "Taco Party",
		Emoji = "🌮",
		Description = "Tacos everywhere!",
		Price = 500,
	},
	{
		Id = "rainbow",
		Kind = "celebration",
		Name = "Rainbow Blast",
		Emoji = "🌈",
		Description = "A rainbow over the goal, from the Food Fight season.",
		Price = 0,
		Season = "foodfight",
	},
	{
		Id = "goldrush",
		Kind = "celebration",
		Name = "Gold Rush",
		Emoji = "🪙",
		Description = "It rains gold coins, from the Food Fight Gold Pass.",
		Price = 0,
		Season = "foodfight",
		Gold = true,
	},
} :: { CosmeticDef }

Cosmetics.Kinds = { "topper", "horn", "celebration" } :: { Kind }

Cosmetics.KindNames = {
	topper = "🎩 HATS",
	horn = "📯 HORNS",
	celebration = "🎉 PARTIES",
}

local byId: { [string]: CosmeticDef } = {}
for _, def in Cosmetics.List do
	byId[def.Id] = def
end

function Cosmetics.get(id: string?): CosmeticDef?
	return if id then byId[id] else nil
end

-- Every item of one kind, in shop order.
function Cosmetics.ofKind(kind: Kind): { CosmeticDef }
	local list = {}
	for _, def in Cosmetics.List do
		if def.Kind == kind then
			table.insert(list, def)
		end
	end
	return list
end

-- What everyone starts with, and wears until they pick something else.
function Cosmetics.defaults(): { [string]: boolean }
	local owned = {}
	for _, def in Cosmetics.List do
		if def.Default then
			owned[def.Id] = true
		end
	end
	return owned
end

function Cosmetics.defaultFor(kind: Kind): string
	for _, def in Cosmetics.List do
		if def.Kind == kind and def.Default then
			return def.Id
		end
	end
	return ""
end

-- Can this be bought with Scrap in the shop? (Season rewards and VIP items can't.)
function Cosmetics.forSale(def: CosmeticDef): boolean
	return def.Season == nil and not def.Default and not def.Vip
end

return Cosmetics
