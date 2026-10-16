local ADDON, FF = ...
_G.FreshFixes = FF

FF.version = C_AddOns.GetAddOnMetadata(ADDON, "Version")


local function print_(...)
    print("|cff66ccffFresh Fixes|r", ...)
end
FF.print = print_

-- Forever can hand out "secret" values in combat; never compare or index one.
local issecret = issecretvalue
local function readable(v)
    return not (issecret and issecret(v))
end
FF.readable = readable

---------------------------------------------------------------------------
-- Events: one frame for the whole addon. Names starting with "FF_" are
-- internal messages and are never registered with the game.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

local function dispatch(event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    -- Backwards so a handler may remove itself.
    for i = #list, 1, -1 do
        list[i](event, ...)
    end
end
frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(event, ...)
end)

function FF.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not event:find("^FF_") then
            pcall(frame.RegisterEvent, frame, event) -- unknown events on this client are ignored
        end
    end
    list[#list + 1] = fn
    return fn
end

function FF.Off(event, fn)
    local list = handlers[event]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == fn then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        handlers[event] = nil
        if not event:find("^FF_") then
            pcall(frame.UnregisterEvent, frame, event)
        end
    end
end

FF.Fire = dispatch

-- Attach or detach a handler as a feature turns on/off. The game event is
-- only registered while something listens to it.
function FF.Listen(event, fn, on)
    local list, has = handlers[event], false
    for _, f in ipairs(list or {}) do
        if f == fn then
            has = true
        end
    end
    if on and not has then
        FF.On(event, fn)
    elseif not on and has then
        FF.Off(event, fn)
    end
end

---------------------------------------------------------------------------
-- Character identity. Forever's UnitFullName returns first, surname, realm
-- (realm nil for your own realm). Key = "first surname-realm" lowercased
-- with whitespace removed; display = as the game shows it.
---------------------------------------------------------------------------
local function homeRealm()
    local realm = GetNormalizedRealmName()
    if not readable(realm) or not realm or realm == "" then
        realm = GetRealmName()
    end
    if readable(realm) and type(realm) == "string" and realm ~= "" then
        return realm
    end
end

-- "Name" or "Name-Realm" or "First Surname-Realm" -> display, key
function FF.Identity(name, realm)
    if not readable(name) or type(name) ~= "string" or name == "" then
        return
    end
    if not name:find("-", 1, true) then
        if not readable(realm) then
            return
        end
        if not realm or realm == "" then
            realm = homeRealm()
        end
        if type(realm) ~= "string" then
            return
        end
        name = name .. "-" .. realm:gsub("%s", "")
    end
    return name, (name:gsub("%s", ""):lower())
end

-- A spell's cooldown: start, duration (nothing when ready). Third value is
-- true when the times are hidden from addons (combat).
function FF.SpellCooldown(spell)
    local cd = C_Spell.GetSpellCooldown(spell)
    local start, duration = cd and cd.startTime, cd and cd.duration
    if not (readable(start) and readable(duration)) then
        return nil, nil, true
    end
    if start and duration and duration > 0 then
        return start, duration
    end
end

-- Friend or guild member (by "Name" / "Name-Realm")
function FF.IsFriendOrGuild(name)
    if not name or not readable(name) then
        return false
    end
    local key = FF.Key(name)
    if key and FF.GuildRoster()[key] then
        return true
    end
    local ok, friend = pcall(C_FriendList.IsFriend, name)
    return ok and friend or false
end

function FF.Key(name, realm)
    local _, key = FF.Identity(name, realm)
    return key
end

-- Each Forever client puts its OWN realm on every character ("ClassicBetaPvE"
-- on one, "ClassicBetaPvE2" on another), so a realm written on one client
-- means nothing on the next. Compare characters by name without the realm
-- (Forever names are "First Surname", so that's as good as unique).
function FF.BareKey(key)
    return type(key) == "string" and (key:match("^(.-)%-") or key) or nil
end

function FF.SameChar(a, b)
    return a ~= nil and b ~= nil and (a == b or FF.BareKey(a) == FF.BareKey(b))
end

function FF.UnitIdentity(unit)
    local first, surname, realm = UnitFullName(unit)
    if not (readable(first) and readable(surname) and readable(realm)) or type(first) ~= "string" or first == "" then
        return
    end
    local name = first
    if type(surname) == "string" and surname ~= "" then
        name = first .. " " .. surname
    end
    return FF.Identity(name, realm)
end

function FF.UnitKey(unit)
    local _, key = FF.UnitIdentity(unit)
    return key
end

---------------------------------------------------------------------------
-- Saved variables. Each module gets FreshFixesDB[key]; flat defaults are
-- served through __index so only changed values are ever written.
-- Nested tables must be created by the module itself.
---------------------------------------------------------------------------
function FF.DB(key, defaults)
    local db = FreshFixesDB[key] or {}
    FreshFixesDB[key] = db
    if defaults then
        setmetatable(db, { __index = defaults })
    end
    return db
end

---------------------------------------------------------------------------
-- Modules: every feature lives in this one addon, but a module's files only
-- register init functions. Those run at login for enabled modules only, so a
-- disabled module creates no frames, events, tables or saved data.
---------------------------------------------------------------------------
FF.catalog = {
    { key = "Profiles", icon = "Interface\\Icons\\INV_Misc_Gear_01", default = true, core = true, title = "General", desc = "Setting profiles, professions export for the website, and guild roster export." },
    { key = "Nicknames", icon = "Interface\\Icons\\INV_Misc_Note_02", default = true, title = "Nicknames", desc = "Guild-shared nicknames, used by raid frames, groups and tooltips." },
    { key = "Groups", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", default = false, title = "Group Setup", desc = "Import and apply raid group layouts, auto-assist and always-mark players." },
    { key = "Consumes", icon = "Interface\\Icons\\INV_Potion_54", default = false, title = "Consumes", desc = "Checks flask/food/weapon buffs on ready check and reports to the lead." },
    { key = "Gear", icon = "Interface\\Icons\\INV_Chest_Plate16", default = false, title = "Gear Check", desc = "Missing enchants, gems, empty slots and item level on ready check; raid summary." },
    { key = "Cooldowns", icon = "Interface\\Icons\\Spell_Holy_DivineIntervention", default = false, title = "Raid Cooldowns", desc = "Tracks raid cooldowns shared by everyone running Fresh Fixes." },
    { key = "QoL", icon = "Interface\\Icons\\INV_Misc_Wrench_01", default = true, title = "Quality of Life", desc = "Auto-repair, sell junk, faster loot and other Leatrix-style tweaks." },
    { key = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01", default = true, title = "Map", desc = "Unexplored areas, map icons, scale, fade and unlocking the world map." },
    { key = "MouseRing", icon = "Interface\\Icons\\Ability_Marksmanship", default = false, title = "Mouse Ring", desc = "Rings around the cursor: plain, global cooldown, cast bar or spell cooldown, plus trail and melee warning." },
    { key = "CoTank", icon = "Interface\\Icons\\INV_Shield_06", default = false, title = "Co-Tank Frame", desc = "Small clickable frame for the other tank." },
    { key = "Summon", icon = "Interface\\Icons\\Spell_Shadow_Twilight", default = false, title = "Summons", desc = "Ritual of Summoning announcements and a '123' summon queue." },
    { key = "Resurrect", icon = "Interface\\Icons\\Spell_Holy_Resurrection", default = false, title = "Resurrections", desc = "After a boss: bars showing who is resurrecting whom, plus announcing your own resurrections." },
    { key = "DropCheapest", icon = "Interface\\Icons\\INV_Misc_Bag_10", default = false, title = "Drop Cheapest", desc = "Button and /ff drop to delete the cheapest junk item in your bags (greys first, confirms anything better)." },
    { key = "Blessings", icon = "Interface\\Icons\\Spell_Holy_FistOfJustice", default = false, title = "Blessings", desc = "PallyPower-compatible paladin blessing assignments, smart auto-assign and a click-to-buff helper." },
    { key = "NpcMarks", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", default = false, title = "Auto-mark NPCs", desc = "Mark mobs by NPC ID when you hover them while holding a key." },
    { key = "Waypoints", icon = "Interface\\Icons\\Ability_Tracking", default = false, title = "Waypoints", desc = "Built-in in-world waypoint that follows the current RestedXP guide step, plus /ff way." },
}
FF.modules = {}
local inits = {} -- [key] = { fn, fn, ... } in file order

function FF.Module(key)
    local m = FF.modules[key] or { key = key }
    FF.modules[key] = m
    return m
end

-- Called at file scope by each module file.
function FF.Init(key, fn)
    local list = inits[key] or {}
    inits[key] = list
    list[#list + 1] = fn
end

local function enabled(entry)
    if entry.core then
        return true
    end
    local v = FF.core.modules[entry.key]
    if v == nil then
        return entry.default
    end
    return v
end
FF.IsEnabled = function(key)
    for _, e in ipairs(FF.catalog) do
        if e.key == key then
            return enabled(e)
        end
    end
end

local function loadModules()
    local onError = geterrorhandler()
    for _, e in ipairs(FF.catalog) do
        local list = inits[e.key]
        if list and enabled(e) then
            for _, fn in ipairs(list) do
                xpcall(fn, onError)
            end
            FF.Module(e.key).loaded = true
        end
        inits[e.key] = list and true or nil -- free the closures, remember it exists
    end
end

---------------------------------------------------------------------------
-- Slash commands: modules register sub-commands with FF.Command.
---------------------------------------------------------------------------
local commands, order = {}, {}
function FF.Command(name, fn, help)
    if not commands[name] then
        order[#order + 1] = name
    end
    commands[name] = { fn = fn, help = help }
end

local function slash(msg)
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local c = commands[cmd]
    if c then
        c.fn(rest)
        return
    end
    if cmd == "" and FF.ShowOptions then
        FF.ShowOptions()
        return
    end
    print_("v" .. FF.version .. " - /ff opens the settings window")
    for _, name in ipairs(order) do
        print("  /ff " .. name .. (commands[name].help and (" - " .. commands[name].help) or ""))
    end
end
-- Run a /ff command from code (settings buttons use the same paths as chat).
function FF.Run(msg)
    slash(msg)
end

SLASH_FRESHFIXES1, SLASH_FRESHFIXES2 = "/ff", "/freshfixes"
SlashCmdList.FRESHFIXES = slash

FF.Command("modules", function(rest)
    local key, state = rest:match("^(%S+)%s*(%S*)$")
    if key then
        for _, e in ipairs(FF.catalog) do
            if e.key:lower() == key:lower() then
                local on = state == "on" or (state ~= "off" and not enabled(e))
                FF.core.modules[e.key] = on
                print_(e.key, on and "enabled" or "disabled", "- /reload to apply")
                return
            end
        end
    end
    for _, e in ipairs(FF.catalog) do
        print(("  %s: %s%s"):format(e.key, enabled(e) and "|cff00ff00on|r" or "|cffff4040off|r",
            inits[e.key] and "" or " (not built yet)"))
    end
end, "list modules, or 'modules <name> on|off'")

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
local function onLoaded(event, name)
    if name ~= ADDON then
        return
    end
    FF.Off(event, onLoaded)
    FreshFixesDB = FreshFixesDB or {}
    FF.core = FF.DB("core")
    FF.core.modules = FF.core.modules or {}
end
FF.On("ADDON_LOADED", onLoaded)

local function onLogin(event)
    FF.Off(event, onLogin)
    FF.ApplyFonts() -- EllesmereUI's font settings are loaded by now
    FF.ProfileLogin() -- swap in this character's profile before anything reads settings
    loadModules()
    FF.Fire("FF_READY")
end
FF.On("PLAYER_LOGIN", onLogin)
