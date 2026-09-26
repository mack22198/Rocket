--!strict
-- A quick fade through black, used when switching between the menus and the stadium (and when the game first
-- opens, so the showroom fades in instead of popping up half-built).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Transition = {}

local FADE_OUT = 0.22
local HOLD = 0.12
local FADE_IN = 0.45

local cover: Frame
local token = 0

local function fadeIn(mine: number)
	TweenService:Create(cover, TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(FADE_IN + 0.02, function()
		if mine == token then
			cover.Visible = false
		end
	end)
end

-- Fades to black, calls `swap` while the screen is covered, then fades back in.
function Transition.fade(swap: () -> ())
	token += 1
	local mine = token
	cover.Visible = true
	TweenService:Create(cover, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 0,
	}):Play()
	task.delay(FADE_OUT + 0.02, function()
		-- Whatever happens while the screen is covered, never leave the player staring at black.
		local ok, err = pcall(function()
			swap()
		end)
		if not ok then
			warn(`[Turbo Ball] Screen change failed: {err}`)
		end
		task.wait(HOLD)
		if mine == token then
			fadeIn(mine)
		end
	end)
end

-- Fades in from the black screen the game starts on.
function Transition.reveal()
	token += 1
	fadeIn(token)
end

function Transition.start()
	local gui = Theme.screen("TurboTransition", 100)
	cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.fromRGB(4, 5, 10)
	cover.BackgroundTransparency = 0
	cover.BorderSizePixel = 0
	cover.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return Transition
