local _, FF = ...
local M = FF.Module("Blessings")

-- Paladin blessings, PallyPower-compatible.
-- Assignment traffic uses PallyPower's own prefix and message formats, matched
-- to PallyPower Forever v10.15.26-forever (owner-supplied; same as CurseForge
-- project 1718986 file PallyPower-Forever-v1015.zip): prefix "PLPWR" on
-- PARTY / RAID / INSTANCE_CHAT (replies to non-leaders by WHISPER).
--   SELF <6x rank,talent hex|"nn">@<9 class assignments, digit|"n">
--   ASSIGN <name> <class> <skill>
--   PASSIGN <name>@<9 digits>   MASSIGN <name> <skill>   CLEAR [SKIP]
--   (ASELF / AASSIGN from PallyPower are ignored — we do not track group auras)
--   NASSIGN <pname_> <class> <tname_> <skill>[@...]   (spaces sent as "_")
--   FREEASSIGN YES|NO | SYMCOUNT n | COOLDOWNS:..   SALV YES|NO   REQ
--   SALVASSIGN <name> YES|NO   (Fresh Fixes: free-assign Salv like blessings; target
--   also emits SALV YES|NO so PallyPower peers stay in sync)
-- Forever classes 1..9: Warrior Rogue Priest Druid Paladin Hunter Mage Warlock Shaman.
-- Blessings: 1 Wisdom 2 Might 3 Kings 4 Salvation 5 Light 6 Sanctuary 7 Sacrifice.
-- Forever: Salv stacks with blessings and is never a class-column assign — it has its
-- own panel column; the helper shows one Salv cell per class (column when vertical,
-- row when horizontal). Sanctuary was removed (no Forever spell). SELF ranks
-- use spell-rank hex + talent nibble (talent always 0 — Forever has no improved
-- blessings). All spell IDs below are Forever client IDs (wowhead.com/forever).
-- Instance groups: no PP "leaders" (match CanControl / CheckLeader). If the real
-- PallyPower addon is loaded, this module stays completely passive.
FF.Init("Blessings", function()
    local db = FF.DB("blessings", {
        panel = false, helper = true, salv = false, free = true, greater = true,
        layout = "vertical", showNick = true, showTitle = false,
        -- Assignments control on the helper (always first by default).
        assignBtn = true,
        helperLocked = true, -- red = locked; green = unlocked (drag to move)
        autoBtn = true, -- PallyPower-style Auto Buff button on the helper
        -- "assign_auto" | "auto_assign" — which control comes first on the shared 50/50 row.
        ctrlOrder = "assign_auto",
        -- Fixed helper column width (px); timer text is centered in its slot.
        colWidth = 56,
        -- Expanded player-row width on the buff helper (px).
        playerWidth = 90,
        -- Timer placement: "left" | "right" | "above" | "below" (default right).
        timerPos = "right",
        -- Salv helper strip: either toggle shows the column/row.
        salvIcon = true, salvTimer = true,
        -- Tint Salv icon green when buffed / red when anyone in that class is missing.
        salvColorIcon = true,
        -- "auto" | "left" | "right" | "above" | "below"
        -- auto = right when vertical, below when horizontal.
        salvPos = "auto",
        -- Active indicator: independent channels (replaces old activeStyle select).
        activeBorder = true, activeTimer = true, activeFill = false, activeIcon = true,
        -- Timer on blessed cells: "m:ss" | "m" | "h:mm:ss" | "compact"
        timerFormat = "m:ss",
    })
    -- Nested tables must be owned by this character's db (not the shared defaults).
    if type(rawget(db, "assign")) ~= "table" then db.assign = {} end
    if type(rawget(db, "normal")) ~= "table" then db.normal = {} end
    db.auras, db.aura = nil, nil -- retired: no group-aura tracking
    -- One-time migrate from the old single-select activeStyle.
    if rawget(db, "activeStyle") ~= nil then
        local s = db.activeStyle
        db.activeBorder = (s == "border" or s == "both" or s == "all")
        db.activeTimer = (s == "timer" or s == "both" or s == "all")
        db.activeFill = (s == "fill" or s == "all")
        db.activeStyle = nil
    end
    -- Enable assignments control if coming from the old off-by-default A button.
    if rawget(db, "assignStyle") == nil and rawget(db, "assignBtn") == nil then
        db.assignBtn = true
    end
    db.assignStyle, db.assignPos = nil, nil -- retired: Auto+Assign share a top row; Assign is a cog
    if db.timerPos == "auto" then
        db.timerPos = (db.layout == "horizontal") and "below" or "right"
    end
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
    -- Forever rank lists (highest first). No TBC 27xxx IDs — those 404 on ForeverDB.
    local RANKS = {
        { 25290, 19854, 19853, 19852, 19850, 19742 },           -- Wisdom R6..R1
        { 25291, 19838, 19837, 19836, 19835, 19834, 19740 },   -- Might R7..R1
        { 20217 },                                             -- Kings
        { 1038 },                                              -- Salvation (SALV switch; not class-assigned)
        { 19979, 19978, 19977 },                               -- Light R3..R1
        {},                                                    -- Sanctuary removed in Forever
        { 20729, 6940 },                                       -- Sacrifice R2..R1
    }
    -- Rank-1 (or only) IDs for icons / name lookup when the spell exists in Forever.
    local BASE = { 19742, 19740, 20217, 1038, 19977, nil, 6940 }
    -- Greater / Mass ranks (highest first). Slot 4 = Mass Salvation; slot 6 gone with Sanctuary.
    local GREATER = {
        { 25918, 25894 }, -- Greater Wisdom R2..R1
        { 25916, 25782 }, -- Greater Might R2..R1
        { 25898 },        -- Greater Kings
        { 25895 },        -- Mass Salvation
        { 25890 },        -- Greater Light
        {},               -- no Greater Sanctuary
    }
    local ICON = {
        "Interface\\Icons\\Spell_Holy_SealOfWisdom", "Interface\\Icons\\Spell_Holy_FistOfJustice",
        "Interface\\Icons\\Spell_Magic_MageArmor", "Interface\\Icons\\Spell_Holy_SealOfSalvation",
        "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", "Interface\\Icons\\Spell_Nature_LightningShield",
        "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    }
    local SHORT = { "Wis", "Might", "Kings", "Salv", "Light", "Sanc", "Sac" }

    local function spellInfo(id)
        if not id then return end
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, i = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(i) == "table" then return i.name, i.iconID end
        elseif GetSpellInfo then
            local ok, n, _, ic = pcall(GetSpellInfo, id)
            if ok then return n, ic end
        end
    end
    local function knows(id)
        if not id then return end
        -- Prefer IsPlayerSpell (covers overrides); fall back to IsSpellKnown.
        if IsPlayerSpell then
            local ok, r = pcall(IsPlayerSpell, id)
            if ok and r then return true end
        end
        if IsSpellKnown then
            local ok, r = pcall(IsSpellKnown, id)
            if ok and r then return true end
        end
    end
    local function firstKnown(list)
        if type(list) ~= "table" then return end
        for _, id in ipairs(list) do
            if knows(id) then return id end
        end
    end
    local function listSpell(list)
        local id = firstKnown(list)
        if id then return spellInfo(id) end
        -- Fallback: client spell data for the highest listed Forever ID (icons / tips).
        if type(list) == "table" and list[1] then return spellInfo(list[1]) end
    end
    -- Spell rank as PallyPower encodes it (GetSpellSubtext digit), not list index.
    local function knownRank(b)
        if b == 4 or b == 6 then return end -- Forever: Salv is SALV; Sanctuary removed
        local list = RANKS[b]
        if not list or #list == 0 then return end
        for _, id in ipairs(list) do
            if knows(id) then
                local name = spellInfo(id)
                if name and GetSpellSubtext then
                    local ok, sub = pcall(GetSpellSubtext, name)
                    if ok and type(sub) == "string" then
                        local r = tonumber(sub:match("(%d+)"))
                        if r then return r end
        end
    end
                return 1
    end
        end
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
    local me, myClass, isPally
    local function refreshIdentity()
        me = unitName("player") or me
        myClass = select(2, UnitClass("player")) or myClass
        isPally = myClass == "PALADIN"
    end
    refreshIdentity()

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
    -- PallyPower Forever: no "leaders" inside instance groups (CanControl / CheckLeader).
    local function inInstanceGroup()
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance()
    end
    local leaders = {}
    local function refreshLeaders()
        wipe(leaders)
        if inInstanceGroup() then return end
        for _, u in ipairs(FF.GroupUnits()) do
            if UnitIsGroupLeader(u) or UnitIsGroupAssistant(u) then
                local n = unitName(u)
                if n then leaders[n] = true end
            end
        end
    end
    local function checkLeader(name)
        return name and leaders[name] == true
    end
    local function isLead(u)
        return u and (UnitIsGroupLeader(u) or UnitIsGroupAssistant(u)) or false
    end
    local function unitClass(u)
        return u and select(2, UnitClass(u))
    end

    ---------------------------------------------------------------------------
    -- State: assignments persist in SavedVariables; ranks re-sync via PLPWR
    ---------------------------------------------------------------------------
    local pals = {}   -- [name] = { ranks = {}, free = bool, salv = bool, spec = 0..3 }
    local assign = db.assign -- [name][class] = blessing (saved)
    local normal = db.normal -- [pname][class][tname] = blessing (saved)
    M.pals, M.assign = pals, assign

    -- Forever: Salv (4) is not a class assign; Sanctuary (6) was removed — strip once.
    if not rawget(db, "foreverSpellIds") then
        db.foreverSpellIds = true
        db.foreverSalvSplit = true -- legacy flag; keep so older chars skip the old path
        for _, byClass in pairs(assign) do
            if type(byClass) == "table" then
                for c, v in pairs(byClass) do
                    if v == 4 or v == 6 then byClass[c] = 0 end
                end
            end
        end
        for _, byClass in pairs(normal) do
            if type(byClass) == "table" then
                for _, byName in pairs(byClass) do
                    if type(byName) == "table" then
                        for n, v in pairs(byName) do
                            if v == 4 or v == 6 then byName[n] = nil end
                        end
                    end
                end
            end
        end
    end

    local refreshPanel, refreshHelper -- forward
    local panelPending

    local function hoverOn(self)
        FF.SetBg(self, C.hover)
        FF.SetBorder(self, C.accent)
    end
    local function hoverOff(self)
        FF.SetBg(self, C.row)
        FF.SetBorder(self, C.border)
    end
    local function iconIn(f, inset)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return t
    end
    -- Hard-clip long names (no "..."). Clip frame sizes the slot; text is left-anchored only.
    local function clipLabel(parent, font)
        local clip = CreateFrame("Frame", nil, parent)
        clip:SetClipsChildren(true)
        local fs = FF.Text(clip, font or "small")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        fs:SetPoint("LEFT", 0, 0)
        return clip, fs
    end
    -- Debounce panel; helper has its own debounce (avoids scroll/wheel thrash).
    local function changed()
        if refreshPanel and not panelPending then
            panelPending = true
            C_Timer.After(0.15, function()
                panelPending = false
        if refreshPanel then refreshPanel() end
            end)
        end
        if refreshHelper then refreshHelper() end
    end

    local function mySpec()
        -- Primary talent tab (1..3) by points invested; 0 unknown. Works for any class.
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
        refreshLeaders()
        if checkLeader(me) then
            send("PPLEADER " .. me, target)
        end
        scanSelf()
        local p, s = pals[me], {}
        -- Six pairs: blessings 1..6 (Salv slot is nn on Forever). Digits = spell rank + talent.
        for b = 1, 6 do
            s[#s + 1] = p.ranks[b] and ("%x0"):format(p.ranks[b]) or "nn"
        end
        s[#s + 1] = "@"
        local a = assign[me] or {}
        for c = 1, MAXC do
            local v = a[c] or 0
            if v == 4 or v == 6 then v = 0 end -- Forever: Salv / removed Sanctuary
            s[#s + 1] = v > 0 and tostring(v) or "n"
        end
        send("SELF " .. table.concat(s), target)
        local list = {}
        for c, t in pairs(normal[me] or {}) do
            for tn, b in pairs(t) do
                if b ~= 4 and b ~= 6 then
                list[#list + 1] = ("%s %d %s %d"):format(me:gsub(" ", "_"), c, tn:gsub(" ", "_"), b)
                end
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
    local selfPending = false
    local function sendSelfSoon()
        if selfPending then return end
        selfPending = true
        C_Timer.After(2, function()
            selfPending = false
            last = nil
            sendSelf()
        end)
    end

    -- PallyPower REQ reply: instance raid → group; else whisper unless requester is PP-leader.
    local function replyToReq(sender)
        if not isPally then return end
                last = nil
        if IsInRaid() and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
            sendSelf()
        elseif checkLeader(sender) then
                sendSelf()
            else
            sendSelf(sender)
            end
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
                for c = 1, MAXC do
                    local v = a[c] or 0
                    if v == 4 or v == 6 then v = 0 end
                    s[c] = v > 0 and tostring(v) or "n"
                end
                send("PASSIGN " .. name .. "@" .. table.concat(s))
            else
                for c in pairs(classes) do
                    local v = a[c] or 0
                    if v == 4 or v == 6 then v = 0 end
                    send(("ASSIGN %s %d %d"):format(name, c, v))
                end
            end
        end
        dirty = {}
    end
    local function setAssign(name, c, b)
        if b == 4 or b == 6 then b = 0 end -- Forever: Salv split; Sanctuary removed
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

    -- Individual (small) blessings: normal[pname][class][tname] = blessing
    -- PallyPower NASSIGN — e.g. Holy on Might for Pallies but small Wisdom on themselves.
    local normalDirty, normalFlushPending = {}, false
    local function flushNormal()
        normalFlushPending = false
        local list = {}
        for _, e in ipairs(normalDirty) do
            list[#list + 1] = ("%s %d %s %d"):format(
                e.pname:gsub(" ", "_"), e.c, e.tname:gsub(" ", "_"), e.b or 0)
        end
        wipe(normalDirty)
        if #list == 0 or not IsInGroup() then return end
        for i = 1, #list, 5 do
            send("NASSIGN " .. table.concat(list, "@", i, math.min(i + 4, #list)))
        end
    end
    -- quiet = skip UI refresh (caller updates a single row; used by mousewheel).
    local function setNormal(pname, c, tname, b, quiet)
        if not (pname and c and tname) then return end
        b = tonumber(b) or 0
        if b == 4 or b == 6 then b = 0 end
        if b == 7 and tname == pname then b = 0 end -- no Sacrifice on self
        normal[pname] = normal[pname] or {}
        normal[pname][c] = normal[pname][c] or {}
        local cur = normal[pname][c][tname]
        local nextv = b > 0 and b or nil
        if cur == nextv then return end
        normal[pname][c][tname] = nextv
        normalDirty[#normalDirty + 1] = { pname = pname, c = c, tname = tname, b = b }
        if not normalFlushPending then
            normalFlushPending = true
            C_Timer.After(0.5, flushNormal)
        end
        if not quiet then changed() end
    end
    local function getNormal(pname, c, tname)
        local t = normal[pname] and normal[pname][c]
        local v = t and t[tname]
        return (type(v) == "number" and v > 0) and v or 0
    end
    -- Like PallyPower GetSpellID: individual normal (or class greater), plus class greater.
    local function blessingFor(pname, c, tname)
        local greater = (assign[pname] or {})[c] or 0
        local n = getNormal(pname, c, tname)
        if n == 0 then n = greater end
        return n, greater
    end
    -- Cached per roster generation (getRoster replaces the table when dirty).
    local memberCache, memberCacheRoster = {}, nil
    local function classMembers(c)
        local r = getRoster()
        if memberCacheRoster ~= r then
            wipe(memberCache)
            memberCacheRoster = r
        end
        local cached = memberCache[c]
        if cached then return cached end
        local out = {}
        for name, u in pairs(r) do
            if CLASSID[unitClass(u) or ""] == c then
                out[#out + 1] = { name = name, unit = u }
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        memberCache[c] = out
        return out
    end
    local function shortName(n)
        if type(n) ~= "string" then return "" end
        return n:match("^(%S+)") or n
    end
    local function cycleNormal(pname, c, tname, dir, quiet)
        local p = pals[pname]
        local opts = { 0 }
        local known
        if p and p.ranks then
            for b = 1, 7 do if p.ranks[b] then known = true; break end end
        end
        for b = 1, 7 do
            if b ~= 4 and b ~= 6 and not (b == 7 and tname == pname) then
                if (known and p.ranks[b]) or (not known and pname ~= me) or (pname == me and knownRank(b)) then
                    opts[#opts + 1] = b
                end
            end
        end
        if #opts == 1 then return end
        local cur, idx = getNormal(pname, c, tname), 1
        for i, v in ipairs(opts) do if v == cur then idx = i end end
        idx = (idx - 1 + (dir or 1)) % #opts + 1
        setNormal(pname, c, tname, opts[idx], quiet)
    end

    -- PallyPower CanControl: in instance → self or their freeassign; else lead/assist or self or freeassign
    local function canEdit(name)
        if name == me then return true end
        if pals[name] and pals[name].free then return true end
        if not inInstanceGroup() and isLead("player") then return true end
        return false
    end

    -- Forever Salv: free-assign like blessings (canEdit). Multiple pallies can be on Salv.
    local function setSalv(name, on)
        on = on and true or false
        if not name or not canEdit(name) then return end
        pals[name] = pals[name] or { ranks = {}, free = false, salv = false, spec = 0 }
        local cur = name == me and db.salv or pals[name].salv
        if (cur and true or false) == on then return end
        pals[name].salv = on
        if name == me then
            db.salv = on
            scanSelf()
            send(on and "SALV YES" or "SALV NO")
        end
        if IsInGroup() then
            send(("SALVASSIGN %s %s"):format(name, on and "YES" or "NO"))
        end
        changed()
    end

    ---------------------------------------------------------------------------
    -- Receiving: PLPWR from a group member; paladin-only for paladin data
    ---------------------------------------------------------------------------
    local CH = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
    local function skillOk(v)
        v = tonumber(v)
        if type(v) ~= "number" or v < 0 or v > 8 or math.floor(v) ~= v then return end
        if v == 4 or v == 6 then return 0 end -- Forever: Salv is SALV; Sanctuary removed
        return v
    end
    local function classOk(v)
        v = tonumber(v)
        if type(v) ~= "number" or v < 1 or v > MAXC or math.floor(v) ~= v then return end
        return v
    end

    -- PallyPower ParseMessage accept: self, CheckLeader(sender), or *our* freeassign
    local function allowed(sender, _su, target)
        return target == sender or checkLeader(sender) or db.free
    end

    local function parse(sender, su, msg)
        local senderPally = unitClass(su) == "PALADIN"
        if msg == "REQ" then
            replyToReq(sender)
            return
        end
        if msg:find("^PPLEADER ") then
            local name = bare(msg:match("^PPLEADER (.+)"))
            name = name and (resolve(name) or name)
            if name and not inInstanceGroup() then leaders[name] = true end
            return
        end
        if msg:find("^SELF ") then
            if not senderPally then return end
            local nums, a = msg:match("^SELF ([0-9a-fn]+)@([0-9n]*)")
            if not nums or #nums < 12 then return end
            a = a or ""
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
            local name, a = msg:match("^PASSIGN (.+)@([0-9n]*)")
            local target, tu = resolve(name)
            if not target or unitClass(tu) ~= "PALADIN" or not a or #a > MAXC or not allowed(sender, su, target) then return end
            assign[target] = {}
            for c = 1, MAXC do assign[target][c] = skillOk(a:sub(c, c)) or 0 end
        elseif msg:find("^ASSIGN ") then
            local name, c, b = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
            local target, tu = resolve(name)
            c, b = classOk(c), skillOk(b)
            if not (target and c and b ~= nil) or unitClass(tu) ~= "PALADIN" or not allowed(sender, su, target) then return end
            assign[target] = assign[target] or {}
            assign[target][c] = b
        elseif msg:find("^MASSIGN ") then
            local name, b = msg:match("^MASSIGN (.+) (%d+)$")
            local target, tu = resolve(name)
            b = skillOk(b)
            if not (target and b ~= nil) or unitClass(tu) ~= "PALADIN" or not allowed(sender, su, target) then return end
            assign[target] = {}
            for c = 1, MAXC do assign[target][c] = b end
        elseif msg:find("^NASSIGN ") then
            local n = 0
            for pn, c, tn, b in msg:sub(9):gmatch("([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
                n = n + 1
                if n > 5 then break end
                if pn ~= "" and tn ~= "" then
                local target, tu = resolve((pn:gsub("_", " ")))
                local tname = bare((tn:gsub("_", " ")))
                c, b = classOk(c), skillOk(b)
                    if target and tname and c and b ~= nil and unitClass(tu) == "PALADIN" and allowed(sender, su, target) then
                    normal[target] = normal[target] or {}
                    normal[target][c] = normal[target][c] or {}
                    local t = normal[target][c]
                    local count = 0
                    for _ in pairs(t) do count = count + 1 end
                    if b == 0 then t[tname] = nil elseif t[tname] or count < 40 then t[tname] = b end
                    end
                end
            end
        elseif msg:find("^CLEAR") then
            if checkLeader(sender) then
                for name in pairs(assign) do assign[name] = {} end
                wipe(normal)
            elseif db.free then
                assign[me] = {}
                normal[me] = nil
            end
        elseif msg:find("^ASELF ") or msg:find("^AASSIGN ") then
            return -- group auras: ignore PallyPower aura traffic
        elseif msg:find("^SALVASSIGN ") then
            -- Free-assign Salv (Fresh Fixes); the target also emits SALV YES/NO for PallyPower.
            local name, yn = msg:match("^SALVASSIGN (.+) (YES|NO)$")
            local target, tu = resolve(name)
            if target and yn and unitClass(tu) == "PALADIN" and allowed(sender, su, target) then
                pals[target] = pals[target] or { ranks = {}, free = false, salv = false, spec = 0 }
                local on = yn == "YES"
                pals[target].salv = on
                if target == me and db.salv ~= on then
                    db.salv = on
                    scanSelf()
                    send(on and "SALV YES" or "SALV NO")
                end
            end
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

    ---------------------------------------------------------------------------
    -- Paladin rows: you first, then every other paladin in the party/raid
    ---------------------------------------------------------------------------
    local function ensurePal(name)
        if not pals[name] then
            pals[name] = { ranks = {}, free = false, salv = false, spec = 0 }
        end
        assign[name] = assign[name] or {}
        return pals[name]
    end

    local function nickFor(name, unit)
        if not db.showNick then return end
        local nicks = FF.modules.Nicknames
        if not (nicks and nicks.loaded) then return end
        local nick
        if unit and nicks.ForUnit then nick = nicks.ForUnit(unit) end
        if not nick and name and nicks.Get then nick = nicks.Get(name) end
        if not nick and unit then nick = FF.NickOr(FF.UnitKey(unit)) end
        if type(nick) == "string" and nick ~= "" then return nick end
    end

    -- Display name: nickname when enabled, else first name (no color).
    local function dispName(name, unit)
        return nickFor(name, unit) or shortName(name) or "?"
    end

    -- Assignment list label: nickname only when enabled, else character first name.
    local function palLabel(name, unit)
        local short = dispName(name, unit)
        return FF.ClassColor("PALADIN", short)
    end

    local function activePals()
        refreshIdentity()
        rosterDirty = true
        local list, seen, units = {}, {}, {}
        local function add(name, u, front)
            if not name or seen[name] then return end
            local class = unitClass(u)
            if u ~= "player" and not (readable(class) and class == "PALADIN") then return end
            if u == "player" and not isPally then return end
            seen[name] = true
            ensurePal(name)
            units[name] = u
            if front then
                table.insert(list, 1, name)
            else
                list[#list + 1] = name
            end
        end
        if isPally and me then
            scanSelf()
            add(me, "player", true)
        end
        for _, u in ipairs(FF.GroupUnits()) do
            if u ~= "player" then
                add(unitName(u), u, false)
            end
        end
        if #list > 1 then
            if isPally and me and list[1] == me then
                local rest = {}
                for i = 2, #list do rest[#rest + 1] = list[i] end
                table.sort(rest)
                list = { me }
                for _, n in ipairs(rest) do list[#list + 1] = n end
            else
        table.sort(list)
            end
        end
        return list, units
    end

    ---------------------------------------------------------------------------
    -- Auto-assign (assignment panel only — not in settings)
    ---------------------------------------------------------------------------
    -- Forever: no Sanctuary (was 6). Prefer Kings / Might / Wisdom / Light.
    local PRIO = {
        { 3, 2, 5 }, { 3, 2, 5 }, { 3, 1, 5 }, { 3, 1, 2, 5 }, { 3, 1, 2, 5 },
        { 3, 2, 1, 5 }, { 3, 1, 5 }, { 3, 1, 5 }, { 3, 1, 2, 5 },
    }
    local PREFER = { [1] = 1, [2] = 3, [6] = 2, [3] = 2 } -- paladin spec → preferred blessing
    -- 1 Wisdom, 2 Might. Hybrids report talent-tab preference via FFIXES "B" (Q / N1|N2).
    local CASTER = { PRIEST = true, MAGE = true, WARLOCK = true }
    local PHYSICAL = { WARRIOR = true, ROGUE = true }
    -- Primary talent tab → preferred bless (each client reads only its own talents).
    local TAB_NEED = {
        DRUID   = { [1] = 1, [2] = 2, [3] = 1 }, -- Balance Wis, Feral Might, Resto Wis
        SHAMAN  = { [1] = 1, [2] = 2, [3] = 1 }, -- Ele Wis, Enh Might, Resto Wis
        HUNTER  = { [1] = 1, [2] = 1, [3] = 2 }, -- BM Wis, MM Wis, Survival Might
        PALADIN = { [1] = 1, [2] = 2, [3] = 2 }, -- Holy Wis, Prot Might, Ret Might
    }

    local function palKnows(n, b)
        local p = pals[n]
        return p and p.ranks and p.ranks[b] and true or false
    end

    -- Local talent-tab preference (no inspect). Role overrides when set.
    local function myNeedBless()
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
        if role == "HEALER" then return 1 end
        if role == "TANK" then return 2 end
        local _, class = UnitClass("player")
        if CASTER[class] then return 1 end
        if PHYSICAL[class] then return 2 end
        local map = TAB_NEED[class]
        if map then
            local tab = mySpec()
            if tab and map[tab] then return map[tab] end
            return 1
        end
        return 1
    end

    -- [canonicalKey] = 1|2 from Fresh Fixes peers (and self). Filled by Auto Q/N.
    local needByKey = {}

    local function reportNeed()
        if not IsInGroup() then return end
        FF.Send("B", "N" .. myNeedBless(), "GROUP")
    end

    -- FFIXES "B": s<0-3> pala talent tab · Q ask preferred Wis/Might · N1|N2 reply
    FF.OnComm("B", function(payload, _, display, key)
        if payload == "Q" then
            if key == FF.UnitKey("player") then return end
            C_Timer.After(math.random() * 0.25, reportNeed)
            return
        end
        local need = payload:match("^N([12])$")
        if need and key then
            needByKey[FF.CanonicalKey(key)] = tonumber(need)
            return
        end
        local sender, su = resolve(display)
        local s = payload:match("^s([0-3])$")
        if sender and s and unitClass(su) == "PALADIN" and pals[sender] then
            pals[sender].spec = tonumber(s)
            changed()
        end
    end)

    -- Preferred Might(2) / Wisdom(1): reported talent need → role → class default.
    local function unitNeedBless(u)
        if not u then return 1 end
        local key = FF.UnitKey(u)
        if key then
            local reported = needByKey[FF.CanonicalKey(key)]
            if reported == 1 or reported == 2 then return reported end
        end
        if u == "player" then return myNeedBless() end

        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        if role == "HEALER" then return 1 end
        if role == "TANK" then return 2 end
        local class = unitClass(u)
        if CASTER[class] then return 1 end
        if PHYSICAL[class] then return 2 end
        if class == "PALADIN" then return 2 end
        -- Hybrid / unknown without a Fresh Fixes reply: Wisdom
        return 1
    end

    local function clearNormalsQuiet(pal)
        local byClass = normal[pal]
        if not byClass then return end
        for c, byName in pairs(byClass) do
            local names = {}
            for tname in pairs(byName) do names[#names + 1] = tname end
            for _, tname in ipairs(names) do setNormal(pal, c, tname, 0, true) end
        end
    end

    -- 3+ paladins: classic one-blessing-per-class.
    local function autoClassic(list)
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
        return plan
    end

    -- 1–2 paladins: Kings + Might/Wisdom by player specs, with individuals for the odd ones out.
    local function autoSmart(list)
        local plan = {}
        for _, n in ipairs(list) do plan[n] = {} end

        -- Pick Kings paladin (Holy preferred, then highest Kings rank).
        local kingsPal, otherPal
        if #list == 1 then
            kingsPal = list[1]
        else
            local best, score
            for _, n in ipairs(list) do
                if palKnows(n, 3) then
                    local p = pals[n]
                    local s = (p.ranks[3] or 0) + ((p.spec or 0) == 1 and 100 or 0) + ((p.spec or 0) == 2 and 40 or 0)
                    if not score or s > score then best, score = n, s end
                end
            end
            kingsPal = best or list[1]
            otherPal = list[1] == kingsPal and list[2] or list[1]
            if not palKnows(otherPal, 1) and not palKnows(otherPal, 2) then
                -- Swap if the "other" can't do Wis/Might but kingsPal can.
                if palKnows(kingsPal, 1) or palKnows(kingsPal, 2) then
                    kingsPal, otherPal = otherPal, kingsPal
                end
            end
        end

        local classesPresent = {}
        for c = 1, MAXC do
            if #classMembers(c) > 0 then classesPresent[#classesPresent + 1] = c end
        end

        for _, c in ipairs(classesPresent) do
            local members = classMembers(c)
            local nMight, nWis = 0, 0
            for _, m in ipairs(members) do
                if unitNeedBless(m.unit) == 2 then nMight = nMight + 1 else nWis = nWis + 1 end
            end
            local majority = nMight >= nWis and 2 or 1 -- Might or Wisdom
            local minority = majority == 2 and 1 or 2

            if kingsPal and palKnows(kingsPal, 3) then
                plan[kingsPal][c] = 3
            elseif kingsPal then
                -- No Kings: fall back to class priority on the sole / kings slot.
                for _, b in ipairs(PRIO[c]) do
                    if palKnows(kingsPal, b) then plan[kingsPal][c] = b; break end
                end
            end

            if otherPal then
                if palKnows(otherPal, majority) then
                    plan[otherPal][c] = majority
                elseif palKnows(otherPal, minority) then
                    plan[otherPal][c] = minority
                    majority, minority = minority, majority
                else
                    for _, b in ipairs(PRIO[c]) do
                        if b ~= 3 and palKnows(otherPal, b) then plan[otherPal][c] = b; break end
                    end
                end
            elseif kingsPal and plan[kingsPal][c] == 3 then
                -- Solo pally on Kings: class stays Kings; individuals cover Might/Wisdom below.
            elseif kingsPal and not plan[kingsPal][c] then
                if palKnows(kingsPal, majority) then plan[kingsPal][c] = majority
                else
                    for _, b in ipairs(PRIO[c]) do
                        if palKnows(kingsPal, b) then plan[kingsPal][c] = b; break end
                    end
                end
            end
        end

        return plan, kingsPal, otherPal
    end

    local function applySmartIndividuals(list, plan, kingsPal, otherPal)
        -- Clear old individuals for pals we can edit, then set new ones.
        for _, n in ipairs(list) do
            if canEdit(n) then clearNormalsQuiet(n) end
        end
        for c = 1, MAXC do
            local members = classMembers(c)
            if #members == 0 then -- skip
            else
                local classBless = {}
                for _, n in ipairs(list) do classBless[n] = plan[n] and plan[n][c] or 0 end

                for _, m in ipairs(members) do
                    local need = unitNeedBless(m.unit) -- 1 Wis or 2 Might
                    if #list == 1 then
                        local pal = list[1]
                        local cb = classBless[pal] or 0
                        -- Solo: Kings (or other) as class; individual for Might/Wisdom when different.
                        if canEdit(pal) and palKnows(pal, need) and need ~= cb then
                            setNormal(pal, c, m.name, need, true)
                        end
                    else
                        -- Duo: Kings from kingsPal, Wis/Might class from otherPal.
                        -- Individual when this player needs the opposite of otherPal's class bless.
                        local secondary = otherPal and classBless[otherPal] or 0
                        local giver = otherPal
                        if giver and canEdit(giver) and need ~= secondary and palKnows(giver, need) then
                            setNormal(giver, c, m.name, need, true)
                        elseif kingsPal and canEdit(kingsPal) and need ~= (classBless[kingsPal] or 0)
                            and need ~= secondary and palKnows(kingsPal, need) then
                            -- Fallback if other can't cover.
                            setNormal(kingsPal, c, m.name, need, true)
                        end
                    end
                end
            end
        end
    end

    local autoBusy = false
    local function finishAuto(list, smart)
        local plan, kingsPal, otherPal
        if smart then
            plan, kingsPal, otherPal = autoSmart(list)
        else
            plan = autoClassic(list)
        end

        local skipped = 0
        for n, a in pairs(plan) do
            if canEdit(n) then
                for c = 1, MAXC do setAssign(n, c, a[c] or 0) end
            else
                skipped = skipped + 1
            end
        end
        if smart then
            applySmartIndividuals(list, plan, kingsPal, otherPal)
        end
        FF.print(skipped > 0
            and ("Assigned; %d paladin(s) skipped (need lead/assist or Free Assignment)"):format(skipped)
            or (smart and "Blessings assigned (smart: class + individuals by talent)" or "Blessings assigned"))
        changed()
        autoBusy = false
    end

    function M.Auto()
        if InCombatLockdown() then FF.print("Not in combat") return end
        if autoBusy then return end
        refreshIdentity()
        scanSelf()
        rosterDirty = true
        local list = activePals()
        if #list == 0 then FF.print("No paladins found") return end

        local smart = #list <= 2
        wipe(needByKey)
        local myKey = FF.UnitKey("player")
        if myKey then needByKey[FF.CanonicalKey(myKey)] = myNeedBless() end

        -- Smart Auto: ask Fresh Fixes peers for talent-tab Wis/Might, then assign.
        if smart and IsInGroup() then
            autoBusy = true
            FF.Send("B", "Q", "GROUP")
            C_Timer.After(0.55, function()
                finishAuto(list, true)
            end)
            return
        end
        finishAuto(list, smart)
    end

    function M.Clear()
        -- Match PallyPower: only non-instance lead/assist can CLEAR the raid.
        if not inInstanceGroup() and isLead("player") then
            for n in pairs(assign) do assign[n] = {} end
            wipe(normal)
            send("CLEAR")
        else
            for c = 1, MAXC do setAssign(me, c, 0) end
        end
        changed()
    end

    ---------------------------------------------------------------------------
    -- Assignment panel: set who buffs which class (not the cast bar)
    ---------------------------------------------------------------------------
    local panel
    local CELL, NAMEW = 20, 130
    -- Wider class columns so nicknames fit under the class icons (PallyPower-style).
    local COLW = 52
    local function salvCol()
        return CELL + 2 -- Forever: Salv is its own column (stacks with blessings)
    end
    local function classColSpan()
        return MAXC * (COLW + 2)
    end
    local function icon(b)
        local _, ic = spellInfo(BASE[b])
        if not ic then
            local id = firstKnown(RANKS[b]) or (RANKS[b] and RANKS[b][1])
            if id then _, ic = spellInfo(id) end
        end
        return ic or ICON[b]
    end
    local function cycle(name, c, dir)
        local p = pals[name]
        if not p then return end
        local opts = { 0 }
        local known
        if p.ranks then
            for b = 1, 7 do if p.ranks[b] then known = true; break end end
        end
        for b = 1, 7 do
            -- Forever: skip Salv (4) and removed Sanctuary (6)
            if b ~= 4 and b ~= 6 and ((known and p.ranks[b]) or (not known and name ~= me)) then
                opts[#opts + 1] = b
            end
        end
        if #opts == 1 then return end
        local cur, idx = (assign[name] or {})[c] or 0, 1
        for i, b in ipairs(opts) do if b == cur then idx = i end end
        idx = (idx - 1 + dir) % #opts + 1
        setAssign(name, c, opts[idx])
        changed()
    end

    local function buildPanel()
        panel = UI.Window("Blessings", "Blessings", NAMEW + salvCol() + classColSpan() + 12, 80, { keepOpen = true })
        panel.rows = {}
        panel.headers = {}
        local y0 = -(UI.TITLE_H + 6)
        -- Salv column: Forever Salv stacks with blessings — per-paladin on/off.
        panel.salvHead = CreateFrame("Frame", nil, panel)
        panel.salvHead:SetSize(CELL, CELL)
        FF.Skin(panel.salvHead, "panel")
        panel.salvHead.tex = iconIn(panel.salvHead, 2)
        FF.SetIcon(panel.salvHead.tex, ICON[4] or "Interface\\Icons\\Spell_Holy_SealOfSalvation")
        panel.salvHead:EnableMouse(true)
        panel.salvHead:SetScript("OnEnter", function(self)
            FF.Tip(self, "Whether this paladin offers Salvation. On Forever it stacks with other blessings. Assign like normal blessings (Free Assignment / lead).", "Salvation")
        end)
        panel.salvHead:SetScript("OnLeave", FF.HideTip)
        for c = 1, MAXC do
            local h = CreateFrame("Frame", nil, panel)
            h:SetSize(COLW, CELL)
            FF.Skin(h, "panel")
            local tex = iconIn(h, 2)
            tex:ClearAllPoints()
            tex:SetSize(CELL - 2, CELL - 2)
            tex:SetPoint("CENTER")
            FF.SetIcon(tex, "Interface\\Icons\\ClassIcon_" .. CLASS[c]:sub(1, 1) .. CLASS[c]:sub(2):lower())
            panel.headers[c] = h
        end
        panel.auto = UI.Button(panel, "Auto", 50, 18, M.Auto, "Smart assign: with 1–2 paladins uses Kings + Might/Wisdom by player specs (class + individuals). With 3+ uses classic per-class assign.")
        panel.clear = UI.Button(panel, "Clear", 50, 18, M.Clear, "Leader: clear everyone's. Otherwise: clear yours")
        panel.status = FF.Text(panel, "small")
        panel.status:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        panel:SetScript("OnHide", function() db.panel = false end)
        panel._y0 = y0
    end

    local function row(i)
        local r = panel.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, panel)
        r:SetSize(NAMEW + salvCol() + classColSpan(), CELL)
        r.strip = CreateFrame("Frame", nil, r)
        r.strip:SetPoint("TOPLEFT")
        r.strip:SetSize(NAMEW - 2, CELL)
        r.strip:SetClipsChildren(true)
        FF.Skin(r.strip, "card", C.cardBd)
        r.name = FF.Text(r.strip, "small")
        r.name:SetPoint("LEFT", 4, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        if r.name.SetNonSpaceWrap then r.name:SetNonSpaceWrap(false) end
        r.salv = CreateFrame("Button", nil, r)
        r.salv:SetSize(CELL, CELL)
        FF.Skin(r.salv, "row")
        r.salv.tex = iconIn(r.salv, 2)
        FF.SetIcon(r.salv.tex, ICON[4] or "Interface\\Icons\\Spell_Holy_SealOfSalvation")
        r.salv:RegisterForClicks("LeftButtonUp")
        r.salv:SetScript("OnClick", function()
            if InCombatLockdown() or not canEdit(r.pal) then return end
            local on = r.pal == me and db.salv or (pals[r.pal] and pals[r.pal].salv)
            setSalv(r.pal, not on)
        end)
        r.salv:SetScript("OnEnter", function(self)
            hoverOn(self)
            local on = r.pal == me and db.salv or (pals[r.pal] and pals[r.pal].salv)
            FF.Tip(self, (on and "Offering Salvation" or "Not offering Salvation") ..
                (canEdit(r.pal) and "\nClick to toggle (Forever: stacks with blessings)"
                    or "\nLocked (needs lead/assist or their Free Assignment)"),
                "Salvation")
        end)
        r.salv:SetScript("OnLeave", function(self) hoverOff(self); FF.HideTip() end)
        r.cells = {}
        for c = 1, MAXC do
            local b = CreateFrame("Button", nil, r)
            b:SetSize(CELL, CELL)
            FF.Skin(b, "row")
            b.tex = iconIn(b, 2)
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
            b:EnableMouseWheel(true)
            b:SetScript("OnMouseWheel", function(_, delta)
                if InCombatLockdown() or not canEdit(r.pal) then return end
                cycle(r.pal, c, delta > 0 and -1 or 1)
            end)
            b:SetScript("OnEnter", function(self)
                hoverOn(self)
                local v = (assign[r.pal] or {})[c] or 0
                local tipName = v > 0 and (spellInfo(BASE[v]) or listSpell(RANKS[v]) or SHORT[v]) or "None"
                FF.Tip(self, tipName ..
                    (canEdit(r.pal) and "\nClick / scroll to change, Shift-click to clear"
                        or "\nLocked (needs lead/assist or their Free Assignment)"),
                    FF.ClassColor(CLASS[c], CLASS[c]:sub(1, 1) .. CLASS[c]:sub(2):lower()))
            end)
            b:SetScript("OnLeave", function(self)
                hoverOff(self)
                FF.HideTip()
            end)
            r.cells[c] = b
        end
        panel.rows[i] = r
        return r
    end

    local MAXPERCLASS = 15

    -- PallyPower-style: pick which paladin gives which small blessing to this player.
    local function openNormalMenu(owner, tname, class)
        local list = activePals()
        local palOpts = {}
        for _, pal in ipairs(list) do
            if canEdit(pal) then
                local mark = getNormal(pal, class, tname)
                local label = shortName(pal) .. (mark > 0 and (" · " .. (SHORT[mark] or "?")) or "")
                palOpts[#palOpts + 1] = { pal, label }
            end
        end
        if #palOpts == 0 then return end
        UI.OpenMenu(owner, palOpts, function(pal)
            local bopts = { { 0, "(none)" } }
            local p = pals[pal]
            local known
            if p and p.ranks then
                for b = 1, 7 do if p.ranks[b] then known = true; break end end
            end
            for b = 1, 7 do
                if b ~= 4 and b ~= 6 and not (b == 7 and tname == pal) then
                    local ok = (known and p.ranks[b]) or (not known and pal ~= me) or (pal == me and knownRank(b))
                    if ok then
                        local n = spellInfo(BASE[b]) or listSpell(RANKS[b]) or SHORT[b] or tostring(b)
                        bopts[#bopts + 1] = { b, n }
                    end
                end
            end
            UI.OpenMenu(owner, bopts, function(bless)
                setNormal(pal, class, tname, bless)
                refreshPanel()
            end)
        end)
    end

    local function clearAllNormals(tname, class)
        local list = activePals()
        for _, pal in ipairs(list) do
            if canEdit(pal) and getNormal(pal, class, tname) > 0 then
                setNormal(pal, class, tname, 0)
            end
        end
        -- Also clear any we can see even if not editable display — only send for editable.
        refreshPanel()
    end

    -- Icon only when *you* are assigned to buff them (not other paladins' individual assigns).
    local function myNormalIcon(tname, class)
        if not me then return end
        local v = getNormal(me, class, tname)
        if v > 0 then return icon(v) end
    end

    local function blessLabel(v)
        return spellInfo(BASE[v]) or listSpell(RANKS[v]) or SHORT[v] or "?"
    end

    local function playerBtn(c, i)
        panel.pCols = panel.pCols or {}
        panel.pCols[c] = panel.pCols[c] or {}
        local b = panel.pCols[c][i]
        if b then return b end
        b = CreateFrame("Button", nil, panel)
        b:SetSize(COLW, CELL)
        FF.Skin(b, "row")
        b.tex = iconIn(b, 1)
        b.tex:ClearAllPoints()
        b.tex:SetPoint("LEFT", 1, 0)
        b.tex:SetSize(CELL - 4, CELL - 4)
        b.nameClip, b.label = clipLabel(b, "small")
        b.nameClip:SetPoint("LEFT", 2, 0)
        b.nameClip:SetPoint("RIGHT", -1, 0)
        b.nameClip:SetHeight(CELL)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, btn)
            if InCombatLockdown() or not b.tname or not b.class then return end
            if btn == "RightButton" then
                clearAllNormals(b.tname, b.class)
            else
                openNormalMenu(b, b.tname, b.class)
            end
        end)
        b:SetScript("OnEnter", function(self)
            hoverOn(self)
            local lines = {}
            local function addLine(text, blessId)
                lines[#lines + 1] = { text = text, icon = blessId and blessId > 0 and icon(blessId) or nil }
            end
            local any
            -- One line per paladin: individual overrides class for that paladin.
            for _, pal in ipairs(activePals()) do
                local nId = getNormal(pal, b.class, b.tname)
                local gId = (assign[pal] or {})[b.class] or 0
                local effective = nId > 0 and nId or gId
                if effective > 0 then
                    any = true
                    local who = (pal == me) and "You" or dispName(pal, getRoster()[pal])
                    if nId > 0 then
                        addLine(who .. (pal == me and " are" or " is") .. " buffing them: " .. blessLabel(nId), nId)
                    else
                        addLine(who .. (pal == me and " are" or " is") .. " buffing their class: " .. blessLabel(gId), gId)
                    end
                end
            end
            if not any then addLine("No blessings assigned") end
            addLine("Left-click: assign · Right-click: clear")
            FF.TipRich(self, dispName(b.tname, b.unit), lines)
        end)
        b:SetScript("OnLeave", function(self) hoverOff(self); FF.HideTip() end)
        panel.pCols[c][i] = b
        return b
    end

    refreshPanel = function()
        if not panel or not panel:IsShown() then return end
        local list, units = activePals()
        local sc = salvCol()
        local side = sc
        local y0 = -(UI.TITLE_H + 6)
        panel.salvHead:ClearAllPoints()
        panel.salvHead:SetPoint("TOPLEFT", 6 + NAMEW, y0 + 2)
        for c = 1, MAXC do
            panel.headers[c]:ClearAllPoints()
            panel.headers[c]:SetPoint("TOPLEFT", 6 + NAMEW + side + (c - 1) * (COLW + 2), y0 + 2)
        end

        -- Players under each class icon (PallyPower-style individual assigns).
        local membersByClass, maxPlayers = {}, 0
        for c = 1, MAXC do
            membersByClass[c] = classMembers(c)
            if #membersByClass[c] > maxPlayers then maxPlayers = #membersByClass[c] end
        end
        local playerY = y0 - CELL - 2
        for c = 1, MAXC do
            local members = membersByClass[c]
            for i = 1, MAXPERCLASS do
                local b = playerBtn(c, i)
                if members[i] then
                    local m = members[i]
                    b.class, b.tname, b.unit = c, m.name, m.unit
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 6 + NAMEW + side + (c - 1) * (COLW + 2), playerY - (i - 1) * (CELL + 2))
                    b:SetSize(COLW, CELL)
                    b.label:SetText(dispName(m.name, m.unit))
                    -- Only the paladin assigned to buff them sees the icon on their client.
                    local ic = myNormalIcon(m.name, c)
                    b.nameClip:ClearAllPoints()
                    if ic then
                        b.tex:SetTexture(ic)
                        b.tex:Show()
                        b.nameClip:SetPoint("LEFT", b.tex, "RIGHT", 2, 0)
                    else
                        b.tex:Hide()
                        b.nameClip:SetPoint("LEFT", 2, 0)
                    end
                    b.nameClip:SetPoint("RIGHT", -1, 0)
                    b.nameClip:SetHeight(CELL)
                    b:Show()
                else
                    b:Hide()
                    b.tname, b.class, b.unit = nil, nil, nil
                end
            end
        end
        if panel.indivLabel then panel.indivLabel:Hide() end

        local playerBlock = maxPlayers > 0 and (maxPlayers * (CELL + 2)) or 0
        local y = playerY - playerBlock - 4
        for i, name in ipairs(list) do
            local r = row(i)
            r.pal = name
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 6, y - (i - 1) * (CELL + 2))
            r:SetWidth(NAMEW + side + classColSpan())
            local p = pals[name] or {}
            local tag = p.spec == 1 and " H" or p.spec == 2 and " P" or p.spec == 3 and " R" or ""
            local u = units and units[name] or (getRoster()[name])
            r.name:SetText(palLabel(name, u) .. FF.Hex(C.muted) .. tag .. (p.free and " *" or "") .. "|r")
            r.salv:ClearAllPoints()
            r.salv:SetPoint("LEFT", NAMEW, 0)
            local salvOn = name == me and db.salv or p.salv
            if salvOn then r.salv.tex:Show() else r.salv.tex:Hide() end
            r.salv:SetAlpha(canEdit(name) and 1 or 0.6)
            for c = 1, MAXC do
                local v = (assign[name] or {})[c] or 0
                local cell = r.cells[c]
                cell:ClearAllPoints()
                -- Center blessing icon in the expanded class column.
                cell:SetPoint("LEFT", NAMEW + side + (c - 1) * (COLW + 2) + math.floor((COLW - CELL) / 2), 0)
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
        panel.auto:ClearAllPoints()
        panel.auto:SetPoint("TOPLEFT", 6, by)
        panel.clear:SetPoint("LEFT", panel.auto, "RIGHT", 4, 0)
        panel.status:SetPoint("LEFT", panel.clear, "RIGHT", 6, 0)
        panel.status:SetText(#list == 0 and "no paladins" or (#list .. " paladin" .. (#list == 1 and "" or "s")))
        panel:SetWidth(NAMEW + side + classColSpan() + 12)
        panel:SetHeight(-by + 26)
    end

    function M.TogglePanel(on)
        if on == nil then on = not (panel and panel:IsShown()) end
        db.panel = on and true or false
        if on then
            if not panel then buildPanel() end
            panel:Show()
            if IsInGroup() then
                sendSelf()
                send("REQ")
            end
            refreshPanel()
        elseif panel then
            panel:Hide()
        end
    end

    ---------------------------------------------------------------------------
    -- Buff helper: your assigned classes only (click to cast). No paladin list.
    ---------------------------------------------------------------------------
    local helper, hCells, sCells = nil, {}, {}
    local HCELL_W, HCELL_H = 78, 24
    local formatRem, paintActive, paintExpandButton, hidePlayerExpand, showPlayerExpand

    local blessNameCache = {}
    local function blessNames(b)
        local cached = blessNameCache[b]
        if cached then return cached end
        local t = {}
        local function add(id)
            local n = spellInfo(id)
        if n then t[n] = true end
        end
        for _, id in ipairs(RANKS[b] or {}) do add(id) end
        for _, id in ipairs(GREATER[b] or {}) do add(id) end
        if BASE[b] then add(BASE[b]) end
        blessNameCache[b] = t
        return t
    end
    local function auraRem(unit, names)
        if not (unit and names and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
        local best
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not a then break end
            local n = a.name
            if not readable(n) then return true end
            if names[n] then
                local rem = a.expirationTime and a.expirationTime > 0 and (a.expirationTime - GetTime()) or 0
                if type(rem) == "number" and (not best or rem < best) then best = rem end
            end
        end
        return best
    end
    local function isTank(u)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        return role == "TANK" or (GetPartyAssignment and GetPartyAssignment("MAINTANK", u)) or false
    end
    local function greaterKnown(b)
        local id = firstKnown(GREATER[b])
        return id and spellInfo(id) or nil
    end
    local function spellFor(b)
        if db.greater then
            local g = greaterKnown(b)
            if g then return g end
        end
        local id = firstKnown(RANKS[b])
        if id then return spellInfo(id) end
        return spellInfo(BASE[b])
    end
    local function classIconPath(c)
        local cls = CLASS[c]
        if not cls then return ICON[4] end
        return "Interface\\Icons\\ClassIcon_" .. cls:sub(1, 1) .. cls:sub(2):lower()
    end

    -- Salv / fixed-blessing scan (no individual overrides).
    -- Returns missUnit, minRem (among buffed), any, refreshUnit, state
    -- state: "need" = all missing (red), "partial" = some missing (orange), "ok" = all buffed (green)
    local function classNeed(c, b)
        local names = blessNames(b)
        local missUnit, minRem, any, refreshUnit
        local nMiss, nOk = 0, 0
        for _, u in pairs(getRoster()) do
            if CLASSID[unitClass(u) or ""] == c and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
                if b == 4 and isTank(u) then
                    -- Salvation never on tanks
                else
                    any = true
                    local rem = auraRem(u, names)
                    if rem == nil then
                        nMiss = nMiss + 1
                        if not missUnit then missUnit = u end
                    else
                        nOk = nOk + 1
                        if rem ~= true and (not minRem or rem < minRem) then
                            minRem = rem
                            refreshUnit = u
                        end
                    end
                end
            end
        end
        local state = "idle"
        if any then
            if nMiss > 0 and nOk == 0 then
                state = "need"
            elseif nMiss > 0 then
                state = "partial"
            else
                state = "ok"
            end
        end
        return missUnit, minRem, any, refreshUnit, state
    end

    -- Class helper row: each member is checked against their effective blessing
    -- (individual small override, else the class assign). Row goes green when
    -- everyone has the right buff — even if individuals differ from the class assign.
    local function classNeedEffective(c, classBless)
        local minRem, any
        local nMiss, nOk = 0, 0
        for _, m in ipairs(classMembers(c)) do
            local u = m.unit
            if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
                local nId = getNormal(me, c, m.name)
                local b = (nId > 0 and nId) or (classBless or 0)
                if b > 0 then
                    any = true
                    local rem = auraRem(u, blessNames(b))
                    if rem == nil then
                        nMiss = nMiss + 1
                    else
                        nOk = nOk + 1
                        if rem ~= true and (not minRem or rem < minRem) then
                            minRem = rem
                    end
                end
            end
        end
        end
        local state = "idle"
        if any then
            if nMiss > 0 and nOk == 0 then
                state = "need"
            elseif nMiss > 0 then
                state = "partial"
            else
                state = "ok"
            end
        end
        return nil, minRem, any, nil, state
    end

    local function classInGroup(c)
        for _, u in pairs(getRoster()) do
            if CLASSID[unitClass(u) or ""] == c then return true end
        end
        return false
    end

    local function classHasSalvTarget(c)
        for _, u in pairs(getRoster()) do
            if CLASSID[unitClass(u) or ""] == c and UnitIsConnected(u) and not isTank(u) then
                return true
            end
        end
        return false
    end

    -- Salv strip on the helper. Icon, colour-icon, or timer shows it.
    local function showSalvColumn()
        return db.salv and knows(1038) and (db.salvIcon or db.salvTimer or db.salvColorIcon) and true or false
    end

    -- Resolved Salv placement for the current layout.
    local function salvSide(vertical)
        local p = db.salvPos
        if vertical then
            if p == "left" then return "left" end
            return "right" -- default / auto / above / below → right
        end
        if p == "above" then return "above" end
        return "below" -- default / auto / left / right → below
    end

    -- Class blessing rows (+ classes with individual normals / salv-only).
    local function helperRows()
        refreshIdentity()
        if not (isPally and me) then return {} end
        scanSelf()
        rosterDirty = true
        local a, rows, seen = assign[me] or {}, {}, {}
        for c = 1, MAXC do
            local b = a[c] or 0
            local hasNormal
            if normal[me] and normal[me][c] then
                for _, v in pairs(normal[me][c]) do if v and v > 0 then hasNormal = true; break end end
            end
            if ((b > 0 and b ~= 4 and b ~= 6 and knownRank(b)) or hasNormal) and classInGroup(c) then
                rows[#rows + 1] = { c = c, b = (b > 0 and b ~= 4 and b ~= 6) and b or 0 }
                seen[c] = true
            end
        end
        if showSalvColumn() then
            for c = 1, MAXC do
                if not seen[c] and classHasSalvTarget(c) then
                    rows[#rows + 1] = { c = c, b = 0 }
                end
            end
            table.sort(rows, function(x, y) return x.c < y.c end)
        end
        return rows
    end

    local function clearSecure(b)
        b:SetAttribute("type", nil)
        b:SetAttribute("type2", nil)
        b:SetAttribute("spell", nil)
        b:SetAttribute("spell2", nil)
        b:SetAttribute("unit", nil)
        b:SetAttribute("unit2", nil)
    end

    -- Auto: always rebuff the oldest blessing or Salv.
    -- Left: try Greater (fallback Normal if no Symbol of Kings). Right: always Greater when known.
    local AUTO_REFRESH = 240 -- refresh when under 4 minutes (PP normal threshold)
    local SYMBOL_KINGS = 21177
    local autoBuffedAt = {}

    local function inSpellRange(spellName, unit)
        if not (spellName and unit) then return false end
        if IsSpellInRange then
            local ok, r = pcall(IsSpellInRange, spellName, unit)
            if ok then return r == 1 or r == true end
        end
        return true
    end

    local function normalSpell(b)
        local id = firstKnown(RANKS[b])
        return (id and spellInfo(id)) or spellInfo(BASE[b])
    end

    local function hasGreaterReagent()
        local n = GetItemCount and GetItemCount(SYMBOL_KINGS)
        return type(n) == "number" and n > 0
    end

    local function autoSpellFor(b, mousebutton)
        local nSpell = normalSpell(b)
        local gSpell = greaterKnown(b)
        if mousebutton == "RightButton" then
            return gSpell or nSpell -- always Greater when known
        end
        if gSpell and hasGreaterReagent() then return gSpell end
        return nSpell
    end

    -- Next cast from a class cell: class-assign targets first, then individual overrides.
    -- Left: Greater when reagent allows (same as Auto). Right: Greater when known.
    -- Individuals always use the small blessing.
    local function classPickCast(c, classBless, mousebutton)
        if not (c and c > 0) then return end
        local classMiss, classRefresh, classRefreshRem
        local indivMiss, indivRefresh, indivRefreshRem
        for _, m in ipairs(classMembers(c)) do
            local u = m.unit
            if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
                local nId = getNormal(me, c, m.name)
                if nId > 0 then
                    local spell = normalSpell(nId)
                    if spell and inSpellRange(spell, u) then
                        local rem = auraRem(u, blessNames(nId))
                        if rem == nil then
                            if not indivMiss then indivMiss = { unit = u, spell = spell } end
                        elseif type(rem) == "number" and (not indivRefreshRem or rem < indivRefreshRem) then
                            indivRefreshRem = rem
                            indivRefresh = { unit = u, spell = spell }
                        end
                    end
                elseif classBless and classBless > 0 and classBless ~= 4 and classBless ~= 6 then
                    local spell = autoSpellFor(classBless, mousebutton)
                    if spell and inSpellRange(spell, u) then
                        local rem = auraRem(u, blessNames(classBless))
                        if rem == nil then
                            if not classMiss then classMiss = { unit = u, spell = spell } end
                        elseif type(rem) == "number" and (not classRefreshRem or rem < classRefreshRem) then
                            classRefreshRem = rem
                            classRefresh = { unit = u, spell = spell }
                        end
                    end
                end
            end
        end
        local pick = classMiss or indivMiss or classRefresh or indivRefresh
        if pick then return pick.unit, pick.spell end
    end

    local function remScore(rem)
        if rem == nil then return -1 end -- missing = oldest / most urgent
        if type(rem) ~= "number" then return math.huge end
        return rem
    end

    -- Oldest needed buff across class greaters, individual smalls, and Salv.
    local function autoCandidates(mousebutton)
        local out = {}
        local function consider(u, b, forceNormal)
            if not (u and b and b > 0) then return end
            if not (UnitIsConnected(u) and not UnitIsDeadOrGhost(u)) then return end
            local spell = forceNormal and normalSpell(b) or autoSpellFor(b, mousebutton)
            if not spell or not inSpellRange(spell, u) then return end
            local rem = auraRem(u, blessNames(b))
            out[#out + 1] = {
                unit = u, spell = spell, b = b,
                rem = rem, score = remScore(rem),
                needs = rem == nil or (type(rem) == "number" and rem < AUTO_REFRESH),
            }
        end
        refreshIdentity()
        if not (isPally and me) then return out end
        local a = assign[me] or {}
        -- Class assigns: skip anyone with an individual override (they use the small below).
        for c = 1, MAXC do
            local g = a[c] or 0
            if g > 0 and g ~= 4 and g ~= 6 then
                for _, m in ipairs(classMembers(c)) do
                    if getNormal(me, c, m.name) == 0 then
                        consider(m.unit, g, false)
                    end
                end
            end
        end
        for c, t in pairs(normal[me] or {}) do
            for tname, b in pairs(t) do
                if type(b) == "number" and b > 0 then
                    local u = getRoster()[tname]
                    consider(u, b, true) -- individual exceptions are always small
                end
            end
        end
        if db.salv and knows(1038) then
            for _, u in pairs(getRoster()) do
                if not isTank(u) then consider(u, 4, false) end
            end
        end
        return out
    end

    local function pickAutoBuff(mousebutton)
        local pool = autoCandidates(mousebutton)
        if #pool == 0 then return end
        local now = GetTime()
        local best
        for _, e in ipairs(pool) do
            local recent = autoBuffedAt[e.unit] and (now - autoBuffedAt[e.unit] < 1.2)
            if not recent then
                if not best or e.score < best.score then best = e end
            end
        end
        best = best or pool[1]
        if not best then return end
        autoBuffedAt[best.unit] = now
        return best.unit, best.spell
    end

    -- Button colour: red while anyone is missing their assign; green when all are up
    -- (refresh-under-4m still drives cast order, but does not keep Auto red).
    local function countAutoNeed()
        local n = 0
        for _, e in ipairs(autoCandidates("LeftButton")) do
            if e.rem == nil then n = n + 1 end
        end
        return n
    end

    local function titleH()
        return db.showTitle and UI.TITLE_H or 0
    end

    local function helperIsLocked()
        return db.helperLocked ~= false
    end

    local function applyAssignLockColor()
        local ab = helper and helper.assignBtn
        if not ab then return end
        local c = helperIsLocked() and C.bad or C.good -- red locked, green unlocked
        if ab.cog then ab.cog:SetVertexColor(c[1], c[2], c[3], 1) end
        if ab.dot then ab.dot:SetColorTexture(c[1], c[2], c[3], 1) end
        if ab.label then ab.label:SetTextColor(c[1], c[2], c[3]) end
    end

    local function applyHelperLock()
        if not helper then return end
        local locked = helperIsLocked()
        helper.unlocked = not locked
        -- Drag via empty frame area only when unlocked and frameless.
        -- Do not call UI.Display SetUnlocked — it paints a border over frameless chrome.
        helper:EnableMouse(not locked and not db.showTitle)
        applyAssignLockColor()
    end

    local function applyHelperChrome()
        if not helper then return end
        local titled = db.showTitle and true or false
        helper.bar:SetShown(titled)
        if titled then
            FF.SetBg(helper, C.bg)
            FF.SetBorder(helper, C.border)
        else
            FF.SetBg(helper, { 0, 0, 0, 0 })
            FF.SetBorder(helper, { 0, 0, 0, 0 })
        end
        applyHelperLock()
    end

    -- Immediate drag (OnMouseDown) avoids the RegisterForDrag threshold that jumps
    -- the frame away from the cursor — the old PallyPower lag.
    local dragOriginX, dragOriginY
    local function helperStopDrag()
        if not helper or not helper._ffDragging then return end
        helper._ffDragging = false
        helper:StopMovingOrSizing()
        FF.SavePosition(helper, "BlessingsHelper")
        local x, y = GetCursorPosition()
        helper._ffDragged = dragOriginX and (math.abs(x - dragOriginX) > 3 or math.abs(y - dragOriginY) > 3)
        dragOriginX, dragOriginY = nil, nil
    end
    local function bindHelperDrag(frame, opts)
        opts = opts or {}
        frame:RegisterForDrag() -- clear any inherited drag scripts
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            if helperIsLocked() or InCombatLockdown() then return end
            if opts.shift and not IsShiftKeyDown() then return end
            dragOriginX, dragOriginY = GetCursorPosition()
            helper._ffDragging = true
            helper._ffDragged = false
            helper:StartMoving()
        end)
        frame:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then helperStopDrag() end
        end)
    end

    local function buildHelper()
        -- Frameless display: title bar optional (off by default).
        helper = UI.Display("BlessingsHelper", HCELL_W, HCELL_H, { "CENTER" })
        helper:SetFrameStrata("MEDIUM")
        helper:SetToplevel(true)
        -- Replace Display's lagged RegisterForDrag with immediate mouse drag.
        bindHelperDrag(helper)
        helper.bar = CreateFrame("Frame", nil, helper)
        helper.bar:SetPoint("TOPLEFT", 1, -1)
        helper.bar:SetPoint("TOPRIGHT", -1, -1)
        helper.bar:SetHeight(UI.TITLE_H)
        FF.Skin(helper.bar, "panel", false)
        helper.bar:EnableMouse(true)
        bindHelperDrag(helper.bar)
        helper.title = FF.Text(helper.bar, "small")
        helper.title:SetPoint("LEFT", 5, 0)
        helper.title:SetText("Buffs")
        helper.close = UI.CloseButton(helper.bar, function()
            if InCombatLockdown() then return end
            db.helper = false
            helper:Hide()
        end)
        helper.close:SetSize(UI.TITLE_H, UI.TITLE_H)
        helper.close:SetPoint("RIGHT", 0, 0)
        helper.empty = FF.Text(helper, "small")
        helper.empty:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        -- Auto Buff (PallyPower-style): PreClick wires the next unit/spell, then secure cast.
        local auto = CreateFrame("Button", "FreshFixesBlessAuto", helper, "SecureActionButtonTemplate")
        auto:SetSize(HCELL_W, HCELL_H)
        auto:RegisterForClicks("AnyUp", "AnyDown")
        FF.Skin(auto, "row")
        auto.label = FF.Text(auto, "small")
        auto.label:SetPoint("CENTER")
        auto.label:SetJustifyH("CENTER")
        auto.label:SetText("Auto")
        auto:SetScript("PreClick", function(self, button)
            local unit, spell = pickAutoBuff(button)
            if unit and spell then
                self:SetAttribute("type", "spell")
                self:SetAttribute("spell", spell)
                self:SetAttribute("unit", unit)
            else
                clearSecure(self)
            end
        end)
        auto:SetScript("PostClick", function(self)
            if not InCombatLockdown() then clearSecure(self) end
            refreshHelper()
        end)
        auto:SetScript("OnEnter", function(self)
            FF.Tip(self,
                "Rebuff the oldest blessing or Salvation.\nLeft-click: Greater when you have Symbol of Kings, otherwise Normal.\nRight-click: always Greater when known.",
                "Auto Buff")
        end)
        auto:SetScript("OnLeave", FF.HideTip)
        bindHelperDrag(auto)
        helper.autoBtn = auto
        -- Assignments control (cog): left = toggle panel, right = lock/unlock (green/red).
        local ab = CreateFrame("Button", nil, helper)
        ab:SetSize(HCELL_W, HCELL_H)
        ab:EnableMouse(true)
        ab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        FF.Skin(ab, "row")
        ab.cog = ab:CreateTexture(nil, "ARTWORK")
        ab.cog:SetSize(16, 16)
        ab.cog:SetPoint("CENTER")
        ab.cog:SetTexture("Interface\\Buttons\\UI-OptionsButton")
        ab:SetScript("OnClick", function(_, btn)
            if InCombatLockdown() then return end
            if btn == "RightButton" then
                db.helperLocked = not helperIsLocked()
                applyHelperLock()
                if helper.assignBtn and GameTooltip and GameTooltip:IsOwned(helper.assignBtn) then
                    helper.assignBtn:GetScript("OnEnter")(helper.assignBtn)
                end
            else
                -- Ignore left-click if this press was a drag.
                if helper._ffDragged then helper._ffDragged = false; return end
                M.TogglePanel()
            end
        end)
        ab:SetScript("OnEnter", function(self)
            local lockTip = helperIsLocked()
                and "Right-click to unlock (green) and drag the helper"
                or "Right-click to lock (red)"
            FF.Tip(self, "Left-click: toggle blessing assignments\n" .. lockTip, "Assignments")
        end)
        ab:SetScript("OnLeave", FF.HideTip)
        bindHelperDrag(ab)
        helper.assignBtn = ab
        for i = 1, MAXC * 2 do
            local b = CreateFrame("Button", "FreshFixesBlessCell" .. i, helper, "SecureActionButtonTemplate")
            b:SetSize(HCELL_W, HCELL_H)
            b:RegisterForClicks("AnyUp", "AnyDown")
            FF.Skin(b, "row")
            b.classTex = iconIn(b, 1)
            b.classTex:ClearAllPoints()
            b.classTex:SetPoint("LEFT", 1, 0)
            b.classTex:SetSize(HCELL_H - 4, HCELL_H - 4)
            b.blessTex = iconIn(b, 1)
            b.blessTex:ClearAllPoints()
            b.blessTex:SetPoint("LEFT", b.classTex, "RIGHT", 1, 0)
            b.blessTex:SetSize(HCELL_H - 4, HCELL_H - 4)
            b.timer = FF.Text(b, "small")
            b.timer:SetPoint("LEFT", b.blessTex, "RIGHT", 2, 0)
            b.timer:SetPoint("RIGHT", -1, 0)
            b.timer:SetJustifyH("CENTER")
            -- Class first, then individual assigns (wired fresh each click).
            b:SetScript("PreClick", function(self, button)
                local unit, spell = classPickCast(self.classId, self.classBless or 0, button)
                if unit and spell then
                    self:SetAttribute("type", "spell")
                    self:SetAttribute("spell", spell)
                    self:SetAttribute("unit", unit)
                    self:SetAttribute("type2", nil)
                    self:SetAttribute("spell2", nil)
                    self:SetAttribute("unit2", nil)
                else
                    clearSecure(self)
                end
            end)
            b:SetScript("PostClick", function(self)
                if not InCombatLockdown() then clearSecure(self) end
                refreshHelper()
            end)
            -- Shift-drag cells so a normal click still casts.
            bindHelperDrag(b, { shift = true })
            b:Hide()
            hCells[i] = b
            -- Salv column cell (no class icon — sits left of the class row).
            local s = CreateFrame("Button", "FreshFixesBlessSalv" .. i, helper, "SecureActionButtonTemplate")
            s:SetSize(HCELL_H, HCELL_H)
            s:RegisterForClicks("AnyUp", "AnyDown")
            FF.Skin(s, "row")
            s.blessTex = iconIn(s, 1)
            s.blessTex:ClearAllPoints()
            s.blessTex:SetPoint("CENTER")
            s.blessTex:SetSize(HCELL_H - 4, HCELL_H - 4)
            FF.SetIcon(s.blessTex, ICON[4] or "Interface\\Icons\\Spell_Holy_SealOfSalvation")
            -- Coloured wash over the Salv icon (green = buffed, red = missing).
            s.colorOverlay = s:CreateTexture(nil, "OVERLAY", nil, 7)
            s.colorOverlay:SetAllPoints(s.blessTex)
            s.colorOverlay:SetColorTexture(1, 1, 1, 0.45)
            s.colorOverlay:Hide()
            s.timer = FF.Text(s, "small")
            s.timer:SetJustifyH("CENTER")
            bindHelperDrag(s, { shift = true })
            s:Hide()
            sCells[i] = s
        end

        -- Player expand strip (PallyPower-style): pops out left of a class row on hover.
        helper.expand = CreateFrame("Frame", nil, helper)
        helper.expand:SetFrameStrata("DIALOG")
        helper.expand:SetSize(1, 1)
        helper.expand:Hide()
        helper.expand.buttons = {}
        helper.expand.class = nil
        helper.expand.anchor = nil
        for i = 1, MAXPERCLASS do
            local pb = CreateFrame("Button", "FreshFixesBlessPlayer" .. i, helper.expand, "SecureActionButtonTemplate")
            pb:SetSize(72, HCELL_H)
            pb:RegisterForClicks("AnyUp", "AnyDown")
            pb:EnableMouseWheel(true)
            FF.Skin(pb, "row")
            pb.nameClip, pb.name = clipLabel(pb, "small")
            pb.blessTex = iconIn(pb, 1)
            pb.blessTex:ClearAllPoints()
            pb.blessTex:SetPoint("RIGHT", -2, 0)
            pb.blessTex:SetSize(HCELL_H - 4, HCELL_H - 4)
            pb.timer = FF.Text(pb, "small")
            pb.timer:SetJustifyH("RIGHT")
            pb.timer:SetWidth(36)
            -- Scroll cycles quietly; paintExpandButton updates this row without a full rebuild.
            pb:SetScript("OnMouseWheel", function(_, delta)
                if InCombatLockdown() or not pb.tname or not pb.class then return end
                if not canEdit(me) then return end
                cycleNormal(me, pb.class, pb.tname, delta > 0 and -1 or 1, true)
                if paintExpandButton then paintExpandButton(pb) end
                refreshHelper() -- debounced: class-row colours only
            end)
            pb:SetScript("OnEnter", function(self)
                helper.expand._hover = true
                local nId = getNormal(me, pb.class, pb.tname)
                local gId = (assign[me] or {})[pb.class] or 0
                local tip = dispName(pb.tname, pb.unit)
                if nId > 0 then
                    tip = tip .. "\nSmall: " .. (spellInfo(BASE[nId]) or SHORT[nId] or "?")
                end
                if gId > 0 then
                    tip = tip .. "\nClass: " .. (spellInfo(BASE[gId]) or SHORT[gId] or "?")
                end
                tip = tip .. "\nLeft-click: cast · Scroll: cycle small blessing · Shift-right: clear small"
                FF.Tip(self, tip, "Player")
            end)
            pb:SetScript("OnLeave", function()
                helper.expand._hover = false
                FF.HideTip()
                C_Timer.After(0.15, function()
                    if helper and helper.expand and not helper.expand._hover and not helper.expand._anchorHover then
                        hidePlayerExpand()
                    end
                end)
            end)
            pb:SetScript("PreClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() and pb.tname and pb.class then
                    if not InCombatLockdown() then
                        setNormal(me, pb.class, pb.tname, 0)
                        clearSecure(self)
                    end
                    return
                end
                local nId, gId = blessingFor(me, pb.class, pb.tname)
                local u = pb.unit
                if not u or (nId == 0 and gId == 0) then clearSecure(self); return end
                local nSpell = nId > 0 and normalSpell(nId) or nil
                local gSpell = gId > 0 and greaterKnown(gId) or nil
                if button == "RightButton" then
                    if nSpell then
                        self:SetAttribute("type", "spell")
                        self:SetAttribute("spell", nSpell)
                        self:SetAttribute("unit", u)
                    else
                        clearSecure(self)
                    end
                else
                    local spell = (gSpell and hasGreaterReagent() and gSpell) or nSpell or gSpell
                    if spell then
                        self:SetAttribute("type", "spell")
                        self:SetAttribute("spell", spell)
                        self:SetAttribute("unit", u)
                    else
                        clearSecure(self)
                    end
                end
            end)
            pb:Hide()
            helper.expand.buttons[i] = pb
        end
        applyHelperChrome()
    end

    formatRem = function(sec)
        if type(sec) ~= "number" or sec < 0 then return "" end
        local fmt = db.timerFormat or "m:ss"
        local m, s = math.floor(sec / 60), math.floor(sec % 60)
        if fmt == "m" then
            return tostring(m) .. "m"
        elseif fmt == "h:mm:ss" then
            local h = math.floor(sec / 3600)
            m = math.floor(sec % 3600 / 60)
            if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
            return ("%d:%02d"):format(m, s)
        elseif fmt == "compact" then
            return FF.Clock(sec)
        end
        -- Full m:ss (default) — wide enough at UI scale ~0.71
        return ("%d:%02d"):format(m, s)
    end

    paintActive = function(b, state, remNum)
        -- state: "need" (all missing/red) | "partial" (some missing/orange+timer) | "ok" (all buffed/green) | "idle"
        local useBorder, useTimer, useFill = db.activeBorder, db.activeTimer, db.activeFill
        local function setTimer(text, color)
            if not b.timer then return end
            b.timer:SetText(text or "")
            if color then b.timer:SetTextColor(color[1], color[2], color[3]) end
        end
        if state == "need" then
            FF.SetBg(b, useFill and { C.bad[1] * 0.35, C.bad[2] * 0.35, C.bad[3] * 0.35, 1 } or C.row)
            FF.SetBorder(b, useBorder and C.bad or C.border)
            setTimer("")
        elseif state == "partial" then
            FF.SetBg(b, useFill and { C.warn[1] * 0.3, C.warn[2] * 0.3, C.warn[3] * 0.3, 1 } or C.row)
            FF.SetBorder(b, useBorder and C.warn or C.border)
            if useTimer and remNum then
                setTimer(formatRem(remNum), C.warn)
            else
                setTimer("")
            end
        elseif state == "ok" then
            FF.SetBg(b, useFill and { C.good[1] * 0.25, C.good[2] * 0.25, C.good[3] * 0.25, 1 } or C.row)
            FF.SetBorder(b, useBorder and C.good or C.border)
            if useTimer and remNum then
                setTimer(formatRem(remNum), C.good)
            else
                setTimer("")
            end
        else
            FF.SetBg(b, C.row)
            FF.SetBorder(b, C.border)
            setTimer("")
        end
    end

    hidePlayerExpand = function()
        if not helper or not helper.expand or InCombatLockdown() then return end
        helper.expand:Hide()
        helper.expand.class = nil
        helper.expand.anchor = nil
        for _, pb in ipairs(helper.expand.buttons) do
            clearSecure(pb)
            pb:Hide()
            pb.tname, pb.class, pb.unit = nil, nil, nil
        end
    end

    -- Light update for one expand row (icon/timer/state) — used by mousewheel.
    paintExpandButton = function(pb)
        if not pb or not pb.tname or not pb.class then return end
        local nId = getNormal(me, pb.class, pb.tname)
        local gId = (assign[me] or {})[pb.class] or 0
        local showB = nId > 0 and nId or gId
        local showIcon = showB > 0
        if showIcon then
            pb.blessTex:SetTexture(icon(showB))
            pb.blessTex:Show()
            pb.blessTex:ClearAllPoints()
            pb.blessTex:SetPoint("RIGHT", -2, 0)
            pb.blessTex:SetVertexColor(1, 1, 1, 1)
            pb.timer:ClearAllPoints()
            pb.timer:SetWidth(36)
            pb.timer:SetPoint("RIGHT", pb.blessTex, "LEFT", -2, 0)
        else
            pb.blessTex:Hide()
            pb.timer:ClearAllPoints()
            pb.timer:SetWidth(36)
            pb.timer:SetPoint("RIGHT", -2, 0)
        end
        -- Clip frame sized to the name slot; text is left-only so it cuts off (no "...").
        pb.nameClip:ClearAllPoints()
        pb.nameClip:SetPoint("LEFT", 3, 0)
        pb.nameClip:SetPoint("RIGHT", pb.timer, "LEFT", -2, 0)
        pb.nameClip:SetHeight(HCELL_H)
        pb.name:ClearAllPoints()
        pb.name:SetPoint("LEFT", 0, 0)
        local rem = showB > 0 and pb.unit and auraRem(pb.unit, blessNames(showB)) or nil
        local remNum = type(rem) == "number" and rem or nil
        paintActive(pb, (showB > 0 and rem == nil) and "need" or (showB > 0 and "ok" or "idle"), remNum)
    end

    showPlayerExpand = function(anchor, classId)
        if not helper or InCombatLockdown() or not classId or classId < 1 then return end
        if not helper.expand then return end
        local members = classMembers(classId)
        if #members == 0 then hidePlayerExpand(); return end
        local gap = 1
        local pw = tonumber(db.playerWidth) or 90
        if pw < 60 then pw = 60 elseif pw > 160 then pw = 160 end
        helper.expand.class = classId
        helper.expand.anchor = anchor
        helper.expand:ClearAllPoints()
        helper.expand:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, 0)
        local n = math.min(#members, MAXPERCLASS)
        helper.expand:SetSize(pw, n * HCELL_H + math.max(0, n - 1) * gap)
        for i = 1, MAXPERCLASS do
            local pb = helper.expand.buttons[i]
            local m = members[i]
            if m then
                pb.class, pb.tname, pb.unit = classId, m.name, m.unit
                pb:ClearAllPoints()
                pb:SetPoint("TOPLEFT", 0, -((i - 1) * (HCELL_H + gap)))
                pb:SetSize(pw, HCELL_H)
                pb.name:SetText(dispName(m.name, m.unit))
                paintExpandButton(pb)
                pb:Show()
            else
                clearSecure(pb)
                pb:Hide()
                pb.tname, pb.class, pb.unit = nil, nil, nil
            end
        end
        helper.expand:Show()
    end

    local ICON_SZ = HCELL_H - 4
    local TIMER_ROW = 12 -- above/below icon row

    local function timerSide()
        local p = db.timerPos
        if p == "left" or p == "right" or p == "above" or p == "below" then return p end
        -- Default: right when vertical, below when horizontal.
        return (db.layout ~= "horizontal") and "right" or "below"
    end

    local function iconsW()
        local w = ICON_SZ
        if db.activeIcon then w = w + 1 + ICON_SZ end
        return w
    end

    local function minColW()
        local side = timerSide()
        local iw = 1 + iconsW() + 1
        if db.activeTimer and (side == "left" or side == "right") then
            -- Need room for icons + a readable timer slot.
            return math.max(48, iw + 20)
        end
        return math.max(28, iw)
    end

    local function cellW()
        local w = tonumber(db.colWidth) or 56
        if w < minColW() then w = minColW() end
        if w > 140 then w = 140 end
        return w
    end

    local function cellH()
        local side = timerSide()
        local stack = (side == "above" or side == "below")
            and ((db.activeTimer) or (showSalvColumn() and db.salvTimer))
        if stack then return HCELL_H + TIMER_ROW end
        return HCELL_H
    end

    local function placeIconPair(b, x, y, fromTop)
        b.classTex:ClearAllPoints()
        b.classTex:SetSize(ICON_SZ, ICON_SZ)
        if fromTop then
            b.classTex:SetPoint("TOPLEFT", x, y)
        else
            b.classTex:SetPoint("LEFT", x, y)
        end
        if db.activeIcon then
            b.blessTex:ClearAllPoints()
            b.blessTex:SetSize(ICON_SZ, ICON_SZ)
            b.blessTex:SetPoint("LEFT", b.classTex, "RIGHT", 1, 0)
        end
    end

    local function salvShowsIcon()
        return (db.salvIcon or db.salvColorIcon) and true or false
    end

    local function salvCellW()
        local w = 2
        local showIcon = salvShowsIcon()
        if showIcon then w = w + ICON_SZ end
        if db.salvTimer then
            local tw = 36
            if showIcon then
                local side = timerSide()
                if side == "left" or side == "right" then
                    w = w + 2 + tw
                else
                    w = math.max(w, tw + 2)
                end
            else
                w = w + tw
            end
        end
        return math.max(w, showIcon and (ICON_SZ + 2) or 28)
    end

    local function layoutSalvCell(b)
        local showIcon = salvShowsIcon()
        local showTimer = db.salvTimer and true or false
        local sw, ch = salvCellW(), cellH()
        local side = timerSide()
        b.blessTex:SetShown(showIcon)
        b.blessTex:ClearAllPoints()
        b.blessTex:SetSize(ICON_SZ, ICON_SZ)
        if b.colorOverlay then
            b.colorOverlay:ClearAllPoints()
            b.colorOverlay:SetAllPoints(b.blessTex)
        end
        b.timer:SetShown(showTimer)
        b.timer:ClearAllPoints()
        b.timer:SetJustifyH("CENTER")
        if showIcon and showTimer then
            if side == "below" then
                b.blessTex:SetPoint("TOP", 0, -math.floor((HCELL_H - ICON_SZ) / 2))
                b.timer:SetPoint("BOTTOMLEFT", 1, 1)
                b.timer:SetPoint("BOTTOMRIGHT", -1, 1)
            elseif side == "above" then
                b.timer:SetPoint("TOPLEFT", 1, -1)
                b.timer:SetPoint("TOPRIGHT", -1, -1)
                b.blessTex:SetPoint("BOTTOM", 0, math.floor((HCELL_H - ICON_SZ) / 2))
            elseif side == "left" then
                b.timer:SetPoint("LEFT", 1, 0)
                b.timer:SetPoint("RIGHT", b.blessTex, "LEFT", -2, 0)
                b.blessTex:SetPoint("RIGHT", -1, 0)
            else
                b.blessTex:SetPoint("LEFT", 1, 0)
                b.timer:SetPoint("LEFT", b.blessTex, "RIGHT", 2, 0)
                b.timer:SetPoint("RIGHT", -1, 0)
            end
        elseif showIcon then
            b.blessTex:SetPoint("CENTER")
        elseif showTimer then
            b.timer:SetPoint("LEFT", 1, 0)
            b.timer:SetPoint("RIGHT", -1, 0)
        end
        b:SetSize(sw, ch)
    end

    local function layoutCell(b)
        local showIcon = db.activeIcon and true or false
        local showTimer = db.activeTimer and true or false
        local cw, ch = cellW(), cellH()
        local side = timerSide()

        b.classTex:ClearAllPoints()
        b.classTex:SetSize(ICON_SZ, ICON_SZ)
        b.blessTex:SetShown(showIcon)
        if showIcon then
            b.blessTex:ClearAllPoints()
            b.blessTex:SetSize(ICON_SZ, ICON_SZ)
        end
        b.timer:SetShown(showTimer)
        b.timer:ClearAllPoints()
        b.timer:SetJustifyH("CENTER")

        if not showTimer then
            placeIconPair(b, 1, 0, false)
            b:SetSize(cw, ch)
            return
        end

        local iw = iconsW()
        if side == "below" then
            local x = math.floor((cw - iw) / 2)
            local iy = -math.floor((HCELL_H - ICON_SZ) / 2)
            placeIconPair(b, x, iy, true)
            b.timer:SetPoint("BOTTOMLEFT", 1, 1)
            b.timer:SetPoint("BOTTOMRIGHT", -1, 1)
        elseif side == "above" then
            local x = math.floor((cw - iw) / 2)
            b.timer:SetPoint("TOPLEFT", 1, -1)
            b.timer:SetPoint("TOPRIGHT", -1, -1)
            b.classTex:ClearAllPoints()
            b.classTex:SetSize(ICON_SZ, ICON_SZ)
            b.classTex:SetPoint("BOTTOMLEFT", x, math.floor((HCELL_H - ICON_SZ) / 2))
            if showIcon then
                b.blessTex:ClearAllPoints()
                b.blessTex:SetSize(ICON_SZ, ICON_SZ)
                b.blessTex:SetPoint("LEFT", b.classTex, "RIGHT", 1, 0)
            end
        elseif side == "left" then
            -- Timer in left slot (centered), icons on the right.
            local ix = cw - 1 - iw
            placeIconPair(b, ix, 0, false)
            b.timer:SetPoint("LEFT", 1, 0)
            b.timer:SetPoint("RIGHT", b.classTex, "LEFT", -2, 0)
        else
            -- right (default vertical): icons left, timer centered in remaining width.
            placeIconPair(b, 1, 0, false)
            local anchor = showIcon and b.blessTex or b.classTex
            b.timer:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
            b.timer:SetPoint("RIGHT", -1, 0)
        end
        b:SetSize(cw, ch)
    end

    local function wireCast(b, sp, gsp, unit)
        if not (sp and unit) then
            clearSecure(b)
            return
        end
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", sp)
        b:SetAttribute("unit", unit)
        if gsp then
            b:SetAttribute("type2", "spell")
            b:SetAttribute("spell2", gsp)
            b:SetAttribute("unit2", unit)
        else
            b:SetAttribute("type2", nil)
            b:SetAttribute("spell2", nil)
            b:SetAttribute("unit2", nil)
        end
    end

    local function applyAssignLook()
        local ab = helper and helper.assignBtn
        if not ab then return end
        FF.Skin(ab, "row")
        if ab.cog then ab.cog:Show() end
        if ab.dot then ab.dot:Hide() end
        if ab.label then ab.label:SetText("") end
        applyAssignLockColor()
    end

    local helperPending = false
    local function doRefreshHelper()
        helperPending = false
        -- Helper (and assignments control) shows whenever the module wants it —
        -- not only for paladins, so leads can open the panel from the green dot.
        local want = db.helper
        if not want then
            if helper and not InCombatLockdown() then helper:Hide() end
            return
        end
        if not helper then buildHelper() end
        if helper._ffDragging or (helper.IsMoving and helper:IsMoving()) then return end
        applyHelperChrome()
        applyAssignLook()
        if InCombatLockdown() then
            if not helper:IsShown() then helper:Show() end
            return
        end

        local rows = isPally and helperRows() or {}
        local vertical = db.layout ~= "horizontal"
        local gap = 1
        local edge = db.showTitle and 4 or 0
        local top = titleH() + (db.showTitle and 2 or 0)
        local cw = cellW()
        local ch = cellH()
        local salvOn = isPally and showSalvColumn()
        local sw = salvOn and salvCellW() or 0
        local sh = salvOn and ch or 0 -- match class cell height
        local side = salvSide(vertical)
        -- Vertical left/right: side-by-side. Horizontal above/below: stacked per class.
        local pairW = vertical and (cw + (salvOn and (sw + gap) or 0)) or cw
        local pairH = (not vertical and salvOn) and (ch + gap + sh) or ch
        local showAuto = db.autoBtn ~= false and isPally
        local showAssign = db.assignBtn ~= false
        local showTop = showAuto or showAssign
        local ctrls = {}
        local assignFirst = db.ctrlOrder ~= "auto_assign"
        if assignFirst then
            if showAssign then ctrls[#ctrls + 1] = "assign" end
            if showAuto then ctrls[#ctrls + 1] = "auto" end
        else
            if showAuto then ctrls[#ctrls + 1] = "auto" end
            if showAssign then ctrls[#ctrls + 1] = "assign" end
        end
        local nCtrl = #ctrls
        local ctrlH = showTop and HCELL_H or 0
        local ctrlGap = (showTop and #rows > 0) and gap or 0
        local ctrlW = vertical and pairW or cw

        if showTop then
            local nNeed = showAuto and countAutoNeed() or 0
            local function placeCtrl(key, x, y, w)
                if key == "auto" then
                    local auto = helper.autoBtn
                    auto:SetSize(w, HCELL_H)
                    auto:ClearAllPoints()
                    auto:SetPoint("TOPLEFT", x, -y)
                    auto:Show()
                    paintActive(auto, nNeed > 0 and "need" or "ok")
                else
                    local ab = helper.assignBtn
                    ab:SetSize(w, HCELL_H)
                    ab:ClearAllPoints()
                    ab:SetPoint("TOPLEFT", x, -y)
                    ab:Show()
                    applyAssignLook()
                end
            end
            helper.autoBtn:Hide()
            helper.assignBtn:Hide()
            if not showAuto and not InCombatLockdown() then clearSecure(helper.autoBtn) end
            local half = math.max(24, math.floor((ctrlW - gap) / 2))
            local w1 = (nCtrl == 2) and half or ctrlW
            local w2 = (nCtrl == 2) and (ctrlW - half - gap) or ctrlW
            if ctrls[1] then placeCtrl(ctrls[1], edge, top, w1) end
            if ctrls[2] then placeCtrl(ctrls[2], edge + w1 + gap, top, w2) end
        else
            helper.autoBtn:Hide()
            helper.assignBtn:Hide()
            if not InCombatLockdown() then clearSecure(helper.autoBtn) end
        end

        local function paintSalv(b, state, remNum)
            local useBorder, useFill = db.activeBorder, db.activeFill
            local useTimer = db.salvTimer
            local function tintIcon(color)
                if not b.blessTex then return end
                if db.salvColorIcon and color and salvShowsIcon() then
                    b.blessTex:SetVertexColor(color[1], color[2], color[3], 1)
                    if b.colorOverlay then
                        b.colorOverlay:SetColorTexture(color[1], color[2], color[3], 0.4)
                        b.colorOverlay:Show()
                    end
                else
                    b.blessTex:SetVertexColor(1, 1, 1, 1)
                    if b.colorOverlay then b.colorOverlay:Hide() end
                end
            end
            if state == "need" then
                FF.SetBg(b, useFill and { C.bad[1] * 0.35, C.bad[2] * 0.35, C.bad[3] * 0.35, 1 } or C.row)
                FF.SetBorder(b, useBorder and C.bad or C.border)
                if b.timer then b.timer:SetText("") end
                tintIcon(C.bad)
            elseif state == "partial" then
                FF.SetBg(b, useFill and { C.warn[1] * 0.3, C.warn[2] * 0.3, C.warn[3] * 0.3, 1 } or C.row)
                FF.SetBorder(b, useBorder and C.warn or C.border)
                if b.timer then
                    if useTimer and remNum then
                        b.timer:SetText(formatRem(remNum))
                        b.timer:SetTextColor(C.warn[1], C.warn[2], C.warn[3])
                    else
                        b.timer:SetText("")
                    end
                end
                tintIcon(C.warn)
            elseif state == "ok" then
                FF.SetBg(b, useFill and { C.good[1] * 0.25, C.good[2] * 0.25, C.good[3] * 0.25, 1 } or C.row)
                FF.SetBorder(b, useBorder and C.good or C.border)
                if b.timer then
                    if useTimer and remNum then
                        b.timer:SetText(formatRem(remNum))
                        b.timer:SetTextColor(C.good[1], C.good[2], C.good[3])
                    else
                        b.timer:SetText("")
                    end
                end
                tintIcon(C.good)
            else
                FF.SetBg(b, C.row)
                FF.SetBorder(b, C.border)
                if b.timer then b.timer:SetText("") end
                tintIcon(nil)
            end
        end

        local function fillSalv(s, c)
            if salvShowsIcon() then
                FF.SetIcon(s.blessTex, ICON[4] or icon(4))
            end
            if classHasSalvTarget(c) then
                local miss, rem, any, refresh, state = classNeed(c, 4)
                local remNum = type(rem) == "number" and rem or nil
                local sp = spellFor(4)
                local gsp = greaterKnown(4)
                local target = miss or refresh
                if any and target and sp then
                    wireCast(s, sp, gsp, target)
                    paintSalv(s, state or "idle", remNum)
                elseif any then
                    clearSecure(s)
                    paintSalv(s, state or "ok", remNum)
                else
                    clearSecure(s)
                    paintSalv(s, "idle")
                end
            else
                clearSecure(s)
                paintSalv(s, "idle")
            end
        end

        for i, row in ipairs(rows) do
            local yBase = top + ctrlH + ctrlGap
            local slot = (i - 1)
            local s = sCells[i]
            local b = hCells[i]

            -- Class blessing cell (skipped for salv-only rows).
            local classX, classY
            if vertical then
                classX = edge + ((salvOn and side == "left") and (sw + gap) or 0)
                classY = yBase + slot * (ch + gap)
            else
                local xBase = edge + (showTop and (cw + gap) or 0)
                classX = xBase + slot * (cw + gap)
                classY = top + ((salvOn and side == "above") and (sh + gap) or 0)
            end

            -- Class cell (also shown for individual-only / salv-only rows so players can expand).
            layoutCell(b)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", classX, -classY)
                b:Show()
            b.classId = row.c
            b.classBless = row.b
            FF.SetIcon(b.classTex, classIconPath(row.c))
            if row.b > 0 and db.activeIcon then
                b.blessTex:SetTexture(icon(row.b))
                b.blessTex:Show()
            elseif db.activeIcon then
                b.blessTex:Hide()
            end
            -- Status from effective blessings; PreClick casts class assigns then individuals.
            do
                local _, rem, any, _, state = classNeedEffective(row.c, row.b)
                local remNum = type(rem) == "number" and rem or nil
                if not InCombatLockdown() then clearSecure(b) end
                if any then
                    paintActive(b, state or "idle", remNum)
                else
                    paintActive(b, "idle")
            end
        end
            b:SetScript("OnEnter", function(self)
                helper.expand._anchorHover = true
                showPlayerExpand(self, self.classId)
            end)
            b:SetScript("OnLeave", function()
                helper.expand._anchorHover = false
                C_Timer.After(0.15, function()
                    if helper and helper.expand and not helper.expand._hover and not helper.expand._anchorHover then
                        hidePlayerExpand()
                    end
                end)
            end)

            -- Salv strip: left/right of class when vertical; above/below when horizontal.
            if salvOn then
                layoutSalvCell(s)
                local sx, sy
                if vertical then
                    sx = (side == "left") and edge or (edge + cw + gap)
                    sy = yBase + slot * (ch + gap)
                else
                    local xBase = edge + (showTop and (cw + gap) or 0)
                    sx = xBase + slot * (cw + gap)
                    sy = (side == "above") and top or (top + ch + gap)
                    -- Match class column width when stacked above/below.
                    s:SetWidth(cw)
                end
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", sx, -sy)
                s:Show()
                fillSalv(s, row.c)
            else
                clearSecure(s)
                s:Hide()
            end
        end
        for i = #rows + 1, #hCells do
            clearSecure(hCells[i])
            hCells[i]:Hide()
            clearSecure(sCells[i])
            sCells[i]:Hide()
        end

        local nRows = #rows
        local function stackSize(n, item, g)
            if n <= 0 then return 0 end
            return n * item + (n - 1) * g
        end
        if vertical then
            local body = ctrlH + ctrlGap + stackSize(nRows, ch, gap)
            if body == 0 then body = HCELL_H end
            helper:SetWidth(pairW + edge * 2)
            helper:SetHeight(top + body + edge)
        else
            local body = (showTop and cw or 0) + ctrlGap + stackSize(nRows, cw, gap)
            if body == 0 then body = cw end
            helper:SetWidth(edge * 2 + body)
            helper:SetHeight(top + pairH + edge)
        end
        helper.empty:ClearAllPoints()
        helper.empty:SetPoint("TOPLEFT", edge, -(top + ctrlH + ctrlGap))
        helper.empty:SetText((isPally and nRows == 0 and not showTop) and "No assignments" or "")
        -- Keep open player expand live (buffs/clears) without needing re-hover.
        if helper.expand and helper.expand:IsShown() and helper.expand.class and helper.expand.anchor then
            showPlayerExpand(helper.expand.anchor, helper.expand.class)
        end
        helper:Show()
    end

    refreshHelper = function()
        if helperPending then return end
        helperPending = true
        C_Timer.After(0.3, doRefreshHelper)
    end

    M.Refresh = changed

    ---------------------------------------------------------------------------
    -- Events
    ---------------------------------------------------------------------------
    local function onAura(_, unit)
        if helper and helper:IsShown() and type(unit) == "string" and (unit == "player" or unit:find("^raid") or unit:find("^party")) then
            refreshHelper()
        end
    end
    local wasInGroup = false
    local function onRoster()
        rosterDirty = true
        refreshLeaders()
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
            wipe(leaders)
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
        refreshIdentity()
        refreshLeaders()
        scanSelf()
        onRoster()
        if db.panel then M.TogglePanel(true) end
        refreshHelper()
    end)

    -- Timers: light expand paint every tick; full helper rebuild less often.
    local helperTick = 0
    C_Timer.NewTicker(1, function()
        if not (helper and helper:IsShown() and db.helper) then return end
        helperTick = helperTick + 1
        if helper.expand and helper.expand:IsShown() and paintExpandButton then
            for _, pb in ipairs(helper.expand.buttons) do
                if pb:IsShown() then paintExpandButton(pb) end
            end
        end
        if helperTick % 2 == 0 then doRefreshHelper() end
    end)

    FF.Command("bless", function(arg)
        arg = (arg or ""):lower()
        if arg == "auto" or arg == "smart" then M.Auto()
        elseif arg == "clear" then M.Clear()
        elseif arg == "buffs" then
            db.helper = not db.helper
            refreshHelper()
        else M.TogglePanel() end
    end, "assignment panel ('bless auto', 'bless buffs', 'bless clear')")

    FF.Settings("Blessings", function(L)
        L:Header("Paladin blessings")
        L:Desc("Two windows: Open panel to set assignments (syncs with PallyPower). Buff helper stays on screen so you can click to cast. If PallyPower itself is installed this module stays out of the way.")
        L:Buttons({
            { "Open panel", function() M.TogglePanel(true) end, "/ff bless — set who buffs which class" },
        })
        L:Toggle("Show nicknames in the assignment list", db, "showNick", {
            onChange = function()
                if refreshPanel then refreshPanel() end
                refreshHelper()
            end,
            tip = "On: nickname only (panel names under class icons + helper player rows). Off: character first name.",
        })
        L:Header("Buff helper")
        L:Toggle("Show buff helper on screen", db, "helper", {
            onChange = refreshHelper,
            tip = "Shows for everyone with the module on. Paladins get click-to-cast cells for classes in the group; the assignments control toggles the panel. Shift-drag a cell to move when the title is hidden.",
        })
        L:Select("Layout", db, "layout", {
            { "vertical", "Vertical" },
            { "horizontal", "Horizontal" },
        }, { onChange = refreshHelper })
        L:Slider("Column width", db, "colWidth", 36, 140, 2, {
            onChange = refreshHelper,
            fmt = function(v) return v .. " px" end,
            tip = "Width of each helper cell. Timer text is centered in its slot (beside or above/below the icons).",
        })
        L:Slider("Player row width", db, "playerWidth", 60, 160, 2, {
            onChange = refreshHelper,
            fmt = function(v) return v .. " px" end,
            tip = "Width of the hover-expanded individual player rows. Long names cut off; the timer always stays fully visible.",
        })
        L:Header("Active buff indicator")
        L:Desc("Red = everyone missing. Orange = some missing (keeps lowest timer). Green = all buffed.")
        L:Toggle("Border colour", db, "activeBorder", {
            onChange = refreshHelper, tip = "Red / orange / green border by missing vs buffed.",
        })
        L:Toggle("Remaining timer", db, "activeTimer", {
            onChange = refreshHelper, tip = "Lowest remaining time on green/orange cells.",
        })
        L:Select("Timer position", db, "timerPos", {
            { "right", "Right of icons" },
            { "left", "Left of icons" },
            { "below", "Below icons" },
            { "above", "Above icons" },
        }, { onChange = refreshHelper, dep = function() return db.activeTimer end,
            tip = "Where the countdown sits relative to the class / blessing icons." })
        L:Select("Timer format", db, "timerFormat", {
            { "m:ss", "Minutes:seconds (12:05)" },
            { "m", "Minutes only (12m)" },
            { "h:mm:ss", "Full timestamp (1:02:05)" },
            { "compact", "Compact (1h02m / 12:05)" },
        }, { onChange = refreshHelper, dep = function() return db.activeTimer end,
            tip = "Widen Column width if a long format clips." })
        L:Toggle("Background fill", db, "activeFill", {
            onChange = refreshHelper, tip = "Tint the whole cell red / orange / green.",
        })
        L:Toggle("Blessing icon", db, "activeIcon", {
            onChange = refreshHelper, tip = "Show the assigned blessing next to the class icon.",
        })
        L:Toggle("Show title bar", db, "showTitle", {
            onChange = refreshHelper,
            tip = "Off by default. When on, drag the title to move and use the close button.",
        })
        L:Header("Auto + Assign")
        L:Toggle("Show Auto Buff", db, "autoBtn", {
            onChange = refreshHelper,
            tip = "Shares the first row 50/50 with Assign. Each click casts the next needed blessing. Left = Greater when known; right = Normal.",
        })
        L:Toggle("Show Assign (cog)", db, "assignBtn", {
            onChange = refreshHelper,
            tip = "Shares the first row 50/50 with Auto. Left-click toggles the assignment panel. Right-click locks (red) or unlocks (green) the helper.",
        })
        L:Select("Button order", db, "ctrlOrder", {
            { "assign_auto", "Assign, then Auto" },
            { "auto_assign", "Auto, then Assign" },
        }, {
            onChange = refreshHelper,
            tip = "Left-to-right order on the shared first row.",
            dep = function() return db.autoBtn ~= false or db.assignBtn ~= false end,
        })
        L:Toggle("Prefer Greater Blessing when casting", db, "greater", {
            onChange = refreshHelper,
            tip = "Click-to-cast class cells: left uses Greater when known. Auto left-click tries Greater when you have Symbol of Kings.",
        })
        L:Header("Salvation")
        L:Toggle("Offer Salvation (never on tanks)", db, "salv", { onChange = function()
            scanSelf()
            send(db.salv and "SALV YES" or "SALV NO")
            changed()
        end, tip = "Assigned from the Salv column on the panel (Free Assignment / lead). Forever: stacks with blessings. Auto includes Salv with your other buffs." })
        L:Toggle("Show Salv icon", db, "salvIcon", {
            onChange = refreshHelper,
            dep = function() return db.salv end,
            tip = "Salv spell icon on the strip (no duplicate class icon).",
        })
        L:Toggle("Colour Salv icon", db, "salvColorIcon", {
            onChange = refreshHelper,
            dep = function() return db.salv end,
            tip = "Green = all Salv'd, orange = some missing (keeps lowest timer), red = all missing.",
        })
        L:Toggle("Show Salv timer", db, "salvTimer", {
            onChange = refreshHelper,
            dep = function() return db.salv end,
            tip = "Countdown on the Salv strip. Strip hides if icon, colour, and timer are all off.",
        })
        L:Select("Salv position", db, "salvPos", {
            { "auto", "Auto (right if vertical, below if horizontal)" },
            { "left", "Left of class (vertical)" },
            { "right", "Right of class (vertical)" },
            { "above", "Above class (horizontal)" },
            { "below", "Below class (horizontal)" },
        }, {
            onChange = refreshHelper,
            dep = function() return db.salv and (db.salvIcon or db.salvTimer or db.salvColorIcon) end,
            tip = "Where the Salv strip sits relative to each class cell.",
        })
        L:Toggle("Free assignment (anyone may set my blessings)", db, "free", { onChange = function()
            scanSelf(); last = nil; sendSelfSoon()
        end })
    end)
end)
