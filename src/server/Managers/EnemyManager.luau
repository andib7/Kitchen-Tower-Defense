-- EnemyManager
-- Spawns food enemies, drives their movement along lane waypoint paths,
-- applies damage, and cleans them up on death or base-leak.
--
-- Callback pattern: WaveManager registers OnEnemyKilled / OnEnemyReachedEnd
-- via the Set* functions below instead of a direct require, keeping the
-- dependency graph acyclic.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Network           = require(Shared.Network)

type EnemyData = Types.EnemyData

local EnemyManager = {}

-- ── Enemy catalog ─────────────────────────────────────────────────────────────
-- TODO: Move to a dedicated Config/Enemies ModuleScript as the roster grows.

local CATALOG: { [string]: EnemyData } = {
	BurgerBasic = {
		id = "BurgerBasic", name = "Basic Burger",
		maxHealth = 100, speed = 8,
		reward = 15, mpReward = 1, isBoss = false,
	},
	HotDogRunner = {
		id = "HotDogRunner", name = "Hot Dog Runner",
		maxHealth = 60, speed = 14,
		reward = 10, mpReward = 1, isBoss = false,
	},
	NachoTank = {
		id = "NachoTank", name = "Nacho Tank",
		maxHealth = 500, speed = 4,
		reward = 50, mpReward = 5, isBoss = false,
	},
	PizzaBoss = {
		id = "PizzaBoss", name = "Pizza Boss",
		maxHealth = 2000, speed = 5,
		reward = 200, mpReward = 25, isBoss = true,
	},
}

-- ── Active enemy state ────────────────────────────────────────────────────────

type EnemyState = {
	data: EnemyData,
	laneId: number,
	health: number,
	waypointIndex: number,
	path: { Vector3 },
	speed: number,
}

local _active: { [Model]: EnemyState } = {}

-- ── Callbacks (set by WaveManager) ───────────────────────────────────────────

local _onKilled:     ((enemy: Model, laneId: number) -> ())?
local _onReachedEnd: ((enemy: Model, laneId: number) -> ())?

-- Register the callback fired when an enemy is killed by a tower.
function EnemyManager.SetOnEnemyKilled(cb: (Model, number) -> ())
	_onKilled = cb
end

-- Register the callback fired when an enemy leaks past the last waypoint.
function EnemyManager.SetOnEnemyReachedEnd(cb: (Model, number) -> ())
	_onReachedEnd = cb
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Start the per-frame movement loop.  Must be called after all callbacks
	are registered.
]]
function EnemyManager.Initialize()
	RunService.Heartbeat:Connect(function(dt)
		EnemyManager.UpdateEnemies(dt)
	end)
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns the static EnemyData for an enemy type id, or nil if unknown.
function EnemyManager.GetEnemyData(enemyId: string): EnemyData?
	return CATALOG[enemyId]
end

-- Returns every active enemy Model on the given lane.
function EnemyManager.GetActiveEnemies(laneId: number): { Model }
	local result = {}
	for model, state in _active do
		if state.laneId == laneId then
			table.insert(result, model)
		end
	end
	return result
end

-- Returns the total count of enemies currently alive across all lanes.
function EnemyManager.GetTotalEnemyCount(): number
	local n = 0
	for _ in _active do n += 1 end
	return n
end

-- ── Mutation ──────────────────────────────────────────────────────────────────

--[[
	Spawn an enemy of the given type on laneId, walking the provided path.
	path should come from MapManager.GetPath(laneId) — passed in here so
	EnemyManager does not need a direct dependency on MapManager.
]]
function EnemyManager.SpawnEnemy(enemyId: string, laneId: number, path: { Vector3 })
	local data = CATALOG[enemyId]
	if not data then
		warn("EnemyManager.SpawnEnemy: unknown enemyId '" .. enemyId .. "'")
		return
	end
	if #path == 0 then
		warn("EnemyManager.SpawnEnemy: empty path for lane", laneId)
		return
	end

	-- TODO: Clone the model from ReplicatedStorage.Enemies[enemyId] instead.
	local model = Instance.new("Model")
	model.Name  = data.name
	model:SetAttribute("EnemyId", enemyId)
	model.Parent = workspace

	_active[model] = {
		data           = data,
		laneId         = laneId,
		health         = data.maxHealth,
		waypointIndex  = 1,
		path           = path,
		speed          = data.speed,
	}

	Network.EnemySpawned:FireAllClients(enemyId, laneId, model)
end

--[[
	Apply damage to an active enemy.  Kills it if health reaches 0.
	source can be a tower Model or any identifier; reserved for future
	kill-credit and mutation proc logic.
]]
function EnemyManager.DamageEnemy(enemy: Model, damage: number, _source: any)
	local state = _active[enemy]
	if not state then return end
	state.health -= damage
	if state.health <= 0 then
		EnemyManager.KillEnemy(enemy)
	end
end

--[[
	Immediately destroy an enemy and fire the killed callback so WaveManager
	and EconomyManager can award rewards.
]]
function EnemyManager.KillEnemy(enemy: Model)
	local state = _active[enemy]
	if not state then return end
	local laneId = state.laneId
	_active[enemy] = nil
	enemy:Destroy()
	Network.EnemyDied:FireAllClients(enemy, laneId)
	if _onKilled then _onKilled(enemy, laneId) end
end

-- ── Per-frame update ──────────────────────────────────────────────────────────

--[[
	Move every active enemy toward its current waypoint.  Advances the
	waypoint index when the enemy gets close enough, and calls EnemyReachedEnd
	when the last waypoint is passed.
]]
function EnemyManager.UpdateEnemies(dt: number)
	for enemy, state in _active do
		local target = state.path[state.waypointIndex]
		if not target then continue end

		local root = enemy.PrimaryPart
		if not root then continue end

		local direction = (target - root.Position)
		local dist      = direction.Magnitude

		if dist < 1 then
			-- Reached waypoint — advance or leak
			state.waypointIndex += 1
			if state.waypointIndex > #state.path then
				_active[enemy] = nil
				enemy:Destroy()
				if _onReachedEnd then _onReachedEnd(enemy, state.laneId) end
			end
		else
			-- Move toward waypoint
			local move   = direction.Unit * math.min(state.speed * dt, dist)
			root.Position = root.Position + move
		end
	end
end

return EnemyManager
