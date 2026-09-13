-- lunar-vehicles — seal and clamp handling before any client apply
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()
LunarVeh = LunarVeh or {}

local LIMITS = {
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

local function clamp(n, lo, hi)
    n = tonumber(n)
    if not n then return lo end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function clampField(field, value, fallback)
    local lim = LIMITS[field]
    if not lim then
        return tonumber(value) or fallback
    end
    return clamp(value, lim[1], lim[2])
end

local function clampMap(src)
    local out = {}
    if type(src) ~= 'table' then return out end
    for k, v in pairs(src) do
        if type(v) == 'number' then
            out[k] = clampField(k, v, v)
        elseif type(v) == 'table' then
            out[k] = clampMap(v)
        end
    end
    return out
end

local function clampDamage(src)
    src = type(src) == 'table' and src or {}
    return {
        engineBelow = clamp(src.engineBelow, 50.0, 1000.0),
        engineForceMult = clamp(src.engineForceMult, 0.10, 1.00),
        bodyBelow = clamp(src.bodyBelow, 50.0, 1000.0),
        tractionMult = clamp(src.tractionMult, 0.30, 1.00),
        panelLimpTraction = clamp(src.panelLimpTraction, 0.40, 1.00),
        panelLimpSteer = clamp(src.panelLimpSteer, 0.40, 1.00),
        oilCriticalForce = clamp(src.oilCriticalForce, 0.15, 1.00),
    }
end

function LunarVeh.ClampPerf(perf)
    if type(perf) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(perf) do
        out[k] = v
    end
    if out.power ~= nil then out.power = clampField('power', out.power, 1.0) end
    if out.top ~= nil then out.top = clampField('top', out.top, 1.0) end
    return out
end

function LunarVeh.SealHandling()
    local h = Config.Handling or {}
    return {
        enabled = h.enabled ~= false,
        global = clampMap(h.global),
        globalAdd = clampMap(h.globalAdd),
        kits = clampMap(h.kits),
        damage = clampDamage(h.damage),
        limits = LIMITS,
    }
end

QBCore.Functions.CreateCallback('lunar-vehicles:handlingProfile', function(_, cb)
    cb(LunarVeh.SealHandling())
end)
