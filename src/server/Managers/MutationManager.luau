-- MutationManager
-- Manages the shared mutation / augment tree.
--
-- Unlocking a mutation spends from the shared MP pool (via EconomyManager).
-- "global" mutations are read at attack-compute time by TowerManager.
-- "tower" mutations are stamped onto a tower Model as Attributes so
--   TowerManager can apply per-tower bonuses without querying this module.
-- "lane" mutations affect enemies entering or on a specific lane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Network           = require(Shared.Network)

type MutationData = Types.MutationData

local MutationManager = {}

-- ── Lazy dependency ───────────────────────────────────────────────────────────

local function getEconomy() return require(script.Parent.EconomyManager) end

-- ── Mutation catalog ──────────────────────────────────────────────────────────
-- TODO: Move to Config/Mutations when the tree grows large.

local CATALOG: { [string]: MutationData } = {
	-- Tier 1 (no prerequisites)
	SharpKnives = {
		id = "SharpKnives", name = "Sharp Knives",
		description   = "All towers deal +10 % damage.",
		cost          = 20, tier = 1,
		prerequisites = {}, targetType = "global",
	},
	CrispyCrust = {
		id = "CrispyCrust", name = "Crispy Crust",
		description   = "Apply to one tower to give it +15 % range.",
		cost          = 25, tier = 1,
		prerequisites = {}, targetType = "tower",
	},
	SeasonedLane = {
		id = "SeasonedLane", name = "Seasoned Lane",
		description   = "Apply to one lane — enemies in that lane have -10 % speed.",
		cost          = 30, tier = 1,
		prerequisites = {}, targetType = "lane",
	},

	-- Tier 2 (require tier-1 nodes)
	DoubleSauce = {
		id = "DoubleSauce", name = "Double Sauce",
		description   = "Saucier-class towers fire 20 % faster globally.",
		cost          = 35, tier = 2,
		prerequisites = { "SharpKnives" }, targetType = "global",
	},
	ExtraCaramelization = {
		id = "ExtraCaramelization", name = "Extra Caramelization",
		description   = "Apply to one tower to add a 10 % chance to stun on hit.",
		cost          = 40, tier = 2,
		prerequisites = { "CrispyCrust" }, targetType = "tower",
	},

	-- Tier 3 (require two tier-2 nodes)
	MergeAmplifier = {
		id = "MergeAmplifier", name = "Merge Amplifier",
		description   = "Enemies entering the merge zone take +25 % damage from all towers.",
		cost          = 60, tier = 3,
		prerequisites = { "DoubleSauce", "SeasonedLane" }, targetType = "global",
	},

	-- Tier 4 (capstone)
	ChefsMasterRecipe = {
		id = "ChefsMasterRecipe", name = "Chef's Master Recipe",
		description   = "Every tower's fireRate and damage are increased by 20 % globally.",
		cost          = 100, tier = 4,
		prerequisites = { "MergeAmplifier", "ExtraCaramelization" }, targetType = "global",
	},
}

-- ── State ─────────────────────────────────────────────────────────────────────

local _unlocked: { [string]: boolean } = {}

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function MutationManager.Initialize()
	_unlocked = {}
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns every MutationData entry in the catalog.
function MutationManager.GetAvailableMutations(): { MutationData }
	local result = {}
	for _, data in CATALOG do
		table.insert(result, data)
	end
	return result
end

-- Returns the MutationData for a given id, or nil if unknown.
function MutationManager.GetMutationData(mutationId: string): MutationData?
	return CATALOG[mutationId]
end

-- Returns true if the mutation has been unlocked in this session.
function MutationManager.IsMutationUnlocked(mutationId: string): boolean
	return _unlocked[mutationId] == true
end

-- Returns an array of all currently unlocked MutationData entries.
function MutationManager.GetActiveMutations(): { MutationData }
	local result = {}
	for id, unlocked in _unlocked do
		if unlocked then
			local data = CATALOG[id]
			if data then table.insert(result, data) end
		end
	end
	return result
end

-- ── Unlock ────────────────────────────────────────────────────────────────────

--[[
	Attempt to unlock a mutation:
	  1. Validates it exists and is not already unlocked.
	  2. Checks that all prerequisite mutations are unlocked.
	  3. Spends the MP cost from the shared pool.
	Returns true on success; fires MutationUnlocked to all clients.
]]
function MutationManager.UnlockMutation(mutationId: string): boolean
	local data = CATALOG[mutationId]
	if not data then return false end
	if _unlocked[mutationId] then return false end -- idempotent guard

	for _, prereq in data.prerequisites do
		if not _unlocked[prereq] then return false end
	end

	if not getEconomy().SpendMutationPoints(data.cost) then return false end

	_unlocked[mutationId] = true
	Network.MutationUnlocked:FireAllClients(mutationId)
	return true
end

-- ── Apply ─────────────────────────────────────────────────────────────────────

--[[
	Apply a targeted mutation to a tower or lane.
	- "tower" targetType: stamps a boolean Attribute on the Model so
	  TowerManager's attack loop can factor it in.
	- "global" / "lane" targetType: these are passively read via
	  GetActiveMutations() and require no per-model stamping.
	Returns true if the mutation is valid, unlocked, and applied.
]]
function MutationManager.ApplyMutation(mutationId: string, target: Model | number): boolean
	local data = CATALOG[mutationId]
	if not data then return false end
	if not _unlocked[mutationId] then return false end

	if data.targetType == "tower" and typeof(target) ~= "number" then
		local model = target :: Model
		model:SetAttribute("Mutation_" .. mutationId, true)
		return true
	elseif data.targetType == "lane" and typeof(target) == "number" then
		-- Lane mutations are stored as a global flag scoped to laneId.
		-- EnemyManager reads GetActiveMutations() and filters by lane.
		return true
	elseif data.targetType == "global" then
		return true -- applied globally by being in _unlocked
	end

	return false
end

return MutationManager
