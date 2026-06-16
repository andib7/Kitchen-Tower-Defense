-- Kitchen Chaos: shared tower catalog.
-- Single source of truth for tower stats and placeholder colors so
-- TowerManager (server) and the shop UI (client) can never drift apart.

local Types = require(script.Parent.Types)

type TowerData = Types.TowerData

local Towers: { [string]: TowerData } = {
	FryingPan = {
		id = "FryingPan", name = "Frying Pan",
		cost = 50,  damage = 15,  range = 6,  fireRate = 3.0,
		upgradeCost = 60,  maxLevel = 3, chefClassBonus = "SousChef",
	},
	Oven = {
		id = "Oven", name = "Oven",
		cost = 75,  damage = 40,  range = 12, fireRate = 0.5,
		upgradeCost = 100, maxLevel = 3, chefClassBonus = "Pastry",
	},
	Blender = {
		id = "Blender", name = "Blender",
		cost = 100, damage = 20,  range = 8,  fireRate = 2.0,
		upgradeCost = 80,  maxLevel = 3, chefClassBonus = "Saucier",
	},
	GrillStation = {
		id = "GrillStation", name = "Grill Station",
		cost = 150, damage = 80,  range = 15, fireRate = 0.4,
		upgradeCost = 150, maxLevel = 3, chefClassBonus = "Grill",
	},
}

-- Placeholder colors until real tower models are cloned from
-- ReplicatedStorage.Towers. Used for both the in-world body and shop buttons.
local Colors: { [string]: Color3 } = {
	FryingPan    = Color3.fromRGB(150, 100, 60),
	Oven         = Color3.fromRGB(80, 80, 80),
	Blender      = Color3.fromRGB(180, 180, 200),
	GrillStation = Color3.fromRGB(40, 40, 40),
}

-- Display order for the shop bar (cheapest first).
local Order: { string } = { "FryingPan", "Oven", "Blender", "GrillStation" }

return {
	Towers = Towers,
	Colors = Colors,
	Order  = Order,
}
