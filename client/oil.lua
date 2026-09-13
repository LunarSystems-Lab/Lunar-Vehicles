-- lunar-vehicles — oil fill (item / qb-target)
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()
local filling = false

-- Session fills for unowned plates until someone drives them.
LunarVeh.oilSession = LunarVeh.oilSession or {}

local function notify(msg, kind)
    QBCore.Functions.Notify(msg, kind or 'primary')
end

local function bottles()
    local cfg = Config.Oil or {}
    if cfg.enabled == false then return {} end
    return cfg.bottles or {}
end

local function bottleByItem(itemName)
    itemName = tostring(itemName or '')
    local list = bottles()
    for i = 1, #list do
        if list[i].item == itemName then return list[i] end
    end
end

local function plateOf(veh)
    if not veh or veh == 0 then return '' end
    return (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()
end

local function classAllowed(entity)
    local class = GetVehicleClass(entity)
    if Config.IgnoreClasses and Config.IgnoreClasses[class] then return false end
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

local function closestVehicle(range)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    if IsPedInAnyVehicle(ped, false) then
        return GetVehiclePedIsIn(ped, false)
    end
    local veh = GetClosestVehicle(c.x, c.y, c.z, range or 2.8, 0, 71)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
end

local function applyFillLocal(plate, fill, grade)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    fill = math.max(0.0, math.min(100.0, tonumber(fill) or 100.0))
    grade = type(grade) == 'string' and grade:sub(1, 12) or 'Serviced'
    if plate ~= '' then
        LunarVeh.oilSession[plate] = { oil = fill, grade = grade, at = GetGameTimer() }
    end
    local veh = LunarVeh.current
    if veh ~= 0 and plateOf(veh) == plate then
        if not LunarVeh.state then LunarVeh.state = Config.DefaultState() end
        LunarVeh.state.oil = fill
        LunarVeh.state.oilGrade = grade
        LunarVeh.MarkDirty()
        if LunarVeh.ApplyHandling then
            LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
        end
        if LunarVeh.ApplyNativeHealth then
            LunarVeh.ApplyNativeHealth(veh, LunarVeh.state)
        end
    end
end

function LunarVeh.RememberOilFill(plate, fill, grade)
    applyFillLocal(plate, fill, grade)
end

--- Merge a roadside/session oil fill when entering a vehicle.
function LunarVeh.MergeSessionOil(plate, state)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    local row = plate ~= '' and LunarVeh.oilSession[plate] or nil
    if not row or type(state) ~= 'table' then return state end
    state.oil = tonumber(row.oil) or state.oil
    state.oilGrade = row.grade or state.oilGrade
    return state
end
local function startOilFill(veh, itemName)
    if filling then return end
    local bottle = bottleByItem(itemName)
    if not bottle then return end
    if not Config.Oil or Config.Oil.enabled == false then
        notify('Oil system is disabled.', 'error')
        return
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        notify('Stand next to a vehicle.', 'error')
        return
    end
    if not classAllowed(veh) then
        notify('That vehicle does not take this oil.', 'error')
        return
    end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        notify('Get out to change the oil.', 'error')
        return
    end
    if not hasItem(bottle.item) then
        notify('You need ' .. (bottle.label or 'oil') .. '.', 'error')
        return
    end

    filling = true
    local plate = plateOf(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local anim = (Config.Oil and Config.Oil.anim) or {}
    local dict = anim.dict or 'mini@repair'
    local clip = anim.clip or 'fixing_a_player'
    RequestAnimDict(dict)
    local n = 0
    while not HasAnimDictLoaded(dict) and n < 40 do
        Wait(50)
        n = n + 1
    end
    TaskPlayAnim(PlayerPedId(), dict, clip, 3.0, 3.0, -1, anim.flag or 1, 0.0, false, false, false)
    SetVehicleDoorOpen(veh, 4, false, false)

    local ms = tonumber(bottle.durationMs) or 8000
    local label = 'Filling ' .. (bottle.label or 'oil') .. '…'
    local function finish(ok)
        ClearPedTasks(PlayerPedId())
        SetVehicleDoorShut(veh, 4, false)
        filling = false
        if not ok then
            notify('Oil change cancelled.', 'error')
            return
        end
        QBCore.Functions.TriggerCallback('lunar-vehicles:fillOil', function(res)
            if not res or not res.ok then
                notify((res and res.message) or 'Could not fill oil.', 'error')
                return
            end
            applyFillLocal(plate, res.fill, res.grade)
            notify(res.message or 'Oil topped up.', 'success')
        end, {
            item = bottle.item,
            plate = plate,
            netId = netId,
        })
    end

    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('lunar_oil_fill', label, ms, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            finish(true)
        end, function()
            finish(false)
        end)
    else
        Wait(ms)
        finish(true)
    end
end

RegisterNetEvent('lunar-vehicles:client:useOilBottle', function(itemName)
    local range = (Config.Oil and Config.Oil.fillDistance) or 2.8
    local veh = closestVehicle(range)
    startOilFill(veh, itemName)
end)

-- Keep mechanic / export path in sync via oil_gauge (lunar-vehicles:client:oilServiced).
-- Session cache is updated from there through LunarVeh.RememberOilFill.

CreateThread(function()
    local list = bottles()
    if #list < 1 then return end
    local n = 0
    while GetResourceState('qb-target') ~= 'started' and n < 60 do
        Wait(250)
        n = n + 1
    end
    if GetResourceState('qb-target') ~= 'started' then
        print('[lunar-vehicles] qb-target not started — oil still works from inventory')
        return
    end
    local options = {}
    for i = 1, #list do
        local bottle = list[i]
        options[#options + 1] = {
            num = 10 + i,
            icon = bottle.icon or 'fas fa-oil-can',
            label = 'Fill ' .. (bottle.label or 'oil'),
            item = bottle.item,
            action = function(entity)
                startOilFill(entity, bottle.item)
            end,
            canInteract = function(entity)
                if filling then return false end
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                if not classAllowed(entity) then return false end
                return hasItem(bottle.item)
            end,
        }
    end
    exports['qb-target']:AddGlobalVehicle({
        options = options,
        distance = (Config.Oil and Config.Oil.fillDistance) or 2.8,
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if filling then
        filling = false
        ClearPedTasks(PlayerPedId())
    end
end)
