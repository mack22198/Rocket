--!strict
-- The colours of the stadium, the lobby and the world around them, in one place so they match.

local rgb = Color3.fromRGB

local Palette = {
	-- Pitch
	GrassLight = rgb(104, 184, 86),
	GrassDark = rgb(91, 169, 77),
	Ramp = rgb(86, 160, 75),
	Line = rgb(246, 248, 250),
	GoalFloor = rgb(34, 38, 52),

	-- Walls
	Board = rgb(26, 32, 56),
	Glass = rgb(205, 230, 255),
	Steel = rgb(190, 196, 208),
	DarkSteel = rgb(62, 68, 84),

	-- Stadium
	Concrete = rgb(168, 172, 180),
	DarkConcrete = rgb(88, 92, 104),
	Step = rgb(196, 200, 208),
	Roof = rgb(232, 236, 242),
	Screen = rgb(10, 12, 20),

	-- Lobby
	Deck = rgb(176, 124, 82),
	DeckTrim = rgb(66, 72, 90),
	Gold = rgb(255, 205, 64),

	-- Outside
	Foliage = { rgb(76, 150, 62), rgb(92, 168, 70), rgb(64, 134, 58), rgb(110, 178, 74) },
	Trunk = rgb(110, 78, 52),
	Plaza = rgb(206, 208, 212),
	Road = rgb(58, 62, 70),

	-- The crowd (shirts and skin tones)
	Shirts = {
		rgb(235, 70, 70),
		rgb(255, 205, 64),
		rgb(250, 250, 250),
		rgb(120, 90, 220),
		rgb(60, 200, 120),
		rgb(40, 44, 60),
		rgb(255, 120, 190),
		rgb(90, 210, 240),
	},
	Skin = { rgb(255, 219, 172), rgb(241, 194, 125), rgb(224, 172, 105), rgb(198, 134, 66), rgb(141, 85, 36) },
}

return Palette
