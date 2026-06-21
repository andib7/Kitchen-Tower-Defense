-- Kitchen Chaos: RemoteEvent / RemoteFunction registry.
--
-- The server creates every remote inside ReplicatedStorage.Remotes on first
-- require; clients call :WaitForChild so they block until the server is ready.
-- Both sides require this module to get typed references — never hard-code
-- remote names elsewhere.

local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

local Network = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function makeEvent(parent: Folder, name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = parent
	return e :: RemoteEvent
end

local function makeFunction(parent: Folder, name: string): RemoteFunction
	local f = Instance.new("RemoteFunction")
	f.Name = name
	f.Parent = parent
	return f :: RemoteFunction
end

-- ── Server: create remotes ───────────────────────────────────────────────────

if IS_SERVER then
	local remotes  = Instance.new("Folder")
	remotes.Name   = "Remotes"
	remotes.Parent = ReplicatedStorage

	-- Client → Server (RemoteFunction: client invokes, awaits boolean result)
	Network.PlaceTower     = makeFunction(remotes, "PlaceTower")     -- (towerId, laneId, position) → bool
	Network.UpgradeTower   = makeFunction(remotes, "UpgradeTower")   -- (towerModel) → bool
	Network.SellTower      = makeFunction(remotes, "SellTower")      -- (towerModel) → void
	Network.UnlockMutation = makeFunction(remotes, "UnlockMutation") -- (mutationId) → bool
	Network.ApplyMutation  = makeFunction(remotes, "ApplyMutation")  -- (mutationId, towerModel|laneId) → bool

	-- Server → Client (RemoteEvent: fire and forget)
	Network.UpdateCoins          = makeEvent(remotes, "UpdateCoins")          -- (laneId, newTotal)
	Network.UpdateMutationPoints = makeEvent(remotes, "UpdateMutationPoints") -- (newTotal)
	Network.UpdateLives          = makeEvent(remotes, "UpdateLives")          -- (newTotal)
	Network.WaveStarted          = makeEvent(remotes, "WaveStarted")          -- (waveNumber)
	Network.WaveEnded            = makeEvent(remotes, "WaveEnded")            -- (waveNumber)
	Network.EnemySpawned         = makeEvent(remotes, "EnemySpawned")         -- (enemyId, laneId, model)
	Network.EnemyDied            = makeEvent(remotes, "EnemyDied")            -- (model, laneId)
	Network.TowerPlaced          = makeEvent(remotes, "TowerPlaced")          -- (towerId, laneId, position, model)
	Network.TowerSold            = makeEvent(remotes, "TowerSold")            -- (model, laneId)
	Network.MutationUnlocked     = makeEvent(remotes, "MutationUnlocked")     -- (mutationId)
	Network.GameOver             = makeEvent(remotes, "GameOver")             -- ()

-- ── Client: wait for remotes ─────────────────────────────────────────────────

else
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	Network.PlaceTower     = remotes:WaitForChild("PlaceTower")
	Network.UpgradeTower   = remotes:WaitForChild("UpgradeTower")
	Network.SellTower      = remotes:WaitForChild("SellTower")
	Network.UnlockMutation = remotes:WaitForChild("UnlockMutation")
	Network.ApplyMutation  = remotes:WaitForChild("ApplyMutation")

	Network.UpdateCoins          = remotes:WaitForChild("UpdateCoins")
	Network.UpdateMutationPoints = remotes:WaitForChild("UpdateMutationPoints")
	Network.UpdateLives          = remotes:WaitForChild("UpdateLives")
	Network.WaveStarted          = remotes:WaitForChild("WaveStarted")
	Network.WaveEnded            = remotes:WaitForChild("WaveEnded")
	Network.EnemySpawned         = remotes:WaitForChild("EnemySpawned")
	Network.EnemyDied            = remotes:WaitForChild("EnemyDied")
	Network.TowerPlaced          = remotes:WaitForChild("TowerPlaced")
	Network.TowerSold            = remotes:WaitForChild("TowerSold")
	Network.MutationUnlocked     = remotes:WaitForChild("MutationUnlocked")
	Network.GameOver             = remotes:WaitForChild("GameOver")
end

return Network
