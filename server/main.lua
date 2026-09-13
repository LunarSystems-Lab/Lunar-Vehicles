-- lunar-vehicles — persist lunarState into player_vehicles.mods
-- Copyright (C) 2026 Lunar
-- SPDX-License-Identifier: GPL-3.0-only

local QBCore = exports['qb-core']:GetCoreObject()

local function normPlate(p)
    if type(p) ~= 'string' then return '' end
    return (p:gsub('%s+', ''):upper())
end

local function readMods(plate)
    plate = normPlate(plate)
    if plate == '' then return nil, nil end
    local row = MySQL.single.await(
        'SELECT plate, mods FROM player_vehicles WHERE REPLACE(plate, " ", "") = ? LIMIT 1',
        { plate }
    )
    if not row then return nil, nil end
    local stored = {}
    if type(row.mods) == 'string' and row.mods ~= '' then
        local ok, decoded = pcall(json.decode, row.mods)
        if ok and type(decoded) == 'table' then stored = decoded end
    end
    return stored, row.plate
end

local function writeMods(rowPlate, stored)
    if not rowPlate or type(stored) ~= 'table' then return false end
    local ok = MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', {
        json.encode(stored),
        rowPlate,
    })
    return ok and true or false
end

local function getState(plate)
    local stored = readMods(plate)
    if not stored then
        return Config.MergeState(nil), false
    end
    return Config.MergeState(stored.lunarState), true
end

local function setState(plate, patch, replace)
    local stored, rowPlate = readMods(plate)
    if not stored or not rowPlate then
        return false, 'ungaraged'
    end
    local cur = Config.MergeState(stored.lunarState)
    if replace and type(patch) == 'table' then
        cur = Config.MergeState(patch)
    elseif type(patch) == 'table' then
        for k, v in pairs(patch) do
            if k == 'panels' and type(v) == 'table' then
                cur.panels = cur.panels or {}
                for id, hp in pairs(v) do
                    cur.panels[id] = math.max(0.0, math.min(100.0, tonumber(hp) or 0.0))
                end
            elseif k == 'tyres' and type(v) == 'table' then
                cur.tyres = {}
                for id, on in pairs(v) do
                    if on then cur.tyres[tostring(id)] = true end
                end
            else
                cur[k] = v
            end
        end
    end
    if cur.oil then cur.oil = math.max(0.0, math.min(100.0, tonumber(cur.oil) or 0.0)) end
    if cur.engine then cur.engine = math.max(0.0, math.min(1000.0, tonumber(cur.engine) or 1000.0)) end
    if cur.body then cur.body = math.max(0.0, math.min(1000.0, tonumber(cur.body) or 1000.0)) end
    cur.oilTemp = nil
    stored.lunarState = cur
    if not writeMods(rowPlate, stored) then
        return false, 'save'
    end
    return true, cur
end

QBCore.Functions.CreateCallback('lunar-vehicles:loadState', function(source, cb, plate)
    plate = normPlate(plate)
    if plate == '' then
        cb({
            ok = false,
            state = Config.DefaultState(),
            owned = false,
            handling = LunarVeh.SealHandling and LunarVeh.SealHandling() or nil,
        })
        return
    end
    local state, owned = getState(plate)
    local stored = readMods(plate)
    local perf = stored and stored.lunarPerf or nil
    if LunarVeh.ClampPerf then
        perf = LunarVeh.ClampPerf(perf)
    end
    cb({
        ok = true,
        state = state,
        owned = owned and true or false,
        perf = perf,
        handling = LunarVeh.SealHandling and LunarVeh.SealHandling() or nil,
    })
end)

QBCore.Functions.CreateCallback('lunar-vehicles:saveState', function(source, cb, data)
    if not Config.Persist then
        cb({ ok = true, skipped = true })
        return
    end
    local plate = normPlate(data and data.plate)
    if plate == '' or type(data and data.state) ~= 'table' then
        cb({ ok = false })
        return
    end
    local patch = {
        oil = tonumber(data.state.oil),
        oilGrade = type(data.state.oilGrade) == 'string' and data.state.oilGrade:sub(1, 12) or nil,
        engine = tonumber(data.state.engine),
        body = tonumber(data.state.body),
        tank = tonumber(data.state.tank),
        mileage = tonumber(data.state.mileage),
        panels = type(data.state.panels) == 'table' and data.state.panels or nil,
        tyres = type(data.state.tyres) == 'table' and data.state.tyres or {},
    }
    local ok, res = setState(plate, patch, false)
    cb({ ok = ok and true or false, state = type(res) == 'table' and res or nil, error = not ok and res or nil })
end)

--- Service oil (called by lunar-mechanic after oil kit fit).
exports('ServiceOil', function(plate, grade, fill)
    plate = normPlate(plate)
    fill = tonumber(fill)
    if not fill then fill = 100.0 end
    if fill > 1.0 and fill <= 1000.0 then
        -- heal-style values from mechanic kits → map to %
        fill = math.min(100.0, (fill / 1000.0) * 100.0)
    end
    fill = math.max(0.0, math.min(100.0, fill))
    local ok, state = setState(plate, {
        oil = fill,
        oilGrade = type(grade) == 'string' and grade:sub(1, 12) or 'Serviced',
    }, false)
    return ok, state, fill
end)

local function bottleCfg(itemName)
    itemName = tostring(itemName or '')
    local list = (Config.Oil and Config.Oil.bottles) or {}
    for i = 1, #list do
        if list[i].item == itemName then return list[i] end
    end
end

local function registerOilBottles()
    if not Config.Oil or Config.Oil.enabled == false then return end
    local list = Config.Oil.bottles or {}
    for i = 1, #list do
        local bottle = list[i]
        local itemName = bottle.item
        if type(itemName) == 'string' and itemName ~= '' then
            QBCore.Functions.CreateUseableItem(itemName, function(source, item)
                TriggerClientEvent('lunar-vehicles:client:useOilBottle', source, itemName)
            end)
        end
    end
    if #list > 0 then
        print(('[lunar-vehicles] %s oil bottle(s) registered'):format(#list))
    end
end

QBCore.Functions.CreateCallback('lunar-vehicles:fillOil', function(source, cb, data)
    if not Config.Oil or Config.Oil.enabled == false then
        cb({ ok = false, message = 'Oil system is disabled.' })
        return
    end
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, message = 'Player missing.' })
        return
    end
    local itemName = tostring(data and data.item or '')
    local bottle = bottleCfg(itemName)
    if not bottle then
        cb({ ok = false, message = 'Unknown oil.' })
        return
    end
    local item = Player.Functions.GetItemByName(itemName)
    if not item or (tonumber(item.amount) or 0) < 1 then
        cb({ ok = false, message = 'You need ' .. (bottle.label or 'oil') .. '.' })
        return
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        cb({ ok = false, message = 'Invalid ped.' })
        return
    end
    local coords = GetEntityCoords(ped)
    local netId = tonumber(data and data.netId)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        cb({ ok = false, message = 'Vehicle gone.' })
        return
    end
    local vcoords = GetEntityCoords(veh)
    local dist = (Config.Oil.fillDistance or 2.8) + 2.0
    if #(coords - vcoords) > dist then
        cb({ ok = false, message = 'Too far from the vehicle.' })
        return
    end

    if not Player.Functions.RemoveItem(itemName, 1) then
        cb({ ok = false, message = 'Could not take the oil.' })
        return
    end
    if GetResourceState('qb-inventory') == 'started' and QBCore.Shared.Items[itemName] then
        TriggerClientEvent('qb-inventory:client:ItemBox', source, QBCore.Shared.Items[itemName], 'remove', 1)
    end

    local fill = tonumber(bottle.fill) or 100.0
    if fill > 100.0 then fill = math.min(100.0, (fill / 1000.0) * 100.0) end
    fill = math.max(0.0, math.min(100.0, fill))
    local grade = type(bottle.grade) == 'string' and bottle.grade:sub(1, 12) or 'Serviced'
    local plate = normPlate(data and data.plate)
    if plate == '' and veh ~= 0 then
        plate = normPlate(GetVehicleNumberPlateText(veh) or '')
    end

    local owned = false
    if plate ~= '' then
        local okSave = setState(plate, { oil = fill, oilGrade = grade }, false)
        owned = okSave and true or false
    end

    TriggerClientEvent('lunar-vehicles:client:oilServiced', source, {
        plate = plate,
        fill = fill,
        grade = grade,
    })

    cb({
        ok = true,
        fill = fill,
        grade = grade,
        owned = owned,
        message = owned
            and (('Filled %s%% %s — logged to the vehicle.'):format(math.floor(fill + 0.5), grade))
            or (('Filled %s%% %s.'):format(math.floor(fill + 0.5), grade)),
    })
end)

CreateThread(function()
    Wait(500)
    registerOilBottles()
end)

exports('RepairEngine', function(plate, amount)
    plate = normPlate(plate)
    amount = tonumber(amount) or 1000.0
    local state = getState(plate)
    local nextHp = math.min(1000.0, (tonumber(state.engine) or 0.0) + amount)
    if amount >= 999.0 then nextHp = 1000.0 end
    return setState(plate, { engine = nextHp }, false)
end)

exports('RepairBody', function(plate, amount)
    plate = normPlate(plate)
    amount = tonumber(amount) or 1000.0
    local state = getState(plate)
    local nextHp = math.min(1000.0, (tonumber(state.body) or 0.0) + amount)
    if amount >= 999.0 then nextHp = 1000.0 end
    local panels = {}
    if amount >= 500.0 then
        for id, _ in pairs(state.panels or {}) do
            panels[id] = 100.0
        end
    end
    local patch = { body = nextHp }
    if next(panels) then
        patch.panels = panels
        patch.tyres = {}
    end
    return setState(plate, patch, false)
end)

exports('RepairPanel', function(plate, panelId, amount)
    plate = normPlate(plate)
    panelId = tostring(panelId or '')
    amount = tonumber(amount) or 100.0
    local state = getState(plate)
    local panels = state.panels or {}
    local cur = tonumber(panels[panelId]) or 100.0
    panels[panelId] = math.min(100.0, cur + amount)
    return setState(plate, { panels = panels }, false)
end)

exports('GetState', function(plate)
    return getState(plate)
end)

exports('SetState', function(plate, patch)
    return setState(plate, patch, false)
end)

QBCore.Functions.CreateCallback('lunar-vehicles:repairEngine', function(source, cb, data)
    local root = Config.Repairs or Config.EngineRepair
    if not root or root.enabled == false then
        cb({ ok = false, message = 'Repairs are disabled.' })
        return
    end
    local kind = tostring(data and data.kind or 'advanced')
    if kind ~= 'basic' and kind ~= 'advanced' then kind = 'advanced' end
    local c = (kind == 'basic' and root.basic) or root.advanced or root
    if type(c) ~= 'table' then
        cb({ ok = false, message = 'Repair config missing.' })
        return
    end

    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        cb({ ok = false, message = 'Player missing.' })
        return
    end

    if c.requireJob and c.requireJob ~= false then
        local job = Player.PlayerData.job
        if not job or job.name ~= c.requireJob then
            cb({ ok = false, message = 'Mechanics only.' })
            return
        end
        if c.requireDuty and job.onduty == false then
            cb({ ok = false, message = 'Go on duty first.' })
            return
        end
    end

    local itemName = c.item or (kind == 'basic' and 'repairkit' or 'advancedrepairkit')
    local item = Player.Functions.GetItemByName(itemName)
    if not item or (tonumber(item.amount) or 0) < 1 then
        cb({
            ok = false,
            message = kind == 'basic' and 'You need a repair kit.' or 'You need an advanced repair kit.',
        })
        return
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        cb({ ok = false, message = 'Invalid ped.' })
        return
    end
    local coords = GetEntityCoords(ped)
    local netId = tonumber(data and data.netId)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        cb({ ok = false, message = 'Vehicle gone.' })
        return
    end
    local vcoords = GetEntityCoords(veh)
    local dist = (root.distance or 2.5) + 3.0
    if #(coords - vcoords) > dist then
        cb({ ok = false, message = 'Too far from the vehicle.' })
        return
    end

    if not Player.Functions.RemoveItem(itemName, 1) then
        cb({ ok = false, message = 'Could not take the kit.' })
        return
    end
    if GetResourceState('qb-inventory') == 'started' and QBCore.Shared.Items[itemName] then
        TriggerClientEvent('qb-inventory:client:ItemBox', source, QBCore.Shared.Items[itemName], 'remove', 1)
    end

    local heal = tonumber(c.healTo) or (kind == 'basic' and 350.0 or 1000.0)
    if kind == 'basic' then
        local cap = tonumber(c.healCap) or 400.0
        if heal > cap then heal = cap end
        -- Never fully restore with a roadside kit
        if heal > 450.0 then heal = 400.0 end
    else
        if heal < 0 then heal = 0 end
        if heal > 1000 then heal = 1000 end
    end

    local plate = normPlate(data and data.plate)
    local owned = false
    if plate ~= '' then
        local patch = { engine = heal + 0.0 }
        if kind == 'advanced' then
            patch.tank = 1000.0
            patch.tyres = {}
        end
        local okSave = setState(plate, patch, false)
        owned = okSave and true or false
    end

    local msg
    if kind == 'basic' then
        msg = 'Field repair done — she\'ll limp to a shop. Get a proper rebuild.'
    else
        msg = owned and 'Engine rebuilt and logged.' or 'Engine rebuilt.'
    end

    cb({
        ok = true,
        kind = kind,
        engine = heal + 0.0,
        owned = owned,
        message = msg,
    })
end)

RegisterNetEvent('lunar-vehicles:server:requestSync', function(netId)
    -- reserved for future entity state-bag broadcast
end)

print(('[lunar-vehicles] %s ready'):format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.2.0'))
