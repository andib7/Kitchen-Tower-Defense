-- VisualController
-- Client-side visual feedback layer: enemy path lines, attack projectiles,
-- and colour-coded status-effect highlights on enemies (burn/slow/stun).
-- Nothing here affects gameplay — it's all cosmetic read-only display.

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local VisualController = {}

-- ── Constants ─────────────────────────────────────────────────────────────────

local STATUS_COLORS: { [string]: Color3 } = {
	burn = Color3.fromRGB(255, 80,  0),
	slow = Color3.fromRGB(50,  120, 255),
	stun = Color3.fromRGB(255, 220, 0),
}

local PROJECTILE_COLOR = Color3.fromRGB(255, 210, 60) -- warm yellow-gold
local PATH_COLOR       = Color3.fromRGB(255, 140, 40) -- orange trail
local PATH_THICKNESS   = 0.35                          -- studs

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Draw a thin neon cylinder between two world points, parented to `parent`.
local function drawSegment(a: Vector3, b: Vector3, parent: Instance): Part
	local mid    = (a + b) / 2
	local length = (b - a).Magnitude
	local part   = Instance.new("Part")
	part.Size        = Vector3.new(PATH_THICKNESS, PATH_THICKNESS, length)
	part.CFrame      = CFrame.lookAt(mid, b)
	part.Anchored    = true
	part.CanCollide  = false
	part.CanQuery    = false
	part.CastShadow  = false
	part.Material    = Enum.Material.Neon
	part.Color       = PATH_COLOR
	part.Transparency = 0.45
	part.Parent      = parent
	return part
end

-- ── Lane paths ────────────────────────────────────────────────────────────────

local function drawLanePaths()
	local lanesFolder = workspace:FindFirstChild("Lanes")
	if not lanesFolder then return end

	local container = Instance.new("Folder")
	container.Name   = "PathVisuals"
	container.Parent = workspace

	for _, laneFolder in lanesFolder:GetChildren() do
		local waypointsFolder = laneFolder:FindFirstChild("Waypoints")
		if not waypointsFolder then continue end

		local points: { BasePart } = {}
		for _, part in waypointsFolder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(points, part)
			end
		end
		table.sort(points, function(a, b)
			return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
		end)

		for i = 1, #points - 1 do
			drawSegment(points[i].Position, points[i + 1].Position, container)
		end
	end
end

-- ── Projectiles ───────────────────────────────────────────────────────────────

local function spawnProjectile(towerModel: Model, hitPosition: Vector3)
	local root = towerModel:FindFirstChildWhichIsA("BasePart", true)
	if not root then return end

	local origin = root.Position

	local proj = Instance.new("Part")
	proj.Name        = "Projectile"
	proj.Shape       = Enum.PartType.Ball
	proj.Size        = Vector3.new(0.4, 0.4, 0.4)
	proj.Position    = origin
	proj.Anchored    = true
	proj.CanCollide  = false
	proj.CanQuery    = false
	proj.CastShadow  = false
	proj.Material    = Enum.Material.Neon
	proj.Color       = PROJECTILE_COLOR
	proj.Parent      = workspace

	local tween = TweenService:Create(
		proj,
		TweenInfo.new(0.1, Enum.EasingStyle.Linear),
		{ Position = hitPosition }
	)
	tween.Completed:Connect(function()
		proj:Destroy()
	end)
	tween:Play()
end

-- ── Enemy status highlights ───────────────────────────────────────────────────

-- Per-enemy tracking: model → { highlight: Highlight, conn: RBXScriptConnection }
local _enemyData: { [Model]: { highlight: Highlight, conn: RBXScriptConnection } } = {}

local function applyHighlight(model: Model, status: string)
	local entry = _enemyData[model]
	if not entry then return end

	local color = STATUS_COLORS[status]
	if color then
		entry.highlight.FillColor    = color
		entry.highlight.OutlineColor = color
		entry.highlight.Enabled      = true
	else
		entry.highlight.Enabled = false
	end
end

local function trackEnemy(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency    = 0.55
	highlight.OutlineTransparency = 0.1
	highlight.Enabled             = false
	highlight.Parent              = model

	local conn = model:GetAttributeChangedSignal("Status"):Connect(function()
		applyHighlight(model, model:GetAttribute("Status") or "")
	end)

	_enemyData[model] = { highlight = highlight, conn = conn }
end

local function untrackEnemy(model: Model)
	local entry = _enemyData[model]
	if not entry then return end
	entry.conn:Disconnect()
	_enemyData[model] = nil
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function VisualController.Initialize(network: any)
	-- Draw lane paths once; they never change at runtime.
	task.defer(drawLanePaths)

	-- Attack projectiles
	network.TowerFired.OnClientEvent:Connect(function(towerModel: Model, hitPosition: Vector3)
		if towerModel and towerModel.Parent then
			spawnProjectile(towerModel, hitPosition)
		end
	end)

	-- Enemy status highlights
	network.EnemySpawned.OnClientEvent:Connect(function(_enemyId: string, _laneId: number, model: Model)
		if model and model.Parent then
			trackEnemy(model)
		end
	end)

	network.EnemyDied.OnClientEvent:Connect(function(model: Model, _laneId: number)
		untrackEnemy(model)
	end)
end

return VisualController
