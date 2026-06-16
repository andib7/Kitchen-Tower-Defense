-- ShopController
-- Bottom-of-screen tower shop bar: one button per tower in the shared
-- TowerCatalog (src/shared/TowerCatalog.luau). Clicking a button toggles
-- placement mode via TowerPlacementController; the active button gets a
-- highlight border, and unaffordable towers dim based on the player's coins.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TowerCatalog      = require(ReplicatedStorage.Shared.TowerCatalog)

local TowerPlacementController = require(script.Parent.TowerPlacementController)

local ShopController = {}

local _localPlayer = Players.LocalPlayer
local _playerGui    = _localPlayer:WaitForChild("PlayerGui")

local _currentCoins:     number = 0
local _selectedTowerId:  string? = nil
local _buttons: { [string]: TextButton } = {}

local BUTTON_SIZE = UDim2.new(0, 110, 0, 70)
local BUTTON_GAP   = 10

-- ── GUI construction ──────────────────────────────────────────────────────────

local function buildShop()
	local gui = Instance.new("ScreenGui")
	gui.Name          = "ShopGui"
	gui.ResetOnSpawn  = false

	local bar = Instance.new("Frame")
	bar.Name            = "ShopBar"
	bar.AnchorPoint     = Vector2.new(0.5, 1)
	bar.Position        = UDim2.new(0.5, 0, 1, -10)
	bar.Size            = UDim2.new(0, (#TowerCatalog.Order * 110) + (#TowerCatalog.Order - 1) * BUTTON_GAP, 0, 70)
	bar.BackgroundTransparency = 1
	bar.Parent          = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding        = UDim.new(0, BUTTON_GAP)
	layout.SortOrder       = Enum.SortOrder.LayoutOrder
	layout.Parent          = bar

	for _, towerId in TowerCatalog.Order do
		local data  = TowerCatalog.Towers[towerId]
		local color = TowerCatalog.Colors[towerId] or Color3.fromRGB(150, 150, 150)

		local button = Instance.new("TextButton")
		button.Name             = towerId
		button.Size             = BUTTON_SIZE
		button.BackgroundColor3 = color
		button.BorderSizePixel  = 0
		button.AutoButtonColor  = false
		button.Font             = Enum.Font.GothamBold
		button.TextColor3       = Color3.new(1, 1, 1)
		button.TextScaled       = true
		button.Text             = string.format("%s\n%d coins", data.name, data.cost)
		button.Parent           = bar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent        = button

		local stroke = Instance.new("UIStroke")
		stroke.Name      = "SelectedStroke"
		stroke.Thickness = 3
		stroke.Color     = Color3.fromRGB(255, 255, 255)
		stroke.Enabled   = false
		stroke.Parent     = button

		button.MouseButton1Click:Connect(function()
			ShopController._OnButtonClicked(towerId)
		end)

		_buttons[towerId] = button
	end

	gui.Parent = _playerGui
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Build the shop bar and hook up coin updates + placement-selection sync.
	Must be called once from init.client.luau, after TowerPlacementController
	has been initialized.
]]
function ShopController.Initialize(network: any)
	buildShop()

	network.UpdateCoins.OnClientEvent:Connect(function(_laneId: number, amount: number)
		_currentCoins = amount
		ShopController._RefreshAffordability()
	end)

	TowerPlacementController.SetOnPlacementChanged(function(selectedTowerId: string?)
		ShopController._OnSelectionChanged(selectedTowerId)
	end)

	ShopController._RefreshAffordability()
end

-- ── Internal ──────────────────────────────────────────────────────────────────

--[[
	Toggle placement mode for the clicked tower: selecting the already-active
	tower cancels placement instead of restarting it.
]]
function ShopController._OnButtonClicked(towerId: string)
	if _selectedTowerId == towerId then
		TowerPlacementController.CancelPlacement()
	else
		TowerPlacementController.BeginPlacement(towerId)
	end
end

-- Update which button shows the "selected" highlight border.
function ShopController._OnSelectionChanged(selectedTowerId: string?)
	_selectedTowerId = selectedTowerId
	for towerId, button in _buttons do
		local stroke = button:FindFirstChild("SelectedStroke") :: UIStroke
		stroke.Enabled = (towerId == selectedTowerId)
	end
end

-- Dim buttons the player can't currently afford.
function ShopController._RefreshAffordability()
	for towerId, button in _buttons do
		local data       = TowerCatalog.Towers[towerId]
		local affordable = data ~= nil and _currentCoins >= data.cost
		button.BackgroundTransparency = if affordable then 0 else 0.6
		button.AutoButtonColor        = affordable
	end
end

return ShopController
