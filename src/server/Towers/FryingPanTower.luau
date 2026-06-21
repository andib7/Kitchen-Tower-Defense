-- FryingPanTower — Sear: every hit applies a burn DoT.
-- Level 3 ("Grease Fire") spreads the burn to nearby enemies too.

local BaseTower = require(script.Parent.BaseTower)

local FryingPanTower = setmetatable({}, { __index = BaseTower })
FryingPanTower.__index = FryingPanTower

function FryingPanTower.new(model: Model, ownerId: number, laneId: number)
	local self = BaseTower.new(model, "FryingPan", ownerId, laneId)
	return setmetatable(self, FryingPanTower)
end

function FryingPanTower:OnHit(enemyManager: any, target: Model, _damage: number, stats: any)
	local special = stats.special
	if not special then return end

	enemyManager.ApplyBurn(target, special.burnDps, special.burnDuration)

	if self.level >= 3 and special.spreadRadius then
		local targetRoot = target.PrimaryPart
		if targetRoot then
			local nearby = enemyManager.GetEnemiesNear(targetRoot.Position, special.spreadRadius, self.laneId, target)
			for _, enemy in nearby do
				enemyManager.ApplyBurn(enemy, special.burnDps, special.burnDuration)
			end
		end
	end
end

return FryingPanTower
