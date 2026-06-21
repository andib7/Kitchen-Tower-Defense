-- OvenTower — Always-AoE: every hit also splashes to enemies near the
-- target. Level 3 ("Well Done") adds a chance to stun the primary target.

local BaseTower = require(script.Parent.BaseTower)

local OvenTower = setmetatable({}, { __index = BaseTower })
OvenTower.__index = OvenTower

function OvenTower.new(model: Model, ownerId: number, laneId: number)
	local self = BaseTower.new(model, "Oven", ownerId, laneId)
	return setmetatable(self, OvenTower)
end

function OvenTower:OnHit(enemyManager: any, target: Model, damage: number, stats: any)
	local special = stats.special
	if not special then return end

	local targetRoot = target.PrimaryPart
	if targetRoot and special.splashRadius then
		local nearby = enemyManager.GetEnemiesNear(targetRoot.Position, special.splashRadius, self.laneId, target)
		for _, enemy in nearby do
			enemyManager.DamageEnemy(enemy, damage, self.model)
		end
	end

	if self.level >= 3 and special.stunChance and special.stunDuration then
		if math.random() <= special.stunChance then
			enemyManager.ApplyStun(target, special.stunDuration)
		end
	end
end

return OvenTower
