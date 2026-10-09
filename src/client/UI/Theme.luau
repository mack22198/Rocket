--!strict
-- The look every screen shares: flat, solid colours with a thick dark outline, like stickers and toy parts.
--
--   * Menus are cream CARDS with dark text. Things you can press are chunky BUTTONS with a darker lip along the
--     bottom, so they look like they push in. The in-match HUD uses dark SLABS, so it doesn't fight the pitch.
--   * One bright colour per job: yellow is the main thing to press (PLAY, COLLECT), green is "done" and buying,
--     purple is evolving, pink is the shop, and the team colours are only for teams.
--   * Two typefaces: Luckiest Guy for titles, buttons and big numbers, Gotham for everything else.
--   * Emoji are only used as big pictures (an item, a car, a hat), never in the middle of text; Scrap has its own
--     coin (scrapIcon).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)

local rgb = Color3.fromRGB

local Theme = {}

Theme.Display = Enum.Font.LuckiestGuy -- titles, buttons, big numbers
Theme.Logo = Enum.Font.LuckiestGuy
Theme.Title = Enum.Font.GothamBlack -- names and headings inside cards
Theme.Caps = Enum.Font.GothamBlack -- small labels in capitals
Theme.Body = Enum.Font.GothamBold

Theme.Colors = {
	-- Surfaces
	Ink = rgb(16, 18, 34), -- outlines, shadows and text on light colours
	Card = rgb(255, 248, 234), -- menu cards
	CardShade = rgb(242, 231, 209), -- rows and wells inside cards
	CardLine = rgb(220, 205, 178), -- dividers and empty tracks on cards
	Panel = rgb(30, 33, 58), -- HUD slabs
	PanelLight = rgb(52, 57, 92),
	PanelDark = rgb(20, 22, 40),
	-- Text
	Text = rgb(255, 251, 242), -- on dark surfaces and over the 3D world
	Muted = rgb(160, 168, 204), -- secondary text on dark surfaces
	InkMuted = rgb(122, 112, 98), -- secondary text on cards
	-- Jobs
	Gold = rgb(255, 202, 40), -- the main button, highlights
	Scrap = rgb(255, 186, 52),
	Good = rgb(52, 200, 100),
	GoodText = rgb(28, 150, 68), -- green that reads well as text on cards
	Bad = rgb(238, 70, 70),
	Evolve = rgb(150, 98, 255), -- car XP and evolving
	Shop = rgb(255, 86, 164),
	Sky = rgb(86, 180, 255),
	Blue = GameConfig.Teams.Blue.Color,
	Orange = GameConfig.Teams.Orange.Color,
	Mega = rgb(255, 108, 40),
	Boost = rgb(255, 202, 40),
}

local C = Theme.Colors

-- How much darker the lip along the bottom of buttons and cards is.
local LIP_SHADE = rgb(158, 158, 158)
local BUTTON_LIP = 6 -- pixels
local CARD_LIP = 6

function Theme.teamColor(team: string?): Color3
	if team == "Blue" then
		return C.Blue
	elseif team == "Orange" then
		return C.Orange
	end
	return C.Muted
end

-- Is this a light colour (so text on it should be dark)?
function Theme.isLight(color: Color3): boolean
	return color.R * 0.3 + color.G * 0.59 + color.B * 0.11 > 0.62
end

-- Removes emoji from text (server messages and names from the configs carry some).
function Theme.noEmoji(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		local emoji = (code >= 0x2190 and code <= 0x2BFF)
			or (code >= 0x1F000 and code <= 0x1FAFF)
			or code == 0xFE0F
			or code == 0x200D
			or code == 0x20E3
		if not emoji then
			table.insert(out, utf8.char(code))
		end
	end
	local cleaned = table.concat(out)
	cleaned = string.gsub(cleaned, "%s%s+", " ")
	cleaned = string.gsub(cleaned, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	return cleaned
end

function Theme.corner(parent: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or C.Ink
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- A thick dark outline around text (for text over the 3D world or on bright buttons).
function Theme.outline(label: TextLabel | TextButton, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = C.Ink
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
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

-- The darker band along the bottom of buttons and cards that makes them look solid. `fraction` is how much of
-- the height it takes.
local function lipSequence(fraction: number): ColorSequence
	local f = math.clamp(fraction, 0.03, 0.4)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
		ColorSequenceKeypoint.new(1 - f - 0.002, rgb(255, 255, 255)),
		ColorSequenceKeypoint.new(1 - f, LIP_SHADE),
		ColorSequenceKeypoint.new(1, LIP_SHADE),
	})
end

-- Adds a lip `pixels` tall to an object, keeping it that tall as the object changes size.
local function addLip(object: GuiObject, pixels: number): UIGradient
	local lip = Instance.new("UIGradient")
	lip.Name = "Lip"
	lip.Rotation = 90
	lip.Parent = object
	local function refresh()
		local height = object.Size.Y.Offset
		if object.Size.Y.Scale ~= 0 or height <= 0 then
			local absolute = object.AbsoluteSize.Y
			height = if absolute > 0 then absolute / math.max(Theme.getScale(), 0.01) else 60
		end
		lip.Color = lipSequence(pixels / math.max(height, 1))
	end
	refresh()
	object:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	return lip
end
Theme.lip = addLip

local function surface(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	color: Color3,
	radius: number,
	lip: number
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.corner(frame, radius)
	Theme.stroke(frame, C.Ink, 3)
	if lip > 0 then
		addLip(frame, lip)
	end
	return frame
end

-- A cream menu card with a dark outline.
function Theme.card(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	return surface(parent, name, size, position, anchor, C.Card, 18, CARD_LIP)
end

-- A dark slab, for the in-match HUD.
function Theme.slab(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	return surface(parent, name, size, position, anchor, C.Panel, 14, 5)
end

-- Menu screens are cards.
Theme.panel = Theme.card

-- A flat inset area inside a card (a row, a list, a box of stats).
function Theme.well(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = C.CardShade
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.corner(frame, 12)
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
	textSize: number?, -- the size when not scaled, and the biggest it gets when scaled
	align: Enum.TextXAlignment?,
	stroke: boolean?, -- a dark outline (for text over the 3D world or a bright colour)
	zIndex: number?,
}

-- Text. By default it's dark (for cards) and fills its box, up to `textSize` if that's given.
function Theme.label(parent: Instance, options: LabelOptions): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = options.name or "Label"
	label.Size = options.size
	label.Position = options.position or UDim2.new()
	label.AnchorPoint = options.anchor or Vector2.zero
	label.BackgroundTransparency = 1
	label.Text = options.text
	label.Font = options.font or Theme.Title
	label.TextColor3 = options.color or C.Ink
	label.TextScaled = if options.scaled == nil then true else options.scaled
	label.TextSize = options.textSize or 24
	label.TextXAlignment = options.align or Enum.TextXAlignment.Center
	label.TextWrapped = true
	label.ZIndex = options.zIndex or 1
	if label.TextScaled and options.textSize then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = options.textSize
		limit.Parent = label
	end
	if options.stroke then
		Theme.outline(label, if (options.textSize or 24) >= 40 then 3 else 2)
	end
	label.Parent = parent
	return label
end

-- A big Luckiest Guy heading.
function Theme.heading(parent: Instance, options: LabelOptions): TextLabel
	local copy = table.clone(options)
	copy.font = copy.font or Theme.Display
	return Theme.label(parent, copy)
end

export type ButtonOptions = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	color: Color3?,
	textColor: Color3?,
	font: Enum.Font?,
	textSize: number?, -- the biggest the text gets (it shrinks to fit)
}

-- Buttons grow a little under the mouse (or the gamepad's selection) and squash when pressed.
local function pop(button: GuiButton): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = button
	local function to(size: number, seconds: number?)
		TweenService:Create(scale, TweenInfo.new(seconds or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = size,
		}):Play()
	end
	button.MouseEnter:Connect(function()
		to(1.04)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.94, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.04)
	end)
	button.SelectionGained:Connect(function()
		to(1.06)
	end)
	button.SelectionLost:Connect(function()
		to(1)
	end)
	return scale
end
Theme.pop = pop

-- Text colour and outline for a button of `color`: dark text on light colours, white outlined text on the rest.
local function styleButtonText(button: TextButton, color: Color3, textColor: Color3?)
	local wanted = textColor or (if Theme.isLight(color) then C.Ink else C.Text)
	button.TextColor3 = wanted
	local outline = button:FindFirstChild("Outline")
	if Theme.isLight(wanted) then
		if not outline then
			Theme.outline(button, 2)
		end
	elseif outline then
		outline:Destroy()
	end
end

-- A chunky button: a flat colour, a dark outline and a darker lip along the bottom.
function Theme.button(parent: Instance, options: ButtonOptions): TextButton
	local color = options.color or C.Gold
	local button = Instance.new("TextButton")
	button.Name = options.name or "Button"
	button.Size = options.size
	button.Position = options.position or UDim2.new()
	button.AnchorPoint = options.anchor or Vector2.zero
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = options.text
	button.Font = options.font or Theme.Display
	button.TextScaled = true
	button.TextWrapped = true
	button.Parent = parent
	styleButtonText(button, color, options.textColor)
	Theme.corner(button, 14)
	Theme.stroke(button, C.Ink, 3)
	addLip(button, BUTTON_LIP)
	-- The text sits on the face (above the lip), as big as the button allows.
	local height = if options.size.Y.Scale == 0 then options.size.Y.Offset else 56
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = options.textSize or math.clamp(math.floor(height * 0.46), 14, 44)
	limit.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, BUTTON_LIP + 3)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = button
	pop(button)
	return button
end

-- A band of light that sweeps across a button every few seconds, to draw the eye (the PLAY button).
function Theme.sweep(button: GuiObject, every: number)
	local band = Instance.new("Frame")
	band.Name = "Sweep"
	band.Size = UDim2.fromScale(1, 1)
	band.BackgroundColor3 = rgb(255, 255, 255)
	band.BackgroundTransparency = 0
	band.BorderSizePixel = 0
	band.ZIndex = button.ZIndex + 1
	band.Parent = button
	Theme.corner(band, 14)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 25
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.44, 1),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(0.56, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = band
	task.spawn(function()
		while band.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			TweenService:Create(gradient, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Offset = Vector2.new(1, 0),
			}):Play()
			task.wait(every)
		end
	end)
end

-- Changes a Theme.button's colour (and its text to suit).
function Theme.setButtonColor(button: TextButton, color: Color3, textColor: Color3?)
	button.BackgroundColor3 = color
	styleButtonText(button, color, textColor)
end

-- Puts the gamepad's selection on a button (when a gamepad is being used), so menus work from the sofa.
function Theme.focus(button: GuiObject?)
	if UserInputService.GamepadEnabled then
		pcall(function()
			GuiService.SelectedObject = button
		end)
	end
end

-- A full-screen shade that fades from dark on one side to clear, so things stay readable over the 3D scene.
function Theme.shade(parent: Instance, name: string, fromLeft: boolean, width: number, darkness: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(width, 1)
	frame.Position = if fromLeft then UDim2.new() else UDim2.fromScale(1 - width, 0)
	frame.BackgroundColor3 = rgb(6, 8, 18)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = if fromLeft then 0 else 180
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - darkness),
		NumberSequenceKeypoint.new(0.55, 1 - darkness * 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	return frame
end

-- Darkens everything behind a pop-up.
function Theme.scrim(parent: Instance, darkness: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Scrim"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(6, 8, 18)
	frame.BackgroundTransparency = 1 - (darkness or 0.55)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
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

-- A small rounded tag with its own background, for short bits of status ("NEW", "3 DAYS LEFT").
function Theme.pill(parent: Instance, options: PillOptions): TextLabel
	local background = options.background or C.Ink
	local label = Instance.new("TextLabel")
	label.Name = options.name or "Pill"
	label.Size = options.size
	label.Position = options.position or UDim2.new()
	label.AnchorPoint = options.anchor or Vector2.zero
	label.BackgroundColor3 = background
	label.BackgroundTransparency = options.transparency or 0
	label.BorderSizePixel = 0
	label.Text = options.text
	label.Font = options.font or Theme.Caps
	label.TextScaled = true
	label.TextColor3 = options.color or (if Theme.isLight(background) then C.Ink else C.Text)
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	Theme.stroke(label, C.Ink, 2)
	local height = if options.size.Y.Scale == 0 then options.size.Y.Offset else 30
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.clamp(math.floor(height * 0.5), 10, 26)
	limit.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = label
	return label
end

export type Bar = { frame: Frame, fill: Frame, set: (fraction: number) -> () }

-- A rounded progress bar. Call bar.set(0..1) to fill it. `track` is the empty part's colour (dark by default;
-- use Theme.Colors.CardLine on cards).
function Theme.bar(parent: Instance, size: UDim2, position: UDim2, color: Color3, track: Color3?): Bar
	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = track or C.PanelDark
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	Theme.stroke(frame, C.Ink, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = frame
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	return {
		frame = frame,
		fill = fill,
		set = function(fraction: number)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.005
		end,
	}
end

export type Ring = { segments: { Frame }, set: (fraction: number, color: Color3) -> () }

-- A circle of little segments around the middle of `parent` (a round dial or button) that light up clockwise
-- from the top as ring.set goes from 0 to 1: the whole ring is lit only at 1. `radius` is in pixels.
function Theme.ring(parent: GuiObject, count: number, radius: number, segment: Vector2): Ring
	local segments: { Frame } = {}
	for i = 1, count do
		local angle = math.rad(360 * (i - 0.5) / count)
		local piece = Instance.new("Frame")
		piece.Name = `Segment{i}`
		piece.Size = UDim2.fromOffset(segment.X, segment.Y)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.new(0.5, math.sin(angle) * radius, 0.5, -math.cos(angle) * radius)
		piece.Rotation = math.deg(angle)
		piece.BackgroundColor3 = C.PanelLight
		piece.BorderSizePixel = 0
		piece.Parent = parent
		Theme.corner(piece, 3)
		table.insert(segments, piece)
	end
	return {
		segments = segments,
		set = function(fraction: number, color: Color3)
			local lit = math.floor(math.clamp(fraction, 0, 1) * count + 1e-6)
			for i, piece in segments do
				piece.BackgroundColor3 = if i <= lit then color else C.PanelLight
			end
		end,
	}
end

-- Big text that floats up `rise` pixels and fades away, like "+12" beside a meter that just filled a little.
function Theme.floatText(parent: Instance, text: string, position: UDim2, anchor: Vector2, rise: number)
	local label = Theme.heading(parent, {
		name = "Float",
		size = UDim2.fromOffset(90, 36),
		position = position,
		anchor = anchor,
		text = text,
		color = C.Gold,
		textSize = 34,
		stroke = true,
		zIndex = 6,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = position + UDim2.fromOffset(0, -rise), TextTransparency = 1 }):Play()
	local outline = label:FindFirstChildOfClass("UIStroke")
	if outline then
		TweenService:Create(outline, info, { Transparency = 1 }):Play()
	end
	task.delay(1, function()
		label:Destroy()
	end)
end

-- Scrap's coin: a gold washer with a dark outline. `size` is its width in pixels.
function Theme.scrapIcon(parent: Instance, size: number, position: UDim2?, anchor: Vector2?): Frame
	local coin = Instance.new("Frame")
	coin.Name = "ScrapIcon"
	coin.Size = UDim2.fromOffset(size, size)
	coin.Position = position or UDim2.new()
	coin.AnchorPoint = anchor or Vector2.zero
	coin.BackgroundColor3 = C.Scrap
	coin.BorderSizePixel = 0
	coin.Parent = parent
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = coin
	Theme.stroke(coin, C.Ink, math.max(1.5, size / 12))
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.Size = UDim2.fromScale(0.64, 0.64)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.BackgroundColor3 = rgb(222, 140, 24)
	rim.BorderSizePixel = 0
	rim.Parent = coin
	local rimRound = Instance.new("UICorner")
	rimRound.CornerRadius = UDim.new(0.5, 0)
	rimRound.Parent = rim
	local hole = Instance.new("Frame")
	hole.Name = "Hole"
	hole.Size = UDim2.fromScale(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.BackgroundColor3 = C.Ink
	hole.BorderSizePixel = 0
	hole.Parent = rim
	local holeRound = Instance.new("UICorner")
	holeRound.CornerRadius = UDim.new(0.5, 0)
	holeRound.Parent = hole
	return coin
end

export type Amount = { frame: Frame, label: TextLabel, set: (value: number, prefix: string?) -> () }

-- A Scrap amount: the coin and a number, left to right, `height` pixels tall.
function Theme.amount(parent: Instance, height: number, position: UDim2, anchor: Vector2?, color: Color3?): Amount
	local frame = Instance.new("Frame")
	frame.Name = "Amount"
	frame.Size = UDim2.fromOffset(0, height) -- as wide as the coin and the number
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, math.max(4, height * 0.25))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local coin = Theme.scrapIcon(frame, math.floor(height * 0.86))
	coin.LayoutOrder = 1
	local label = Theme.label(frame, {
		name = "Value",
		size = UDim2.fromOffset(0, height),
		text = "0",
		font = Theme.Display,
		color = color or C.Ink,
		scaled = false,
		textSize = math.floor(height * 0.92),
		align = Enum.TextXAlignment.Left,
	})
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextWrapped = false
	label.LayoutOrder = 2
	return {
		frame = frame,
		label = label,
		set = function(value: number, prefix: string?)
			label.Text = (prefix or "") .. Theme.formatNumber(value)
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
