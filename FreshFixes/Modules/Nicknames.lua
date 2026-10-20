local _, FF = ...
local M = FF.Module("Nicknames")

-- Guild nicknames. Officers (guild rank 0 or 1) keep one list and push it
-- to the guild when they want. Everyone else accepts that push and replaces
-- their list with it.
--   * Forever has no realms: a character is "First Surname", unique per
--     region. Nicknames are keyed by that name alone ("nik palatoo"), so the
--     realm each beta client tacks on (its OWN realm, for everyone) and
--     Forever's habit of putting the surname where the realm goes
--     ("Nik-Palatoo") never matter. Any name shape finds the entry.
--   * One nickname can cover alts: edit as "Nick: Char1, Char2". A BattleTag
--     ("Name#1234") entry covers every character of a Battle.net friend.
--   * Shown on Blizzard unit frames (player, target, focus, party, raid), in
--     chat, tooltips, WeakAuras and the add-on frames in NicknamesFrames.lua.
-- Comms tag "K": P<str> officer push (guild). Strings: NICK:1 (FORMATS.md)
FF.Init("Nicknames", function()
    local readable = FF.readable
    local db = FF.DB("nicknames", {
        tooltip = true, frames = true, chat = true, weakauras = true,
        elvui = true, grid2 = true, vuhdo = true, ellesmere = true,
    })
    M.db = db
    db.map = db.map or {}     -- [name key or "bt:name#1234"] = nickname
    db.names = db.names or {} -- [name key] = "First Surname" as written

    local function clean(n)
        if type(n) ~= "string" then
            return
        end
        n = n:gsub("[%c|~]", ""):match("^%s*(.-)%s*$")
        if n ~= "" and #n <= 24 then
            return n
        end
    end

    ---------------------------------------------------------------------------
    -- Names
    ---------------------------------------------------------------------------
    local function norm(s)
        return (s:lower():gsub("%s+", " "):match("^%s*(.-)%s*$"))
    end
    local function squash(s)
        return (s:gsub("%s", ""))
    end
    local function firstWord(s)
        return s:match("^%S+")
    end

    -- Realm suffixes seen in the guild roster ("First Surname-Realm") and our
    -- own. Beta realms ("ClassicBetaPvE2") always count.
    local realms, realmsFrom
    local function isRealm(t)
        local roster = FF.GuildRoster()
        if realmsFrom ~= roster then
            realmsFrom, realms = roster, {}
            realms[squash(norm(GetNormalizedRealmName() or ""))] = true
            for _, r in pairs(roster) do
                local tail = r.name:match("%s.-%-(.+)$")
                if tail then
                    realms[squash(norm(tail))] = true
                end
            end
        end
        t = squash(t)
        return realms[t] or t:find("^classicbeta") ~= nil
    end

    -- Any way a name arrives -> key, display. "Nik Palatoo-Realm", "Nik-Realm",
    -- "Nik-Palatoo" (surname in the realm slot), "nikpalatoo-realm" (our
    -- internal keys), "Nik", "Name#1234".
    local function nameKey(s)
        if type(s) ~= "string" or not readable(s) then
            return
        end
        s = s:match("^%s*(.-)%s*$")
        if s == "" then
            return
        end
        if s:find("#", 1, true) then
            return "bt:" .. s:lower(), s
        end
        local head, tail = s:match("^(.-)%-(.+)$")
        head = (head or s):match("^%s*(.-)%s*$")
        if head:find(" ", 1, true) or not tail or isRealm(norm(tail)) then
            return norm(head), head
        end
        local full = head .. " " .. tail:match("^%s*(.-)%s*$")
        return norm(full), full
    end

    local function unitName(unit)
        local first, surname = UnitFullName(unit)
        if readable(first) and readable(surname) and type(first) == "string" and first ~= "" then
            return type(surname) == "string" and surname ~= "" and (first .. " " .. surname) or first
        end
    end

    -- The one rule: a nickname shows only when the character's first AND last
    -- name match a row. A first name alone never matches, and the realm part
    -- is ignored. bySquash also lets our internal keys ("nikpalatoo-realm",
    -- spaces removed) find "nik palatoo"; it only holds full names.
    local bySquash
    local function look(s)
        local k = nameKey(s)
        if not k then
            return
        end
        if k:find("^bt:") or k:find(" ", 1, true) then
            return db.map[k]
        end
        if not bySquash then
            bySquash = {}
            for key, v in pairs(db.map) do
                if key:find(" ", 1, true) then
                    bySquash[squash(key)] = v
                end
            end
        end
        return bySquash[k]
    end

    function M.Get(name)
        return look(name)
    end

    -- where: the "where nicknames show" setting asking (frames, chat, ...)
    function M.For(unit, where)
        return db[where] and M.ForUnit(unit) or nil
    end

    function M.ForUnit(unit)
        if not unit or not readable(unit) or not UnitIsPlayer(unit) then
            return
        end
        local nick = look(unitName(unit))
        if nick or not C_BattleNet or not C_BattleNet.GetAccountInfoByGUID then
            return nick
        end
        local ok, guid = pcall(UnitGUID, unit)
        if ok and guid and readable(guid) then
            local info = C_BattleNet.GetAccountInfoByGUID(guid)
            if info and type(info.battleTag) == "string" then
                return db.map["bt:" .. info.battleTag:lower()]
            end
        end
    end

    -- Global helper for other addons / WeakAuras custom code.
    function FreshFixesUnitName(unit)
        return M.ForUnit(unit) or UnitName(unit)
    end

    local myKey, myName
    local function me()
        if not myKey then
            myName = unitName("player")
            myKey = myName and nameKey(myName)
        end
        return myKey
    end

    local function displayName(key)
        if key:find("^bt:") then
            return key:sub(4)
        end
        return db.names[key] or key:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
    end

    -- Set one character's nickname (nil clears it); drops copies of the same
    -- name stored another way. Returns true when something changed.
    local function setNick(key, nick, display)
        local changed = false
        if not key:find("^bt:") then
            local sq = squash(key:match("^[^%-]+"))
            for k in pairs(db.map) do
                if k ~= key and not k:find("^bt:") and squash(k:match("^[^%-]+")) == sq then
                    db.map[k], db.names[k] = nil, nil
                    changed = true
                end
            end
            if display and display:find(" ", 1, true) then
                db.names[key] = display
            end
        end
        if db.map[key] ~= nick then
            db.map[key] = nick
            changed = true
        end
        bySquash = nil
        return changed
    end

    ---------------------------------------------------------------------------
    -- Unit frames: Blizzard player / target / focus / party, and raid frames
    ---------------------------------------------------------------------------
    -- fromGame: Blizzard just wrote the real name, so remember it; going back
    -- from a nickname restores exactly that text (never looked up again).
    local busy
    local function nameUnitFrame(f, fromGame)
        local fs = f and f.ffName
        if not fs or not f.unit or busy then
            return
        end
        busy = true
        if fromGame then
            f.ffReal = fs:GetText()
        end
        local nick = M.For(f.unit, "frames")
        if nick then
            fs:SetText(nick)
        elseif f.ffNicked and f.ffReal then
            fs:SetText(f.ffReal)
        end
        f.ffNicked = nick ~= nil
        busy = false
    end

    local unitFrames = {}
    local function hookUnitFrames()
        local list = { PlayerFrame, TargetFrame, FocusFrame, TargetFrameToT, FocusFrameToT }
        for i = 1, 4 do
            list[#list + 1] = PartyFrame and PartyFrame["MemberFrame" .. i] or _G["PartyMemberFrame" .. i]
        end
        for _, f in pairs(list) do
            local fs = f and (f.name or f.Name)
            if fs and not f.ffName then
                f.ffName = fs
                unitFrames[#unitFrames + 1] = f
                -- whatever updates the name, put the nickname back on top
                hooksecurefunc(fs, "SetText", function()
                    nameUnitFrame(f, true)
                end)
                nameUnitFrame(f, true)
            end
        end
    end

    -- raid / party frames and player nameplates (forbidden ones are off limits)
    local function nameRaidFrame(frame)
        if not db.frames or not frame or (frame.IsForbidden and frame:IsForbidden()) or not frame.name then
            return
        end
        local nick = M.For(frame.unit, "frames")
        if nick then
            frame.name:SetText(nick)
        end
    end

    function M.UpdateFrames()
        bySquash = nil -- the list changed
        if M.RefreshAddons then
            M.RefreshAddons()
        end
        for _, f in ipairs(unitFrames) do
            nameUnitFrame(f)
        end
        -- let Blizzard rewrite the real names; the hook puts nicknames on top
        local function redraw(frame)
            if frame and frame.unit and not (frame.IsForbidden and frame:IsForbidden()) then
                CompactUnitFrame_UpdateName(frame)
            end
        end
        for g = 1, 8 do
            for i = 1, 5 do
                redraw(_G["CompactRaidGroup" .. g .. "Member" .. i])
            end
        end
        for i = 1, 40 do
            redraw(_G["CompactPartyFrameMember" .. i] or _G["CompactRaidFrame" .. i])
        end
    end

    ---------------------------------------------------------------------------
    -- Chat: the clickable [Name] shows the nickname; the link still points at
    -- the real character, so whispers and menus work as usual.
    ---------------------------------------------------------------------------
    local function chatText(text)
        if not db.chat or not readable(text) or type(text) ~= "string" or not text:find("|Hplayer:", 1, true) then
            return text
        end
        return (text:gsub("(|Hplayer:([^:|]+)[^|]*|h)(.-)(|h)", function(open, target, shown, close)
            local nick = look(target) -- full name in the link, or nothing
            if not nick then
                return
            end
            local visible = shown:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%[%]]", "")
            local s, e = shown:find(visible, 1, true)
            if visible == "" or not s then
                return
            end
            return open .. shown:sub(1, s - 1) .. nick .. shown:sub(e + 1) .. close
        end))
    end

    local function hookChat()
        for _, name in ipairs(CHAT_FRAMES or {}) do
            local cf = _G[name]
            if cf and not cf.ffNick then
                cf.ffNick = true
                local add = cf.AddMessage
                cf.AddMessage = function(self, text, ...)
                    return add(self, chatText(text), ...)
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Text editor format and strings
    ---------------------------------------------------------------------------
    local function toText()
        local by, nicks = {}, {}
        for key, nick in pairs(db.map) do
            if not by[nick] then
                by[nick] = {}
                nicks[#nicks + 1] = nick
            end
            table.insert(by[nick], displayName(key))
        end
        table.sort(nicks, function(a, b)
            return a:lower() < b:lower()
        end)
        local out = { "# Nick: First Surname, Alt Surname, BattleTag#1234   (one nickname per line)" }
        for _, nick in ipairs(nicks) do
            table.sort(by[nick])
            out[#out + 1] = nick .. ": " .. table.concat(by[nick], ", ")
        end
        return table.concat(out, "\n")
    end

    -- Our format, and RG Aliases' "Nick - Name1 Name2". -> { {key, display, nick} }
    local function parseText(text)
        local out = {}
        for line in (text .. "\n"):gmatch("(.-)\r?\n") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" and not line:find("^#") then
                local nick, names = line:match("^(.-)%s*:%s*(.+)$")
                local list = {}
                if nick then
                    for n in names:gmatch("[^,]+") do
                        list[#list + 1] = n
                    end
                else
                    nick, names = line:match("^(%S+)%s+%-%s+(.+)$")
                    for n in (names or ""):gmatch("%S+") do
                        list[#list + 1] = n
                    end
                end
                nick = clean(nick)
                for _, n in ipairs(nick and list or {}) do
                    local key, display = nameKey(n)
                    if key then
                        out[#out + 1] = { key, display, nick }
                    end
                end
            end
        end
        return out
    end

    local function exportString()
        local list = {}
        for key, nick in pairs(db.map) do
            list[#list + 1] = { name = displayName(key), nick = nick }
        end
        table.sort(list, function(a, b)
            return a.name < b.name
        end)
        return FF.Encode("NICK", 1, { nicknames = list })
    end

    -- A push is the whole list. Anything not in it is removed.
    local function applyList(data)
        wipe(db.map)
        wipe(db.names)
        local n = 0
        for _, e in ipairs(type(data.nicknames) == "table" and data.nicknames or {}) do
            local key, display = nameKey(type(e) == "table" and e.name)
            local nick = key and clean(e.nick)
            if nick and setNick(key, nick, display) then
                n = n + 1
            end
        end
        M.UpdateFrames()
        return n
    end

    ---------------------------------------------------------------------------
    -- Who may push: guild rank 0 (GM) or 1 (officer). nil = rank unknown.
    ---------------------------------------------------------------------------
    local function officerRank(idx)
        if type(idx) ~= "number" then
            return nil
        end
        return idx <= 1
    end

    local rosterBy, rosterFrom
    local function member(key)
        local roster = FF.GuildRoster()
        if rosterFrom ~= roster then
            rosterFrom, rosterBy = roster, {}
            for _, r in pairs(roster) do
                local k = nameKey(r.name)
                if k then
                    rosterBy[k] = r
                    local f = firstWord(k)
                    rosterBy["first:" .. f] = rosterBy["first:" .. f] == nil and r or false
                end
            end
        end
        return rosterBy[key] or (key == firstWord(key) and rosterBy["first:" .. key]) or nil
    end

    -- true / false, or nil when the sender isn't in our roster cache yet
    local function isOfficer(key)
        if key == me() then
            return officerRank(select(3, GetGuildInfo("player"))) == true
        end
        local r = key and member(key)
        return officerRank(r and r.rankIndex)
    end

    FF.OnComm("K", function(payload, channel, display, senderKey)
        if senderKey == FF.UnitKey("player") then
            return -- our own push echoes back
        end
        if payload:sub(1, 1) ~= "P" or channel ~= "GUILD" then
            return
        end
        local d = FF.Decode(payload:sub(2), "NICK")
        if not d then
            return
        end
        -- trust only the real sender the game reports, never a name inside the payload
        local from = display
        local key = nameKey(from)
        local function apply(retry)
            local ok = isOfficer(key)
            if ok == nil and retry then
                FF.RequestGuildRoster(true) -- sender not in our roster yet
                C_Timer.After(4, function()
                    apply(false)
                end)
            elseif ok then
                applyList(d)
            end
        end
        apply(true)
    end)

    ---------------------------------------------------------------------------
    -- WeakAuras name functions (same approach as RG Aliases)
    ---------------------------------------------------------------------------
    local function hookWeakAuras()
        local WA = WeakAuras
        if not db.weakauras or not WA or M.waHooked then
            return
        end
        M.waHooked = true
        if WA.GetName then
            local orig = WA.GetName
            WA.GetName = function(name)
                if name then
                    return (db.weakauras and look(name)) or orig(name)
                end
            end
        end
        if WA.UnitName then
            local orig = WA.UnitName
            WA.UnitName = function(unit)
                local name, realm = orig(unit)
                return M.For(unit, "weakauras") or name, realm
            end
        end
        if WA.GetUnitName then
            local orig = WA.GetUnitName
            WA.GetUnitName = function(unit, showServer)
                return M.For(unit, "weakauras") or orig(unit, showServer)
            end
        end
    end

    FF.On("FF_READY", function()
        FF.RequestGuildRoster() -- ranks for incoming pushes
        if db.frames then
            hooksecurefunc("CompactUnitFrame_UpdateName", nameRaidFrame)
            hookUnitFrames()
        end
        hookChat()
        if FCF_OpenTemporaryWindow then
            hooksecurefunc("FCF_OpenTemporaryWindow", hookChat) -- new whisper tabs
        end
        C_Timer.After(2, M.UpdateFrames)
        hookWeakAuras()
    end)
    FF.On("ADDON_LOADED", function(_, name)
        if name == "WeakAuras" then
            hookWeakAuras()
        end
    end)
    local framesPending -- roster changes come in bursts: refresh once
    FF.On("GROUP_ROSTER_UPDATE", function()
        if not framesPending then
            framesPending = true
            C_Timer.After(0.5, function()
                framesPending = false
                M.UpdateFrames()
            end)
        end
    end)

    -- Tooltip: the first line is the unit name. Put the nickname there.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        if not db.tooltip or tip ~= GameTooltip then
            return
        end
        local _, unit = tip:GetUnit()
        local nick = M.For(unit, "tooltip")
        local line = nick and GameTooltipTextLeft1
        if line then
            local r, g, b = line:GetTextColor()
            line:SetText(nick)
            line:SetTextColor(r, g, b)
        end
    end)

    FF.Settings("Nicknames", function(L)
        L:Header("Where nicknames show")
        L:Toggle("Blizzard unit frames", db, "frames", { onChange = M.UpdateFrames,
            tip = "Player, target, focus, party and raid frames, and player nameplates. Turning this on takes effect after a reload." })
        L:Toggle("Chat", db, "chat", { tip = "Player names in chat; clicking still whispers the real character" })
        L:Toggle("Unit tooltips", db, "tooltip", { tip = "Replaces the name on the first line of the tooltip" })
        local function has(...)
            local names = { ... }
            return function()
                for _, n in ipairs(names) do
                    if C_AddOns.IsAddOnLoaded(n) then
                        return true
                    end
                end
                return false, names[1] .. " isn't installed or enabled."
            end
        end
        L:Toggle("EllesmereUI raid and unit frames", db, "ellesmere", { dep = has("EllesmereUIRaidFrames", "EllesmereUIUnitFrames", "EllesmereUI"), onChange = M.UpdateFrames })
        L:Toggle("ElvUI tags  [ff:name]", db, "elvui", { dep = has("ElvUI"), tip = "Adds [ff:name], [ff:name:short] (veryshort/medium/long) and [ff:target]. Reload to apply." })
        L:Toggle("Grid2 status", db, "grid2", { dep = has("Grid2"), tip = "Adds the 'Fresh Fixes Nickname' status for text indicators. Reload to apply." })
        L:Toggle("VuhDo bar names", db, "vuhdo", { dep = has("VuhDo"), tip = "Reload to apply." })
        L:Toggle("WeakAuras names", db, "weakauras", { dep = has("WeakAuras"), tip = "Reload to apply." })

        L:Header("Nickname list")
        L:Buttons({
            { "Edit list", function() FF.Run("nick edit") end, "Nick: First Surname, Alt, BattleTag#1234 - one line per player" },
            { "Push to guild", function() FF.Run("nick push") end, "Officers only." },
        })
    end)

    FF.Command("nick", function(rest)
        local cmd, arg = rest:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        if cmd == "list" or cmd == "edit" then
            FF.ShowText("Nicknames", toText(), function(text)
                wipe(db.map)
                wipe(db.names)
                for _, e in ipairs(parseText(text)) do
                    setNick(e[1], e[3], e[2])
                end
                M.UpdateFrames()
            end, "Save")
        elseif cmd == "push" then
            if not IsInGuild() then
                FF.print("You're not in a guild")
                return
            end
            if not isOfficer(me()) then
                FF.print("Only officers can push nicknames to the guild")
                return
            end
            FF.Send("K", "P" .. exportString(), "GUILD")
            FF.print("Pushing nicknames to the guild...")
        elseif cmd == "set" and arg ~= "" then
            local who, nick = arg:match("^(.-)%s*=%s*(.+)$")
            local key, display = nameKey(who)
            if not key then
                FF.print("Usage: /ff nick set First Surname = Nick   (or Name#1234 = Nick)")
                return
            end
            setNick(key, clean(nick), display)
            M.UpdateFrames()
        else
            print("  /ff nick edit - edit the list (Nick: First Surname, Alt, BattleTag#1234)")
            print("  /ff nick set First Surname = Nick")
            print("  /ff nick push - officers only (guild rank 0 or 1)")
        end
    end, "nicknames (/ff nick help)")
end)
