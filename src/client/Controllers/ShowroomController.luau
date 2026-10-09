--!strict
-- Runs the garage showroom behind the menus (see ShowroomBuilder): builds it the first time it's needed, puts
-- the right car on the turntable, flies the camera, and swaps the lighting to a dark studio look - then hands
-- the camera and lighting back when a match starts.
--
-- Drag across the car (mouse or finger) to spin it yourself.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local MathUtil = require(Shared.Util.MathUtil)

local ShowroomBuilder = require(script.Parent.Parent.Showroom.ShowroomBuilder)
local CameraController = require(script.Parent.CameraController)

local ShowroomController = {}

export type Mode = "menu" | "garage"

local rgb = Color3.fromRGB

local SPIN_SPEED = math.rad(11) -- turntable speed, radians per second
local DRAG_SPEED = 0.012 -- radians per pixel dragged
local DROP_TIME = 0.55 -- a new car drops onto the turntable for this long
local DROP_HEIGHT = 3.5
local EVOLVE_COLOR = rgb(186, 120, 255)

-- The studio look. Anything listed here is put back exactly as it was when the showroom closes.
local LIGHTING: { [string]: any } = {
	Ambient = rgb(30, 32, 42),
	OutdoorAmbient = rgb(30, 32, 42),
	Brightness = 0,
	ClockTime = 0, -- night outside, so shiny paint reflects a dark sky instead of a blue one
	EnvironmentDiffuseScale = 0.2,
	EnvironmentSpecularScale = 0.5,
	ExposureCompensation = 0,
}
local EFFECTS: { [string]: { [string]: any } } = {
	Atmosphere = { Density = 0, Haze = 0, Glare = 0 },
	-- Only the neon (the ring, the lamps, the screen) glows; the car's paint never should.
	BloomEffect = { Intensity = 0.4, Size = 24, Threshold = 1.3 },
	ColorCorrectionEffect = {
		Contrast = 0.12,
		Saturation = 0.1,
		Brightness = 0,
		TintColor = Color3.new(0.97, 0.98, 1),
	},
	SunRaysEffect = { Intensity = 0 },
}

type Shot = ShowroomBuilder.Shot

local room: ShowroomBuilder.Showroom? = nil
local display: ShowroomBuilder.Display? = nil
local active = false
local mode: Mode = "menu"
local shownDef: CarCatalog.CarDef? = nil
local shownStage = 1
local shownTopper: string? = nil
local builtKey = ""
local yaw = math.rad(-30)
local dropStarted = -math.huge
local celebrateStarted = -math.huge
local dragging = false
local lastDrag = -math.huge
local shot: Shot = table.clone(ShowroomBuilder.Shots.menu)
local saved: { [Instance]: { [string]: any } } = {}
local focus: DepthOfFieldEffect? = nil
local ringColor = rgb(170, 180, 190)
local flashBase: { [Light]: number } = {}

local function glowFor(def: CarCatalog.CarDef): Color3
	local rarity = CarCatalog.Rarities[def.Rarity]
	return if rarity then rarity.Color else rgb(170, 180, 190)
end

local function setRingColor(color: Color3)
	local r = room
	if not r then
		return
	end
	for _, part in r.rings do
		part.Color = color
	end
end

-- Swaps in the car we're meant to be showing (if it isn't there already).
local function refreshDisplay()
	local r, def = room, shownDef
	if not r or not def then
		return
	end
	local key = `{def.Id}:{shownStage}:{shownTopper or ""}`
	if key == builtKey then
		return
	end
	builtKey = key
	if display then
		display.destroy()
	end
	ringColor = glowFor(def)
	setRingColor(ringColor)
	display = ShowroomBuilder.display(r, def, shownStage, ringColor, shownTopper)
	r.screenLine.Text = string.upper(CarCatalog.stageName(def, shownStage))
	dropStarted = os.clock()
	local sparkles = r.sparkles
	if sparkles then
		sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), ringColor)
		sparkles:Emit(24)
	end
end

local function ensureRoom(): ShowroomBuilder.Showroom
	local existing = room
	if existing then
		return existing
	end
	local built = ShowroomBuilder.build()
	room = built
	for _, light in built.flashLights do
		flashBase[light] = light.Brightness
	end
	refreshDisplay()
	return built
end

local function override(object: Instance, values: { [string]: any })
	local store = saved[object] or {}
	for key, value in values do
		local ok, current = pcall(function()
			return (object :: any)[key]
		end)
		if ok then
			if store[key] == nil then
				store[key] = current
			end
			pcall(function()
				(object :: any)[key] = value
			end)
		end
	end
	saved[object] = store
end

local function restoreLighting()
	for object, store in saved do
		for key, value in store do
			pcall(function()
				(object :: any)[key] = value
			end)
		end
	end
	table.clear(saved)
end

local function applyLighting()
	override(Lighting, LIGHTING)
	for className, values in EFFECTS do
		local effect = Lighting:FindFirstChildOfClass(className)
		if effect then
			override(effect, values)
		end
	end
end

-- Eases a number: out-cubic for the drop, then a little bounce.
local function dropLift(t: number): number
	if t >= 1 then
		return 0
	end
	local fall = 1 - (1 - t) ^ 3
	return DROP_HEIGHT * (1 - fall) + math.sin(t * math.pi) * 0.25 * (1 - t)
end

-- Where the camera goes this frame.
local function cameraFrame(dt: number): (CFrame?, number)
	local r = room
	local camera = workspace.CurrentCamera
	if not active or not r or not camera then
		return nil, 70
	end
	-- Glide between the menu and garage shots.
	local target = ShowroomBuilder.Shots[mode]
	local blend = MathUtil.expDecay(3.2, dt)
	for key, value in target :: any do
		(shot :: any)[key] = MathUtil.lerp((shot :: any)[key], value, blend)
	end
	-- A slow drift so the picture never feels frozen, and a punch-in while a car evolves.
	local t = os.clock()
	local sway: Shot = table.clone(shot)
	sway.angle += math.sin(t * 0.19) * math.rad(4)
	sway.height += math.sin(t * 0.31) * 0.3
	local celebrating = t - celebrateStarted
	if celebrating < 2.2 then
		sway.distance *= 1 - 0.14 * math.sin(math.clamp(celebrating / 2.2, 0, 1) * math.pi)
	end
	local viewport = camera.ViewportSize
	local position, aim = ShowroomBuilder.camera(sway, viewport.X / math.max(viewport.Y, 1))
	local f = focus
	if f then
		f.FocusDistance = (position - (r.origin + Vector3.new(0, 2, 0))).Magnitude
	end
	return MathUtil.lookAlong(position, aim - position, Vector3.yAxis), sway.fov
end

local function update(dt: number)
	if not active then
		return
	end
	local now = os.clock()
	if not dragging and now - lastDrag > 1.5 then
		yaw += SPIN_SPEED * dt
	end
	local d = display
	if d then
		d.place(yaw, dropLift((now - dropStarted) / DROP_TIME))
	end

	-- Evolving: the ring and lights pulse in evolution purple, then settle back.
	local r = room
	local celebrating = now - celebrateStarted
	if r and celebrating < 2.6 then
		local pulse = (math.sin(celebrating * 14) + 1) / 2 * (1 - celebrating / 2.6)
		setRingColor(ringColor:Lerp(EVOLVE_COLOR, 0.35 + 0.65 * pulse))
		for light, base in flashBase do
			light.Brightness = base * (1 + pulse * 1.5)
		end
	elseif r and celebrating < 2.7 then
		setRingColor(ringColor)
		for light, base in flashBase do
			light.Brightness = base
		end
	end
end

-- Turns the showroom on (camera, lighting, the room itself) or off.
function ShowroomController.setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	local r = ensureRoom()
	if on then
		r.folder.Parent = workspace
		applyLighting()
		if focus then
			focus.Enabled = true
		end
		shot = table.clone(ShowroomBuilder.Shots[mode])
		CameraController.setProvider(cameraFrame)
	else
		CameraController.setProvider(nil)
		restoreLighting()
		if focus then
			focus.Enabled = false
		end
		r.folder.Parent = nil
	end
end

function ShowroomController.isActive(): boolean
	return active
end

-- "menu" frames the car on the right (the menu is on the left); "garage" puts it in the middle.
function ShowroomController.setMode(newMode: Mode)
	mode = newMode
end

-- Puts a car on the turntable (at an evolution stage, wearing a hat if `topper` is given).
function ShowroomController.showCar(def: CarCatalog.CarDef, stage: number, topper: string?)
	shownDef = def
	shownStage = stage
	shownTopper = if topper == "none" then nil else topper
	refreshDisplay()
end

-- Builds the car on the turntable again (after the smooth car meshes turn up).
function ShowroomController.rebuild()
	builtKey = ""
	refreshDisplay()
end

-- The big moment when a car evolves: lights pulse, sparkles fly and the camera leans in.
function ShowroomController.celebrate()
	celebrateStarted = os.clock()
	local r = room
	local sparkles = r and r.sparkles
	if sparkles then
		sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), EVOLVE_COLOR)
		sparkles:Emit(90)
	end
end

function ShowroomController.start()
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "ShowroomFocus"
	dof.FarIntensity = 0.4
	dof.NearIntensity = 0
	dof.InFocusRadius = 12
	dof.FocusDistance = 22
	dof.Enabled = false
	dof.Parent = Lighting
	focus = dof

	RunService.RenderStepped:Connect(update)

	-- Drag to spin the car (only when the drag didn't start on a button or panel).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not active or processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			yaw += input.Delta.X * DRAG_SPEED
			lastDrag = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = false
			lastDrag = os.clock()
		end
	end)
end

return ShowroomController
