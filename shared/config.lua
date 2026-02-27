-- ============================================================
--  vorp_cattle_herding | shared/config.lua
--  Central configuration — edit this file to customise the job
-- ============================================================

Config = {}

-- ── Economy ──────────────────────────────────────────────────
Config.CowBuyPrice     = 2000   -- Gold/cash to buy one cow
Config.CowSellPrice    = 2500   -- Base cash received when selling one cow
Config.CowboyHirePrice = 2500   -- Cost to hire one AI cowboy
Config.MaxCowboys      = 3      -- Maximum AI cowboys that can be hired at once
Config.WageInterval    = 300    -- Seconds between wage payments (5 min = 1 "game day")

-- ── Locations ────────────────────────────────────────────────
Config.BuyLocations = {
    { label = "Emerald Ranch",  coords = vector3(1422.70, 295.06, 88.96),   radius = 5.0 },
    { label = "McFarlane Ranch", coords = vector3(-2373.0, -2410.0, 61.5), radius = 5.0 },
}

Config.SellLocations = {
    { label = "Valentine",   coords = vector3(-258.03, 669.95, 113.27),  radius = 40.0 },
    { label = "Blackwater",  coords = vector3(-754.0, -1291.0, 43.0),    radius = 40.0 },
}

-- ── Herding ───────────────────────────────────────────────────
Config.MaxHerdingDistance = 50.0   -- Cows outside this range stop responding
Config.UpdateInterval     = 1000   -- Milliseconds between herd AI ticks
Config.StragglerChance    = 20     -- % chance a purchased cow becomes a straggler
Config.HerdWalkSpeed      = 1.0
Config.HerdRunSpeed       = 2.0

-- ── Random Events ─────────────────────────────────────────────
Config.RustlersEnabled    = false  -- Set true to allow rustler ambushes
Config.EventCooldown      = 900    -- Seconds between event checks (15 min)
Config.EventChance        = 30     -- % chance an event fires when the cooldown expires
Config.NumRustlers        = 5      -- How many rustlers spawn per attack

-- ── Progression ───────────────────────────────────────────────
Config.MarketFluctuation  = true   -- Enable daily buy/sell price swings
Config.MarketMin          = 0.8    -- Lowest multiplier (80 %)
Config.MarketMax          = 1.2    -- Highest multiplier (120 %)

-- ── Debug ────────────────────────────────────────────────────
Config.DebugHUD           = true   -- Show debug overlay by default (toggle with U)
Config.DebugSpawnAmount   = 10     -- Cows spawned per press of the debug key (O)

-- ── Cowboy names (randomly assigned on hire) ─────────────────
Config.CowboyNames = {
    "Jake","Buck","Tex","Cole","Wade","Clay","Luke","Hank",
    "Rusty","Dutch","Jim","Jesse","Colt","Clint","Shane"
}

-- ── Horse models used for AI cowboys ─────────────────────────
Config.CowboyHorseModels = {
    `A_C_HORSE_KENTUCKYSADDLE_BLACK`,
    `A_C_HORSE_KENTUCKYSADDLE_CHESTNUTPINTO`,
    `A_C_HORSE_KENTUCKYSADDLE_GREY`,
    `A_C_HORSE_KENTUCKYSADDLE_SILVERBAY`,
}

-- ── VORP currency type ────────────────────────────────────────
-- "money"  = in-game paper cash
-- "gold"   = gold bars
Config.CurrencyType = "money"
