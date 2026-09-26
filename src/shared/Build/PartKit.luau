--!strict
-- Small helpers for building the stadium out of anchored parts.

local PartKit = {}

export type Props = {
	Name: string?,
	Size: Vector3?, -- required by part(); the other helpers fill it in
	CFrame: CFrame?,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Shape: Enum.PartType?,
	Collide: boolean?, -- default true
	Query: boolean?, -- default = Collide (so decorations are invisible to wheel rays)
	Shadow: boolean?,
}

export type BannerItem = { text: string, color: Color3 }
export type SignOptions = { color: Color3?, background: Color3?, font: Enum.Font?, pixelsPerStud: number? }
export type BannerOptions = { background: Color3?, font: Enum.Font?, pixelsPerStud: number?, textHeight: number? }

local function apply(part: BasePart, props: Props)
	assert(props.Size and props.CFrame, "PartKit: parts need a Size and a CFrame")
	part.Anchored = true
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	local collide = if props.Collide == nil then true else props.Collide
	part.CanCollide = collide
	part.CanQuery = if props.Query == nil then collide else props.Query
	part.CanTouch = false
	part.CastShadow = if props.Shadow == nil then true else props.Shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- A solid, anchored part.
function PartKit.part(parent: Instance, props: Props): Part
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	if props.Shape then
		part.Shape = props.Shape
	end
	apply(part, props)
	part.Parent = parent
	return part
end

-- A decoration: no collisions, and ignored by raycasts.
function PartKit.decor(parent: Instance, props: Props): Part
	props.Collide = false
	props.Query = false
	return PartKit.part(parent, props)
end

-- A wedge (the slope rises from the front, -Z, to the back, +Z).
function PartKit.wedge(parent: Instance, props: Props): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = props.Name or "Wedge"
	apply(part, props)
	part.Parent = parent
	return part
end

-- An axis-aligned box between two corners.
function PartKit.box(parent: Instance, low: Vector3, high: Vector3, props: Props): Part
	props.Size = high - low
	props.CFrame = CFrame.new((low + high) / 2)
	return PartKit.part(parent, props)
end

-- A part stretched between two points (for beams, posts and lines).
function PartKit.between(parent: Instance, a: Vector3, b: Vector3, thickness: number, props: Props): Part
	local offset = b - a
	local direction = offset.Unit
	local up = if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = direction:Cross(up).Unit
	local realUp = right:Cross(direction)
	props.CFrame = CFrame.fromMatrix((a + b) / 2, right, realUp)
	props.Size = Vector3.new(thickness, thickness, offset.Magnitude)
	return PartKit.part(parent, props)
end

-- A flat disc lying on the ground (a cylinder turned upright), centred at `centre`.
function PartKit.disc(parent: Instance, centre: Vector3, radius: number, height: number, props: Props): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, radius * 2, radius * 2)
	props.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2)
	return PartKit.part(parent, props)
end

local function surfaceGui(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = part
	return gui
end

local function backgroundFrame(gui: SurfaceGui, background: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Background"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background or Color3.new(0, 0, 0)
	frame.BackgroundTransparency = if background then 0 else 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return frame
end

-- Lines of text stacked on one face of a part (the first line is the big title).
function PartKit.sign(part: BasePart, face: Enum.NormalId, lines: { string }, options: SignOptions?): SurfaceGui
	local o: SignOptions = options or ({} :: SignOptions)
	local gui = surfaceGui(part, "Sign", face, o.pixelsPerStud or 20)
	local frame = backgroundFrame(gui, o.background)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	for i, text in lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{i}`
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(0.94, (if i == 1 then 1.6 else 1) / (#lines + 0.6) * 0.92)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = o.color or Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = if i == 1 then (o.font or Enum.Font.FredokaOne) else Enum.Font.GothamBold
		label.Parent = frame
	end
	return gui
end

-- Short labels side by side across one face of a part, like the adverts on the boards.
function PartKit.banner(part: BasePart, face: Enum.NormalId, items: { BannerItem }, options: BannerOptions?): SurfaceGui
	local o: BannerOptions = options or ({} :: BannerOptions)
	local gui = surfaceGui(part, "Banner", face, o.pixelsPerStud or 10)
	local frame = backgroundFrame(gui, o.background)
	for i, item in items do
		local label = Instance.new("TextLabel")
		label.Name = `Item{i}`
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale((i - 0.5) / #items, 0.5)
		label.Size = UDim2.fromScale(0.86 / #items, o.textHeight or 0.62)
		label.BackgroundTransparency = 1
		label.Text = item.text
		label.TextColor3 = item.color
		label.TextScaled = true
		label.Font = o.font or Enum.Font.FredokaOne
		label.Parent = frame
	end
	return gui
end

-- One label at a spot on a face (position and size as fractions of the face). Returns the label so it can
-- be updated later (the scoreboards do this).
function PartKit.label(
	gui: SurfaceGui,
	name: string,
	text: string,
	color: Color3,
	centre: Vector2,
	size: Vector2,
	font: Enum.Font?
): TextLabel
	local frame = gui:FindFirstChild("Background") or backgroundFrame(gui, nil)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(centre.X, centre.Y)
	label.Size = UDim2.fromScale(size.X, size.Y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = font or Enum.Font.FredokaOne
	label.Parent = frame
	return label
end

-- An empty SurfaceGui (with a background) to put labels on.
function PartKit.screen(part: BasePart, face: Enum.NormalId, background: Color3?, pixelsPerStud: number?): SurfaceGui
	local gui = surfaceGui(part, "Screen", face, pixelsPerStud or 10)
	backgroundFrame(gui, background)
	return gui
end

return PartKit
