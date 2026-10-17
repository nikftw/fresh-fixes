local _, FF = ...
local M = FF.Module("Cooldowns")

-- Raid cooldown tracker. The combat log isn't available to addons on
-- Midnight-style clients, so each Fresh Fixes user reports their own
-- cooldowns. Comms tag "D":
--   U<spell>:<remaining>                used a cooldown
--   H<spell>:<rem>;<spell>:<rem>;...    cooldowns I have (answer to Q / on join)
--   Q                                   ask everyone for H
FF.Init("Cooldowns", function()
    local readable = FF.readable
    local db = FF.DB("cooldowns", {
        show = true, raidOnly = false, openWorld = false, onlyOnCooldown = false,
        width = 200, perColumn = 12, columns = 3, locked = true, showSpellName = false, showTitle = true,
        sortBy = "spellReady", readyFirst = false, reverse = false,
        clickCall = true, barFills = false, showLastOn = true, barRight = true, nicknames = true,
        reqHighlight = false, reqAlert = false, reqSound = "RAID_WARNING", reqDuration = 8,
    })
    db.off = db.off or {} -- [spell] = true: not shown
    db.extra = db.extra or {} -- [spell name] = cooldown seconds (user additions)

    -- Checked against Wowhead's Forever spell database (Oct 2026). Order = priority.
    -- No Bloodlust/Heroism on Forever. Soulstone's 30 min is the item's cooldown.
    -- { name, cooldown, spell ID (for the icon - any class, known or not) }
    local DEFAULTS = {
        { "Rebirth", 1800, 20484 }, { "Soulstone Resurrection", 1800, 20707 }, { "Reincarnation", 3600, 20608 },
        { "Divine Intervention", 3600, 19752 }, { "Innervate", 360, 29166 }, { "Mana Tide Totem", 300, 16190 },
        { "Tranquility", 300, 740 }, { "Power Infusion", 180, 10060 }, { "Lay on Hands", 1200, 633 },
        { "Blessing of Protection", 300, 1022 }, { "Contingency Plan", 300, 1277464 }, { "Divine Grace", 600, 1277370 },
        { "Fear Ward", 180, 6346 }, { "Shield Wall", 900, 871 }, { "Last Stand", 180, 12975 }, { "Retaliation", 900, 20230 },
        { "Recklessness", 1800, 1719 }, { "Challenging Shout", 600, 1161 }, { "Challenging Roar", 600, 5209 },
        { "Divine Shield", 300, 642 }, { "Ice Block", 300, 11958 }, { "Evocation", 480, 12051 },
    }
    db.extraIds = db.extraIds or {} -- [spell name] = spell ID for spells you added by ID

    local tracked, order, rank = {}, {}, {} -- [name] = cd, list, [name] = priority
    local function buildList()
        tracked, order, rank = {}, {}, {}
        for _, d in ipairs(DEFAULTS) do
            tracked[d[1]] = d[2]
            order[#order + 1] = d[1]
        end
        for name, cd in pairs(db.extra) do
            if cd and not tracked[name] then
                order[#order + 1] = name
            end
            tracked[name] = cd or nil
        end
        local kept = {}
        for _, name in ipairs(order) do
            if tracked[name] then
                kept[#kept + 1] = name
            end
        end
        order = kept
        for i, name in ipairs(order) do
            rank[name] = i
        end
    end
    buildList()

    local members = {} -- [key] = { name, class, spells = {[spell] = readyAt} }

    local spellName = C_Spell.GetSpellName

    local function known(name)
        return C_Spell.GetSpellInfo(name) ~= nil
    end

    local function remaining(name)
        local start, duration = FF.SpellCooldown(name)
        return start and duration > 1.5 and math.max(0, start + duration - GetTime()) or 0
    end

    local function record(key, display, spells, lastOn)
        local m = members[key] or { spells = {} }
        m.key = key
        m.lastOn = m.lastOn or {}
        members[key] = m
        m.name = display:match("^[^%-]+")
        local u = FF.UnitByKey(key)
        if u then
            local _, class = UnitClass(u)
            m.class = class
        end
        for spell, rem in pairs(spells) do
            if tracked[spell] then
                m.spells[spell] = GetTime() + rem
                if rem > 0 and lastOn and lastOn[spell] then
                    m.lastOn[spell] = lastOn[spell]
                elseif rem <= 0 then
                    m.lastOn[spell] = nil
                end
            end
        end
    end

    local function haveList()
        local parts = {}
        for _, name in ipairs(order) do
            if known(name) then
                parts[#parts + 1] = ("%s:%d"):format(name, remaining(name))
            end
        end
        return table.concat(parts, ";")
    end

    local myKey
    -- our own known spells go straight into the window
    local function recordSelf()
        myKey = myKey or FF.UnitKey("player")
        local spells = {}
        for _, name in ipairs(order) do
            if known(name) then
                spells[name] = remaining(name)
            end
        end
        if myKey and next(spells) then
            record(myKey, FF.UnitIdentity("player"), spells)
        end
    end

    local function announceHave()
        if IsInGroup() then
            recordSelf()
            local list = haveList()
            if list ~= "" then
                FF.Send("D", "H" .. list, "GROUP")
            end
        end
    end

    FF.OnComm("D", function(payload, channel, display, key)
        if channel == "WHISPER" or channel == "GUILD" or not (db.show and (db.openWorld or FF.InGroupContent())) then
            return
        end
        local op, data = payload:sub(1, 1), payload:sub(2)
        if op == "Q" then
            C_Timer.After(math.random() * 3, announceHave)
            return
        end
        local spells, lastOn = {}, {}
        if op == "U" then
            local name, rem, target = data:match("^([^:;]+):(%d+):?([^:;]*)$")
            if name then
                spells[name] = tonumber(rem)
                lastOn[name] = target ~= "" and target or nil
            end
        else
            for name, rem in data:gmatch("([^:;]+):(%d+)") do
                spells[name] = tonumber(rem)
            end
        end
        record(key, display, spells, lastOn)
        M.Refresh()
    end)

    local casts = CreateFrame("Frame")
    local sentTo = {} -- [spell name] = target name from UNIT_SPELLCAST_SENT
    -- Dungeons and raids only, unless open world is on
    local function active()
        return db.show and (db.openWorld or FF.InGroupContent())
    end

    local function listenCasts()
        casts:UnregisterAllEvents()
        if active() and IsInGroup() then
            casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            casts:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        end
    end
    M.ListenCasts = listenCasts

    -- Became active (setting changed): fill the window right away
    function M.Wake()
        listenCasts()
        if active() and IsInGroup() then
            FF.Send("D", "Q", "GROUP")
            announceHave()
        elseif not active() then
            wipe(members)
        end
        M.Refresh()
    end
    FF.On("FF_READY", listenCasts)
    FF.On("FF_ZONE", function()
        listenCasts()
        if not active() then
            wipe(members)
        elseif IsInGroup() then
            FF.Send("D", "Q", "GROUP")
        end
        M.Refresh()
    end)
    casts:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
        if event == "UNIT_SPELLCAST_SENT" then
            local target, spell = a2, a4
            local n = readable(spell) and spellName(spell)
            if n and readable(n) and tracked[n] then
                sentTo[n] = readable(target) and target ~= "" and target or nil
            end
            return
        end
        local spellID = a3
        if not readable(spellID) then
            return
        end
        local name = spellName(spellID)
        if not name or not readable(name) or not tracked[name] then
            return
        end
        C_Timer.After(0.2, function()
            local rem = remaining(name)
            if rem <= 0 then
                rem = tracked[name]
            end
            myKey = myKey or FF.UnitKey("player")
            local target = sentTo[name]
            sentTo[name] = nil
            target = target and target:match("^[^%-]+") -- drop the realm
            record(myKey, FF.UnitIdentity("player"), { [name] = rem }, { [name] = target })
            if IsInGroup() then
                FF.Send("D", ("U%s:%d:%s"):format(name, rem, target or ""), "GROUP")
            end
            M.Refresh()
        end)
    end)

    local wasInGroup = false
    local rosterTimer
    FF.On("GROUP_ROSTER_UPDATE", function()
        listenCasts()
        if rosterTimer then
            rosterTimer:Cancel()
        end
        rosterTimer = C_Timer.NewTimer(2, function()
            rosterTimer = nil
            local inGroup = IsInGroup()
            -- prune people who left
            local present = {}
            for _, u in ipairs(FF.GroupUnits()) do
                local k = FF.UnitKey(u)
                if k then
                    present[k] = true
                end
            end
            for k in pairs(members) do
                if not present[k] then
                    members[k] = nil
                end
            end
            local on = db.show and (db.openWorld or FF.InGroupContent())
            if on and inGroup and not wasInGroup then
                FF.Send("D", "Q", "GROUP")
            end
            if on and inGroup then
                announceHave()
            end
            wasInGroup = inGroup
            M.Refresh()
        end)
    end)

    ---------------------------------------------------------------------------
    -- Window
    ---------------------------------------------------------------------------
    local win

    -- Sorting (MRT-style rules). Keys compared in order; ties fall through.
    local SORTS = {
        { "spellReady", "Spell > time left > player", { "spell", "left", "name" } },
        { "spell", "Spell > player", { "spell", "name" } },
        { "player", "Player > spell", { "name", "spell" } },
        { "classSpell", "Class > spell > player", { "class", "spell", "name" } },
        { "classPlayer", "Class > player > spell", { "class", "name", "spell" } },
        { "ready", "Time left > spell > player", { "left", "spell", "name" } },
    }
    local KEYS = {
        spell = function(e) return rank[e.spell] or 999 end,
        name = function(e) return e.m.name or "" end,
        class = function(e) return e.m.class or "" end,
        left = function(e) return e.left end,
    }
    local function sortEntries(list)
        local keys = SORTS[1][3]
        for _, s in ipairs(SORTS) do
            if s[1] == db.sortBy then
                keys = s[3]
            end
        end
        table.sort(list, function(a, b)
            if db.readyFirst and (a.left > 0) ~= (b.left > 0) then
                return a.left == 0 -- usable cooldowns first, kept above any reverse
            end
            for _, k in ipairs(keys) do
                local x, y = KEYS[k](a), KEYS[k](b)
                if x ~= y then
                    if db.reverse then
                        return x > y
                    end
                    return x < y
                end
            end
            return false
        end)
    end

    -- Row clicks: whisper the player to use it, or (shift) call it in group chat
    local function callCooldown(d, button)
        if button ~= "LeftButton" or not d.spell then
            return
        end
        local status = d.left > 0 and (" (ready in " .. FF.Clock(d.left) .. ")") or ""
        if IsShiftKeyDown() then
            if IsInGroup() then
                local channel = IsInRaid() and "RAID" or "PARTY"
                pcall(SendChatMessage, ("%s: %s please%s"):format(d.who, d.spell, status), channel)
            end
        else
            pcall(SendChatMessage, ("%s please%s"):format(d.spell, status), "WHISPER", nil, d.who)
        end
    end

    -- Icons come from spell IDs (works for every class's spells); a name
    -- lookup only finds spells you know, so it's the last resort.
    local IDS = {}
    for _, d in ipairs(DEFAULTS) do
        IDS[d[1]] = d[3]
    end
    local icons = {}
    local function spellIcon(spell)
        if icons[spell] == nil then
            local id = IDS[spell] or db.extraIds[spell]
            local tex = C_Spell.GetSpellTexture(id or spell)
            icons[spell] = tex or false
        end
        return icons[spell] or 134400
    end

    local function visible()
        if not db.locked then
            return true -- unlocked to be moved
        end
        return active() and (IsInRaid() or (IsInGroup() and not db.raidOnly)) and next(members) ~= nil
    end

    local ticking -- something is on cooldown: redraw on the timer
    function M.Refresh()
        if not visible() then
            if win then
                win:Hide()
            end
            return
        end
        if not win then
            win = FF.ListWindow("Cooldowns", "Raid Cooldowns", db.width, db.perColumn * db.columns)
            win.iconFull = true -- spell icon fills the row
            win.dragRows = true -- when unlocked, drag by any row
            win:SetTitleShown(db.showTitle)
            local acc = 0
            win:SetScript("OnUpdate", function(_, dt)
                acc = acc + dt
                if acc > 0.5 then
                    acc = 0
                    if ticking then
                        M.Refresh()
                    end
                end
            end)
        end
        local rows, now = {}, GetTime()
        win.barRight = db.barRight
        win.locked = db.locked
        local wantTitle = db.showTitle or not db.locked
        if win.titleBar:IsShown() ~= wantTitle then
            win:SetTitleShown(wantTitle)
        end
        win.title:SetText(db.locked and "Raid Cooldowns" or "Raid Cooldowns - drag me")
        win:SetGrid(db.perColumn, db.columns, db.width)
        local list = {}
        for _, m in pairs(members) do
            for spell, ready in pairs(m.spells) do
                if tracked[spell] and not db.off[spell] and (not db.onlyOnCooldown or ready > now) then
                    list[#list + 1] = { m = m, spell = spell, left = math.max(0, ready - now) }
                end
            end
        end
        sortEntries(list)
        ticking = false
        for _, e in ipairs(list) do
            ticking = ticking or e.left > 0
            local frac = e.left / tracked[e.spell]
            if e.left <= 0 and e.m.lastOn then
                e.m.lastOn[e.spell] = nil
            end
            local on = db.showLastOn and e.left > 0 and e.m.lastOn and e.m.lastOn[e.spell]
            local nicks = FF.modules.Nicknames
            if on and db.nicknames and nicks and nicks.loaded and nicks.Get then
                on = nicks.Get(on) or on
            end
            rows[#rows + 1] = {
                icon = spellIcon(e.spell),
                text = (db.showSpellName and (e.spell .. "  ") or "") .. FF.ClassColor(e.m.class, db.nicknames and FF.NickOr(e.m.key, e.m.name) or e.m.name)
                    .. (on and (FF.Hex(FF.C.muted) .. " > " .. on .. "|r") or ""),
                right = e.left > 0 and FF.Clock(e.left) or (FF.Hex(FF.C.good) .. "Ready|r"),
                -- default: the red drains away as the cooldown comes back
                bar = e.left > 0 and (db.barFills and (1 - frac) or frac) or nil,
                barColor = { 0.8, 0.3, 0.2 },
                spell = e.spell, who = e.m.name, left = e.left,
                onClick = db.clickCall and callCooldown or nil,
            }
        end
        win:SetRows(rows)
        win:Show()
    end

    ---------------------------------------------------------------------------
    -- Highlight on request: when someone in the group clicks one of YOUR
    -- cooldown rows, their whisper ("<Spell> please" / "<Spell> please (ready
    -- in m:ss)", see callCooldown) puts a flat accent border over their raid
    -- frame and plays a sound. Overlays are our own plain frames (never
    -- secure), parented to UIParent and anchored over the unit frame, made
    -- out of combat. Idle = no OnUpdate and no events beyond the whisper.
    ---------------------------------------------------------------------------
    local C = FF.C
    local pool, lit = {}, {} -- lit[senderKey] = { frames = {}, spell, timer }
    local POOL = 8

    local function makeOverlay()
        local o = CreateFrame("Frame", nil, UIParent)
        o:Hide()
        local e = {}
        for i = 1, 4 do
            e[i] = o:CreateTexture(nil, "OVERLAY", nil, 7)
            e[i]:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        end
        local t = 2 -- 2px reads as a border on raid frames; still flat
        e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
        e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
        e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)
        local glow = o:CreateTexture(nil, "OVERLAY", nil, 6)
        glow:SetAllPoints()
        glow:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
        local ag = o:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.5)
        o.pulse = ag
        return o
    end
    local function fillPool()
        if InCombatLockdown() then return end
        while #pool < POOL do pool[#pool + 1] = makeOverlay() end
    end

    local function release(key)
        local a = lit[key]
        if not a then return end
        if a.timer then a.timer:Cancel() end
        for _, o in ipairs(a.frames) do
            o.pulse:Stop()
            o:Hide()
            o:ClearAllPoints()
            pool[#pool + 1] = o
        end
        lit[key] = nil
    end

    -- Unit frames showing `unit`, from every frame system we know
    local function frameUnit(f)
        local u = f and (f.displayedUnit or f.unit)
        if type(u) == "string" and readable(u) then return u end
    end
    local function framesFor(unit)
        local found, seen = {}, {}
        local function try(f)
            if f and not seen[f] and f.IsVisible and f:IsVisible() then
                local u = frameUnit(f)
                if u and UnitExists(u) and UnitIsUnit(u, unit) then
                    seen[f] = true
                    found[#found + 1] = f
                end
            end
        end
        -- Blizzard compact raid / party frames
        for i = 1, 40 do try(_G["CompactRaidFrame" .. i]) end
        for g = 1, 8 do
            for i = 1, 5 do try(_G["CompactRaidGroup" .. g .. "Member" .. i]) end
        end
        for i = 1, 5 do try(_G["CompactPartyFrameMember" .. i]) end
        -- ElvUI (oUF): every spawned unit frame is in ElvUF.objects
        local ouf = _G.ElvUF
        if type(ouf) == "table" and type(ouf.objects) == "table" then
            for _, f in ipairs(ouf.objects) do
                local n = f.GetName and f:GetName()
                if n and (n:find("^ElvUF_Raid") or n:find("^ElvUF_Party")) then try(f) end
            end
        end
        -- EllesmereUI and anything else: generic scan of visible frames with a
        -- .unit field (only runs on a request, never while idle)
        if #found == 0 then
            local f = EnumerateFrames()
            local n = 0
            while f and n < 20000 do
                n = n + 1
                if not f:IsForbidden() and rawget(f, "unit") ~= nil then
                    local name = f:GetName()
                    -- raid / party style frames only (skip target, focus, nameplates)
                    local u = frameUnit(f)
                    if u and (u:find("^raid%d") or u:find("^party%d") or u == "player") and not (name and name:find("NamePlate")) then
                        try(f)
                    end
                end
                f = EnumerateFrames(f)
            end
        end
        return found
    end

    local castWatch = CreateFrame("Frame")
    local function watchCasts()
        if next(lit) then
            castWatch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            castWatch:UnregisterAllEvents()
        end
    end
    castWatch:SetScript("OnEvent", function(_, _, _, _, spellID)
        if not readable(spellID) then return end
        local n = spellName(spellID)
        if not n or not readable(n) then return end
        for key, a in pairs(lit) do
            if a.spell == n then release(key) end
        end
        watchCasts()
    end)

    function M.Highlight(unit, key, spell)
        release(key) -- a new request replaces this sender's old one
        local frames = framesFor(unit)
        local a = { frames = {}, spell = spell }
        for _, f in ipairs(frames) do
            local o = table.remove(pool)
            if not o then break end -- pool is made out of combat only
            o:SetFrameStrata(f:GetFrameStrata())
            o:SetFrameLevel(math.min(10000, f:GetFrameLevel() + 20))
            o:ClearAllPoints()
            o:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            o:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            o:Show()
            o.pulse:Play()
            a.frames[#a.frames + 1] = o
        end
        lit[key] = a
        a.timer = C_Timer.NewTimer(db.reqDuration or 8, function()
            release(key)
            watchCasts()
        end)
        watchCasts()
        return #a.frames
    end

    -- "<Spell> please" or "<Spell> please (ready in 1:23)" / "(ready in 1h02m)"
    local function parseRequest(text)
        local spell = text:match("^(.-) please$") or text:match("^(.-) please %(ready in [%dhm:]+%)$")
        return spell
    end

    local function wantRequests()
        return db.reqHighlight or db.reqAlert
    end

    -- Centre-screen raid warning with spell icon: "Name requested Spell"
    local function requestAlert(requester, spell)
        if not db.reqAlert or not spell then return end
        local icon = spellIcon(spell)
        local tex = (type(icon) == "number" or type(icon) == "string") and icon or 134400
        local who = requester or "?"
        -- |T…|t with 10% crop each edge ≈ 20% zoom (same idea as SetTexCoord 0.1–0.9).
        FF.Alert(("|T%s:0:0:0:0:64:64:6:58:6:58|t %s requested %s"):format(tex, who, spell))
    end

    local function onRequest(text, sender)
        if not wantRequests() or not (readable(text) and readable(sender)) or type(text) ~= "string" then return end
        local spell = parseRequest(text)
        if not spell or not tracked[spell] or not known(spell) then return end -- only requests for my tracked spells
        local key = FF.Key(sender)
        key = key and FF.CanonicalKey(key)
        local unit = key and FF.UnitByKey(key)
        if not unit or UnitIsUnit(unit, "player") then return end -- must be in my group
        local who = Ambiguate and Ambiguate(sender, "short") or sender:match("^([^-]+)") or sender
        if db.nicknames then
            who = FF.NickOr(key, who) or who
        end
        FF.PlaySound(db.reqSound)
        if db.reqHighlight then
            M.Highlight(unit, key, spell)
        end
        requestAlert(who, spell)
    end

    local function onWhisper(_, text, sender)
        onRequest(text, sender)
    end

    local function applyRequest()
        local on = wantRequests()
        FF.Listen("CHAT_MSG_WHISPER", onWhisper, on and true or false)
        FF.Listen("PLAYER_REGEN_ENABLED", fillPool, db.reqHighlight and true or false)
        if db.reqHighlight then
            fillPool()
        else
            for key in pairs(lit) do release(key) end
            watchCasts()
        end
    end
    M.ApplyRequest = applyRequest
    FF.On("FF_READY", applyRequest)

    FF.Settings("Cooldowns", function(L)
        L:Header("Window")
        L:Toggle("Show the raid cooldown window", db, "show", { onChange = M.Wake })
        L:Buttons({ { "Unlock / lock window", function()
            db.locked = not db.locked
            M.Refresh()
        end } }, { dep = function() return db.show end })
        local on = function() return db.show end
        L:Toggle("Only in raids (not parties)", db, "raidOnly", { dep = on, onChange = M.Refresh })
        L:Toggle("Also work in the open world", db, "openWorld", { dep = on, tip = "Off: only inside dungeons and raids",
            onChange = M.Wake })
        L:Toggle("Only list spells that are on cooldown", db, "onlyOnCooldown", { dep = on, onChange = M.Refresh })
        L:Toggle("Show spell names", db, "showSpellName", { dep = on, onChange = M.Refresh, tip = "The spell icon is always shown" })
        L:Slider("Column width", db, "width", 100, 300, 10, { dep = on, onChange = M.Refresh })
        L:Slider("Spells per column", db, "perColumn", 1, 40, 1, { dep = on, onChange = M.Refresh })
        L:Slider("Columns", db, "columns", 1, 6, 1, { dep = on, onChange = M.Refresh, tip = "Anything past the last column isn't shown" })

        L:Header("Sorting")
        L:Select("Sort by", db, "sortBy", (function()
            local list = {}
            for _, s in ipairs(SORTS) do
                list[#list + 1] = { s[1], s[2] }
            end
            return list
        end)(), { dep = on, onChange = M.Refresh, width = 220 })
        L:Toggle("Ready cooldowns first", db, "readyFirst", { dep = on, onChange = M.Refresh })
        L:Toggle("Reverse order", db, "reverse", { dep = on, onChange = M.Refresh })

        L:Header("Rows")
        L:Toggle("Bar fills up instead of draining", db, "barFills", { dep = on, onChange = M.Refresh,
            tip = "Off: the red shrinks away as the cooldown comes back" })
        L:Select("Bar starts from", db, "barRight", { { true, "Right side" }, { false, "Left side" } }, { dep = on, onChange = M.Refresh })
        L:Toggle("Show nicknames", db, "nicknames", { dep = on, onChange = M.Refresh, tip = "From the Nicknames module" })
        L:Toggle("Show who it was last used on", db, "showLastOn", { dep = on, onChange = M.Refresh,
            tip = "Adds the target of the last cast (from players running Fresh Fixes)" })
        L:Toggle("Click to call cooldowns", db, "clickCall", { dep = on, onChange = M.Refresh,
            tip = "Click a row: whisper that player to use it. Shift-click: ask for it in raid/party chat." })
        L:TitleToggle(db, function() return win end)

        L:Header("Requests")
        L:Toggle("Highlight on raid cooldown request", db, "reqHighlight", { onChange = M.ApplyRequest,
            tip = "When someone clicks your cooldown in their window, their whisper puts a border on their raid frame and plays a sound" })
        L:Toggle("Raid warning on request", db, "reqAlert", { onChange = M.ApplyRequest,
            tip = "Centre-screen notice with the spell icon: who requested which cooldown" })
        local req = function() return wantRequests() end
        local hl = function() return db.reqHighlight end
        L:Select("Request sound", db, "reqSound", FF.SoundChoices, { dep = req, width = 180 })
        L:Buttons({ { "Test sound", function() FF.PlaySound(db.reqSound) end },
            { "Test highlight", function()
                local n = M.Highlight("player", "_test", "")
                if n == 0 then FF.print("No raid/party frame found for you (frames must be visible)") end
            end, "Highlights your own raid frame" },
            { "Test warning", function()
                requestAlert(UnitName("player") or "You", order[1] or "Innervate")
            end, "Shows a sample centre-screen request warning" } }, { dep = req })
        L:Slider("Highlight duration (seconds)", db, "reqDuration", 3, 30, 1, { dep = hl })

        L:Header("Tracked spells")
        L:Desc("Everyone running Fresh Fixes reports their own cooldowns. Turn off spells you don't care about.")
        for _, spell in ipairs(order) do
            L:Toggle(("%s  (%s)"):format(spell, FF.Clock(tracked[spell])), db.off, spell, { invert = true, onChange = M.Refresh, indent = 12 })
        end

        -- spells you added: one row each with an x to remove it
        local custom = {}
        for name, cd in pairs(db.extra) do
            if cd then
                custom[#custom + 1] = name
            end
        end
        table.sort(custom)
        L:Header("Added spells")
        if #custom == 0 then
            L:Desc("None yet - add one below.")
        end
        for _, name in ipairs(custom) do
            L:Custom(24, function(f, width)
                local t = FF.Text(f)
                t:SetPoint("LEFT", 24, 0)
                t:SetText(("%s  %s(%s)|r"):format(name, FF.Hex(FF.C.muted), FF.Clock(db.extra[name])))
                local x = FF.UI.CloseButton(f, function()
                    FF.Run("cd remove " .. name)
                    FF.RebuildSettings("Cooldowns")
                end)
                x:SetPoint("RIGHT", f, "LEFT", width - 12, 0)
            end)
        end
        db._newSpell = db._newSpell or ""
        db._newCd = db._newCd or ""
        L:Input("Spell name or ID", db, "_newSpell", { width = 200 })
        L:Input("Cooldown (seconds)", db, "_newCd", { width = 80 })
        L:Buttons({ { "Add spell", function()
            local secs = tonumber(db._newCd)
            if db._newSpell == "" or not secs or secs <= 0 then
                FF.print("Type a spell name or ID and its cooldown in seconds.")
                return
            end
            FF.Run(("cd add %s %d"):format(db._newSpell, secs))
            db._newSpell, db._newCd = "", ""
            FF.RebuildSettings("Cooldowns")
        end } })
    end)

    FF.Command("cd", function(rest)
        local cmd, arg = rest:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        if cmd == "add" then
            local spell, secs = arg:match("^(.-)%s+(%d+)$")
            if not spell then
                FF.print("Usage: /ff cd add <spell name or ID> <cooldown seconds>")
                return
            end
            -- an ID becomes its name (cooldowns are shared by name); names get the game's spelling
            local name = spell
            if tonumber(spell) then
                name = spellName(tonumber(spell))
                if name and readable(name) then
                    db.extraIds[name] = tonumber(spell) -- icon for everyone, known or not
                end
            else
                local info = C_Spell.GetSpellInfo(spell)
                name = info and info.name or spell
            end
            if not name or not readable(name) then
                FF.print("No spell with ID " .. spell)
                return
            end
            db.extra[name] = tonumber(secs)
            buildList()
            M.Refresh()
            FF.print("Tracking", name, "(" .. FF.Clock(tonumber(secs)) .. ")")
        elseif cmd == "remove" and arg ~= "" then
            db.extra[arg] = nil
            buildList()
            M.Refresh()
            FF.print("Stopped tracking", arg)
        else
            FF.ShowOptions("Cooldowns")
        end
    end, "raid cooldowns: add <spell or ID> <seconds> / remove <spell>")
end)
