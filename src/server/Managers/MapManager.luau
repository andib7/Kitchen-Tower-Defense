-- MapManager
-- Owns lane definitions, enemy waypoint paths, the co-op merge zone, and
-- the player-to-lane assignment table.  Must be initialized first because
-- every other manager reads lane/path data from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared
local Types             = require(Shared.Types)
local Constants         = require(Shared.Constants)

type Lane = Types.Lane
type Zone = Types.Zone

local MapManager = {}

local _lanes: { [number]: Lane } = {}
local _playerLaneMap: { [number]: number } = {} -- [UserId] = laneId
local _mergeZone: Zone = {
	center = Vector3.new(0, 0, 0),
	size   = Vector3.new(20, 10, 20),
}

--[[
	Initialize lane definitions.  Replace the stub paths with Vector3
	waypoint arrays derived from named Parts in Workspace, e.g.:

	    local pts = workspace.Lanes.Lane1.Waypoints:GetChildren()
	    table.sort(pts, function(a, b) return a.Name < b.Name end)
	    _lanes[1].path = table.map(pts, function(p) return p.Position end)
]]
function MapManager.Initialize()
	_lanes = {
		[1] = { id = 1, name = "Lane 1", path = {}, ownerId = nil, isCoopShared = false },
		[2] = { id = 2, name = "Lane 2", path = {}, ownerId = nil, isCoopShared = false },
		[3] = { id = 3, name = "Lane 3", path = {}, ownerId = nil, isCoopShared = false },
		[4] = { id = 4, name = "Lane 4", path = {}, ownerId = nil, isCoopShared = false },
	}

	-- TODO: Read merge zone bounds from a Workspace Part named "MergeZone"
end

-- Returns the Lane record for the given laneId, or nil if unknown.
function MapManager.GetLane(laneId: number): Lane?
	return _lanes[laneId]
end

-- Returns every defined lane as a flat array.
function MapManager.GetAllLanes(): { Lane }
	local result = {}
	for _, lane in _lanes do
		table.insert(result, lane)
	end
	return result
end

-- Returns the ordered Vector3 waypoint list for laneId's enemy path.
function MapManager.GetPath(laneId: number): { Vector3 }
	local lane = _lanes[laneId]
	return if lane then lane.path else {}
end

-- Returns the Zone bounding box of the shared co-op merge area.
function MapManager.GetMergeZone(): Zone
	return _mergeZone
end

--[[
	Assign a player to a specific lane.  Overwrites any prior assignment.
	Call this during lobby setup before the first wave starts.
]]
function MapManager.AssignPlayerToLane(player: Player, laneId: number)
	_playerLaneMap[player.UserId] = laneId
	local lane = _lanes[laneId]
	if lane then
		lane.ownerId = player.UserId
	end
end

-- Returns the laneId the player is assigned to, or nil if unassigned.
function MapManager.GetPlayerLane(player: Player): number?
	return _playerLaneMap[player.UserId]
end

--[[
	Distribute players evenly across up to MAX_LANES lanes.
	Marks lanes as co-op shared when the player count exceeds the lane count.
	Call once at round start after all players have joined.
]]
function MapManager.SetupCoopLanes(players: { Player })
	for i, player in ipairs(players) do
		local laneId = ((i - 1) % Constants.MAX_LANES) + 1
		MapManager.AssignPlayerToLane(player, laneId)
		if #players > Constants.MAX_LANES then
			if _lanes[laneId] then
				_lanes[laneId].isCoopShared = true
			end
		end
	end
end

-- Returns the first waypoint (enemy spawn point) for a lane.
function MapManager.GetSpawnPoint(laneId: number): Vector3
	local path = MapManager.GetPath(laneId)
	return path[1] or Vector3.new(0, 0, 0)
end

-- Returns the last waypoint (player base / leak point) for a lane.
function MapManager.GetEndPoint(laneId: number): Vector3
	local path = MapManager.GetPath(laneId)
	return path[#path] or Vector3.new(0, 0, 0)
end

return MapManager
