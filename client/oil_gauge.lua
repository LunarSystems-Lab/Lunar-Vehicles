-- lunar-vehicles — oil burn + NUI gauge
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local gaugeVisible = false
local holdPeek = false

local function nui(msg)
    SendNUIMessage(msg)
end

local function setGauge(show, payload)
    if show and not gaugeVisible then
        gaugeVisible = true
        nui({ action = 'oil', open = true })
    elseif not show and gaugeVisible then
        gaugeVisible = false
        nui({ action = 'oil', open = false })
    end
    if show and payload then
        nui({ action = 'oilUpdate', data = payload })
    end
end

local function oilPayload(state)
    local oil = tonumber(state.oil) or 100.0
    local cfg = Config.Oil
    local level = 'ok'
    if oil <= (cfg.critical or cfg.limpAt or 10.0) then
        level = 'crit'
    elseif oil <= (cfg.warn or 28.0) then
        level = 'warn'
    end
    return {
        oil = oil,
        grade = state.oilGrade or 'STOCK',
        level = level,
    }
end

CreateThread(function()
    if not Config.Enabled or not Config.Oil.enabled then return end
    while true do
        local wait = 500
        local veh = LunarVeh.current
        local state = LunarVeh.state
        if veh ~= 0 and state and DoesEntityExist(veh) and GetIsVehicleEngineRunning(veh) then
            wait = 250
            local dt = wait / 1000.0
            local throttle = 0.0
            if GetVehicleThrottleOffset then
                throttle = GetVehicleThrottleOffset(veh) or 0.0
            else
                throttle = GetControlNormal(0, 71)
            end
            if throttle < 0.0 then throttle = 0.0 end
            local rpm = GetVehicleCurrentRpm(veh)
            local cfg = Config.Oil

            local burn = (cfg.idleBurn or 0.004) + (cfg.throttleBurn or 0.018) * throttle
            if rpm >= (cfg.highRpm or 0.72) then
                burn = burn * (cfg.highRpmMult or 2.1)
            end
            local grade = tostring(state.oilGrade or '')
            if grade == 'Syn' or grade == 'Synth' then burn = burn * 0.72
            elseif grade == 'Race' then burn = burn * 0.55
            elseif grade == 'Std' then burn = burn * 0.9
            end

            state.oil = math.max(0.0, (tonumber(state.oil) or 100.0) - burn * dt * 10.0)

            local limpAt = tonumber(cfg.limpAt) or tonumber(cfg.critical) or 10.0
            if state.oil <= limpAt then
                -- oil limp: power only (criticalDamagePerSec == 0 by default)
                local dps = tonumber(cfg.criticalDamagePerSec) or 0.0
                if dps > 0.0 then
                    local limpFloor = tonumber(cfg.limpEngineFloor) or 420.0
                    local eng = tonumber(state.engine) or 1000.0
                    if eng > limpFloor then
                        state.engine = math.max(limpFloor, eng - dps * dt * 10.0)
                        LunarVeh.ApplyNativeHealth(veh, state)
                    end
                end
                if LunarVeh.ApplyHandling then
                    LunarVeh.ApplyHandling(veh, state, LunarVeh.perf)
                end
                if LunarVeh.ApplyLimpCues then
                    LunarVeh.ApplyLimpCues(veh, state)
                end
            end

            LunarVeh.MarkDirty()

            local payload = oilPayload(state)
            local shouldShow = Config.Oil.showAlways or holdPeek or payload.level ~= 'ok'
            setGauge(shouldShow, payload)
        else
            if gaugeVisible then setGauge(false) end
            wait = 900
        end
        Wait(wait)
    end
end)

CreateThread(function()
    if not Config.Enabled or not Config.Oil.enabled then return end
    while true do
        local wait = 200
        if LunarVeh.current ~= 0 then
            wait = 0
            holdPeek = IsControlPressed(0, Config.Oil.holdKey or 20)
        else
            holdPeek = false
        end
        Wait(wait)
    end
end)

RegisterNetEvent('lunar-vehicles:client:oilServiced', function(data)
    data = data or {}
    local fill = tonumber(data.fill) or 100.0
    if fill > 100.0 then fill = math.min(100.0, (fill / 1000.0) * 100.0) end
    local grade = data.grade and tostring(data.grade) or nil
    local plate = tostring(data.plate or '')
    if plate == '' and LunarVeh.current ~= 0 then
        plate = (GetVehicleNumberPlateText(LunarVeh.current) or ''):gsub('%s+', ''):upper()
    end
    if LunarVeh.RememberOilFill then
        LunarVeh.RememberOilFill(plate, fill, grade)
    else
        if not LunarVeh.state then
            LunarVeh.state = Config.DefaultState()
        end
        LunarVeh.state.oil = fill
        if grade then LunarVeh.state.oilGrade = grade end
        LunarVeh.MarkDirty()
        local veh = LunarVeh.current
        if veh ~= 0 then
            LunarVeh.ApplyNativeHealth(veh, LunarVeh.state)
            if LunarVeh.ApplyHandling then
                LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
            end
        end
    end
    if LunarVeh.state then
        setGauge(true, oilPayload(LunarVeh.state))
    end
end)

exports('ShowOilGauge', function(show)
    if show and LunarVeh.state then
        setGauge(true, oilPayload(LunarVeh.state))
    else
        setGauge(false)
    end
end)
