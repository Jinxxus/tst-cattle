-- ============================================================
--  vorp_cattle_herding | server/main.lua
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
RegisterNetEvent('vorp_cattle_herding:deductMoney')
AddEventHandler('vorp_cattle_herding:deductMoney', function(amount, reason)
    local src       = source
    local character = getCharacter(src)
    if not character then
        TriggerClientEvent('vorp_cattle_herding:moneyResult', src, false, reason)
        return
    end

    local balance = character.getMoney()
    if balance >= amount then
        character.removeMoney(amount)
        TriggerClientEvent('vorp_cattle_herding:moneyResult', src, true, reason)
    else
        TriggerClientEvent('vorp_cattle_herding:moneyResult', src, false, reason)
    end
end)

-- ── Add money ────────────────────────────────────────────────
RegisterNetEvent('vorp_cattle_herding:addMoney')
AddEventHandler('vorp_cattle_herding:addMoney', function(amount, reason)
    local src       = source
    local character = getCharacter(src)
    if not character then return end

    character.addMoney(amount)
    TriggerClientEvent('vorp_cattle_herding:moneyResult', src, true, reason)
end)
