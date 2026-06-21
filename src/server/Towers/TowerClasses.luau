-- TowerClasses
-- Registry mapping a TowerCatalog id to the class that implements its
-- on-hit ability. TowerManager uses this to construct the right subclass
-- instance when a tower is placed.

return {
	FryingPan    = require(script.Parent.FryingPanTower),
	Oven         = require(script.Parent.OvenTower),
	Blender      = require(script.Parent.BlenderTower),
	GrillStation = require(script.Parent.GrillStationTower),
}
