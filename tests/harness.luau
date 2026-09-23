-- Loads the game's shared modules outside of Roblox (in Lune) so their logic can be unit tested.
-- Modules use Roblox-style requires (`require(script.Parent.Foo)`); this harness fakes `script` with a small
-- proxy that maps instance paths onto files under src/, and injects Roblox datatypes (Vector3, CFrame, ...).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local harness = {}

local moduleCache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local makeProxy: (string) -> any

local function resolveFile(path: string): string?
	if fs.isFile(path .. ".luau") then
		return path .. ".luau"
	elseif fs.isDir(path) and fs.isFile(path .. "/init.luau") then
		return path .. "/init.luau"
	end
	return nil
end

local function parentOf(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or path
end

function makeProxy(path: string): any
	return setmetatable({ __path = path }, {
		__index = function(_, key: string)
			if key == "Parent" then
				return makeProxy(parentOf(path))
			elseif key == "Name" then
				return string.match(path, "([^/]+)$")
			end
			return makeProxy(path .. "/" .. key)
		end,
		__tostring = function()
			return `ScriptProxy({path})`
		end,
	})
end

local fakeRequire: (any) -> any

local function loadModule(path: string): any
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local file = resolveFile(path)
	assert(file, `harness: no module at {path}`)
	assert(not loading[path], `harness: require cycle at {path}`)
	loading[path] = true
	local env = harness.makeEnvironment(makeProxy(path))
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
	local result = chunk()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

local builtins: { [string]: any } = {
	["@lune/roblox"] = roblox,
	["@lune/fs"] = fs,
	["@lune/luau"] = luau,
}

function fakeRequire(target: any): any
	if type(target) == "table" and rawget(target, "__path") then
		return loadModule(rawget(target, "__path"))
	elseif type(target) == "string" and builtins[target] then
		return builtins[target]
	end
	error(`harness: unsupported require target {tostring(target)}`)
end

-- Extra globals (like a fake `game`) that specs can inject into every module they load.
harness.globals = {} :: { [string]: any }

function harness.makeEnvironment(scriptProxy: any): { [string]: any }
	local env = {
		script = scriptProxy,
		require = fakeRequire,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Enum = roblox.Enum,
		BrickColor = roblox.BrickColor,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		ColorSequence = roblox.ColorSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Instance = roblox.Instance,
		Font = roblox.Font,
		Rect = roblox.Rect,
	}
	for name, value in harness.globals do
		env[name] = value
	end
	return env
end

-- Loads another file from tests/ (like sim.luau) with the same environment specs get.
function harness.loadFile(path: string): any
	local env = harness.makeEnvironment(nil)
	env.harness = harness
	env.Shared = harness.Shared
	env.Server = harness.Server
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end

-- The shared and server folders, as seen from a test: require(Shared.Physics.BallSim)
harness.Shared = makeProxy("src/shared")
harness.Server = makeProxy("src/server")
harness.require = fakeRequire

return harness
