-- EconomyManager
-- Owns two economies:
--   1. Per-player, per-lane coin wallets (individual — players cannot spend
--      each other's coins even in co-op).
--   2. A single shared Mutation Point (MP) pool that all players draw from
--      and contribute to together.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Constants         = require(Shared.Constants)
local Network           = require(Shared.Network)

local EconomyManager = {}

-- _coins[UserId][laneId] = current balance
local _coins: { [number]: { [number]: number } } = {}
local _mutationPoints: number = 0

-- ── Internal ──────────────────────────────────────────────────────────────────

local function ensureWallet(userId: number, laneId: number)
	if not _coins[userId] then
		_coins[userId] = {}
	end
	if not _coins[userId][laneId] then
		_coins[userId][laneId] = Constants.STARTING_COINS
	end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Connect PlayerAdded / PlayerRemoving so wallets are created and cleaned up
	automatically.  Call this before any player can join.
]]
function EconomyManager.Initialize()
	Players.PlayerAdded:Connect(function(player)
		_coins[player.UserId] = {}
	end)
	Players.PlayerRemoving:Connect(function(player)
		_coins[player.UserId] = nil
	end)
	-- Seed wallets for anyone already in-game (Studio test with existing players)
	for _, player in Players:GetPlayers() do
		_coins[player.UserId] = {}
	end
end

-- ── Lane coins ────────────────────────────────────────────────────────────────

--[[
	Add coins to a player's lane wallet and broadcast the new total.
	Safe to call with any non-negative amount.
]]
function EconomyManager.AddCoins(player: Player, laneId: number, amount: number)
	ensureWallet(player.UserId, laneId)
	_coins[player.UserId][laneId] += amount
	Network.UpdateCoins:FireClient(player, laneId, _coins[player.UserId][laneId])
end

--[[
	Attempt to deduct coins from a player's lane wallet.
	Returns true on success, false when the player cannot afford it (no change).
]]
function EconomyManager.SpendCoins(player: Player, laneId: number, amount: number): boolean
	ensureWallet(player.UserId, laneId)
	if _coins[player.UserId][laneId] < amount then
		return false
	end
	_coins[player.UserId][laneId] -= amount
	Network.UpdateCoins:FireClient(player, laneId, _coins[player.UserId][laneId])
	return true
end

-- Returns the current coin balance for a player's lane wallet.
function EconomyManager.GetCoins(player: Player, laneId: number): number
	ensureWallet(player.UserId, laneId)
	return _coins[player.UserId][laneId]
end

-- ── Mutation Points (shared pool) ─────────────────────────────────────────────

-- Add to the shared MP pool and broadcast the updated total to all clients.
function EconomyManager.AddMutationPoints(amount: number)
	_mutationPoints += amount
	Network.UpdateMutationPoints:FireAllClients(_mutationPoints)
end

--[[
	Deduct from the shared MP pool.
	Returns true on success, false when the pool has insufficient points.
]]
function EconomyManager.SpendMutationPoints(amount: number): boolean
	if _mutationPoints < amount then
		return false
	end
	_mutationPoints -= amount
	Network.UpdateMutationPoints:FireAllClients(_mutationPoints)
	return true
end

-- Returns the current shared MP total.
function EconomyManager.GetMutationPoints(): number
	return _mutationPoints
end

-- ── Convenience ───────────────────────────────────────────────────────────────

--[[
	Award both lane coins and shared MP when an enemy is killed.
	Call this from WaveManager after confirming the kill.
	coinReward / mpReward come from the enemy's EnemyData.
]]
function EconomyManager.OnEnemyKilled(
	player: Player,
	laneId: number,
	coinReward: number,
	mpReward: number
)
	EconomyManager.AddCoins(player, laneId, coinReward)
	EconomyManager.AddMutationPoints(mpReward)
end

return EconomyManager
