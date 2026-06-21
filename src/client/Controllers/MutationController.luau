-- MutationController
-- Client-side mutation tree UI logic.
-- Tracks which mutations are unlocked (server is authoritative; this mirrors
-- state for instant UI feedback), handles unlock/apply requests, and drives
-- the mutation tree panel open/close.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants         = require(ReplicatedStorage.Shared.Constants)
local Types             = require(ReplicatedStorage.Shared.Types)

local TowerSelectionController = require(script.Parent.TowerSelectionController)

type MutationData = Types.MutationData

local MutationController = {}

local _network: any = nil
local _currentMP: number = Constants.STARTING_MP
local _unlocked: { [string]: boolean } = {}
local _panelOpen: boolean = false

local _toggleButton: TextButton
local _panel:        Frame
local _mpLabel:      TextLabel
local _rows:         { [string]: { frame: Frame, unlockButton: TextButton, applyButton: TextButton?, statusLabel: TextLabel } } = {}

-- Catalog mirrored from the server so the panel can list every node without
-- a round trip. Kept in sync structurally with MutationManager's CATALOG —
-- only display-relevant fields (no balance logic) live here.
local CATALOG: { MutationData } = {
	{ id = "SharpKnives", name = "Sharp Knives", description = "All towers deal +10% damage.", cost = 20, tier = 1, prerequisites = {}, targetType = "global" },
	{ id = "CrispyCrust", name = "Crispy Crust", description = "Apply to one tower for +15% range.", cost = 25, tier = 1, prerequisites = {}, targetType = "tower" },
	{ id = "SeasonedLane", name = "Seasoned Lane", description = "Apply to your lane: enemies there move -10% slower.", cost = 30, tier = 1, prerequisites = {}, targetType = "lane" },
	{ id = "DoubleSauce", name = "Double Sauce", description = "Saucier-class towers fire 20% faster, globally.", cost = 35, tier = 2, prerequisites = { "SharpKnives" }, targetType = "global" },
	{ id = "ExtraCaramelization", name = "Extra Caramelization", description = "Apply to one tower to add a 10% chance to stun on hit.", cost = 40, tier = 2, prerequisites = { "CrispyCrust" }, targetType = "tower" },
	{ id = "MergeAmplifier", name = "Merge Amplifier", description = "Enemies in the merge zone take +25% damage from all towers.", cost = 60, tier = 3, prerequisites = { "DoubleSauce", "SeasonedLane" }, targetType = "global" },
	{ id = "ChefsMasterRecipe", name = "Chef's Master Recipe", description = "Every tower's damage and fire rate are increased by 20%, globally.", cost = 100, tier = 4, prerequisites = { "MergeAmplifier", "ExtraCaramelization" }, targetType = "global" },
}

-- ── GUI construction ──────────────────────────────────────────────────────────

local function buildRow(data: MutationData, parent: Instance, order: number)
	local row = Instance.new("Frame")
	row.Name                   = data.id
	row.LayoutOrder            = order
	row.Size                   = UDim2.new(1, 0, 0, 70)
	row.BackgroundColor3       = Color3.fromRGB(45, 45, 45)
	row.BorderSizePixel        = 0
	row.Parent                 = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent        = row

	local nameLabel                    = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency   = 1
	nameLabel.Position                 = UDim2.new(0, 10, 0, 4)
	nameLabel.Size                     = UDim2.new(0.62, 0, 0, 22)
	nameLabel.Font                     = Enum.Font.GothamBold
	nameLabel.TextScaled               = true
	nameLabel.TextXAlignment           = Enum.TextXAlignment.Left
	nameLabel.TextColor3               = Color3.new(1, 1, 1)
	nameLabel.Text                     = string.format("T%d  %s", data.tier, data.name)
	nameLabel.Parent                   = row

	local descLabel                    = Instance.new("TextLabel")
	descLabel.BackgroundTransparency   = 1
	descLabel.Position                 = UDim2.new(0, 10, 0, 26)
	descLabel.Size                     = UDim2.new(0.62, 0, 0, 40)
	descLabel.Font                     = Enum.Font.Gotham
	descLabel.TextScaled               = true
	descLabel.TextWrapped              = true
	descLabel.TextXAlignment           = Enum.TextXAlignment.Left
	descLabel.TextYAlignment           = Enum.TextYAlignment.Top
	descLabel.TextColor3               = Color3.fromRGB(200, 200, 200)
	descLabel.Text                     = data.description
	descLabel.Parent                   = row

	local statusLabel                  = Instance.new("TextLabel")
	statusLabel.Name                   = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position               = UDim2.new(0.64, 0, 0, 4)
	statusLabel.Size                   = UDim2.new(0.16, 0, 0, 20)
	statusLabel.Font                   = Enum.Font.GothamBold
	statusLabel.TextScaled             = true
	statusLabel.TextColor3             = Color3.fromRGB(255, 215, 0)
	statusLabel.Text                   = ""
	statusLabel.Parent                 = row

	local unlockButton                  = Instance.new("TextButton")
	unlockButton.Name                   = "Unlock"
	unlockButton.Position               = UDim2.new(0.64, 0, 0, 28)
	unlockButton.Size                   = UDim2.new(0.34, 0, 0, 34)
	unlockButton.BackgroundColor3       = Color3.fromRGB(60, 140, 200)
	unlockButton.BorderSizePixel        = 0
	unlockButton.Font                   = Enum.Font.GothamBold
	unlockButton.TextScaled             = true
	unlockButton.TextColor3             = Color3.new(1, 1, 1)
	unlockButton.Text                   = string.format("Unlock (%d)", data.cost)
	unlockButton.Parent                 = row

	local unlockCorner = Instance.new("UICorner")
	unlockCorner.CornerRadius = UDim.new(0, 6)
	unlockCorner.Parent        = unlockButton

	unlockButton.MouseButton1Click:Connect(function()
		MutationController.RequestUnlock(data.id)
	end)

	local applyButton: TextButton? = nil
	if data.targetType ~= "global" then
		applyButton                  = Instance.new("TextButton")
		applyButton.Name             = "Apply"
		applyButton.Position         = UDim2.new(0.64, 0, 0, 28)
		applyButton.Size             = UDim2.new(0.34, 0, 0, 34)
		applyButton.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
		applyButton.BorderSizePixel  = 0
		applyButton.Font             = Enum.Font.GothamBold
		applyButton.TextScaled       = true
		applyButton.TextColor3       = Color3.new(1, 1, 1)
		applyButton.Text             = if data.targetType == "tower" then "Apply to Tower" else "Apply to Lane"
		applyButton.Visible          = false
		applyButton.Parent           = row

		local applyCorner = Instance.new("UICorner")
		applyCorner.CornerRadius = UDim.new(0, 6)
		applyCorner.Parent        = applyButton

		applyButton.MouseButton1Click:Connect(function()
			if data.targetType == "tower" then
				local target = TowerSelectionController.GetSelectedModel()
				if not target then
					warn("MutationController: select a tower before applying", data.id)
					return
				end
				MutationController.RequestApply(data.id, target)
			else
				MutationController.RequestApply(data.id, nil)
			end
		end)
	end

	_rows[data.id] = { frame = row, unlockButton = unlockButton, applyButton = applyButton, statusLabel = statusLabel }
end

local function buildPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name         = "MutationGui"
	gui.ResetOnSpawn = false

	_toggleButton                  = Instance.new("TextButton")
	_toggleButton.Name             = "MutationToggle"
	_toggleButton.AnchorPoint      = Vector2.new(1, 0)
	_toggleButton.Position         = UDim2.new(1, -10, 0, 58) -- below the lives counter (top-right) so they don't overlap
	_toggleButton.Size             = UDim2.new(0, 140, 0, 36)
	_toggleButton.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
	_toggleButton.BorderSizePixel  = 0
	_toggleButton.Font             = Enum.Font.GothamBold
	_toggleButton.TextScaled       = true
	_toggleButton.TextColor3       = Color3.new(1, 1, 1)
	_toggleButton.Text             = "Mutations (M)"
	_toggleButton.Parent           = gui

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent        = _toggleButton

	_toggleButton.MouseButton1Click:Connect(function()
		MutationController.TogglePanel()
	end)

	_panel                         = Instance.new("Frame")
	_panel.Name                    = "MutationPanel"
	_panel.AnchorPoint             = Vector2.new(1, 0)
	_panel.Position                = UDim2.new(1, -10, 0, 98)
	_panel.Size                    = UDim2.new(0, 420, 0, 480)
	_panel.BackgroundColor3        = Color3.fromRGB(25, 25, 25)
	_panel.BackgroundTransparency  = 0.05
	_panel.Visible                 = false
	_panel.Parent                  = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent        = _panel

	_mpLabel                        = Instance.new("TextLabel")
	_mpLabel.BackgroundTransparency = 1
	_mpLabel.Position               = UDim2.new(0, 10, 0, 6)
	_mpLabel.Size                   = UDim2.new(1, -20, 0, 26)
	_mpLabel.Font                   = Enum.Font.GothamBold
	_mpLabel.TextScaled             = true
	_mpLabel.TextXAlignment         = Enum.TextXAlignment.Left
	_mpLabel.TextColor3             = Color3.fromRGB(255, 215, 0)
	_mpLabel.Text                   = string.format("MP: %d", Constants.STARTING_MP)
	_mpLabel.Parent                 = _panel

	local scroll                      = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency     = 1
	scroll.Position                   = UDim2.new(0, 8, 0, 38)
	scroll.Size                       = UDim2.new(1, -16, 1, -46)
	scroll.CanvasSize                 = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize        = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness         = 6
	scroll.Parent                     = _panel

	local layout = Instance.new("UIListLayout")
	layout.Padding   = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent     = scroll

	table.sort(CATALOG, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.name < b.name
	end)

	for i, data in CATALOG do
		buildRow(data, scroll, i)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Connect all mutation-related server events and build the panel GUI.
	Must be called once from init.client.luau.
]]
function MutationController.Initialize(network: any)
	_network = network

	buildPanel()

	network.MutationUnlocked.OnClientEvent:Connect(function(mutationId: string)
		MutationController.OnMutationUnlocked(mutationId)
	end)

	network.UpdateMutationPoints.OnClientEvent:Connect(function(total: number)
		MutationController.OnMPUpdated(total)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.M then
			MutationController.TogglePanel()
		end
	end)

	MutationController._RefreshPanel()
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
		warn("MutationController: could not unlock", mutationId)
	end
end

--[[
	Request that the server applies a targeted mutation. towerModel is required
	for "tower"-type mutations and nil for "lane"-type (the server resolves the
	caller's own lane).
]]
function MutationController.RequestApply(mutationId: string, towerModel: Model?)
	local ok = _network.ApplyMutation:InvokeServer(mutationId, towerModel)
	if not ok then
		warn("MutationController: could not apply", mutationId)
	end
end

-- ── Panel UI ─────────────────────────────────────────────────────────────────

--[[
	Toggle the mutation tree panel open or closed.
	Bound to the M key and the "Mutations" HUD button.
]]
function MutationController.TogglePanel()
	_panelOpen = not _panelOpen
	_panel.Visible = _panelOpen
	MutationController._RefreshPanel()
end

--[[
	Rebuild the visual state of every tree row based on:
	  - Which mutations are unlocked (_unlocked)
	  - Current MP (_currentMP) vs. each mutation's cost
	  - Which prerequisites are satisfied
	Called automatically after every OnMutationUnlocked / OnMPUpdated / toggle.
]]
function MutationController._RefreshPanel()
	if not _panelOpen then return end

	_mpLabel.Text = string.format("MP: %d", _currentMP)

	for _, data in CATALOG do
		local row = _rows[data.id]
		if not row then continue end

		local unlocked = _unlocked[data.id] == true
		local prereqsMet = true
		for _, prereq in data.prerequisites do
			if not _unlocked[prereq] then
				prereqsMet = false
				break
			end
		end
		local affordable = _currentMP >= data.cost

		if unlocked then
			row.unlockButton.Visible = false
			row.statusLabel.Text     = "UNLOCKED"
			if row.applyButton then
				row.applyButton.Visible = true
			end
		else
			row.unlockButton.Visible              = true
			row.unlockButton.AutoButtonColor       = prereqsMet and affordable
			row.unlockButton.BackgroundTransparency = (prereqsMet and affordable) and 0 or 0.6
			row.statusLabel.Text                   = if not prereqsMet then "LOCKED" else ""
			if row.applyButton then
				row.applyButton.Visible = false
			end
		end
	end
end

return MutationController
