local _, FF = ...
local M = FF.Module("Groups")

-- Group setup:
--   * Layouts: import (website GROUP string or text) and apply it (move
--     everyone in the raid into their group). Imports are kept in memory only,
--     until the next import or reload. Export gives the raid's current groups.
--   * Assistants: everyone, a list of players, and/or anyone at a guild rank.
--   * Always-mark (MRT style): give players a raid marker and put it back
--     whenever it's removed. Each marker can list several names in priority
--     order - the first one in the group gets it.
--   * Whisper-keyword invites.
-- Names may be "First", "First Surname", "First Surname-Realm" or a nickname.
FF.Init("Groups", function()
    local readable = FF.readable
    local db = FF.DB("groups", {
        inviteWord = false, inviteGuildOnly = true, keyword = "inv",
        everyoneAssist = false, autoPromote = false, promoteByRank = false, promoteRank = 1,
        autoMark = false,
    })
    db.promote = db.promote or {} -- [name] = true
    local current -- last imported layout: { name, groups = { {names...} x8 } }
    db.marks = db.marks or {}     -- [1..8] = "Name, Name"

    local STEP_DELAY = 0.3

    local function trim(s)
        return s:match("^%s*(.-)%s*$")
    end

    ---------------------------------------------------------------------------
    -- Name -> unit in my group (surname and nickname safe)
    ---------------------------------------------------------------------------
    local function squash(s)
        return (s:gsub("%s", ""):lower())
    end

    function M.FindUnit(name)
        name = trim(name)
        if name == "" then
            return
        end
        local wantKey = name:find("-", 1, true) and FF.Key(name)
        local full = squash(name:match("^[^%-]+"))
        local firstHit, firstCount = nil, 0
        for _, u in ipairs(FF.GroupUnits()) do
            local display, key = FF.UnitIdentity(u)
            if key then
                if wantKey then
                    if FF.SameChar(key, wantKey) then
                        return u
                    end
                else
                    local base = key:match("^[^%-]+")
                    if base == full then
                        return u -- "First Surname" (or single-word name) matches exactly
                    end
                    local nick = FF.NickOr(key)
                    if nick and squash(nick) == full then
                        return u
                    end
                    local first = display and display:match("^(%S+)")
                    if first and first:lower() == full then
                        firstHit, firstCount = u, firstCount + 1
                    end
                end
            end
        end
        if firstCount == 1 then
            return firstHit -- just "First", and only one player has that first name
        end
    end

    ---------------------------------------------------------------------------
    -- Layouts
    ---------------------------------------------------------------------------
    -- Text form:   name: Mythic Vexie
    --              1: Fojji Ashmane, Shane, Tankyboy-Forever
    local function parseText(text)
        local name, groups, any = nil, {}, false
        for line in (text .. "\n"):gmatch("(.-)\r?\n") do
            line = trim(line)
            local k, v = line:match("^(%w+):%s*(.*)$")
            if k and k:lower() == "name" then
                name = v
            elseif k and tonumber(k) and tonumber(k) >= 1 and tonumber(k) <= 8 then
                local g = {}
                for n in v:gmatch("[^,]+") do
                    n = trim(n)
                    if n ~= "" and #g < 5 then
                        g[#g + 1] = n:sub(1, 64)
                    end
                end
                groups[tonumber(k)] = g
                any = true
            end
        end
        for i = 1, 8 do
            groups[i] = groups[i] or {}
        end
        if not any then
            return
        end
        return name or "Imported", { groups = groups }
    end

    local function fromData(d)
        if type(d) ~= "table" or type(d.groups) ~= "table" then
            return
        end
        local groups = {}
        for i = 1, 8 do
            groups[i] = {}
            for _, n in ipairs(type(d.groups[i]) == "table" and d.groups[i] or {}) do
                if type(n) == "string" and n ~= "" and #groups[i] < 5 then
                    table.insert(groups[i], n:sub(1, 64))
                end
            end
        end
        return type(d.name) == "string" and d.name:sub(1, 48) or "Imported", { groups = groups }
    end

    function M.Import(text)
        local compact = text:gsub("%s", "")
        local name, p
        local chunk = compact:match("!FF:%u+:%d+![%w%+/=]+")
        if chunk then
            name, p = fromData((FF.Decode(chunk, "GROUP")))
        else
            name, p = parseText(text)
        end
        if not name then
            return false
        end
        p.name = name
        current = p
        local n = 0
        for i = 1, 8 do
            n = n + #p.groups[i]
        end
        FF.print(("Loaded layout %s (%d players) - press Apply"):format(name, n))
        return true
    end

    function M.Current()
        return current
    end

    -- The raid's groups right now, as a GROUP string (e.g. for the website)
    function M.Export()
        if not IsInRaid() then
            FF.print("Not in a raid")
            return
        end
        local groups = {}
        for i = 1, 8 do
            groups[i] = {}
        end
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            local display = FF.UnitIdentity("raid" .. i)
            if display and subgroup then
                table.insert(groups[subgroup], display)
            end
        end
        FF.ShowText("Current raid groups", FF.Encode("GROUP", 1, { name = "Current raid", groups = groups }))
    end

    ---------------------------------------------------------------------------
    -- Apply: move everyone into their group, one move at a time
    ---------------------------------------------------------------------------
    local active, timer

    local function raidMembers()
        local list = {}
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            local key = FF.UnitKey("raid" .. i)
            if key then
                list[#list + 1] = { index = i, key = key, group = subgroup }
            end
        end
        return list
    end

    local step
    local function schedule(delay)
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(delay, step)
    end

    step = function()
        timer = nil
        if not active then
            return
        end
        if GetTime() > active.untilTime or active.steps > 120 then
            FF.print("Group sorting stopped")
            active = nil
            return
        end
        if InCombatLockdown() then
            schedule(2)
            return
        end
        if not IsInRaid() or not FF.IsGroupLead() then
            FF.print("You need to be in a raid with lead or assist to arrange groups")
            active = nil
            return
        end
        local fighting = {}
        for i = 1, GetNumGroupMembers() do
            if UnitAffectingCombat("raid" .. i) then
                fighting[#fighting + 1] = UnitName("raid" .. i) or "?"
            end
        end
        if #fighting > 0 then
            FF.print("Group sorting stopped - in combat: " .. table.concat(fighting, ", "))
            active = nil
            return
        end
        local members, counts = raidMembers(), {}
        for i = 1, 8 do
            counts[i] = 0
        end
        for _, m in ipairs(members) do
            counts[m.group] = counts[m.group] + 1
        end
        for _, m in ipairs(members) do
            local want = active.target[m.key]
            if want and want ~= m.group then
                active.steps = active.steps + 1
                if counts[want] < 5 then
                    SetRaidSubgroup(m.index, want)
                    schedule(STEP_DELAY)
                    return
                end
                for _, o in ipairs(members) do
                    if o.group == want and active.target[o.key] ~= want then
                        SwapRaidSubgroup(m.index, o.index)
                        schedule(STEP_DELAY)
                        return
                    end
                end
            end
        end
        FF.print("Groups arranged")
        active = nil
    end

    local lastApply = 0
    function M.Apply()
        local p = current
        if not p then
            FF.print("Import a layout first")
            return
        end
        local name = p.name
        if InCombatLockdown() then
            FF.print("Can't arrange groups in combat")
            return
        end
        if GetTime() - lastApply < 5 then
            FF.print("Please wait a few seconds between group sorts")
            return
        end
        lastApply = GetTime()
        local target, missing = {}, {}
        for g = 1, 8 do
            for _, n in ipairs(p.groups[g]) do
                local u = M.FindUnit(n)
                local key = u and FF.UnitKey(u)
                if key then
                    target[key] = g
                else
                    missing[#missing + 1] = n
                end
            end
        end
        if #missing > 0 then
            FF.print("Not in the raid:", table.concat(missing, ", "))
        end
        active = { target = target, steps = 0, untilTime = GetTime() + 60 }
        FF.print("Arranging groups for " .. name .. "...")
        schedule(0.2)
    end

    FF.On("GROUP_ROSTER_UPDATE", function()
        if active and not timer then
            schedule(STEP_DELAY)
        end
    end)

    ---------------------------------------------------------------------------
    -- Assistants
    ---------------------------------------------------------------------------
    local promoteTimer
    local function promotePass()
        promoteTimer = nil
        if not IsInRaid() or not UnitIsGroupLeader("player") or InCombatLockdown() then
            return
        end
        if db.everyoneAssist and SetEveryoneIsAssistant then
            SetEveryoneIsAssistant(true)
            return
        end
        local wanted = {}
        if db.autoPromote then
            for name in pairs(db.promote) do
                local u = M.FindUnit(name)
                if u then
                    wanted[u] = true
                end
            end
        end
        local roster = db.promoteByRank and FF.GuildRoster()
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            local key = FF.UnitKey(u)
            local r = roster and key and roster[key]
            if r and r.rankIndex and r.rankIndex <= db.promoteRank then
                wanted[u] = true
            end
        end
        for u in pairs(wanted) do
            if UnitExists(u) and not UnitIsGroupAssistant(u) and not UnitIsGroupLeader(u) then
                PromoteToAssistant(u)
            end
        end
    end

    local function queuePromote()
        if (db.autoPromote or db.everyoneAssist or db.promoteByRank) and not promoteTimer then
            promoteTimer = C_Timer.NewTimer(1, promotePass)
        end
    end
    FF.On("GROUP_ROSTER_UPDATE", queuePromote)

    ---------------------------------------------------------------------------
    -- Always-mark (MRT Marks)
    ---------------------------------------------------------------------------
    local MARKS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

    local function canMark()
        if not IsInGroup() then
            return false
        end
        return not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    local function markPass()
        if not db.autoMark or not canMark() then
            return
        end
        local used = {}
        for i = 1, 8 do
            local list = db.marks[i]
            if list and list ~= "" then
                for name in list:gmatch("[^,]+") do
                    local u = M.FindUnit(name)
                    if u and not used[u] then
                        used[u] = true
                        local current = GetRaidTargetIndex(u)
                        if readable(current) and current ~= i then
                            SetRaidTarget(u, i)
                        end
                        break
                    end
                end
            end
        end
    end

    local markTicker
    local function markChanged()
        C_Timer.After(0.2, markPass)
    end
    local function updateMarking()
        local want = db.autoMark and IsInGroup()
        FF.Listen("RAID_TARGET_UPDATE", markChanged, want)
        if want and not markTicker then
            markTicker = C_Timer.NewTicker(2, markPass)
        elseif not want and markTicker then
            markTicker:Cancel()
            markTicker = nil
        end
        if want then
            markPass()
        end
    end
    FF.On("GROUP_ROSTER_UPDATE", updateMarking)
    FF.On("FF_READY", updateMarking)

    ---------------------------------------------------------------------------
    -- Whisper-keyword invites
    ---------------------------------------------------------------------------
    local function canInvite()
        return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    local function onWhisper(_, msg, author)
        if not db.inviteWord or not (readable(msg) and readable(author)) then
            return
        end
        if msg:lower():match("^%s*(.-)%s*$") ~= db.keyword:lower() or not canInvite() then
            return
        end
        local key = FF.Key(author)
        if db.inviteGuildOnly and not (key and FF.GuildRoster()[key]) then
            return
        end
        if IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 and UnitIsGroupLeader("player") then
            C_PartyInfo.ConvertToRaid()
        end
        C_PartyInfo.InviteUnit(author)
    end
    local function listenWhispers()
        FF.Listen("CHAT_MSG_WHISPER", onWhisper, db.inviteWord)
    end
    FF.On("FF_READY", listenWhispers)

    ---------------------------------------------------------------------------
    -- Settings
    ---------------------------------------------------------------------------
    local function importWindow()
        FF.ShowText("Import group layouts", "", function(text)
            if not M.Import(text) then
                return "No layout found - paste a Fresh Fixes GROUP string or 'name: ...' / '1: Name, Name' lines"
            end
            FF.RebuildSettings("Groups")
        end)
    end

    FF.Settings("Groups", function(L)
        L:Header("Layouts")
        L:Desc("Import a layout from the website (or as text: 'name: Mythic', then '1: First Surname, Name, ...'), then Apply to move everyone in the raid into their group. Export gives the raid's current groups.")
        L:Buttons({
            { "Import", importWindow },
            { "Apply", function() M.Apply() end, "Needs raid lead or assist, out of combat" },
            { "Export", function() M.Export() end, "Copy the raid's current groups as a layout string" },
        })
        local status = L:Custom(20, function(f)
            f.text = FF.Text(f, "small")
            f.text:SetPoint("LEFT", 12, 0)
        end)
        L:Track({
            Refresh = function()
                local p = current
                if p then
                    local n = 0
                    for i = 1, 8 do
                        n = n + #p.groups[i]
                    end
                    status.text:SetText(("Loaded: %s (%d players)"):format(p.name, n))
                else
                    status.text:SetText(FF.Hex(FF.C.muted) .. "No layout loaded|r")
                end
            end,
        })

        L:Header("Assistants")
        L:Toggle("Make everyone assistant", db, "everyoneAssist", { onChange = queuePromote })
        local notAll = function() return not db.everyoneAssist end
        L:Toggle("Promote by guild rank", db, "promoteByRank", { dep = notAll, onChange = queuePromote })
        L:Slider("Rank and above (0 = GM)", db, "promoteRank", 0, 9, 1, { dep = function() return notAll() and db.promoteByRank end, indent = 12,
            onChange = queuePromote, tip = "Guild rank index - 0 is the guild master, 1 the next rank down, ..." })
        L:Toggle("Promote these players", db, "autoPromote", { dep = notAll, onChange = queuePromote })
        L:Input("Players (comma separated)", db, "_promote", {
            lines = 3, indent = 12,
            dep = function() return notAll() and db.autoPromote end,
            get = function()
                local names = {}
                for n in pairs(db.promote) do
                    names[#names + 1] = n
                end
                table.sort(names)
                return table.concat(names, ", ")
            end,
            set = function(v)
                wipe(db.promote)
                for n in v:gmatch("[^,\n]+") do
                    n = trim(n)
                    if n ~= "" then
                        db.promote[n] = true
                    end
                end
                queuePromote()
            end,
        })

        L:Header("Always-mark players")
        L:Desc("Give a player a raid marker and put it back if it's removed. List several names for one marker (comma separated) - the first one in your group gets it. Needs lead or assist in raids.")
        L:Toggle("Keep these markers on", db, "autoMark", { onChange = updateMarking })
        for i = 1, 8 do
            L:Input(("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t  %s"):format(i, MARKS[i]), db.marks, i, {
                width = 260, indent = 12, dep = function() return db.autoMark end, onChange = markPass,
            })
        end

        L:Header("Whisper invites")
        L:Toggle("Invite people who whisper a keyword", db, "inviteWord", { onChange = listenWhispers })
        L:Input("Keyword", db, "keyword", { dep = function() return db.inviteWord end, indent = 12 })
        L:Toggle("Guild members only", db, "inviteGuildOnly", { dep = function() return db.inviteWord end, indent = 12 })
    end)

    FF.Command("group", function(rest)
        local cmd = rest:match("^(%S*)"):lower()
        if cmd == "apply" then
            M.Apply()
        elseif cmd == "export" then
            M.Export()
        elseif cmd == "import" then
            importWindow()
        else
            FF.ShowOptions("Groups")
        end
    end, "group layouts, assistants, markers (opens settings)")
end)
