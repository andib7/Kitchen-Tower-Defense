-- WaveManager
-- Drives wave progression: reads WaveConfig tables, schedules staggered enemy
-- spawns via EnemyManager, and transitions into intermission when every enemy
-- in the wave has been killed or has leaked past the base.
--
-- Dependencies on EnemyManager, MapManager, and EconomyManager are lazy-
-- required so there are no load-time circular references.

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Constants         = require(Shared.Constants)
local Network           = require(Shared.Network)

type WaveConfig = Types.WaveConfig

local WaveManager = {}

-- ── Lazy dependencies ─────────────────────────────────────────────────────────

local function getEnemy()   return require(script.Parent.EnemyManager)   end
local function getMap()     return require(script.Parent.MapManager)     end
local function getEconomy() return require(script.Parent.EconomyManager) end

-- ── Wave configs ──────────────────────────────────────────────────────────────
-- Add entries here to expand the campaign.  Endless scaling kicks in beyond
-- the last defined entry via GetWaveData().

local WAVE_CONFIGS: { WaveConfig } = {
	{
		number = 1,
		enemies = { { id = "BurgerBasic",  count = 5, interval = 1.5 } },
		mutationPointBonus = 5,
		soloScaleMultiplier = Constants.SOLO_ENEMY_SCALE,
	},
	{
		number = 2,
		enemies = {
			{ id = "BurgerBasic",  count = 8,  interval = 1.2 },
			{ id = "HotDogRunner", count = 3,  interval = 2.0 },
		},
		mutationPointBonus = 10,
		soloScaleMultiplier = Constants.SOLO_ENEMY_SCALE,
	},
	{
		number = 3,
		enemies = {
			{ id = "BurgerBasic",  count = 10, interval = 1.0 },
			{ id = "HotDogRunner", count = 5,  interval = 1.5 },
			{ id = "NachoTank",    count = 2,  interval = 4.0 },
		},
		mutationPointBonus = 15,
		soloScaleMultiplier = Constants.SOLO_ENEMY_SCALE,
	},
	{
		number = 4,
		enemies = {
			{ id = "BurgerBasic",  count = 15, interval = 0.8 },
			{ id = "HotDogRunner", count = 8,  interval = 1.2 },
			{ id = "NachoTank",    count = 4,  interval = 3.0 },
			{ id = "PizzaBoss",    count = 1,  interval = 0   },
		},
		mutationPointBonus = 30,
		soloScaleMultiplier = Constants.SOLO_ENEMY_SCALE,
	},
}

-- ── State ─────────────────────────────────────────────────────────────────────

local _currentWave:    number  = 0
local _isWaveActive:   boolean = false
local _enemiesLeft:    number  = 0   -- spawned enemies not yet killed or leaked
local _inIntermission: boolean = false
local _intermissionT:  number  = 0

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Wire enemy callbacks and start the intermission countdown loop.
	Must be called after EnemyManager.Initialize().
]]
function WaveManager.Initialize()
	local enemy = getEnemy()

	enemy.SetOnEnemyKilled(function(e, laneId)
		WaveManager._OnEnemyRemoved(e, laneId, true)
	end)
	enemy.SetOnEnemyReachedEnd(function(e, laneId)
		WaveManager._OnEnemyRemoved(e, laneId, false)
	end)

	RunService.Heartbeat:Connect(function(dt)
		if _inIntermission then
			_intermissionT -= dt
			if _intermissionT <= 0 then
				_inIntermission = false
				WaveManager.StartWave(_currentWave + 1)
			end
		end
	end)
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns the current wave number (0 = no wave has started yet).
function WaveManager.GetCurrentWave(): number
	return _currentWave
end

-- Returns true while enemies are still alive or spawning.
function WaveManager.IsWaveActive(): boolean
	return _isWaveActive
end

--[[
	Returns the WaveConfig for waveNumber.  For waves beyond the last
	defined entry, returns an auto-scaled variant of the final config
	so the game supports endless play.
]]
function WaveManager.GetWaveData(waveNumber: number): WaveConfig
	if waveNumber <= #WAVE_CONFIGS then
		return WAVE_CONFIGS[waveNumber]
	end

	-- Endless scaling: extrapolate from the last config
	local base      = WAVE_CONFIGS[#WAVE_CONFIGS]
	local overflow  = waveNumber - #WAVE_CONFIGS
	local countMult = 1 + overflow * 0.2
	local speedMult = math.max(0.4, 1 - overflow * 0.05)

	local scaled: WaveConfig = {
		number             = waveNumber,
		enemies            = {},
		mutationPointBonus = base.mutationPointBonus + overflow * 5,
		soloScaleMultiplier = base.soloScaleMultiplier,
	}
	for _, group in base.enemies do
		table.insert(scaled.enemies, {
			id       = group.id,
			count    = math.ceil(group.count * countMult),
			interval = group.interval * speedMult,
		})
	end
	return scaled
end

-- ── Wave control ──────────────────────────────────────────────────────────────

--[[
	Begin spawning enemies for waveNumber.  Enemies are distributed across
	every currently active lane; groups are staggered by their interval.
	No-ops if a wave is already running.
]]
function WaveManager.StartWave(waveNumber: number)
	if _isWaveActive then
		warn("WaveManager.StartWave: wave already in progress")
		return
	end

	local config = WaveManager.GetWaveData(waveNumber)
	local map    = getMap()
	local enemy  = getEnemy()
	local lanes  = map.GetAllLanes()

	-- Apply solo scaling when only one player is present
	local isSolo   = #Players:GetPlayers() == 1
	local scaleMult = (isSolo and config.soloScaleMultiplier) and config.soloScaleMultiplier or 1

	_currentWave  = waveNumber
	_isWaveActive = true
	_enemiesLeft  = 0

	Network.WaveStarted:FireAllClients(waveNumber)

	local delay = 0
	for _, group in config.enemies do
		local count = math.max(1, math.round(group.count * scaleMult))
		_enemiesLeft += count * #lanes

		for i = 1, count do
			local spawnDelay = delay + (i - 1) * group.interval
			task.delay(spawnDelay, function()
				if not _isWaveActive then return end
				for _, lane in lanes do
					enemy.SpawnEnemy(group.id, lane.id, map.GetPath(lane.id))
				end
			end)
		end
		delay += count * group.interval
	end
end

--[[
	Force-terminate the active wave (admin command, game-over trigger, etc.).
]]
function WaveManager.EndWave()
	if not _isWaveActive then return end
	_isWaveActive = false
	Network.WaveEnded:FireAllClients(_currentWave)
end

-- ── Internal ──────────────────────────────────────────────────────────────────

--[[
	Called by enemy callbacks whenever an enemy is removed from the field.
	Awards kill rewards through EconomyManager and checks for wave completion.
]]
function WaveManager._OnEnemyRemoved(enemy: Model, laneId: number, wasKilled: boolean)
	_enemiesLeft = math.max(0, _enemiesLeft - 1)

	if wasKilled then
		local enemyId = enemy:GetAttribute("EnemyId") :: string?
		if enemyId then
			local data = getEnemy().GetEnemyData(enemyId)
			if data then
				-- Credit the player assigned to this lane, or the first player as fallback
				local laneOwner: Player? = nil
				for _, player in Players:GetPlayers() do
					if getMap().GetPlayerLane(player) == laneId then
						laneOwner = player
						break
					end
				end
				if laneOwner then
					getEconomy().OnEnemyKilled(laneOwner, laneId, data.reward, data.mpReward)
				end
			end
		end
	end

	WaveManager._CheckWaveComplete()
end

function WaveManager._CheckWaveComplete()
	if not _isWaveActive then return end
	if _enemiesLeft > 0 then return end
	if getEnemy().GetTotalEnemyCount() > 0 then return end

	WaveManager.EndWave()

	-- Bonus MP for clearing the wave
	local config = WaveManager.GetWaveData(_currentWave)
	getEconomy().AddMutationPoints(config.mutationPointBonus)

	-- Begin intermission countdown
	_inIntermission = true
	_intermissionT  = Constants.WAVE_INTERMISSION_SECS
end

return WaveManager
