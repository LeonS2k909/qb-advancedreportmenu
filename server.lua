local QBCore = exports['qb-core']:GetCoreObject()

-- === Live Logs ===
local liveLogs = {}            -- ring buffer of recent logs
local MAX_LOGS = 500

local function pushLog(entry)
    entry.id = (liveLogs[#liveLogs] and liveLogs[#liveLogs].id or 0) + 1
    entry.ts = entry.ts or os.time()
    table.insert(liveLogs, entry)
    if #liveLogs > MAX_LOGS then table.remove(liveLogs, 1) end
    -- broadcast to online staff
    for _, pid in pairs(QBCore.Functions.GetPlayers()) do
        if isStaff(pid) then
            TriggerClientEvent('pc:client:LogEvent', pid, entry)
        end
    end
end

-- client -> server: submit a log event
RegisterNetEvent('pc:log:Submit', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    -- normalize
    local e = {
        kind = tostring(payload.kind or 'misc'),    -- 'KILL','VDM','DIED','ENTER_VEH','EXIT_VEH', etc.
        actor = { id = src, name = GetPlayerName(src) or ('src '..src) },
        target = payload.target or nil,             -- { id, name } if applicable
        info = payload.info or {},                  -- free-form
        ts = os.time()
    }
    pushLog(e)

    -- optional ox_lib pop for critical events
    if e.kind == 'KILL' or e.kind == 'VDM' then
        local desc = e.kind == 'KILL'
            and (('%s killed %s (%s)'):format(e.actor.name, e.target and e.target.name or 'unknown', e.info.weapon or 'unknown'))
            or  (('%s ran over %s'):format(e.actor.name, e.target and e.target.name or 'unknown'))
        for _, pid in pairs(QBCore.Functions.GetPlayers()) do
            if isStaff(pid) then
                TriggerClientEvent('pc:client:Notify', pid, { title='Live Log', description=desc, type='warning', duration=6000 })
            end
        end
    end
end)

-- staff requests current buffer
RegisterNetEvent('pc:log:RequestHistory', function()
    local src = source
    if not isStaff(src) then return end
    TriggerClientEvent('pc:client:LogHistory', src, liveLogs)
end)


-- helpers
local function getIdByPrefix(src, prefix)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, #prefix) == prefix then return id end
    end
end
local function lic(src) return getIdByPrefix(src, 'license:') end
local function pname(src) return GetPlayerName(src) or ('src '..tostring(src)) end

local function isStaff(src)
    if QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god') then
        return true
    end
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'qbwarnings.delete') or IsPlayerAceAllowed(src, 'qbcore.admin') then
        return true
    end
    return false
end

local function notify(src, title, description, ttype, dur)
    TriggerClientEvent('pc:client:Notify', src, {
        title = title, description = description, type = ttype or 'inform', duration = dur or 5000
    })
end

-- state
local chatLog      = {} -- [reportId] = { msgs }
local reporterById = {} -- [reportId] = src
local handlerById  = {} -- [reportId] = src
local watchers     = {} -- [reportId] = { [staffSrc] = true }

-- init
RegisterNetEvent('pc:server:Init', function()
    local src = source
    local mylicense = lic(src)
    local staff = isStaff(src)
    exports.oxmysql:execute(
        'SELECT id, status, claimedByName FROM player_reports WHERE reporterIdentifier = ? AND status IN ("open","claimed") ORDER BY id DESC LIMIT 1',
        { mylicense },
        function(rows)
            local myReport = rows and rows[1] or false
            TriggerClientEvent('pc:client:InitData', src, { isStaff = staff, myReport = myReport })
        end
    )
end)

-- warnings: own list + delete
RegisterNetEvent('qb-warnings:server:RequestWarnings', function()
    local src = source
    local l = lic(src); if not l then return end
    exports.oxmysql:execute(
        'SELECT reason, senderIdentifier, id AS warnId FROM player_warns WHERE targetIdentifier = ? ORDER BY id DESC',
        { l },
        function(results)
            TriggerClientEvent('qb-warnings:client:ShowWarnings', src, results or {})
        end
    )
end)

RegisterNetEvent('qb-warnings:server:DeleteWarning', function(warnId)
    local src = source
    if not isStaff(src) then
        TriggerClientEvent('qb-warnings:client:NotifyDeleted', src, false)
        return
    end
    warnId = tonumber(warnId)
    if not warnId then
        TriggerClientEvent('qb-warnings:client:NotifyDeleted', src, false)
        return
    end
    exports.oxmysql:execute('DELETE FROM player_warns WHERE id = ?', { warnId }, function(rowsChanged)
        local ok = (rowsChanged or 0) > 0
        TriggerClientEvent('qb-warnings:client:NotifyDeleted', src, ok)
        if ok then
            notify(src, 'Warnings', ('Warning #%s deleted.'):format(warnId), 'success')
            for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                if isStaff(pid) then TriggerClientEvent('pc:client:WarnsDirty', pid) end
            end
        end
    end)
end)

-- warnings: create + list all
RegisterNetEvent('pc:server:CreateWarning', function(data)
    local src = source
    if not isStaff(src) then
        TriggerClientEvent('pc:client:WarnCreated', src, false, 'No permission.'); return
    end
    if type(data) ~= 'table' then
        TriggerClientEvent('pc:client:WarnCreated', src, false, 'Invalid data.'); return
    end
    local targetId = tonumber(data.targetId)
    local reason = tostring(data.reason or ''):sub(1, 2000)
    if not targetId or reason == '' then
        TriggerClientEvent('pc:client:WarnCreated', src, false, 'Player ID and reason required.'); return
    end
    if GetPlayerPed(targetId) == 0 then
        TriggerClientEvent('pc:client:WarnCreated', src, false, 'Player not online.'); return
    end
    local targetLic = lic(targetId)
    if not targetLic then
        TriggerClientEvent('pc:client:WarnCreated', src, false, 'Target has no identifier.'); return
    end
    local senderLic = lic(src) or 'unknown'
    exports.oxmysql:insert(
        'INSERT INTO player_warns (targetIdentifier, senderIdentifier, reason) VALUES (?, ?, ?)',
        { targetLic, senderLic, reason },
        function(insertId)
            local ok = insertId and insertId > 0
            if ok then
                notify(src, 'Warnings', ('Warning created for %s'):format(pname(targetId)), 'success')
                notify(targetId, 'Warning Received', reason, 'warning', 8000)
                for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                    if isStaff(pid) then TriggerClientEvent('pc:client:WarnsDirty', pid) end
                end
            end
            TriggerClientEvent('pc:client:WarnCreated', src, ok, ok and 'Warning created.' or 'Insert failed.')
        end
    )
end)

RegisterNetEvent('pc:server:GetAllWarnings', function(query)
    local src = source
    if not isStaff(src) then return end
    query = tostring(query or ''):gsub('%%','\\%%')
    local sql = [[
        SELECT id AS warnId, targetIdentifier, senderIdentifier, reason
        FROM player_warns
        WHERE (? = '' OR targetIdentifier LIKE CONCAT('%', ?, '%')
            OR senderIdentifier LIKE CONCAT('%', ?, '%')
            OR reason LIKE CONCAT('%', ?, '%'))
        ORDER BY id DESC
        LIMIT 300
    ]]
    exports.oxmysql:execute(sql, { query, query, query, query }, function(rows)
        TriggerClientEvent('pc:client:AllWarnings', src, rows or {})
    end)
end)

-- reports: submit/list/claim/unclaim/delete
RegisterNetEvent('qb-warnings:server:SubmitReport', function(data)
    local src = source
    if type(data) ~= 'table' then
        TriggerClientEvent('qb-warnings:client:ReportSubmitted', src, false, 'Invalid data.'); return
    end
    local reporter = lic(src); if not reporter then
        TriggerClientEvent('qb-warnings:client:ReportSubmitted', src, false, 'No identifier.'); return
    end
    local targetId = tonumber(data.targetId)
    local targetIdentifier = nil
    if targetId and GetPlayerPed(targetId) ~= 0 then targetIdentifier = lic(targetId) end
    local category = tostring(data.category or ''):sub(1, 48)
    local details  = tostring(data.details  or ''):sub(1, 2000)
    if details == '' then
        TriggerClientEvent('qb-warnings:client:ReportSubmitted', src, false, 'Please add details.'); return
    end

    exports.oxmysql:insert([[
        INSERT INTO player_reports (reporterIdentifier, targetIdentifier, category, details, status, createdAt)
        VALUES (?, ?, ?, ?, "open", NOW())
    ]], { reporter, targetIdentifier, category, details }, function(id)
        local ok = id and id > 0
        if ok then
            reporterById[id] = src
            chatLog[id] = {}
            for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                if isStaff(pid) or QBCore.Functions.HasPermission(pid, 'mod') then
                    notify(pid, 'New Report', ('#%s by %s'):format(id, pname(src)), 'inform', 8000)
                    TriggerClientEvent('pc:client:ReportUpdated', pid, {
                        id = id, reporterName = pname(src), status = 'open',
                        claimedByName = nil, category = category, createdAt = os.date('!%Y-%m-%d %H:%M:%S')
                    })
                end
            end
            TriggerClientEvent('qb-warnings:client:ReportSubmitted', src, true, 'Report submitted.')
            notify(src, 'Report', 'Report submitted. Please keep this window open.', 'success')
            TriggerClientEvent('pc:client:ReportMyStatus', src, { id = id, status = 'open', claimedByName = nil })
        else
            TriggerClientEvent('qb-warnings:client:ReportSubmitted', src, false, 'Failed to save report.')
        end
    end)
end)

RegisterNetEvent('pc:server:RequestReportList', function()
    local src = source
    if not isStaff(src) then return end
    exports.oxmysql:execute([[
        SELECT id, reporterIdentifier, targetIdentifier, category, details, status, claimedByIdentifier, claimedByName, createdAt
        FROM player_reports
        WHERE status IN ("open","claimed")
        ORDER BY id ASC
    ]], {}, function(rows)
        local list = rows or {}
        for _, r in ipairs(list) do
            r.reporterName = 'Offline'
            for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                if lic(pid) == r.reporterIdentifier then r.reporterName = pname(pid); break end
            end
        end
        TriggerClientEvent('pc:client:ReportList', src, list)
    end)
end)

RegisterNetEvent('pc:server:ClaimReport', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local myLic, myName = lic(src), pname(src)
    exports.oxmysql:update([[
        UPDATE player_reports
        SET status="claimed", claimedByIdentifier=?, claimedByName=?
        WHERE id=? AND status IN ("open","claimed")
    ]], { myLic, myName, reportId }, function(changed)
        if (changed or 0) > 0 then
            handlerById[reportId] = src
            local repSrc = reporterById[reportId]
            if repSrc then
                TriggerClientEvent('pc:client:ReportMyStatus', repSrc, { id = reportId, status = 'claimed', claimedByName = myName })
                notify(repSrc, 'Report', ('Your report #%s was claimed by %s'):format(reportId, myName), 'inform')
            end
            for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                if isStaff(pid) then
                    TriggerClientEvent('pc:client:ReportUpdated', pid, { id = reportId, status = 'claimed', claimedByName = myName })
                end
            end
            notify(src, 'Report', ('You claimed report #%s'):format(reportId), 'success')
        end
    end)
end)

RegisterNetEvent('pc:server:UnclaimReport', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    exports.oxmysql:update('UPDATE player_reports SET status="open", claimedByIdentifier=NULL, claimedByName=NULL WHERE id=?',
    { reportId }, function(changed)
        if (changed or 0) > 0 then
            handlerById[reportId] = nil
            local repSrc = reporterById[reportId]
            if repSrc then
                TriggerClientEvent('pc:client:ReportMyStatus', repSrc, { id = reportId, status = 'open', claimedByName = nil })
                notify(repSrc, 'Report', ('Report #%s was unclaimed. Please wait.' ):format(reportId), 'warning')
            end
            for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                if isStaff(pid) then
                    TriggerClientEvent('pc:client:ReportUpdated', pid, { id = reportId, status = 'open', claimedByName = nil })
                end
            end
            notify(src, 'Report', ('You unclaimed report #%s'):format(reportId), 'inform')
        end
    end)
end)

RegisterNetEvent('pc:server:DeleteReport', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    exports.oxmysql:execute('SELECT reporterIdentifier FROM player_reports WHERE id = ? LIMIT 1', { reportId }, function(rows)
        local reporterIdentifier = rows and rows[1] and rows[1].reporterIdentifier or nil
        exports.oxmysql:execute('DELETE FROM player_reports WHERE id = ?', { reportId }, function(changed)
            if (changed or 0) > 0 then
                chatLog[reportId], reporterById[reportId], handlerById[reportId], watchers[reportId] = nil, nil, nil, nil
                if reporterIdentifier then
                    for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                        if lic(pid) == reporterIdentifier then
                            TriggerClientEvent('pc:client:ReportMyStatus', pid, false)
                            notify(pid, 'Report', ('Your report #%s was closed.'):format(reportId), 'inform')
                            break
                        end
                    end
                end
                for _, pid in pairs(QBCore.Functions.GetPlayers()) do
                    if isStaff(pid) then
                        TriggerClientEvent('pc:client:ReportUpdated', pid, { id = reportId, deleted = true })
                    end
                end
                notify(src, 'Report', ('Report #%s deleted'):format(reportId), 'success')
            end
        end)
    end)
end)

-- reporter actions
RegisterNetEvent('pc:server:TeleportToReporter', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local repSrc = reporterById[reportId]; if not repSrc or GetPlayerPed(repSrc) == 0 then return end
    local coords = GetEntityCoords(GetPlayerPed(repSrc))
    TriggerClientEvent('pc:client:_tpToCoords', src, { x = coords.x + 0.5, y = coords.y + 0.5, z = coords.z + 0.5 })
    notify(repSrc, 'Staff', (pname(src) .. ' teleported to you.'), 'inform')
    notify(src, 'Staff', 'Teleported to reporter.', 'success')
end)

RegisterNetEvent('pc:server:BringReporter', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local repSrc = reporterById[reportId]; if not repSrc or GetPlayerPed(repSrc) == 0 then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('pc:client:_tpToCoords', repSrc, { x = coords.x + 0.5, y = coords.y + 0.5, z = coords.z + 0.5 })
    notify(repSrc, 'Staff', ('You were brought to %s'):format(pname(src)), 'inform')
    notify(src, 'Staff', 'Reporter brought to you.', 'success')
end)

RegisterNetEvent('pc:server:HealReporter', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local repSrc = reporterById[reportId]
    if repSrc and GetPlayerPed(repSrc) ~= 0 then
        TriggerClientEvent('pc:client:Heal', repSrc)
        notify(repSrc, 'Staff', 'You were healed by staff.', 'success')
        notify(src, 'Staff', 'Reporter healed.', 'success')
    end
end)

RegisterNetEvent('pc:server:ReviveReporter', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local repSrc = reporterById[reportId]
    if repSrc and GetPlayerPed(repSrc) ~= 0 then
        if GetResourceState('qb-ambulancejob') == 'started' then
            TriggerClientEvent('hospital:client:Revive', repSrc)
        else
            TriggerClientEvent('pc:client:Revive', repSrc)
        end
        notify(repSrc, 'Staff', 'You were revived by staff.', 'success')
        notify(src, 'Staff', 'Reporter revived.', 'success')
    end
end)

-- chat + notifications
RegisterNetEvent('pc:server:ReportMessage', function(reportId, text)
    local src = source
    text = tostring(text or ''):sub(1, 500)
    if text == '' then return end

    -- Work out roles and direct recipient
    local fromRole, toSrc
    if handlerById[reportId] == src then
        fromRole = 'staff'
        toSrc = reporterById[reportId]
    elseif reporterById[reportId] == src then
        fromRole = 'reporter'
        toSrc = handlerById[reportId]
    elseif isStaff(src) then
        fromRole = 'staff'
        toSrc = reporterById[reportId]
    else
        return
    end

    local entry = {
        reportId = reportId,
        from = fromRole,
        name = GetPlayerName(src) or ('src '..src),
        text = text,
        time = os.time()
    }
    chatLog[reportId] = chatLog[reportId] or {}
    table.insert(chatLog[reportId], entry)

    -- 1) Sender always gets the chat echo + "Message sent"
    TriggerClientEvent('pc:client:ReportChatMessage', src, entry)
    notify(src, 'Report', 'Message sent.', 'success', 3000)

    -- 2) Deliver to the direct recipient (can be the same player in self-tests)
    if toSrc then
        TriggerClientEvent('pc:client:ReportChatMessage', toSrc, entry)

        local roleLabel = (fromRole == 'staff') and 'Admin' or 'Reporter'
        local receivedDesc = ('%s: %s'):format(roleLabel, text)

        -- Always show a "received" toast to the recipient — even if recipient == sender
        notify(toSrc, 'Report', receivedDesc, 'inform', 6000)
    end

    -- 3) Any other watching staff also get echo + toast
    local w = watchers[reportId]
    if w then
        for watcherSrc in pairs(w) do
            if watcherSrc ~= src and watcherSrc ~= toSrc then
                TriggerClientEvent('pc:client:ReportChatMessage', watcherSrc, entry)
                notify(watcherSrc, 'Report', ('%s: %s'):format(GetPlayerName(src) or ('src '..src), text), 'inform', 6000)
            end
        end
    end

    -- 4) SPECIAL CASE: self-test while unclaimed (sender is reporter, no handler)
    -- If you have the manager chat open as the same player (you’re your own watcher),
    -- you still want a second "received" toast. Handle that explicitly:
    if (not toSrc or toSrc == src) and w and w[src] then
        local roleLabel = (fromRole == 'staff') and 'Admin' or 'Reporter'
        notify(src, 'Report', ('%s: %s'):format(roleLabel, text), 'inform', 6000)
    end
end)





RegisterNetEvent('pc:server:RequestChat', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    local history = chatLog[reportId] or {}
    TriggerClientEvent('pc:client:ReportChatHistory', src, reportId, history)
end)

RegisterNetEvent('pc:server:WatchReport', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    watchers[reportId] = watchers[reportId] or {}; watchers[reportId][src] = true
end)

RegisterNetEvent('pc:server:UnwatchReport', function(reportId)
    local src = source
    if not isStaff(src) or not reportId then return end
    if watchers[reportId] then watchers[reportId][src] = nil end
end)

-- staff tools on any ID
RegisterNetEvent('pc:server:StaffAction', function(data)
    local src = source
    if not isStaff(src) or type(data) ~= 'table' then return end
    local action = tostring(data.action or '')
    local targetId = tonumber(data.targetId)
    if not targetId or GetPlayerPed(targetId) == 0 then return end

    if action == 'tpTo' then
        local coords = GetEntityCoords(GetPlayerPed(targetId))
        TriggerClientEvent('pc:client:_tpToCoords', src, { x = coords.x + 0.5, y = coords.y + 0.5, z = coords.z + 0.5 })
        notify(targetId, 'Staff', (pname(src) .. ' teleported to you.'), 'inform')
        notify(src, 'Staff', 'Teleported.', 'success')
    elseif action == 'bring' then
        local coords = GetEntityCoords(GetPlayerPed(src))
        TriggerClientEvent('pc:client:_tpToCoords', targetId, { x = coords.x + 0.5, y = coords.y + 0.5, z = coords.z + 0.5 })
        notify(targetId, 'Staff', ('You were brought to %s'):format(pname(src)), 'inform')
        notify(src, 'Staff', 'Player brought.', 'success')
    elseif action == 'heal' then
        TriggerClientEvent('pc:client:Heal', targetId)
        notify(targetId, 'Staff', 'You were healed by staff.', 'success')
        notify(src, 'Staff', 'Player healed.', 'success')
    elseif action == 'revive' then
        if GetResourceState('qb-ambulancejob') == 'started' then
            TriggerClientEvent('hospital:client:Revive', targetId)
        else
            TriggerClientEvent('pc:client:Revive', targetId)
        end
        notify(targetId, 'Staff', 'You were revived by staff.', 'success')
        notify(src, 'Staff', 'Player revived.', 'success')
    end
end)

-- cleanup
AddEventHandler('playerDropped', function()
    local src = source
    for id, s in pairs(reporterById) do if s == src then reporterById[id] = nil end end
    for id, s in pairs(handlerById)  do if s == src then handlerById[id]  = nil end end
    for _, w in pairs(watchers) do w[src] = nil end
end)

-- ==== LIVE LOG CORE (if not already present) ====
local QBCore = exports['qb-core']:GetCoreObject()
local liveLogs, MAX_LOGS = liveLogs or {}, 500
local function isStaff(src)
    return QBCore.Functions.HasPermission(src,'admin') or QBCore.Functions.HasPermission(src,'god') or IsPlayerAceAllowed(src,'command')
end
local function pushLog(entry)
    entry.ts = entry.ts or os.time()
    table.insert(liveLogs, entry); if #liveLogs > MAX_LOGS then table.remove(liveLogs,1) end
    for _, pid in pairs(QBCore.Functions.GetPlayers()) do
        if isStaff(pid) then TriggerClientEvent('pc:client:LogEvent', pid, entry) end
    end
end

-- history for Logs tab
RegisterNetEvent('pc:log:RequestHistory', function()
    local src = source; if not isStaff(src) then return end
    TriggerClientEvent('pc:client:LogHistory', src, liveLogs)
end)

-- client submits detected events (VDM etc.)
RegisterNetEvent('pc:log:Submit', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    payload.actor = payload.actor or { id = src, name = GetPlayerName(src) or ('src '..src) }
    pushLog(payload)
end)

-- ==== GAMEPLAY HOOKS ====

-- Kills / Deaths (baseevents)


AddEventHandler('baseevents:onPlayerDied', function(killerType, deathCoords)
    local victim = source
    pushLog({
        kind = 'DIED',
        actor = { id = victim, name = GetPlayerName(victim) or ('src '..victim) },
        info  = { cause = killerType or 'unknown',
                  x = deathCoords and deathCoords.x, y = deathCoords and deathCoords.y, z = deathCoords and deathCoords.z }
    })
end)

-- Vehicle enter/exit
AddEventHandler('baseevents:enteredVehicle', function(vehNet, seat, displayName)
    local src = source
    pushLog({ kind='ENTER_VEH', actor={ id=src, name=GetPlayerName(src) }, info={ seat=seat, name=displayName or 'vehicle' } })
end)
AddEventHandler('baseevents:leftVehicle', function(vehNet, seat, displayName)
    local src = source
    pushLog({ kind='EXIT_VEH', actor={ id=src, name=GetPlayerName(src) }, info={ seat=seat, name=displayName or 'vehicle' } })
end)

-- Chat → Live Logs (for NUI filter value "CHAT_MESSAGES")
AddEventHandler('chatMessage', function(src, name, msg)
    if not msg or msg:gsub('%s+', '') == '' then return end
    pushLog({
        kind  = 'CHAT_MESSAGES',
        actor = { id = src, name = name or ('src '..src) },
        info  = { text = msg }
    })
    -- do not CancelEvent(); keep normal chat
end)


-- Your report chat -> also log
RegisterNetEvent('pc:server:ReportMessage')  -- already exists; just wrap pushLog inside your handler
AddEventHandler('pc:server:ReportMessage', function(reportId, text)
    -- ...your existing logic...
    local src = source
    pushLog({ kind='REPORT_MSG', actor={ id=src, name=GetPlayerName(src) }, info={ reportId=reportId, text=tostring(text or '') } })
end)

-- === De-dupe helper (put near pushLog) ===
-- de-dupe helper
-- Weapon hash -> nice label
local QBCore = exports['qb-core']:GetCoreObject()
local function weaponLabelFromHash(hash)
    if not hash then return 'unknown' end
    for _, w in pairs(QBCore.Shared.Weapons or {}) do
        if w.hash == hash or (w.name and GetHashKey(w.name) == hash) then
            return w.label or w.name or ('hash:'..tostring(hash))
        end
    end
    return ('hash:'..tostring(hash))
end

-- De-dupe kills
-- keep your QBCore, pushLog(), weaponLabelFromHash() as-is

-- de-dupe: one kill per victim within 1s
-- Weapon hash -> label (QBCore)
local QBCore = exports['qb-core']:GetCoreObject()
local function weaponLabelFromHash(hash)
    if not hash then return 'unknown' end
    for _, w in pairs(QBCore.Shared.Weapons or {}) do
        if w.hash == hash or (w.name and GetHashKey(w.name) == hash) then
            return w.label or w.name or ('hash:'..tostring(hash))
        end
    end
    return ('hash:'..tostring(hash))
end

-- De-dupe: only one KILL per victim within 2s
local recentKills, pending = {}, {}
local function pushKillOnce(killer, victim, info)
    if not killer or not victim then return end
    local now = os.clock()
    local rk = recentKills[victim]
    if rk and (now - rk.t) < 2.0 then return end
    recentKills[victim] = { t = now }
    pushLog({
        kind  = 'KILL',
        actor = { id = killer,  name = GetPlayerName(killer) or ('src '..killer) },
        target= { id = victim,  name = GetPlayerName(victim) or ('src '..victim) },
        info  = info or {}
    })
end

-- Primary path: victim client reports killer (ONLY source of KILL when it arrives)
RegisterNetEvent('pc:log:SubmitKill', function(killerServerId, weaponHash)
    local victim = source
    pending[victim] = nil -- cancel fallback
    if killerServerId and killerServerId > 0 then
        pushKillOnce(killerServerId, victim, {
            weapon     = weaponLabelFromHash(weaponHash),
            weaponHash = weaponHash
        })
    else
        -- unknown killer -> only DIED
        pushLog({
            kind='DIED',
            actor={ id=victim, name=GetPlayerName(victim) or ('src '..victim) },
            info ={ cause='unknown', weapon = weaponLabelFromHash(weaponHash), weaponHash = weaponHash }
        })
    end
end)

-- Fallback: if client didn’t report in time; NEVER logs KILL for killerId <= 0
RegisterNetEvent('baseevents:onPlayerKilled', function(killerId, data)
    local victim = source
    local killer = tonumber(killerId) or -1
    local whash  = data and (data.weaponHash or data.weaponhash or data.weapon) or nil
    pending[victim] = true
    SetTimeout(1200, function()          -- give client 1.2s to report
        if not pending[victim] then return end
        pending[victim] = nil
        if killer > 0 then
            pushKillOnce(killer, victim, { weapon = weaponLabelFromHash(whash), weaponHash = whash })
        else
            pushLog({
                kind='DIED',
                actor={ id=victim, name=GetPlayerName(victim) or ('src '..victim) },
                info ={ cause='unknown', weapon = weaponLabelFromHash(whash), weaponHash = whash }
            })
        end
    end)
end)

-- uses your existing: QBCore, pushLog(), weaponLabelFromHash()

-- rate-limit spam: one DMG per attacker->victim per 250ms; merge small hits
local dmgBucket = {}  -- [victim] = { [attacker]={t, dmg, lastInfo} }
local function flushDmg(victim, attacker)
    local vb = dmgBucket[victim] and dmgBucket[victim][attacker]; if not vb then return end
    local info = vb.lastInfo or {}
    info.damage = vb.dmg
    pushLog({
        kind='DMG',
        actor = { id = attacker, name = attacker>0 and (GetPlayerName(attacker) or ('src '..attacker)) or 'NPC/World' },
        target= { id = victim,   name = GetPlayerName(victim) or ('src '..victim) },
        info  = info
    })
    dmgBucket[victim][attacker] = nil
end

RegisterNetEvent('pc:log:Damage', function(payload)
    local victim = source
    if type(payload) ~= 'table' then return end
    local attacker = tonumber(payload.attacker or -1) or -1
    local now = GetGameTimer()

    dmgBucket[victim] = dmgBucket[victim] or {}
    local vb = dmgBucket[victim][attacker]
    if not vb then
        vb = { t = now, dmg = 0, lastInfo = {} }
        dmgBucket[victim][attacker] = vb
        -- auto-flush after 250ms
        SetTimeout(250, function() flushDmg(victim, attacker) end)
    end

    vb.dmg = vb.dmg + math.floor(tonumber(payload.damage or 0))
    vb.t = now
    vb.lastInfo = {
        weapon     = weaponLabelFromHash(payload.weaponHash),
        weaponHash = payload.weaponHash,
        headshot   = payload.headshot and true or false,
        melee      = payload.melee and true or false,
        distance   = math.floor((payload.distance or 0.0) * 10) / 10.0
    }
end)
