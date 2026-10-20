local _, FF = ...
local M = FF.Module("Graphics")

-- Graphics / visibility CVars with Forever Visibility-style presets.
-- Catalog lives in GraphicsCatalog.lua. Applies at login when enabled.
FF.Init("Graphics", function()
    local Cat = FF.GraphicsCatalog
    if not Cat then
        return
    end

    local db = FF.DB("graphics", {
        applyAtLogin = true,
        raid = true,
        chat = false,
        -- false = Off (don't manage). 0..4 = Max visibility … Max graphics.
        preset = false,
    })
    db.values = db.values or {}
    db.manage = db.manage or {}
    db.originals = db.originals or {}

    local EPSILON = 1e-4
    local pending, applying, verifyQueued = false, false, false

    local function printChat(msg)
        if db.chat then
            FF.print(msg)
        end
    end

    local SECURE_WRITABLE = {}
    for _, entry in ipairs(Cat.ENTRIES) do
        if entry.trySecure then
            SECURE_WRITABLE[entry.cvar:lower()] = true
        end
    end

    local function Number(text)
        if type(text) == "number" then
            return text
        end
        if type(text) ~= "string" then
            return nil
        end
        return tonumber(text) or tonumber(text:match("^%s*(%-?[%d%.]+)%s*,"))
    end

    local function Same(a, b)
        local x, y = Number(a), Number(b)
        if x and y then
            return math.abs(x - y) < EPSILON
        end
        return a == b
    end

    local function Probe(cvar)
        local value, default, _, _, locked, secure, readOnly = C_CVar.GetCVarInfo(cvar)
        local info = { value = type(value) == "string" and value or nil, default = default }
        if not info.value then
            return "missing", info
        end
        if (secure and not SECURE_WRITABLE[cvar:lower()]) or locked then
            return "protected", info
        end
        if readOnly then
            return "readonly", info
        end
        return "ok", info
    end

    local function RememberOriginal(cvar, value)
        if type(cvar) == "string" and type(value) == "string" and db.originals[cvar] == nil then
            db.originals[cvar] = value
        end
    end

    local function Write(cvar, text)
        local state, info = Probe(cvar)
        if state ~= "ok" then
            return state, info.value
        end
        if Same(info.value, text) then
            return "same", info.value
        end
        RememberOriginal(cvar, info.value)
        local ok = C_CVar.SetCVar(cvar, text)
        local now = C_CVar.GetCVar(cvar)
        if Same(now, text) then
            return "changed", now
        end
        if ok ~= true then
            return "rejected", now
        end
        return "clamped", now
    end

    local function Limits(entry)
        if entry.limits == "fov" and type(GetCameraFOVDefaults) == "function" then
            local _, low, high = GetCameraFOVDefaults()
            if type(low) == "number" and type(high) == "number" and low < high then
                return low, high
            end
        end
        return entry.min, entry.max
    end

    local function Snap(entry, value)
        local low, high = Limits(entry)
        if type(low) ~= "number" or type(high) ~= "number" then
            return value
        end
        value = math.max(low, math.min(high, value))
        local step = entry.step or 1
        value = low + math.floor((value - low) / step + 0.5) * step
        return math.min(high, value)
    end

    local function FormatNumber(value)
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        return (string.format("%.4f", value):gsub("0+$", ""))
    end

    local function Encode(entry, value)
        if entry.kind == "bool" then
            return (value ~= (entry.invert == true)) and "1" or "0"
        end
        return FormatNumber(value)
    end

    local function Decode(entry, text)
        local number = Number(text)
        if not number then
            return nil
        end
        if entry.kind == "bool" then
            return (number ~= 0) ~= (entry.invert == true)
        end
        return number
    end

    local function IsSupported(entry)
        return not entry.supported or entry.supported()
    end

    local function PresetValue(entry, index)
        if entry.personal then
            return nil
        end
        local value = entry.best
        for level = 1, index or 0 do
            if entry.levels and entry.levels[level] ~= nil then
                value = entry.levels[level]
            end
        end
        return value
    end

    local function IsManaged(entry)
        local flag = db.manage[entry.key]
        if flag == nil then
            return entry.best ~= nil
        end
        return flag
    end

    local function GetValue(entry)
        local own = db.values[entry.key]
        if own ~= nil then
            return own
        end
        if entry.personal then
            return nil
        end
        local preset = db.preset
        if type(preset) ~= "number" then
            return nil
        end
        return PresetValue(entry, preset)
    end

    local function Target(entry)
        local value = GetValue(entry)
        if value == nil then
            return nil
        end
        if entry.kind == "bool" then
            return value
        end
        if value == "max" then
            return select(2, Limits(entry))
        end
        if type(value) ~= "number" then
            return nil
        end
        if entry.kind == "choice" then
            for _, option in ipairs(entry.values) do
                if option == value then
                    return value
                end
            end
            return entry.best
        end
        return Snap(entry, value)
    end

    local function RestoreOriginal(cvar)
        local value = cvar and db.originals[cvar]
        if value == nil then
            return false
        end
        db.originals[cvar] = nil
        local state, info = Probe(cvar)
        if state ~= "ok" or Same(info.value, value) then
            return false
        end
        C_CVar.SetCVar(cvar, value)
        return true
    end

    local function ApplyOutlinesOff(entry, sparkleOn)
        local outlines = entry.outlinesOff and Cat.BY_KEY[entry.outlinesOff]
        if not outlines or IsSupported(outlines) then
            return false
        end
        local changed = false
        for _, cvar in ipairs({ outlines.cvar, outlines.raid }) do
            if sparkleOn then
                if (cvar == outlines.cvar or db.raid) and Write(cvar, "0") == "changed" then
                    changed = true
                end
            elseif RestoreOriginal(cvar) then
                changed = true
            end
        end
        return changed
    end

    local function ApplyEntry(entry)
        if not IsSupported(entry) then
            return false
        end
        local value
        if IsManaged(entry) then
            value = Target(entry)
        end
        if value == nil then
            local restored = RestoreOriginal(entry.cvar)
            restored = ApplyOutlinesOff(entry, false) or restored
            return RestoreOriginal(entry.raid) or restored
        end
        local text = Encode(entry, value)
        local state = Write(entry.cvar, text)
        local changed = state == "changed"
        if entry.raid and db.raid then
            local rs = Write(entry.raid, text)
            changed = changed or rs == "changed"
        end
        if entry.outlinesOff then
            local written = state == "changed" or state == "same" or state == "clamped"
            changed = ApplyOutlinesOff(entry, value == true and written) or changed
        end
        return changed
    end

    local ApplyAll
    local function afterCombat()
        if pending then
            ApplyAll()
        end
    end

    function ApplyAll(verifying)
        if type(db.preset) ~= "number" and next(db.values) == nil then
            return 0
        end
        pending = InCombatLockdown() and true or false
        FF.Listen("PLAYER_REGEN_ENABLED", afterCombat, pending) -- only while a change waits
        if pending then
            return nil
        end
        applying = true
        for _, entry in ipairs(Cat.ENTRIES) do
            if IsManaged(entry) and IsSupported(entry) then
                for _, cvar in ipairs({ entry.cvar, db.raid and entry.raid or nil }) do
                    local state, info = Probe(cvar)
                    if state == "ok" then
                        RememberOriginal(cvar, info.value)
                    end
                end
            end
        end
        local changed, presetChanged = 0, false
        for pass = 1, 2 do
            for _, entry in ipairs(Cat.ENTRIES) do
                if (pass == 1) == (entry.preset == true) and ApplyEntry(entry) then
                    changed = changed + 1
                    if pass == 1 then
                        presetChanged = true
                    end
                end
            end
        end
        applying = false
        if presetChanged and not verifying and not verifyQueued then
            verifyQueued = true
            C_Timer.After(1, function()
                verifyQueued = false
                ApplyAll(true)
            end)
        end
        return changed
    end

    local function SetPreset(index)
        if type(index) ~= "number" or not Cat.PRESETS[index] then
            return false
        end
        for key in pairs(db.values) do
            local entry = Cat.BY_KEY[key]
            if not (entry and entry.personal) then
                db.values[key] = nil
            end
        end
        for key in pairs(db.manage) do
            local entry = Cat.BY_KEY[key]
            if not (entry and entry.personal) then
                db.manage[key] = nil
            end
        end
        db.preset = index
        return true
    end

    local function Choose(entry, value)
        db.values[entry.key] = value
        db.manage[entry.key] = true
        local preset = db.preset
        if not entry.personal and type(preset) == "number" then
            local pv = PresetValue(entry, preset)
            if type(value) == "number" and type(pv) == "number" and math.abs(value - pv) < 1e-6 then
                db.values[entry.key] = nil
            elseif value == pv then
                db.values[entry.key] = nil
            end
        end
        if not applying then
            ApplyEntry(entry)
        end
    end

    local function RestoreAll()
        if InCombatLockdown() then
            FF.print("Graphics: restore unavailable in combat")
            return
        end
        db.preset = false
        wipe(db.values)
        wipe(db.manage)
        applying = true
        for pass = 1, 2 do
            for _, entry in ipairs(Cat.ENTRIES) do
                if (pass == 1) == (entry.preset == true) then
                    RestoreOriginal(entry.cvar)
                    RestoreOriginal(entry.raid)
                end
            end
        end
        for cvar in pairs(db.originals) do
            RestoreOriginal(cvar)
        end
        applying = false
        printChat("Graphics: restored originals")
    end

    local function ApplyPicture(choiceKey)
        for _, choice in ipairs(Cat.PICTURE_CHOICES) do
            if choice.key == choiceKey then
                for key, value in pairs(choice.values) do
                    local entry = Cat.BY_KEY[key]
                    if entry then
                        Choose(entry, value)
                    end
                end
                return
            end
        end
    end

    -- Settings proxies so Layout:Slider/Toggle/Select can bind db.values[key].
    local proxies = {}
    local function proxyFor(entry)
        local p = proxies[entry.key]
        if p then
            return p
        end
        p = {}
        setmetatable(p, {
            __index = function(_, k)
                if k ~= "v" then
                    return nil
                end
                local v = GetValue(entry)
                if v ~= nil then
                    return v
                end
                if entry.kind == "bool" then
                    local state, info = Probe(entry.cvar)
                    if state ~= "missing" then
                        return Decode(entry, info.value)
                    end
                    return entry.best
                end
                if entry.best == "max" then
                    return select(2, Limits(entry))
                end
                return entry.best or entry.min or 0
            end,
            __newindex = function(_, k, v)
                if k == "v" then
                    Choose(entry, v)
                end
            end,
        })
        proxies[entry.key] = p
        return p
    end

    local function choiceOptions(entry)
        local list = {}
        for _, v in ipairs(entry.values) do
            list[#list + 1] = { v, entry.labels and entry.labels[v] or tostring(v) }
        end
        return list
    end

    M.Apply = function()
        local n = ApplyAll()
        if n == nil then
            FF.print("Graphics: will apply after combat")
            return
        end
        printChat(("Graphics: applied (%d changed)"):format(n))
    end

    FF.On("FF_READY", function()
        if db.applyAtLogin and (type(db.preset) == "number" or next(db.values)) then
            C_Timer.After(1, function()
                ApplyAll()
            end)
        end
    end)

    FF.Command("graphics", function(arg)
        arg = (arg or ""):lower()
        if arg == "apply" then
            M.Apply()
        elseif arg == "restore" then
            RestoreAll()
        else
            FF.print("graphics apply | restore")
        end
    end, "graphics presets (apply, restore)")

    FF.Settings("Graphics", function(L)
        L:Header("Presets")
        L:Desc("From Forever Visibility: stepped presets from clearest to prettiest. Personal rows (brightness, names, interact) are never overwritten by a preset.")
        L:Select("Preset", db, "preset", {
            { false, "Off (don't manage)" },
            { 0, "Max visibility" },
            { 1, "Free only" },
            { 2, "Balanced" },
            { 3, "Scenic" },
            { 4, "Max graphics" },
        }, {
            width = 200,
            tip = Cat.PRESETS[0] and Cat.PRESETS[0].tip,
            onChange = function()
                if type(db.preset) == "number" then
                    SetPreset(db.preset)
                    M.Apply()
                end
            end,
        })
        L:Toggle("Apply at login", db, "applyAtLogin")
        L:Toggle("Also set Raid / Battleground graphics", db, "raid", {
            tip = "Writes each setting's raidGraphics* / RAID* twin when the client has one.",
            onChange = function()
                if type(db.preset) == "number" then
                    M.Apply()
                end
            end,
        })
        L:Toggle("Chat messages when applying", db, "chat")
        L:Buttons({
            { "Apply now", function()
                M.Apply()
            end },
            { "Restore originals", function()
                RestoreAll()
            end, "Puts back values from before Fresh Fixes changed them" },
        })

        L:Header("Your picture")
        L:Buttons({
            { "Suggested", function()
                ApplyPicture("suggested")
            end, "Brightness 50, contrast 85, gamma 1.5" },
            { "Blizzard default", function()
                ApplyPicture("blizzard")
            end, "Brightness 50, contrast 50, gamma 1.0" },
        })

        for _, section in ipairs(Cat.SECTIONS) do
            L:Header(section.title or "?")
            if section.note then
                L:Desc(section.note)
            end
            for _, entry in ipairs(section.entries) do
                if IsSupported(entry) then
                    local px = proxyFor(entry)
                    if entry.kind == "bool" then
                        L:Toggle(entry.label, px, "v", { tip = entry.tip })
                    elseif entry.kind == "choice" then
                        L:Select(entry.label, px, "v", choiceOptions(entry), { tip = entry.tip, width = 160 })
                    else
                        local low, high = Limits(entry)
                        L:Slider(entry.label, px, "v", low or entry.min or 0, high or entry.max or 1, entry.step or 1, {
                            tip = entry.tip, fmt = entry.format,
                        })
                    end
                end
            end
        end
    end)
end)
