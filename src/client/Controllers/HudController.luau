-- HudController
-- Owns the in-game HUD ScreenGui: coin counters per lane, shared MP display,
-- wave number, and intermission / game-over overlays.
-- GUI elements are created programmatically here so no Studio-authored Gui
-- files are needed to run in Play mode.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants         = require(ReplicatedStorage.Shared.Constants)

local HudController = {}

local _localPlayer  = Players.LocalPlayer
local _playerGui    = _localPlayer:WaitForChild("PlayerGui")
local _network: any = nil

-- ── GUI construction ──────────────────────────────────────────────────────────

local _hud: ScreenGui
local _coinLabel: TextLabel
local _mpLabel:   TextLabel
local _livesLabel: TextLabel
local _waveLabel: TextLabel
local _statusLabel: TextLabel

local function buildHud()
	_hud          = Instance.new("ScreenGui")
	_hud.Name     = "KitchenChaosHud"
	_hud.ResetOnSpawn = false

	-- Coin display (top-left)
	local coinFrame      = Instance.new("Frame", _hud)
	coinFrame.Size       = UDim2.new(0, 200, 0, 40)
	coinFrame.Position   = UDim2.new(0, 10, 0, 10)
	coinFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	coinFrame.BackgroundTransparency = 0.4

	_coinLabel           = Instance.new("TextLabel", coinFrame)
	_coinLabel.Size      = UDim2.new(1, 0, 1, 0)
	_coinLabel.Text      = "Coins: 150"
	_coinLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	_coinLabel.BackgroundTransparency = 1
	_coinLabel.Font      = Enum.Font.GothamBold
	_coinLabel.TextScaled = true

	-- MP display (top-left below coins)
	local mpFrame        = Instance.new("Frame", _hud)
	mpFrame.Size         = UDim2.new(0, 200, 0, 40)
	mpFrame.Position     = UDim2.new(0, 10, 0, 58)
	mpFrame.BackgroundColor3 = Color3.fromRGB(80, 40, 120)
	mpFrame.BackgroundTransparency = 0.4

	_mpLabel             = Instance.new("TextLabel", mpFrame)
	_mpLabel.Size        = UDim2.new(1, 0, 1, 0)
	_mpLabel.Text        = "MP: 0"
	_mpLabel.TextColor3  = Color3.fromRGB(200, 130, 255)
	_mpLabel.BackgroundTransparency = 1
	_mpLabel.Font        = Enum.Font.GothamBold
	_mpLabel.TextScaled  = true

	-- Lives display (top-right)
	local livesFrame     = Instance.new("Frame", _hud)
	livesFrame.Size      = UDim2.new(0, 160, 0, 40)
	livesFrame.AnchorPoint = Vector2.new(1, 0)
	livesFrame.Position  = UDim2.new(1, -10, 0, 10)
	livesFrame.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
	livesFrame.BackgroundTransparency = 0.4

	_livesLabel           = Instance.new("TextLabel", livesFrame)
	_livesLabel.Size      = UDim2.new(1, 0, 1, 0)
	_livesLabel.Text      = string.format("Lives: %d", Constants.STARTING_LIVES)
	_livesLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	_livesLabel.BackgroundTransparency = 1
	_livesLabel.Font      = Enum.Font.GothamBold
	_livesLabel.TextScaled = true

	-- Wave counter (top-center)
	_waveLabel           = Instance.new("TextLabel", _hud)
	_waveLabel.Size      = UDim2.new(0, 200, 0, 40)
	_waveLabel.Position  = UDim2.new(0.5, -100, 0, 10)
	_waveLabel.Text      = "Wave 1"
	_waveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	_waveLabel.BackgroundTransparency = 1
	_waveLabel.Font      = Enum.Font.GothamBold
	_waveLabel.TextScaled = true

	-- Status banner (center-screen; used for wave-complete / intermission)
	_statusLabel         = Instance.new("TextLabel", _hud)
	_statusLabel.Size    = UDim2.new(0, 400, 0, 60)
	_statusLabel.Position = UDim2.new(0.5, -200, 0.4, 0)
	_statusLabel.Text    = ""
	_statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Font    = Enum.Font.GothamBold
	_statusLabel.TextScaled = true
	_statusLabel.Visible = false

	_hud.Parent = _playerGui
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--[[
	Build the HUD and hook up all server-to-client network events.
]]
function HudController.Initialize(network: any)
	_network = network
	buildHud()

	network.UpdateCoins.OnClientEvent:Connect(function(laneId: number, amount: number)
		HudController.SetCoinDisplay(laneId, amount)
	end)

	network.UpdateMutationPoints.OnClientEvent:Connect(function(total: number)
		HudController.SetMPDisplay(total)
	end)

	network.UpdateLives.OnClientEvent:Connect(function(total: number)
		HudController.SetLivesDisplay(total)
	end)

	network.WaveStarted.OnClientEvent:Connect(function(waveNumber: number)
		HudController.SetWaveDisplay(waveNumber)
	end)

	network.WaveEnded.OnClientEvent:Connect(function(waveNumber: number)
		HudController.ShowWaveComplete(waveNumber)
	end)

	network.GameOver.OnClientEvent:Connect(function()
		HudController.ShowGameOver()
	end)
end

-- ── Display updates ───────────────────────────────────────────────────────────

-- Update the coin label for the local player's lane.
function HudController.SetCoinDisplay(_laneId: number, amount: number)
	if _coinLabel then
		_coinLabel.Text = string.format("Coins: %d", amount)
	end
end

-- Update the shared MP label.
function HudController.SetMPDisplay(total: number)
	if _mpLabel then
		_mpLabel.Text = string.format("MP: %d", total)
	end
end

-- Update the shared lives label.
function HudController.SetLivesDisplay(total: number)
	if _livesLabel then
		_livesLabel.Text = string.format("Lives: %d", total)
	end
end

-- Update the wave counter label.
function HudController.SetWaveDisplay(waveNumber: number)
	if _waveLabel then
		_waveLabel.Text = string.format("Wave %d", waveNumber)
	end
end

-- Briefly show a wave-complete banner and hide it after 3 s.
function HudController.ShowWaveComplete(waveNumber: number)
	if not _statusLabel then return end
	_statusLabel.Text    = string.format("Wave %d Complete!", waveNumber)
	_statusLabel.Visible = true
	task.delay(3, function()
		if _statusLabel then _statusLabel.Visible = false end
	end)
end

-- Show the game-over overlay (replace with a proper screen when ready).
function HudController.ShowGameOver()
	if not _statusLabel then return end
	_statusLabel.Text       = "Game Over"
	_statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	_statusLabel.Visible    = true
end

return HudController
