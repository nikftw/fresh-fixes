local _, FF = ...

-- Warlock helper: announce Ritual of Summoning to the group (and optionally
-- whisper the target), plus a queue of people who typed "123" / "summon".
-- Listeners only exist while needed: warlock, the feature on, and (unless
-- allowed) not inside a raid instance. Otherwise nothing is registered.
FF.Init("Summon", function()
    local readable = FF.readable
    local db = FF.DB("summon", {
        announce = true, whisper = true, queue = false, channel = "auto", inRaids = false,
        message = "Summoning %t - please click the portal!",
        messageNoTarget = "Summoning portal is up - please click it!",
        whisperText = "Summoning you now - accept when it pops up.",
        keywords = "123, summon, sum, summ, summon pls, summon please, sum pls, summon plz",
        expiry = 15, removeArrived = true, showTitle = true, width = 200,
    })
    local RITUAL_ID = 698
    local isWarlock = select(2, UnitClass("player")) == "WARLOCK"

    local spellName = C_Spell.GetSpellName
    local ritualName = spellName(RITUAL_ID) or "Ritual of Summoning"

    local queue = {} -- [key] = { name, time }
    local win

    local function refresh()
        if not (isWarlock and db.queue) or not next(queue) then
            if win then
                win:Hide()
            end
            return
        end
        if not win then
            win = FF.ListWindow("Summon", "Summon queue", db.width, 20)
            win:SetTitleShown(db.showTitle)
        end
        local rows, roster, myZone = {}, FF.GuildRoster(), GetRealZoneText()
        local list = {}
        for key, q in pairs(queue) do
            list[#list + 1] = { key = key, q = q }
        end
        table.sort(list, function(a, b)
            return a.q.time < b.q.time
        end)
        for _, e in ipairs(list) do
            local r = roster[e.key]
            local zone = r and r.zone or "?"
            local u = FF.UnitByKey(e.key)
            local class = u and select(2, UnitClass(u))
            rows[#rows + 1] = {
                text = FF.ClassColor(class, e.q.name),
                right = zone == myZone and "|cff00ff00here|r" or zone,
                tooltip = e.q.name .. "\n" .. zone .. "\nClick to remove",
                onClick = function()
                    queue[e.key] = nil
                    refresh()
                end,
            }
        end
        win:SetRows(rows)
        win:Show()
    end

    local function words()
        local w = {}
        for k in (db.keywords or ""):gmatch("[^,]+") do
            k = k:match("^%s*(.-)%s*$"):lower()
            if k ~= "" then
                w[k] = true
            end
        end
        return w
    end

    local function onChat(_, _, msg, author)
        if not (readable(msg) and readable(author)) then
            return
        end
        local l = msg:lower():match("^%s*(.-)[%s!%.]*$")
        if not words()[l] then
            return
        end
        local display, key = FF.Identity(author)
        if key and key ~= FF.UnitKey("player") then
            queue[key] = { name = display:match("^[^%-]+"), time = GetTime() }
            refresh()
        end
    end
    local chat = CreateFrame("Frame")
    chat:SetScript("OnEvent", onChat)

    -- Drop stale requests and people who arrived (only while the queue listens).
    local function sweep()
        if not next(queue) then
            return
        end
        local now, roster, myZone = GetTime(), FF.GuildRoster(), GetRealZoneText()
        for key, q in pairs(queue) do
            local r = roster[key]
            local u = FF.UnitByKey(key)
            if now - q.time > db.expiry * 60 or not u or (db.removeArrived and r and r.zone == myZone) then
                queue[key] = nil
            end
        end
        refresh()
    end

    local lastAnnounce = 0
    local casts = CreateFrame("Frame")
    casts:SetScript("OnEvent", function(_, _, _, _, spellID)
        if not db.announce or not readable(spellID) then
            return
        end
        if spellID ~= RITUAL_ID and spellName(spellID) ~= ritualName then
            return
        end
        if GetTime() - lastAnnounce < 8 or not IsInGroup() then
            return
        end
        lastAnnounce = GetTime()
        local target
        if UnitExists("target") and UnitIsPlayer("target") and (UnitInParty("target") or UnitInRaid("target")) then
            target = UnitName("target")
            local key = FF.UnitKey("target")
            if key then
                queue[key] = nil
                refresh()
            end
        end
        local channel = db.channel ~= "auto" and db.channel or (IsInRaid() and "RAID" or "PARTY")
        if target then
            SendChatMessage((db.message:gsub("%%t", target)), channel)
            if db.whisper then
                SendChatMessage(db.whisperText, "WHISPER", nil, GetUnitName("target", true))
            end
        else
            SendChatMessage(db.messageNoTarget, channel)
        end
    end)

    ---------------------------------------------------------------------------
    -- Listeners: (re)registered only when something needs them
    ---------------------------------------------------------------------------
    local sweeper
    local function listen()
        local active = isWarlock and (db.inRaids or not FF.InRaidInstance())
        casts:UnregisterAllEvents()
        chat:UnregisterAllEvents()
        if active and db.announce then
            casts:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            casts:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        end
        local q = active and db.queue
        if q then
            for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
                chat:RegisterEvent(ev)
            end
            sweeper = sweeper or C_Timer.NewTicker(20, sweep)
        else
            if sweeper then
                sweeper:Cancel()
                sweeper = nil
            end
            wipe(queue)
            refresh()
        end
    end
    listen()
    if isWarlock then
        FF.On("FF_ZONE", listen) -- re-check when entering / leaving raid instances
    end

    FF.Settings("Summon", function(L)
        local on = function() return db.announce end
        L:Header("Where")
        L:Toggle("Also work inside raid instances", db, "inRaids", { onChange = listen,
            tip = "Off: inside a raid instance the summon helper goes completely quiet" })
        L:Header("Announce Ritual of Summoning")
        L:Toggle("Announce when I summon", db, "announce", { onChange = listen })
        L:Select("Channel", db, "channel", {
            { "auto", "Raid or party" }, { "RAID", "Raid" }, { "PARTY", "Party" }, { "SAY", "Say" }, { "YELL", "Yell" },
        }, { dep = on })
        L:Input("Message (%t = target)", db, "message", { dep = on, width = 300 })
        L:Input("Message with no target", db, "messageNoTarget", { dep = on, width = 300 })
        L:Toggle("Whisper the player being summoned", db, "whisper", { dep = on })
        L:Input("Whisper text", db, "whisperText", { dep = function() return db.announce and db.whisper end, width = 300, indent = 12 })

        L:Header("Summon queue")
        L:Toggle("Show the summon request queue", db, "queue", { onChange = listen, tip = "Only warlocks see it. Listens to party/raid chat only while on." })
        local q = function() return db.queue end
        L:Input("Trigger words", db, "keywords", { dep = q, width = 300, tip = "Comma separated. The whole message must match one." })
        L:Slider("Forget requests after", db, "expiry", 1, 60, 1, { dep = q, fmt = function(v) return v .. " min" end })
        L:Toggle("Remove people who reach my zone", db, "removeArrived", { dep = q })
        L:Slider("Width", db, "width", 100, 300, 10, { dep = q, onChange = function()
            if win then
                win:SetWidth(db.width)
                refresh()
            end
        end })
        L:TitleToggle(db, function() return win end, { dep = q })
        L:Buttons({ { "Clear queue", function() FF.Run("sum clear") end } }, { dep = q })
    end)

    FF.Command("sum", function(rest)
        if rest:lower() == "clear" then
            wipe(queue)
            refresh()
            FF.print("Summon queue cleared")
        else
            FF.print("/ff sum clear - clear the summon queue. Options in /ff")
        end
    end, "summon queue")
end)
