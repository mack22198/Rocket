--!strict
-- When is a bump a demolition? When you smash into a car on the other team faster than any car can drive
-- without boosting. Bots never demolish players who are still in their first few matches, so new players
-- aren't picked on while they learn. (Bubble Shields and Shark Dives can't be bumped at all; see BumpService.)

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Demolition = {}

export type Side = {
	team: string,
	bot: boolean,
	matches: number, -- matches finished before this one
}

-- `speed` is how fast the attacker was closing in on the victim.
function Demolition.check(attacker: Side, victim: Side, speed: number): boolean
	if attacker.team == victim.team or speed < GameConfig.Bump.DemoSpeed then
		return false
	end
	if attacker.bot and not victim.bot and victim.matches < GameConfig.Bots.RookieMatches then
		return false
	end
	return true
end

return Demolition
