local QBCore = exports['qb-core']:GetCoreObject()

local TrackedPlayers = {}

-- Store player status immediately when they join
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source

    -- Immediately cache their state
    TrackedPlayers[src] = {
        cid = Player.PlayerData.citizenid,
        isDead = Player.PlayerData.metadata["isdead"],
        isInLaststand = Player.PlayerData.metadata["inlaststand"],
        isCuffed = Player.PlayerData.metadata["ishandcuffed"],
        name = GetPlayerName(src)
    }

    -- Check for anti-LTARP prison flag
    local prisonFlag = Player.PlayerData.metadata["antiLTARPPrison"]
    if prisonFlag then
        exports['qb-prison']:SendToPrison(src, 30, "LTARP: Disconnect while cuffed")
        Player.Functions.SetMetaData("antiLTARPPrison", false)
        print(("[ANTI-LTARP] %s sent to prison for 30 mins for LTARP"):format(Player.PlayerData.citizenid))
    end
end)

-- Background status tracker (updates every 2 seconds)
CreateThread(function()
    while true do
        Wait(2000)
        for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
            local Player = QBCore.Functions.GetPlayer(tonumber(playerId))
            if Player then
                TrackedPlayers[Player.PlayerData.source] = {
                    cid = Player.PlayerData.citizenid,
                    isDead = Player.PlayerData.metadata["isdead"],
                    isInLaststand = Player.PlayerData.metadata["inlaststand"],
                    isCuffed = Player.PlayerData.metadata["ishandcuffed"],
                    name = GetPlayerName(Player.PlayerData.source)
                }
            end
        end
    end
end)

-- Handle player disconnect
AddEventHandler('playerDropped', function(reason)
    local src = source
    local track = TrackedPlayers[src]

    if not track then
        print("[ANTI-LTARP] No tracked data for dropped player: " .. tostring(src))
        return
    end

    print(("[ANTI-LTARP DEBUG] %s (%s) dropped | Dead: %s | InLaststand: %s | Cuffed: %s | Reason: %s"):format(
        track.name or "Unknown",
        track.cid or "N/A",
        tostring(track.isDead),
        tostring(track.isInLaststand),
        tostring(track.isCuffed),
        reason
    ))

    if track.isDead or track.isInLaststand then
        local license = nil
        for _, id in pairs(GetPlayerIdentifiers(src)) do
            if string.find(id, "license:") then
                license = id
                break
            end
        end

        if license then
            local expire = os.time() + (2 * 24 * 60 * 60) -- 2 days from now
            exports.oxmysql:insert('INSERT INTO bans (license, name, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?)', {
                license,
                track.name or "Unknown",
                "LTARP - Disconnected while dead or in laststand",
                expire,
                "LTARP System"
            })
            print(("[ANTI-LTARP] %s (%s) was banned (DB insert) for 2 days for LTARP"):format(track.name, license))
        else
            print("[ANTI-LTARP] No license identifier found, unable to insert DB ban.")
        end


    elseif track.isCuffed then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local metadata = Player.PlayerData.metadata
            metadata["antiLTARPPrison"] = true
            Player.Functions.SetMetaData("metadata", metadata)
            Player.Functions.Save()
        end
        print(("[ANTI-LTARP] %s (%s) disconnected while cuffed — flagged for 30min prison on reconnect."):format(track.name, track.cid))
    end

    TrackedPlayers[src] = nil
end)


-- Debug command
QBCore.Commands.Add("bleedstatus", "Check if you're flagged as dead or in laststand", {}, false, function(source)
    local track = TrackedPlayers[source]
    if track then
        local msg = ("Tracked status for %s (%s): isDead = %s | isInLaststand = %s | isCuffed = %s"):format(
            track.name or "Unknown",
            track.cid or "N/A",
            tostring(track.isDead),
            tostring(track.isInLaststand),
            tostring(track.isCuffed)
        )

        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 255, 0},
            multiline = false,
            args = {"System", msg}
        })

        print("[ANTI-LTARP DEBUG] /bleedstatus → " .. msg)
    else
        TriggerClientEvent("chat:addMessage", source, {
            color = {255, 0, 0},
            multiline = false,
            args = {"System", "No tracked status found for you."}
        })
        print("[ANTI-LTARP DEBUG] /bleedstatus → no tracked data for source " .. source)
    end
end)
