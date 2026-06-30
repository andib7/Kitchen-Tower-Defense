-- TowerSelectionController
-- Click-to-select for already-placed towers: highlights the selected tower
-- with a SelectionBox and shows an upgrade/sell panel with live cost info.
-- Disabled while TowerPlacementController has an active ghost so placement
-- clicks and selection clicks never fight over the same input.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants         = require(ReplicatedStorage.Shared.Constants)
local TowerCatalog      = require(ReplicatedStorage.Shared.TowerCatalog)

local TowerPlacementController = require(script.Parent.TowerPlacementController)

local TowerSelectionController = {}

local _localPlayer = Players.LocalPlayer
local _playerGui    = _localPlayer:WaitForChild("PlayerGui")
local _mouse        = _localPlayer:GetMouse()

local _selectedModel: Model?            = nil
local _levelConn:     RBXScriptConnection? = nil
local _destroyConn:   RBXScriptConnection? = nil
local _selectionBox:  SelectionBox
local _rangeRing:     Part? = nil

local _panel:          Frame
local _titleLabel:     TextLabel
local _upgradeButton:  TextButton
local _sellButton:     TextButton

-- ── Range ring ────────────────────────────────────────────────────────────────

local function destroyRangeRing()
	if _rangeRing then _rangeRing:Destroy(); _rangeRing = nil end
end

local function showRangeRing(model: Model)
	destroyRangeRing()
	local root    = model.PrimaryPart
	if not root then return end
	local towerId = model:GetAttribute("TowerId") :: string?
	local level   = (model:GetAttribute("Level") :: number?) or 1
	local data    = towerId and TowerCatalog.Towers[towerId]
	if not data then return end
	local levelData = data.levels and data.levels[level]
	local range     = (levelData and levelData.range) or data.range
	if model:GetAttribute("Mutation_CrispyCrust") then range *= 1.15 end

	local ring = Instance.new("Part")
	ring.Name          = "RangeRing"
	ring.Shape         = Enum.PartType.Cylinder
	ring.Size          = Vector3.new(0.1, range * 2, range * 2)
	ring.CFrame        = CFrame.new(root.Position.X, root.Position.Y - 1.4, root.Position.Z)
	                   * CFrame.Angles(0, 0, math.pi / 2)
	ring.Anchored      = true
	ring.CanCollide    = false
	ring.CanQuery      = false
	ring.CastShadow    = false
	ring.Material      = Enum.Material.Neon
	ring.Color         = Color3.fromRGB(100, 200, 255)
	ring.Transparency  = 0.72
	ring.Parent        = workspace
	_rangeRing = ring
end

-- ── GUI construction ──────────────────────────────────────────────────────────

local function buildPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name         = "TowerSelectionGui"
	gui.ResetOnSpawn = false

	_panel                         = Instance.new("Frame")
	_panel.Name                    = "SelectionPanel"
	_panel.AnchorPoint             = Vector2.new(0.5, 1)
	_panel.Position                = UDim2.new(0.5, 0, 1, -100)
	_panel.Size                    = UDim2.new(0, 300, 0, 80)
	_panel.BackgroundColor3        = Color3.fromRGB(30, 30, 30)
	_panel.BackgroundTransparency  = 0.1
	_panel.Visible                 = false
	_panel.Parent                  = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent        = _panel

	_titleLabel                        = Instance.new("TextLabel", _panel)
	_titleLabel.Size                   = UDim2.new(1, 0, 0, 26)
	_titleLabel.Position               = UDim2.new(0, 0, 0, 4)
	_titleLabel.BackgroundTransparency = 1
	_titleLabel.Font                   = Enum.Font.GothamBold
	_titleLabel.TextScaled             = true
	_titleLabel.TextColor3             = Color3.new(1, 1, 1)
	_titleLabel.Text                   = ""

	_upgradeButton                  = Instance.new("TextButton", _panel)
	_upgradeButton.Size             = UDim2.new(0.48, 0, 0, 40)
	_upgradeButton.Position         = UDim2.new(0.02, 0, 0, 36)
	_upgradeButton.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
	_upgradeButton.BorderSizePixel  = 0
	_upgradeButton.AutoButtonColor  = true
	_upgradeButton.Font             = Enum.Font.GothamBold
	_upgradeButton.TextScaled       = true
	_upgradeButton.TextColor3       = Color3.new(1, 1, 1)
	_upgradeButton.Text             = "Upgrade"

	local upgradeCorner = Instance.new("UICorner")
	upgradeCorner.CornerRadius = UDim.new(0, 8)
	upgradeCorner.Parent        = _upgradeButton

	_sellButton                  = Instance.new("TextButton", _panel)
	_sellButton.Size             = UDim2.new(0.48, 0, 0, 40)
	_sellButton.Position         = UDim2.new(0.5, 0, 0, 36)
	_sellButton.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
	_sellButton.BorderSizePixel  = 0
	_sellButton.AutoButtonColor  = true
	_sellButton.Font             = Enum.Font.GothamBold
	_sellButton.TextScaled       = true
	_sellButton.TextColor3       = Color3.new(1, 1, 1)
	_sellButton.Text             = "Sell"

	local sellCorner = Instance.new("UICorner")
	sellCorner.CornerRadius = UDim.new(0, 8)
	sellCorner.Parent        = _sellButton

	_upgradeButton.MouseButton1Click:Connect(function()
		if _selectedModel then
			TowerPlacementController.RequestUpgrade(_selectedModel)
		end
	end)

	_sellButton.MouseButton1Click:Connect(function()
		if _selectedModel then
			TowerPlacementController.RequestSell(_selectedModel)
		end
	end)

	_selectionBox               = Instance.new("SelectionBox")
	_selectionBox.Name          = "TowerSelectionHighlight"
	_selectionBox.Color3        = Color3.fromRGB(255, 255, 255)
	_selectionBox.LineThickness = 0.05
	_selectionBox.Parent        = workspace

	gui.Parent = _playerGui
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Build the selection UI and wire input + placement-mode handoff.
	Must be called once from init.client.luau, after TowerPlacementController
	has been initialized.
]]
function TowerSelectionController.Initialize(_network: any)
	buildPanel()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if TowerPlacementController.GetSelectedTowerId() ~= nil then return end -- placing a new tower

		local target = _mouse.Target
		local model  = target and target:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("TowerId") then
			TowerSelectionController._Select(model)
		else
			TowerSelectionController._Deselect()
		end
	end)

	-- Drop the current selection the moment placement mode starts so the
	-- selection panel never overlaps the placement ghost.
	TowerPlacementController.SetOnPlacementChanged(function(selectedTowerId: string?)
		if selectedTowerId ~= nil then
			TowerSelectionController._Deselect()
		end
	end)
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Returns the currently selected tower Model, or nil if nothing is selected.
-- Used by MutationController so "Apply to Selected Tower" knows its target.
function TowerSelectionController.GetSelectedModel(): Model?
	return _selectedModel
end

-- ── Selection ─────────────────────────────────────────────────────────────────

function TowerSelectionController._Select(model: Model)
	if _selectedModel == model then return end
	TowerSelectionController._Deselect()

	_selectedModel         = model
	_selectionBox.Adornee  = model
	_panel.Visible         = true
	showRangeRing(model)

	_levelConn = model:GetAttributeChangedSignal("Level"):Connect(function()
		TowerSelectionController._RefreshPanel()
		showRangeRing(model)
	end)
	_destroyConn = model.Destroying:Connect(function()
		TowerSelectionController._Deselect()
	end)

	TowerSelectionController._RefreshPanel()
end

function TowerSelectionController._Deselect()
	if _levelConn then _levelConn:Disconnect(); _levelConn = nil end
	if _destroyConn then _destroyConn:Disconnect(); _destroyConn = nil end
	_selectedModel        = nil
	_selectionBox.Adornee = nil
	_panel.Visible        = false
	destroyRangeRing()
end

-- Refresh the panel's title and button labels from the selected tower's
-- current level and the shared TowerCatalog data.
function TowerSelectionController._RefreshPanel()
	if not _selectedModel then return end

	local towerId = _selectedModel:GetAttribute("TowerId") :: string?
	local level    = (_selectedModel:GetAttribute("Level") :: number?) or 1
	local data     = towerId and TowerCatalog.Towers[towerId]
	if not data then return end

	_titleLabel.Text = string.format("%s — Lv %d/%d", data.name, level, data.maxLevel)

	if level >= data.maxLevel then
		_upgradeButton.Text                   = "Max Level"
		_upgradeButton.AutoButtonColor         = false
		_upgradeButton.BackgroundTransparency  = 0.6
	else
		_upgradeButton.Text                   = string.format("Upgrade (%d)", data.upgradeCost)
		_upgradeButton.AutoButtonColor         = true
		_upgradeButton.BackgroundTransparency  = 0
	end

	local totalSpent = data.cost + (level - 1) * data.upgradeCost
	local refund     = math.floor(totalSpent * Constants.SELL_REFUND_RATE)
	_sellButton.Text = string.format("Sell (+%d)", refund)
end

return TowerSelectionController
