local _, FF = ...
local readable = FF.readable

-- Shared group + guild roster helpers so modules don't each walk the roster.

function FF.GroupUnits()
    local t = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            t[#t + 1] = "raid" .. i
        end
    else
        t[1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            t[#t + 1] = "party" .. i
        end
    end
    return t
end

-- Exact key first, then the same name under another realm spelling
function FF.UnitByKey(key)
    local loose
    for _, u in ipairs(FF.GroupUnits()) do
        local k = FF.UnitKey(u)
        if k == key then
            return u
        elseif not loose and FF.SameChar(k, key) then
            loose = u
        end
    end
    return loose
end

-- Leader or assistant. No key = the player.
function FF.IsGroupLead(key)
    local u = key and FF.UnitByKey(key) or "player"
    return u and (UnitIsGroupLeader(u) or UnitIsGroupAssistant(u)) or false
end

---------------------------------------------------------------------------
-- Guild roster cache: rebuilt lazily after GUILD_ROSTER_UPDATE.
-- [key] = { index, name, rank, rankIndex, level, zone, note, officerNote,
--           online, class, guid }
---------------------------------------------------------------------------
local roster, dirty, lastRequest = {}, true, -60
local byFirst = {} -- ["first-realm"] = full key, false when two members share it

local watching
local function rosterChanged()
    dirty = true
end

local function rebuild()
    if not watching then
        watching = true
        FF.On("GUILD_ROSTER_UPDATE", rosterChanged)
        FF.On("PLAYER_GUILD_UPDATE", rosterChanged)
    end
    roster, byFirst = {}, {}
    dirty = false
    if not IsInGuild() then
        return
    end
    local n = GetNumGuildMembers()
    if not readable(n) or not n then
        dirty = true
        return
    end
    for i = 1, n do
        local name, rank, rankIndex, level, _, zone, note, officerNote, online, _, class, _, _, mobile, _, _, guid =
            GetGuildRosterInfo(i)
        local display, key = FF.Identity(name)
        if key then
            local first = key:match("^(%a+)") and display:match("^(%S+)")
            local realm = key:match("%-(.+)$")
            if first and realm and display:find(" ", 1, true) then
                local short = first:lower() .. "-" .. realm
                byFirst[short] = byFirst[short] == nil and key or false
            end
            roster[key] = {
                index = i, name = display, rank = rank, rankIndex = rankIndex, level = level,
                zone = zone, note = note or "", officerNote = officerNote or "",
                online = online and not mobile, class = class, guid = guid,
            }
        end
    end
end

function FF.GuildRoster()
    if dirty then
        rebuild()
    end
    return roster
end

-- Forever names are "First Surname-Realm", but a sender can arrive as just
-- "First-Realm". Map that to the one guild / group member it belongs to.
function FF.CanonicalKey(key)
    if not key or key:find(" ", 1, true) then
        return key
    end
    local r = FF.GuildRoster()
    if r[key] then
        return key
    end
    local full = byFirst[key]
    if full then
        return full
    end
    local first, realm = key:match("^(.-)%-(.+)$")
    if first then
        local found
        for _, u in ipairs(FF.GroupUnits()) do
            local k = FF.UnitKey(u)
            if k and k:sub(1, #first) == first and k:match("%-(.+)$") == realm then
                if found and found ~= k then
                    return key -- ambiguous
                end
                found = k
            end
        end
        return found or key
    end
    return key
end

-- force: skip the 15 s throttle and rebuild from whatever the game has now
function FF.RequestGuildRoster(force)
    if not IsInGuild() or (not force and GetTime() - lastRequest < 15) then
        return
    end
    lastRequest = GetTime()
    dirty = dirty or force
    C_GuildInfo.GuildRoster()
end

-- One place watches zone changes; modules listen to FF_ZONE (no extra
-- game event registrations per module).
local function zoneChanged()
    FF.Fire("FF_ZONE")
end
FF.On("PLAYER_ENTERING_WORLD", zoneChanged)
FF.On("ZONE_CHANGED_NEW_AREA", zoneChanged)

function FF.InRaidInstance()
    return select(2, IsInInstance()) == "raid"
end

-- Inside a dungeon or raid instance
function FF.InGroupContent()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

