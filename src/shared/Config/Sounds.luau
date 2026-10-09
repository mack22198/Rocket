--!strict
-- Every sound in the game, in one place. Each plays a sound that comes with Roblox until you give it a better one
-- from the Toolbox:
--   1. In Studio, open the Toolbox (View > Toolbox) and choose Audio.
--   2. Find a sound you like (each one's Note says what to look for) and right-click it > Copy Asset ID.
--   3. Paste the number as its Id below (e.g. Id = 1234567890), save, and press Play to hear it.
-- An Id of 0 keeps the built-in sound, or silence for the ones that don't have one (music, the crowd, the
-- whistle and the cheer). Roblox only plays sounds a game is allowed to use: sounds made by Roblox in the
-- Toolbox and sounds you've uploaded yourself always work.
-- (Car horns are set up with the rest of the style items in Cosmetics.)

local Sounds = {}

export type SoundDef = {
	Id: number, -- a Toolbox sound's asset ID (0 = use BuiltIn)
	BuiltIn: string?, -- a sound that comes with Roblox (nil = silent until it has an Id)
	Volume: number, -- 1 = as loud as the game asks for
	Looped: boolean?, -- plays over and over in the background
	Note: string, -- what to look for in the Toolbox
}

Sounds.List = {
	-- In a match
	Jump = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/action_jump.mp3",
		Volume = 1,
		Note = "a springy car hop",
	},
	Hit = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/action_jump_land.mp3",
		Volume = 1,
		Note = "a big rubbery ball kick",
	},
	Whoosh = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/swoosh.wav",
		Volume = 1,
		Note = "a fast whoosh (dashes and ultimates)",
	},
	Goal = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 1,
		Note = "a stadium goal horn",
	},
	Bump = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/action_jump_land.mp3",
		Volume = 1,
		Note = "a cartoon car bonk (when your car gets bumped)",
	},
	Poof = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/action_jump_land.mp3",
		Volume = 1,
		Note = "a cartoon explosion poof (when a car gets demolished)",
	},
	Pickup = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/button.wav",
		Volume = 1,
		Note = "a sparkly pickup chime (grabbing the charge orb)",
	},
	Ultimate = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 1,
		Note = "a big power-up blast (whenever someone sets off their ultimate)",
	},
	Orb = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/button.wav",
		Volume = 0.8,
		Note = "a magical twinkle (when the charge orb appears)",
	},
	Engine = {
		Id = 0,
		Volume = 0.35,
		Looped = true,
		Note = "a car engine hum (loops on your car and gets higher the faster you go)",
	},
	DashLoop = { Id = 0, Volume = 0.5, Looped = true, Note = "a rocket or jet roar (loops while your car dashes)" },
	Cheer = { Id = 0, Volume = 0.8, Note = "a stadium crowd cheering (after goals)" },
	Whistle = { Id = 0, Volume = 0.7, Note = "a referee's whistle (kickoffs and full time)" },
	Crowd = { Id = 0, Volume = 0.25, Looped = true, Note = "stadium crowd chatter (loops during matches)" },
	MatchMusic = { Id = 0, Volume = 0.15, Looped = true, Note = "energetic background music (loops during matches)" },
	-- In the menus
	Click = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/button.wav",
		Volume = 1,
		Note = "a menu button click",
	},
	Fanfare = {
		Id = 0,
		BuiltIn = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 1,
		Note = "a short victory fanfare (unlocking, evolving and fusing cars)",
	},
	MenuMusic = { Id = 0, Volume = 0.3, Looped = true, Note = "fun, upbeat music (loops in the menus)" },
} :: { [string]: SoundDef }

-- The sound to play for one of the names above ("" = nothing to play).
function Sounds.idFor(name: string): string
	local def = Sounds.List[name]
	if not def then
		return ""
	elseif def.Id > 0 then
		return `rbxassetid://{def.Id}`
	end
	return def.BuiltIn or ""
end

return Sounds
