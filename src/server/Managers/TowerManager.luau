-- TowerManager
-- Handles tower placement (with cost / lane-ownership validation), upgrades,
-- sells, and the per-frame attack loop.  EconomyManager and MapManager are
-- lazy-required inside functions to avoid a circular dependency at load time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Constants         = require(Shared.Constants)
local Network           = require(Shared.Network)
local TowerCatalog      = require(Shared.TowerCatalog)

type TowerData = Types.TowerData

local TowerManager = {}

-- ── Lazy dependencies ─────────────────────────────────────────────────────────

local function getEconomy() return require(script.Parent.EconomyManager) end
local function getMap()     return require(script.Parent.MapManager)     end

-- Tower stats and placeholder colors live in the shared TowerCatalog so the
-- client shop UI reads the exact same data — see src/shared/TowerCatalog.luau.
local CATALOG:      { [string]: TowerData } = TowerCatalog.Towers
local TOWER_COLORS: { [string]: Color3 }    = TowerCatalog.Colors

-- ── Active tower state ────────────────────────────────────────────────────────

type TowerRecord = {
	model:   Model,
	data:    TowerData,
	level:   number,
	ownerId: number,
	cooldown: number, -- seconds until next attack
}

-- _placed[laneId] = { TowerRecord, ... }
local _placed: { [number]: { TowerRecord } } = {}

--[[
	Build a simple colored block tower body.
	TODO: Replace with model:Clone() from ReplicatedStorage.Towers[towerId].
]]
local function buildTowerModel(towerId: string): Model
	local model = Instance.new("Model")
	model.Name = towerId

	local body = Instance.new("Part")
	body.Name       = "Body"
	body.Size       = Vector3.new(3, 3, 3)
	body.Anchored   = true
	body.CanCollide = true
	body.Color      = TOWER_COLORS[towerId] or Color3.fromRGB(150, 150, 150)
	body.Material   = Enum.Material.Metal
	body.Parent     = model

	model.PrimaryPart = body
	return model
end

local function getLaneTowers(laneId: number): { TowerRecord }
	if not _placed[laneId] then
		_placed[laneId] = {}
	end
	return _placed[laneId]
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function TowerManager.Initialize()
	-- Nothing to initialize; tables are populated lazily on first placement.
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns the static TowerData for a tower type id, or nil if unknown.
function TowerManager.GetTowerData(towerId: string): TowerData?
	return CATALOG[towerId]
end

-- Returns the array of TowerRecords for all towers on a lane.
function TowerManager.GetPlacedTowers(laneId: number): { TowerRecord }
	return getLaneTowers(laneId)
end

-- ── Placement ─────────────────────────────────────────────────────────────────

--[[
	Attempt to place a tower on laneId at position.
	Validates: towerId exists, player owns the lane, tower cap not reached,
	and the player can afford it.
	Returns true on success.
]]
function TowerManager.PlaceTower(
	player:   Player,
	towerId:  string,
	laneId:   number,
	position: Vector3
): boolean
	local data = CATALOG[towerId]
	if not data then return false end

	if getMap().GetPlayerLane(player) ~= laneId then return false end

	local laneTowers = getLaneTowers(laneId)
	if #laneTowers >= Constants.MAX_TOWERS_PER_LANE then return false end

	if not getEconomy().SpendCoins(player, laneId, data.cost) then return false end

	local model = buildTowerModel(towerId)
	model:SetAttribute("TowerId", towerId)
	model:SetAttribute("Level",   1)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 1.5, 0))) -- sit on top of the ground hit point
	model.Parent = workspace

	table.insert(laneTowers, {
		model    = model,
		data     = data,
		level    = 1,
		ownerId  = player.UserId,
		cooldown = 0,
	})

	Network.TowerPlaced:FireAllClients(towerId, laneId, position, model)
	return true
end

-- ── Upgrade ───────────────────────────────────────────────────────────────────

--[[
	Upgrade a tower to the next level, charging upgradeCost from the lane wallet.
	Returns true on success.
]]
function TowerManager.UpgradeTower(player: Player, tower: Model): boolean
	local laneId = getMap().GetPlayerLane(player)
	if not laneId then return false end

	for _, rec in getLaneTowers(laneId) do
		if rec.model == tower and rec.ownerId == player.UserId then
			if rec.level >= rec.data.maxLevel then return false end
			if not getEconomy().SpendCoins(player, laneId, rec.data.upgradeCost) then
				return false
			end
			rec.level += 1
			tower:SetAttribute("Level", rec.level)
			-- TODO: Apply visual upgrade via a skin change or level indicator
			return true
		end
	end
	return false
end

-- ── Sell ─────────────────────────────────────────────────────────────────────

--[[
	Sell a tower and refund SELL_REFUND_RATE × total spent to the lane wallet.
	Total spent = cost + (level - 1) × upgradeCost.
]]
function TowerManager.SellTower(player: Player, tower: Model)
	local laneId = getMap().GetPlayerLane(player)
	if not laneId then return end

	local laneTowers = getLaneTowers(laneId)
	for i, rec in laneTowers do
		if rec.model == tower and rec.ownerId == player.UserId then
			local totalSpent = rec.data.cost + (rec.level - 1) * rec.data.upgradeCost
			local refund     = math.floor(totalSpent * Constants.SELL_REFUND_RATE)
			getEconomy().AddCoins(player, laneId, refund)
			table.remove(laneTowers, i)
			tower:Destroy()
			Network.TowerSold:FireAllClients(tower, laneId)
			return
		end
	end
end

-- ── Per-frame attack loop ─────────────────────────────────────────────────────

--[[
	Tick every tower's cooldown and fire at the nearest enemy in range.
	enemyManager is passed in (not required at module level) to keep the
	dependency graph acyclic.

	Call this from a RunService.Heartbeat connection in init.server.luau:
	    RunService.Heartbeat:Connect(function(dt)
	        TowerManager.UpdateTowers(dt, EnemyManager)
	    end)
]]
function TowerManager.UpdateTowers(dt: number, enemyManager: any)
	for laneId, records in _placed do
		local enemies = enemyManager.GetActiveEnemies(laneId)
		for _, rec in records do
			rec.cooldown -= dt
			if rec.cooldown > 0 then continue end

			-- Find the closest enemy within range
			local root   = rec.model.PrimaryPart
			local range  = rec.data.range * (1 + (rec.level - 1) * 0.15) -- +15% range per level
			local damage = rec.data.damage * (1 + (rec.level - 1) * 0.25) -- +25% damage per level

			local closest, closestDist = nil, math.huge
			for _, enemy in enemies do
				local ep = enemy.PrimaryPart
				if not ep or not root then continue end
				local d = (ep.Position - root.Position).Magnitude
				if d < range and d < closestDist then
					closest, closestDist = enemy, d
				end
			end

			if closest then
				enemyManager.DamageEnemy(closest, damage, rec.model)
				rec.cooldown = 1 / rec.data.fireRate
				-- TODO: Spawn a projectile VFX from root.Position toward closest
			end
		end
	end
end

return TowerManager
