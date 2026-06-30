-- BaseTower
-- Parent "class" for placed tower instances. Owns targeting, cooldown,
-- mutation-aware stat computation, and the attack loop. Subclasses override
-- :OnHit() to give each tower type a distinct on-hit ability — see
-- FryingPanTower / OvenTower / BlenderTower / GrillStationTower.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local TowerCatalog      = require(Shared.TowerCatalog)
local Network           = require(Shared.Network)

type TowerData      = Types.TowerData
type TowerLevelData = Types.TowerLevelData
type Zone            = Types.Zone

-- Lazy requires: Towers/ is a sibling of Managers/ under src/server, both
-- synced under the single ServerScriptService.Server $path.
local function getMutation() return require(script.Parent.Parent.Managers.MutationManager) end
local function getMap()      return require(script.Parent.Parent.Managers.MapManager)      end

local BaseTower = {}
BaseTower.__index = BaseTower

export type EffectiveStats = {
	damage:   number,
	range:    number,
	fireRate: number,
	special:  { [string]: number }?,
}

-- Construct a new tower instance wrapping an already-placed Model.
-- Subclasses call this via BaseTower.new(...) then re-apply their own
-- metatable on top (see FryingPanTower.new for the pattern).
function BaseTower.new(model: Model, towerId: string, ownerId: number, laneId: number)
	local self = setmetatable({}, BaseTower)
	self.model    = model
	self.towerId  = towerId
	self.ownerId  = ownerId
	self.laneId   = laneId
	self.level    = 1
	self.cooldown = 0
	return self
end

-- ── Data ──────────────────────────────────────────────────────────────────────

-- Returns the static TowerCatalog entry for this tower's type.
function BaseTower:GetCatalogData(): TowerData
	return TowerCatalog.Towers[self.towerId]
end

-- Returns this tower's current-level stat block, falling back to the
-- catalog's top-level stats if no `levels` table is defined.
function BaseTower:GetLevelData(): TowerLevelData
	local data = self:GetCatalogData()
	local levelData = data.levels and data.levels[self.level]
	if levelData then return levelData end
	return { damage = data.damage, range = data.range, fireRate = data.fireRate, special = nil }
end

-- Set this tower's level and stamp the Level Attribute clients read.
function BaseTower:SetLevel(level: number)
	self.level = level
	self.model:SetAttribute("Level", level)
end

-- Compute this tower's damage/range/fireRate after mutation modifiers
-- that don't depend on a specific target (global bonuses + per-instance
-- tower Attributes). Target-dependent bonuses (MergeAmplifier) are applied
-- separately in :Update once a target is known.
function BaseTower:GetEffectiveStats(): EffectiveStats
	local catalogData = self:GetCatalogData()
	local levelData    = self:GetLevelData()
	local mutation     = getMutation()

	local damage   = levelData.damage
	local range    = levelData.range
	local fireRate = levelData.fireRate

	if mutation.IsMutationUnlocked("SharpKnives") then
		damage *= 1.10
	end
	if mutation.IsMutationUnlocked("ChefsMasterRecipe") then
		damage   *= 1.20
		fireRate *= 1.20
	end
	if catalogData.chefClassBonus == "Saucier" and mutation.IsMutationUnlocked("DoubleSauce") then
		fireRate *= 1.20
	end
	if self.model:GetAttribute("Mutation_CrispyCrust") then
		range *= 1.15
	end

	return {
		damage   = damage,
		range    = range,
		fireRate = fireRate,
		special  = levelData.special,
	}
end

-- ── Targeting ─────────────────────────────────────────────────────────────────

-- Default targeting: nearest enemy within range. Subclasses may override
-- for different priorities (e.g. lowest health, most-clustered).
function BaseTower:FindTarget(enemies: { Model }, range: number): Model?
	local root = self.model.PrimaryPart
	if not root then return nil end

	local closest, closestDist = nil, math.huge
	for _, enemy in enemies do
		local enemyRoot = enemy.PrimaryPart
		if not enemyRoot then continue end
		local dist = (enemyRoot.Position - root.Position).Magnitude
		if dist <= range and dist < closestDist then
			closest, closestDist = enemy, dist
		end
	end
	return closest
end

local function isInZone(position: Vector3, zone: Zone?): boolean
	if not zone then return false end
	local half = zone.size / 2
	local diff = position - zone.center
	return math.abs(diff.X) <= half.X and math.abs(diff.Y) <= half.Y and math.abs(diff.Z) <= half.Z
end

-- ── Attack loop ───────────────────────────────────────────────────────────────

-- Called once per Heartbeat by TowerManager.UpdateTowers. Ticks cooldown,
-- finds a target, deals damage (with the merge-zone bonus if applicable),
-- then hands off to the subclass's :OnHit for its signature ability.
function BaseTower:Update(dt: number, enemyManager: any)
	self.cooldown -= dt
	if self.cooldown > 0 then return end

	local stats = self:GetEffectiveStats()
	local enemies = enemyManager.GetActiveEnemies(self.laneId)
	local target  = self:FindTarget(enemies, stats.range)
	if not target then return end

	local damage = stats.damage
	local mutation = getMutation()
	if mutation.IsMutationUnlocked("MergeAmplifier") then
		local targetRoot = target.PrimaryPart
		if targetRoot and isInZone(targetRoot.Position, getMap().GetMergeZone()) then
			damage *= 1.25
		end
	end

	local targetRoot = target.PrimaryPart
	if targetRoot then
		Network.TowerFired:FireAllClients(self.model, targetRoot.Position)
	end

	enemyManager.DamageEnemy(target, damage, self.model)
	self:OnHit(enemyManager, target, damage, stats)
	self.cooldown = 1 / stats.fireRate
end

-- Subclass hook fired after the base hit lands. No-op by default.
function BaseTower:OnHit(_enemyManager: any, _target: Model, _damage: number, _stats: EffectiveStats)
end

return BaseTower
