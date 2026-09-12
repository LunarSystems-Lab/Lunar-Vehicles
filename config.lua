-- lunar-vehicles — buyer-facing config (data only)
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

Config = {}

Config.Enabled = true
Config.Debug = false

-- Persist into player_vehicles.mods.lunarState (same JSON blob as lunarPerf).
Config.Persist = true
Config.SaveIntervalMs = 45000
Config.SaveOnExit = true

-- Boats, helis, planes, trains, cycles. Set [8] = false to include motorcycles.
Config.IgnoreClasses = {
    [8] = true,
    [13] = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [21] = true,
}

Config.Oil = {
    enabled = true,
    max = 100.0,
    startFull = true,
    idleBurn = 0.004,
    throttleBurn = 0.018,
    highRpm = 0.72,
    highRpmMult = 2.1,
    critical = 12.0,
    warn = 28.0,
    criticalDamagePerSec = 1.8,
    showAlways = false,
    holdKey = 20, -- Z
}

Config.Panels = {
    enabled = true,
    list = {
        { id = 'bumper_f', label = 'Front bumper', bone = 'bumper_f', offset = vector3(0.0, 2.4, 0.15) },
        { id = 'bumper_r', label = 'Rear bumper', bone = 'bumper_r', offset = vector3(0.0, -2.4, 0.15) },
        { id = 'door_lf', label = 'Driver door', bone = 'door_dside_f', offset = vector3(-0.9, 0.3, 0.2) },
        { id = 'door_rf', label = 'Passenger door', bone = 'door_pside_f', offset = vector3(0.9, 0.3, 0.2) },
        { id = 'door_lr', label = 'Rear left door', bone = 'door_dside_r', offset = vector3(-0.9, -0.6, 0.2) },
        { id = 'door_rr', label = 'Rear right door', bone = 'door_pside_r', offset = vector3(0.9, -0.6, 0.2) },
        { id = 'hood', label = 'Bonnet', bone = 'bonnet', offset = vector3(0.0, 1.6, 0.45) },
        { id = 'boot', label = 'Boot', bone = 'boot', offset = vector3(0.0, -1.7, 0.4) },
        { id = 'wing_lf', label = 'Left wing', bone = 'wing_lf', offset = vector3(-0.95, 1.1, 0.35) },
        { id = 'wing_rf', label = 'Right wing', bone = 'wing_rf', offset = vector3(0.95, 1.1, 0.35) },
        { id = 'glass_f', label = 'Windscreen', bone = 'windscreen', offset = vector3(0.0, 0.55, 0.7) },
    },
    smashBelow = 28.0,
    limpBelow = 45.0,
    collisionScale = 0.22,
    minImpulse = 4.0,
    tickMs = 400,
}

-- GTA wheel ids: 0 FL, 1 FR, 4 RL, 5 RR (2/3 are mid-axle).
Config.Tyres = {
    persist = true,
    wheels = { 0, 1, 4, 5 },
}

Config.Health = {
    engineFloor = 50.0, -- wreck stays below explode-the-block
    crashEngineScale = 0.55,
    crashBodyScale = 1.0,
    enforceEngine = true,
    enforceBody = true,
    tickMs = 250,
}

-- Loss = (speed drop in m/s)^2 * K. 80 mph wall ≈ 36 m/s → write-off.
Config.Crash = {
    enabled = true,
    minDelta = 4.2,
    engineK = 0.78,
    bodyK = 0.95,
    tankK = 0.18,
    maxEngineHit = 1000.0,
    maxBodyHit = 980.0,
    writeOffDelta = 26.0,
    writeOffEngine = 80.0,
    writeOffBody = 70.0,
    stallBelow = 180.0,
    undriveableBelow = 110.0,
    burstTyresAbove = 11.0,
    smashWindowsAbove = 12.0,
    breakDoorsAbove = 20.0,
    cooldownMs = 380,
    playerHurtDelta = 14.0,
    playerKillDelta = 26.0,
    playerHurtK = 0.42,
    -- Stock qb-ambulancejob: first down = laststand. Hard crash finishes them.
    finishLaststand = true,
}

-- Stop the *car* cooking off. Occupants are not crash-proof.
Config.Safety = {
    noVehicleExplode = true,
    tankFloor = 550.0,
}

-- qb-target + ps-ui Circle. advancedrepairkit = mechanic rebuild.
-- repairkit = anyone, limp-home only.
Config.Repairs = {
    enabled = true,
    distance = 2.5,
    anim = {
        dict = 'mini@repair',
        clip = 'fixing_a_player',
        flag = 1,
    },
    advanced = {
        item = 'advancedrepairkit',
        label = 'Repair engine',
        icon = 'fas fa-wrench',
        requireJob = 'mechanic',
        requireDuty = true,
        durationMs = 12000,
        healTo = 1000.0,
        minDamage = 980.0,
        circle = { circles = 2, seconds = 12 },
        fixTyres = true,
    },
    basic = {
        item = 'repairkit',
        label = 'Field repair',
        icon = 'fas fa-screwdriver-wrench',
        requireJob = false,
        requireDuty = false,
        durationMs = 13200,
        healTo = 350.0,
        healCap = 400.0,
        minDamage = 350.0,
        circle = { circles = 3, seconds = 7 },
        fixTyres = false,
    },
}

-- Multipliers live in config.handling.lua (server-only). The client apply
-- loop never reads Config.Handling.global / kits — only a sealed snapshot.
Config.Handling = {
    enabled = true,
    reapplyMs = 400,
    sealRefreshMs = 20000,
}

Config.Defaults = {
    oil = 92.0,
    engine = 1000.0,
    body = 1000.0,
    tank = 1000.0,
    mileage = 0.0,
}

function Config.DefaultState()
    local panels = {}
    for i = 1, #(Config.Panels.list or {}) do
        panels[Config.Panels.list[i].id] = 100.0
    end
    return {
        oil = Config.Defaults.oil,
        oilGrade = 'STOCK',
        engine = Config.Defaults.engine,
        body = Config.Defaults.body,
        tank = Config.Defaults.tank,
        mileage = Config.Defaults.mileage,
        panels = panels,
        tyres = {},
        version = 2,
    }
end

function Config.MergeState(raw)
    local base = Config.DefaultState()
    if type(raw) ~= 'table' then return base end
    for k, v in pairs(raw) do
        if k == 'panels' and type(v) == 'table' then
            for id, hp in pairs(v) do
                base.panels[id] = tonumber(hp) or base.panels[id]
            end
        elseif k == 'tyres' and type(v) == 'table' then
            base.tyres = {}
            for id, on in pairs(v) do
                if on then base.tyres[tostring(id)] = true end
            end
        else
            base[k] = v
        end
    end
    return base
end
