-- Kitchen Chaos: tunable game constants.
-- All balance numbers live here so designers only need to edit one file.

local Constants = {}

-- ── Economy ──────────────────────────────────────────────────────────────────
Constants.STARTING_COINS         = 150   -- per-lane coins each player starts with
Constants.SELL_REFUND_RATE       = 0.6   -- fraction of total tower spend returned on sell
Constants.BASE_WAVE_MP_BONUS     = 10    -- minimum MP bonus for clearing any wave

-- ── Lanes ────────────────────────────────────────────────────────────────────
Constants.MAX_LANES              = 4
Constants.COOP_MERGE_LANE_ID     = 0     -- pseudo lane-id for the shared merge zone

-- ── Waves ────────────────────────────────────────────────────────────────────
Constants.WAVE_INTERMISSION_SECS = 20    -- seconds between wave end and the next wave
Constants.SOLO_ENEMY_SCALE       = 0.65  -- enemy count multiplier in single-player
Constants.MAX_ENEMIES_IN_FLIGHT  = 30    -- hard cap on simultaneously active enemies per lane

-- ── Mutations ────────────────────────────────────────────────────────────────
Constants.MAX_MUTATION_TIER      = 4

-- ── Towers ───────────────────────────────────────────────────────────────────
Constants.MAX_TOWERS_PER_LANE    = 12

-- ── VS mode (not yet implemented) ────────────────────────────────────────────
Constants.VS_MODE_ENABLED        = false

return Constants
