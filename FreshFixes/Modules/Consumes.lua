local _, FF = ...
local M = FF.Module("Consumes")

-- Ready check consumables (Nova Consumes / Northern Sky style):
--   * checks flask, elixir, food, weapon buff (and expiring ones), healthstone,
--     missing raid buffs and durability
--   * shows a clickable bar of the consumables you carry so one click rebuffs
--   * "Raid check" asks every Fresh Fixes user to report; a window lists them
-- Comms tag "C": S<flags>  (flags = letters of categories you HAVE)
FF.Init("Consumes", function()
    local readable = FF.readable
    local db = FF.DB("consumes", {
        flask = true, elixir = false, food = true, weapon = true, healthstone = true,
        raidBuffs = true, durability = true, bar = true,
        onReadyCheck = true, onRaidZone = true, raidTimer = false, raidInterval = 120, barTips = false,
        minMinutes = 5, minDurability = 30,
        raidWarning = false, sound = false, soundKit = "RAID_WARNING",
        barSize = 36, barSeconds = 30, barLabel = false,
        barSpacing = 0, barActive = "hide", barMode = "check", barBorder = 0,
    })
    db.extra = db.extra or {} -- [cat] = { ids = {[id]=true}, names = {[lower]=true} }
    db.items = db.items or {} -- [cat] = { itemID, ... } extra items for the click bar

    -- Buff names / spell IDs / items per category (more can be added in settings;
    -- /ff cons buffs lists your buffs with their spell IDs).
    local CATS = {
        { key = "flask", flag = "F", label = "Flask", short = "Flask",
          names = { "flask", "supreme power", "distilled wisdom", "chromatic resistance" },
          ids = { 17626, 17627, 17628, 17629 },
          items = { 13510, 13511, 13512, 13513 } },
        { key = "elixir", flag = "E", label = "Elixir", short = "Elixir",
          names = { "elixir", "mongoose", "greater agility", "giants", "greater arcane", "shadow power", "greater firepower" },
          ids = { 17538, 11405, 11334, 17539, 11348, 11474, 26276, 3593, 24363 },
          -- Forever additions first: Owl, Whale, Grizzly, Cunning, Minor Arcane
          items = { 250337, 250348, 250351, 250328, 247754, 13452, 9206, 9187, 13454, 13445, 9264, 21546 } },
        { key = "food", flag = "D", label = "Food", short = "Food", names = { "well fed" }, ids = {}, icon = 136000, items = {} },
    }
    local WEAPON = { key = "weapon", flag = "W", label = "Weapon buff", short = "Weapon", items = { 20749, 20748, 18262, 12404, 12643, 23122, 23123 } }
    local HEALTHSTONE = { key = "healthstone", flag = "H", label = "Healthstone",
        items = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 } }

    -- Raid buffs: buff names (any rank/group version) -> provider class
    local RAID_BUFFS = {
        { class = "MAGE", label = "Intellect", names = { "arcane intellect", "arcane brilliance" } },
        { class = "PRIEST", label = "Stamina", names = { "power word: fortitude", "prayer of fortitude" } },
        { class = "DRUID", label = "Mark of the Wild", names = { "mark of the wild", "gift of the wild" } },
        { class = "WARRIOR", label = "Battle Shout", names = { "battle shout" } },
    }

    local function lookup(cat)
        local ids, names = {}, {}
        for _, id in ipairs(cat.ids) do
            ids[id] = true
        end
        for _, n in ipairs(cat.names) do
            names[#names + 1] = n
        end
        local x = db.extra[cat.key]
        if x then
            for id in pairs(x.ids or {}) do
                ids[id] = true
            end
            for n in pairs(x.names or {}) do
                names[#names + 1] = n
            end
        end
        return ids, names
    end

    local function itemCount(id)
        local n = C_Item.GetItemCount(id, false, false, false, false)
        return readable(n) and n or 0
    end

    local function groupHasClass(class)
        for _, u in ipairs(FF.GroupUnits()) do
            if select(2, UnitClass(u)) == class then
                return true
            end
        end
    end

    -- Returns has (set of flags), expiring (set of flags), missingBuffs (list),
    -- lowDurability (number or nil) - or nil when buffs can't be read now.
    function M.Scan()
        if InCombatLockdown() then
            return
        end
        if C_Secrets.ShouldAurasBeSecret() then
            return
        end
        local has, expiring, buffNames = {}, {}, {}
        local lookups = {}
        for i, cat in ipairs(CATS) do
            lookups[i] = { lookup(cat) }
        end
        local now, minLeft = GetTime(), db.minMinutes * 60
        for i = 1, 60 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then
                break
            end
            if not (readable(a.name) and readable(a.spellId) and readable(a.icon)) then
                return
            end
            local lname = (a.name or ""):lower()
            buffNames[lname] = true
            for c, cat in ipairs(CATS) do
                local ids, names = lookups[c][1], lookups[c][2]
                local hit = ids[a.spellId] or (cat.icon and a.icon == cat.icon)
                if not hit then
                    for _, n in ipairs(names) do
                        if lname:find(n, 1, true) then
                            hit = true
                            break
                        end
                    end
                end
                if hit then
                    has[cat.flag] = true
                    if readable(a.expirationTime) and a.expirationTime and a.expirationTime > 0
                        and a.expirationTime - now < minLeft then
                        expiring[cat.flag] = true
                    end
                end
            end
        end
        local mh, mhExpires = GetWeaponEnchantInfo()
        if readable(mh) and mh then
            has.W = true
            if readable(mhExpires) and mhExpires and mhExpires / 1000 < minLeft then
                expiring.W = true
            end
        end
        for _, id in ipairs(HEALTHSTONE.items) do
            if itemCount(id) > 0 then
                has.H = true
                break
            end
        end
        local missingBuffs = {}
        if db.raidBuffs then
            for _, b in ipairs(RAID_BUFFS) do
                if groupHasClass(b.class) then
                    local found = false
                    for _, n in ipairs(b.names) do
                        if buffNames[n] then
                            found = true
                        end
                    end
                    if not found then
                        missingBuffs[#missingBuffs + 1] = b.label
                    end
                end
            end
        end
        local low
        if db.durability then
            for slot = 1, 18 do
                local cur, max = GetInventoryItemDurability(slot)
                if cur and max and max > 0 then
                    local pct = cur / max * 100
                    if pct < db.minDurability then
                        low = math.min(low or 100, math.floor(pct))
                    end
                end
            end
        end
        return has, expiring, missingBuffs, low
    end

    local function wanted()
        local list = {}
        for _, cat in ipairs(CATS) do
            if db[cat.key] then
                list[#list + 1] = cat
            end
        end
        if db.weapon then
            list[#list + 1] = WEAPON
        end
        if db.healthstone and groupHasClass("WARLOCK") then
            list[#list + 1] = HEALTHSTONE
        end
        return list
    end

    local function problems(has, expiring, missingBuffs, low)
        local out = {}
        for _, cat in ipairs(wanted()) do
            if not has[cat.flag] then
                out[#out + 1] = cat.label
            elseif expiring[cat.flag] then
                out[#out + 1] = cat.label .. " (expiring)"
            end
        end
        for _, b in ipairs(missingBuffs or {}) do
            out[#out + 1] = b
        end
        if low then
            out[#out + 1] = ("Durability %d%%"):format(low)
        end
        return out
    end

    local function flagString(has, expiring)
        local s = ""
        for f in pairs(has) do
            if not expiring[f] then
                s = s .. f
            end
        end
        return s
    end

    ---------------------------------------------------------------------------
    -- Click bar: one button per category you need and carry an item for
    ---------------------------------------------------------------------------
    local bar
    local function itemsFor(cat)
        local list = {}
        for _, id in ipairs(db.items[cat.key] or {}) do
            list[#list + 1] = id
        end
        for _, id in ipairs(cat.items or {}) do
            list[#list + 1] = id
        end
        return list
    end

    local function showBar(has, expiring)
        if not db.bar or InCombatLockdown() then
            return
        end
        if not bar then
            bar = CreateFrame("Frame", "FreshFixesConsumeBar", UIParent)
            bar:SetSize(10, 40)
            FF.RestorePosition(bar, "ConsumeBar", "CENTER", 0, 160)
            bar:SetMovable(true)
            bar:EnableMouse(true)
            bar:RegisterForDrag("LeftButton")
            bar:SetScript("OnDragStart", bar.StartMoving)
            bar:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                FF.SavePosition(self, "ConsumeBar")
            end)
            bar.buttons = {}
        end
        local n = 0
        for _, cat in ipairs(wanted()) do
            local need = not has[cat.flag] or expiring[cat.flag]
            if cat ~= HEALTHSTONE and (need or db.barActive == "grey") then
                for _, id in ipairs(itemsFor(cat)) do
                    if itemCount(id) > 0 then
                        n = n + 1
                        local b = bar.buttons[n]
                        if not b then
                            b = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
                            FF.Skin(b, "row")
                            b:RegisterForClicks("AnyUp", "AnyDown")
                            b.tex = b:CreateTexture(nil, "ARTWORK")
                            b.tex:SetAllPoints()
                            b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                            b.count:SetPoint("BOTTOMRIGHT", -2, 2)
                            b.tick = b:CreateTexture(nil, "OVERLAY")
                            b.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                            b.tick:SetPoint("CENTER")
                            b.cap = FF.Text(b, "small") -- short type name above the icon
                            b.cap:SetPoint("BOTTOM", b, "TOP", 0, 2)
                            b:SetScript("OnEnter", function(self)
                                if not db.barTips then
                                    return
                                end
                                local id = self.itemID
                                local name = C_Item.GetItemNameByID(id) or ("Item " .. tostring(id))
                                local count = C_Item.GetItemCount(id)
                                FF.Tip(self, ("%d in bags - click to use"):format(count or 0), name)
                            end)
                            b:SetScript("OnLeave", FF.HideTip)
                            bar.buttons[n] = b
                        end
                        b.itemID = id
                        b.cap:SetText(cat.short or cat.label)
                        b.cap:SetShown(db.barLabel)
                        if not need then
                            b:SetAttribute("type", nil) -- buff is up: greyed out, does nothing
                        elseif cat == WEAPON then
                            b:SetAttribute("type", "macro")
                            b:SetAttribute("macrotext", "/use item:" .. id .. "\n/use 16")
                        else
                            b:SetAttribute("type", "item")
                            b:SetAttribute("item", "item:" .. id)
                        end
                        b.tex:SetTexture(C_Item.GetItemIconByID(id) or 134400)
                        b.tex:SetDesaturated(not need)
                        b.tex:SetAlpha(need and 1 or 0.45)
                        b.tick:SetShown(not need)
                        b.count:SetText(itemCount(id))
                        b:Show()
                        break
                    end
                end
            end
        end
        for i = n + 1, #bar.buttons do
            bar.buttons[i]:Hide()
        end
        local size, gap = db.barSize, db.barSpacing
        for i = 1, n do
            local b = bar.buttons[i]
            b:SetSize(size, size)
            b.tick:SetSize(size * 0.6, size * 0.6)
            b:ClearAllPoints()
            b:SetPoint("LEFT", (i - 1) * (size + gap), 0)
            -- border = the button's background showing around the icon (0-3px)
            local bw = db.barBorder
            for _, e in ipairs(b.ffEdges or {}) do
                e:Hide()
            end
            FF.SetBg(b, bw > 0 and FF.C.border or { 0, 0, 0, 0 })
            b.tex:ClearAllPoints()
            b.tex:SetPoint("TOPLEFT", bw, -bw)
            b.tex:SetPoint("BOTTOMRIGHT", -bw, bw)
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        bar:SetSize(math.max(10, n * size + math.max(0, n - 1) * gap), size)
        bar:SetShown(n > 0)
    end

    local function hideBar()
        if bar and not InCombatLockdown() then
            bar:Hide()
        end
    end

    local function check(silent)
        local has, expiring, missingBuffs, low = M.Scan()
        if not has then
            return
        end
        local list = problems(has, expiring, missingBuffs, low)
        if #list > 0 and not silent then
            if db.raidWarning then
                FF.Alert("Missing: " .. table.concat(list, ", "))
            end
            if db.sound then
                FF.PlaySound(db.soundKit)
            end
        end
        showBar(has, expiring)
        return has, expiring, list
    end

    ---------------------------------------------------------------------------
    -- Raid check: everyone running Fresh Fixes reports; a window lists them.
    -- Comms tag "C":  S<have>[;<expiring>]  ·  Q (ask everyone to report)
    ---------------------------------------------------------------------------
    local reports = {} -- [key] = { name, class, have = "FDW", expiring = "D", t }
    local win

    local function report(silent)
        local has, expiring = check(silent)
        if not has then
            return
        end
        local exp = ""
        for f in pairs(expiring) do
            exp = exp .. f
        end
        local msg = "S" .. flagString(has, expiring) .. ";" .. exp
        local display, key = FF.UnitIdentity("player")
        if key then
            reports[key] = { name = display:match("^[^%-]+"), class = select(2, UnitClass("player")),
                have = flagString(has, expiring), expiring = exp, t = GetTime() }
        end
        if IsInGroup() then
            FF.Send("C", msg, "GROUP")
        end
        M.RefreshWindow()
    end

    local function catIcon(cat)
        if cat.icon then
            return cat.icon
        end
        local id = cat.items and cat.items[1]
        return id and C_Item.GetItemIconByID(id) or 134400
    end

    -- Players missing the most first; slots: red X = missing, ! = expiring
    function M.RefreshWindow()
        if not win or not win:IsShown() then
            return
        end
        local cats, list, short = wanted(), {}, 0
        for _, u in ipairs(IsInGroup() and FF.GroupUnits() or { "player" }) do
            local key = FF.UnitKey(u)
            if key and not reports[key] then
                list[#list + 1] = { name = UnitName(u) or "?", class = select(2, UnitClass(u)), none = true }
            end
        end
        for _, r in pairs(reports) do
            r.missing = 0
            for _, cat in ipairs(cats) do
                if not r.have:find(cat.flag, 1, true) then
                    r.missing = r.missing + 1
                end
            end
            if r.missing > 0 then
                short = short + 1
            end
            list[#list + 1] = r
        end
        table.sort(list, function(a, b)
            if (a.none or false) ~= (b.none or false) then
                return not a.none
            end
            if (a.missing or 0) ~= (b.missing or 0) then
                return (a.missing or 0) > (b.missing or 0)
            end
            return a.name < b.name
        end)
        local rows = {}
        for _, r in ipairs(list) do
            local badges = {}
            if not r.none then
                for _, cat in ipairs(cats) do
                    local has = r.have:find(cat.flag, 1, true)
                    local exp = r.expiring and r.expiring:find(cat.flag, 1, true)
                    badges[#badges + 1] = { icon = catIcon(cat), dim = not has and not exp,
                        text = (not has and not exp) and "|cffff5050X|r" or (exp and "|cffffc040!|r" or "") }
                end
            end
            rows[#rows + 1] = {
                text = FF.ClassColor(r.class, r.name) .. ((r.missing or 0) > 0 and ("  |cffff6060" .. r.missing .. "|r") or ""),
                right = r.none and (FF.Hex(FF.C.muted) .. "no report|r") or "",
                badges = badges,
            }
        end
        win.title:SetText(("Raid Consumes  %s%d reports, %d missing something|r"):format(FF.Hex(FF.C.muted), #list, short))
        win:SetRows(rows)
    end

    local function openRaidCheck()
        if not win then
            win = FF.ListWindow("ConsumesCheck", "Raid Consumes", 260, 41)
            win.rightWidth = 52
        end
        win:Show()
        report(true)
        if IsInGroup() then
            FF.Send("C", "Q", "GROUP")
        end
        M.RefreshWindow()
    end
    M.RaidCheck = openRaidCheck

    FF.OnComm("C", function(payload, _, display, key)
        if key == FF.UnitKey("player") then
            return
        end
        if payload == "Q" then
            C_Timer.After(math.random() * 2, function()
                report(true)
            end)
            return
        end
        local have, exp = payload:match("^S([%u]*);?([%u]*)$")
        if have then
            local u = FF.UnitByKey(key)
            reports[key] = { name = display:match("^[^%-]+"), class = u and select(2, UnitClass(u)),
                have = have, expiring = exp, t = GetTime() }
            M.RefreshWindow()
        end
    end)

    FF.On("READY_CHECK", function()
        if not db.onReadyCheck then
            return
        end
        report(false)
    end)
    FF.On("READY_CHECK_FINISHED", function()
        if db.barMode ~= "always" then
            C_Timer.After(db.barSeconds, hideBar)
        end
    end)

    local watcher, pendingRefresh
    local function refreshAlways()
        pendingRefresh = false
        if db.barMode == "always" and db.bar and not InCombatLockdown() then
            check(true)
        end
    end
    local function listen()
        if db.barMode == "always" and db.bar then
            watcher = watcher or CreateFrame("Frame")
            watcher:SetScript("OnEvent", function(_, event, unit)
                if event == "UNIT_AURA" and unit ~= "player" then
                    return
                end
                if not pendingRefresh then
                    pendingRefresh = true
                    C_Timer.After(1, refreshAlways)
                end
            end)
            for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
                watcher:RegisterEvent(ev)
            end
            refreshAlways()
        elseif watcher then
            watcher:UnregisterAllEvents()
            hideBar()
        end
    end
    M.Listen = listen

    function M.RedrawBar()
        if bar and bar:IsShown() and not InCombatLockdown() then
            check(true)
        end
    end
    FF.On("FF_READY", listen)

    FF.On("PLAYER_REGEN_DISABLED", function()
        if db.barMode == "always" then
            return -- stays up (can't change during combat)
        end
        if bar and bar:IsShown() then
            C_Timer.After(0, function()
                if not InCombatLockdown() then
                    bar:Hide()
                end
            end)
        end
    end)

    -- Every N seconds while inside a raid instance and out of combat
    local raidTicker
    local function raidTimer()
        if raidTicker then
            raidTicker:Cancel()
            raidTicker = nil
        end
        if db.raidTimer and FF.InRaidInstance() then
            raidTicker = C_Timer.NewTicker(db.raidInterval, function()
                if not InCombatLockdown() then
                    check(false)
                    if db.barMode ~= "always" then
                        C_Timer.After(db.barSeconds, hideBar)
                    end
                end
            end)
        end
    end
    M.RaidTimer = raidTimer
    FF.On("FF_ZONE", raidTimer)

    FF.On("FF_ZONE", function()
        if not db.onRaidZone then
            return
        end
        if FF.InRaidInstance() then
            C_Timer.After(6, function()
                check(false)
                C_Timer.After(db.barSeconds, hideBar)
            end)
        end
    end)

    -- "a, b, 123" <-> { ids = {[123]=true}, names = {["a"]=true} }
    local function extraGet(cat)
        local x, out = db.extra[cat], {}
        if x then
            for id in pairs(x.ids or {}) do
                out[#out + 1] = tostring(id)
            end
            for n in pairs(x.names or {}) do
                out[#out + 1] = n
            end
        end
        table.sort(out)
        return table.concat(out, ", ")
    end
    local function extraSet(cat, text)
        local x = { ids = {}, names = {} }
        for part in text:gmatch("[^,]+") do
            part = part:match("^%s*(.-)%s*$")
            if tonumber(part) then
                x.ids[tonumber(part)] = true
            elseif part ~= "" then
                x.names[part:lower()] = true
            end
        end
        db.extra[cat] = x
    end
    local function itemsGet(cat)
        local out = {}
        for _, id in ipairs(db.items[cat] or {}) do
            out[#out + 1] = tostring(id)
        end
        return table.concat(out, ", ")
    end
    local function itemsSet(cat, text)
        local list = {}
        for id in text:gmatch("%d+") do
            list[#list + 1] = tonumber(id)
        end
        db.items[cat] = list
    end

    FF.Settings("Consumes", function(L)
        L:Header("What to check")
        L:Toggle("Flask", db, "flask")
        L:Toggle("Elixirs", db, "elixir")
        L:Toggle("Food (Well Fed)", db, "food")
        L:Toggle("Weapon oil / sharpening stone", db, "weapon")
        L:Toggle("Healthstone (if a warlock is here)", db, "healthstone")
        L:Toggle("Missing raid buffs", db, "raidBuffs", { tip = "Intellect, Stamina, Mark of the Wild, Battle Shout - when someone in the group can cast it" })
        L:Toggle("Durability", db, "durability")
        L:Slider("Low durability below", db, "minDurability", 5, 90, 5, { dep = function() return db.durability end,
            fmt = function(v) return v .. "%" end })
        L:Slider("Buff counts as expiring under", db, "minMinutes", 0, 30, 1, { fmt = function(v) return v .. " min" end })

        L:Header("When to check")
        L:Toggle("On ready check", db, "onReadyCheck")
        L:Toggle("When entering a raid", db, "onRaidZone")
        L:Toggle("In a raid, out of combat", db, "raidTimer", { onChange = function() M.RaidTimer() end })
        L:Slider("Check every", db, "raidInterval", 30, 300, 30, { dep = function() return db.raidTimer end, indent = 12,
            onChange = function() M.RaidTimer() end,
            fmt = function(v) return v < 60 and (v .. " s") or (v % 60 == 0 and (v / 60 .. " min") or ("%d min %d s"):format(v / 60, v % 60)) end })
        L:Buttons({
            { "Check now", function() FF.Run("cons") end },
            { "Raid check", function() M.RaidCheck() end, "Ask everyone to report and list who is missing what" },
            { "List my buffs + IDs", function() FF.Run("cons buffs") end },
        })

        L:Header("Alerts")
        L:Toggle("Raid warning text", db, "raidWarning")
        L:Toggle("Sound", db, "sound")
        L:Select("Sound to play", db, "soundKit", FF.SoundChoices, { dep = function() return db.sound end,
            onChange = function() FF.PlaySound(db.soundKit) end })

        L:Header("Click-to-use bar")
        L:Toggle("Show the consumables bar", db, "bar", { tip = "Buttons for the consumables you carry", onChange = function() M.Listen() end })
        local onBar = function() return db.bar end
        L:Select("Show the bar", db, "barMode", { { "check", "After a check" }, { "always", "Always (out of combat)" } },
            { dep = onBar, onChange = function() M.Listen() end })
        L:Slider("Hide after", db, "barSeconds", 5, 120, 5, { dep = function() return db.bar and db.barMode == "check" end,
            indent = 12, fmt = function(v) return v .. " s" end })
        local redraw = function() M.RedrawBar() end
        L:Select("Buffs already up", db, "barActive", { { "hide", "Hide their button" }, { "grey", "Grey out with a tick" } },
            { dep = onBar, onChange = redraw, tip = "They come back when the buff is about to run out (see 'counts as expiring')" })
        L:Slider("Icon size", db, "barSize", 20, 64, 2, { dep = onBar, onChange = redraw })
        L:Slider("Icon spacing", db, "barSpacing", 0, 12, 1, { dep = onBar, onChange = redraw, fmt = function(v) return v .. " px" end })
        L:Slider("Icon border", db, "barBorder", 0, 3, 1, { dep = onBar, onChange = redraw, fmt = function(v) return v .. " px" end })
        L:Toggle("Show type above each icon", db, "barLabel", { dep = onBar, onChange = redraw })
        L:Toggle("Show tooltips", db, "barTips", { dep = onBar })

        L:Header("Custom buffs and items")
        L:Desc("Forever may use different IDs than Classic. Add buff names or spell IDs (comma separated); 'List my buffs' prints yours. Items are item IDs for the click bar, tried first.")
        for _, cat in ipairs({ "flask", "elixir", "food" }) do
            L:Input(cat:sub(1, 1):upper() .. cat:sub(2) .. " buffs", db, "_x" .. cat, {
                get = function() return extraGet(cat) end,
                set = function(v) extraSet(cat, v) end,
            })
        end
        for _, cat in ipairs({ "flask", "elixir", "food", "weapon" }) do
            L:Input(cat:sub(1, 1):upper() .. cat:sub(2) .. " items", db, "_i" .. cat, {
                get = function() return itemsGet(cat) end,
                set = function(v) itemsSet(cat, v) end,
            })
        end
    end)

    FF.Command("cons", function(rest)
        if rest:lower() == "buffs" then
            for i = 1, 60 do
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not a then
                    break
                end
                if readable(a.name) then
                    print(("  %s  (spell %s)"):format(a.name, tostring(a.spellId)))
                end
            end
            return
        end
        local has, _, list = check(true)
        if not has then
            FF.print("Can't read buffs right now (combat)")
            return
        end
        FF.print(#list == 0 and "All consumes up" or ("Missing: " .. table.concat(list, ", ")))
    end, "check consumes ('cons buffs' lists your buffs with spell IDs)")
end)
