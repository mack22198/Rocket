-- Runs every tests/specs/*.spec.luau file. Usage (from the repository root):  lune run tests/run
-- Each spec returns a function(t) that registers tests with t.test(name, fn) and uses the t.expect helpers.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local harness = require("./harness")

local passed, failed = 0, 0
local failures: { string } = {}

local function formatValue(value: any): string
	return tostring(value)
end

local expect = {}

function expect.truthy(value: any, message: string?)
	if not value then
		error(message or `expected a truthy value, got {formatValue(value)}`, 2)
	end
end

function expect.falsy(value: any, message: string?)
	if value then
		error(message or `expected a falsy value, got {formatValue(value)}`, 2)
	end
end

function expect.equal(actual: any, wanted: any, message: string?)
	if actual ~= wanted then
		error(message or `expected {formatValue(wanted)}, got {formatValue(actual)}`, 2)
	end
end

function expect.near(actual: number, wanted: number, tolerance: number, message: string?)
	if math.abs(actual - wanted) > tolerance then
		error(message or `expected {wanted} (+/- {tolerance}), got {actual}`, 2)
	end
end

function expect.atLeast(actual: number, minimum: number, message: string?)
	if actual < minimum then
		error(message or `expected at least {minimum}, got {actual}`, 2)
	end
end

function expect.atMost(actual: number, maximum: number, message: string?)
	if actual > maximum then
		error(message or `expected at most {maximum}, got {actual}`, 2)
	end
end

local filter = process.args[1]

local specDir = "tests/specs"
local files = fs.readDir(specDir)
table.sort(files)
for _, name in files do
	if not string.match(name, "%.spec%.luau$") then
		continue
	end
	if filter and not string.find(name, filter, 1, true) then
		continue
	end
	local path = `{specDir}/{name}`
	local env = harness.makeEnvironment(nil)
	env.Shared = harness.Shared
	env.Server = harness.Server
	env.harness = harness
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local register = chunk()
	local tests: { { name: string, fn: () -> () } } = {}
	register({
		test = function(testName: string, fn: () -> ())
			table.insert(tests, { name = testName, fn = fn })
		end,
		expect = expect,
	})
	for _, case in tests do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, `{name} > {case.name}\n    {tostring(err)}`)
		end
	end
end

for _, failure in failures do
	print(`FAIL {failure}`)
end
print(`{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
