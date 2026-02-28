-- ============================================================
--  tst-cattle | client/main.lua
-- ============================================================

-- ── VORP Core ────────────────────────────────────────────────
-- Obtained via the "getCore" event — same pattern used by all
-- official VORP resources and confirmed community scripts.
local Core = nil
TriggerEvent("getCore", function(c) Core = c end)

-- ── Notify ───────────────────────────────────────────────────
-- vorp:TipRight is the correct VORP client notification event.
-- From server: TriggerClientEvent("vorp:TipRight", src, msg, ms)
-- From client: TriggerEvent("vorp:TipRight", msg, ms)
local function Notify(msg)
    TriggerEvent("vorp:TipRight", msg, 4000)
end

-- ── State ────────────────────────────────────────────────────
local herd          = {}
local stragglers    = {}
local cowboys       = {}
local cowBlips      = {}
local cowboyBlips   = {}

local herdingActive    = false
local showHUD          = Config.DebugHUD
local herdSpeed        = Config.HerdWalkSpeed
local ranchReputation  = 0
local herdingSkill     = 1
local dailyMarket      = 1.0
local lastMarketDay    = -1
local lastEventTime    = 0
local lastUpdateTime   = 0
local lastCowboyUpdate = 0
local lastWageTime     = 0

-- Gate: nothing runs until the character is in the world
local playerReady  = false
local promptsReady = false

-- ── Utility ──────────────────────────────────────────────────
local function Dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

local function NearAny(locations, pos)
    for _, loc in ipairs(locations) do
        if Dist(pos, loc.coords) < loc.radius then return true end
    end
    return false
end

local function RandFloat(lo, hi) return lo + math.random() * (hi - lo) end
local function RandElem(t)       return t[math.random(1, #t)]           end

local function HerdCenter()
    local cx, cy, cz, n = 0.0, 0.0, 0.0, 0
    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) and not IsEntityDead(cow) then
            local p = GetEntityCoords(cow)
            cx = cx + p.x; cy = cy + p.y; cz = cz + p.z; n = n + 1
        end
    end
    if n > 0 then return vector3(cx/n, cy/n, cz/n) end
    return vector3(0.0, 0.0, 0.0)
end

local function Norm2(x, y)
    local l = math.sqrt(x*x + y*y)
    if l > 0 then return x/l, y/l end
    return 0.0, 0.0
end

-- ── Blips ────────────────────────────────────────────────────
-- Correct RedM native: BlipAddForCoord(blipStyleHash, vector3)
-- Name set with CreateVarString + SetBlipNameFromPlayerString
-- (confirmed from kibook's own redm-blips resource)
local function MakeStaticBlip(label, coords)
    local blip = BlipAddForCoord(`BLIP_STYLE_CAMP`, coords)
    if blip and blip ~= 0 then
        SetBlipNameFromPlayerString(blip, CreateVarString(10, "LITERAL_STRING", label))
    end
    return blip
end

local function AddCowBlip(cow)
    local blip = BlipAddForEntity(`BLIP_STYLE_OBJECTIVE`, cow)
    if blip and blip ~= 0 then
        table.insert(cowBlips, blip)
    end
end

local function ClearCowBlips()
    for _, b in ipairs(cowBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    cowBlips = {}
end

-- ── Market ───────────────────────────────────────────────────
local function UpdateMarket()
    local day = GetClockDayOfMonth()
    if day ~= lastMarketDay then
        dailyMarket   = Config.MarketMin + math.random() * (Config.MarketMax - Config.MarketMin)
        lastMarketDay = day
    end
end

-- ── Progression ──────────────────────────────────────────────
local function ChangeReputation(amt)
    ranchReputation = math.max(-100, math.min(100, ranchReputation + amt))
    if amt > 0 then Notify("Your reputation as a rancher has improved.")
    elseif amt < 0 then Notify("Your reputation has suffered.") end
end

local function ImproveHerding(amt)
    herdingSkill = math.max(1, math.min(10, herdingSkill + amt))
end

-- ── Herd speed ───────────────────────────────────────────────
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

-- ── Spawn cow ────────────────────────────────────────────────
local function SpawnCow(pos)
    local model = `A_C_COW`
    RequestModel(model)
    while not HasModelLoaded(model) do Citizen.Wait(10) end

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

-- ── Economy ──────────────────────────────────────────────────
local function BuyCow()
    TriggerServerEvent('tst-cattle:deductMoney', Config.CowBuyPrice, 'buy_cow')
end

local function SellHerd()
    if #herd == 0 then Notify("You have no cattle to sell!"); return end

    local count      = #herd
    local finalTotal = math.floor(Config.CowSellPrice * count * dailyMarket)

    if dailyMarket > 1.0 then
        Notify("Market is strong today — buyers pay more!")
    elseif dailyMarket < 1.0 then
        Notify("Market is weak today — prices are down.")
    end

    if ranchReputation > 20      then finalTotal = math.floor(finalTotal * 1.1)
    elseif ranchReputation < -10 then finalTotal = math.floor(finalTotal * 0.9) end
    finalTotal = finalTotal + herdingSkill

    for _, cow in ipairs(herd) do
        if DoesEntityExist(cow) then DeleteEntity(cow) end
    end
    herd       = {}
    stragglers = {}
    ClearCowBlips()

    TriggerServerEvent('tst-cattle:addMoney', finalTotal, 'sell_herd')
    ChangeReputation(1)
    if count > 10 then ImproveHerding(1) end
    Notify(("Sold %d cattle for $%d!"):format(count, finalTotal))
end

-- ============================================================
--  AI Cowboys
-- ============================================================
local function SpawnCowboy(pos)
    local horseModel = RandElem(Config.CowboyHorseModels)
    RequestModel(horseModel)
    while not HasModelLoaded(horseModel) do Citizen.Wait(10) end
    local horse = CreatePed(horseModel, pos.x, pos.y, pos.z, 0.0, true, true, true, true)
    SetEntityAsMissionEntity(horse, true, true)
    SetModelAsNoLongerNeeded(horseModel)

    local pedModel = `A_M_M_RANCHER_01`
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do Citizen.Wait(10) end
    local ped = CreatePed(pedModel, pos.x + 1.0, pos.y, pos.z, 0.0, true, true, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetModelAsNoLongerNeeded(pedModel)

    SetPedOntoMount(ped, horse, -1, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    GiveWeaponToPed(ped, `WEAPON_LASSO`, 1, false, false)

    local skill = math.random(1, 5)
    if skill >= 3 then GiveWeaponToPed(ped, `WEAPON_REVOLVER_CATTLEMAN`, 30, false, false) end

    local blip = BlipAddForEntity(`BLIP_STYLE_PLAYER`, ped)
    if blip and blip ~= 0 then table.insert(cowboyBlips, blip) end

    local data = {
        ped     = ped,
        horse   = horse,
        skill   = skill,
        wages   = 5.0 + (skill * 5.0),
        working = false,
        name    = RandElem(Config.CowboyNames),
    }
    table.insert(cowboys, data)
    return data
end

local function HireCowboy()
    if #cowboys >= Config.MaxCowboys then
        Notify("You already have the maximum number of cowboys!"); return
    end
    TriggerServerEvent('tst-cattle:deductMoney', Config.CowboyHirePrice, 'hire_cowboy')
end

local function DismissCowboy(targetPed)
    if #cowboys == 0 then Notify("No cowboys to dismiss!"); return end
    local removeIdx = nil
    if targetPed and targetPed ~= 0 then
        for i, cb in ipairs(cowboys) do
            if cb.ped == targetPed then removeIdx = i; break end
        end
    end
    if not removeIdx then
        local playerPos = GetEntityCoords(PlayerPedId())
        local maxRange  = IsPedOnMount(PlayerPedId()) and 50.0 or 10.0
        local closest   = math.huge
        for i, cb in ipairs(cowboys) do
            if DoesEntityExist(cb.ped) then
                local d = Dist(playerPos, GetEntityCoords(cb.ped))
                if d < closest and d < maxRange then closest = d; removeIdx = i end
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
    for i = #cowboys, 1, -1 do
        local cb = cowboys[i]
        if not DoesEntityExist(cb.ped) or IsEntityDead(cb.ped) then
            Notify("Cowboy " .. cb.name .. " is no longer available.")
            if DoesEntityExist(cb.horse) then DeleteEntity(cb.horse) end
            table.remove(cowboys, i)
        end
    end
    for _, b in ipairs(cowboyBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    cowboyBlips = {}
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped) then
            local blip = BlipAddForEntity(`BLIP_STYLE_PLAYER`, cb.ped)
            if blip and blip ~= 0 then table.insert(cowboyBlips, blip) end
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
        TriggerServerEvent('tst-cattle:deductMoney', math.floor(total), 'wages')
    end
end

local function UpdateCowboyAI()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local center    = HerdCenter()
    local hdx, hdy  = Norm2(center.x - playerPos.x, center.y - playerPos.y)

    for idx, cb in ipairs(cowboys) do
        if not DoesEntityExist(cb.ped) or IsEntityDead(cb.ped) then goto continue end
        local cbPos        = GetEntityCoords(cb.ped)
        local distToPlayer = Dist(cbPos, playerPos)

        if not herdingActive or #herd == 0 then
            if distToPlayer > 15.0 then
                local angle = ((idx - 1) * 120.0) * math.pi / 180.0
                TaskFollowNavMeshToCoord(cb.ped,
                    playerPos.x + math.cos(angle) * 12.0,
                    playerPos.y + math.sin(angle) * 12.0,
                    playerPos.z,
                    distToPlayer > 30.0 and 2.5 or 1.5, -1, 4.0, 0, 0.0)
            end
            cb.working = false; goto continue
        end

        if distToPlayer > Config.MaxHerdingDistance * 2.5 then
            cb.working = false; goto continue
        end
        cb.working = true

        local bestCow, bestScore, bestPos = nil, 0.0, nil
        for _, cow in ipairs(herd) do
            if DoesEntityExist(cow) and not IsEntityDead(cow) then
                local cp    = GetEntityCoords(cow)
                local dc    = Dist(cp, center)
                local score = dc + Dist(cp, playerPos) * 0.5
                if score > bestScore and dc > 15.0 then
                    bestScore = score; bestCow = cow; bestPos = cp
                end
            end
        end

        if bestCow then
            local pdx, pdy = Norm2(center.x - bestPos.x, center.y - bestPos.y)
            local cbSpd    = herdSpeed > 1.5 and herdSpeed * 1.1 or math.max(herdSpeed, 0.5)
            if math.random(1, 100) <= math.floor(80 * (cb.skill / 5.0)) then
                TaskFollowNavMeshToCoord(cb.ped,
                    bestPos.x - pdx * 12.0, bestPos.y - pdy * 12.0, bestPos.z,
                    cbSpd, -1, 3.0, 0, 0.0)
                if Dist(cbPos, bestPos) < 20.0 then
                    local jx = pdx + RandFloat(-0.3, 0.3)
                    local jy = pdy + RandFloat(-0.3, 0.3)
                    local jl = math.sqrt(jx*jx + jy*jy)
                    if jl > 0 then jx = jx/jl; jy = jy/jl end
                    TaskFollowNavMeshToCoord(bestCow,
                        bestPos.x + jx*15.0, bestPos.y + jy*15.0, bestPos.z,
                        herdSpeed, -1, 1.0, 0, 0.0)
                end
            end
        else
            local baseAngle = math.atan2(hdy, hdx)
            local angle     = baseAngle + ((idx - 1) * 120.0 * math.pi / 180.0)
            TaskFollowNavMeshToCoord(cb.ped,
                center.x + math.cos(angle) * 30.0,
                center.y + math.sin(angle) * 30.0,
                center.z,
                math.max(herdSpeed, 0.8), -1, 8.0, 0, 0.0)
        end
        ::continue::
    end
end

-- ── Rustlers ─────────────────────────────────────────────────
local function TriggerRustlers()
    if #herd == 0 or not Config.RustlersEnabled then return end
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local rMdl = `A_M_M_RANCHER_01`
    local hMdl = `A_C_HORSE_KENTUCKYSADDLE_BLACK`
    RequestModel(rMdl); RequestModel(hMdl)
    while not HasModelLoaded(rMdl) or not HasModelLoaded(hMdl) do Citizen.Wait(10) end
    for i = 0, Config.NumRustlers - 1 do
        local angle = i * (360.0 / Config.NumRustlers) * math.pi / 180.0
        local d     = RandFloat(180.0, 200.0)
        local sx    = playerPos.x + math.cos(angle) * d
        local sy    = playerPos.y + math.sin(angle) * d
        local gz    = GetGroundZFor_3dCoord(sx, sy, 1000.0, false) or playerPos.z
        local horse   = CreatePed(hMdl, sx, sy, gz, 0.0, true, true, true, true)
        local rustler = CreatePed(rMdl, sx, sy, gz, 0.0, true, true, true, true)
        if DoesEntityExist(horse) and DoesEntityExist(rustler) then
            RemoveAllPedWeapons(rustler, true)
            GiveWeaponToPed(rustler,
                math.random(1,2) == 1 and `WEAPON_REVOLVER_CATTLEMAN` or `WEAPON_REPEATER_CARBINE`,
                50, false, true)
            SetPedOntoMount(rustler, horse, -1, true)
            SetEntityAsMissionEntity(rustler, true, true)
            SetEntityAsMissionEntity(horse,   true, true)
            if math.random(1,2) == 1 then
                TaskCombatPed(rustler, playerPed, 0, 16)
            elseif #herd > 0 then
                TaskCombatPed(rustler, herd[math.random(1, #herd)], 0, 16)
            end
        end
    end
    SetModelAsNoLongerNeeded(rMdl); SetModelAsNoLongerNeeded(hMdl)
    Notify("Rustlers spotted! They're coming for you and your herd!")
    for _, cb in ipairs(cowboys) do
        if DoesEntityExist(cb.ped) and not IsEntityDead(cb.ped) then
            SetPedCombatAttributes(cb.ped, 5,  true)
            SetPedCombatAttributes(cb.ped, 46, true)
            SetPedCombatAttributes(cb.ped, 17, false)
            SetPedRelationshipGroupHash(cb.ped, `PLAYER`)
        end
    end
end

-- ── Herd movement ────────────────────────────────────────────
local function UpdateHerd()
    local playerPed  = PlayerPedId()
    local playerPos  = GetEntityCoords(playerPed)
    local center     = HerdCenter()
    local dx, dy     = Norm2(center.x - playerPos.x, center.y - playerPos.y)
    local herdTarget = vector3(center.x + dx*20.0, center.y + dy*20.0, center.z)

    for i = #herd, 1, -1 do
        if not DoesEntityExist(herd[i]) or IsEntityDead(herd[i]) then table.remove(herd, i) end
    end
    for i = #stragglers, 1, -1 do
        if not DoesEntityExist(stragglers[i]) or IsEntityDead(stragglers[i]) then
            table.remove(stragglers, i)
        end
    end

    local isStraggler = {}
    for _, s in ipairs(stragglers) do isStraggler[s] = true end

    for i, cow in ipairs(herd) do
        if not DoesEntityExist(cow) then goto nextcow end
        local cowPos = GetEntityCoords(cow)
        if isStraggler[cow] and math.random(1, 100) <= 10 then
            TaskFollowNavMeshToCoord(cow,
                cowPos.x + RandFloat(-20,20), cowPos.y + RandFloat(-20,20), cowPos.z,
                0.8, -1, 0.5, 0, 0.0)
            goto nextcow
        end
        if Dist(playerPos, cowPos) <= Config.MaxHerdingDistance then
            local col = (i-1) % 5
            local row = math.floor((i-1) / 5)
            TaskFollowNavMeshToCoord(cow,
                herdTarget.x + (-2.0*col - dx*row*2.0),
                herdTarget.y + (-2.0*col - dy*row*2.0),
                herdTarget.z, herdSpeed, -1, 0.5, 0, 0.0)
        else
            ClearPedTasks(cow, true, true)
        end
        ::nextcow::
    end
end

-- ── Server callbacks ─────────────────────────────────────────
RegisterNetEvent('tst-cattle:moneyResult')
AddEventHandler('tst-cattle:moneyResult', function(success, reason)
    if reason == 'buy_cow' then
        if success then
            local pos = GetEntityCoords(PlayerPedId())
            SpawnCow(vector3(pos.x + 3.0, pos.y + 3.0, pos.z))
            Notify("You bought a cow!")
        else
            Notify("Not enough money to buy a cow!")
        end
    elseif reason == 'hire_cowboy' then
        if success then
            if #cowboys >= Config.MaxCowboys then
                Notify("You already have the maximum number of cowboys!"); return
            end
            local pos = GetEntityCoords(PlayerPedId())
            local cb  = SpawnCowboy(vector3(pos.x + RandFloat(10,15), pos.y + RandFloat(10,15), pos.z))
            Notify(("Hired cowboy %s (Skill: %d/5)"):format(cb.name, cb.skill))
            ChangeReputation(1)
        else
            Notify("Not enough money to hire a cowboy!")
        end
    elseif reason == 'wages' then
        if not success then
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
--  HUD
-- ============================================================
local function DrawLine(text, x, y, scale, r, g, b)
    Citizen.InvokeNative(0x5F7F8B6D6C2C9A8E, 0)
    Citizen.InvokeNative(0x07C837F9A01C34C9, scale, scale)
    Citizen.InvokeNative(0xBE6B23FFA53FB442, r, g, b, 255)
    Citizen.InvokeNative(0x2513DFB0FB8400FE)
    Citizen.InvokeNative(0x25FBB336DF1804CB, "STRING")
    Citizen.InvokeNative(0x6C188BE134E074AA, text)
    Citizen.InvokeNative(0xCD015E5BB0D96A57, x, y)
end

local function DrawHUD()
    if not showHUD then return end
    local y, lh = 0.05, 0.025
    DrawLine(("Herding [Numpad8]: %s"):format(herdingActive and "ACTIVE" or "INACTIVE"), 0.05, y, 0.4, 255,255,255); y=y+lh
    DrawLine(("Herd: %d cattle"):format(#herd), 0.05, y, 0.4, 255,255,255); y=y+lh
    DrawLine(("Cowboys: %d/%d"):format(#cowboys, Config.MaxCowboys), 0.05, y, 0.4, 255,255,255); y=y+lh
    for i = 1, math.min(#cowboys, 3) do
        local cb = cowboys[i]
        if DoesEntityExist(cb.ped) then
            DrawLine(("  %s Skill:%d %s"):format(cb.name, cb.skill, cb.working and "WORKING" or "IDLE"),
                0.05, y, 0.35, 150,255,150); y=y+lh
        end
    end
    y=y+lh*0.5
    DrawLine(("Reputation: %d  Skill: %d"):format(ranchReputation, herdingSkill), 0.05, y, 0.4, 255,255,255); y=y+lh
    DrawLine(("Rustlers [Backspace]: %s  HUD [G]"):format(Config.RustlersEnabled and "ON" or "OFF"),
        0.05, y, 0.4, 255,200,100)
end

-- ============================================================
--  Prompts — only created after playerSpawned fires
-- ============================================================
local buyGroup, promptBuyCow, promptHireCow
local sellGroup, promptSell
local cowboyGroup, promptDismiss
local herdGroup, promptRun, promptWalk, promptStop

local function CreatePrompts()
    if promptsReady then return end
    promptsReady = true

    buyGroup      = UipromptGroup:new("Ranch Store")
    promptBuyCow  = Uiprompt:new(`INPUT_CONTEXT`,   "Buy Cow ($"     .. Config.CowBuyPrice     .. ")", buyGroup,  false)
    promptHireCow = Uiprompt:new(`INPUT_CONTEXT_B`, "Hire Cowboy ($" .. Config.CowboyHirePrice .. ")", buyGroup,  false)
    promptBuyCow:setHoldMode(true)
    promptHireCow:setHoldMode(true)

    sellGroup  = UipromptGroup:new("Cattle Market")
    promptSell = Uiprompt:new(`INPUT_CONTEXT`, "Sell Herd", sellGroup, false)
    promptSell:setHoldMode(true)

    cowboyGroup   = UipromptGroup:new("Cowboy")
    promptDismiss = Uiprompt:new(`INPUT_CONTEXT_Y`, "Dismiss Cowboy", cowboyGroup, false)
    promptDismiss:setHoldMode(true)

    herdGroup  = UipromptGroup:new("Herd")
    promptRun  = Uiprompt:new(`INPUT_FRONTEND_UP`,    "Run Herd",  herdGroup, false)
    promptWalk = Uiprompt:new(`INPUT_FRONTEND_RIGHT`, "Walk Herd", herdGroup, false)
    promptStop = Uiprompt:new(`INPUT_FRONTEND_DOWN`,  "Stop Herd", herdGroup, false)

    promptBuyCow:setOnHoldModeJustCompleted(function()  BuyCow()    end)
    promptHireCow:setOnHoldModeJustCompleted(function() HireCowboy() end)
    promptSell:setOnHoldModeJustCompleted(function()    SellHerd()  end)

    promptDismiss:setOnHoldModeJustCompleted(function()
        local target = nil
        if IsPlayerFreeAiming(PlayerId()) then
            local aimed = GetEntityPlayerIsFreeAimingAt(PlayerId())
            for _, cb in ipairs(cowboys) do
                if cb.ped == aimed then target = cb.ped; break end
            end
        end
        DismissCowboy(target)
    end)

    promptRun:setOnHoldModeJustCompleted(function()
        SetHerdSpeed(Config.HerdRunSpeed); Notify("Herd: RUN")
    end)
    promptWalk:setOnHoldModeJustCompleted(function()
        SetHerdSpeed(Config.HerdWalkSpeed); Notify("Herd: WALK")
    end)
    promptStop:setOnHoldModeJustCompleted(function()
        SetHerdSpeed(0.0); Notify("Herd: STOPPED")
    end)

    -- Must start AFTER all prompts are created
    UipromptManager:startEventThread()
end

-- ============================================================
--  playerSpawned — standard CitizenFX event, fires after
--  every spawn including after character selection in VORP.
-- ============================================================
AddEventHandler('playerSpawned', function()
    if playerReady then return end   -- only run once
    playerReady = true

    -- Short delay to let the world settle after spawn
    Citizen.SetTimeout(3000, function()
        -- Place map blips now that a character is active
        for _, loc in ipairs(Config.BuyLocations) do
            MakeStaticBlip("Buy Cattle", loc.coords)
        end
        for _, loc in ipairs(Config.SellLocations) do
            MakeStaticBlip("Sell Cattle", loc.coords)
        end

        CreatePrompts()
    end)
end)

-- ============================================================
--  Main loop
-- ============================================================
Citizen.CreateThread(function()
    math.randomseed(GetGameTimer())

    -- Sit idle until spawned and prompts are ready
    while not playerReady  do Citizen.Wait(500) end
    while not promptsReady do Citizen.Wait(100) end

    while true do
        local now       = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        local hasCattle = #herd > 0

        UpdateMarket()

        if now - lastCowboyUpdate > 5000 then
            CleanupCowboys(); HandleWages()
            lastCowboyUpdate = now
        end

        -- ── Proximity + prompt visibility ─────────────────────
        local nearBuy  = NearAny(Config.BuyLocations,  playerPos)
        local nearSell = NearAny(Config.SellLocations, playerPos)

        promptBuyCow:setEnabledAndVisible(nearBuy)
        promptHireCow:setEnabledAndVisible(nearBuy and #cowboys < Config.MaxCowboys)
        if nearBuy then buyGroup:setActiveThisFrame() end

        promptSell:setEnabledAndVisible(nearSell and hasCattle)
        if nearSell and hasCattle then
            promptSell:setText(("Sell Herd (%d cattle)"):format(#herd))
            sellGroup:setActiveThisFrame()
        end

        -- Cowboy dismiss
        local nearCowboy = false
        if IsPlayerFreeAiming(PlayerId()) then
            local aimed = GetEntityPlayerIsFreeAimingAt(PlayerId())
            for _, cb in ipairs(cowboys) do
                if cb.ped == aimed then nearCowboy = true; break end
            end
        end
        if not nearCowboy then
            local maxRange = IsPedOnMount(playerPed) and 50.0 or 10.0
            for _, cb in ipairs(cowboys) do
                if DoesEntityExist(cb.ped) and Dist(playerPos, GetEntityCoords(cb.ped)) < maxRange then
                    nearCowboy = true; break
                end
            end
        end
        promptDismiss:setEnabledAndVisible(nearCowboy)
        if nearCowboy then cowboyGroup:setActiveThisFrame() end

        -- Herd speed prompts
        promptRun:setEnabledAndVisible(herdingActive and hasCattle)
        promptWalk:setEnabledAndVisible(herdingActive and hasCattle)
        promptStop:setEnabledAndVisible(herdingActive and hasCattle)
        if herdingActive and hasCattle then herdGroup:setActiveThisFrame() end

        -- ── Keyboard toggles ───────────────────────────────────
        -- Numpad 8 (213): toggle herding
        if IsControlJustPressed(0, 213) then
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

        -- G (80): toggle HUD
        if IsControlJustPressed(0, 80) then
            showHUD = not showHUD
        end

        -- Backspace (177): toggle rustlers
        if IsControlJustPressed(0, 177) then
            Config.RustlersEnabled = not Config.RustlersEnabled
            Notify(Config.RustlersEnabled and "Rustler attacks ENABLED." or "Rustler attacks DISABLED.")
        end

        -- Numpad 2 (217): debug spawn (HUD on only)
        if showHUD and IsControlJustPressed(0, 217) then
            for _ = 1, Config.DebugSpawnCount do
                SpawnCow(vector3(
                    playerPos.x + RandFloat(-5, 5),
                    playerPos.y + RandFloat(-5, 5),
                    playerPos.z))
            end
            Notify("Spawned " .. Config.DebugSpawnCount .. " cows (debug)")
        end

        -- ── AI ticks ───────────────────────────────────────────
        if herdingActive and hasCattle then
            if now - lastUpdateTime > Config.UpdateInterval then
                UpdateHerd(); UpdateCowboyAI()
                lastUpdateTime = now
            end
            if now - lastEventTime > Config.EventCooldown * 1000 then
                lastEventTime = now
                if Config.RustlersEnabled and math.random(1,100) <= Config.EventChance then
                    TriggerRustlers()
                end
            end
        end

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
    if promptsReady then
        promptBuyCow:delete(); promptHireCow:delete()
        promptSell:delete();   promptDismiss:delete()
        promptRun:delete();    promptWalk:delete(); promptStop:delete()
    end
end)
