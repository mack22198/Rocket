--!strict
-- Who plays on which team. The game is built to be fun with only a few people online, so players team up:
-- up to a full team plays together against bots, and only when there are more players than that are they
-- split between the two teams (as evenly as possible). Bots fill every other seat.

local Teams = {}

export type Team = "Blue" | "Orange"

export type Counts = { Blue: number, Orange: number }

local function other(team: Team): Team
	return if team == "Blue" then "Orange" else "Blue"
end
Teams.other = other

-- The team for each of `count` players at kickoff. `home` is the team a small group plays on together.
function Teams.split(count: number, teamSize: number, home: Team): { Team }
	local teams: { Team } = {}
	for i = 1, count do
		if count <= teamSize then
			table.insert(teams, home)
		else
			table.insert(teams, if i % 2 == 1 then home else other(home))
		end
	end
	return teams
end

-- The team a player joining a match in progress should take a bot's seat on (nil if there's no bot seat).
-- While all the players are on one side they keep teaming up; once both sides have players, the side with
-- fewer of them gets the new one.
function Teams.joinTeam(players: Counts, botSeats: Counts): Team?
	local onlyBlue = players.Blue > 0 and players.Orange == 0
	local onlyOrange = players.Orange > 0 and players.Blue == 0
	if onlyBlue and botSeats.Blue > 0 then
		return "Blue"
	elseif onlyOrange and botSeats.Orange > 0 then
		return "Orange"
	end
	local best: Team? = nil
	for _, team: Team in { "Blue", "Orange" } :: { Team } do
		if botSeats[team] > 0 and (best == nil or players[team] < players[best]) then
			best = team
		end
	end
	return best
end

return Teams
