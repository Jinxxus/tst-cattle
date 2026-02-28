--[[
    Cattle Herding Script - RedM / VORP Framework
    Converted from RDR2 SHVDN C++ (script.cpp)
    Prompts: kibook/uiprompt
    Starts after character spawn to avoid interfering with character selection.
--]]

-- ==================== DEPENDENCIES ====================
-- Requires: kibook/uiprompt
-- Requires: vorp_core (for money handling)

-- ==================== GLOBALS ====================
local herd           = {}          -- Active herd of cow entity handles
local spawnedCows    = {}          -- Debug-spawned cows
local cowBlips       = {}          -- Map blips for cows
local stragglerCows  = {}          -- Cows that tend to wander

-- AI Cowboy system
local activeCowboys  = {}          -- { ped, horse, skillLevel, wages, hiredTime, isWorking, lastPosition, name }
local cowboyBlips    = {}
local cowboysEnabled = true
local maxCowboys     = 3
local cowboyHirePrice = 2500

-- Herding state
local herdingActive  = false
local herdSpeed      = 1.0
local showHerdHUD    = true

-- Progression
local ranchReputation  = 0
local herdingSkill     = 1
local dailyMarketModifier = 1.0
local lastMarketDay    = -1
local rustlersEnabled  = false

-- Timers
local lastUpdateTime   = 0
local lastEventTime    = 0
local lastCowboyUpdate = 0
local lastWageTime     = 0
local eventCooldown    = 900000   -- 15 minutes
local randomEventChance = 30      -- 30%

-- Economy
local cowPrice      = 2000
local cowSellPrice  = 2500

-- Notify system
local notifyText    = ""
local notifyStart   = 0
local notifyDuration = 3000

-- Locations
local sellLocationValentine  = vector3(-258.027618, 669.947327, 113.267586)
local sellLocationBlackwater = vector3(-754.0, -1291.0, 43.0)
local buyLocationEmerald     = vector3(1422.697266, 295.063171, 88.962830)
local buyLocationMcFarlane   = vector3(-2373.0, -2410.0, 61.5)

-- Cowboy names
local cowboyNames = {
    "Jake","Buck","Tex","Cole","Wade","Clay","Luke","Hank",
    "Rusty","Dutch","Jim","Jesse","Colt","Clint","Shane"
}

-- Horse models for cowboys
local kentuckyModels = {
    joaat("A_C_HORSE_KENTUCKYSADDLE_BLACK"),
    joaat("A_C_HORSE_KENTUCKYSADDLE_CHESTNUTPINTO"),
    joaat("A_C_HORSE_KENTUCKYSADDLE_GREY"),
    joaat("A_C_HORSE_KENTUCKYSADDLE_SILVERBAY"),
}

-- Prompts (created after spawn)
local buyPrompt          = nil
local sellPrompt         = nil
local speedUpPrompt      = nil
local slowDownPrompt     = nil
local stopPrompt         = nil
local hireCowboyPrompt   = nil
local dismissCowboyPrompt = nil

local promptsCreated = false

-- ==================== VORP CORE ====================
local VORPcore = nil

AddEventHandler("onClientResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        VORPcore = exports.vorp_core:GetCore()
    end
end)

-- ==================== UTILS ====================
local function Dist(a, b)
    return #(a - b)
end

local function Notify(msg)
    notifyText  = msg
    notifyStart = GetGameTimer()
end

local function VorpNotify(msg)
    -- Use VORP notification if available, fallback to our own
    if VORPcore then
        VORPcore.NotifyRightTip(msg, 4000)
    else
        Notify(msg)
    end
end

local function GetRandomFloat(min, max)
    return min + math.random() * (max - min)
end

local function CalculateHerdCenter()
    local cx, cy, cz = 0, 0, 0
    local count = 0
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) and not IsEntityDead(cow) then
            local p = GetEntityCoords(cow)
            cx = cx + p.x; cy = cy + p.y; cz = cz + p.z
            count = count + 1
        end
    end
    if count > 0 then
        return vector3(cx / count, cy / count, cz / count)
    end
    return vector3(0, 0, 0)
end

local function NormalizeVec(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len > 0 then return vector3(v.x / len, v.y / len, v.z / len) end
    return vector3(0, 0, 0)
end

local function GetRandomOffsetFromCoords(pos, minDist, maxDist)
    local angle = GetRandomFloat(0, math.pi * 2)
    local dist  = GetRandomFloat(minDist, maxDist)
    return vector3(pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist, pos.z)
end

local function LoadModel(model)
    RequestModel(model, false)
    while not HasModelLoaded(model) do
        Citizen.Wait(0)
    end
end

-- ==================== MONEY (VORP) ====================
local function GetPlayerCash()
    if VORPcore then
        local character = VORPcore.getUser(PlayerId()).getUsedCharacter
        if character then return character.money end
    end
    return 0
end

local function AddPlayerCash(amount)
    if VORPcore then
        TriggerServerEvent("vorp:addmoney", 0, amount) -- 0 = cash
    end
end

local function RemovePlayerCash(amount)
    if VORPcore then
        TriggerServerEvent("vorp:removemoney", 0, amount)
    end
end

-- ==================== BLIPS ====================
local function CreateLocationBlip(sprite, name, pos)
    local blip = BlipAddForCoords(joaat("BLIP_STYLE_CAMP"), pos.x, pos.y, pos.z)
    SetBlipSprite(blip, sprite, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(name)
    EndTextCommandSetBlipName(blip)
    return blip
end

-- ==================== REPUTATION & SKILL ====================
local function ChangeReputation(amount)
    ranchReputation = math.max(-100, math.min(100, ranchReputation + amount))
    if amount > 0 then
        VorpNotify("Your reputation as a rancher has improved.")
    elseif amount < 0 then
        VorpNotify("Your reputation has suffered.")
    end
end

local function ImproveHerding(amount)
    herdingSkill = math.max(1, math.min(10, herdingSkill + amount))
end

local function UpdateMarketModifier()
    local day = GetClockDayOfMonth()
    if day ~= lastMarketDay then
        dailyMarketModifier = 0.8 + (math.random(0, 40) / 100.0)
        lastMarketDay = day
    end
end

-- ==================== PROMPTS (uiprompt) ====================
local function CreatePrompts()
    if promptsCreated then return end

    -- Buy prompt (hold E context)
    buyPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(buyPrompt, 0x760A9C6F) -- INPUT_CONTEXT
    UiPromptSetText(buyPrompt, CreateVarString(10, "LITERAL_STRING", "Buy Cow"))
    UiPromptSetEnabled(buyPrompt, true)
    UiPromptSetVisible(buyPrompt, false)
    UiPromptSetHoldMode(buyPrompt, 1000)
    UiPromptRegisterEnd(buyPrompt)

    -- Sell prompt
    sellPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(sellPrompt, 0x8B4B4E86) -- INPUT_CONTEXT_X
    UiPromptSetText(sellPrompt, CreateVarString(10, "LITERAL_STRING", "Sell Herd"))
    UiPromptSetEnabled(sellPrompt, true)
    UiPromptSetVisible(sellPrompt, false)
    UiPromptSetHoldMode(sellPrompt, 1000)
    UiPromptRegisterEnd(sellPrompt)

    -- Speed up herd (D-Pad Up)
    speedUpPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(speedUpPrompt, 0xA65EBAB4) -- INPUT_FRONTEND_UP
    UiPromptSetText(speedUpPrompt, CreateVarString(10, "LITERAL_STRING", "Run Herd"))
    UiPromptSetEnabled(speedUpPrompt, true)
    UiPromptSetVisible(speedUpPrompt, false)
    UiPromptSetHoldMode(speedUpPrompt, 500)
    UiPromptRegisterEnd(speedUpPrompt)

    -- Slow down herd (D-Pad Right)
    slowDownPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(slowDownPrompt, 0xDEB34313) -- INPUT_FRONTEND_RIGHT
    UiPromptSetText(slowDownPrompt, CreateVarString(10, "LITERAL_STRING", "Walk Herd"))
    UiPromptSetEnabled(slowDownPrompt, true)
    UiPromptSetVisible(slowDownPrompt, false)
    UiPromptSetHoldMode(slowDownPrompt, 500)
    UiPromptRegisterEnd(slowDownPrompt)

    -- Stop herd (D-Pad Down)
    stopPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(stopPrompt, 0x05CA7C52) -- INPUT_FRONTEND_DOWN
    UiPromptSetText(stopPrompt, CreateVarString(10, "LITERAL_STRING", "Stop Herd"))
    UiPromptSetEnabled(stopPrompt, true)
    UiPromptSetVisible(stopPrompt, false)
    UiPromptSetHoldMode(stopPrompt, 500)
    UiPromptRegisterEnd(stopPrompt)

    -- Hire cowboy
    hireCowboyPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(hireCowboyPrompt, 0x5B5A8975) -- INPUT_CONTEXT_B
    UiPromptSetText(hireCowboyPrompt, CreateVarString(10, "LITERAL_STRING", "Hire Cowboy"))
    UiPromptSetEnabled(hireCowboyPrompt, true)
    UiPromptSetVisible(hireCowboyPrompt, false)
    UiPromptSetHoldMode(hireCowboyPrompt, 1000)
    UiPromptRegisterEnd(hireCowboyPrompt)

    -- Dismiss cowboy
    dismissCowboyPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(dismissCowboyPrompt, 0xB2F377E8) -- INPUT_CONTEXT_Y
    UiPromptSetText(dismissCowboyPrompt, CreateVarString(10, "LITERAL_STRING", "Dismiss Cowboy"))
    UiPromptSetEnabled(dismissCowboyPrompt, true)
    UiPromptSetVisible(dismissCowboyPrompt, false)
    UiPromptSetHoldMode(dismissCowboyPrompt, 1000)
    UiPromptRegisterEnd(dismissCowboyPrompt)

    promptsCreated = true
end

local function SetPromptVisible(prompt, visible)
    if prompt then
        UiPromptSetVisible(prompt, visible)
        UiPromptSetEnabled(prompt, visible)
    end
end

local function PromptCompleted(prompt)
    if prompt then
        return UiPromptHasHoldModeCompleted(prompt)
    end
    return false
end

-- ==================== ECONOMY ====================
local function SpawnCow(pos)
    local model = joaat("A_C_COW")
    LoadModel(model)
    local cow = CreatePed(model, pos.x, pos.y, pos.z, 0.0, true, true, true, true)
    SetModelAsNoLongerNeeded(model)
    if DoesEntityExist(cow) then
        SetPedFleeAttributes(cow, 0, false)
        SetBlockingOfNonTemporaryEvents(cow, true)
        table.insert(herd, cow)
        -- 20% straggler chance
        if math.random(100) <= 20 then
            table.insert(stragglerCows, cow)
        end
        local blip = BlipAddForEntity(joaat("BLIP_STYLE_OBJECTIVE"), cow)
        SetBlipSprite(blip, joaat("blip_ambient_herd"), true)
        table.insert(cowBlips, blip)
    end
end

local function BuyCow()
    local cash = GetPlayerCash()
    if cash >= cowPrice then
        RemovePlayerCash(cowPrice)
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        local spawnPos
        if Dist(playerPos, buyLocationEmerald) < Dist(playerPos, buyLocationMcFarlane) then
            spawnPos = buyLocationEmerald + vector3(2, 2, 0)
        else
            spawnPos = buyLocationMcFarlane + vector3(2, 2, 0)
        end
        SpawnCow(spawnPos)
        VorpNotify("You bought a cow! ($" .. cowPrice .. ")")
    else
        VorpNotify("Not enough money to buy a cow!")
    end
end

local function AutoSellHerd()
    local soldCount = 0
    local newHerd = {}
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) then
            local cowPos = GetEntityCoords(cow)
            if Dist(cowPos, sellLocationValentine) < 40.0 or Dist(cowPos, sellLocationBlackwater) < 40.0 then
                DeleteEntity(cow)
                soldCount = soldCount + 1
            else
                table.insert(newHerd, cow)
            end
        end
    end
    herd = newHerd

    -- Clean cow blips
    for _, blip in ipairs(cowBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    cowBlips = {}

    return soldCount
end

-- ==================== HERDING ====================
local function SetHerdSpeed(speed)
    herdSpeed = speed
end

local function UpdateHerdMovement(playerPed)
    local playerPos = GetEntityCoords(playerPed)
    local herdCenter = CalculateHerdCenter()

    local dir = NormalizeVec(vector3(
        herdCenter.x - playerPos.x,
        herdCenter.y - playerPos.y,
        0
    ))

    local herdTarget = vector3(
        herdCenter.x + dir.x * 20.0,
        herdCenter.y + dir.y * 20.0,
        herdCenter.z
    )

    -- Clean dead/missing cows
    local aliveHerd = {}
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) and not IsEntityDead(cow) then
            table.insert(aliveHerd, cow)
        end
    end
    herd = aliveHerd

    for i, cow in ipairs(herd) do
        local cowPos = GetEntityCoords(cow)
        local distToPlayer = Dist(playerPos, cowPos)

        -- Check straggler
        local isStraggler = false
        for _, s in ipairs(stragglerCows) do
            if s == cow then isStraggler = true; break end
        end

        if isStraggler and math.random(100) <= 10 then
            local wanderTarget = vector3(
                cowPos.x + GetRandomFloat(-20, 20),
                cowPos.y + GetRandomFloat(-20, 20),
                cowPos.z
            )
            TaskFollowNavMeshToCoord(cow, wanderTarget.x, wanderTarget.y, wanderTarget.z,
                0.8, -1, 0.5, 0, 0.0)
        elseif distToPlayer <= 50.0 then
            local col = (i - 1) % 5
            local row = math.floor((i - 1) / 5)
            local offsetX = -2.0 * col - dir.x * row * 2.0
            local offsetY = -2.0 * col - dir.y * row * 2.0
            local target = vector3(herdTarget.x + offsetX, herdTarget.y + offsetY, herdTarget.z)
            if herdSpeed > 0 then
                TaskFollowNavMeshToCoord(cow, target.x, target.y, target.z,
                    herdSpeed, -1, 0.5, 0, 0.0)
            else
                ClearPedTasks(cow, true, true)
            end
        else
            ClearPedTasks(cow, true, true)
        end
    end
end

-- ==================== AI COWBOYS ====================
local function CreateCowboy(position)
    -- Spawn horse
    local horseModel = kentuckyModels[math.random(#kentuckyModels)]
    LoadModel(horseModel)
    local horse = CreatePed(horseModel, position.x, position.y, position.z, 0.0, true, true, true, true)
    SetModelAsNoLongerNeeded(horseModel)

    -- Spawn cowboy
    local cowboyModel = joaat("A_M_M_RANCHER_01")
    LoadModel(cowboyModel)
    local cowboyPos = position + vector3(1, 0, 0)
    local ped = CreatePed(cowboyModel, cowboyPos.x, cowboyPos.y, cowboyPos.z, 0.0, true, true, true, true)
    SetModelAsNoLongerNeeded(cowboyModel)

    -- Mount cowboy
    SetPedOntoMount(ped, horse, -1, true)

    -- Skill
    local skill = math.random(1, 5)

    -- Give weapons
    GiveWeaponToPed(ped, joaat("WEAPON_LASSO"), 1, false, false)
    if skill >= 3 then
        GiveWeaponToPed(ped, joaat("WEAPON_REVOLVER_CATTLEMAN"), 30, false, false)
    end

    -- Behavior
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)

    -- Blip
    local blip = BlipAddForEntity(joaat("BLIP_STYLE_PLAYER"), ped)
    SetBlipSprite(blip, joaat("blip_ambient_companion"), true)
    table.insert(cowboyBlips, blip)

    local cowboy = {
        ped         = ped,
        horse       = horse,
        skillLevel  = skill,
        wages       = 5.0 + (skill * 5.0),
        hiredTime   = GetGameTimer(),
        isWorking   = false,
        lastPosition = position,
        name        = cowboyNames[math.random(#cowboyNames)],
    }
    return cowboy
end

local function HireCowboy()
    if #activeCowboys >= maxCowboys then
        VorpNotify("You already have the maximum number of cowboys!")
        return
    end
    local cash = GetPlayerCash()
    if cash < cowboyHirePrice then
        VorpNotify("Not enough money to hire a cowboy!")
        return
    end
    RemovePlayerCash(cowboyHirePrice)
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local spawnPos  = GetRandomOffsetFromCoords(playerPos, 10.0, 15.0)
    local cowboy    = CreateCowboy(spawnPos)
    table.insert(activeCowboys, cowboy)
    VorpNotify("Hired cowboy " .. cowboy.name .. " (Skill: " .. cowboy.skillLevel .. "/5)")
    ChangeReputation(1)
end

local function DismissCowboy(targetPed)
    if #activeCowboys == 0 then
        VorpNotify("No cowboys to dismiss!")
        return
    end
    local removeIdx = nil
    if targetPed and targetPed ~= 0 then
        for i, cb in ipairs(activeCowboys) do
            if cb.ped == targetPed then removeIdx = i; break end
        end
    end
    if not removeIdx then
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        local onHorse   = IsPedOnMount(playerPed)
        local maxRange  = onHorse and 50.0 or 10.0
        local closest   = 999999.0
        for i, cb in ipairs(activeCowboys) do
            if DoesEntityExist(cb.ped) then
                local d = Dist(playerPos, GetEntityCoords(cb.ped))
                if d < closest and d < maxRange then
                    closest = d; removeIdx = i
                end
            end
        end
    end
    if removeIdx then
        local cb = activeCowboys[removeIdx]
        VorpNotify("Dismissed cowboy " .. cb.name)
        if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
        if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
        table.remove(activeCowboys, removeIdx)
    else
        VorpNotify("No cowboy nearby to dismiss!")
    end
end

local function CleanupCowboys()
    local alive = {}
    for _, cb in ipairs(activeCowboys) do
        if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
            table.insert(alive, cb)
        else
            VorpNotify("Cowboy " .. cb.name .. " is no longer available.")
            if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
        end
    end
    activeCowboys = alive

    -- Refresh blips
    for _, blip in ipairs(cowboyBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    cowboyBlips = {}
    for _, cb in ipairs(activeCowboys) do
        if DoesEntityExist(cb.ped) then
            local blip = BlipAddForEntity(joaat("BLIP_STYLE_PLAYER"), cb.ped)
            SetBlipSprite(blip, joaat("blip_ambient_companion"), true)
            table.insert(cowboyBlips, blip)
        end
    end
end

local function HandleCowboyWages()
    local now = GetGameTimer()
    if now - lastWageTime > 300000 then -- every 5 real minutes
        lastWageTime = now
        local total = 0
        for _, cb in ipairs(activeCowboys) do
            if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
                total = total + cb.wages
            end
        end
        if total > 0 then
            local cash = GetPlayerCash()
            if cash >= total then
                RemovePlayerCash(math.floor(total))
                VorpNotify("Paid $" .. math.floor(total) .. " in cowboy wages.")
            else
                -- Unpaid cowboys may leave
                local remaining = {}
                for _, cb in ipairs(activeCowboys) do
                    if math.random(100) <= 30 then
                        VorpNotify("Cowboy " .. cb.name .. " left due to unpaid wages!")
                        if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
                        if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
                        ChangeReputation(-2)
                    else
                        table.insert(remaining, cb)
                    end
                end
                activeCowboys = remaining
            end
        end
    end
end

local function UpdateCowboyAI()
    local playerPed  = PlayerPedId()
    local playerPos  = GetEntityCoords(playerPed)
    local herdCenter = CalculateHerdCenter()
    local herdDir    = NormalizeVec(vector3(herdCenter.x - playerPos.x, herdCenter.y - playerPos.y, 0))

    for i, cb in ipairs(activeCowboys) do
        if not DoesEntityExist(cb.ped) or IsEntityDead(cb.ped) then goto continue end

        local cbPos      = GetEntityCoords(cb.ped)
        local distToPlayer = Dist(cbPos, playerPos)

        if not herdingActive or #herd == 0 then
            -- Follow player in formation
            if distToPlayer > 15.0 then
                local angle   = ((i - 1) * 120.0) * math.pi / 180.0
                local followPos = vector3(
                    playerPos.x + math.cos(angle) * 12.0,
                    playerPos.y + math.sin(angle) * 12.0,
                    playerPos.z
                )
                local speed = distToPlayer > 30.0 and 2.5 or 1.5
                TaskFollowNavMeshToCoord(cb.ped, followPos.x, followPos.y, followPos.z, speed, -1, 4.0, 0, 0.0)
                cb.isWorking = false
            end
        else
            if distToPlayer > 125.0 then
                cb.isWorking = false
                goto continue
            end

            cb.isWorking = true

            -- Find most stray cow
            local targetCow     = nil
            local maxStray      = 0.0
            local strayPos      = nil

            for _, cow in ipairs(herd) do
                if DoesEntityExist(cow) and not IsEntityDead(cow) then
                    local cowPos = GetEntityCoords(cow)
                    local dCenter = Dist(cowPos, herdCenter)
                    local dPlayer = Dist(cowPos, playerPos)
                    local priority = dCenter + dPlayer * 0.5
                    if priority > maxStray and dCenter > 15.0 then
                        maxStray   = priority
                        targetCow  = cow
                        strayPos   = cowPos
                    end
                end
            end

            if targetCow then
                local pushDir = NormalizeVec(vector3(
                    herdCenter.x - strayPos.x,
                    herdCenter.y - strayPos.y,
                    0
                ))
                local herderPos = vector3(
                    strayPos.x - pushDir.x * 12.0,
                    strayPos.y - pushDir.y * 12.0,
                    strayPos.z
                )
                local cowboySpeed = herdSpeed
                if herdSpeed > 1.5 then cowboySpeed = herdSpeed * 1.1 end

                if math.random(100) <= math.floor(80 * (cb.skillLevel / 5.0)) then
                    TaskFollowNavMeshToCoord(cb.ped, herderPos.x, herderPos.y, herderPos.z,
                        cowboySpeed, -1, 3.0, 0, 0.0)

                    if Dist(cbPos, strayPos) < 20.0 then
                        local cowMoveDir = NormalizeVec(vector3(
                            pushDir.x + GetRandomFloat(-0.3, 0.3),
                            pushDir.y + GetRandomFloat(-0.3, 0.3),
                            0
                        ))
                        local cowTarget = vector3(
                            strayPos.x + cowMoveDir.x * 15.0,
                            strayPos.y + cowMoveDir.y * 15.0,
                            strayPos.z
                        )
                        TaskFollowNavMeshToCoord(targetCow, cowTarget.x, cowTarget.y, cowTarget.z,
                            herdSpeed, -1, 1.0, 0, 0.0)
                    end
                end
            else
                -- Flank formation
                local baseAngle   = math.atan(herdDir.y, herdDir.x)
                local cowboyAngle = baseAngle + ((i - 1) * 120.0 * math.pi / 180.0)
                local flankPos = vector3(
                    herdCenter.x + math.cos(cowboyAngle) * 30.0,
                    herdCenter.y + math.sin(cowboyAngle) * 30.0,
                    herdCenter.z
                )
                local moveSpeed = herdSpeed > 0 and herdSpeed or 0.8
                TaskFollowNavMeshToCoord(cb.ped, flankPos.x, flankPos.y, flankPos.z,
                    moveSpeed, -1, 8.0, 0, 0.0)
            end
        end

        cb.lastPosition = cbPos
        ::continue::
    end
end

-- ==================== RANDOM EVENTS ====================
local function TriggerRandomEvent(playerPed)
    if #herd == 0 then return end
    if not rustlersEnabled then return end

    local playerPos = GetEntityCoords(playerPed)
    local numRustlers = 5

    VorpNotify("Rustlers Spotted! They are coming for you and your herd!")

    for i = 1, numRustlers do
        local angle    = (i / numRustlers) * math.pi * 2
        local distance = GetRandomFloat(180, 200)
        local spawnPos = vector3(
            playerPos.x + math.cos(angle) * distance,
            playerPos.y + math.sin(angle) * distance,
            playerPos.z + 100.0
        )

        local groundZ = GetGroundZFor3dCoord(spawnPos.x, spawnPos.y, 1000.0, false)
        spawnPos = vector3(spawnPos.x, spawnPos.y, groundZ)

        local rustlerModel = joaat("A_M_M_RANCHER_01")
        local horseModel   = joaat("A_C_HORSE_KENTUCKYSADDLE_BLACK")
        LoadModel(rustlerModel)
        LoadModel(horseModel)

        local horse   = CreatePed(horseModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, true, true, true)
        local rustler = CreatePed(rustlerModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, true, true, true)

        SetModelAsNoLongerNeeded(rustlerModel)
        SetModelAsNoLongerNeeded(horseModel)

        if DoesEntityExist(horse) and DoesEntityExist(rustler) then
            RemoveAllPedWeapons(rustler, true)
            if math.random(2) == 1 then
                GiveWeaponToPed(rustler, joaat("WEAPON_REVOLVER_CATTLEMAN"), 50, false, true)
            else
                GiveWeaponToPed(rustler, joaat("WEAPON_REPEATER_CARBINE"), 50, false, true)
            end
            SetPedOntoMount(rustler, horse, -1, true)

            if math.random(100) <= 50 then
                TaskCombatPed(rustler, playerPed, 0, 16)
            else
                if #herd > 0 then
                    local targetCow = herd[math.random(#herd)]
                    TaskCombatPed(rustler, targetCow, 0, 16)
                end
            end
        end
    end

    -- Make cowboys defend
    for _, cb in ipairs(activeCowboys) do
        if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
            SetPedCombatAttributes(cb.ped, 5,  true)
            SetPedCombatAttributes(cb.ped, 46, true)
            SetPedCombatAttributes(cb.ped, 17, false)
            SetPedRelationshipGroupHash(cb.ped, joaat("PLAYER"))
        end
    end
end

-- ==================== HUD ====================
local function DrawHUD()
    -- Top-left debug overlay
    SetTextFont(1)
    SetTextScale(0.0, 0.35)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()

    local lines = {
        "[U] HUD  [K] Herding: " .. (herdingActive and "ACTIVE" or "INACTIVE"),
        "Herd Size: " .. #herd,
        "Cowboys: " .. #activeCowboys .. "/" .. maxCowboys,
        "Reputation: " .. ranchReputation,
        "Skill: " .. herdingSkill,
        "Speed: " .. herdSpeed,
        "[R] Rustlers: " .. (rustlersEnabled and "ON" or "OFF"),
        "[C] Cowboys: "  .. (cowboysEnabled and "ON" or "OFF"),
    }
    for idx, cb in ipairs(activeCowboys) do
        if idx <= 3 then
            table.insert(lines, "  " .. cb.name .. " Skill:" .. cb.skillLevel .. " " .. (cb.isWorking and "WORKING" or "IDLE"))
        end
    end

    for lineIdx, txt in ipairs(lines) do
        SetTextEntry("STRING")
        AddTextComponentSubstringPlayerName(txt)
        DrawText(0.05, 0.05 + (lineIdx - 1) * 0.025)
    end
end

-- ==================== MAIN LOOP ====================
local function StartHerdingScript()
    -- Setup map blips for buy/sell locations
    CreateLocationBlip(joaat("blip_ambient_herd"), "Sell Cows (Valentine)",  sellLocationValentine)
    CreateLocationBlip(joaat("blip_ambient_herd"), "Sell Cows (Blackwater)", sellLocationBlackwater)
    CreateLocationBlip(joaat("blip_ambient_herd"), "Buy Cows (Emerald)",     buyLocationEmerald)
    CreateLocationBlip(joaat("blip_ambient_herd"), "Buy Cows (McFarlane)",   buyLocationMcFarlane)

    -- Create uiprompts now that we're post-spawn
    CreatePrompts()

    -- Main tick loop
    Citizen.CreateThread(function()
        while true do
            local playerPed = PlayerPedId()
            local playerPos = GetEntityCoords(playerPed)
            local now       = GetGameTimer()

            UpdateMarketModifier()

            -- ===== COWBOY MAINTENANCE =====
            if now - lastCowboyUpdate > 5000 then
                CleanupCowboys()
                HandleCowboyWages()
                lastCowboyUpdate = now
            end

            -- ===== DISMISS COWBOY (aimed-at or nearby) =====
            local nearCowboy  = false
            local targetCowboy = nil

            if IsPlayerFreeAiming(PlayerId()) then
                local _, aimedPed = GetEntityPlayerIsFreeAimingAt(PlayerId())
                if aimedPed and aimedPed ~= 0 then
                    for _, cb in ipairs(activeCowboys) do
                        if cb.ped == aimedPed then
                            nearCowboy   = true
                            targetCowboy = cb.ped
                            break
                        end
                    end
                end
            end

            if not nearCowboy then
                local onHorse  = IsPedOnMount(playerPed)
                local maxRange = onHorse and 50.0 or 10.0
                for _, cb in ipairs(activeCowboys) do
                    if DoesEntityExist(cb.ped) and Dist(playerPos, GetEntityCoords(cb.ped)) < maxRange then
                        nearCowboy   = true
                        targetCowboy = cb.ped
                        break
                    end
                end
            end

            SetPromptVisible(dismissCowboyPrompt, nearCowboy)
            if PromptCompleted(dismissCowboyPrompt) then
                DismissCowboy(targetCowboy)
                Citizen.Wait(500)
            end

            -- ===== HERDING SPEED PROMPTS =====
            SetPromptVisible(speedUpPrompt,  herdingActive)
            SetPromptVisible(slowDownPrompt, herdingActive)
            SetPromptVisible(stopPrompt,     herdingActive)

            if herdingActive then
                if PromptCompleted(speedUpPrompt)  then SetHerdSpeed(2.0) end
                if PromptCompleted(slowDownPrompt)  then SetHerdSpeed(1.0) end
                if PromptCompleted(stopPrompt)      then SetHerdSpeed(0.0) end
            end

            -- ===== BUY COWS =====
            local nearBuy = Dist(playerPos, buyLocationEmerald) < 5.0
                         or Dist(playerPos, buyLocationMcFarlane) < 5.0

            SetPromptVisible(buyPrompt, nearBuy)
            if nearBuy and PromptCompleted(buyPrompt) then
                BuyCow()
                Citizen.Wait(500)
            end

            -- ===== HIRE COWBOY =====
            local canHire = nearBuy and #activeCowboys < maxCowboys
            SetPromptVisible(hireCowboyPrompt, canHire)
            if canHire and PromptCompleted(hireCowboyPrompt) then
                HireCowboy()
                Citizen.Wait(500)
            end

            -- ===== SELL COWS =====
            local nearSell = Dist(playerPos, sellLocationValentine) < 40.0
                          or Dist(playerPos, sellLocationBlackwater) < 40.0

            SetPromptVisible(sellPrompt, nearSell)
            if nearSell and PromptCompleted(sellPrompt) then
                if #herd == 0 then
                    VorpNotify("You have no cattle to sell!")
                else
                    local soldCount = AutoSellHerd()
                    if soldCount > 0 then
                        local finalPrice = math.floor(cowSellPrice * soldCount * dailyMarketModifier)

                        if dailyMarketModifier > 1.0 then
                            VorpNotify("Market is strong today, buyers pay more.")
                        elseif dailyMarketModifier < 1.0 then
                            VorpNotify("Market is weak today, prices are down.")
                        end

                        if ranchReputation > 20 then
                            finalPrice = math.floor(finalPrice * 1.1)
                        elseif ranchReputation < -10 then
                            finalPrice = math.floor(finalPrice * 0.9)
                        end
                        finalPrice = finalPrice + herdingSkill

                        AddPlayerCash(finalPrice)
                        VorpNotify("Sold " .. soldCount .. " cattle for $" .. finalPrice)
                        ChangeReputation(1)
                        ImproveHerding(soldCount > 10 and 1 or 0)
                    else
                        VorpNotify("No cattle close enough to sell!")
                    end
                end
                Citizen.Wait(500)
            end

            -- ===== KEY TOGGLES (keyboard) =====
            -- U - toggle HUD
            if IsControlJustReleased(0, 0x55) then
                showHerdHUD = not showHerdHUD
            end
            -- K - toggle herding
            if IsControlJustReleased(0, 0x4B) then
                herdingActive = not herdingActive
                if not herdingActive then
                    for _, cow in ipairs(herd) do
                        if DoesEntityExist(cow) then ClearPedTasks(cow, true, true) end
                    end
                end
            end
            -- R - toggle rustlers
            if IsControlJustReleased(0, 0x52) then
                rustlersEnabled = not rustlersEnabled
                VorpNotify("Rustler attacks " .. (rustlersEnabled and "ENABLED" or "DISABLED"))
            end
            -- C - toggle cowboys
            if IsControlJustReleased(0, 0x43) then
                cowboysEnabled = not cowboysEnabled
                if not cowboysEnabled then
                    for _, cb in ipairs(activeCowboys) do
                        if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
                        if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
                    end
                    activeCowboys = {}
                    VorpNotify("Cowboy system DISABLED.")
                else
                    VorpNotify("Cowboy system ENABLED.")
                end
            end
            -- O - debug spawn cows
            if IsControlJustReleased(0, 0x4F) then
                for _ = 1, 10 do
                    local spawnPos = GetRandomOffsetFromCoords(playerPos, 1.0, 2.5)
                    SpawnCow(spawnPos)
                end
                VorpNotify("Spawned 10 cows (debug).")
                Citizen.Wait(500)
            end

            -- ===== HERDING MOVEMENT UPDATE =====
            if herdingActive and #herd > 0 then
                if now - lastUpdateTime > 1000 then
                    UpdateHerdMovement(playerPed)
                    if cowboysEnabled then UpdateCowboyAI() end
                    lastUpdateTime = now
                end
            end

            -- ===== RANDOM EVENTS =====
            if herdingActive and #herd > 0 then
                if now - lastEventTime > eventCooldown then
                    lastEventTime = now
                    if math.random(100) <= randomEventChance then
                        TriggerRandomEvent(playerPed)
                    end
                end
            end

            -- ===== HUD =====
            if showHerdHUD then
                DrawHUD()
            end

            -- ===== CUSTOM NOTIFY =====
            if notifyText ~= "" and (now - notifyStart) < notifyDuration then
                SetTextFont(1)
                SetTextScale(0.0, 0.45)
                SetTextColour(213, 225, 224, 255)
                SetTextOutline()
                SetTextEntry("STRING")
                AddTextComponentSubstringPlayerName(notifyText)
                DrawText(0.40, 0.85)
            end

            Citizen.Wait(0)
        end
    end)
end

-- ==================== WAIT FOR CHARACTER SPAWN ====================
-- Listen for the VORP character spawn event so prompts are only
-- created after character selection is complete.

AddEventHandler("vorp:SelectedCharacter", function(charId)
    -- Small delay to let the game fully load the character
    Citizen.SetTimeout(3000, function()
        -- Get VORPcore reference if not yet set
        if not VORPcore then
            VORPcore = exports.vorp_core:GetCore()
        end
        StartHerdingScript()
    end)
end)

-- Fallback: also hook playerSpawned if the server uses it
AddEventHandler("playerSpawned", function()
    if not promptsCreated then
        Citizen.SetTimeout(3000, function()
            if not VORPcore then
                VORPcore = exports.vorp_core:GetCore()
            end
            StartHerdingScript()
        end)
    end
end)
