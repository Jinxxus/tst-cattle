-- ============================================================
--  vorp_cattle_herding | client/main.lua
--  Full cattle herding job — converted from open-source C++ SHVDN
--  to RedM / VORP Lua by Claude (Anthropic)
-- ============================================================

-- ── State ────────────────────────────────────────────────────
local herd          = {}   -- All cows currently in the player's herd
local stragglers    = {}   -- Subset of herd that wanders randomly
local cowboys       = {}   -- Active AI cowboy data tables
local cowBlips      = {}
local cowboyBlips   = {}

local herdingActive = false
local showHUD       = Config.DebugHUD
local herdSpeed     = Config.HerdWalkSpeed

local ranchReputation  = 0
local herdingSkill     = 1
local dailyMarket      = 1.0
local lastMarketDay    = -1
local lastEventTime    = 0
local lastUpdateTime   = 0
local lastCowboyUpdate = 0
local lastWageTime     = 0

local notifyText  = ""
local notifyStart = 0
local notifyDur   = 3000

-- ── Utility: Notify ──────────────────────────────────────────
local function Notify(msg)
    notifyText  = msg
    notifyStart = GetGameTimer()
    -- Also push through VORP's notification if available
    TriggerEvent('vorp:notify', msg, 'info', 4000)
end

-- ── Utility: Distance ────────────────────────────────────────
local function Dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

-- ── Utility: Herd centre ─────────────────────────────────────
local function HerdCenter()
    local cx, cy, cz, n = 0.0, 0.0, 0.0, 0
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) and not IsEntityDead(cow) then
            local p = GetEntityCoords(cow)
            cx = cx + p.x; cy = cy + p.y; cz = cz + p.z
            n = n + 1
        end
    end
    if n > 0 then return vector3(cx/n, cy/n, cz/n) end
    return vector3(0.0, 0.0, 0.0)
end

-- ── Utility: Normalize 2-D vector ───────────────────────────
local function Norm2(x, y)
    local l = math.sqrt(x*x + y*y)
    if l > 0 then return x/l, y/l end
    return 0.0, 0.0
end

-- ── Utility: Random float ─────────────────────────────────────
local function RandFloat(min, max)
    return min + math.random() * (max - min)
end

-- ── Utility: Random table element ────────────────────────────
local function RandElem(t)
    return t[math.random(1, #t)]
end

-- ── Progression helpers ──────────────────────────────────────
local function ChangeReputation(amt)
    ranchReputation = math.max(-100, math.min(100, ranchReputation + amt))
    if amt > 0 then Notify("Your reputation as a rancher has improved.")
    elseif amt < 0 then Notify("Your reputation has suffered.") end
end

local function ImproveHerding(amt)
    herdingSkill = math.max(1, math.min(10, herdingSkill + amt))
end

local function UpdateMarket()
    local day = GetClockDayOfMonth()
    if day ~= lastMarketDay then
        dailyMarket  = Config.MarketMin + math.random() * (Config.MarketMax - Config.MarketMin)
        lastMarketDay = day
    end
end

-- ── Set herd speed ────────────────────────────────────────────
local function SetHerdSpeed(speed)
    herdSpeed = speed
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) and not IsEntityDead(cow) then
            local p = GetEntityCoords(cow)
            if speed > 0.0 then
                TaskFollowNavMeshToCoord(cow, p.x, p.y, p.z, speed, -1, 0.5, 0, 0.0)
            else
                ClearPedTasks(cow, true, true)
            end
        end
    end
end

-- ── Blip helpers ─────────────────────────────────────────────
local function AddCowBlip(cow)
    local blip = BlipAddForEntity(`BLIP_STYLE_OBJECTIVE`, cow)
    BlipAddModifier(blip, `blip_ambient_herd`)
    table.insert(cowBlips, blip)
end

local function ClearCowBlips()
    for _, b in ipairs(cowBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    cowBlips = {}
end

-- ── Spawn a cow and add it to the herd ───────────────────────
local function SpawnCow(pos)
    local model = `A_C_COW`
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 3000 do
        Citizen.Wait(0); t = t + 0
        -- spin until loaded (RedM streams synchronously on wait)
    end

    local cow = CreatePed(model, pos.x, pos.y, pos.z, 0.0, true, true, true, true)
    if DoesEntityExist(cow) then
        SetEntityAsMissionEntity(cow, true, true)
        SetPedFleeAttributes(cow, 0, false)
        SetBlockingOfNonTemporaryEvents(cow, false)
        table.insert(herd, cow)
        if math.random(1, 100) <= Config.StragglerChance then
            table.insert(stragglers, cow)
        end
        AddCowBlip(cow)
    end
    SetModelAsNoLongerNeeded(model)
    return cow
end

-- ── Buy a cow (server round-trip for money deduction) ────────
local function BuyCow()
    TriggerServerEvent('vorp_cattle_herding:deductMoney', Config.CowBuyPrice, 'buy_cow')
end

-- ── Sell entire herd (money added server-side) ───────────────
local function SellHerd()
    if #herd == 0 then
        Notify("You have no cattle to sell!")
        return
    end

    local count = #herd
    local baseTotal = Config.CowSellPrice * count

    -- Market fluctuation
    local finalTotal = math.floor(baseTotal * dailyMarket)
    if dailyMarket > 1.0 then
        Notify("Market is strong today — buyers pay more!")
    elseif dailyMarket < 1.0 then
        Notify("Market is weak today — prices are down.")
    end

    -- Reputation bonus/penalty
    if ranchReputation > 20 then
        finalTotal = math.floor(finalTotal * 1.1)
    elseif ranchReputation < -10 then
        finalTotal = math.floor(finalTotal * 0.9)
    end

    -- Skill bonus (flat, small)
    finalTotal = finalTotal + herdingSkill

    -- Delete cows and blips
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) then
            DeleteEntity(cow)
        end
    end
    herd      = {}
    stragglers = {}
    ClearCowBlips()

    -- Pay the player
    TriggerServerEvent('vorp_cattle_herding:addMoney', finalTotal, 'sell_herd')

    -- Progression
    ChangeReputation(1)
    if count > 10 then ImproveHerding(1) end

    Notify(("Sold %d cattle for $%d!"):format(count, finalTotal))
end

-- ============================================================
--  AI Cowboy System
-- ============================================================

local function SpawnCowboy(pos)
    -- Horse
    local horseModel = RandElem(Config.CowboyHorseModels)
    RequestModel(horseModel)
    while not HasModelLoaded(horseModel) do Citizen.Wait(0) end
    local horse = CreatePed(horseModel, pos.x, pos.y, pos.z, 0.0, true, true, true, true)
    SetEntityAsMissionEntity(horse, true, true)
    SetModelAsNoLongerNeeded(horseModel)

    -- Cowboy
    local pedModel = `A_M_M_RANCHER_01`
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do Citizen.Wait(0) end
    local ped = CreatePed(pedModel, pos.x + 1.0, pos.y, pos.z, 0.0, true, true, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetModelAsNoLongerNeeded(pedModel)

    -- Mount and configure
    SetPedOntoMount(ped, horse, -1, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)

    -- Give lasso
    GiveWeaponToPed(ped, `WEAPON_LASSO`, 1, false, false)

    local skill = math.random(1, 5)
    if skill >= 3 then
        GiveWeaponToPed(ped, `WEAPON_REVOLVER_CATTLEMAN`, 30, false, false)
    end

    -- Blip
    local blip = BlipAddForEntity(`BLIP_STYLE_PLAYER`, ped)
    BlipAddModifier(blip, `blip_ambient_companion`)
    table.insert(cowboyBlips, blip)

    local data = {
        ped       = ped,
        horse     = horse,
        skill     = skill,
        wages     = 5.0 + (skill * 5.0),
        hired     = GetGameTimer(),
        working   = false,
        name      = RandElem(Config.CowboyNames),
    }
    table.insert(cowboys, data)
    return data
end

local function HireCowboy()
    if #cowboys >= Config.MaxCowboys then
        Notify("You already have the maximum number of cowboys!")
        return
    end
    TriggerServerEvent('vorp_cattle_herding:deductMoney', Config.CowboyHirePrice, 'hire_cowboy')
end

local function DismissCowboy(targetPed)
    if #cowboys == 0 then
        Notify("No cowboys to dismiss!")
        return
    end

    local removeIdx = nil

    -- If a specific ped was passed, match it
    if targetPed and targetPed ~= 0 then
        for i, cb in ipairs(cowboys) do
            if cb.ped == targetPed then removeIdx = i; break end
        end
    end

    -- Fallback: nearest within range
    if not removeIdx then
        local playerPos = GetEntityCoords(PlayerPedId())
        local onHorse   = IsPedOnMount(PlayerPedId())
        local maxRange  = onHorse and 50.0 or 10.0
        local closest   = math.huge
        for i, cb in ipairs(cowboys) do
            if DoesEntityExist(cb.ped) then
                local d = Dist(playerPos, GetEntityCoords(cb.ped))
                if d < closest and d < maxRange then
                    closest = d; removeIdx = i
                end
            end
        end
    end

    if removeIdx then
        local cb = cowboys[removeIdx]
        Notify("Dismissed cowboy " .. cb.name)
        if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
        if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
        table.remove(cowboys, removeIdx)
    else
        Notify("No cowboy nearby to dismiss!")
    end
end

local function CleanupCowboys()
    -- Remove dead / missing
    for i = #cowboys, 1, -1 do
        local cb = cowboys[i]
        if not DoesEntityExist(cb.ped) or IsEntityDead(cb.ped) then
            Notify("Cowboy " .. cb.name .. " is no longer available.")
            if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
            table.remove(cowboys, i)
        end
    end

    -- Refresh blips
    for _, b in ipairs(cowboyBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    cowboyBlips = {}
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped) then
            local blip = BlipAddForEntity(`BLIP_STYLE_PLAYER`, cb.ped)
            BlipAddModifier(blip, `blip_ambient_companion`)
            table.insert(cowboyBlips, blip)
        end
    end
end

local function HandleWages()
    local now = GetGameTimer()
    if now - lastWageTime < Config.WageInterval * 1000 then return end
    lastWageTime = now

    local total = 0.0
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
            total = total + cb.wages
        end
    end

    if total > 0 then
        -- Attempt deduction; server responds via moneyResult event
        TriggerServerEvent('vorp_cattle_herding:deductMoney', math.floor(total), 'wages')
        Notify(("Paid $%d in cowboy wages."):format(math.floor(total)))
    end
end

-- Cowboy AI tick (called from main loop every second)
local function UpdateCowboyAI()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local center    = HerdCenter()

    local hdx, hdy = Norm2(center.x - playerPos.x, center.y - playerPos.y)

    for idx, cb in ipairs(cowboys) do
        if not DoesEntityExist(cb.ped) or IsEntityDead(cb.ped) then goto continue end

        local cbPos = GetEntityCoords(cb.ped)
        local distToPlayer = Dist(cbPos, playerPos)

        -- ── Idle / follow player when not herding ────────────
        if not herdingActive or #herd == 0 then
            if distToPlayer > 15.0 then
                local angle = ((idx - 1) * 120.0) * math.pi / 180.0
                local fp = vector3(
                    playerPos.x + math.cos(angle) * 12.0,
                    playerPos.y + math.sin(angle) * 12.0,
                    playerPos.z
                )
                local spd = distToPlayer > 30.0 and 2.5 or 1.5
                TaskFollowNavMeshToCoord(cb.ped, fp.x, fp.y, fp.z, spd, -1, 4.0, 0, 0.0)
            end
            cb.working = false
            goto continue
        end

        if distToPlayer > Config.MaxHerdingDistance * 2.5 then
            cb.working = false; goto continue
        end

        cb.working = true

        -- ── Find the most stray cow ───────────────────────────
        local bestCow, bestScore, bestPos = nil, 0.0, nil
        for _, cow in ipairs(herd) do
            if DoesEntityExist(cow) and not IsEntityDead(cow) then
                local cp  = GetEntityCoords(cow)
                local dc  = Dist(cp, center)
                local dp  = Dist(cp, playerPos)
                local score = dc + dp * 0.5
                if score > bestScore and dc > 15.0 then
                    bestScore = score; bestCow = cow; bestPos = cp
                end
            end
        end

        if bestCow then
            local pdx, pdy = Norm2(center.x - bestPos.x, center.y - bestPos.y)
            local herderTarget = vector3(
                bestPos.x - pdx * 12.0,
                bestPos.y - pdy * 12.0,
                bestPos.z
            )
            local cbSpd = herdSpeed > 1.5 and herdSpeed * 1.1 or herdSpeed
            if cbSpd == 0.0 then cbSpd = 0.5 end

            local successChance = math.floor(80 * (cb.skill / 5.0))
            if math.random(1, 100) <= successChance then
                TaskFollowNavMeshToCoord(cb.ped, herderTarget.x, herderTarget.y, herderTarget.z, cbSpd, -1, 3.0, 0, 0.0)

                if Dist(cbPos, bestPos) < 20.0 then
                    local jx = pdx + RandFloat(-0.3, 0.3)
                    local jy = pdy + RandFloat(-0.3, 0.3)
                    local jl = math.sqrt(jx*jx + jy*jy)
                    if jl > 0 then jx = jx/jl; jy = jy/jl end
                    local cowTarget = vector3(bestPos.x + jx * 15.0, bestPos.y + jy * 15.0, bestPos.z)
                    TaskFollowNavMeshToCoord(bestCow, cowTarget.x, cowTarget.y, cowTarget.z, herdSpeed, -1, 1.0, 0, 0.0)
                end
            end
        else
            -- Flank the herd
            local baseAngle = math.atan2(hdy, hdx)
            local angle     = baseAngle + ((idx - 1) * 120.0 * math.pi / 180.0)
            local fp = vector3(
                center.x + math.cos(angle) * 30.0,
                center.y + math.sin(angle) * 30.0,
                center.z
            )
            local spd = herdSpeed > 0.0 and herdSpeed or 0.8
            TaskFollowNavMeshToCoord(cb.ped, fp.x, fp.y, fp.z, spd, -1, 8.0, 0, 0.0)
        end

        ::continue::
    end
end

-- ── Rustler event ────────────────────────────────────────────
local function TriggerRustlers()
    if #herd == 0 then return end
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)

    local rustlerModel = `A_M_M_RANCHER_01`
    local horseModel   = `A_C_HORSE_KENTUCKYSADDLE_BLACK`
    RequestModel(rustlerModel)
    RequestModel(horseModel)
    while not HasModelLoaded(rustlerModel) or not HasModelLoaded(horseModel) do
        Citizen.Wait(0)
    end

    for i = 0, Config.NumRustlers - 1 do
        local angle    = i * (360.0 / Config.NumRustlers) * math.pi / 180.0
        local dist     = RandFloat(180.0, 200.0)
        local spawnPos = vector3(
            playerPos.x + math.cos(angle) * dist,
            playerPos.y + math.sin(angle) * dist,
            playerPos.z
        )
        local gz = GetGroundZFor_3dCoord(spawnPos.x, spawnPos.y, 1000.0, false)
        if gz then spawnPos = vector3(spawnPos.x, spawnPos.y, gz) end

        local horse   = CreatePed(horseModel,   spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, true, true, true)
        local rustler = CreatePed(rustlerModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, true, true, true)

        if DoesEntityExist(horse) and DoesEntityExist(rustler) then
            RemoveAllPedWeapons(rustler, true)
            local wep = math.random(1, 2) == 1 and `WEAPON_REVOLVER_CATTLEMAN` or `WEAPON_REPEATER_CARBINE`
            GiveWeaponToPed(rustler, wep, 50, false, true)
            SetPedOntoMount(rustler, horse, -1, true)
            SetEntityAsMissionEntity(rustler, true, true)
            SetEntityAsMissionEntity(horse,   true, true)

            if math.random(1, 2) == 1 then
                TaskCombatPed(rustler, playerPed, 0, 16)
            elseif #herd > 0 then
                local target = herd[math.random(1, #herd)]
                TaskCombatPed(rustler, target, 0, 16)
            end
        end
    end

    SetModelAsNoLongerNeeded(rustlerModel)
    SetModelAsNoLongerNeeded(horseModel)

    Notify("Rustlers spotted! They're coming for you and your herd!")

    -- Cowboys defend
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
            SetPedCombatAttributes(cb.ped, 5,  true)
            SetPedCombatAttributes(cb.ped, 46, true)
            SetPedCombatAttributes(cb.ped, 17, false)
            SetPedRelationshipGroupHash(cb.ped, `PLAYER`)
        end
    end
end

-- ── Herd movement tick ────────────────────────────────────────
local function UpdateHerd()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local center    = HerdCenter()

    local dx, dy = Norm2(center.x - playerPos.x, center.y - playerPos.y)
    local herdTarget = vector3(center.x + dx * 20.0, center.y + dy * 20.0, center.z)

    -- Clean dead/missing from lists
    for i = #herd, 1, -1 do
        if not DoesEntityExist(herd[i]) or IsEntityDead(herd[i]) then
            table.remove(herd, i)
        end
    end
    for i = #stragglers, 1, -1 do
        if not DoesEntityExist(stragglers[i]) or IsEntityDead(stragglers[i]) then
            table.remove(stragglers, i)
        end
    end

    -- Build straggler lookup
    local isStraggler = {}
    for _, s in ipairs(stragglers) do isStraggler[s] = true end

    for i, cow in ipairs(herd) do
        if not DoesEntityExist(cow) then goto nextcow end

        local cowPos = GetEntityCoords(cow)
        local distToPlayer = Dist(playerPos, cowPos)

        -- Stragglers occasionally wander
        if isStraggler[cow] and math.random(1, 100) <= 10 then
            local wander = vector3(
                cowPos.x + RandFloat(-20.0, 20.0),
                cowPos.y + RandFloat(-20.0, 20.0),
                cowPos.z
            )
            TaskFollowNavMeshToCoord(cow, wander.x, wander.y, wander.z, 0.8, -1, 0.5, 0, 0.0)
            goto nextcow
        end

        if distToPlayer <= Config.MaxHerdingDistance then
            local col  = (i - 1) % 5
            local row  = math.floor((i - 1) / 5)
            local ox   = -2.0 * col - dx * row * 2.0
            local oy   = -2.0 * col - dy * row * 2.0
            local target = vector3(herdTarget.x + ox, herdTarget.y + oy, herdTarget.z)
            TaskFollowNavMeshToCoord(cow, target.x, target.y, target.z, herdSpeed, -1, 0.5, 0, 0.0)
        else
            ClearPedTasks(cow, true, true)
        end

        ::nextcow::
    end
end

-- ============================================================
--  Server callbacks — money results
-- ============================================================
RegisterNetEvent('vorp_cattle_herding:moneyResult')
AddEventHandler('vorp_cattle_herding:moneyResult', function(success, reason)
    if reason == 'buy_cow' then
        if success then
            local playerPed = PlayerPedId()
            local pos       = GetEntityCoords(playerPed)
            -- Find nearest buy location to spawn near
            local spawnPos  = vector3(pos.x + 3.0, pos.y + 3.0, pos.z)
            SpawnCow(spawnPos)
            Notify("You bought a cow!")
        else
            Notify("Not enough money to buy a cow!")
        end

    elseif reason == 'hire_cowboy' then
        if success then
            if #cowboys >= Config.MaxCowboys then
                Notify("You already have the maximum number of cowboys!")
                return
            end
            local pos   = GetEntityCoords(PlayerPedId())
            local spawnPos = vector3(
                pos.x + RandFloat(10.0, 15.0),
                pos.y + RandFloat(10.0, 15.0),
                pos.z
            )
            local cb = SpawnCowboy(spawnPos)
            Notify(("Hired cowboy %s (Skill: %d/5)"):format(cb.name, cb.skill))
            ChangeReputation(1)
        else
            Notify("Not enough money to hire a cowboy!")
        end

    elseif reason == 'wages' then
        if not success then
            -- Cowboys may leave if unpaid
            for i = #cowboys, 1, -1 do
                if math.random(1, 100) <= 30 then
                    local cb = cowboys[i]
                    Notify("Cowboy " .. cb.name .. " left due to unpaid wages!")
                    if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
                    if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
                    table.remove(cowboys, i)
                    ChangeReputation(-2)
                end
            end
        end
    end
end)

-- ============================================================
--  Proximity zone helpers (replaces prompt system)
-- ============================================================
local function NearAny(locations, pos)
    for _, loc in ipairs(locations) do
        if Dist(pos, loc.coords) < loc.radius then return true, loc end
    end
    return false, nil
end

-- ============================================================
--  HUD / On-screen text
-- ============================================================
local function DrawText2D(text, x, y, scale, r, g, b, a)
    SetTextFont(0)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function DrawHUD()
    if not showHUD then return end

    local y, lh = 0.05, 0.025

    DrawText2D(("HUD(U) Herding(K): %s"):format(herdingActive and "ACTIVE" or "INACTIVE"), 0.05, y, 0.4, 255, 255, 255, 255)
    y = y + lh
    DrawText2D(("Herd size: %d"):format(#herd), 0.05, y, 0.4, 255, 255, 255, 255)
    y = y + lh
    DrawText2D(("Cowboys: %d/%d"):format(#cowboys, Config.MaxCowboys), 0.05, y, 0.4, 255, 255, 255, 255)
    y = y + lh

    for i = 1, math.min(#cowboys, 3) do
        local cb = cowboys[i]
        if DoesEntityExist(cb.ped) then
            DrawText2D(("  %s (Skill:%d %s)"):format(cb.name, cb.skill, cb.working and "WORKING" or "IDLE"),
                0.05, y, 0.35, 150, 255, 150, 255)
            y = y + lh
        end
    end

    y = y + lh * 0.5
    DrawText2D(("Reputation: %d"):format(ranchReputation), 0.05, y, 0.4, 255, 255, 255, 255)
    y = y + lh
    DrawText2D(("Herding Skill: %d"):format(herdingSkill), 0.05, y, 0.4, 255, 255, 255, 255)
    y = y + lh + lh * 0.5
    DrawText2D(("Rustlers(R): %s  Cowboys(C): ENABLED"):format(Config.RustlersEnabled and "ON" or "OFF"),
        0.05, y, 0.4, 255, 255, 255, 255)

    -- On-screen floating notification
    if notifyText ~= "" and (GetGameTimer() - notifyStart) < notifyDur then
        DrawText2D(notifyText, 0.40, 0.85, 0.5, 213, 225, 224, 255)
    end
end

-- ── Interaction hint banner (shown near locations) ────────────
local function DrawHint(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentString(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- ============================================================
--  Main loop
-- ============================================================
Citizen.CreateThread(function()
    math.randomseed(GetGameTimer())

    -- ── Map blips for buy/sell zones ─────────────────────────
    for _, loc in ipairs(Config.BuyLocations) do
        local b = BlipAddForCoords(`BLIP_STYLE_CAMP`, loc.coords.x, loc.coords.y, loc.coords.z)
        BlipAddModifier(b, `blip_ambient_herd`)
        SetBlipName(b, "Buy Cattle")
    end
    for _, loc in ipairs(Config.SellLocations) do
        local b = BlipAddForCoords(`BLIP_STYLE_CAMP`, loc.coords.x, loc.coords.y, loc.coords.z)
        BlipAddModifier(b, `blip_ambient_herd`)
        SetBlipName(b, "Sell Cattle")
    end

    while true do
        local now       = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)

        UpdateMarket()

        -- ── Cowboy maintenance every 5 seconds ───────────────
        if now - lastCowboyUpdate > 5000 then
            CleanupCowboys()
            HandleWages()
            lastCowboyUpdate = now
        end

        -- ── Proximity checks ─────────────────────────────────
        local nearBuy,  buyLoc  = NearAny(Config.BuyLocations,  playerPos)
        local nearSell, sellLoc = NearAny(Config.SellLocations, playerPos)

        -- ── Buy zone hints & interaction ─────────────────────
        if nearBuy then
            DrawHint("Press ~INPUT_CONTEXT~ to buy a cow ($" .. Config.CowBuyPrice .. ")\n" ..
                     "Press ~INPUT_CONTEXT_B~ to hire a cowboy ($" .. Config.CowboyHirePrice .. ")")

            if IsControlJustPressed(0, `INPUT_CONTEXT`) then
                BuyCow()
            end
            if IsControlJustPressed(0, `INPUT_CONTEXT_B`) then
                HireCowboy()
            end
        end

        -- ── Sell zone hints & interaction ─────────────────────
        if nearSell and #herd > 0 then
            DrawHint("Press ~INPUT_CONTEXT~ to sell your herd (" .. #herd .. " cattle)")
            if IsControlJustPressed(0, `INPUT_CONTEXT`) then
                SellHerd()
            end
        end

        -- ── Cowboy dismiss (proximity or aim) ─────────────────
        local nearCowboy, targetCowboy = false, nil
        if IsPlayerFreeAiming(PlayerId()) then
            local aimed = GetEntityPlayerIsFreeAimingAt(PlayerId())
            for _, cb in ipairs(cowboys) do
                if cb.ped == aimed then nearCowboy = true; targetCowboy = cb.ped; break end
            end
        end
        if not nearCowboy then
            local onHorse  = IsPedOnMount(playerPed)
            local maxRange = onHorse and 50.0 or 10.0
            for _, cb in ipairs(cowboys) do
                if DoesEntityExist(cb.ped) and Dist(playerPos, GetEntityCoords(cb.ped)) < maxRange then
                    nearCowboy = true; targetCowboy = cb.ped; break
                end
            end
        end
        if nearCowboy then
            DrawHint("Press ~INPUT_CONTEXT_Y~ to dismiss cowboy")
            if IsControlJustPressed(0, `INPUT_CONTEXT_Y`) then
                DismissCowboy(targetCowboy)
            end
        end

        -- ── Herding prompts when active ───────────────────────
        if herdingActive and #herd > 0 then
            DrawHint("~INPUT_FRONTEND_UP~ Run  ~INPUT_FRONTEND_RIGHT~ Walk  ~INPUT_FRONTEND_DOWN~ Stop herd")

            if IsControlJustPressed(0, `INPUT_FRONTEND_UP`) then
                SetHerdSpeed(Config.HerdRunSpeed)
                Notify("Herd speed: RUN")
            end
            if IsControlJustPressed(0, `INPUT_FRONTEND_RIGHT`) then
                SetHerdSpeed(Config.HerdWalkSpeed)
                Notify("Herd speed: WALK")
            end
            if IsControlJustPressed(0, `INPUT_FRONTEND_DOWN`) then
                SetHerdSpeed(0.0)
                Notify("Herd: STOPPED")
            end
        end

        -- ── Keyboard toggles ─────────────────────────────────
        -- U: toggle HUD
        if IsControlJustPressed(0, `INPUT_CONTEXT_SECONDARY`) then
            showHUD = not showHUD
        end

        -- K: toggle herding
        if IsControlJustPressed(0, `INPUT_SCRIPT_PAD_UP`) then
            herdingActive = not herdingActive
            if not herdingActive then
                for _, cow in ipairs(herd) do
                    if DoesEntityExist(cow) then ClearPedTasks(cow, true, true) end
                end
                Notify("Herding DEACTIVATED")
            else
                Notify("Herding ACTIVATED")
            end
        end

        -- R: toggle rustlers
        if IsControlJustPressed(0, `INPUT_SWITCH_VISOR`) then
            Config.RustlersEnabled = not Config.RustlersEnabled
            Notify(Config.RustlersEnabled and "Rustler attacks ENABLED." or "Rustler attacks DISABLED.")
        end

        -- Debug: O — spawn 10 cows around player
        if showHUD and IsControlJustPressed(0, `INPUT_SCRIPT_PAD_DOWN`) then
            for _ = 1, Config.DebugSpawnAmount do
                local offset = vector3(
                    playerPos.x + RandFloat(-5.0, 5.0),
                    playerPos.y + RandFloat(-5.0, 5.0),
                    playerPos.z
                )
                SpawnCow(offset)
            end
            Notify("Spawned " .. Config.DebugSpawnAmount .. " cows (debug)")
        end

        -- ── Herding AI tick ───────────────────────────────────
        if herdingActive and #herd > 0 then
            if now - lastUpdateTime > Config.UpdateInterval then
                UpdateHerd()
                UpdateCowboyAI()
                lastUpdateTime = now
            end
        end

        -- ── Random events ─────────────────────────────────────
        if herdingActive and #herd > 0 then
            if now - lastEventTime > Config.EventCooldown * 1000 then
                lastEventTime = now
                if math.random(1, 100) <= Config.EventChance then
                    TriggerRustlers()
                end
            end
        end

        -- ── HUD draw ──────────────────────────────────────────
        DrawHUD()

        Citizen.Wait(0)
    end
end)

-- ── Cleanup on resource stop ──────────────────────────────────
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) then DeleteEntity(cow) end
    end
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped)   then DeleteEntity(cb.ped)   end
        if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
    end
    ClearCowBlips()
    for _, b in ipairs(cowboyBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
end)
