-- lunar-vehicles — live handling from a server-sealed snapshot
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()

local HANDLING_FIELDS = {
    'fInitialDriveForce',
    'fDriveInertia',
    'fInitialDragCoeff',
    'fSteeringLock',
    'fTractionCurveMax',
    'fTractionCurveMin',
    'fTractionCurveLateral',
    'fTractionSpringDeltaMax',
    'fLowSpeedTractionLossMult',
    'fTractionLossMult',
    'fTractionBiasFront',
    'fCamberStiffnesss',
    'fSuspensionForce',
    'fSuspensionCompDamp',
    'fSuspensionReboundDamp',
    'fSuspensionUpperLimit',
    'fSuspensionLowerLimit',
    'fSuspensionRaise',
    'fAntiRollBarForce',
    'fRollCentreHeightFront',
    'fRollCentreHeightRear',
    'fBrakeForce',
    'fHandBrakeForce',
    'fCollisionDamageMult',
    'fWeaponDamageMult',
    'fDeformationDamageMult',
    'fEngineDamageMult',
    'fClutchChangeRateScaleUpShift',
    'fClutchChangeRateScaleDownShift',
}

local ADD_FIELDS = {
    fSuspensionRaise = true,
}

-- Fallback caps if the seal has not arrived yet. Never read Config.Handling.global.
local FALLBACK_LIMITS = {
    fInitialDriveForce = { 0.35, 1.40 },
    fDriveInertia = { 0.60, 2.00 },
    fInitialDragCoeff = { 0.70, 2.00 },
    fSteeringLock = { 0.70, 1.35 },
    fTractionCurveMax = { 0.45, 1.20 },
    fTractionCurveMin = { 0.40, 1.20 },
    fTractionCurveLateral = { 0.50, 1.25 },
    fTractionSpringDeltaMax = { 0.50, 1.25 },
    fLowSpeedTractionLossMult = { 0.50, 2.00 },
    fTractionLossMult = { 0.50, 2.00 },
    fTractionBiasFront = { 0.85, 1.15 },
    fCamberStiffnesss = { 0.50, 1.40 },
    fSuspensionForce = { 0.30, 1.40 },
    fSuspensionCompDamp = { 0.30, 1.40 },
    fSuspensionReboundDamp = { 0.30, 1.40 },
    fSuspensionUpperLimit = { 0.70, 1.50 },
    fSuspensionLowerLimit = { 0.70, 1.50 },
    fSuspensionRaise = { -0.08, 0.08 },
    fAntiRollBarForce = { 0.20, 1.40 },
    fRollCentreHeightFront = { 0.60, 1.30 },
    fRollCentreHeightRear = { 0.60, 1.30 },
    fBrakeForce = { 0.70, 1.40 },
    fHandBrakeForce = { 0.70, 1.50 },
    fCollisionDamageMult = { 0.80, 6.00 },
    fWeaponDamageMult = { 0.50, 2.00 },
    fDeformationDamageMult = { 0.80, 6.00 },
    fEngineDamageMult = { 0.80, 6.00 },
    fClutchChangeRateScaleUpShift = { 0.80, 1.60 },
    fClutchChangeRateScaleDownShift = { 0.80, 1.60 },
    power = { 0.70, 1.30 },
    top = { 0.70, 1.30 },
}

local profile = nil

local function deepCopy(src)
    if type(src) ~= 'table' then return src end
    local out = {}
    for k, v in pairs(src) do
        out[k] = type(v) == 'table' and deepCopy(v) or v
    end
    return out
end

local function clamp(n, lo, hi)
    n = tonumber(n)
    if not n then return lo end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function limits()
    return (profile and profile.limits) or FALLBACK_LIMITS
end

local function clampField(field, value, fallback)
    local lim = limits()[field]
    if not lim then return tonumber(value) or fallback end
    return clamp(value, lim[1], lim[2])
end

function LunarVeh.SetHandlingProfile(data)
    if type(data) ~= 'table' then return end
    profile = deepCopy(data)
end

function LunarVeh.ClampPerf(perf)
    if type(perf) ~= 'table' then return nil end
    local out = deepCopy(perf)
    if out.power ~= nil then out.power = clampField('power', out.power, 1.0) end
    if out.top ~= nil then out.top = clampField('top', out.top, 1.0) end
    return out
end

local function getFloat(veh, field)
    local ok, val = pcall(function()
        return GetVehicleHandlingFloat(veh, 'CHandlingData', field)
    end)
    if ok and type(val) == 'number' then return val end
    return nil
end

local function setFloat(veh, field, value)
    if type(value) ~= 'number' then return end
    pcall(function()
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value + 0.0)
    end)
end

local function ensureBaseline(veh)
    if LunarVeh.baselines[veh] then return LunarVeh.baselines[veh] end
    local base = {}
    for i = 1, #HANDLING_FIELDS do
        local f = HANDLING_FIELDS[i]
        local v = getFloat(veh, f)
        if v then base[f] = v end
    end
    LunarVeh.baselines[veh] = base
    return base
end

local function multInto(dst, src)
    if type(src) ~= 'table' then return end
    for k, v in pairs(src) do
        if type(v) == 'number' then
            dst[k] = (dst[k] or 1.0) * clampField(k, v, 1.0)
        end
    end
end

local function kitMults(perf, kits)
    local out = {}
    if type(perf) ~= 'table' or type(kits) ~= 'table' then return out end
    if perf.engine and kits.engine and kits.engine[perf.engine] then
        multInto(out, kits.engine[perf.engine])
    end
    if perf.brakes and kits.brakes and kits.brakes[perf.brakes] then
        multInto(out, kits.brakes[perf.brakes])
    end
    if perf.susp and kits.susp and kits.susp[tostring(perf.susp)] then
        multInto(out, kits.susp[tostring(perf.susp)])
    end
    if perf.trans and kits.trans and kits.trans[perf.trans] then
        multInto(out, kits.trans[perf.trans])
    end
    return out
end

local function damageMults(state, dmg)
    local out = {}
    dmg = dmg or {}
    local engine = tonumber(state and state.engine) or 1000.0
    local body = tonumber(state and state.body) or 1000.0
    local oil = tonumber(state and state.oil) or 100.0

    if engine < (dmg.engineBelow or 450.0) then
        local t = engine / (dmg.engineBelow or 450.0)
        out.fInitialDriveForce = (dmg.engineForceMult or 0.72) + (1.0 - (dmg.engineForceMult or 0.72)) * t
    end
    if body < (dmg.bodyBelow or 550.0) then
        local t = body / (dmg.bodyBelow or 550.0)
        local tr = dmg.tractionMult or 0.88
        out.fTractionCurveMax = tr + (1.0 - tr) * t
        out.fTractionCurveMin = tr + (1.0 - tr) * t
    end
    if oil < (Config.Oil.critical or 12.0) then
        out.fInitialDriveForce = (out.fInitialDriveForce or 1.0) * (dmg.oilCriticalForce or 0.65)
    end

    local limp = Config.Panels.limpBelow or 45.0
    local limpCount = 0
    for _, hp in pairs((state and state.panels) or {}) do
        if (tonumber(hp) or 100.0) < limp then limpCount = limpCount + 1 end
    end
    if limpCount > 0 then
        local factor = math.min(1.0, limpCount / 4.0)
        out.fTractionCurveMax = (out.fTractionCurveMax or 1.0) * (1.0 - (1.0 - (dmg.panelLimpTraction or 0.9)) * factor)
        out.fSteeringLock = (out.fSteeringLock or 1.0) * (1.0 - (1.0 - (dmg.panelLimpSteer or 0.92)) * factor)
    end
    return out
end

function LunarVeh.ApplyHandling(veh, state, perf)
    if not Config.Handling.enabled or not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if not profile or profile.enabled == false then return end

    local base = ensureBaseline(veh)
    local m = {}
    for k, _ in pairs(base) do m[k] = 1.0 end
    multInto(m, profile.global)
    multInto(m, kitMults(perf, profile.kits))
    multInto(m, damageMults(state, profile.damage))

    local extra = profile.globalAdd or {}
    for field, stock in pairs(base) do
        if ADD_FIELDS[field] then
            setFloat(veh, field, stock + clampField(field, extra[field] or 0.0, 0.0))
        else
            setFloat(veh, field, stock * clampField(field, m[field] or 1.0, 1.0))
        end
    end

    local engine = tonumber(state and state.engine) or 1000.0
    local body = tonumber(state and state.body) or 1000.0
    SetVehicleReduceGrip(veh, engine < 320.0 or body < 380.0)

    if LunarVeh.ApplyTyres then
        LunarVeh.ApplyTyres(veh, state)
    end
    if LunarVeh.SyncDriveable then
        LunarVeh.SyncDriveable(veh, state)
    end

    if type(perf) == 'table' then
        local power = clampField('power', tonumber(perf.power) or 1.0, 1.0)
        local top = clampField('top', tonumber(perf.top) or 1.0, 1.0)
        SetVehicleCheatPowerIncrease(veh, power)
        ModifyVehicleTopSpeed(veh, top)
    end
end

local function pullProfile(cb)
    QBCore.Functions.TriggerCallback('lunar-vehicles:handlingProfile', function(data)
        LunarVeh.SetHandlingProfile(data)
        if cb then cb(profile) end
    end)
end

RegisterNetEvent('lunar-vehicles:client:refreshHandling', function()
    local veh = LunarVeh.current
    if veh ~= 0 and LunarVeh.state then
        LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
    end
end)

RegisterNetEvent('lunar-vehicles:client:setPerf', function(perf)
    LunarVeh.perf = LunarVeh.ClampPerf(perf)
    local veh = LunarVeh.current
    if veh ~= 0 and LunarVeh.state then
        LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
    end
end)

exports('RefreshHandling', function(veh)
    veh = veh or LunarVeh.current
    if veh and veh ~= 0 then
        LunarVeh.ApplyHandling(veh, LunarVeh.state or Config.DefaultState(), LunarVeh.perf)
    end
end)

CreateThread(function()
    if not Config.Handling.enabled then return end
    pullProfile()
    local wait = Config.Handling.reapplyMs or 400
    while true do
        local veh = LunarVeh.current
        if veh ~= 0 and LunarVeh.state and DoesEntityExist(veh) and profile then
            LunarVeh.ApplyHandling(veh, LunarVeh.state, LunarVeh.perf)
            Wait(wait)
        else
            Wait(800)
        end
    end
end)

CreateThread(function()
    if not Config.Handling.enabled then return end
    local refresh = Config.Handling.sealRefreshMs or 20000
    while true do
        Wait(refresh)
        pullProfile()
    end
end)
