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
	healthLabel: TextLabel?,
	-- Status effects: countdown-seconds, decremented by dt each Heartbeat
	-- (same style as TowerManager's per-tower cooldown).
	slowMultiplier: number?,
	slowExpiry: number?,
	stunExpiry: number?,
	burnDps: number?,
	burnExpiry: number?,
}

local _active: { [Model]: EnemyState } = {}

-- Permanent per-lane speed multiplier (e.g. the SeasonedLane mutation).
-- Defaults to 1 (no effect) for any lane not present in this table.
local _laneSpeedMultiplier: { [number]: number } = {}

-- Placeholder colors per enemy type until real models are cloned from
-- ReplicatedStorage.Enemies.
local ENEMY_COLORS: { [string]: Color3 } = {
	BurgerBasic  = Color3.fromRGB(140, 90, 40),
	HotDogRunner = Color3.fromRGB(230, 140, 40),
	NachoTank    = Color3.fromRGB(230, 200, 60),
	PizzaBoss    = Color3.fromRGB(200, 40, 40),
}

--[[
	Build a simple colored block with a floating health label.
	TODO: Replace with model:Clone() from ReplicatedStorage.Enemies[data.id].
]]
local function buildEnemyModel(data: EnemyData): (Model, TextLabel)
	local model = Instance.new("Model")
	model.Name = data.name

	local size = if data.isBoss then Vector3.new(4, 4, 4) else Vector3.new(2, 2, 2)
	local body = Instance.new("Part")
	body.Name        = "Body"
	body.Size        = size
	body.Anchored    = true
	body.CanCollide  = false
	body.Color       = ENEMY_COLORS[data.id] or Color3.fromRGB(200, 200, 200)
	body.Material    = Enum.Material.SmoothPlastic
	body.Parent      = model

	local healthGui = Instance.new("BillboardGui")
	healthGui.Name        = "HealthGui"
	healthGui.Size        = UDim2.new(2, 0, 0.5, 0)
	healthGui.StudsOffset = Vector3.new(0, size.Y / 2 + 0.5, 0)
	healthGui.AlwaysOnTop = true
	healthGui.Parent      = body

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name                = "HealthLabel"
	healthLabel.Size                = UDim2.new(1, 0, 1, 0)
	healthLabel.BackgroundTransparency = 1
	healthLabel.TextColor3          = Color3.new(1, 1, 1)
	healthLabel.TextScaled          = true
	healthLabel.Font                = Enum.Font.GothamBold
	healthLabel.Text                = tostring(data.maxHealth)
	healthLabel.Parent              = healthGui

	model.PrimaryPart = body
	return model, healthLabel
end

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

-- Returns the current health of an active enemy, or nil if it's not active.
function EnemyManager.GetEnemyHealth(enemy: Model): number?
	local state = _active[enemy]
	return state and state.health
end

-- Returns every active enemy on laneId within radius studs of position,
-- excluding centerEnemy itself. Used for splash/spread on-hit effects.
function EnemyManager.GetEnemiesNear(position: Vector3, radius: number, laneId: number, centerEnemy: Model?): { Model }
	local result = {}
	for model, state in _active do
		if model == centerEnemy or state.laneId ~= laneId then continue end
		local root = model.PrimaryPart
		if not root then continue end
		if (root.Position - position).Magnitude <= radius then
			table.insert(result, model)
		end
	end
	return result
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

	local model, healthLabel = buildEnemyModel(data)
	model:SetAttribute("EnemyId", enemyId)
	model:PivotTo(CFrame.new(path[1]))
	model.Parent = workspace

	_active[model] = {
		data           = data,
		laneId         = laneId,
		health         = data.maxHealth,
		waypointIndex  = 1,
		path           = path,
		speed          = data.speed,
		healthLabel    = healthLabel,
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
	if state.healthLabel then
		state.healthLabel.Text = tostring(math.max(0, math.floor(state.health)))
	end
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

-- ── Status effects ───────────────────────────────────────────────────────────

-- Apply (or refresh) a damage-over-time burn on enemy for duration seconds.
function EnemyManager.ApplyBurn(enemy: Model, dps: number, duration: number)
	local state = _active[enemy]
	if not state then return end
	state.burnDps    = dps
	state.burnExpiry = duration
end

-- Apply (or refresh) a speed multiplier on enemy for duration seconds.
-- multiplier should be < 1 to slow; the most recent application always wins.
function EnemyManager.ApplySlow(enemy: Model, multiplier: number, duration: number)
	local state = _active[enemy]
	if not state then return end
	state.slowMultiplier = multiplier
	state.slowExpiry     = duration
end

-- Prevent enemy from moving for duration seconds.
function EnemyManager.ApplyStun(enemy: Model, duration: number)
	local state = _active[enemy]
	if not state then return end
	state.stunExpiry = duration
end

-- Set a permanent speed multiplier for every enemy currently and future on
-- laneId (e.g. the SeasonedLane mutation). Pass 1 to clear.
function EnemyManager.SetLaneSpeedMultiplier(laneId: number, multiplier: number)
	_laneSpeedMultiplier[laneId] = multiplier
end

-- ── Per-frame update ──────────────────────────────────────────────────────────

--[[
	Move every active enemy toward its current waypoint.  Advances the
	waypoint index when the enemy gets close enough, and calls EnemyReachedEnd
	when the last waypoint is passed.
]]
function EnemyManager.UpdateEnemies(dt: number)
	for enemy, state in _active do
		-- Tick burn DoT first; it may kill the enemy before it ever moves.
		if state.burnExpiry and state.burnExpiry > 0 then
			EnemyManager.DamageEnemy(enemy, (state.burnDps or 0) * dt, "burn")
			if not _active[enemy] then continue end -- burn finished it off
			state.burnExpiry -= dt
			if state.burnExpiry <= 0 then
				state.burnDps    = nil
				state.burnExpiry = nil
			end
		end

		-- Tick stun: skip movement entirely while stunned.
		if state.stunExpiry and state.stunExpiry > 0 then
			state.stunExpiry -= dt
			if state.stunExpiry <= 0 then
				state.stunExpiry = nil
			end
			continue
		end

		-- Tick slow expiry (multiplier itself is applied below).
		if state.slowExpiry and state.slowExpiry > 0 then
			state.slowExpiry -= dt
			if state.slowExpiry <= 0 then
				state.slowMultiplier = nil
				state.slowExpiry     = nil
			end
		end

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
			-- Move toward waypoint, applying any active slow + the lane's
			-- permanent speed multiplier (e.g. from the SeasonedLane mutation).
			local effectiveSpeed = state.speed
				* (state.slowMultiplier or 1)
				* (_laneSpeedMultiplier[state.laneId] or 1)
			local move    = direction.Unit * math.min(effectiveSpeed * dt, dist)
			root.Position = root.Position + move
		end
	end
end

return EnemyManager
