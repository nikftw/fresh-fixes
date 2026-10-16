local _, FF = ...
local M = FF.Module("Blessings")

-- Paladin blessings, PallyPower-compatible.
-- Assignment traffic uses PallyPower's own prefix and message formats, matched
-- to PallyPower Forever v10.15.26-forever (owner-supplied; same as CurseForge
-- project 1718986 file PallyPower-Forever-v1015.zip): prefix "PLPWR" on
-- PARTY / RAID / INSTANCE_CHAT (replies to non-leaders by WHISPER).
--   SELF <6x rank,talent hex|"nn">@<9 class assignments, digit|"n">
--   ASELF <7x aura rank,talent>@<aura>   ASSIGN <name> <class> <skill>
--   PASSIGN <name>@<9 digits>   MASSIGN <name> <skill>   CLEAR [SKIP]
--   NASSIGN <pname_> <class> <tname_> <skill>[@...]   (spaces sent as "_")
--   FREEASSIGN YES|NO | SYMCOUNT n | COOLDOWNS:..   SALV YES|NO   REQ
-- Forever classes 1..9: Warrior Rogue Priest Druid Paladin Hunter Mage Warlock Shaman.
-- Blessings: 1 Wisdom 2 Might 3 Kings 4 Salvation (own SALV toggle on Forever)
-- 5 Light 6 Sanctuary 7 Sacrifice. Forever has no improved-blessing talents (talent = 0).
-- If the real PallyPower addon is loaded, this module stays completely passive.
FF.Init("Blessings", function()
    local db = FF.DB("blessings", { panel = false, helper = true, salv = false, free = false, greater = true })
    local C, UI = FF.C, FF.UI
    local readable = FF.readable

    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded and (loaded("PallyPower")) then
        M.passive = true
        FF.Settings("Blessings", function(L)
            L:Header("Blessings")
            L:Desc("PallyPower is installed and running, so this module stays off (no panel, no messages) to avoid duplicates. Use PallyPower; assignments are the same either way.")
        end)
        return
    end

    local PREFIX = "PLPWR"
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
    local sendRaw = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage

    local MAXC = 9
    local CLASS = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
    local CLASSID = {}
    for i, c in ipairs(CLASS) do CLASSID[c] = i end
    -- rank lists exactly as PallyPower's NormalBuffs (non-Wrath)
    local RANKS = {
        { 27142, 25290, 19854, 19853, 19852, 19850, 19742 },
        { 27140, 25291, 19838, 19837, 19836, 19835, 19834, 19740 },
        { 20217 }, { 1038 },
        { 27144, 19979, 19978, 19977 },
        { 27168, 20914, 20913, 20912, 20911 },
        { 27148, 27147, 20729, 6940 },
    }
    local BASE = { 19742, 19740, 20217, 1038, 19977, 20911, 6940 }
    local GREATER = { 25894, 25782, 25898, 25895, 25890, 25899 }
    local AURAS = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } -- PALLYPOWER_MAXAURAS = 7
    local ICON = {
        "Interface\\Icons\\Spell_Holy_SealOfWisdom", "Interface\\Icons\\Spell_Holy_FistOfJustice",
        "Interface\\Icons\\Spell_Magic_MageArmor", "Interface\\Icons\\Spell_Holy_SealOfSalvation",
        "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", "Interface\\Icons\\Spell_Nature_LightningShield",
        "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    }
    local SHORT = { "Wis", "Might", "Kings", "Salv", "Light", "Sanc", "Sac" }

    local function spellInfo(id)
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, i = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(i) == "table" then return i.name, i.iconID end
        elseif GetSpellInfo then
            local ok, n, _, ic = pcall(GetSpellInfo, id)
            if ok then return n, ic end
        end
    end
    local function knows(id)
        local f = IsPlayerSpell or IsSpellKnown
        local ok, r = pcall(f, id)
        return ok and r
    end
    local function knownRank(b)
        local list = RANKS[b]
        for i, id in ipairs(list) do
            if knows(id) then return #list - i + 1 end
        end
    end
    local function greaterKnown(b)
        return GREATER[b] and knows(GREATER[b]) and spellInfo(GREATER[b]) or nil
    end

    -- Names as PallyPower keys them: "First Surname", realm dropped
    local function bare(n)
        if type(n) ~= "string" or not readable(n) then return end
        n = n:match("^([^%-]+)") or n
        if n == "" or #n > 48 then return end
        return n
    end
    local function unitName(u)
        local ok, n = pcall(GetUnitName, u, true)
        return ok and bare(n) or nil
    end
    local me = unitName("player")
    local myClass = select(2, UnitClass("player"))
    local isPally = myClass == "PALADIN"

    -- roster: name -> unit, rebuilt on demand
    local roster, rosterDirty = {}, true
    local function getRoster()
        if rosterDirty then
            roster = {}
            for _, u in ipairs(FF.GroupUnits()) do
                local n = unitName(u)
                if n then roster[n] = u end
            end
            rosterDirty = false
        end
        return roster
    end
    -- senders can arrive as "First" only: match a unique group member
    local function resolve(n)
        n = bare(n)
        if not n then return end
        local r = getRoster()
        if r[n] then return n, r[n] end
        local found
        for name, u in pairs(r) do
            if name:sub(1, #n + 1) == n .. " " then
                if found then return end
                found = name
            end
        end
        if found then return found, r[found] end
    end
    local function isLead(u)
        return u and (UnitIsGroupLeader(u) or UnitIsGroupAssistant(u)) or false
    end
    local function unitClass(u)
        return u and select(2, UnitClass(u))
    end

    ---------------------------------------------------------------------------
    -- State (session only: PallyPower re-syncs on join / REQ)
    ---------------------------------------------------------------------------
    local pals = {}   -- [name] = { ranks = {}, free = bool, salv = bool, spec = 0..3 }
    local assign = {} -- [name][class] = blessing
    local normal = {} -- [pname][class][tname] = blessing (per-player overrides)
    local myAura = 0
    M.pals, M.assign = pals, assign

    local refreshPanel, refreshHelper -- forward
    local function changed()
        if refreshPanel then refreshPanel() end
        if refreshHelper then refreshHelper() end
    end

    local function mySpec()
        -- 1 Holy, 2 Protection, 3 Retribution, 0 unknown (talent API may be missing on Forever)
        if not GetTalentTabInfo then return 0 end
        local best, spec = 0, 0
        for t = 1, 3 do
            local ok, a, b, c, d, e = pcall(GetTalentTabInfo, t)
            local pts = ok and ((type(c) == "number" and c) or (type(e) == "number" and e) or (type(d) == "number" and d)) or 0
            if type(pts) == "number" and pts > best then best, spec = pts, t end
        end
        return spec
    end

    local function scanSelf()
        if not (isPally and me) then return end
        local p = pals[me] or {}
        p.ranks = {}
        for b = 1, 7 do
            if b ~= 4 then p.ranks[b] = knownRank(b) end -- Forever: Salvation is its own switch
        end
        p.free, p.salv, p.spec = db.free and true or false, db.salv and true or false, mySpec()
        pals[me] = p
        assign[me] = assign[me] or {}
    end

    ---------------------------------------------------------------------------
    -- Sending: small queue, one message per 0.25s, group only, dedup repeats
    ---------------------------------------------------------------------------
    local q, pumping, last = {}, false, nil
    local function pump()
        local m = table.remove(q, 1)
        if m then
            pcall(sendRaw, PREFIX, m[1], m[2], m[3])
        end
        if #q > 0 then
            C_Timer.After(0.25, pump)
        else
            pumping = false
        end
    end
    local function send(msg, target)
        if not IsInGroup() or #msg > 250 then return end
        if not target then
            if msg == last then return end
            last = msg
        end
        local ch = target and "WHISPER" or FF.GroupChannel()
        if not ch or #q > 40 then return end
        q[#q + 1] = { msg, ch, target }
        if not pumping then
            pumping = true
            C_Timer.After(0, pump)
        end
    end

    local function sendSelf(target)
        if not (isPally and me and IsInGroup()) then return end
        scanSelf()
        local p, s = pals[me], {}
        for b = 1, 6 do
            s[#s + 1] = p.ranks[b] and ("%x0"):format(p.ranks[b]) or "nn"
        end
        s[#s + 1] = "@"
        local a = assign[me]
        for c = 1, MAXC do
            s[#s + 1] = (a[c] and a[c] > 0) and tostring(a[c]) or "n"
        end
        send("SELF " .. table.concat(s), target)
        local au = {}
        for i = 1, 7 do
            au[i] = (spellInfo(AURAS[i]) and knows(AURAS[i])) and "10" or "nn"
        end
        send("ASELF " .. table.concat(au) .. "@" .. myAura, target)
        local list = {}
        for c, t in pairs(normal[me] or {}) do
            for tn, b in pairs(t) do
                list[#list + 1] = ("%s %d %s %d"):format(me:gsub(" ", "_"), c, tn:gsub(" ", "_"), b)
            end
        end
        for i = 1, #list, 5 do
            send("NASSIGN " .. table.concat(list, "@", i, math.min(i + 4, #list)), target)
        end
        send(("FREEASSIGN %s | SYMCOUNT 0 | COOLDOWNS:n:n:n:n"):format(db.free and "YES" or "NO"), target)
        send(db.salv and "SALV YES" or "SALV NO", target)
        if not target then
            FF.Send("B", "s" .. (p.spec or 0), "GROUP") -- spec for other Fresh Fixes paladins
        end
    end

    -- debounced triggers
    local selfPending, reqFrom = false, {}
    local function sendSelfSoon()
        if selfPending then return end
        selfPending = true
        C_Timer.After(2, function()
            selfPending = false
            last = nil
            sendSelf()
        end)
    end
    local replyPending = false
    local function replySoon(name)
        reqFrom[name] = true
        if replyPending then return end
        replyPending = true
        C_Timer.After(1.5, function()
            replyPending = false
            local whisperTo, group = {}, false
            for n in pairs(reqFrom) do
                local _, u = resolve(n)
                if isLead(u) or IsInRaid() then group = true else whisperTo[#whisperTo + 1] = n end
            end
            reqFrom = {}
            if group then
                last = nil
                sendSelf()
            else
                for _, n in ipairs(whisperTo) do sendSelf(n) end
            end
        end)
    end

    -- outgoing assignment changes, batched per paladin
    local dirty, flushPending = {}, false
    local function flush()
        flushPending = false
        for name, classes in pairs(dirty) do
            local a = assign[name] or {}
            local n = 0
            for _ in pairs(classes) do n = n + 1 end
            if n > 2 then
                local s = {}
                for c = 1, MAXC do s[c] = (a[c] and a[c] > 0) and tostring(a[c]) or "n" end
                send("PASSIGN " .. name .. "@" .. table.concat(s))
            else
                for c in pairs(classes) do
                    send(("ASSIGN %s %d %d"):format(name, c, a[c] or 0))
                end
            end
        end
        dirty = {}
    end
    local function setAssign(name, c, b)
        assign[name] = assign[name] or {}
        if (assign[name][c] or 0) == (b or 0) then return end
        assign[name][c] = b
        dirty[name] = dirty[name] or {}
        dirty[name][c] = true
        if not flushPending then
            flushPending = true
            C_Timer.After(0.5, flush)
        end
    end

    -- may we change this paladin's assignments? (PallyPower's own rule)
    local function canEdit(name)
        if name == me then return true end
        if isLead("player") then return true end
        return pals[name] and pals[name].free or false
    end

    ---------------------------------------------------------------------------
    -- Receiving: PLPWR from a group member; paladin-only for paladin data
    ---------------------------------------------------------------------------
    local CH = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
    local function skillOk(v) v = tonumber(v); return v and v >= 0 and v <= 8 and math.floor(v) == v and v end
    local function classOk(v) v = tonumber(v); return v and v >= 1 and v <= MAXC and math.floor(v) == v and v end

    -- assignment for `target` written by `sender`: allowed if self, leader, or we are free-assign
    local function allowed(sender, su, target)
        return target == sender or isLead(su) or (target == me and db.free)
    end

    local function parse(sender, su, msg)
        local senderPally = unitClass(su) == "PALADIN"
        if msg == "REQ" then
            if isPally then replySoon(sender) end
            return
        end
        if msg:find("^SELF ") then
            if not senderPally then return end
            local nums, a = msg:match("^SELF ([0-9a-fn]+)@([0-9n]*)$")
            if not nums or #nums ~= 12 or #a > MAXC then return end
            local p = pals[sender] or {}
            p.ranks = {}
            for b = 1, 6 do
                local r = nums:sub(b * 2 - 1, b * 2 - 1)
                if r ~= "n" then p.ranks[b] = tonumber(r, 16) end
            end
            pals[sender] = p
            assign[sender] = {}
            for c = 1, MAXC do
                assign[sender][c] = skillOk(a:sub(c, c)) or 0
            end
        elseif msg:find("^PASSIGN ") then
            local name, a = msg:match("^PASSIGN (.+)@([0-9n]+)$")
            local target, tu = resolve(name)
            if not target or unitClass(tu) ~= "PALADIN" or #a > MAXC or not allowed(sender, su, target) then return end
            assign[target] = {}
            for c = 1, MAXC do assign[target][c] = skillOk(a:sub(c, c)) or 0 end
        elseif msg:find("^ASSIGN ") then
            local name, c, b = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
            local target, tu = resolve(name)
            c, b = classOk(c), skillOk(b)
            if not (target and c and b) or unitClass(tu) ~= "PALADIN" or not allowed(sender, su, target) then return end
            assign[target] = assign[target] or {}
            assign[target][c] = b
        elseif msg:find("^MASSIGN ") then
            local name, b = msg:match("^MASSIGN (.+) (%d+)$")
            local target, tu = resolve(name)
            b = skillOk(b)
            if not (target and b) or unitClass(tu) ~= "PALADIN" or not allowed(sender, su, target) then return end
            assign[target] = {}
            for c = 1, MAXC do assign[target][c] = b end
        elseif msg:find("^NASSIGN ") then
            local n = 0
            for pn, c, tn, b in msg:sub(9):gmatch("([^@ ]+) ([^@ ]+) ([^@ ]+) ([^@ ]+)") do
                n = n + 1
                if n > 5 then break end
                local target, tu = resolve((pn:gsub("_", " ")))
                local tname = bare((tn:gsub("_", " ")))
                c, b = classOk(c), skillOk(b)
                if target and tname and c and b and unitClass(tu) == "PALADIN" and allowed(sender, su, target) then
                    normal[target] = normal[target] or {}
                    normal[target][c] = normal[target][c] or {}
                    local t = normal[target][c]
                    local count = 0
                    for _ in pairs(t) do count = count + 1 end
                    if b == 0 then t[tname] = nil elseif t[tname] or count < 40 then t[tname] = b end
                end
            end
        elseif msg:find("^CLEAR") then
            if isLead(su) then
                for name in pairs(assign) do assign[name] = {} end
                normal = {}
            end
        elseif msg:find("^AASSIGN ") then
            local name, v = msg:match("^AASSIGN (.+) (%d+)$")
            local target = resolve(name)
            v = tonumber(v)
            if target == me and v and v <= 8 and allowed(sender, su, me) then myAura = v end
            return
        end
        if senderPally and pals[sender] then
            if msg:find("FREEASSIGN YES", 1, true) then pals[sender].free = true
            elseif msg:find("FREEASSIGN NO", 1, true) then pals[sender].free = false end
            if msg:find("^SALV YES") then pals[sender].salv = true
            elseif msg:find("^SALV NO") then pals[sender].salv = false end
        end
        changed()
    end

    local function onAddon(_, prefix, msg, channel, source)
        if not readable(prefix) or prefix ~= PREFIX then return end
        if not (readable(msg) and readable(channel) and readable(source)) then return end
        if type(msg) ~= "string" or #msg > 255 or not CH[channel] or not IsInGroup() then return end
        local sender, su = resolve(Ambiguate and Ambiguate(source, "none") or source)
        if not sender or sender == me then return end -- must be in our group
        parse(sender, su, msg)
    end
    FF.On("CHAT_MSG_ADDON", onAddon)

    FF.OnComm("B", function(payload, _, display)
        local sender, su = resolve(display)
        local s = payload:match("^s([0-3])$")
        if sender and s and unitClass(su) == "PALADIN" and pals[sender] then
            pals[sender].spec = tonumber(s)
            changed()
        end
    end)

    ---------------------------------------------------------------------------
    -- Smart auto-assign: class priorities, spec preference, known blessings
    ---------------------------------------------------------------------------
    local PRIO = {
        { 3, 2, 5, 6 }, { 3, 2, 5, 6 }, { 3, 1, 5, 6 }, { 3, 1, 2, 5 }, { 3, 1, 2, 5 },
        { 3, 2, 1, 5 }, { 3, 1, 5, 6 }, { 3, 1, 5, 6 }, { 3, 1, 2, 5 },
    }
    local PREFER = { [1] = 1, [2] = 3, [6] = 2, [3] = 2 } -- blessing -> spec that should give it

    local function activePals()
        local list, r = {}, getRoster()
        for name in pairs(pals) do
            if r[name] and unitClass(r[name]) == "PALADIN" then list[#list + 1] = name end
        end
        table.sort(list)
        return list
    end

    function M.Smart()
        if InCombatLockdown() then FF.print("Not in combat") return end
        scanSelf()
        local list = activePals()
        if #list == 0 then FF.print("No paladins found (they need PallyPower or Fresh Fixes Blessings)") return end
        local plan = {}
        for _, n in ipairs(list) do plan[n] = {} end
        for c = 1, MAXC do
            local used = {}
            for _, b in ipairs(PRIO[c]) do
                local best, score
                for _, n in ipairs(list) do
                    local p = pals[n]
                    if not used[n] and p.ranks and p.ranks[b] then
                        local s = p.ranks[b] + ((p.spec or 0) == PREFER[b] and 100 or 0)
                        if not score or s > score then best, score = n, s end
                    end
                end
                if best then
                    used[best] = true
                    plan[best][c] = b
                end
            end
        end
        local skipped = 0
        for n, a in pairs(plan) do
            if canEdit(n) then
                for c = 1, MAXC do setAssign(n, c, a[c] or 0) end
            else
                skipped = skipped + 1
            end
        end
        FF.print(skipped > 0 and ("Assigned; %d paladin(s) skipped (need lead/assist or their Free Assignment)"):format(skipped) or "Blessings assigned")
        changed()
    end

    function M.Clear()
        if not isLead("player") then
            for c = 1, MAXC do setAssign(me, c, 0) end
        else
            for n in pairs(assign) do assign[n] = {} end
            normal = {}
            send("CLEAR")
        end
        changed()
    end

    ---------------------------------------------------------------------------
    -- Assignment panel (flat grid)
    ---------------------------------------------------------------------------
    local panel
    local CELL, NAMEW = 20, 96
    local function icon(b)
        local _, ic = spellInfo(BASE[b])
        return ic or ICON[b]
    end
    local function cycle(name, c, dir)
        local p = pals[name]
        if not p or not p.ranks then return end
        local opts = { 0 }
        for b = 1, 7 do if p.ranks[b] then opts[#opts + 1] = b end end
        local cur, idx = (assign[name] or {})[c] or 0, 1
        for i, b in ipairs(opts) do if b == cur then idx = i end end
        idx = (idx - 1 + dir) % #opts + 1
        setAssign(name, c, opts[idx])
        changed()
    end

    local function buildPanel()
        panel = UI.Window("Blessings", "Blessings", NAMEW + MAXC * (CELL + 2) + 12, 80, { keepOpen = true })
        panel.rows = {}
        local y0 = -(UI.TITLE_H + 6)
        for c = 1, MAXC do
            local t = panel:CreateTexture(nil, "ARTWORK")
            t:SetSize(CELL - 4, CELL - 4)
            t:SetPoint("TOPLEFT", 6 + NAMEW + (c - 1) * (CELL + 2) + 2, y0)
            FF.SetIcon(t, "Interface\\Icons\\ClassIcon_" .. CLASS[c]:sub(1, 1) .. CLASS[c]:sub(2):lower())
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        panel.smart = UI.Button(panel, "Smart", 60, 18, M.Smart, "Auto-assign by known blessings and spec (Kings first, Wisdom from Holy, Might from Ret, Sanctuary from Prot)")
        panel.clear = UI.Button(panel, "Clear", 50, 18, M.Clear, "Leader: clear everyone's. Otherwise: clear yours")
        panel.buffs = UI.Button(panel, "Buffs", 50, 18, function()
            db.helper = not db.helper
            if refreshHelper then refreshHelper() end
        end, "Show / hide the buff helper")
        panel.status = FF.Text(panel, "small")
        panel.status:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        panel:SetScript("OnHide", function() db.panel = false end)
    end

    local function row(i)
        local r = panel.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, panel)
        r:SetSize(NAMEW + MAXC * (CELL + 2), CELL)
        r.name = FF.Text(r, "small")
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetWidth(NAMEW - 4)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.cells = {}
        for c = 1, MAXC do
            local b = CreateFrame("Button", nil, r)
            b:SetSize(CELL, CELL)
            b:SetPoint("LEFT", NAMEW + (c - 1) * (CELL + 2), 0)
            FF.Skin(b, "row")
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetPoint("TOPLEFT", 2, -2)
            b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", function(self, btn)
                if InCombatLockdown() or not canEdit(r.pal) then return end
                if IsShiftKeyDown() then
                    setAssign(r.pal, c, 0)
                    changed()
                else
                    cycle(r.pal, c, btn == "RightButton" and -1 or 1)
                end
            end)
            b:SetScript("OnEnter", function(self)
                FF.SetBorder(self, C.accent)
                local v = (assign[r.pal] or {})[c] or 0
                FF.Tip(self, (v > 0 and (spellInfo(BASE[v]) or SHORT[v]) or "None") ..
                    (canEdit(r.pal) and "\nClick / right-click to change, Shift-click to clear" or "\nLocked (needs lead/assist or their Free Assignment)"),
                    FF.ClassColor(CLASS[c], CLASS[c]:sub(1, 1) .. CLASS[c]:sub(2):lower()))
            end)
            b:SetScript("OnLeave", function(self)
                FF.SetBorder(self, C.border)
                FF.HideTip()
            end)
            r.cells[c] = b
        end
        panel.rows[i] = r
        return r
    end

    refreshPanel = function()
        if not panel or not panel:IsShown() then return end
        local list = activePals()
        local y = -(UI.TITLE_H + 6 + CELL)
        for i, name in ipairs(list) do
            local r = row(i)
            r.pal = name
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 6, y - (i - 1) * (CELL + 2))
            local p = pals[name]
            local tag = p.spec == 1 and " H" or p.spec == 2 and " P" or p.spec == 3 and " R" or ""
            r.name:SetText(FF.ClassColor("PALADIN", name:match("^(%S+)") or name) .. FF.Hex(C.muted) .. tag .. (p.free and " *" or "") .. "|r")
            for c = 1, MAXC do
                local v = (assign[name] or {})[c] or 0
                local cell = r.cells[c]
                if v > 0 then
                    cell.tex:SetTexture(icon(v))
                    cell.tex:Show()
                else
                    cell.tex:Hide()
                end
                cell:SetAlpha(canEdit(name) and 1 or 0.6)
            end
            r:Show()
        end
        for i = #list + 1, #panel.rows do panel.rows[i]:Hide() end
        local by = y - math.max(1, #list) * (CELL + 2) - 4
        panel.smart:ClearAllPoints()
        panel.smart:SetPoint("TOPLEFT", 6, by)
        panel.clear:SetPoint("LEFT", panel.smart, "RIGHT", 4, 0)
        panel.buffs:SetPoint("LEFT", panel.clear, "RIGHT", 4, 0)
        panel.status:SetPoint("LEFT", panel.buffs, "RIGHT", 6, 0)
        panel.status:SetText(#list == 0 and "no paladins" or (isLead("player") and "lead" or ""))
        panel:SetHeight(-by + 26)
    end

    function M.TogglePanel(on)
        if on == nil then on = not (panel and panel:IsShown()) end
        db.panel = on
        if on then
            if not panel then buildPanel() end
            panel:Show()
            if IsInGroup() then send("REQ") end
            refreshPanel()
        elseif panel then
            panel:Hide()
        end
    end

    ---------------------------------------------------------------------------
    -- Buff helper: who is missing MY assigned blessing. Secure buttons only:
    -- a click casts on that player; nothing is ever cast automatically.
    -- Attributes and visibility change only out of combat.
    ---------------------------------------------------------------------------
    local helper, hRows = nil, {}
    local MAXROWS = 12
    local function blessNames(b)
        local t = {}
        local n = spellInfo(BASE[b])
        if n then t[n] = true end
        if GREATER[b] then
            local g = spellInfo(GREATER[b])
            if g then t[g] = true end
        end
        return t
    end
    local function hasAny(unit, names)
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not a then return false end
            local n = a.name
            if not readable(n) then return true end -- hidden: don't nag
            if names[n] then return true end
        end
        return false
    end
    local function isTank(u)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        return role == "TANK" or (GetPartyAssignment and GetPartyAssignment("MAINTANK", u)) or false
    end

    local function missing()
        local out, a = {}, assign[me] or {}
        local salvName = db.salv and knows(1038) and spellInfo(1038)
        for name, u in pairs(getRoster()) do
            if #out >= MAXROWS then break end
            if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
                local c = CLASSID[unitClass(u) or ""]
                if c then
                    local b = (normal[me] and normal[me][c] and normal[me][c][name]) or a[c] or 0
                    if b > 0 and b ~= 4 and knownRank(b) and not hasAny(u, blessNames(b)) then
                        out[#out + 1] = { unit = u, name = name, class = unitClass(u), b = b,
                            spell = spellInfo(BASE[b]), greater = db.greater and greaterKnown(b) or nil }
                    elseif salvName and not isTank(u) and not hasAny(u, blessNames(4)) and #out < MAXROWS then
                        out[#out + 1] = { unit = u, name = name, class = unitClass(u), b = 4, spell = salvName }
                    end
                end
            end
        end
        table.sort(out, function(x, y) return x.name < y.name end)
        return out
    end

    local function buildHelper()
        helper = UI.Window("BlessingsHelper", "Missing blessings", 170, 40, { keepOpen = true })
        helper.close:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            db.helper = false
            helper:Hide()
        end)
        helper.empty = FF.Text(helper, "small")
        helper.empty:SetPoint("TOPLEFT", 6, -(UI.TITLE_H + 5))
        helper.empty:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        for i = 1, MAXROWS do
            local b = CreateFrame("Button", "FreshFixesBlessRow" .. i, helper, "SecureActionButtonTemplate")
            b:SetSize(158, 18)
            b:SetPoint("TOPLEFT", 6, -(UI.TITLE_H + 4) - (i - 1) * 20)
            b:RegisterForClicks("AnyUp", "AnyDown")
            FF.Skin(b, "row")
            b.ic = b:CreateTexture(nil, "ARTWORK")
            b.ic:SetSize(14, 14)
            b.ic:SetPoint("LEFT", 2, 0)
            b.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.text = FF.Text(b, "small")
            b.text:SetPoint("LEFT", b.ic, "RIGHT", 4, 0)
            b.text:SetPoint("RIGHT", -2, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetScript("OnEnter", function(self) FF.SetBorder(self, C.accent) end)
            b:SetScript("OnLeave", function(self) FF.SetBorder(self, C.border) end)
            b:Hide()
            hRows[i] = b
        end
    end

    local helperPending = false
    local function doRefreshHelper()
        helperPending = false
        if InCombatLockdown() then return end -- resumes on PLAYER_REGEN_ENABLED
        local want = db.helper and isPally and IsInGroup()
        if not want then
            if helper then helper:Hide() end
            return
        end
        if not helper then buildHelper() end
        local list = missing()
        for i, b in ipairs(hRows) do
            local d = list[i]
            if d then
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", d.spell)
                b:SetAttribute("unit", d.unit)
                b:SetAttribute("type2", "spell")
                b:SetAttribute("spell2", d.greater or d.spell)
                b:SetAttribute("unit2", d.unit)
                b.ic:SetTexture(icon(d.b))
                b.text:SetText(FF.ClassColor(d.class, d.name:match("^(%S+)") or d.name) .. FF.Hex(C.muted) .. "  " .. SHORT[d.b] .. "|r")
                b:Show()
            else
                b:SetAttribute("type", nil)
                b:SetAttribute("type2", nil)
                b:Hide()
            end
        end
        helper.empty:SetText(#list == 0 and "All blessed" or "")
        helper:SetHeight(UI.TITLE_H + 10 + math.max(1, #list) * 20)
        helper:Show()
    end
    refreshHelper = function()
        if helperPending then return end
        helperPending = true
        C_Timer.After(0.5, doRefreshHelper)
    end
    M.Refresh = changed

    ---------------------------------------------------------------------------
    -- Events: only while in a group
    ---------------------------------------------------------------------------
    local function onAura(_, unit)
        if helper and helper:IsShown() and type(unit) == "string" and (unit == "player" or unit:find("^raid") or unit:find("^party")) then
            refreshHelper()
        end
    end
    local wasInGroup = false
    local function onRoster()
        rosterDirty = true
        local inGroup = IsInGroup()
        FF.Listen("UNIT_AURA", onAura, inGroup and isPally)
        if inGroup and not wasInGroup then
            C_Timer.After(2, function()
                if IsInGroup() then
                    sendSelf()
                    send("REQ")
                end
            end)
        elseif not inGroup then
            for n in pairs(pals) do if n ~= me then pals[n] = nil end end
            last = nil
        end
        wasInGroup = inGroup
        changed()
    end
    FF.On("GROUP_ROSTER_UPDATE", onRoster)
    FF.On("PLAYER_REGEN_ENABLED", function() changed() end)
    FF.On("SPELLS_CHANGED", function()
        if isPally and IsInGroup() then sendSelfSoon() end
    end)
    FF.On("FF_READY", function()
        me = unitName("player") or me
        scanSelf()
        onRoster()
        if db.panel then M.TogglePanel(true) end
    end)

    FF.Command("bless", function(arg)
        arg = (arg or ""):lower()
        if arg == "smart" then M.Smart()
        elseif arg == "clear" then M.Clear()
        elseif arg == "buffs" then db.helper = not db.helper; refreshHelper()
        else M.TogglePanel() end
    end, "blessing panel ('bless smart', 'bless buffs', 'bless clear')")

    FF.Settings("Blessings", function(L)
        L:Header("Paladin blessings")
        L:Desc("PallyPower-style blessing assignments. Talks PallyPower's own protocol, so paladins on PallyPower Forever and on Fresh Fixes see each other's assignments. If PallyPower itself is installed this module stays out of the way.")
        L:Buttons({
            { "Open panel", function() M.TogglePanel(true) end, "/ff bless" },
            { "Smart assign", M.Smart, "Assign by known blessings and spec" },
        })
        L:Toggle("Buff helper: list who misses your blessing", db, "helper", { onChange = refreshHelper, tip = "Click a row to cast on that player. Never casts by itself" })
        L:Toggle("Right-click casts the Greater Blessing (if known)", db, "greater", { onChange = refreshHelper })
        L:Toggle("Offer Salvation (never on tanks)", db, "salv", { onChange = function()
            scanSelf(); send(db.salv and "SALV YES" or "SALV NO"); refreshHelper()
        end })
        L:Toggle("Free assignment (anyone may set my blessings)", db, "free", { onChange = function()
            scanSelf(); last = nil; sendSelfSoon()
        end })
    end)
end)
