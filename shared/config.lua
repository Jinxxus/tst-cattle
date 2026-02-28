-- ============================================================
--  tst-cattle | shared/config.lua
-- ============================================================
Config = {}

-- Economy
Config.CowBuyPrice     = 2000
Config.CowSellPrice    = 2500
Config.CowboyHirePrice = 2500
Config.MaxCowboys      = 3
Config.WageInterval    = 300   -- seconds between wage payments

-- Buy / sell locations
Config.BuyLocations = {
    { label = "Emerald Ranch",   coords = vector3(1422.70, 295.06, 88.96),    radius = 5.0 },
    { label = "McFarlane Ranch", coords = vector3(-2373.0, -2410.0, 61.5),   radius = 5.0 },
}
Config.SellLocations = {
    { label = "Valentine",  coords = vector3(-258.03, 669.95, 113.27), radius = 40.0 },
    { label = "Blackwater", coords = vector3(-754.0, -1291.0, 43.0),  radius = 40.0 },
}

-- Herding
Config.MaxHerdingDistance = 50.0
Config.UpdateInterval     = 1000   -- ms between herd AI ticks
Config.StragglerChance    = 20     -- % chance a cow becomes a straggler
Config.HerdWalkSpeed      = 1.0
Config.HerdRunSpeed       = 2.0

-- Random events
Config.RustlersEnabled = false
Config.EventCooldown   = 900       -- seconds between event checks
Config.EventChance     = 30        -- % chance event fires at cooldown
Config.NumRustlers     = 5

-- Market
Config.MarketMin = 0.8
Config.MarketMax = 1.2

-- Debug
Config.DebugHUD        = true
Config.DebugSpawnCount = 10

-- Cowboy names
Config.CowboyNames = {
    "Jake","Buck","Tex","Cole","Wade","Clay","Luke","Hank",
    "Rusty","Dutch","Jim","Jesse","Colt","Clint","Shane",
}

-- Horse models for AI cowboys
Config.CowboyHorseModels = {
    `A_C_HORSE_KENTUCKYSADDLE_BLACK`,
    `A_C_HORSE_KENTUCKYSADDLE_CHESTNUTPINTO`,
    `A_C_HORSE_KENTUCKYSADDLE_GREY`,
    `A_C_HORSE_KENTUCKYSADDLE_SILVERBAY`,
}
