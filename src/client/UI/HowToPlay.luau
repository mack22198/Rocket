--!strict
-- "How to play": six picture cards that explain the whole game in a few words, plus the controls for
-- keyboard, gamepad and touch. Opened from the main menu and the in-match menu.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local HowToPlay = {}

local C = Theme.Colors
local rgb = Color3.fromRGB

local CARDS = {
	{
		icon = "⚽",
		title = "SCORE GOALS",
		text = "Drive into the ball to knock it into the other team's goal. Most goals when the clock hits 0:00 wins!",
		color = C.Good,
	},
	{
		icon = "🚀",
		title = "BOOST & JUMP",
		text = "Boost to go super fast - pads fill it up. Jump twice to flip! Smash the other team at full boost - POOF!",
		color = C.Boost,
	},
	{
		icon = "🎁",
		title = "ITEM BOXES",
		text = "Drive through a ? box to grab an item, like a Magnet or Freeze Ray. Losing? You get better ones!",
		color = rgb(120, 200, 255),
	},
	{
		icon = "⚡",
		title = "CAR POWERS",
		text = "Every car has its own power, like Cheese Trap or Ground Pound. It charges back up after each use!",
		color = rgb(255, 214, 90),
	},
	{
		icon = "💥",
		title = "MEGA SHOT",
		text = "Touching the ball fills your Mega meter. When it's full, press Mega and your next hit blasts the ball!",
		color = C.Mega,
	},
	{
		icon = "🔩",
		title = "UNLOCK & EVOLVE",
		text = "Matches earn Scrap for new cars and season rewards (more with friends!). Drive a car to make it evolve!",
		color = C.Evolve,
	},
}

local CONTROLS = {
	{ "⌨️", "WASD drive · SPACE jump · SHIFT boost · R item · G power · F mega · H horn · C cam · M menu" },
	{
		"🎮",
		"RT/LT drive · A jump · B boost · RB item · LB power · X mega · D-pad up horn · Y cam · VIEW menu",
	},
	{ "📱", "Drag toward where you want to go, then JUMP, BOOST, ITEM and POWER. Mega Shot arms itself!" },
}

local gui: ScreenGui
local panel: Frame
local closeButton: TextButton
local onClosed: (() -> ())? = nil

local function card(parent: Instance, info: typeof(CARDS[1]), order: number)
	local frame = Instance.new("Frame")
	frame.Name = `Card{order}`
	frame.LayoutOrder = order
	frame.BackgroundColor3 = C.PanelDark
	frame.BackgroundTransparency = 0.2
	frame.Parent = parent
	Theme.corner(frame, 14)
	Theme.stroke(frame, info.color, 2).Transparency = 0.35
	local icon = Theme.label(frame, {
		name = "Icon",
		size = UDim2.fromOffset(62, 62),
		position = UDim2.fromOffset(12, 14),
		text = info.icon,
		stroke = false,
	})
	icon.BackgroundColor3 = info.color
	icon.BackgroundTransparency = 0.75
	Theme.corner(icon, 31)
	Theme.label(frame, {
		name = "Title",
		size = UDim2.new(1, -96, 0, 26),
		position = UDim2.fromOffset(86, 14),
		text = info.title,
		color = info.color,
		align = Enum.TextXAlignment.Left,
	})
	local body = Theme.label(frame, {
		name = "Text",
		size = UDim2.new(1, -96, 0, 72),
		position = UDim2.fromOffset(86, 44),
		text = info.text,
		font = Theme.Body,
		color = C.Text,
		align = Enum.TextXAlignment.Left,
		stroke = false,
		scaled = false,
		textSize = 15,
	})
	body.TextYAlignment = Enum.TextYAlignment.Top
end

local function build()
	gui = Theme.screen("TurboHowToPlay", 40)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = rgb(0, 0, 0)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	panel = Theme.panel(gui, "HowToPlay", UDim2.fromOffset(940, 540), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 20)
	Theme.label(panel, {
		name = "Heading",
		size = UDim2.new(1, 0, 0, 46),
		text = "HOW TO PLAY",
		color = C.Gold,
	})
	Theme.label(panel, {
		name = "Subheading",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 48),
		text = "3 vs 3 CAR SOCCER - YOUR TEAM IS BLUE OR ORANGE",
		font = Theme.Caps,
		color = C.Muted,
		stroke = false,
	})

	local grid = Instance.new("Frame")
	grid.Name = "Cards"
	grid.Size = UDim2.new(1, 0, 0, 260)
	grid.Position = UDim2.fromOffset(0, 80)
	grid.BackgroundTransparency = 1
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(292, 124)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	for i, info in CARDS do
		card(grid, info, i)
	end

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.Size = UDim2.new(1, 0, 0, 78)
	controls.Position = UDim2.fromOffset(0, 352)
	controls.BackgroundTransparency = 1
	controls.Parent = panel
	for i, row in CONTROLS do
		Theme.label(controls, {
			name = `Controls{i}`,
			size = UDim2.new(1, -170, 0, 22),
			position = UDim2.fromOffset(0, (i - 1) * 25),
			text = `{row[1]}  {row[2]}`,
			font = Theme.Body,
			color = C.Muted,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
	end

	closeButton = Theme.button(panel, {
		name = "GotIt",
		size = UDim2.fromOffset(170, 56),
		position = UDim2.fromScale(1, 1),
		anchor = Vector2.new(1, 1),
		text = "GOT IT!",
		color = C.Good,
	})
	closeButton.Activated:Connect(function()
		HowToPlay.close()
	end)
	dim.Activated:Connect(function()
		HowToPlay.close()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Shows the page; `closed` runs when it's dismissed (to put the gamepad selection back).
function HowToPlay.open(closed: (() -> ())?)
	onClosed = closed
	gui.Enabled = true
	panel.Position = UDim2.fromScale(0.5, 0.57)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.53) })
		:Play()
	Theme.focus(closeButton)
end

function HowToPlay.close()
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	local callback = onClosed
	onClosed = nil
	if callback then
		callback()
	end
end

function HowToPlay.isOpen(): boolean
	return gui.Enabled
end

function HowToPlay.start()
	build()
end

return HowToPlay
