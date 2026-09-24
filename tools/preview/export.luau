-- Builds the stadium, lobby, cars and ball with the game's real builder code (using Lune's Roblox
-- instances) and writes every part to a JSON file that the three.js previewer can draw.
-- Usage (from the repository root):  lune run tools/preview/export <out.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local harness = require("../../tests/harness")

local outPath = process.args[1] or "tools/preview/scene.json"

local dataModel = roblox.Instance.new("DataModel")
local workspaceInstance = dataModel:GetService("Workspace")
local sharedProxy = harness.Shared
local fakeReplicatedStorage = {
	WaitForChild = function(_, name: string)
		assert(name == "Shared", `unexpected WaitForChild({name})`)
		return sharedProxy
	end,
}
harness.globals.workspace = workspaceInstance
harness.globals.game = {
	GetService = function(_, name: string)
		if name == "ReplicatedStorage" then
			return fakeReplicatedStorage
		end
		return dataModel:GetService(name)
	end,
}

-- Lune instances have no PivotTo; do the same maths by hand.
local function pivotTo(model, target)
	local primary = model.PrimaryPart
	local pivot = if primary then primary.CFrame else roblox.CFrame.new()
	local offset = target * pivot:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = offset * d.CFrame
		end
	end
end
harness.globals.__pivotTo = pivotTo
for _, path in { "src/server/Arena/LobbyBuilder", "src/server/Arena/EnvironmentBuilder" } do
	harness.sourceTransforms[path] = function(source)
		return (string.gsub(source, "([%w_%.]+):PivotTo%(", "__pivotTo(%1, "))
	end
end

local Shared = harness.Shared
local Server = harness.Server
local ArenaBuilder = harness.require(Server.Arena.ArenaBuilder)
local StadiumBuilder = harness.require(Server.Arena.StadiumBuilder)
local LobbyBuilder = harness.require(Server.Arena.LobbyBuilder)
local EnvironmentBuilder = harness.require(Server.Arena.EnvironmentBuilder)
local CarCatalog = harness.require(Shared.Config.CarCatalog)
local CarModelBuilder = harness.require(Shared.Cars.CarModelBuilder)
local GameConfig = harness.require(Shared.Config.GameConfig)
local BallModelBuilder = harness.require(Shared.Ball.BallModelBuilder)

local extras = {}
ArenaBuilder.build()
StadiumBuilder.build()
LobbyBuilder.build()
EnvironmentBuilder.build()
extras.terrain = {}
for _, piece in EnvironmentBuilder.terrainPlan() do
	table.insert(extras.terrain, {
		kind = piece.kind,
		cf = { roblox.CFrame.new(piece.position):GetComponents() },
		size = { piece.size.X, piece.size.Y, piece.size.Z },
		radius = piece.size.X / 2,
		material = piece.material,
	})
end

-- A line-up of every car (each evolution stage if the builder supports it) for close-up shots.
local showcase = roblox.Instance.new("Folder")
showcase.Name = "Showcase"
showcase.Parent = workspaceInstance
-- Car i's evolution stages stand side by side, 14 studs apart, facing +Z, starting at x = (i - 1) * 100.
local stages = GameConfig.Evolution.Stages
for i, def in CarCatalog.ordered() do
	for stage = 1, stages do
		local model = CarModelBuilder.build(def, { preview = true, stage = stage, teamColor = GameConfig.Teams.Blue.Color })
		local x = (i - 1) * 100 + (stage - 1) * 14
		local z = 600
		pivotTo(model, roblox.CFrame.new(x, def.Hitbox.Y / 2 + 0.9, z) * roblox.CFrame.Angles(0, math.rad(205), 0))
		model.Parent = showcase
	end
end
-- Kickoff line-up in the arena: blue cars on their spots, orange cars on theirs.
local kick = { { -48, 70 }, { 48, 70 }, { 0, 125 } }
for t, team in { "Blue", "Orange" } do
	local side = GameConfig.Teams[team].DefendsSide
	for slot = 1, 3 do
		local def = CarCatalog.ordered()[((t - 1) * 3 + slot - 1) % #CarCatalog.ordered() + 1]
		local stage = ((t - 1) * 3 + slot - 1) % GameConfig.Evolution.Stages + 1
		local model = CarModelBuilder.build(def, { preview = true, stage = stage, teamColor = GameConfig.Teams[team].Color })
		local pos = roblox.Vector3.new(kick[slot][1] * side, def.Hitbox.Y / 2 + 0.9, kick[slot][2] * side)
		local look = (roblox.Vector3.new(0, pos.Y, 0) - pos).Unit
		local right = look:Cross(roblox.Vector3.yAxis).Unit
		local up = right:Cross(look)
		pivotTo(model, roblox.CFrame.fromMatrix(pos, right, up))
		model.Parent = showcase
	end
end

-- The ball on the centre spot.
local ball = BallModelBuilder.build()
pivotTo(ball, roblox.CFrame.new(0, GameConfig.Ball.Radius, 0))
ball.Parent = showcase

local parts = {}
local guis = {}
local lights = {}
local function color(c)
	return { c.R, c.G, c.B }
end
-- Where each label sits on a SurfaceGui, as fractions of the face (x, y, width, height).
local function guiTexts(gui)
	local frame = gui:FindFirstChildWhichIsA("Frame")
	local labels = {}
	for _, g in gui:GetDescendants() do
		if g:IsA("TextLabel") then
			table.insert(labels, g)
		end
	end
	local texts = {}
	local stacked = frame and frame:FindFirstChildWhichIsA("UIListLayout")
	if stacked then
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local total = 0
		for _, label in labels do
			total += label.Size.Y.Scale
		end
		local y = (1 - total) / 2
		for _, label in labels do
			local w, h = label.Size.X.Scale, label.Size.Y.Scale
			table.insert(texts, { text = label.Text, col = color(label.TextColor3), rect = { (1 - w) / 2, y, w, h } })
			y += h
		end
	else
		for _, label in labels do
			local w, h = label.Size.X.Scale, label.Size.Y.Scale
			local x = label.Position.X.Scale - label.AnchorPoint.X * w
			local y = label.Position.Y.Scale - label.AnchorPoint.Y * h
			table.insert(texts, { text = label.Text, col = color(label.TextColor3), rect = { x, y, w, h } })
		end
	end
	return texts
end

local function guiBackground(gui)
	for _, g in gui:GetDescendants() do
		if g:IsA("Frame") and g.BackgroundTransparency < 1 then
			return color(g.BackgroundColor3)
		end
	end
	return nil
end

for _, d in workspaceInstance:GetDescendants() do
	if d:IsA("BasePart") then
		local shape = "Block"
		if d.ClassName == "WedgePart" then
			shape = "Wedge"
		elseif d.ClassName == "CornerWedgePart" then
			shape = "CornerWedge"
		elseif d.ClassName == "Part" or d.ClassName == "SpawnLocation" then
			shape = d.Shape.Name
		end
		local mesh = d:FindFirstChildWhichIsA("SpecialMesh")
		local size = d.Size
		if mesh then
			size = size * mesh.Scale
			if mesh.MeshType == roblox.Enum.MeshType.Sphere then
				shape = "Ellipsoid"
			elseif mesh.MeshType == roblox.Enum.MeshType.Cylinder then
				shape = "MeshCylinder"
			end
		end
		local cf = { d.CFrame:GetComponents() }
		table.insert(parts, {
			n = d.Name,
			s = shape,
			sz = { size.X, size.Y, size.Z },
			cf = cf,
			col = color(d.Color),
			m = d.Material.Name,
			t = d.Transparency,
			r = d.Reflectance,
		})
		local index = #parts
		for _, child in d:GetChildren() do
			if child:IsA("SurfaceGui") then
				table.insert(guis, {
					part = index,
					face = child.Face.Name,
					texts = guiTexts(child),
					bg = guiBackground(child),
					pps = child.PixelsPerStud,
				})
			elseif child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
				table.insert(lights, { part = index, col = color(child.Color), range = child.Range, b = child.Brightness })
			end
		end
	end
end

local scene = {
	parts = parts,
	guis = guis,
	lights = lights,
	terrain = extras.terrain or {},
}
fs.writeFile(outPath, serde.encode("json", scene))
print(`wrote {#parts} parts, {#guis} signs, {#lights} lights to {outPath}`)
