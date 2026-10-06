--!strict
-- Easy steering for touch screens: push the stick toward where you want to go on the screen and the car drives
-- that way - it turns toward the direction you're pointing, or backs up if you pull the stick back toward
-- yourself while that's behind the car. (In the air the stick tips the car as usual; see InputController.)

local EasySteer = {}

local REVERSE_ANGLE = math.rad(145) -- pulling back within 35° of straight behind the car backs it up
local TURN_GAIN = 2.2 -- how hard it steers for each radian it's pointing away from where you want to go

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else nil
end

-- (throttle, steer) for a stick (x = right, y = up the screen, length up to 1), for a car at `car` seen through
-- a camera at `camera`. Steer is positive to the right.
function EasySteer.input(stick: Vector2, car: CFrame, camera: CFrame): (number, number)
	local amount = math.min(stick.Magnitude, 1)
	local look = flat(car.LookVector)
	local cameraLook = flat(camera.LookVector)
	if amount < 0.05 or not look or not cameraLook then
		return 0, 0
	end
	local cameraRight = cameraLook:Cross(Vector3.yAxis)
	local wanted = (cameraRight * stick.X + cameraLook * stick.Y).Unit
	local angle = math.atan2(look:Cross(wanted).Y, look:Dot(wanted)) -- positive: it's to the left
	if math.abs(angle) > REVERSE_ANGLE and stick.Y < 0 then
		return -amount, 0
	end
	return amount, math.clamp(-angle * TURN_GAIN, -1, 1)
end

return EasySteer
