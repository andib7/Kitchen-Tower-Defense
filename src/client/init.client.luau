-- Kitchen Chaos: client entry point.
-- Boots all controllers in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Network blocks until the server has created all RemoteEvents/Functions.
local Network = require(ReplicatedStorage.Shared.Network)

local Controllers = script.Controllers

local HudController            = require(Controllers.HudController)
local TowerPlacementController = require(Controllers.TowerPlacementController)
local MutationController       = require(Controllers.MutationController)

HudController.Initialize(Network)
TowerPlacementController.Initialize(Network)
MutationController.Initialize(Network)
