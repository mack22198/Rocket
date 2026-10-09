--!strict
-- When is a bump a demolition? When you smash into a car on the other team in the middle of a dash, faster than
-- any car can drive on its own (only the Kart's Nitro Rocket does that). Bots never demolish players who are
-- still in their first few matches, so new players aren't picked on while they learn. (Shark Dives can't be
-- bumped at all; see BumpService.)

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Demolition = {}

export type Side = {
	team: string,
	bot: boolean,
	matches: number, -- matches finished before this one
	dashing: boolean, -- in the middle of a Nitro Rocket
}

-- `speed` is how fast the attacker was closing in on the victim.
function Demolition.check(attacker: Side, victim: Side, speed: number): boolean
	if attacker.team == victim.team or not attacker.dashing or speed < GameConfig.Bump.DemoSpeed then
		return false
	end
	if attacker.bot and not victim.bot and victim.matches < GameConfig.Bots.RookieMatches then
		return false
	end
	return true
end

return Demolition
