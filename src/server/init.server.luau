-- Kitchen Chaos: server entry point.
-- Initializes all managers in dependency order, then wires RemoteFunction
-- handlers so the client can invoke server actions.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requiring Network first ensures Remotes exist before any client connects.
local Network       = require(ReplicatedStorage.Shared.Network)
local Managers      = script.Managers

local MapManager      = require(Managers.MapManager)
local EconomyManager  = require(Managers.EconomyManager)
local EnemyManager    = require(Managers.EnemyManager)
local TowerManager    = require(Managers.TowerManager)
local MutationManager = require(Managers.MutationManager)
local WaveManager     = require(Managers.WaveManager)

-- ── Boot order ────────────────────────────────────────────────────────────────

MapManager.Initialize()      -- lanes / paths must exist before enemies can walk them
EconomyManager.Initialize()  -- wallets must exist before any spend/award
EnemyManager.Initialize()    -- starts Heartbeat movement loop
TowerManager.Initialize()
MutationManager.Initialize()
WaveManager.Initialize()     -- registers enemy callbacks; must run after EnemyManager

-- Tower attack loop — pass EnemyManager to avoid a circular module require
RunService.Heartbeat:Connect(function(dt)
	TowerManager.UpdateTowers(dt, EnemyManager)
end)

-- ── RemoteFunction handlers ───────────────────────────────────────────────────

Network.PlaceTower.OnServerInvoke = function(player, towerId, laneId, position)
	return TowerManager.PlaceTower(player, towerId, laneId, position)
end

Network.UpgradeTower.OnServerInvoke = function(player, tower)
	return TowerManager.UpgradeTower(player, tower)
end

Network.SellTower.OnServerInvoke = function(player, tower)
	TowerManager.SellTower(player, tower)
end

Network.UnlockMutation.OnServerInvoke = function(_player, mutationId)
	return MutationManager.UnlockMutation(mutationId)
end

Network.ApplyMutation.OnServerInvoke = function(player, mutationId, target)
	return MutationManager.ApplyMutation(player, mutationId, target)
end

-- ── Game start ────────────────────────────────────────────────────────────────
-- TODO: Replace this with a proper lobby countdown and lane-assignment flow.
-- For now, kick off wave 1 after a short delay so you can test in Studio.

task.delay(5, function()
	-- Assign all current players to lanes before the first wave
	local Players = game:GetService("Players")
	local players = Players:GetPlayers()
	MapManager.SetupCoopLanes(players)

	-- Push each player's real starting balance now that their lane is known,
	-- so the HUD shows the actual wallet instead of a guessed placeholder.
	for _, player in players do
		local laneId = MapManager.GetPlayerLane(player)
		if laneId then
			EconomyManager.SyncCoins(player, laneId)
		end
	end

	WaveManager.StartWave(1)
end)
