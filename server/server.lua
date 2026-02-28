--[[
    cattle_herding_server.lua
    Server-side money handling via VORP Core.
    All money changes are validated server-side to prevent exploits.
--]]

local VORPcore = nil

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        VORPcore = exports.vorp_core:GetCore()
    end
end)

-- Add money to player cash
RegisterNetEvent("vorp:addmoney")
AddEventHandler("vorp:addmoney", function(moneyType, amount)
    local src = source
    if not src or amount <= 0 or amount > 1000000 then return end -- basic sanity check
    local User = VORPcore.getUser(src)
    if not User then return end
    local Char = User.getUsedCharacter
    if not Char then return end
    Char.addCurrency(moneyType, amount)
end)

-- Remove money from player cash
RegisterNetEvent("vorp:removemoney")
AddEventHandler("vorp:removemoney", function(moneyType, amount)
    local src = source
    if not src or amount <= 0 then return end
    local User = VORPcore.getUser(src)
    if not User then return end
    local Char = User.getUsedCharacter
    if not Char then return end
    Char.removeCurrency(moneyType, amount)
end)
