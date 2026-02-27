-- ============================================================
--  vorp_cattle_herding | server/main.lua
--  Handles all economy transactions through VORP Core
-- ============================================================

local VORPcore = nil

AddEventHandler('onServerResourceStart', function(resource)
    if resource == 'vorp_core' or resource == GetCurrentResourceName() then
        VORPcore = exports.vorp_core:GetVorp()
    end
end)

-- ── Helper: get character money safely ───────────────────────
local function getCharacter(source)
    local user = VORPcore.getUser(source)
    if user then return user.getCharacter end
    return nil
end

-- ── Event: Deduct money (buy cow / hire cowboy) ──────────────
RegisterNetEvent('vorp_cattle_herding:deductMoney')
AddEventHandler('vorp_cattle_herding:deductMoney', function(amount, reason)
    local src = source
    local character = getCharacter(src)
    if not character then return end

    local balance = character.getMoney()
    if balance >= amount then
        character.removeMoney(amount)
        TriggerClientEvent('vorp_cattle_herding:moneyResult', src, true, reason)
    else
        TriggerClientEvent('vorp_cattle_herding:moneyResult', src, false, reason)
    end
end)

-- ── Event: Add money (sell herd) ─────────────────────────────
RegisterNetEvent('vorp_cattle_herding:addMoney')
AddEventHandler('vorp_cattle_herding:addMoney', function(amount, reason)
    local src = source
    local character = getCharacter(src)
    if not character then return end

    character.addMoney(amount)
    TriggerClientEvent('vorp_cattle_herding:moneyResult', src, true, reason)
end)

-- ── Event: Check balance (optional pre-check) ─────────────────
RegisterNetEvent('vorp_cattle_herding:checkBalance')
AddEventHandler('vorp_cattle_herding:checkBalance', function()
    local src = source
    local character = getCharacter(src)
    if not character then
        TriggerClientEvent('vorp_cattle_herding:balanceResult', src, 0)
        return
    end
    TriggerClientEvent('vorp_cattle_herding:balanceResult', src, character.getMoney())
end)
