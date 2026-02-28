-- ============================================================
--  tst-cattle | server/main.lua
-- ============================================================

local Core = nil

-- VORP core is obtained via the "getCore" event on both client and server
TriggerEvent("getCore", function(c) Core = c end)

-- ── Helper ───────────────────────────────────────────────────
local function getCharacter(source)
    if not Core then return nil end
    local user = Core.getUser(source)
    if not user then return nil end
    return user.getCharacter()   -- must be called as a function
end

-- ── Deduct money ─────────────────────────────────────────────
RegisterNetEvent('tst-cattle:deductMoney')
AddEventHandler('tst-cattle:deductMoney', function(amount, reason)
    local src  = source
    local char = getCharacter(src)
    if not char then
        TriggerClientEvent('tst-cattle:moneyResult', src, false, reason)
        return
    end
    local balance = char.getMoney()
    if balance >= amount then
        char.removeMoney(amount)
        TriggerClientEvent('tst-cattle:moneyResult', src, true, reason)
    else
        TriggerClientEvent('tst-cattle:moneyResult', src, false, reason)
    end
end)

-- ── Add money ────────────────────────────────────────────────
RegisterNetEvent('tst-cattle:addMoney')
AddEventHandler('tst-cattle:addMoney', function(amount, reason)
    local src  = source
    local char = getCharacter(src)
    if not char then return end
    char.addMoney(amount)
    TriggerClientEvent('tst-cattle:moneyResult', src, true, reason)
end)
