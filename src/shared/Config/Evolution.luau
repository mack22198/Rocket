--!strict
-- Car evolution: every car earns XP while you drive it (as much XP as the Scrap you win), and at set XP
-- totals it can EVOLVE into its next look. It's earned by playing, never bought, and it only changes how the
-- car looks. Players can switch back to any look they've already unlocked.

local CarCatalog = require(script.Parent.CarCatalog)
local GameConfig = require(script.Parent.GameConfig)

local Evolution = {}

export type Progress = {
	stage: number, -- the stage the car has evolved to
	maxStage: number,
	xp: number,
	nextStage: number?, -- nil when fully evolved
	nextName: string?,
	xpForNext: number, -- total XP the next stage needs (0 when fully evolved)
	fraction: number, -- 0..1 progress from this stage toward the next
	ready: boolean, -- has enough XP to evolve right now
}

local cfg = GameConfig.Evolution

-- Total XP a car needs to reach `stage`.
function Evolution.xpForStage(stage: number): number
	return cfg.Xp[math.clamp(stage, 1, cfg.Stages)] or 0
end

-- The highest stage a car's XP allows (evolving still needs a press of the EVOLVE button).
function Evolution.stageAllowed(xp: number): number
	local stage = 1
	for s = 2, cfg.Stages do
		if xp >= Evolution.xpForStage(s) then
			stage = s
		end
	end
	return stage
end

function Evolution.progress(def: CarCatalog.CarDef, xp: number, stage: number): Progress
	local maxStage = cfg.Stages
	stage = math.clamp(stage, 1, maxStage)
	if stage >= maxStage then
		return {
			stage = stage,
			maxStage = maxStage,
			xp = xp,
			nextStage = nil,
			nextName = nil,
			xpForNext = 0,
			fraction = 1,
			ready = false,
		}
	end
	local from = Evolution.xpForStage(stage)
	local to = Evolution.xpForStage(stage + 1)
	return {
		stage = stage,
		maxStage = maxStage,
		xp = xp,
		nextStage = stage + 1,
		nextName = CarCatalog.stageName(def, stage + 1),
		xpForNext = to,
		fraction = math.clamp((xp - from) / math.max(1, to - from), 0, 1),
		ready = xp >= to,
	}
end

-- A random stage for a bot's car, weighted so evolved cars show up now and then.
function Evolution.botStage(roll: number): number
	local total = 0
	for _, weight in cfg.BotStageWeights do
		total += weight
	end
	local pick = roll * total
	for stage, weight in cfg.BotStageWeights do
		pick -= weight
		if pick < 0 then
			return stage
		end
	end
	return 1
end

return Evolution
