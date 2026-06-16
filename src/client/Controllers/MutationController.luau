-- MutationController
-- Client-side mutation tree UI logic.
-- Tracks which mutations are unlocked (server is authoritative; this mirrors
-- state for instant UI feedback), handles unlock/apply requests, and drives
-- the mutation tree panel open/close animation.

local MutationController = {}

local _network: any = nil
local _currentMP: number = 0
local _unlocked: { [string]: boolean } = {}
local _panelOpen: boolean = false
local _panelGui: ScreenGui? = nil

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Connect all mutation-related server events and build the panel GUI.
	Must be called once from init.client.luau.
]]
function MutationController.Initialize(network: any)
	_network = network

	network.MutationUnlocked.OnClientEvent:Connect(function(mutationId: string)
		MutationController.OnMutationUnlocked(mutationId)
	end)

	network.UpdateMutationPoints.OnClientEvent:Connect(function(total: number)
		MutationController.OnMPUpdated(total)
	end)

	-- TODO: Build the tree panel ScreenGui via buildPanel() when visual assets
	-- are ready.  For now the panel is a placeholder.
end

-- ── Network callbacks ─────────────────────────────────────────────────────────

--[[
	Called when the server confirms any mutation unlock (local or remote player).
	Marks the mutation as unlocked locally and refreshes the tree UI.
]]
function MutationController.OnMutationUnlocked(mutationId: string)
	_unlocked[mutationId] = true
	MutationController._RefreshPanel()
end

--[[
	Called whenever the shared MP pool changes.
	Refreshes affordability highlights on tree nodes.
]]
function MutationController.OnMPUpdated(total: number)
	_currentMP = total
	MutationController._RefreshPanel()
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns true if the mutation is locally known to be unlocked.
function MutationController.IsUnlocked(mutationId: string): boolean
	return _unlocked[mutationId] == true
end

-- Returns the last known shared MP total.
function MutationController.GetCurrentMP(): number
	return _currentMP
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--[[
	Request that the server unlocks mutationId using the shared MP pool.
	The server fires MutationUnlocked to all clients on success; this function
	only shows an error flash on failure.
]]
function MutationController.RequestUnlock(mutationId: string)
	local ok = _network.UnlockMutation:InvokeServer(mutationId)
	if not ok then
		-- TODO: Tween a red flash on the node button
		warn("MutationController: could not unlock", mutationId)
	end
end

--[[
	Request that the server applies a tower-targeted mutation to towerModel.
	The player must first select a tower in the world, then click "Apply" in
	the mutation panel.
]]
function MutationController.RequestApply(mutationId: string, towerModel: Model)
	local ok = _network.ApplyMutation:InvokeServer(mutationId, towerModel)
	if ok then
		-- TODO: Play apply VFX on towerModel (particles, glow)
	else
		warn("MutationController: could not apply", mutationId)
	end
end

-- ── Panel UI ─────────────────────────────────────────────────────────────────

--[[
	Toggle the mutation tree panel open or closed.
	Bind this to a keybind (default: M) or a HUD button.
]]
function MutationController.TogglePanel()
	_panelOpen = not _panelOpen
	-- TODO: Tween panel Frame's Position between off-screen and on-screen.
	MutationController._RefreshPanel()
end

--[[
	Rebuild or update the visual state of all tree nodes based on:
	  - Which mutations are unlocked (_unlocked)
	  - Current MP (_currentMP) vs. each mutation's cost
	  - Which prerequisites are satisfied
	Called automatically after every OnMutationUnlocked / OnMPUpdated.
]]
function MutationController._RefreshPanel()
	if not _panelOpen then return end
	-- TODO: Iterate tree node buttons and set their visual state:
	--   unlocked → gold border
	--   affordable + prereqs met → green border
	--   otherwise → grey / locked
end

return MutationController
