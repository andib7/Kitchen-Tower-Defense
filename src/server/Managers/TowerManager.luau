-- TowerManager
-- Handles tower placement (with cost / lane-ownership validation), upgrades,
-- and sells.  Combat behavior (targeting, on-hit abilities, mutation-aware
-- stats) lives in the BaseTower class hierarchy under src/server/Towers — this
-- module just owns economy/ownership bookkeeping and ticks each instance's
-- :Update() from the Heartbeat loop.  EconomyManager and MapManager are
-- lazy-required inside functions to avoid a circular dependency at load time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Constants         = require(Shared.Constants)
local Network           = require(Shared.Network)
local TowerCatalog      = require(Shared.TowerCatalog)
local TowerClasses      = require(script.Parent.Parent.Towers.TowerClasses)

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

-- A BaseTower subclass instance (see src/server/Towers/BaseTower.luau).
type TowerInstance = typeof(setmetatable({} :: {
	model: Model, towerId: string, ownerId: number, laneId: number,
	level: number, cooldown: number,
}, {} :: any))

-- _placed[laneId] = { TowerInstance, ... }
local _placed: { [number]: { TowerInstance } } = {}

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

local function getLaneTowers(laneId: number): { TowerInstance }
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

-- Returns the array of tower instances placed on a lane.
function TowerManager.GetPlacedTowers(laneId: number): { TowerInstance }
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

	local class    = TowerClasses[towerId]
	local instance = class.new(model, player.UserId, laneId)
	table.insert(laneTowers, instance)

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

	for _, instance in getLaneTowers(laneId) do
		if instance.model == tower and instance.ownerId == player.UserId then
			local data = CATALOG[instance.towerId]
			if instance.level >= data.maxLevel then return false end
			if not getEconomy().SpendCoins(player, laneId, data.upgradeCost) then
				return false
			end
			instance:SetLevel(instance.level + 1)
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
	for i, instance in laneTowers do
		if instance.model == tower and instance.ownerId == player.UserId then
			local data       = CATALOG[instance.towerId]
			local totalSpent = data.cost + (instance.level - 1) * data.upgradeCost
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
	for _, records in _placed do
		for _, instance in records do
			instance:Update(dt, enemyManager)
		end
	end
end

return TowerManager
