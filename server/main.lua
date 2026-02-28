-- ============================================================
--  tst-cattle | server/main.lua
-- ============================================================

local VORPcore = nil

-- Grab the core reference as soon as possible.
-- GetCore() is the correct export name (not GetVorp).
CreateThread(function()
    while VORPcore == nil do
        VORPcore = exports.vorp_core:GetCore()
        Wait(100)
    end
end)

-- ── Helper ───────────────────────────────────────────────────
-- getCharacter returns the active character object or nil.
-- NOTE: user.getCharacter is a METHOD — it must be called with ().
local function getCharacter(source)
    if not VORPcore then return nil end
    local user = VORPcore.getUser(source)
    if not user then return nil end
    local character = user.getCharacter()   -- <-- () required
    return character
end

-- ── Deduct money ─────────────────────────────────────────────
RegisterNetEvent('tst-cattle:deductMoney')
AddEventHandler('tst-cattle:deductMoney', function(amount, reason)
    local src       = source
    local character = getCharacter(src)
    if not character then
        TriggerClientEvent('tst-cattle:moneyResult', src, false, reason)
        return
    end

    local balance = character.getMoney()
    if balance >= amount then
        character.removeMoney(amount)
        TriggerClientEvent('tst-cattle:moneyResult', src, true, reason)
    else
        TriggerClientEvent('tst-cattle:moneyResult', src, false, reason)
    end
end)

-- ── Add money ────────────────────────────────────────────────
RegisterNetEvent('tst-cattle:addMoney')
AddEventHandler('tst-cattle:addMoney', function(amount, reason)
    local src       = source
    local character = getCharacter(src)
    if not character then return end

    character.addMoney(amount)
    TriggerClientEvent('tst-cattle:moneyResult', src, true, reason)
end)
