local _, FF = ...
local M = FF.Module("Profiles")

-- Profiles: named copies of every setting (module switches, positions and
-- each module's options). Each character picks a profile; switching swaps
-- the settings in before modules load. Shared data (nicknames, caches)
-- is never part of a profile.
--
-- FreshFixesDB.profiles[name] = { [dbKey] = { settings } }
-- FreshFixesDB.profileOf[charKey] = name, .activeProfile = name whose
-- settings are live in FreshFixesDB right now, .defaultProfile for new chars.
-- The first profile is always "Default", and a character with none yet uses it.
local KIND, SCHEMA = "PROFILE", 1
local DEFAULT_NAME = "Default"
local META = { profiles = true, profileOf = true, activeProfile = true, defaultProfile = true, pendingApply = true }
local DATA = {
    nicknames = { map = true, names = true, senders = true, mine = true },
    -- Raid assignment state — kept across reload, not part of a settings profile
    blessings = { assign = true, normal = true, aura = true },
}

local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, x in pairs(v) do
        t[k] = copy(x)
    end
    return t
end

local function isData(dbKey, field)
    return (type(field) == "string" and field:sub(1, 1) == "_") or (DATA[dbKey] and DATA[dbKey][field])
end

-- Settings currently live in FreshFixesDB
local function snapshot()
    local out = {}
    for dbKey, t in pairs(FreshFixesDB) do
        if not META[dbKey] and type(t) == "table" then
            local s = {}
            for field, v in pairs(t) do
                if not isData(dbKey, field) then
                    s[field] = copy(v)
                end
            end
            if next(s) then
                out[dbKey] = s
            end
        end
    end
    return out
end

-- Replace the live settings with a profile's (tables are kept, so anything
-- already holding FreshFixesDB.core stays valid).
local function apply(profile)
    for dbKey, t in pairs(FreshFixesDB) do
        if not META[dbKey] and type(t) == "table" then
            for field in pairs(t) do
                if not isData(dbKey, field) then
                    t[field] = nil
                end
            end
        end
    end
    for dbKey, s in pairs(profile) do
        if not META[dbKey] and type(s) == "table" then
            local t = FreshFixesDB[dbKey] or {}
            FreshFixesDB[dbKey] = t
            for field, v in pairs(s) do
                if not isData(dbKey, field) then
                    t[field] = copy(v)
                end
            end
        end
    end
    FreshFixesDB.core = FreshFixesDB.core or {}
    FreshFixesDB.core.modules = FreshFixesDB.core.modules or {}
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function store()
    local db = FreshFixesDB
    db.profiles = db.profiles or {}
    db.profileOf = db.profileOf or {}
    if not db.defaultProfile or db.defaultProfile == "" then
        db.defaultProfile = DEFAULT_NAME
    end
    return db
end

-- Save the live settings into the active profile, then load another.
local function switchTo(name)
    local db = store()
    db.profiles[db.activeProfile] = snapshot()
    if name ~= db.activeProfile then
        apply(db.profiles[name] or {})
        db.activeProfile = name
    end
    db.profiles[name] = db.profiles[name] or snapshot()
end

-- Core calls this at login, before any module loads.
-- Changes are never made to a running session: they are saved, the UI
-- reloads, and this applies them before modules read anything.
function FF.ProfileLogin()
    local db = store()
    if db.pendingApply then
        db.pendingApply = nil
        apply(db.profiles[db.activeProfile] or {})
    end
    local me = charKey()
    -- Older builds named the first profile after the character. Keep those
    -- settings and call the profile Default.
    if not db.profiles[DEFAULT_NAME] then
        local current = db.profileOf[me] or db.activeProfile
        if current == me and db.profiles[current] then
            db.profiles[DEFAULT_NAME] = db.profiles[current]
            db.profiles[current] = nil
            for char, name in pairs(db.profileOf) do
                if name == current then
                    db.profileOf[char] = DEFAULT_NAME
                end
            end
            if db.activeProfile == current then
                db.activeProfile = DEFAULT_NAME
            end
        end
    end
    local want = db.profileOf[me]
    if not want or (not db.profiles[want] and want ~= db.activeProfile) then
        local d = db.defaultProfile
        want = (d and d ~= "" and (db.profiles[d] or d == DEFAULT_NAME)) and d or DEFAULT_NAME
    end
    db.activeProfile = db.activeProfile or want -- first run: the live settings are fresh
    db.profileOf[me] = want
    switchTo(want)
end

function M.Current()
    return store().activeProfile
end

function M.Names()
    local names = {}
    for name in pairs(store().profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- JSON object keys must be strings: number keys travel as "#<n>".
local function pack(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, x in pairs(v) do
        t[type(k) == "number" and ("#" .. k) or tostring(k)] = pack(x)
    end
    return t
end

local function unpackKeys(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, x in pairs(v) do
        local n = type(k) == "string" and k:match("^#(%-?[%d%.]+)$")
        t[n and tonumber(n) or k] = unpackKeys(x)
    end
    return t
end

function M.Export(name)
    local db = store()
    if name == db.activeProfile then
        db.profiles[name] = snapshot()
    end
    return FF.Encode(KIND, SCHEMA, { name = name, author = UnitName("player"), settings = pack(db.profiles[name] or {}) })
end

-- Returns the new profile's name, or nil and an error.
function M.Import(text)
    local data, err = FF.Decode(text, KIND)
    if not data then
        return nil, err
    end
    if type(data.settings) ~= "table" then
        return nil, "Not a Fresh Fixes profile"
    end
    local db = store()
    local base = type(data.name) == "string" and data.name ~= "" and data.name or "Imported"
    local name, n = base, 2
    while db.profiles[name] do
        name = base .. " " .. n
        n = n + 1
    end
    local settings = unpackKeys(data.settings)
    for dbKey, s in pairs(settings) do
        if META[dbKey] or type(s) ~= "table" then
            settings[dbKey] = nil
        else
            for field in pairs(s) do
                if isData(dbKey, field) then
                    s[field] = nil
                end
            end
        end
    end
    db.profiles[name] = settings
    return name
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
FF.Init("Profiles", function()
    local db = store()
    local ui = { name = "" }

    local function choices()
        local list = {}
        for _, name in ipairs(M.Names()) do
            list[#list + 1] = { name, name }
        end
        return list
    end

    local function useProfile(name)
        db.profileOf[charKey()] = name
        ReloadUI()
    end

    FF.Settings("Profiles", function(L)
        L:Header("Profile for this character")
        local pick = { profile = db.activeProfile }
        L:Select("Profile", pick, "profile", choices, {
            tip = "Switching saves your current settings to the old profile, loads the new one and reloads the UI.",
            onChange = function()
                if pick.profile ~= db.activeProfile then
                    useProfile(pick.profile)
                end
            end,
        })
        L:Select("New characters use", db, "defaultProfile", choices, {
            tip = "A character that has no profile yet uses this one. The first profile is Default.",
        })
        L:Desc(("%s uses %s. Nicknames and other shared data stay the same in every profile.")
            :format(charKey(), FF.Hex(FF.C.accent) .. db.activeProfile .. "|r"))

        L:Header("New profile")
        L:Input("Name", ui, "name", { width = 200 })
        local function named()
            local name = ui.name and ui.name:match("^%s*(.-)%s*$") or ""
            if name == "" then
                return false, "Type a name for the new profile first."
            end
            if db.profiles[name] then
                return false, "A profile with that name already exists."
            end
            return true
        end
        local function create(blank)
            local ok, why = named()
            if not ok then
                FF.print(why)
                return
            end
            local name = ui.name:match("^%s*(.-)%s*$")
            db.profiles[db.activeProfile] = snapshot()
            db.profiles[name] = blank and {} or snapshot()
            ui.name = ""
            useProfile(name)
        end
        L:Buttons({
            { "Create", function() create(false) end, "New profile starting from your current settings (reloads)" },
            { "Start with defaults", function() create(true) end, "New profile with every setting at its default (reloads)" },
        })

        L:Header("Share a profile")
        L:Desc("Send a profile as a string, e.g. a raid leader's recommended setup.")
        L:Buttons({
            { "Export current", function()
                FF.ShowText("Profile: " .. db.activeProfile, M.Export(db.activeProfile))
            end },
            { "Import", function()
                FF.ShowText("Import profile", "", function(text)
                    local name, err = M.Import(text)
                    if not name then
                        return err
                    end
                    FF.print(("Imported profile %s - pick it under This character to use it."):format(name))
                    FF.RebuildSettings("Profiles")
                end)
            end },
            { "Reset current to defaults", function()
                db.profiles[db.activeProfile] = {}
                db.pendingApply = true
                ReloadUI()
            end, "Every setting in this profile back to default (reloads)" },
        })

        -- the other sections of this page
        for _, key in ipairs({ "Professions", "Guild" }) do
            local m = FF.modules[key]
            if m and m.Section then
                m.Section(L)
            end
        end
    end)
end)
