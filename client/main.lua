-- lunar-vehicles — session state, persist, tyres, occupant damage
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()

LunarVeh = LunarVeh or {}
LunarVeh.current = 0
LunarVeh.state = nil
LunarVeh.perf = nil
LunarVeh.owned = false
LunarVeh.dirty = false
LunarVeh.lastSave = 0
LunarVeh.baselines = {}

-- GTA corners are 0/1/4/5. Mid-axle 2/3 aliases to rear on 4-wheel cars.
local TYRE_ALIASES = {
    [0] = { 0 },
    [1] = { 1 },
    [2] = { 2, 4 },
    [3] = { 3, 5 },
    [4] = { 4, 2 },
    [5] = { 5, 3 },
}

local function dbg(...)
    if Config.Debug then
        print('[lunar-vehicles]', ...)
    end
end

local function plateOf(veh)
    if not veh or veh == 0 then return '' end
    return (QBCore.Functions.GetPlate(veh) or ''):gsub('%s+', ''):upper()
end

local function classOk(veh)
    local class = GetVehicleClass(veh)
    if Config.IgnoreClasses and Config.IgnoreClasses[class] then
        return false
    end
    return true
end

local function playerMeta()
    local data = QBCore.Functions.GetPlayerData()
    return (data and data.metadata) or {}
end

function LunarVeh.IsTracked(veh)
    return veh and veh ~= 0 and DoesEntityExist(veh) and classOk(veh)
end

function LunarVeh.MarkDirty()
    LunarVeh.dirty = true
end

function LunarVeh.GetState()
    return LunarVeh.state
end

function LunarVeh.AddMileage(state, speedMs, dtMs)
    if not state then return end
    local metres = (tonumber(speedMs) or 0.0) * (math.max(0, tonumber(dtMs) or 0) / 1000.0)
    state.mileage = (tonumber(state.mileage) or 0.0) + metres * 0.000621371
end

function LunarVeh.IsOilLimp(state)
    if not state or not Config.Oil or Config.Oil.enabled == false then return false end
    local oil = tonumber(state.oil) or 100.0
    local at = tonumber(Config.Oil.limpAt) or tonumber(Config.Oil.critical) or 10.0
    return oil <= at
end

function LunarVeh.IsEngineLimp(state)
    if not state then return false end
    local eng = tonumber(state.engine) or 1000.0
    local below = (Config.Health and tonumber(Config.Health.limpBelow)) or 200.0
    return eng <= below
end

function LunarVeh.IsLimp(state)
    return LunarVeh.IsOilLimp(state) or LunarVeh.IsEngineLimp(state)
end

function LunarVeh.ApplyLimpCues(veh, state)
    if not veh or veh == 0 or not DoesEntityExist(veh) or not state then return end
    if not LunarVeh.IsLimp(state) then return end
    local health = Config.Health or {}
    local oil = Config.Oil or {}
    local force = tonumber(health.limpForceMult) or tonumber(oil.limpForceMult) or 0.36
    local top = tonumber(health.limpTopMult) or tonumber(oil.limpTopMult) or 0.52
    if LunarVeh.IsOilLimp(state) and LunarVeh.IsEngineLimp(state) then
        force = force * 0.85
        top = top * 0.9
    end
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleUndriveable(veh, false)
    if SetVehicleCheatPowerIncrease then
        SetVehicleCheatPowerIncrease(veh, force)
    end
    if ModifyVehicleTopSpeed then
        ModifyVehicleTopSpeed(veh, top)
    end
end

function LunarVeh.SyncDriveable(veh, state)
    if not veh or veh == 0 or not state or not DoesEntityExist(veh) then return end
    local crash = Config.Crash or {}
    local eng = tonumber(state.engine) or 1000.0
    if eng <= (crash.undriveableBelow or 70.0) then
        SetVehicleUndriveable(veh, true)
        SetVehicleEngineOn(veh, false, true, true)
        return
    end
    SetVehicleUndriveable(veh, false)
    if LunarVeh.IsLimp(state) then
        LunarVeh.ApplyLimpCues(veh, state)
        return
    end
    if eng <= (crash.stallBelow or 90.0) and GetIsVehicleEngineRunning(veh) then
        if GetGameTimer() % 7 == 0 then
            SetVehicleEngineOn(veh, false, true, true)
        end
    end
end

function LunarVeh.HardenVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if not Config.Safety or Config.Safety.noVehicleExplode == false then return end
    SetVehicleExplodesOnHighExplosionDamage(veh, false)
    SetDisableVehiclePetrolTankFires(veh, true)
    SetDisableVehiclePetrolTankDamage(veh, true)
    if IsEntityOnFire(veh) then
        StopEntityFire(veh)
    end
end

function LunarVeh.BurstWheel(veh, index)
    index = math.floor(tonumber(index) or -1)
    if not veh or veh == 0 or index < 0 then return end
    SetVehicleTyresCanBurst(veh, true)
    pcall(function()
        SetVehicleWheelsCanBreak(veh, true)
    end)
    local aliases = TYRE_ALIASES[index] or { index }
    for i = 1, #aliases do
        local wheel = aliases[i]
        if not IsVehicleTyreBurst(veh, wheel, false) and not IsVehicleTyreBurst(veh, wheel, true) then
            SetVehicleTyreBurst(veh, wheel, true, 1000.0)
        end
        pcall(function()
            SetVehicleWheelHealth(veh, wheel, 0.0)
        end)
    end
end

function LunarVeh.RememberTyre(state, index)
    if not state then return end
    index = math.floor(tonumber(index) or -1)
    if index < 0 then return end
    if index == 2 then index = 4 end
    if index == 3 then index = 5 end
    state.tyres = state.tyres or {}
    state.tyres[tostring(index)] = true
end

function LunarVeh.ApplyTyres(veh, state)
    if not veh or veh == 0 or not state or not state.tyres then return end
    if Config.Tyres and Config.Tyres.persist == false then return end
    SetVehicleTyresCanBurst(veh, true)
    for key, on in pairs(state.tyres) do
        if on then LunarVeh.BurstWheel(veh, key) end
    end
end

function LunarVeh.CaptureTyres(veh, state)
    if not veh or veh == 0 or not state then return false end
    local changed = false
    for i = 0, 5 do
        if IsVehicleTyreBurst(veh, i, false) or IsVehicleTyreBurst(veh, i, true) then
            if not (state.tyres and state.tyres[tostring(i)]) then
                LunarVeh.RememberTyre(state, i)
                changed = true
            end
        end
    end
    return changed
end

function LunarVeh.ClearTyres(veh, state)
    if state then state.tyres = {} end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    for i = 0, 7 do
        SetVehicleTyreFixed(veh, i)
        pcall(function()
            SetVehicleWheelHealth(veh, i, 1000.0)
        end)
    end
end

function LunarVeh.ApplyNativeHealth(veh, state)
    if not veh or veh == 0 or not state then return end
    local tankFloor = (Config.Safety and Config.Safety.tankFloor) or 550.0
    if Config.Health.enforceEngine and state.engine then
        local floor = Config.Health.engineFloor or 50.0
        state.engine = math.max(tonumber(state.engine) or floor, floor)
        SetVehicleEngineHealth(veh, state.engine + 0.0)
    end
    if Config.Health.enforceBody and state.body then
        SetVehicleBodyHealth(veh, tonumber(state.body) + 0.0)
    end
    if state.tank then
        state.tank = math.max(tonumber(state.tank) or tankFloor, tankFloor)
        SetVehiclePetrolTankHealth(veh, state.tank + 0.0)
    end
    if SetVehicleOilLevel and state.oil then
        SetVehicleOilLevel(veh, (tonumber(state.oil) / 100.0) * 1000.0)
    end
    LunarVeh.HardenVehicle(veh)
    LunarVeh.ApplyTyres(veh, state)
    LunarVeh.SyncDriveable(veh, state)
end

-- Real ped damage so qb-ambulancejob sees CEventNetworkEntityDamage.
-- Hard crash: first down is laststand, then a second hit finishes them.
function LunarVeh.HurtOccupant(amount)
    local ped = PlayerPedId()
    local meta = playerMeta()
    if meta.isdead then return end
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetEntityInvincible(ped, false)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    ApplyDamageToPed(ped, amount, false)
end

function LunarVeh.KillOccupant()
    local ped = PlayerPedId()
    local meta = playerMeta()
    if meta.isdead then return end

    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetEntityInvincible(ped, false)
    SetPedArmour(ped, 0)
    local hp = GetEntityHealth(ped)
    if hp > 0 then
        ApplyDamageToPed(ped, hp + 100, false)
    end
    if GetEntityHealth(ped) > 0 then
        SetEntityHealth(ped, 0)
    end

    local crash = Config.Crash or {}
    if crash.finishLaststand == false then return end

    CreateThread(function()
        local deadline = GetGameTimer() + 45000
        while GetGameTimer() < deadline do
            Wait(100)
            ped = PlayerPedId()
            meta = playerMeta()
            if meta.isdead then return end
            local hp = GetEntityHealth(ped)
            -- laststand resurrects to ~150 after the wreck stops sliding
            if meta.inlaststand or (hp > 0 and hp <= 160 and not IsEntityDead(ped)) then
                SetEntityProofs(ped, false, false, false, false, false, false, false, false)
                SetEntityInvincible(ped, false)
                SetPedArmour(ped, 0)
                ApplyDamageToPed(ped, hp + 100, false)
                if GetEntityHealth(ped) > 0 then
                    SetEntityHealth(ped, 0)
                end
                return
            end
        end
    end)
end

function LunarVeh.LoadForVehicle(veh)
    if not LunarVeh.IsTracked(veh) then
        LunarVeh.state = nil
        LunarVeh.perf = nil
        LunarVeh.owned = false
        return
    end
    local plate = plateOf(veh)
    QBCore.Functions.TriggerCallback('lunar-vehicles:loadState', function(res)
        if GetVehiclePedIsIn(PlayerPedId(), false) ~= veh then return end
        if res and res.handling and LunarVeh.SetHandlingProfile then
            LunarVeh.SetHandlingProfile(res.handling)
        end
        LunarVeh.state = Config.MergeState(res and res.state)
        if LunarVeh.MergeSessionOil then
            LunarVeh.state = LunarVeh.MergeSessionOil(plate, LunarVeh.state)
        end
        LunarVeh.perf = LunarVeh.ClampPerf and LunarVeh.ClampPerf(res and res.perf) or (res and res.perf or nil)
        LunarVeh.owned = res and res.owned and true or false
        LunarVeh.dirty = false
        LunarVeh.ApplyNativeHealth(veh, LunarVeh.state)
        if LunarVeh.OnStateLoaded then
            LunarVeh.OnStateLoaded(veh, LunarVeh.state, LunarVeh.perf)
        end
        dbg('loaded', plate, LunarVeh.owned and 'owned' or 'session')
    end, plate)
end

function LunarVeh.Save(force)
    if not Config.Persist then return end
    if not LunarVeh.owned or not LunarVeh.state then return end
    if not LunarVeh.dirty and not force then return end
    local veh = LunarVeh.current
    if veh == 0 or not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)
    if plate == '' then return end

    local floor = Config.Health.engineFloor or 50.0
    local tankFloor = (Config.Safety and Config.Safety.tankFloor) or 550.0
    local nativeEng = GetVehicleEngineHealth(veh)
    local nativeBody = GetVehicleBodyHealth(veh)
    local nativeTank = GetVehiclePetrolTankHealth(veh)
    LunarVeh.state.engine = math.max(floor, math.min(tonumber(LunarVeh.state.engine) or nativeEng, nativeEng))
    LunarVeh.state.body = math.min(tonumber(LunarVeh.state.body) or nativeBody, nativeBody)
    LunarVeh.state.tank = math.max(tankFloor, math.min(tonumber(LunarVeh.state.tank) or nativeTank, nativeTank))
    LunarVeh.CaptureTyres(veh, LunarVeh.state)

    QBCore.Functions.TriggerCallback('lunar-vehicles:saveState', function(res)
        if res and res.ok then
            LunarVeh.dirty = false
            LunarVeh.lastSave = GetGameTimer()
            if res.state then LunarVeh.state = Config.MergeState(res.state) end
        end
    end, { plate = plate, state = LunarVeh.state })
end

CreateThread(function()
    if not Config.Enabled then return end
    while true do
        local sleep = 700
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and LunarVeh.IsTracked(veh) then
            if veh ~= LunarVeh.current then
                if LunarVeh.current ~= 0 and Config.SaveOnExit then
                    LunarVeh.Save(true)
                end
                LunarVeh.current = veh
                LunarVeh.HardenVehicle(veh)
                LunarVeh.LoadForVehicle(veh)
            end
            sleep = 400
        else
            if LunarVeh.current ~= 0 then
                if Config.SaveOnExit then LunarVeh.Save(true) end
                LunarVeh.current = 0
                LunarVeh.state = nil
                LunarVeh.perf = nil
                LunarVeh.owned = false
                SendNUIMessage({ action = 'oil', open = false })
                for entity, _ in pairs(LunarVeh.baselines) do
                    if not DoesEntityExist(entity) then
                        LunarVeh.baselines[entity] = nil
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    if not Config.Enabled or not Config.Persist then return end
    while true do
        Wait(Config.SaveIntervalMs or 45000)
        if LunarVeh.current ~= 0 and LunarVeh.dirty then
            LunarVeh.Save(false)
        end
    end
end)

exports('GetClientState', function()
    return LunarVeh.state
end)

exports('ForceSave', function()
    LunarVeh.Save(true)
end)

exports('Reload', function(veh)
    veh = veh or LunarVeh.current
    if veh and veh ~= 0 then LunarVeh.LoadForVehicle(veh) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LunarVeh.current ~= 0 then LunarVeh.Save(true) end
end)
