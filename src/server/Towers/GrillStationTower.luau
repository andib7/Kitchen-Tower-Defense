-- GrillStationTower — Charred: after damage, a level-scaled chance to
-- instantly execute targets below a level-scaled remaining-health threshold.

local BaseTower = require(script.Parent.BaseTower)

local GrillStationTower = setmetatable({}, { __index = BaseTower })
GrillStationTower.__index = GrillStationTower

function GrillStationTower.new(model: Model, ownerId: number, laneId: number)
	local self = BaseTower.new(model, "GrillStation", ownerId, laneId)
	return setmetatable(self, GrillStationTower)
end

function GrillStationTower:OnHit(enemyManager: any, target: Model, _damage: number, stats: any)
	local special = stats.special
	if not special then return end

	local health = enemyManager.GetEnemyHealth(target)
	if not health or health <= 0 then return end -- the base hit already killed it

	local enemyId   = target:GetAttribute("EnemyId") :: string?
	local enemyData = enemyId and enemyManager.GetEnemyData(enemyId)
	if not enemyData then return end

	local healthPct = health / enemyData.maxHealth
	if healthPct <= special.executeThreshold and math.random() <= special.executeChance then
		enemyManager.KillEnemy(target)
	end
end

return GrillStationTower
