-- Kitchen Chaos: shared tower catalog.
-- Single source of truth for tower stats and placeholder colors so
-- TowerManager (server) and the shop UI (client) can never drift apart.

local Types = require(script.Parent.Types)

type TowerData = Types.TowerData

local Towers: { [string]: TowerData } = {
	-- Sear: every hit applies a burn DoT. Level 3 ("Grease Fire") spreads
	-- the burn to nearby enemies.
	FryingPan = {
		id = "FryingPan", name = "Frying Pan",
		cost = 50,  damage = 15,  range = 6,  fireRate = 3.0,
		upgradeCost = 60,  maxLevel = 3, chefClassBonus = "SousChef",
		levels = {
			[1] = { damage = 15, range = 6.0, fireRate = 3.0, special = { burnDps = 4, burnDuration = 2 } },
			[2] = { damage = 20, range = 6.5, fireRate = 3.3, special = { burnDps = 6, burnDuration = 2.5 } },
			[3] = { damage = 28, range = 7.0, fireRate = 3.6, special = { burnDps = 9, burnDuration = 3, spreadRadius = 4 } },
		},
	},
	-- Always-AoE: every hit splashes to enemies near the target. Level 3
	-- ("Well Done") also stuns the primary target.
	Oven = {
		id = "Oven", name = "Oven",
		cost = 75,  damage = 40,  range = 12, fireRate = 0.5,
		upgradeCost = 100, maxLevel = 3, chefClassBonus = "Pastry",
		levels = {
			[1] = { damage = 40, range = 12.0, fireRate = 0.50, special = { splashRadius = 3 } },
			[2] = { damage = 55, range = 13.0, fireRate = 0.55, special = { splashRadius = 4 } },
			[3] = { damage = 75, range = 14.0, fireRate = 0.60, special = { splashRadius = 5, stunChance = 1, stunDuration = 1 } },
		},
	},
	-- Purée: every hit slows the target. Level 3 ("Deep Purée") applies a
	-- much stronger slow every 4th hit.
	Blender = {
		id = "Blender", name = "Blender",
		cost = 100, damage = 20,  range = 8,  fireRate = 2.0,
		upgradeCost = 80,  maxLevel = 3, chefClassBonus = "Saucier",
		levels = {
			[1] = { damage = 20, range = 8.0, fireRate = 2.0, special = { slowMultiplier = 0.8, slowDuration = 1.5 } },
			[2] = { damage = 27, range = 8.5, fireRate = 2.2, special = { slowMultiplier = 0.7, slowDuration = 1.75 } },
			[3] = { damage = 36, range = 9.0, fireRate = 2.4, special = {
				slowMultiplier = 0.6, slowDuration = 2,
				deepPureeEvery = 4, deepPureeMultiplier = 0.25, deepPureeDuration = 2,
			} },
		},
	},
	-- Charred: a chance to instantly execute low-health targets, scaling
	-- with level.
	GrillStation = {
		id = "GrillStation", name = "Grill Station",
		cost = 150, damage = 80,  range = 15, fireRate = 0.4,
		upgradeCost = 150, maxLevel = 3, chefClassBonus = "Grill",
		levels = {
			[1] = { damage = 80,  range = 15.0, fireRate = 0.40, special = { executeThreshold = 0.10, executeChance = 0.15 } },
			[2] = { damage = 110, range = 16.0, fireRate = 0.45, special = { executeThreshold = 0.15, executeChance = 0.25 } },
			[3] = { damage = 150, range = 17.0, fireRate = 0.50, special = { executeThreshold = 0.20, executeChance = 0.40 } },
		},
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
