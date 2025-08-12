local QBCore = exports['qb-core']:GetCoreObject()

local isOpen, isStaff = false, false

local function openUI(defaultTab)
    if isOpen then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', tab = defaultTab or 'warnings' })
    TriggerServerEvent('pc:server:Init')
    if (defaultTab or 'warnings') == 'warnings' then
        TriggerServerEvent('qb-warnings:server:RequestWarnings')
    elseif defaultTab == 'manager' then
        TriggerServerEvent('pc:server:RequestReportList')
    elseif defaultTab == 'warnmgr' then
        TriggerServerEvent('pc:server:GetAllWarnings', '')
    end
end

RegisterCommand('warnings', function() openUI('warnings') end, false)
RegisterCommand('report',   function() openUI('report')   end, false)
RegisterCommand('reports',  function() openUI('manager')  end, false)
RegisterCommand('warns',    function() openUI('warnmgr')  end, false)
RegisterCommand('tools',    function() openUI('tools')    end, false)

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
    if isOpen then
        isOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end
    cb(true)
end)

RegisterNUICallback('requestWarnings', function(_, cb)
    TriggerServerEvent('qb-warnings:server:RequestWarnings'); cb(true)
end)

RegisterNUICallback('submitReport', function(data, cb)
    TriggerServerEvent('qb-warnings:server:SubmitReport', data or {}); cb(true)
end)

RegisterNUICallback('managerRequestList', function(_, cb)
    TriggerServerEvent('pc:server:RequestReportList'); cb(true)
end)

RegisterNUICallback('managerClaim', function(data, cb)
    TriggerServerEvent('pc:server:ClaimReport', tonumber(data.reportId)); cb(true)
end)

RegisterNUICallback('managerUnclaim', function(data, cb)
    TriggerServerEvent('pc:server:UnclaimReport', tonumber(data.reportId)); cb(true)
end)

RegisterNUICallback('managerDelete', function(data, cb)
    local id = tonumber(data.reportId); if not id then cb(true) return end
    local result = lib.alertDialog({
        header = 'Delete report?',
        content = ('Are you sure you want to delete report #%s?'):format(id),
        centered = true, cancel = true,
        labels = { confirm = 'Delete', cancel = 'Cancel' }
    })
    if result == 'confirm' then TriggerServerEvent('pc:server:DeleteReport', id) end
    cb(true)
end)

RegisterNUICallback('managerTeleport', function(data, cb)
    TriggerServerEvent('pc:server:TeleportToReporter', tonumber(data.reportId)); cb(true)
end)
RegisterNUICallback('managerBring', function(data, cb)
    TriggerServerEvent('pc:server:BringReporter', tonumber(data.reportId)); cb(true)
end)
RegisterNUICallback('managerHeal', function(data, cb)
    TriggerServerEvent('pc:server:HealReporter', tonumber(data.reportId)); cb(true)
end)
RegisterNUICallback('managerRevive', function(data, cb)
    TriggerServerEvent('pc:server:ReviveReporter', tonumber(data.reportId)); cb(true)
end)

RegisterNUICallback('reportMessage', function(data, cb)
    TriggerServerEvent('pc:server:ReportMessage', tonumber(data.reportId), tostring(data.text or '')); cb(true)
end)

RegisterNUICallback('managerRequestChat', function(data, cb)
    local id = tonumber(data.reportId); if id then TriggerServerEvent('pc:server:RequestChat', id) end; cb(true)
end)
RegisterNUICallback('managerWatch', function(data, cb)
    local id = tonumber(data.reportId); if id then TriggerServerEvent('pc:server:WatchReport', id) end; cb(true)
end)
RegisterNUICallback('managerUnwatch', function(data, cb)
    local id = tonumber(data.reportId); if id then TriggerServerEvent('pc:server:UnwatchReport', id) end; cb(true)
end)

RegisterNUICallback('createWarning', function(data, cb)
    TriggerServerEvent('pc:server:CreateWarning', data or {}); cb(true)
end)
RegisterNUICallback('deleteWarning', function(data, cb)
    local warnId = tonumber(data.warnId)
    if not warnId then cb(true) return end
    local result = lib.alertDialog({
        header = 'Delete warning?',
        content = ('Are you sure you want to delete warning ID %s?'):format(warnId),
        centered = true, cancel = true,
        labels = { confirm = 'Delete', cancel = 'Cancel' }
    })
    if result == 'confirm' then TriggerServerEvent('qb-warnings:server:DeleteWarning', warnId) end
    cb(true)
end)
RegisterNUICallback('getAllWarnings', function(data, cb)
    TriggerServerEvent('pc:server:GetAllWarnings', tostring(data and data.query or '')); cb(true)
end)

RegisterNUICallback('staffAction', function(data, cb)
    TriggerServerEvent('pc:server:StaffAction', data or {}); cb(true)
end)

-- Server -> Client

RegisterNetEvent('pc:client:LogEvent', function(entry)
    SendNUIMessage({ action = 'logEvent', entry = entry })
end)
RegisterNetEvent('pc:client:LogHistory', function(entries)
    SendNUIMessage({ action = 'logHistory', entries = entries or {} })
end)

RegisterNetEvent('pc:client:InitData', function(data)
    isStaff = data.isStaff or false
    SendNUIMessage({ action = 'init', isStaff = isStaff, myReport = data.myReport or false })
end)

RegisterNetEvent('qb-warnings:client:ShowWarnings', function(warnings)
    SendNUIMessage({ action = 'setWarnings', warnings = warnings or {} })
end)

RegisterNetEvent('qb-warnings:client:NotifyDeleted', function(success)
    SendNUIMessage({ action = 'notify', success = success })
    if success then TriggerServerEvent('qb-warnings:server:RequestWarnings') end
end)

RegisterNetEvent('pc:client:ReportList', function(list)
    SendNUIMessage({ action = 'managerList', reports = list or {} })
end)

RegisterNetEvent('pc:client:ReportUpdated', function(report)
    SendNUIMessage({ action = 'managerUpdate', report = report })
end)

RegisterNetEvent('pc:client:ReportMyStatus', function(myReport)
    SendNUIMessage({ action = 'myReport', myReport = myReport or false })
end)

RegisterNetEvent('pc:client:ReportChatMessage', function(payload)
    SendNUIMessage({ action = 'chatMessage', msg = payload })
end)

RegisterNetEvent('pc:client:ReportChatHistory', function(reportId, history)
    SendNUIMessage({ action = 'chatHistory', reportId = reportId, history = history or {} })
end)

RegisterNetEvent('pc:client:WarnCreated', function(ok, msg)
    SendNUIMessage({ action = 'warnResult', success = ok, message = msg or (ok and 'Warning created.' or 'Failed to create warning') })
end)

RegisterNetEvent('pc:client:AllWarnings', function(rows)
    SendNUIMessage({ action = 'allWarnings', rows = rows or {} })
end)

RegisterNetEvent('pc:client:WarnsDirty', function()
    SendNUIMessage({ action = 'warnsDirty' })
end)

-- Actions
RegisterNetEvent('pc:client:Heal', function()
    local ped = cache and cache.ped or PlayerPedId()
    SetEntityHealth(ped, math.max(GetEntityHealth(ped), 200))
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('pc:client:Revive', function()
    local ped = cache and cache.ped or PlayerPedId()
    ResurrectPed(ped); SetEntityHealth(ped, 200)
    ClearPedTasksImmediately(ped); ClearPedBloodDamage(ped)
end)

RegisterNetEvent('pc:client:_tpToCoords', function(c)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
end)

-- ox_lib notifications
RegisterNetEvent('pc:client:Notify', function(data)
    if type(data) ~= 'table' then return end
    data.position = data.position or 'top-right'
    data.duration = data.duration or 5000
    lib.notify(data)
end)

-- Close handling
CreateThread(function()
    while true do
        if isOpen then
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 18, true)
            DisableControlAction(0, 106, true)
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 200) then
                isOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'close' })
            end
        else
            Wait(250)
        end
        Wait(0)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)

-- === Live Logs (client capture) ===
-- baseevents: deaths/kills
AddEventHandler('baseevents:onPlayerDied', function(killerType, deathCoords)
    TriggerServerEvent('pc:log:Submit', {
        kind = 'DIED',
        info = { killerType = killerType or 'unknown', x = deathCoords and deathCoords.x, y = deathCoords and deathCoords.y, z = deathCoords and deathCoords.z }
    })
end)



-- vehicle enter/exit
RegisterNetEvent('baseevents:enteredVehicle', function(veh, seat, displayName)
    TriggerServerEvent('pc:log:Submit', {
        kind = 'ENTER_VEH',
        info = { seat = seat, name = displayName or 'vehicle' }
    })
end)
RegisterNetEvent('baseevents:leftVehicle', function(veh, seat, displayName)
    TriggerServerEvent('pc:log:Submit', {
        kind = 'EXIT_VEH',
        info = { seat = seat, name = displayName or 'vehicle' }
    })
end)

-- (Optional) Detect VDM via damage event on *victim* side
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    -- args vary; conservative heuristic:
    local victim = args[1]
    local attacker = args[2]
    if not (victim and attacker) then return end
    if not IsEntityAVehicle(attacker) then return end
    local myPed = PlayerPedId()
    if victim ~= myPed then return end
    local atkOwner = NetworkGetEntityOwner(attacker)
    if not atkOwner then return end
    TriggerServerEvent('pc:log:Submit', {
        kind = 'VDM',
        target = { id = GetPlayerServerId(PlayerId()), name = GetPlayerName(PlayerId()) or 'Me' },
        info = {}
    })
end)

-- NUI -> server: ask for history when Logs tab opens
RegisterNUICallback('logRequestHistory', function(_, cb)
    TriggerServerEvent('pc:log:RequestHistory')
    cb(true)
end)

-- Ask history when Logs tab opens (NUI calls this)
RegisterNUICallback('logRequestHistory', function(_, cb)
    TriggerServerEvent('pc:log:RequestHistory'); cb(true)
end)

-- Receive history + live
RegisterNetEvent('pc:client:LogHistory', function(entries)
    SendNUIMessage({ action='logHistory', entries = entries or {} })
end)
RegisterNetEvent('pc:client:LogEvent', function(entry)
    SendNUIMessage({ action='logEvent', entry = entry })
end)

-- VDM detection (victim-side)
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim = args[1]; local attacker = args[2]
    if not (victim and attacker) then return end
    if not IsEntityAVehicle(attacker) then return end
    if victim ~= PlayerPedId() then return end
    local atkOwner = NetworkGetEntityOwner(attacker); if not atkOwner then return end
    TriggerServerEvent('pc:log:Submit', {
        kind = 'VDM',
        target = { id = GetPlayerServerId(PlayerId()), name = GetPlayerName(PlayerId()) or 'Me' },
        info = {}
    })
end)

-- Victim resolves killer and reports to server (single source of truth)
local function resolveKillerServerIdFromEntity(ent)
    if not ent or ent == 0 then return -1 end
    if IsEntityAPed(ent) then
        local idx = NetworkGetPlayerIndexFromPed(ent)
        if idx ~= -1 then return GetPlayerServerId(idx) end
    elseif IsEntityAVehicle(ent) then
        local driver = GetPedInVehicleSeat(ent, -1)
        if driver and driver ~= 0 then
            local idx = NetworkGetPlayerIndexFromPed(driver)
            if idx ~= -1 then return GetPlayerServerId(idx) end
        end
    end
    return -1
end

AddEventHandler('baseevents:onPlayerKilled', function(killerId, data)
    local killerServerId = tonumber(killerId) or -1
    if killerServerId == -1 then
        local ent = GetPedSourceOfDeath(PlayerPedId())
        killerServerId = resolveKillerServerIdFromEntity(ent)
    end
    local whash = data and (data.weaponHash or data.weaponhash or data.weapon) or nil
    TriggerServerEvent('pc:log:SubmitKill', killerServerId, whash)
end)

-- === DAMAGE LOG (victim-side) ===
local lastHealth = GetEntityHealth(PlayerPedId())
local function pedDist(a,b) if not a or not b then return 0.0 end return #(GetEntityCoords(a)-GetEntityCoords(b)) end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim = args[1]; if victim ~= PlayerPedId() then return end

    local attacker = args[2]
    local weaponHash = args[5]          -- weapon hash from event (works on most builds)
    local isMelee   = args[10] == 1     -- sometimes indicates melee
    local bone, fatal = GetPedLastDamageBone(victim)
    local headshot = (bone == 31086 or bone == 12844) -- head/neck bones

    local atkServerId = -1
    if attacker and attacker ~= 0 then
        if IsEntityAPed(attacker) then
            local idx = NetworkGetPlayerIndexFromPed(attacker)
            if idx and idx ~= -1 then atkServerId = GetPlayerServerId(idx) end
        elseif IsEntityAVehicle(attacker) then
            local driver = GetPedInVehicleSeat(attacker, -1)
            if driver and driver ~= 0 then
                local idx = NetworkGetPlayerIndexFromPed(driver)
                if idx and idx ~= -1 then atkServerId = GetPlayerServerId(idx) end
            end
        end
    end

    local ped = PlayerPedId()
    local cur = GetEntityHealth(ped)
    local dmg = (lastHealth - cur)
    if dmg <= 0 then return end                  -- ignore healing/zero
    lastHealth = cur

    local dist = 0.0
    if attacker and attacker ~= 0 then
        local aPed = attacker
        if IsEntityAVehicle(attacker) then aPed = GetPedInVehicleSeat(attacker, -1) end
        if aPed and aPed ~= 0 then dist = pedDist(ped, aPed) end
    end

    TriggerServerEvent('pc:log:Damage', {
        attacker = atkServerId,                 -- -1 if unknown/NPC
        weaponHash = weaponHash,
        headshot = headshot and true or false,
        melee = isMelee and true or false,
        damage = dmg,
        distance = dist
    })
end)

-- keep this up to date across respawns
CreateThread(function()
    while true do
        Wait(1000)
        local p = PlayerPedId()
        local h = GetEntityHealth(p)
        if h > lastHealth + 5 or h < lastHealth - 5 then lastHealth = h end
    end
end)
