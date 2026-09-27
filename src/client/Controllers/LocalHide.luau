--!strict
-- Hides a car on this screen only (goal replays and the podium show stand-in copies of the cars, so the real
-- ones step out of the picture for a moment). Nothing here is sent to the server.
--
-- Parts, name tags and lights are hidden here. Trails, flames and other effects are switched on and off every
-- frame by their own controllers, which check LocalHide.isHidden first.

local LocalHide = {}

local ATTRIBUTE = "HiddenLocally"

type Saved = { guis: { BillboardGui }, lights: { Light } }
local saved: { [Model]: Saved } = {}

function LocalHide.isHidden(model: Instance): boolean
	return model:GetAttribute(ATTRIBUTE) == true
end

function LocalHide.set(model: Model, hidden: boolean)
	if hidden == LocalHide.isHidden(model) then
		return
	end
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

-- Hides (or shows again) every car in `folder`.
function LocalHide.setAll(folder: Instance, hidden: boolean)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			LocalHide.set(child, hidden)
		end
	end
end

return LocalHide
