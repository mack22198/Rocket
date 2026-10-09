--!strict
-- The maths behind goal replays: how long a replay lasts and which moment of the clip to show when. The last
-- second before the goal plays in extra-slow motion, so the shot itself gets the drama.
-- (The recording and playback live in the client's ReplayController.)

local Replay = {}

Replay.ClipLength = 3 -- seconds of play shown before the goal
Replay.StartDelay = 1.4 -- the goal explosion plays first
Replay.SlowPart = 1 -- the final second of the clip...
Replay.SlowRate = 0.45 -- ...plays at this speed
Replay.FastRate = 0.9 -- and everything before it at this speed

export type Frame = {
	t: number,
	ball: Vector3,
	cars: { [any]: CFrame },
	dashing: { [any]: boolean },
}

-- How many real seconds a clip of `clipLength` seconds takes to play.
function Replay.duration(clipLength: number): number
	local slow = math.clamp(Replay.SlowPart, 0, clipLength)
	return (clipLength - slow) / Replay.FastRate + slow / Replay.SlowRate
end

-- Which moment of the clip (0 .. clipLength) to show, `elapsed` real seconds into the replay.
function Replay.clipTime(elapsed: number, clipLength: number): number
	local slow = math.clamp(Replay.SlowPart, 0, clipLength)
	local fastPart = clipLength - slow
	local fastDuration = fastPart / Replay.FastRate
	if elapsed <= fastDuration then
		return math.max(0, elapsed) * Replay.FastRate
	end
	return math.min(clipLength, fastPart + (elapsed - fastDuration) * Replay.SlowRate)
end

-- The two recorded frames either side of time `t` (in the frames' own clock), and how far between them `t`
-- is (0 = the first, 1 = the second).
function Replay.sample(frames: { Frame }, t: number): (Frame, Frame, number)
	if t <= frames[1].t then
		return frames[1], frames[1], 0
	end
	local last = frames[#frames]
	if t >= last.t then
		return last, last, 0
	end
	-- Binary search for the last frame at or before t.
	local low, high = 1, #frames
	while high - low > 1 do
		local middle = (low + high) // 2
		if frames[middle].t <= t then
			low = middle
		else
			high = middle
		end
	end
	local a, b = frames[low], frames[high]
	local gap = b.t - a.t
	return a, b, if gap > 1e-6 then (t - a.t) / gap else 0
end

-- The last `length` seconds of a recording (a new list; the frames themselves are shared).
function Replay.trim(frames: { Frame }, length: number): { Frame }
	local clip: { Frame } = {}
	local last = frames[#frames]
	if not last then
		return clip
	end
	local from = last.t - length
	for i, frame in frames do
		-- Keep one frame from before the cut so the clip starts exactly on time.
		local nextFrame = frames[i + 1]
		if frame.t >= from or (nextFrame and nextFrame.t > from) then
			table.insert(clip, frame)
		end
	end
	return clip
end

return Replay
