-- Builds the game's real screens (HUD, garage, results...) in Lune with pretend services, then writes the
-- GUI tree to JSON so ui.html can draw it. This is only a preview: nothing here runs in the game.
-- Usage (from the repository root):  lune run tools/preview/ui-export <scenario> <out.json>
--   scenarios: lobby, match, touch, goal, garage, evolve, results

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local harness = require("../../tests/harness")

local scenario = process.args[1] or "lobby"
local outPath = process.args[2] or "tools/preview/ui.json"

local Vector2 = roblox.Vector2
local Instance = roblox.Instance

local function signal()
	local s = { handlers = {} }
	function s.Connect(self, fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	s.Once = s.Connect
	function s.Wait() end
	function s.Fire(self, ...)
		for _, fn in self.handlers do
			fn(...)
		end
	end
	return s
end

local NOW = 10000
local touch = scenario == "touch"

-- Pretend match state.
local attrs: { [string]: any } = {
	Phase = "Intermission",
	PhaseEndsAt = NOW + 14,
	BlueScore = 0,
	OrangeScore = 0,
	ClockRunning = false,
	ClockRemaining = 300,
	Overtime = false,
	Banner = "",
}
if scenario ~= "lobby" and scenario ~= "garage" and scenario ~= "evolve" then
	attrs.Phase = "Playing"
	attrs.BlueScore = 2
	attrs.OrangeScore = 1
	attrs.ClockRunning = true
	attrs.ClockEndsAt = NOW + 154
end
if scenario == "results" then
	attrs.Phase = "Results"
end
local stateObject = {
	Name = "MatchState",
	GetAttribute = function(_, name)
		return attrs[name]
	end,
	SetAttribute = function(_, name, value)
		attrs[name] = value
	end,
	GetAttributeChangedSignal = function()
		return signal()
	end,
}

local remotes = setmetatable({}, {
	__index = function(t, name)
		local remote = {
			OnClientEvent = signal(),
			OnServerEvent = signal(),
			FireServer = function() end,
			InvokeServer = function()
				return nil
			end,
		}
		rawset(t, name, remote)
		return remote
	end,
})
remotes.BallFlags = { Snap = 1, Hidden = 2, Frozen = 4 }
harness.preload("src/shared/Net/Remotes", remotes)

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local localPlayer = {
	Name = "Player1",
	DisplayName = "Player1",
	UserId = 1,
	WaitForChild = function(_, name)
		assert(name == "PlayerGui", name)
		return playerGui
	end,
	FindFirstChild = function(_, name)
		return if name == "PlayerGui" then playerGui else nil
	end,
	GetAttribute = function()
		return nil
	end,
}

local renderStepped, heartbeat = signal(), signal()
local services = {
	Players = { LocalPlayer = localPlayer, GetPlayers = function()
		return { localPlayer }
	end },
	ReplicatedStorage = {
		WaitForChild = function(_, name)
			if name == "Shared" then
				return harness.Shared
			elseif name == "MatchState" then
				return stateObject
			end
			error(`unexpected ReplicatedStorage:WaitForChild({name})`)
		end,
	},
	RunService = {
		IsServer = function()
			return false
		end,
		IsClient = function()
			return true
		end,
		IsStudio = function()
			return false
		end,
		RenderStepped = renderStepped,
		Heartbeat = heartbeat,
		PreSimulation = signal(),
	},
	TweenService = {
		Create = function(_, object, _info, goal)
			return {
				Play = function()
					for key, value in goal do
						object[key] = value
					end
				end,
				Cancel = function() end,
				Completed = signal(),
			}
		end,
	},
	UserInputService = {
		TouchEnabled = touch,
		KeyboardEnabled = not touch,
		GamepadEnabled = false,
		MouseEnabled = not touch,
		InputBegan = signal(),
		InputEnded = signal(),
		InputChanged = signal(),
		TouchStarted = signal(),
		TouchEnded = signal(),
		LastInputTypeChanged = signal(),
		GetLastInputType = function()
			return if touch then roblox.Enum.UserInputType.Touch else roblox.Enum.UserInputType.Keyboard
		end,
	},
	StarterGui = { SetCore = function() end },
	SoundService = Instance.new("Folder"),
	GuiService = {
		GetGuiInset = function()
			return Vector2.new(0, 58), Vector2.zero
		end,
	},
}
harness.globals.game = {
	GetService = function(_, name)
		return services[name] or error(`no fake service {name}`)
	end,
}
harness.globals.workspace = {
	CurrentCamera = {
		ViewportSize = Vector2.new(1280, 720),
		GetPropertyChangedSignal = function()
			return signal()
		end,
	},
	GetServerTimeNow = function()
		return NOW
	end,
}
harness.globals.task = task
harness.globals.TweenInfo = { new = function(...)
	return { ... }
end }

-- Pretend player data and car.
local data = {
	scrap = 740,
	owned = { pizza = true, banana = true, kart = true },
	equipped = "banana",
	stats = {},
	carXp = { pizza = 620, banana = 1540, kart = 90 },
	carStage = { pizza = 1, banana = 2 },
	carLook = { banana = 2 },
}
local carAttrs = { Boost = 67, Mega = 100, MegaArmed = false, Team = "Blue", Stage = 2 }
local driving = attrs.Phase == "Playing"
local car = {
	Name = "Car",
	GetAttribute = function(_, name)
		return carAttrs[name]
	end,
	GetAttributeChangedSignal = function()
		return signal()
	end,
}
local controllers = "src/client/Controllers/"
harness.preload(controllers .. "PlayerDataClient", {
	get = function()
		return data
	end,
	isLoaded = function()
		return true
	end,
	Changed = signal(),
	start = function() end,
})
harness.preload(controllers .. "CarController", {
	getCar = function()
		return if driving then car else nil
	end,
	getChassis = function()
		return nil
	end,
	isGrounded = function()
		return true
	end,
	CarChanged = signal(),
	Jumped = signal(),
	start = function() end,
	addVelocity = function() end,
})
harness.preload(controllers .. "CameraController", {
	isBallCam = function()
		return true
	end,
	shake = function() end,
	start = function() end,
})
harness.preload(controllers .. "InputController", {
	MegaPressed = signal(),
	BallCamToggled = signal(),
	setTouchStick = function() end,
	setTouchButton = function() end,
	setDriving = function() end,
	read = function()
		return {}
	end,
	start = function() end,
})
harness.preload(controllers .. "EffectsController", {
	play = function() end,
	start = function() end,
})

-- Lune's instances have no events, so button clicks and the like get pretend signals in the preview.
local events: { [any]: { [string]: any } } = {}
harness.globals.__event = function(object, name: string)
	if type(object) == "table" then
		-- Already a fake (a service or controller): use its signal if it has one.
		local value = object[name]
		return if type(value) == "table" and value.Connect then value else signal()
	end
	events[object] = events[object] or {}
	events[object][name] = events[object][name] or signal()
	return events[object][name]
end
harness.globals.__pivotTo = function(model, target)
	local primary = model.PrimaryPart
	local offset = target * (if primary then primary.CFrame else roblox.CFrame.new()):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = offset * d.CFrame
		end
	end
end
local UI_EVENTS = { "Activated", "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave" }
for _, name in { "HUD", "Announcer", "ResultsScreen", "Garage", "TouchControls", "Theme" } do
	harness.sourceTransforms["src/client/UI/" .. name] = function(source)
		for _, event in UI_EVENTS do
			source = string.gsub(source, "([%w_%.]+)%." .. event .. ":", "__event(%1, \"" .. event .. "\"):")
		end
		source = string.gsub(source, "([%w_%.]+):PivotTo%(", "__pivotTo(%1, ")
		return (string.gsub(source, "([%w_%.]+):GetPropertyChangedSignal%(([^)]*)%)", "__event(%1, %2)"))
	end
end

local UI = harness.Client.UI
local HUD = harness.require(UI.HUD)
local Announcer = harness.require(UI.Announcer)
local ResultsScreen = harness.require(UI.ResultsScreen)
local Garage = harness.require(UI.Garage)
local TouchControls = harness.require(UI.TouchControls)
HUD.start()
Announcer.start()
ResultsScreen.start()
Garage.start()
if touch then
	TouchControls.start()
end

local function frame()
	renderStepped:Fire(1 / 60)
	heartbeat:Fire(1 / 60)
end
frame()

if scenario == "goal" then
	remotes.GoalScored.OnClientEvent:Fire("Blue", "Player1", "Sparky (bot)", roblox.Vector3.new(0, 10, 160), "AIR HIT")
	remotes.Announce.OnClientEvent:Fire("style", "AIR HIT!", "Blue", "Player1")
	remotes.Announce.OnClientEvent:Fire("save", "EPIC SAVE!", "Orange", "Bolt (bot)")
elseif scenario == "garage" then
	Garage.open()
elseif scenario == "evolve" then
	data.carXp.pizza = 520
	Garage.open("pizza")
elseif scenario == "results" then
	remotes.MatchResults.OnClientEvent:Fire({
		outcome = "Win",
		team = "Blue",
		blueScore = 3,
		orangeScore = 2,
		mvp = "Player1",
		youAreMvp = true,
		lines = {
			{ label = "Played a match", amount = 60 },
			{ label = "Victory!", amount = 60 },
			{ label = "Goals x2", amount = 50 },
			{ label = "Saves x1", amount = 20 },
			{ label = "Ball touches x31", amount = 6 },
			{ label = "MVP!", amount = 20 },
		},
		total = 216,
		scrap = 956,
		nextGoal = {
			carId = "shark",
			displayName = "Neon Shark",
			emoji = "🦈",
			price = 1000,
			have = 956,
			remaining = 44,
			canAfford = false,
		},
		scoreboard = {
			{ name = "Player1", team = "Blue", points = 412, goals = 2, assists = 0, saves = 1, isBot = false },
			{ name = "Sparky (bot)", team = "Blue", points = 180, goals = 1, assists = 1, saves = 0, isBot = true },
			{ name = "Zippy (bot)", team = "Blue", points = 96, goals = 0, assists = 1, saves = 1, isBot = true },
			{ name = "Bolt (bot)", team = "Orange", points = 250, goals = 1, assists = 0, saves = 2, isBot = true },
			{ name = "Comet (bot)", team = "Orange", points = 210, goals = 1, assists = 1, saves = 0, isBot = true },
			{ name = "Dash (bot)", team = "Orange", points = 88, goals = 0, assists = 0, saves = 1, isBot = true },
		},
		stats = { goals = 2, assists = 0, saves = 1, shots = 4, touches = 31, styleTouches = 3 },
		car = {
			id = "banana",
			name = "Ripe Banana Car",
			emoji = "🍌",
			xpGained = 216,
			progress = {
				stage = 2,
				maxStage = 4,
				xp = 1540,
				nextStage = 3,
				nextName = "Lava Banana Car",
				xpForNext = 1500,
				fraction = 1,
				ready = true,
			},
		},
	})
end
-- Let delayed animations (reward lines counting up, etc.) finish, then take the picture.
task.wait(if scenario == "goal" then 0.3 else 2.5)
frame()

---------------------------------------------------------------------------------------------------------------
-- Serialize every ScreenGui.
---------------------------------------------------------------------------------------------------------------

local function prop(instance, name: string, fallback: any): any
	local ok, value = pcall(function()
		return instance[name]
	end)
	return if ok and value ~= nil then value else fallback
end
local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end
local function udim(u)
	return { u.Scale, u.Offset }
end
local function color(c)
	return { c.R, c.G, c.B }
end
local function enumName(value, fallback: string): string
	return if value then value.Name else fallback
end

local function serialize(inst)
	local node: { [string]: any } = { class = inst.ClassName, name = inst.Name, children = {} }
	if inst:IsA("GuiObject") then
		node.pos = udim2(inst.Position)
		node.size = udim2(inst.Size)
		node.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		node.bg = color(inst.BackgroundColor3)
		node.bgT = inst.BackgroundTransparency
		node.visible = inst.Visible
		node.z = inst.ZIndex
		node.order = inst.LayoutOrder
		node.rot = inst.Rotation
		node.clip = prop(inst, "ClipsDescendants", false)
		node.autoSize = enumName(prop(inst, "AutomaticSize", nil), "None")
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			node.text = inst.Text
			node.textColor = color(inst.TextColor3)
			node.textT = prop(inst, "TextTransparency", 0)
			node.strokeT = prop(inst, "TextStrokeTransparency", 1)
			node.strokeColor = color(prop(inst, "TextStrokeColor3", roblox.Color3.new(0, 0, 0)))
			node.font = enumName(prop(inst, "Font", nil), "SourceSans")
			node.scaled = prop(inst, "TextScaled", false)
			node.textSize = prop(inst, "TextSize", 14)
			node.wrapped = prop(inst, "TextWrapped", false)
			node.xAlign = enumName(prop(inst, "TextXAlignment", nil), "Center")
			node.yAlign = enumName(prop(inst, "TextYAlignment", nil), "Center")
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			node.image = prop(inst, "Image", "")
			node.imageColor = color(prop(inst, "ImageColor3", roblox.Color3.new(1, 1, 1)))
			node.imageT = prop(inst, "ImageTransparency", 0)
		end
	elseif inst:IsA("ScreenGui") then
		node.displayOrder = prop(inst, "DisplayOrder", 0)
		node.ignoreInset = prop(inst, "IgnoreGuiInset", false)
		node.enabled = prop(inst, "Enabled", true)
	elseif inst:IsA("UICorner") then
		node.radius = udim(inst.CornerRadius)
	elseif inst:IsA("UIStroke") then
		node.color = color(prop(inst, "Color", roblox.Color3.new(0, 0, 0)))
		node.thickness = prop(inst, "Thickness", 1)
		node.t = prop(inst, "Transparency", 0)
		node.mode = enumName(prop(inst, "ApplyStrokeMode", nil), "Contextual")
		node.enabled = prop(inst, "Enabled", true)
	elseif inst:IsA("UIGradient") then
		local keys = {}
		for _, k in inst.Color.Keypoints do
			table.insert(keys, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
		local tkeys = {}
		for _, k in prop(inst, "Transparency", roblox.NumberSequence.new(0)).Keypoints do
			table.insert(tkeys, { k.Time, k.Value })
		end
		node.colors = keys
		node.alphas = tkeys
		node.rotation = prop(inst, "Rotation", 0)
		node.enabled = prop(inst, "Enabled", true)
	elseif inst:IsA("UIPadding") then
		node.pad = {
			udim(prop(inst, "PaddingTop", roblox.UDim.new())),
			udim(prop(inst, "PaddingBottom", roblox.UDim.new())),
			udim(prop(inst, "PaddingLeft", roblox.UDim.new())),
			udim(prop(inst, "PaddingRight", roblox.UDim.new())),
		}
	elseif inst:IsA("UIScale") then
		node.scale = prop(inst, "Scale", 1)
	elseif inst:IsA("UIListLayout") then
		node.fill = enumName(prop(inst, "FillDirection", nil), "Vertical")
		node.padding = udim(prop(inst, "Padding", roblox.UDim.new()))
		node.hAlign = enumName(prop(inst, "HorizontalAlignment", nil), "Left")
		node.vAlign = enumName(prop(inst, "VerticalAlignment", nil), "Top")
		node.sort = enumName(prop(inst, "SortOrder", nil), "Name")
	elseif inst:IsA("UIGridLayout") then
		node.cellSize = udim2(prop(inst, "CellSize", roblox.UDim2.fromOffset(100, 100)))
		node.cellPadding = udim2(prop(inst, "CellPadding", roblox.UDim2.fromOffset(5, 5)))
		node.fill = enumName(prop(inst, "FillDirection", nil), "Horizontal")
		node.hAlign = enumName(prop(inst, "HorizontalAlignment", nil), "Left")
		node.vAlign = enumName(prop(inst, "VerticalAlignment", nil), "Top")
		node.sort = enumName(prop(inst, "SortOrder", nil), "Name")
	elseif inst:IsA("UIAspectRatioConstraint") then
		node.ratio = prop(inst, "AspectRatio", 1)
	elseif inst:IsA("UITextSizeConstraint") then
		node.maxText = prop(inst, "MaxTextSize", 100)
		node.minText = prop(inst, "MinTextSize", 1)
	end
	for _, child in inst:GetChildren() do
		table.insert(node.children, serialize(child))
	end
	return node
end

local screens = {}
for _, child in playerGui:GetChildren() do
	if child:IsA("ScreenGui") then
		table.insert(screens, serialize(child))
	end
end
table.sort(screens, function(a, b)
	return a.displayOrder < b.displayOrder
end)
fs.writeFile(outPath, serde.encode("json", { scenario = scenario, touch = touch, screens = screens }))
print(`wrote {#screens} screens for '{scenario}' to {outPath}`)
