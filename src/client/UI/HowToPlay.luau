--!strict
-- "How to play": six numbered cards that explain the whole game in a few words, plus the controls for
-- keyboard, gamepad and touch. Opened from the main menu and the in-match menu.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local HowToPlay = {}

local C = Theme.Colors
local rgb = Color3.fromRGB

local CARDS = {
	{
		title = "SCORE GOALS",
		text = "Hold W and your car helps you hit the ball at the other team's goal. Most goals at 0:00 wins!",
		color = C.Good,
	},
	{
		title = "BOOST AND JUMP",
		text = "Boost to go super fast. Ball in the air? Jump at it, then jump again to flip into it. Smash cars at full boost - POOF!",
		color = C.Gold,
	},
	{
		title = "ITEM BOXES",
		text = "Drive through a ? box to grab an item, like a Magnet or Freeze Ray. Losing? You get better ones!",
		color = C.Sky,
	},
	{
		title = "CAR POWERS",
		text = "Every car has its own power, like Cheese Trap or Ground Pound. It charges back up after each use!",
		color = C.Shop,
	},
	{
		title = "MEGA SHOT",
		text = "Touching the ball fills your Mega meter. When it's full, press Mega and your next hit blasts the ball!",
		color = C.Mega,
	},
	{
		title = "UNLOCK AND EVOLVE",
		text = "Matches earn Scrap for new cars and season rewards (more with friends!). Drive a car to make it evolve!",
		color = C.Evolve,
	},
}

local CONTROLS = {
	{ "KEYBOARD", "W S drive, A D steer, SPACE jump, SHIFT boost, R item, G power, F mega, T chat, M menu" },
	{ "GAMEPAD", "RT LT drive, A jump, B boost, RB item, LB power, X mega, D-pad chat, Y cam, VIEW menu" },
	{ "TOUCH", "Drag toward where you want to go, then JUMP, BOOST, ITEM and POWER. Mega Shot arms itself!" },
}

local gui: ScreenGui
local panel: Frame
local closeButton: TextButton
local onClosed: (() -> ())? = nil

local function card(parent: Instance, info: typeof(CARDS[1]), order: number)
	local frame = Theme.well(parent, `Card{order}`, UDim2.new(), UDim2.new())
	frame.LayoutOrder = order
	local number = Theme.heading(frame, {
		name = "Number",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.fromOffset(14, 14),
		text = tostring(order),
		color = if Theme.isLight(info.color) then C.Ink else C.Text,
		textSize = 28,
	})
	number.BackgroundColor3 = info.color
	number.BackgroundTransparency = 0
	Theme.corner(number, 22)
	Theme.stroke(number, C.Ink, 3)
	Theme.label(frame, {
		name = "Title",
		size = UDim2.new(1, -86, 0, 22),
		position = UDim2.fromOffset(72, 14),
		text = info.title,
		textSize = 18,
		align = Enum.TextXAlignment.Left,
	})
	local body = Theme.label(frame, {
		name = "Text",
		size = UDim2.new(1, -86, 0, 74),
		position = UDim2.fromOffset(72, 40),
		text = info.text,
		font = Theme.Body,
		color = C.InkMuted,
		align = Enum.TextXAlignment.Left,
		scaled = false,
		textSize = 14,
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
	dim.BackgroundColor3 = rgb(6, 8, 18)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	panel = Theme.card(gui, "HowToPlay", UDim2.fromOffset(940, 556), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 24)
	Theme.heading(panel, {
		name = "Heading",
		size = UDim2.new(1, 0, 0, 44),
		text = "HOW TO PLAY",
		textSize = 44,
		align = Enum.TextXAlignment.Left,
	})
	Theme.label(panel, {
		name = "Subheading",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(2, 48),
		text = "Three against three. Your team is blue or orange.",
		font = Theme.Body,
		color = C.InkMuted,
		textSize = 16,
		align = Enum.TextXAlignment.Left,
	})

	local grid = Instance.new("Frame")
	grid.Name = "Cards"
	grid.Size = UDim2.new(1, 0, 0, 268)
	grid.Position = UDim2.fromOffset(0, 84)
	grid.BackgroundTransparency = 1
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(289, 126)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid
	for i, info in CARDS do
		card(grid, info, i)
	end

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.Size = UDim2.new(1, -200, 0, 96)
	controls.Position = UDim2.fromOffset(0, 372)
	controls.BackgroundTransparency = 1
	controls.Parent = panel
	for i, row in CONTROLS do
		local y = (i - 1) * 32
		Theme.pill(controls, {
			name = `Device{i}`,
			size = UDim2.fromOffset(96, 24),
			position = UDim2.fromOffset(0, y),
			text = row[1],
		})
		Theme.label(controls, {
			name = `Controls{i}`,
			size = UDim2.new(1, -110, 0, 24),
			position = UDim2.fromOffset(110, y),
			text = row[2],
			font = Theme.Body,
			textSize = 13,
			align = Enum.TextXAlignment.Left,
		})
	end

	closeButton = Theme.button(panel, {
		name = "GotIt",
		size = UDim2.fromOffset(180, 62),
		position = UDim2.fromScale(1, 1),
		anchor = Vector2.new(1, 1),
		text = "GOT IT!",
		textSize = 30,
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
