-- lunar-vehicles — collision, panels, tyres, occupant injury
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()
local lastSpeed = 0.0
local lastTick = 0
local crashLockUntil = 0

local function clamp(n, a, b)
    if n < a then return a end
    if n > b then return b end
    return n
end

-- FiveM has no GetEntityRightVector. Yaw-perpendicular of forward is enough.
local function entityRight(ent)
    local fwd = GetEntityForwardVector(ent)
    return vector3(fwd.y, -fwd.x, 0.0)
end

local function weakestPanel(state)
    local worst, id = 100.0, nil
    for pid, hp in pairs(state.panels or {}) do
        hp = tonumber(hp) or 100.0
        if hp < worst then
            worst, id = hp, pid
        end
    end
    return worst, id
end

local function applyPanelVisuals(veh, state)
    if not Config.Panels.enabled or not state or not state.panels then return end
    local smash = Config.Panels.smashBelow or 28.0
    for i = 1, #(Config.Panels.list or {}) do
        local p = Config.Panels.list[i]
        local hp = tonumber(state.panels[p.id]) or 100.0
        if hp <= smash then
            if p.id == 'glass_f' then
                SmashVehicleWindow(veh, 0)
            elseif p.id == 'door_lf' then
                SetVehicleDoorBroken(veh, 0, true)
            elseif p.id == 'door_rf' then
                SetVehicleDoorBroken(veh, 1, true)
            elseif p.id == 'door_lr' then
                SetVehicleDoorBroken(veh, 2, true)
            elseif p.id == 'door_rr' then
                SetVehicleDoorBroken(veh, 3, true)
            elseif p.id == 'hood' then
                SetVehicleDoorBroken(veh, 4, true)
            elseif p.id == 'boot' then
                SetVehicleDoorBroken(veh, 5, true)
            elseif p.id == 'wing_lf' then
                LunarVeh.RememberTyre(state, 0)
            elseif p.id == 'wing_rf' then
                LunarVeh.RememberTyre(state, 1)
            end
        end
    end
    LunarVeh.ApplyTyres(veh, state)
end

local function damageNearestPanels(state, amount, forwardBias)
    amount = tonumber(amount) or 0.0
    if amount <= 0.0 then return end
    local list = Config.Panels.list or {}
    for i = 1, #list do
        local p = list[i]
        local weight = 0.35
        if forwardBias > 0.2 and (p.id == 'bumper_f' or p.id == 'hood' or p.id == 'wing_lf' or p.id == 'wing_rf' or p.id == 'glass_f') then
            weight = 1.0
        elseif forwardBias < -0.2 and (p.id == 'bumper_r' or p.id == 'boot') then
            weight = 1.0
        elseif p.id:find('door', 1, true) then
            weight = 0.55
        end
        local cur = tonumber(state.panels[p.id]) or 100.0
        state.panels[p.id] = clamp(cur - amount * weight, 0.0, 100.0)
    end
end

local function pickWheels(forwardBias, side, wipe)
    if wipe then return { 0, 1, 4, 5 } end
    local front = forwardBias >= -0.2
    if side < -0.45 then
        return front and { 0, 4 } or { 4, 0 }
    end
    if side > 0.45 then
        return front and { 1, 5 } or { 5, 1 }
    end
    return front and { 0, 1 } or { 4, 5 }
end

local function hurtDriver(veh, delta)
    local crash = Config.Crash or {}
    local ped = PlayerPedId()
    if not IsPedInVehicle(ped, veh, false) then return end

    local data = QBCore.Functions.GetPlayerData()
    local meta = (data and data.metadata) or {}
    if meta.isdead then return end

    if delta >= (crash.playerKillDelta or 26.0) then
        LunarVeh.KillOccupant()
        return
    end
    if meta.inlaststand then return end
    if delta >= (crash.playerHurtDelta or 14.0) then
        local dmg = math.floor((delta * delta) * (crash.playerHurtK or 0.42))
        LunarVeh.HurtOccupant(math.min(160, math.max(18, dmg)))
    end
end

function LunarVeh.OnStateLoaded(veh, state, perf)
    applyPanelVisuals(veh, state)
    LunarVeh.ApplyTyres(veh, state)
    if LunarVeh.ApplyHandling then
        LunarVeh.ApplyHandling(veh, state, perf)
    end
end

local function applyCrash(veh, state, delta)
    local crash = Config.Crash or {}
    if crash.enabled == false then return end
    local now = GetGameTimer()
    if now < crashLockUntil then return end
    crashLockUntil = now + (crash.cooldownMs or 380)

    local energy = delta * delta
    local engineLoss = math.min(energy * (crash.engineK or 0.78), crash.maxEngineHit or 1000.0)
    local bodyLoss = math.min(energy * (crash.bodyK or 0.95), crash.maxBodyHit or 980.0)
    local floor = Config.Health.engineFloor or 50.0
    local writeOff = delta >= (crash.writeOffDelta or 26.0)

    if writeOff then
        state.engine = math.min(tonumber(state.engine) or 1000.0, crash.writeOffEngine or 80.0)
        state.body = math.min(tonumber(state.body) or 1000.0, crash.writeOffBody or 70.0)
    else
        state.engine = clamp((tonumber(state.engine) or 1000.0) - engineLoss, floor, 1000.0)
        state.body = clamp((tonumber(state.body) or 1000.0) - bodyLoss, 0.0, 1000.0)
    end

    if delta >= 18.0 then
        local tankFloor = (Config.Safety and Config.Safety.tankFloor) or 550.0
        state.tank = clamp((tonumber(state.tank) or 1000.0) - energy * (crash.tankK or 0.18), tankFloor, 1000.0)
    end

    local vel = GetEntityVelocity(veh)
    local fwd = GetEntityForwardVector(veh)
    local right = entityRight(veh)
    local forwardBias = vel.x * fwd.x + vel.y * fwd.y + vel.z * fwd.z
    local side = vel.x * right.x + vel.y * right.y
    damageNearestPanels(state, math.min(100.0, energy * (Config.Panels.collisionScale or 0.22)), forwardBias)

    SetVehicleDamage(veh, 0.0, forwardBias >= 0.0 and 2.4 or -2.4, 0.35, math.min(280.0, energy * 0.35), 1400.0, true)

    if delta >= (crash.smashWindowsAbove or 12.0) then
        for w = 0, 7 do SmashVehicleWindow(veh, w) end
    end

    if delta >= (crash.burstTyresAbove or 11.0) or writeOff then
        local wheels = pickWheels(forwardBias, side, writeOff)
        for i = 1, #wheels do
            LunarVeh.RememberTyre(state, wheels[i])
            LunarVeh.BurstWheel(veh, wheels[i])
        end
    end

    if delta >= (crash.breakDoorsAbove or 20.0) then
        SetVehicleDoorBroken(veh, 4, true)
        SetVehicleDoorBroken(veh, forwardBias >= 0.0 and 0 or 2, true)
    end

    applyPanelVisuals(veh, state)
    LunarVeh.ApplyNativeHealth(veh, state)
    LunarVeh.MarkDirty()
    if LunarVeh.ApplyHandling then
        LunarVeh.ApplyHandling(veh, state, LunarVeh.perf)
    end
    hurtDriver(veh, delta)
end

CreateThread(function()
    if not Config.Enabled then return end
    lastTick = GetGameTimer()
    local crash = Config.Crash or {}
    while true do
        local veh = LunarVeh.current
        local state = LunarVeh.state
        if veh ~= 0 and state and DoesEntityExist(veh) then
            local now = GetGameTimer()
            local dt = math.max(16, now - lastTick)
            lastTick = now
            local speed = GetEntitySpeed(veh)
            if lastSpeed > 0.0 then
                local delta = lastSpeed - speed
                local minD = crash.minDelta or 4.2
                local hit = HasEntityCollidedWithAnything(veh)
                if delta >= minD and (hit or delta >= minD * 1.55) then
                    applyCrash(veh, state, delta)
                end
            end
            lastSpeed = speed
            LunarVeh.AddMileage(state, speed, dt)
            Wait(speed > 8.0 and 0 or 50)
        else
            lastSpeed = 0.0
            lastTick = GetGameTimer()
            Wait(800)
        end
    end
end)

AddEventHandler('gameEventTriggered', function(name, data)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not Config.Enabled or not LunarVeh.state then return end
    local veh = LunarVeh.current
    if veh == 0 or not data or data[1] ~= veh then return end
    local delta = lastSpeed - GetEntitySpeed(veh)
    if delta >= (Config.Crash and Config.Crash.minDelta or 4.2) then
        applyCrash(veh, LunarVeh.state, delta)
    end
end)

CreateThread(function()
    if not Config.Enabled then return end
    while true do
        local wait = Config.Health.tickMs or 250
        local veh = LunarVeh.current
        local state = LunarVeh.state
        if veh ~= 0 and state and DoesEntityExist(veh) then
            if Config.Health.enforceEngine then
                local eng = GetVehicleEngineHealth(veh)
                local want = tonumber(state.engine) or eng
                if eng > want + 8.0 then
                    SetVehicleEngineHealth(veh, want)
                elseif eng < want - 25.0 then
                    state.engine = eng
                    LunarVeh.MarkDirty()
                end
            end
            if Config.Health.enforceBody then
                local body = GetVehicleBodyHealth(veh)
                local want = tonumber(state.body) or body
                if body > want + 8.0 then
                    SetVehicleBodyHealth(veh, want)
                elseif body < want - 25.0 then
                    state.body = body
                    LunarVeh.MarkDirty()
                end
            end
            if LunarVeh.CaptureTyres(veh, state) then
                LunarVeh.MarkDirty()
            end
            LunarVeh.ApplyTyres(veh, state)
            if LunarVeh.SyncDriveable then
                LunarVeh.SyncDriveable(veh, state)
            end
        else
            wait = 1200
        end
        Wait(wait)
    end
end)

exports('GetPanelHealth', function(panelId)
    local state = LunarVeh.state
    if not state or not state.panels then return 100.0 end
    return tonumber(state.panels[panelId]) or 100.0
end)

exports('WeakestPanel', function()
    if not LunarVeh.state then return 100.0, nil end
    return weakestPanel(LunarVeh.state)
end)
