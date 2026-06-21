-- Kitchen Chaos: client entry point.
-- Boots all controllers in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Network blocks until the server has created all RemoteEvents/Functions.
local Network = require(ReplicatedStorage.Shared.Network)

local Controllers = script.Controllers

local HudController             = require(Controllers.HudController)
local TowerPlacementController  = require(Controllers.TowerPlacementController)
local TowerSelectionController  = require(Controllers.TowerSelectionController)
local MutationController        = require(Controllers.MutationController)
local ShopController            = require(Controllers.ShopController)

HudController.Initialize(Network)
TowerPlacementController.Initialize(Network)
TowerSelectionController.Initialize(Network) -- after TowerPlacementController so SetOnPlacementChanged is wired
MutationController.Initialize(Network)
ShopController.Initialize(Network) -- after TowerPlacementController so SetOnPlacementChanged is wired
