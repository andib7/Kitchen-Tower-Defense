-- BlenderTower — Purée: every hit slows the target. Level 3 ("Deep Purée")
-- applies a much stronger slow every 4th hit (per-tower hit counter).

local BaseTower = require(script.Parent.BaseTower)

local BlenderTower = setmetatable({}, { __index = BaseTower })
BlenderTower.__index = BlenderTower

function BlenderTower.new(model: Model, ownerId: number, laneId: number)
	local self = BaseTower.new(model, "Blender", ownerId, laneId)
	self = setmetatable(self, BlenderTower)
	self.hitCount = 0
	return self
end

function BlenderTower:OnHit(enemyManager: any, target: Model, _damage: number, stats: any)
	local special = stats.special
	if not special then return end

	self.hitCount += 1

	if self.level >= 3 and special.deepPureeEvery and self.hitCount % special.deepPureeEvery == 0 then
		enemyManager.ApplySlow(target, special.deepPureeMultiplier, special.deepPureeDuration)
	else
		enemyManager.ApplySlow(target, special.slowMultiplier, special.slowDuration)
	end
end

return BlenderTower
