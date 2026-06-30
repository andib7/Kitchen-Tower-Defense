-- TowerPlacementController
-- Manages the two-step tower placement flow:
--   1. Player selects a tower from the shop → BeginPlacement().
--   2. A ghost (preview) model follows the mouse; clicking confirms placement.
-- Also handles upgrade and sell requests for already-placed towers.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TowerCatalog      = require(ReplicatedStorage.Shared.TowerCatalog)

local TowerPlacementController = {}

local _localPlayer = Players.LocalPlayer
local _mouse       = _localPlayer:GetMouse()
local _network: any

local _isPlacing:      boolean = false
local _selectedTowerId: string? = nil
local _ghostModel:     Model?   = nil
local _ghostRing:      Part?    = nil
-- TODO: determine laneId from which lane the cursor is hovering over (via
-- a named lane Part's attributes, or a lane-bounds raycast result).
local _activeLaneId:   number  = 1

-- Fired with the newly-selected towerId (or nil when placement ends), so the
-- shop UI and tower-selection UI can react to placement mode toggling.
-- A list (not a single slot) since multiple controllers need to listen.
local _onPlacementChanged: { (selectedTowerId: string?) -> () } = {}

-- Register a callback fired whenever the active placement selection changes.
function TowerPlacementController.SetOnPlacementChanged(cb: (string?) -> ())
	table.insert(_onPlacementChanged, cb)
end

local function fireOnPlacementChanged()
	for _, cb in _onPlacementChanged do
		cb(_selectedTowerId)
	end
end

-- Returns the towerId currently selected for placement, or nil if none.
function TowerPlacementController.GetSelectedTowerId(): string?
	return _selectedTowerId
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Wire input events and server confirmation remotes.
	Must be called once from init.client.luau.
]]
function TowerPlacementController.Initialize(network: any)
	_network = network

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and _isPlacing then
			TowerPlacementController._AttemptPlace()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			TowerPlacementController.CancelPlacement()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if _isPlacing and _ghostModel then
			TowerPlacementController._UpdateGhostPosition()
		end
	end)

	network.TowerPlaced.OnClientEvent:Connect(
		function(towerId: string, laneId: number, position: Vector3, model: Model)
			TowerPlacementController.OnTowerConfirmed(towerId, laneId, position, model)
		end
	)

	network.TowerSold.OnClientEvent:Connect(function(_model: Model, _laneId: number)
		-- Visual cleanup (e.g. remove a selection highlight) goes here.
	end)
end

-- ── Placement flow ────────────────────────────────────────────────────────────

--[[
	Begin placement mode for the given tower type.
	Spawns a ghost (tinted, non-collidable) preview model the player drags
	around before clicking to commit.
	Call this from the tower-shop UI when the player clicks a tower button.
]]
function TowerPlacementController.BeginPlacement(towerId: string)
	TowerPlacementController.CancelPlacement() -- clean up any prior ghost

	_selectedTowerId = towerId
	_isPlacing       = true

	-- TODO: Clone from ReplicatedStorage.TowerPreviews[towerId] instead of a block.
	local body = Instance.new("Part")
	body.Name        = "GhostBody"
	body.Size        = Vector3.new(3, 3, 3)
	body.Anchored    = true
	body.CanCollide  = false
	body.CanQuery    = false -- don't let the ghost block its own placement raycast
	body.Transparency = 0.5
	body.Color       = Color3.fromRGB(80, 220, 255)
	body.Material    = Enum.Material.ForceField

	_ghostModel = Instance.new("Model")
	_ghostModel.Name = towerId .. "_Ghost"
	_ghostModel.PrimaryPart = body
	body.Parent = _ghostModel
	_ghostModel.Parent = workspace

	local data = TowerCatalog.Towers[towerId]
	if data then
		local levelData = data.levels and data.levels[1]
		local range = (levelData and levelData.range) or data.range
		local ring = Instance.new("Part")
		ring.Name         = "GhostRangeRing"
		ring.Shape        = Enum.PartType.Cylinder
		ring.Size         = Vector3.new(0.1, range * 2, range * 2)
		ring.Anchored     = true
		ring.CanCollide   = false
		ring.CanQuery     = false
		ring.CastShadow   = false
		ring.Material     = Enum.Material.Neon
		ring.Color        = Color3.fromRGB(80, 220, 255)
		ring.Transparency = 0.78
		ring.Parent       = workspace
		_ghostRing = ring
	end

	fireOnPlacementChanged()
end

--[[
	Cancel placement mode without placing a tower.
	Called on Escape or when placement succeeds.
]]
function TowerPlacementController.CancelPlacement()
	_isPlacing       = false
	_selectedTowerId = nil
	if _ghostModel then _ghostModel:Destroy(); _ghostModel = nil end
	if _ghostRing   then _ghostRing:Destroy();  _ghostRing  = nil end
	fireOnPlacementChanged()
end

--[[
	Raycast to the mouse hit position and move the ghost there, snapped to
	a grid.  Tint red when the position would be invalid (e.g. off-lane,
	overlapping another tower).
]]
function TowerPlacementController._UpdateGhostPosition()
	local unitRay = workspace.CurrentCamera:ScreenPointToRay(_mouse.X, _mouse.Y)
	local result  = workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * 500,
		RaycastParams.new() -- TODO: exclude ghost model and enemy models from hits
	)
	if result and _ghostModel then
		-- Snap to 2-stud grid
		local p = result.Position
		local snapped = Vector3.new(
			math.round(p.X / 2) * 2,
			p.Y,
			math.round(p.Z / 2) * 2
		)
		if _ghostModel.PrimaryPart then
			local liftedPos = snapped + Vector3.new(0, 1.5, 0)
			_ghostModel:PivotTo(CFrame.new(liftedPos))
			if _ghostRing then
				_ghostRing.CFrame = CFrame.new(liftedPos.X, liftedPos.Y - 1.4, liftedPos.Z)
				                  * CFrame.Angles(0, 0, math.pi / 2)
			end
		end
		-- TODO: Validate placement (on-lane, no overlap) and tint accordingly
	end
end

--[[
	Send the place request to the server at the ghost model's current position.
	CancelPlacement() is called immediately on success; on failure the ghost
	stays so the player can try a different spot.
]]
function TowerPlacementController._AttemptPlace()
	if not _selectedTowerId or not _ghostModel then return end
	-- Send the ground hit point (un-lifted) — TowerManager.PlaceTower applies
	-- its own +1.5 stud lift server-side so towers sit on the surface.
	local pos = _ghostModel.PrimaryPart
		and (_ghostModel.PrimaryPart.Position - Vector3.new(0, 1.5, 0))
		or Vector3.new()
	local ok  = _network.PlaceTower:InvokeServer(_selectedTowerId, _activeLaneId, pos)
	if ok then
		TowerPlacementController.CancelPlacement()
	end
	-- TODO: Show red flash + shake on failure
end

-- ── Confirmation callbacks ────────────────────────────────────────────────────

--[[
	Called when the server broadcasts any tower placement (local or remote).
	Use this to play a placement sound/VFX and update any shop UI state.
]]
function TowerPlacementController.OnTowerConfirmed(
	_towerId:  string,
	_laneId:   number,
	_position: Vector3,
	_model:    Model
)
	-- TODO: Play snap-in VFX at _position; update affordability in shop UI.
end

-- ── Tower actions ─────────────────────────────────────────────────────────────

-- Send an upgrade request for a tower the player has selected in the world.
function TowerPlacementController.RequestUpgrade(tower: Model)
	local ok = _network.UpgradeTower:InvokeServer(tower)
	if ok then
		-- TODO: Play upgrade VFX / update level badge
	end
end

-- Send a sell request for a tower the player has selected.
function TowerPlacementController.RequestSell(tower: Model)
	_network.SellTower:InvokeServer(tower)
end

return TowerPlacementController
