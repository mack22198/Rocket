-- Sounds: every sound the code plays is listed in Sounds, and each one is set up sensibly.
local fs = require("@lune/fs")
local Sounds = require(Shared.Config.Sounds)

return function(t)
	local expect = t.expect

	t.test("every sound is set up sensibly", function()
		for name, def in Sounds.List do
			expect.truthy(def.Id >= 0 and def.Id == math.floor(def.Id), `{name}'s Id is 0 or an asset ID`)
			expect.truthy(def.Volume > 0 and def.Volume <= 2, `{name} can be heard`)
			expect.truthy(#def.Note > 5, `{name} says what to look for`)
			if def.Id == 0 then
				expect.equal(Sounds.idFor(name), def.BuiltIn or "")
			else
				expect.equal(Sounds.idFor(name), `rbxassetid://{def.Id}`)
			end
		end
		expect.equal(Sounds.idFor("NoSuchSound"), "")
	end)

	t.test("every sound the game plays is in the list", function()
		local function scan(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					scan(path)
				elseif string.match(entry, "%.luau$") then
					local source = fs.readFile(path)
					for name in string.gmatch(source, '%.play%("(%w+)"') do
						expect.truthy(Sounds.List[name] ~= nil, `{path} plays "{name}"`)
					end
				end
			end
		end
		scan("src")
	end)
end
