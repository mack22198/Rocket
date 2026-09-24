--!strict
-- Colours, fonts and small helpers that give every screen the same bright, chunky look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)

local rgb = Color3.fromRGB

local Theme = {}

Theme.Title = Enum.Font.FredokaOne
Theme.Body = Enum.Font.GothamBold

Theme.Colors = {
	Panel = rgb(22, 26, 48),
	PanelLight = rgb(40, 48, 84),
	PanelDark = rgb(12, 14, 28),
	Text = rgb(255, 255, 255),
	Muted = rgb(170, 182, 214),
	Gold = rgb(255, 204, 51),
	Scrap = rgb(255, 176, 64),
	Good = rgb(88, 222, 118),
	Bad = rgb(255, 92, 92),
	Blue = GameConfig.Teams.Blue.Color,
	Orange = GameConfig.Teams.Orange.Color,
	Mega = rgb(255, 120, 40),
	Boost = rgb(255, 200, 50),
	Evolve = rgb(186, 120, 255), -- car XP and evolving
	Ink = rgb(10, 12, 24), -- outlines and text on bright buttons
}

function Theme.teamColor(team: string?): Color3
	if team == "Blue" then
		return Theme.Colors.Blue
	elseif team == "Orange" then
		return Theme.Colors.Orange
	end
	return Theme.Colors.Muted
end

function Theme.corner(parent: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or rgb(0, 0, 0)
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.padding(parent: GuiObject, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
end

function Theme.gradient(parent: GuiObject, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
end

function Theme.panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.corner(frame, 16)
	Theme.stroke(frame, rgb(255, 255, 255), 2).Transparency = 0.82
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(rgb(255, 255, 255), rgb(170, 175, 195))
	shade.Rotation = 90
	shade.Parent = frame
	return frame
end

export type LabelOptions = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	font: Enum.Font?,
	color: Color3?,
	scaled: boolean?,
	textSize: number?,
	align: Enum.TextXAlignment?,
	stroke: boolean?,
	zIndex: number?,
}

function Theme.label(parent: Instance, options: LabelOptions): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = options.name or "Label"
	label.Size = options.size
	label.Position = options.position or UDim2.new()
	label.AnchorPoint = options.anchor or Vector2.zero
	label.BackgroundTransparency = 1
	label.Text = options.text
	label.Font = options.font or Theme.Title
	label.TextColor3 = options.color or Theme.Colors.Text
	label.TextScaled = if options.scaled == nil then true else options.scaled
	label.TextSize = options.textSize or 24
	label.TextXAlignment = options.align or Enum.TextXAlignment.Center
	label.TextWrapped = true
	label.ZIndex = options.zIndex or 1
	if options.stroke ~= false then
		label.TextStrokeTransparency = 0.4
		label.TextStrokeColor3 = rgb(0, 0, 0)
	end
	label.Parent = parent
	return label
end

export type ButtonOptions = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	color: Color3?,
	textColor: Color3?,
}

-- A chunky button: bright colour, a darker rim and a little shine on top.
function Theme.button(parent: Instance, options: ButtonOptions): TextButton
	local color = options.color or Theme.Colors.Gold
	local button = Instance.new("TextButton")
	button.Name = options.name or "Button"
	button.Size = options.size
	button.Position = options.position or UDim2.new()
	button.AnchorPoint = options.anchor or Vector2.zero
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = options.text
	button.Font = Theme.Title
	button.TextScaled = true
	button.TextColor3 = options.textColor or Theme.Colors.Ink
	button.Parent = parent
	Theme.corner(button, 14)
	Theme.stroke(button, color:Lerp(rgb(0, 0, 0), 0.5), 3)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(rgb(255, 255, 255), rgb(205, 205, 205))
	shine.Rotation = 90
	shine.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = button
	return button
end

-- Sets a Theme.button's colour (keeping its rim in step).
function Theme.setButtonColor(button: TextButton, color: Color3, textColor: Color3?)
	button.BackgroundColor3 = color
	button.TextColor3 = textColor or Theme.Colors.Ink
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color:Lerp(rgb(0, 0, 0), 0.5)
	end
end

export type PillOptions = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	color: Color3?, -- text colour
	background: Color3?,
	transparency: number?,
	font: Enum.Font?,
}

-- A rounded label with its own background, for short bits of status.
function Theme.pill(parent: Instance, options: PillOptions): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = options.name or "Pill"
	label.Size = options.size
	label.Position = options.position or UDim2.new()
	label.AnchorPoint = options.anchor or Vector2.zero
	label.BackgroundColor3 = options.background or Theme.Colors.Panel
	label.BackgroundTransparency = options.transparency or 0.1
	label.BorderSizePixel = 0
	label.Text = options.text
	label.Font = options.font or Theme.Title
	label.TextScaled = true
	label.TextColor3 = options.color or Theme.Colors.Text
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	Theme.stroke(label, rgb(255, 255, 255), 2).Transparency = 0.8
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = label
	return label
end

export type Bar = { frame: Frame, fill: Frame, set: (fraction: number) -> () }

-- A rounded progress bar. Call bar.set(0..1) to fill it.
function Theme.bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): Bar
	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Colors.PanelDark
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	Theme.stroke(frame, rgb(255, 255, 255), 1.5).Transparency = 0.85
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = frame
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 200, 200))
	shine.Rotation = 90
	shine.Parent = fill
	return {
		frame = frame,
		fill = fill,
		set = function(fraction: number)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.005
		end,
	}
end

-- UI is laid out in pixels for a 1280x720 screen and scaled per panel, so it's a sensible size from phones
-- to TVs. (Each panel scales around its own anchor point, so corner-anchored panels stay in their corners.)
local scaleObjects: { UIScale } = {}
local currentScale = 1
local scaleListeners: { (number) -> () } = {}

local function computeScale(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1.5)
end

local function refreshScale()
	currentScale = computeScale()
	for _, scale in scaleObjects do
		scale.Scale = currentScale
	end
	for _, listener in scaleListeners do
		task.spawn(listener, currentScale)
	end
end

local watchingViewport = false
local function watchViewport()
	if watchingViewport then
		return
	end
	watchingViewport = true
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
	refreshScale()
end

function Theme.scaled(object: GuiObject): UIScale
	watchViewport()
	local scale = Instance.new("UIScale")
	scale.Scale = currentScale
	scale.Parent = object
	table.insert(scaleObjects, scale)
	return scale
end

function Theme.getScale(): number
	watchViewport()
	return currentScale
end

function Theme.onScaleChanged(listener: (number) -> ())
	watchViewport()
	table.insert(scaleListeners, listener)
end

function Theme.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local replaced, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end
	return formatted
end

function Theme.screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	return gui
end

return Theme
