local _, FF = ...
local M = FF.Module("Resurrect")

-- Res tracker + announcer (like the summon helper). A small stack of bars
-- shows who is resurrecting whom, with the cast time left. By default only
-- inside dungeons and raids (nothing runs elsewhere). When you start a res it can
-- be announced in raid/party chat and whispered to the target, and your
-- Fresh Fixes tells the group who you're casting on so every bar is right.
-- Comms tag "Y":  S<target>:<cast ms> (started) · X (stopped)
FF.Init("Resurrect", function()
    local readable = FF.readable
    local db = FF.DB("resurrect", {
        track = true, openWorld = false, maxBars = 8,
        width = 200, scale = 1, showTitle = false,
        announce = true, channel = "auto", message = "Resurrecting %t",
        whisper = true, whisperText = "Resurrecting you - accept when it pops up.",
    })
    local ROW = 18

    -- Resurrection spells by name (every rank shares the name)
    local RES = {
        ["Resurrection"] = true, ["Redemption"] = true, ["Ancestral Spirit"] = true,
        ["Revive"] = true, ["Rebirth"] = true, ["Raise Ally"] = true, ["Resuscitate"] = true,
        ["Return"] = true, ["Revitalize"] = true, ["Mass Resurrection"] = true, ["Absolution"] = true,
        ["Ancestral Vision"] = true, ["Reawaken"] = true, ["Mass Return"] = true,
    }

    local spellName = C_Spell.GetSpellName

    local function isGroupUnit(u)
        return type(u) == "string" and (u == "player" or u:find("^raid%d") or u:find("^party%d")) and true or false
    end

    local casts = {} -- [caster unit name] = { caster, class, target, startT, endT, done }
    local display, rows = nil, {}

    ---------------------------------------------------------------------------
    -- Display
    ---------------------------------------------------------------------------
    -- Flat, borderless, rows flush to the edges. Optional 18px title row.
    local function build()
        display = FF.UI.Display("Resurrect", db.width, ROW, { "CENTER", 0, 200 })
        for _, e in ipairs(display.ffEdges or {}) do
            e:Hide()
        end
        display.ffBg:Hide() -- rows and the title bar carry their own backgrounds
        display.bar = CreateFrame("Frame", nil, display)
        display.bar:SetPoint("TOPLEFT")
        display.bar:SetPoint("TOPRIGHT")
        display.bar:SetHeight(ROW)
        FF.Skin(display.bar, "panel", false)
        display.bar.line = display.bar:CreateTexture(nil, "BORDER")
        display.bar.line:SetPoint("BOTTOMLEFT")
        display.bar.line:SetPoint("BOTTOMRIGHT")
        display.bar.line:SetHeight(1)
        display.bar.line:SetColorTexture(FF.C.border[1], FF.C.border[2], FF.C.border[3], 1)
        display.title = FF.Text(display.bar, "small")
        display.title:SetPoint("LEFT", 5, 0)
        display.title:SetPoint("RIGHT", -5, 0)
        display.title:SetJustifyH("LEFT")
        local acc = 0
        display:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc > 0.1 then
                acc = 0
                M.Refresh()
            end
        end)
        display:Hide()
    end

    local function row(i)
        local r = rows[i]
        if not r then
            r = CreateFrame("Frame", nil, display)
            FF.Skin(r, "bg", false)
            r.fill = r:CreateTexture(nil, "ARTWORK")
            r.fill:SetPoint("TOPLEFT")
            r.fill:SetPoint("BOTTOMLEFT")
            r.text = FF.Text(r, "small")
            r.text:SetPoint("LEFT", 5, 0)
            r.text:SetPoint("RIGHT", -40, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            r.time = FF.Text(r, "small")
            r.time:SetPoint("RIGHT", -5, 0)
            rows[i] = r
        end
        return r
    end


    -- Dungeons and raids only (unless open world is on); nothing runs elsewhere
    local function windowOpen()
        return db.openWorld or FF.InGroupContent()
    end

    function M.Refresh()
        if not display then
            return
        end
        local now = GetTime()
        local list = {}
        for key, c in pairs(casts) do
            if c.done and now > c.done + 2 then
                casts[key] = nil
            else
                list[#list + 1] = c
            end
        end
        table.sort(list, function(a, b)
            return a.endT < b.endT
        end)
        if not windowOpen() or #list == 0 then
            if not display.unlocked then
                display:Hide()
            end
            return
        end
        display:SetWidth(db.width)
        display:SetScale(db.scale)
        local titled = db.showTitle or display.unlocked
        display.bar:SetShown(titled)
        display.title:SetText(display.unlocked and "Resurrections - drag me" or "Resurrections")
        local rowH = FF.PixelHeight(display, ROW)
        display.bar:SetHeight(rowH)
        -- Place the title and rows from the top of the window. Anchoring a
        -- row to the title bar let the first row cover it.
        local y, n = 0, math.min(#list, db.maxBars)
        if titled then
            display.bar:ClearAllPoints()
            display.bar:SetPoint("TOPLEFT", 0, 0)
            display.bar:SetPoint("TOPRIGHT", 0, 0)
            display.bar:SetFrameLevel(display:GetFrameLevel() + 5)
            y = -rowH
        end
        for i = 1, n do
            local c, r = list[i], row(i)
            r:ClearAllPoints()
            r:SetHeight(rowH)
            r:SetPoint("TOPLEFT", 0, y)
            r:SetPoint("TOPRIGHT", 0, y)
            local total = math.max(0.1, c.endT - c.startT)
            local pct = c.done and 1 or math.max(0, math.min(1, (now - c.startT) / total))
            r.fill:SetWidth(math.max(1, db.width * pct))
            r.fill:SetColorTexture(1, 1, 1, c.done and 0.16 or 0.1) -- neutral bar
            r.text:SetText(FF.ClassColor(c.class, c.caster) .. " > " .. FF.ClassColor(c.targetClass, c.target or "?"))
            r.time:SetText(c.done and "done" or ("%d"):format(math.ceil(math.max(0, c.endT - now))))
            r:Show()
            y = y - rowH
        end
        for i = n + 1, #rows do
            rows[i]:Hide()
        end
        display:SetHeight(math.max(rowH, -y))
        display:Show()
    end

    local function wake()
        if not db.track then
            return
        end
        if not display then
            build()
        end
        M.Refresh()
        display:Show()
    end

    ---------------------------------------------------------------------------
    -- Cast tracking
    ---------------------------------------------------------------------------
    local tracker = CreateFrame("Frame")
    local myAnnounced

    -- target = display name; whisperTo = full name (with realm when known)
    local function announce(target, whisperTo)
        if not db.announce or not IsInGroup() then
            return
        end
        local channel = db.channel ~= "auto" and db.channel or (IsInRaid() and "RAID" or "PARTY")
        local msg = db.message:gsub("%%t", target or "someone")
        pcall(SendChatMessage, msg, channel)
        if db.whisper and (whisperTo or target) then
            pcall(SendChatMessage, db.whisperText, "WHISPER", nil, whisperTo or target)
        end
    end

    -- Who a res is actually cast on. Ours: UNIT_SPELLCAST_SENT names the cast
    -- target (mouseover / @target macros included). Others: the game doesn't
    -- say, so their target if it's dead, else a dead group member with an
    -- incoming res that no bar shows yet.
    local sentTarget -- name from our last SENT res
    local function unitFor(name)
        for _, u in ipairs(FF.GroupUnits()) do
            if UnitName(u) == name then
                return u
            end
        end
    end
    local function guessTarget(unit)
        local t = unit .. "target"
        if UnitExists(t) and UnitIsDeadOrGhost(t) then
            local n = UnitName(t)
            if readable(n) then
                return n, select(2, UnitClass(t))
            end
        end
        local taken = {}
        for _, c in pairs(casts) do
            if c.target then
                taken[c.target] = true
            end
        end
        for _, u in ipairs(FF.GroupUnits()) do
            local n = UnitName(u)
            local has = UnitHasIncomingResurrection and UnitHasIncomingResurrection(u)
            if readable(n) and not taken[n] and UnitIsDeadOrGhost(u) and readable(has) and has then
                return n, select(2, UnitClass(u))
            end
        end
    end

    tracker:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
        if event == "UNIT_SPELLCAST_SENT" then
            local name = readable(a4) and spellName(a4)
            if name and RES[name] then
                sentTarget = readable(a2) and a2 ~= "" and a2 or nil
            end
            return
        end
        local spellID = a3
        if not isGroupUnit(unit) or not readable(spellID) then
            return
        end
        local name = spellName(spellID)
        if not name or not readable(name) or not RES[name] then
            return
        end
        local caster = UnitName(unit)
        if not caster or not readable(caster) then
            return
        end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            local startMS, endMS
            if event == "UNIT_SPELLCAST_START" then
                startMS, endMS = select(4, UnitCastingInfo(unit))
            else
                startMS, endMS = select(4, UnitChannelInfo(unit))
            end
            local target, targetClass
            if UnitIsUnit(unit, "player") and sentTarget then
                target = sentTarget:match("^[^%-]+")
                local tu = unitFor(target)
                targetClass = tu and select(2, UnitClass(tu))
            else
                target, targetClass = guessTarget(unit)
            end
            if not readable(targetClass) then
                targetClass = nil
            end
            local now = GetTime()
            local s = (readable(startMS) and startMS) and startMS / 1000 or now
            local e = (readable(endMS) and endMS) and endMS / 1000 or now + 10
            casts[caster] = { caster = caster, class = select(2, UnitClass(unit)), target = target, targetClass = targetClass, startT = s, endT = e }
            if UnitIsUnit(unit, "player") and myAnnounced ~= s then
                myAnnounced = s
                announce(target, sentTarget)
                sentTarget = nil
                if IsInGroup() and target then
                    FF.Send("Y", ("S%s:%d"):format(target, math.floor((e - s) * 1000)), "GROUP")
                end
            end
            if db.track and windowOpen() then
                wake()
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if casts[caster] then
                casts[caster].done = GetTime()
            end
        elseif UnitIsUnit(unit, "player") and casts[caster] and not casts[caster].done and IsInGroup() then
            casts[caster] = nil
            FF.Send("Y", "X", "GROUP")
        else -- stopped, interrupted or failed
            if casts[caster] and not casts[caster].done then
                casts[caster] = nil
            end
        end
    end)

    -- A caster told us who they're resurrecting: fix (or add) their bar
    FF.OnComm("Y", function(payload, channel, display, key)
        if key == FF.UnitKey("player") or channel == "GUILD" or channel == "WHISPER" or not db.track or not windowOpen() then
            return
        end
        local caster = display:match("^[^%-]+")
        if payload == "X" then
            if casts[caster] and not casts[caster].done then
                casts[caster] = nil
            end
            return
        end
        local target, ms = payload:match("^S([^:]+):(%d+)$")
        if not target then
            return
        end
        local tu = unitFor(target)
        local c = casts[caster]
        if c and not c.done then
            c.target, c.targetClass = target, tu and select(2, UnitClass(tu)) or c.targetClass
        else
            local u = FF.UnitByKey(key)
            local now = GetTime()
            casts[caster] = { caster = caster, class = u and select(2, UnitClass(u)), target = target,
                targetClass = tu and select(2, UnitClass(tu)), startT = now, endT = now + tonumber(ms) / 1000 }
        end
        wake()
    end)

    local function listen()
        tracker:UnregisterAllEvents()
        if (db.track or db.announce) and windowOpen() then
            -- STOP / CHANNEL_STOP also fire after an interrupt or failure
            for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
                "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
                tracker:RegisterEvent(ev)
            end
            tracker:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        end
    end

    FF.On("FF_READY", listen)
    FF.On("FF_ZONE", function()
        wipe(casts)
        listen()
    end)

    ---------------------------------------------------------------------------
    -- Settings
    ---------------------------------------------------------------------------
    local function toggleMove()
        if not display then
            build()
        end
        display.unlocked = not display.unlocked
        display:SetUnlocked(display.unlocked)
        if display.unlocked then
            display.title:SetText("Resurrections - drag me")
            display.bar:Show()
            display:SetSize(db.width, ROW)
            display:Show()
        else
            M.Refresh()
        end
    end

    FF.Settings("Resurrect", function(L)
        L:Header("Tracker")
        L:Toggle("Show who is resurrecting whom", db, "track", { onChange = listen })
        local on = function() return db.track end
        L:Toggle("Also work in the open world", db, "openWorld", { onChange = listen,
            tip = "Off: only inside dungeons and raids" })
        L:Slider("Most bars", db, "maxBars", 1, 20, 1, { dep = on })
        L:Slider("Width", db, "width", 100, 300, 10, { dep = on })
        L:Toggle("Show the title row", db, "showTitle", { dep = on, onChange = function()
            if display then
                M.Refresh()
            end
        end })
        L:Slider("Scale", db, "scale", 0.5, 2, 0.05, { dep = on })
        L:Buttons({ { "Unlock / lock window", toggleMove } }, { dep = on })

        L:Header("Announce my resurrections")
        L:Toggle("Announce when I start a res", db, "announce", { onChange = listen })
        local a = function() return db.announce end
        L:Select("Channel", db, "channel", {
            { "auto", "Raid or party" }, { "RAID", "Raid" }, { "PARTY", "Party" }, { "SAY", "Say" },
        }, { dep = a })
        L:Input("Message (%t = target)", db, "message", { dep = a, width = 300 })
        L:Toggle("Whisper the player", db, "whisper", { dep = a })
        L:Input("Whisper text", db, "whisperText", { dep = function() return db.announce and db.whisper end, width = 300, indent = 12 })
    end)
end)
