--!strict
-- The garage: every car with a spinning 3D preview, its strengths and weaknesses, and a clear price.
-- Unlock with Scrap, equip anything you own. Changes apply from your next match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.Config.CarCatalog)
local CarModelBuilder = require(Shared.Cars.CarModelBuilder)
local Remotes = require(Shared.Net.Remotes)

local PlayerDataClient = require(script.Parent.Parent.Controllers.PlayerDataClient)
local Theme = require(script.Parent.Theme)

local Garage = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

type Card = {
	def: CarCatalog.CarDef,
	frame: Frame,
	status: TextLabel,
	action: TextButton,
	model: Model,
}

local gui: ScreenGui
local scrapLabel: TextLabel
local toast: TextLabel
local cards: { Card } = {}
local busy = false
local spin = 0

local STAT_ROWS = {
	{ key = "Speed", label = "Speed" },
	{ key = "Acceleration", label = "Accel" },
	{ key = "Handling", label = "Turning" },
	{ key = "Weight", label = "Weight" },
	{ key = "BumpPower", label = "Bump" },
}

local function showToast(text: string, good: boolean)
	toast.Text = text
	toast.TextColor3 = if good then C.Good else C.Bad
	toast.TextTransparency = 0
	toast.Visible = true
	task.delay(2.5, function()
		if toast.Text == text then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

local function refresh()
	local data = PlayerDataClient.get()
	scrapLabel.Text = `🔩 {Theme.formatNumber(data.scrap)} Scrap`
	for _, card in cards do
		local owned = data.owned[card.def.Id] == true
		local equipped = data.equipped == card.def.Id
		if equipped then
			card.status.Text = "✅ EQUIPPED"
			card.status.TextColor3 = C.Good
			card.action.Text = "EQUIPPED"
			card.action.BackgroundColor3 = C.PanelLight
			card.action.TextColor3 = C.Muted
			card.action.AutoButtonColor = false
		elseif owned then
			card.status.Text = "OWNED"
			card.status.TextColor3 = C.Text
			card.action.Text = "EQUIP"
			card.action.BackgroundColor3 = C.Good
			card.action.TextColor3 = Color3.fromRGB(10, 40, 20)
			card.action.AutoButtonColor = true
		else
			local canAfford = data.scrap >= card.def.Price
			card.status.Text = if canAfford
				then `🔩 {Theme.formatNumber(card.def.Price)} - you can afford it!`
				else `🔩 {Theme.formatNumber(data.scrap)} / {Theme.formatNumber(card.def.Price)}`
			card.status.TextColor3 = if canAfford then C.Gold else C.Muted
			card.action.Text = if canAfford then "UNLOCK" else "LOCKED"
			card.action.BackgroundColor3 = if canAfford then C.Gold else C.PanelLight
			card.action.TextColor3 = if canAfford then Color3.fromRGB(40, 30, 10) else C.Muted
			card.action.AutoButtonColor = canAfford
		end
	end
end

local function request(action: string, def: CarCatalog.CarDef)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.Garage:InvokeServer(action, def.Id)
	end)
	busy = false
	if ok and type(result) == "table" then
		showToast(tostring(result.message), result.ok == true)
	else
		showToast("Couldn't reach the garage. Try again!", false)
	end
end

local function buildCard(parent: Instance, def: CarCatalog.CarDef, order: number): Card
	local rarity = CarCatalog.Rarities[def.Rarity]
	local frame = Instance.new("Frame")
	frame.Name = def.Id
	frame.LayoutOrder = order
	frame.BackgroundColor3 = C.PanelLight
	frame.Parent = parent
	Theme.corner(frame, 12)
	Theme.stroke(frame, rarity.Color, 3)

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -16, 0, 110)
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.BackgroundColor3 = C.PanelDark
	viewport.Ambient = Color3.fromRGB(170, 170, 190)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = frame
	Theme.corner(viewport, 10)
	local model = CarModelBuilder.build(def, { preview = true })
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 7, 15), Vector3.new(0, 0.5, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	Theme.label(frame, {
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.fromOffset(8, 122),
		text = `{def.Emoji} {def.DisplayName}`,
	})
	Theme.label(frame, {
		size = UDim2.new(1, -16, 0, 18),
		position = UDim2.fromOffset(8, 148),
		text = `{string.upper(def.Rarity)} - {def.Tagline}`,
		font = Theme.Body,
		color = rarity.Color,
		stroke = false,
	})

	for i, statRow in STAT_ROWS do
		local value = (def.Stats :: any)[statRow.key] :: number
		local y = 168 + (i - 1) * 16
		Theme.label(frame, {
			size = UDim2.new(0.34, 0, 0, 14),
			position = UDim2.fromOffset(10, y),
			text = statRow.label,
			font = Theme.Body,
			color = C.Muted,
			align = Enum.TextXAlignment.Left,
			stroke = false,
		})
		local back = Instance.new("Frame")
		back.Size = UDim2.new(0.6, -12, 0, 8)
		back.Position = UDim2.new(0.38, 0, 0, y + 3)
		back.BackgroundColor3 = C.PanelDark
		back.Parent = frame
		Theme.corner(back, 4)
		local fill = Instance.new("Frame")
		-- 0.7 .. 1.4 maps to a mostly-full bar so every car looks decent at something.
		fill.Size = UDim2.fromScale(math.clamp((value - 0.6) / 0.8, 0.05, 1), 1)
		fill.BackgroundColor3 = if value > 1.001 then C.Good elseif value < 0.999 then C.Bad else C.Gold
		fill.Parent = back
		Theme.corner(fill, 4)
	end

	local status = Theme.label(frame, {
		size = UDim2.new(1, -16, 0, 18),
		position = UDim2.new(0, 8, 1, -62),
		text = "",
		font = Theme.Body,
		stroke = false,
	})
	local action = Theme.button(frame, {
		size = UDim2.new(1, -16, 0, 36),
		position = UDim2.new(0, 8, 1, -42),
		text = "",
	})
	local card: Card = { def = def, frame = frame, status = status, action = action, model = model }
	action.Activated:Connect(function()
		local data = PlayerDataClient.get()
		if data.equipped == def.Id then
			return
		elseif data.owned[def.Id] then
			request("equip", def)
		elseif data.scrap >= def.Price then
			request("unlock", def)
		else
			showToast(`You need {Theme.formatNumber(def.Price - data.scrap)} more Scrap. Keep playing!`, false)
		end
	end)
	return card
end

local function build()
	gui = Theme.screen("TurboGarage", 12)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui

	local panel =
		Theme.panel(gui, "Garage", UDim2.fromOffset(900, 600), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	Theme.scaled(panel)
	Theme.padding(panel, 16)
	Theme.label(panel, { size = UDim2.new(0.5, 0, 0, 48), text = "🚗 GARAGE", align = Enum.TextXAlignment.Left })
	scrapLabel = Theme.label(panel, {
		size = UDim2.new(0.4, 0, 0, 40),
		position = UDim2.new(0.5, 0, 0, 4),
		text = "",
		color = C.Scrap,
		align = Enum.TextXAlignment.Right,
	})
	local close = Theme.button(panel, {
		size = UDim2.fromOffset(44, 44),
		position = UDim2.fromScale(1, 0),
		anchor = Vector2.new(1, 0),
		text = "X",
		color = C.Bad,
		textColor = C.Text,
	})
	close.Activated:Connect(function()
		Garage.close()
	end)
	Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 20),
		position = UDim2.fromOffset(0, 50),
		text = "Earn Scrap every match. Every car is good at something - rarer just means flashier!",
		font = Theme.Body,
		color = C.Muted,
		stroke = false,
	})

	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.new(1, 0, 1, -110)
	scroller.Position = UDim2.fromOffset(0, 76)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 8
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(205, 330)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller

	for i, def in CarCatalog.ordered() do
		table.insert(cards, buildCard(scroller, def, i))
	end

	toast = Theme.label(panel, {
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.new(0, 0, 1, -28),
		text = "",
	})
	toast.Visible = false

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function Garage.open()
	refresh()
	gui.Enabled = true
end

function Garage.close()
	gui.Enabled = false
end

function Garage.isOpen(): boolean
	return gui.Enabled
end

function Garage.start()
	build()
	refresh()
	PlayerDataClient.Changed:Connect(refresh)
	RunService.RenderStepped:Connect(function(dt: number)
		if not gui.Enabled then
			return
		end
		spin += dt * 0.8
		for _, card in cards do
			card.model:PivotTo(CFrame.Angles(0, spin, 0))
		end
	end)
end

return Garage
