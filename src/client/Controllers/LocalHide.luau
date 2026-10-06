--!strict
-- Hides a car on this screen only. Goal replays and the podium show stand-in copies of the cars, so the real ones
-- step out of the picture for a moment; a demolished car is gone until it pops back in. A car can be hidden for
-- more than one of these reasons at once, and shows again only when none of them apply. Nothing here is sent to
-- the server.
--
-- Parts, name tags and lights are hidden here. Trails, flames and other effects are switched on and off every
-- frame by their own controllers, which check LocalHide.isHidden first.

local LocalHide = {}

local ATTRIBUTE = "HiddenLocally"

type Saved = { guis: { BillboardGui }, lights: { Light } }
local saved: { [Model]: Saved } = {}
local reasons: { [Model]: { [string]: boolean } } = {}

function LocalHide.isHidden(model: Instance): boolean
	return model:GetAttribute(ATTRIBUTE) == true
end

local function apply(model: Model, hidden: boolean)
	model:SetAttribute(ATTRIBUTE, hidden)
	if hidden then
		local record: Saved = { guis = {}, lights = {} }
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				table.insert(record.guis, d)
			elseif d:IsA("Light") and d.Enabled then
				d.Enabled = false
				table.insert(record.lights, d)
			end
		end
		saved[model] = record
	else
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
		local record = saved[model]
		saved[model] = nil
		if record then
			for _, gui in record.guis do
				gui.Enabled = true
			end
			for _, light in record.lights do
				light.Enabled = true
			end
		end
	end
end

-- Hides (or stops hiding) a car for one reason: "scene" (replays and the podium; the default) or "demo".
function LocalHide.set(model: Model, hidden: boolean, reason: string?)
	local why: { [string]: boolean } = reasons[model] or {}
	local key = reason or "scene"
	if hidden then
		why[key] = true
	else
		why[key] = nil
	end
	local nowHidden = next(why) ~= nil
	if nowHidden then
		reasons[model] = why
	else
		reasons[model] = nil
	end
	if nowHidden ~= LocalHide.isHidden(model) then
		apply(model, nowHidden)
	end
end

-- Hides (or shows again) every car in `folder`, for the default reason.
function LocalHide.setAll(folder: Instance, hidden: boolean)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			LocalHide.set(child, hidden)
		end
	end
end

-- The car has left the match.
function LocalHide.forget(model: Model)
	reasons[model] = nil
	saved[model] = nil
end

return LocalHide
