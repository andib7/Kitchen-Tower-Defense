-- Kitchen Chaos: shared Luau type definitions used by server and client.
-- Import with:  local Types = require(ReplicatedStorage.Shared.Types)

export type ChefClass = "SousChef" | "Pastry" | "Grill" | "Saucier"

-- A single lane on the map, owned by one player (solo) or shared (co-op).
export type Lane = {
	id: number,
	name: string,
	path: { Vector3 },     -- ordered waypoints enemies walk along
	ownerId: number?,      -- UserId of assigned player; nil = unassigned
	isCoopShared: boolean, -- true when two players share this lane
}

-- Static definition for a kitchen-appliance tower type.
export type TowerData = {
	id: string,
	name: string,
	cost: number,
	damage: number,
	range: number,
	fireRate: number,      -- attacks per second
	upgradeCost: number,
	maxLevel: number,
	chefClassBonus: ChefClass?, -- class whose chef gets a stat bonus on this tower
}

-- Static definition for a food enemy type.
export type EnemyData = {
	id: string,
	name: string,
	maxHealth: number,
	speed: number,
	reward: number,    -- lane coins awarded on kill
	mpReward: number,  -- shared Mutation Points awarded on kill
	isBoss: boolean,
}

-- Describes one wave: which enemies spawn, how fast, and the MP bonus for clearing it.
export type WaveConfig = {
	number: number,
	enemies: { { id: string, count: number, interval: number } },
	mutationPointBonus: number,   -- MP bonus awarded when the wave is fully cleared
	soloScaleMultiplier: number?, -- enemy count multiplier when only one player is active
}

-- A node in the shared mutation / augment tree.
export type MutationData = {
	id: string,
	name: string,
	description: string,
	cost: number,              -- Mutation Point cost to unlock
	tier: number,              -- tree depth; higher tiers require earlier nodes
	prerequisites: { string }, -- mutation ids that must be unlocked first
	targetType: "tower" | "global" | "lane",
}

-- An axis-aligned bounding box used for the merge zone.
export type Zone = {
	center: Vector3,
	size: Vector3,
}

return {}
