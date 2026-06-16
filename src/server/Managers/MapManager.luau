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
	Initialize lane definitions by reading Parts under workspace.Lanes.LaneN.Waypoints
	(see default.project.json, which version-controls these as plain Parts).
	Falls back to a single empty-path lane if the Lanes folder is missing so the
	game doesn't hard-crash when testing without it.
]]
function MapManager.Initialize()
	_lanes = {}

	local lanesFolder = workspace:FindFirstChild("Lanes")
	if lanesFolder then
		local laneFolders = lanesFolder:GetChildren()
		table.sort(laneFolders, function(a, b)
			return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
		end)

		for _, laneFolder in laneFolders do
			local laneId = tonumber(laneFolder.Name:match("%d+"))
			if not laneId then continue end

			local path: { Vector3 } = {}
			local waypointsFolder = laneFolder:FindFirstChild("Waypoints")
			if waypointsFolder then
				local points = waypointsFolder:GetChildren()
				table.sort(points, function(a, b)
					return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
				end)
				for _, part in points do
					table.insert(path, (part :: BasePart).Position)
				end
			end

			_lanes[laneId] = {
				id = laneId,
				name = laneFolder.Name,
				path = path,
				ownerId = nil,
				isCoopShared = false,
			}
		end
	end

	if next(_lanes) == nil then
		warn("MapManager.Initialize: no Lanes folder found under Workspace; using an empty stub lane")
		_lanes = {
			[1] = { id = 1, name = "Lane 1", path = {}, ownerId = nil, isCoopShared = false },
		}
	end

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
