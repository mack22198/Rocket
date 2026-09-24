--!strict
-- The exact math shape of the arena, used to simulate the ball identically on the server and on every client.
--
-- Top view (not to scale). Blue defends the goal at -Z, Orange defends the goal at +Z.
--
--            ____[ORANGE GOAL]____
--           /                     \      <- 45 degree corner walls
--          |                       |
--          |           o           |     the field is centred on the world origin, floor at Y = 0
--          |                       |
--           \_____[BLUE GOAL]_____/
--
-- The floor meets every wall with a curved ramp (a quarter circle), so cars and the ball can ride up the walls.
-- The ramps along the end walls stop at the goal posts, and the goal is a box-shaped hole in the end wall.
-- ArenaBuilder builds real parts that match these numbers.

local ArenaShape = {}
ArenaShape.__index = ArenaShape

export type Config = {
	Width: number,
	Length: number,
	Height: number,
	CornerCut: number,
	CurveRadius: number,
	GoalWidth: number,
	GoalHeight: number,
	GoalDepth: number,
}

export type Plane = { point: Vector3, normal: Vector3 }
export type Box = { min: Vector3, max: Vector3 }
-- A curved floor-to-wall ramp: the quarter-circle fillet between the floor and a wall, extruded along the wall.
export type Ramp = {
	wallPoint: Vector3, -- a point where the wall meets the floor
	inward: Vector3, -- horizontal unit vector pointing away from the wall, into the field
	along: Vector3, -- horizontal unit vector along the wall
	from: number, -- extent along `along`, measured from wallPoint
	to: number,
	radius: number,
	-- Where this ramp meets the next wall's ramp in a 45 degree corner (nil = a free end, beside a goal).
	-- Only used to draw the ramps; the maths above is all the ball needs.
	cornerFrom: number?,
	cornerTo: number?,
}

export type Arena = typeof(setmetatable(
	{} :: {
		config: Config,
		halfWidth: number,
		halfLength: number,
		height: number,
		goalHalfWidth: number,
		goalHeight: number,
		goalDepth: number,
		planes: { Plane },
		sidePlanes: { Plane },
		boxes: { Box },
		ramps: { Ramp },
	},
	ArenaShape
))

local BIG = 1e4
local UP = Vector3.yAxis

function ArenaShape.new(config: Config): Arena
	local halfWidth = config.Width / 2
	local halfLength = config.Length / 2
	local cut = config.CornerCut
	local radius = config.CurveRadius
	local goalHalfWidth = config.GoalWidth / 2

	assert(goalHalfWidth < halfWidth - cut, "Goals must be narrower than the straight part of the end walls")
	assert(radius < config.GoalHeight, "Curve radius must be smaller than the goal height")
	-- The goal box must not poke through the corner walls.
	local goalClearance = (halfWidth - goalHalfWidth - config.GoalDepth - cut) / math.sqrt(2)
	assert(goalClearance > 0, "Goal box is too big for the corner walls")

	local planes: { Plane } = {
		{ point = Vector3.zero, normal = UP }, -- floor
		{ point = Vector3.new(0, config.Height, 0), normal = -UP }, -- ceiling
	}
	local sidePlanes: { Plane } = {}
	local function addWall(point: Vector3, normal: Vector3)
		local plane = { point = point, normal = normal }
		table.insert(planes, plane)
		table.insert(sidePlanes, plane)
	end
	addWall(Vector3.new(halfWidth, 0, 0), Vector3.new(-1, 0, 0))
	addWall(Vector3.new(-halfWidth, 0, 0), Vector3.new(1, 0, 0))
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			addWall(Vector3.new(sx * halfWidth, 0, sz * (halfLength - cut)), -Vector3.new(sx, 0, sz).Unit)
		end
	end

	-- End walls are solid blocks around the goal mouth, plus the back of the goal.
	local boxes: { Box } = {}
	for _, s in { 1, -1 } do
		local zNear = s * halfLength
		local zBack = s * (halfLength + config.GoalDepth)
		local zFar = s * BIG
		local zMin, zMax = math.min(zNear, zFar), math.max(zNear, zFar)
		table.insert(boxes, { min = Vector3.new(-BIG, -BIG, zMin), max = Vector3.new(-goalHalfWidth, BIG, zMax) })
		table.insert(boxes, { min = Vector3.new(goalHalfWidth, -BIG, zMin), max = Vector3.new(BIG, BIG, zMax) })
		table.insert(boxes, {
			min = Vector3.new(-goalHalfWidth, config.GoalHeight, zMin),
			max = Vector3.new(goalHalfWidth, BIG, zMax),
		})
		table.insert(boxes, {
			min = Vector3.new(-BIG, -BIG, math.min(zBack, zFar)),
			max = Vector3.new(BIG, BIG, math.max(zBack, zFar)),
		})
	end

	-- Ramps overlap a little where two walls meet so there's no gap in the corners.
	local overlap = radius * 0.5
	local ramps: { Ramp } = {}
	local straightHalf = halfLength - cut
	for _, sx in { 1, -1 } do
		table.insert(ramps, {
			wallPoint = Vector3.new(sx * halfWidth, 0, 0),
			inward = Vector3.new(-sx, 0, 0),
			along = Vector3.zAxis,
			from = -straightHalf - overlap,
			to = straightHalf + overlap,
			radius = radius,
			cornerFrom = -straightHalf,
			cornerTo = straightHalf,
		})
	end
	local diagonalLength = cut * math.sqrt(2)
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local a = Vector3.new(sx * halfWidth, 0, sz * (halfLength - cut))
			local b = Vector3.new(sx * (halfWidth - cut), 0, sz * halfLength)
			table.insert(ramps, {
				wallPoint = a,
				inward = -Vector3.new(sx, 0, sz).Unit,
				along = (b - a).Unit,
				from = -overlap,
				to = diagonalLength + overlap,
				radius = radius,
				cornerFrom = 0,
				cornerTo = diagonalLength,
			})
		end
	end
	local endStraightHalf = halfWidth - cut
	for _, s in { 1, -1 } do
		local wallPoint = Vector3.new(0, 0, s * halfLength)
		local inward = Vector3.new(0, 0, -s)
		table.insert(ramps, {
			wallPoint = wallPoint,
			inward = inward,
			along = Vector3.xAxis,
			from = goalHalfWidth,
			to = endStraightHalf + overlap,
			radius = radius,
			cornerTo = endStraightHalf,
		})
		table.insert(ramps, {
			wallPoint = wallPoint,
			inward = inward,
			along = Vector3.xAxis,
			from = -endStraightHalf - overlap,
			to = -goalHalfWidth,
			radius = radius,
			cornerFrom = -endStraightHalf,
		})
	end

	local self = {
		config = config,
		halfWidth = halfWidth,
		halfLength = halfLength,
		height = config.Height,
		goalHalfWidth = goalHalfWidth,
		goalHeight = config.GoalHeight,
		goalDepth = config.GoalDepth,
		planes = planes,
		sidePlanes = sidePlanes,
		boxes = boxes,
		ramps = ramps,
	}
	return setmetatable(self, ArenaShape)
end

local function planeContact(pos: Vector3, radius: number, plane: Plane): (Vector3?, number)
	local distance = (pos - plane.point):Dot(plane.normal)
	if distance < radius then
		return plane.normal, radius - distance
	end
	return nil, 0
end

local function boxContact(pos: Vector3, radius: number, box: Box): (Vector3?, number)
	local lo, hi = box.min, box.max
	local closest =
		Vector3.new(math.clamp(pos.X, lo.X, hi.X), math.clamp(pos.Y, lo.Y, hi.Y), math.clamp(pos.Z, lo.Z, hi.Z))
	local offset = pos - closest
	local distance = offset.Magnitude
	if distance >= radius then
		return nil, 0
	end
	if distance > 1e-6 then
		return offset / distance, radius - distance
	end
	-- The centre is inside the box: push out through the nearest face.
	local best = pos.X - lo.X
	local normal = Vector3.new(-1, 0, 0)
	local function consider(depth: number, n: Vector3)
		if depth < best then
			best = depth
			normal = n
		end
	end
	consider(hi.X - pos.X, Vector3.new(1, 0, 0))
	consider(pos.Y - lo.Y, Vector3.new(0, -1, 0))
	consider(hi.Y - pos.Y, Vector3.new(0, 1, 0))
	consider(pos.Z - lo.Z, Vector3.new(0, 0, -1))
	consider(hi.Z - pos.Z, Vector3.new(0, 0, 1))
	return normal, best + radius
end

local function rampContact(pos: Vector3, radius: number, ramp: Ramp): (Vector3?, number)
	local rel = pos - ramp.wallPoint
	local s = rel:Dot(ramp.along)
	local u = rel:Dot(ramp.inward) -- distance in front of the wall
	local v = rel.Y -- height above the floor
	local R = ramp.radius
	if u < 0 or v < 0 then
		return nil, 0 -- behind the wall or under the floor: the wall and floor push the ball out first
	end
	if u > R + radius or v > R + radius or s < ramp.from - radius or s > ramp.to + radius then
		return nil, 0
	end

	-- Where is the centre relative to the fillet's cross-section (the corner region outside the quarter circle)?
	local inSquare = u <= R and v <= R
	local cu, cv = u - R, v - R
	local insideFillet = false
	local filletDepth = 0 -- how deep the centre is inside the fillet (when insideFillet)
	local gapToFillet = 0 -- distance from the centre to the fillet (when not inside)
	local gu, gv = 0.7071, 0.7071 -- direction (in the u/v plane) pointing away from the fillet
	if inSquare then
		local len = math.sqrt(cu * cu + cv * cv)
		if len > R then
			insideFillet = true
			filletDepth = len - R
		else
			gapToFillet = R - len
		end
		if len > 1e-6 then
			gu, gv = -cu / len, -cv / len
		end
	else
		-- Outside the fillet's bounding square the nearest fillet points are its two lips.
		local toFloorLip = (u - R) * (u - R) + v * v
		local toWallLip = u * u + (v - R) * (v - R)
		if toFloorLip <= toWallLip then
			gapToFillet = math.sqrt(toFloorLip)
			if gapToFillet > 1e-6 then
				gu, gv = (u - R) / gapToFillet, v / gapToFillet
			end
		else
			gapToFillet = math.sqrt(toWallLip)
			if gapToFillet > 1e-6 then
				gu, gv = u / gapToFillet, (v - R) / gapToFillet
			end
		end
	end
	local sectionNormal = ramp.inward * gu + UP * gv

	local beyond = math.max(ramp.from - s, s - ramp.to) -- > 0 when past either end of the ramp
	if beyond <= 0 then
		if insideFillet then
			return sectionNormal, radius + filletDepth
		elseif inSquare and gapToFillet < radius then
			return sectionNormal, radius - gapToFillet
		end
		return nil, 0 -- the plain floor/wall planes handle everything else
	end

	-- Past the end of the ramp: the ball can bump into the ramp's flat end face (next to the goal posts).
	local endNormal = if s > ramp.to then ramp.along else -ramp.along
	if insideFillet then
		if beyond < radius then
			return endNormal, radius - beyond
		end
		return nil, 0
	end
	local distance = math.sqrt(beyond * beyond + gapToFillet * gapToFillet)
	if distance < radius and distance > 1e-6 then
		return (endNormal * beyond + sectionNormal * gapToFillet) / distance, radius - distance
	end
	return nil, 0
end

-- The single deepest contact between a sphere and the arena (nil if the sphere is free).
function ArenaShape.deepestContact(self: Arena, pos: Vector3, radius: number): (Vector3?, number)
	local bestNormal: Vector3? = nil
	local bestDepth = 0
	for _, plane in self.planes do
		local n, depth = planeContact(pos, radius, plane)
		if n and depth > bestDepth then
			bestNormal, bestDepth = n, depth
		end
	end
	for _, box in self.boxes do
		local n, depth = boxContact(pos, radius, box)
		if n and depth > bestDepth then
			bestNormal, bestDepth = n, depth
		end
	end
	for _, ramp in self.ramps do
		local n, depth = rampContact(pos, radius, ramp)
		if n and depth > bestDepth then
			bestNormal, bestDepth = n, depth
		end
	end
	return bestNormal, bestDepth
end

-- Pushes a sphere out of the arena geometry. Returns the corrected position and the last contact normal.
function ArenaShape.resolve(self: Arena, pos: Vector3, radius: number, iterations: number?): (Vector3, Vector3?)
	local lastNormal: Vector3? = nil
	for _ = 1, iterations or 4 do
		local n, depth = self:deepestContact(pos, radius)
		if not n then
			break
		end
		pos += n * depth
		lastNormal = n
	end
	return pos, lastNormal
end

-- Which goal a ball is fully inside: 1 for the goal at +Z (Orange's goal), -1 for -Z (Blue's goal), nil otherwise.
function ArenaShape.goalSide(self: Arena, pos: Vector3, radius: number): number?
	if math.abs(pos.X) > self.goalHalfWidth or pos.Y > self.goalHeight then
		return nil
	end
	if pos.Z > self.halfLength + radius then
		return 1
	elseif pos.Z < -self.halfLength - radius then
		return -1
	end
	return nil
end

-- The centre of a goal mouth, on the goal line.
function ArenaShape.goalCenter(self: Arena, side: number): Vector3
	return Vector3.new(0, self.goalHeight / 2, side * self.halfLength)
end

-- Distance from a point to the nearest wall (ignoring floor and ceiling). Used to spot wall hits.
function ArenaShape.wallDistance(self: Arena, pos: Vector3): number
	local best = math.huge
	for _, plane in self.sidePlanes do
		best = math.min(best, (pos - plane.point):Dot(plane.normal))
	end
	local inMouth = math.abs(pos.X) < self.goalHalfWidth and pos.Y < self.goalHeight
	if not inMouth then
		best = math.min(best, self.halfLength - math.abs(pos.Z))
	end
	return best
end

-- Is the point inside the playable space (field or goals), at least `margin` from every surface?
function ArenaShape.contains(self: Arena, pos: Vector3, margin: number): boolean
	local n = self:deepestContact(pos, margin)
	return n == nil
end

-- Clamps a point so it stays inside the field (not the goals), `margin` from the walls. Handy for cameras.
function ArenaShape.clampInside(self: Arena, pos: Vector3, margin: number): Vector3
	local x = math.clamp(pos.X, -self.halfWidth + margin, self.halfWidth - margin)
	local y = math.clamp(pos.Y, margin, self.height - margin)
	local z = math.clamp(pos.Z, -self.halfLength + margin, self.halfLength - margin)
	local p = Vector3.new(x, y, z)
	for _, plane in self.sidePlanes do
		local distance = (p - plane.point):Dot(plane.normal)
		if distance < margin then
			p += plane.normal * (margin - distance)
		end
	end
	return p
end

return ArenaShape
