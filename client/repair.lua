-- lunar-vehicles — qb-target engine repairs
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only
--
-- ps-ui Circle → progressbar → consume kit.
-- advancedrepairkit = mechanic rebuild. repairkit = anyone, limp home.

local QBCore = exports['qb-core']:GetCoreObject()
local repairing = false

local function notify(msg, kind)
    QBCore.Functions.Notify(msg, kind or 'primary')
end

local function rootCfg()
    return Config.Repairs or Config.EngineRepair or {}
end

local function kitCfg(kind)
    local root = rootCfg()
    if kind == 'basic' then
        return root.basic or {}
    end
    return root.advanced or root
end

local function jobOk(c)
    if not c.requireJob or c.requireJob == false then return true end
    local job = QBCore.Functions.GetPlayerData().job
    if not job then return false end
    if type(c.requireJob) == 'string' and job.name ~= c.requireJob then return false end
    if c.requireDuty and job.onduty == false then return false end
    return true
end

local function hasItem(itemName)
    if not itemName then return false end
    local ok, result = pcall(function()
        return exports['qb-inventory']:HasItem(itemName, 1)
    end)
    if ok and result then return true end
    local pdata = QBCore.Functions.GetPlayerData()
    for _, it in pairs(pdata.items or {}) do
        if it and it.name == itemName and (tonumber(it.amount) or 0) > 0 then
            return true
        end
    end
    return false
end

local function openHood(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleDoorOpen(veh, 4, false, false)
end

local function closeHood(veh)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleDoorShut(veh, 4, false)
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local n = 0
    while not HasAnimDictLoaded(dict) and n < 40 do
        Wait(50)
        n += 1
    end
    return HasAnimDictLoaded(dict)
end

local function runCircle(circles, seconds)
    local names = { 'ps-ui', 'ps_lib' }
    for i = 1, #names do
        local res = names[i]
        if GetResourceState(res) == 'started' then
            local ok, result = pcall(function()
                return exports[res]:Circle(false, circles or 2, seconds or 10)
            end)
            if ok and result ~= nil then
                return result and true or false
            end
        end
    end
    notify('Hack UI missing — hold steady…', 'primary')
    Wait(1500)
    return true
end

local function applyClientHeal(veh, heal, kind)
    if not DoesEntityExist(veh) then return end
    heal = tonumber(heal) or 350.0
    SetVehicleEngineHealth(veh, heal + 0.0)
    if kind == 'advanced' then
        SetVehiclePetrolTankHealth(veh, 1000.0)
    else
        -- limp: keep tank usable but don't full-service
        local tank = GetVehiclePetrolTankHealth(veh)
        if tank < 400.0 then SetVehiclePetrolTankHealth(veh, 500.0) end
    end
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, false)
    local kit = kitCfg(kind)
    if kit.fixTyres and LunarVeh.ClearTyres then
        LunarVeh.ClearTyres(veh, LunarVeh.state)
    end
    if LunarVeh.current == veh or (LunarVeh.state and LunarVeh.IsTracked and LunarVeh.IsTracked(veh)) then
        if not LunarVeh.state then LunarVeh.state = Config.DefaultState() end
        LunarVeh.state.engine = heal
        if kind == 'advanced' then LunarVeh.state.tank = 1000.0 end
        LunarVeh.MarkDirty()
        if LunarVeh.ApplyHandling then
            LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
        end
        if LunarVeh.current == veh then
            LunarVeh.Save(true)
        end
    end
end

local function finishRepair(veh, kind, plate, netId)
    local c = kitCfg(kind)
    QBCore.Functions.TriggerCallback('lunar-vehicles:repairEngine', function(res)
        repairing = false
        closeHood(veh)
        ClearPedTasks(PlayerPedId())
        FreezeEntityPosition(PlayerPedId(), false)
        if not res or not res.ok then
            notify((res and res.message) or 'Repair failed.', 'error')
            return
        end
        applyClientHeal(veh, res.engine, kind)
        notify(res.message or 'Engine repaired.', 'success')
    end, {
        kind = kind,
        plate = plate,
        netId = netId,
        item = c.item,
    })
end

local function startProgress(veh, kind, plate, netId)
    local root = rootCfg()
    local c = kitCfg(kind)
    local duration = c.durationMs or 12000
    local anim = root.anim or c.anim or { dict = 'mini@repair', clip = 'fixing_a_player', flag = 1 }
    local label = kind == 'basic' and 'Field repair — limp home…' or 'Rebuilding engine…'

    if loadAnim(anim.dict) then
        TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 1, 0.0, false, false, false)
    end
    FreezeEntityPosition(PlayerPedId(), true)

    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('lunar_engine_repair_' .. kind, label, duration, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            finishRepair(veh, kind, plate, netId)
        end, function()
            repairing = false
            ClearPedTasks(PlayerPedId())
            FreezeEntityPosition(PlayerPedId(), false)
            closeHood(veh)
            notify('Repair cancelled.', 'error')
        end)
    else
        Wait(duration)
        finishRepair(veh, kind, plate, netId)
    end
end

local function startEngineRepair(veh, kind)
    kind = kind or 'advanced'
    local root = rootCfg()
    local c = kitCfg(kind)
    if not root.enabled or repairing then return end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        notify('Get out to work on the engine.', 'error')
        return
    end
    if not jobOk(c) then
        notify(kind == 'advanced' and 'Mechanics only.' or 'You cannot repair that.', 'error')
        return
    end
    if not hasItem(c.item) then
        notify(kind == 'basic' and 'You need a repair kit.' or 'You need an advanced repair kit.', 'error')
        return
    end

    local eng = GetVehicleEngineHealth(veh)
    local minD = tonumber(c.minDamage) or (kind == 'basic' and 350.0 or 980.0)
    if eng >= minD then
        notify(kind == 'basic' and 'It can already limp — take it to a mechanic.' or 'Engine looks fine.', 'primary')
        return
    end

    local plate = (QBCore.Functions.GetPlate(veh) or ''):gsub('%s+', ''):upper()
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local circ = c.circle or { circles = 2, seconds = 10 }

    repairing = true
    openHood(veh)

    CreateThread(function()
        local ok = runCircle(circ.circles, circ.seconds)
        if not ok then
            repairing = false
            closeHood(veh)
            notify('You botched the diagnosis.', 'error')
            return
        end
        if not DoesEntityExist(veh) then
            repairing = false
            notify('Vehicle gone.', 'error')
            return
        end
        startProgress(veh, kind, plate, netId)
    end)
end

local function classAllowed(entity)
    local class = GetVehicleClass(entity)
    if Config.IgnoreClasses and Config.IgnoreClasses[class] then return false end
    return true
end

CreateThread(function()
    local root = rootCfg()
    if not root.enabled then return end
    local n = 0
    while GetResourceState('qb-target') ~= 'started' and n < 60 do
        Wait(250)
        n += 1
    end
    if GetResourceState('qb-target') ~= 'started' then
        print('[lunar-vehicles] qb-target not started — repair targets disabled')
        return
    end

    local adv = kitCfg('advanced')
    local basic = kitCfg('basic')

    exports['qb-target']:AddGlobalVehicle({
        options = {
            {
                num = 1,
                icon = adv.icon or 'fas fa-wrench',
                label = adv.label or 'Repair engine',
                item = adv.item or 'advancedrepairkit',
                job = adv.requireJob or nil,
                action = function(entity)
                    startEngineRepair(entity, 'advanced')
                end,
                canInteract = function(entity)
                    if repairing then return false end
                    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                    if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                    if not classAllowed(entity) then return false end
                    if not jobOk(adv) then return false end
                    if GetVehicleEngineHealth(entity) >= (tonumber(adv.minDamage) or 980.0) then return false end
                    return hasItem(adv.item or 'advancedrepairkit')
                end,
            },
            {
                num = 2,
                icon = basic.icon or 'fas fa-screwdriver-wrench',
                label = basic.label or 'Field repair',
                item = basic.item or 'repairkit',
                action = function(entity)
                    startEngineRepair(entity, 'basic')
                end,
                canInteract = function(entity)
                    if repairing then return false end
                    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                    if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                    if not classAllowed(entity) then return false end
                    if not jobOk(basic) then return false end
                    if GetVehicleEngineHealth(entity) >= (tonumber(basic.minDamage) or 350.0) then return false end
                    return hasItem(basic.item or 'repairkit')
                end,
            },
        },
        distance = root.distance or 2.5,
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if repairing then
        repairing = false
        ClearPedTasks(PlayerPedId())
        FreezeEntityPosition(PlayerPedId(), false)
    end
end)
