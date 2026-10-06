-- Teams: a few players team up against bots, more than a team's worth are split evenly, and people joining a
-- match in progress join the players already there.
local Teams = require(Shared.Match.Teams)

return function(t)
	local expect = t.expect

	local function count(teams: { Teams.Team }): (number, number)
		local blue, orange = 0, 0
		for _, team in teams do
			if team == "Blue" then
				blue += 1
			else
				orange += 1
			end
		end
		return blue, orange
	end

	t.test("up to three players are all on one team", function()
		for n = 1, 3 do
			local blue, orange = count(Teams.split(n, 3, "Orange"))
			expect.equal(blue, 0)
			expect.equal(orange, n)
		end
	end)

	t.test("more players than a team are split evenly", function()
		local blue, orange = count(Teams.split(4, 3, "Blue"))
		expect.equal(blue, 2)
		expect.equal(orange, 2)
		blue, orange = count(Teams.split(5, 3, "Blue"))
		expect.equal(blue, 3)
		expect.equal(orange, 2)
		blue, orange = count(Teams.split(6, 3, "Orange"))
		expect.equal(blue, 3)
		expect.equal(orange, 3)
	end)

	t.test("someone joining a match joins the other players", function()
		expect.equal(Teams.joinTeam({ Blue = 1, Orange = 0 }, { Blue = 2, Orange = 3 }), "Blue")
		expect.equal(Teams.joinTeam({ Blue = 0, Orange = 2 }, { Blue = 3, Orange = 1 }), "Orange")
		-- Their team is full: the other side it is.
		expect.equal(Teams.joinTeam({ Blue = 3, Orange = 0 }, { Blue = 0, Orange = 3 }), "Orange")
		-- Players on both sides: the side with fewer players.
		expect.equal(Teams.joinTeam({ Blue = 2, Orange = 1 }, { Blue = 1, Orange = 2 }), "Orange")
		-- Nobody playing yet (only bots): any free seat.
		expect.truthy(Teams.joinTeam({ Blue = 0, Orange = 0 }, { Blue = 3, Orange = 3 }) ~= nil)
		-- No bots left to take over.
		expect.equal(Teams.joinTeam({ Blue = 3, Orange = 3 }, { Blue = 0, Orange = 0 }), nil)
	end)
end
