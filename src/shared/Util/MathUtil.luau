--!strict
-- Small math helpers shared by the server, the client and the offline tests.

local MathUtil = {}

local EPSILON = 1e-6

-- Returns v normalized, or `fallback` when v is too short to normalize safely.
function MathUtil.safeUnit(v: Vector3, fallback: Vector3): Vector3
	local magnitude = v.Magnitude
	if magnitude < EPSILON or magnitude ~= magnitude then
		return fallback
	end
	return v / magnitude
end

-- Drops the vertical component.
function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Frame-rate independent smoothing factor: how far to move toward a target this frame.
function MathUtil.expDecay(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Linear map of x from [inMin, inMax] onto [outMin, outMax], clamped to the output range.
function MathUtil.remapClamped(x: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if inMax == inMin then
		return outMax
	end
	local t = math.clamp((x - inMin) / (inMax - inMin), 0, 1)
	return outMin + (outMax - outMin) * t
end

function MathUtil.isFiniteNumber(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

function MathUtil.isFiniteVector(v: Vector3): boolean
	return MathUtil.isFiniteNumber(v.X) and MathUtil.isFiniteNumber(v.Y) and MathUtil.isFiniteNumber(v.Z)
end

function MathUtil.clampMagnitude(v: Vector3, maxMagnitude: number): Vector3
	local magnitude = v.Magnitude
	if magnitude > maxMagnitude and magnitude > EPSILON then
		return v * (maxMagnitude / magnitude)
	end
	return v
end

-- Builds a CFrame at `position` looking along `direction`, keeping `up` as close to the requested up as possible.
-- (Implemented with fromMatrix instead of CFrame.lookAt so it behaves identically in the offline test runner.)
function MathUtil.lookAlong(position: Vector3, direction: Vector3, up: Vector3?): CFrame
	local look = MathUtil.safeUnit(direction, Vector3.new(0, 0, -1))
	local upHint = up or Vector3.yAxis
	local right = look:Cross(upHint)
	if right.Magnitude < 1e-3 then
		-- Looking straight along the up hint: pick any perpendicular.
		right = look:Cross(Vector3.xAxis)
		if right.Magnitude < 1e-3 then
			right = look:Cross(Vector3.zAxis)
		end
	end
	right = right.Unit
	local realUp = right:Cross(look)
	return CFrame.fromMatrix(position, right, realUp)
end

-- A CFrame at `position` that only keeps the heading (yaw) of `look`.
function MathUtil.uprightFacing(position: Vector3, look: Vector3): CFrame
	local flatLook = MathUtil.safeUnit(MathUtil.flat(look), Vector3.new(0, 0, -1))
	return MathUtil.lookAlong(position, flatLook, Vector3.yAxis)
end

return MathUtil
