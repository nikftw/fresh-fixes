local _, FF = ...
local M = FF.Module("DebuffTracker")

-- Target debuff tracker: grey missing, red weak/low-rank, green when the
-- preferred (first) debuff of a slot is up at full rank. Forever spell IDs.
FF.Init("DebuffTracker", function()
    local C, UI = FF.C, FF.UI
    local readable = FF.readable

    -- families[] ordered strongest → weakest. Each family's ids[] are best rank first.
    local BUILTIN = {
        {
            key = "ffcor", label = "Faerie Fire / CoR",
            icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
            families = {
                { ids = { 9907, 9749, 778, 770 } }, -- Faerie Fire
                { ids = { 11717, 7659, 7658, 704 } }, -- Curse of Recklessness
            },
        },
        {
            key = "expose", label = "Expose / Sunder",
            icon = "Interface\\Icons\\Ability_Warrior_Sunder",
            families = {
                { ids = { 11198, 11197, 8650, 8649, 8647 } }, -- Expose Armor
                { ids = { 11597, 11596, 8380, 7405, 7386 } }, -- Sunder Armor
            },
        },
        {
            key = "demo", label = "Demo / Vindication",
            icon = "Interface\\Icons\\Ability_Warrior_WarCry",
            families = {
                { ids = { 11556, 11555, 11554, 6190, 1160 } }, -- Demoralizing Shout
                { ids = { 9898, 9747, 9490, 1735, 99 } }, -- Demoralizing Roar
                { ids = { 440667 } }, -- Vindication (Forever debuff)
            },
        },
        {
            key = "coe", label = "Curse of Elements",
            icon = "Interface\\Icons\\Spell_Shadow_ChillTouch",
            families = {
                { ids = { 1311680 } }, -- Forever Curse of the Elements
            },
        },
        {
            key = "tc", label = "Thunder Clap",
            icon = "Interface\\Icons\\Spell_Nature_ThunderClap",
            families = {
                { ids = { 11581, 11580, 8205, 8204, 8198, 6343 } },
            },
        },
        {
            key = "jow", label = "Judgement of Wisdom",
            icon = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
            families = {
                { ids = { 20355, 20354, 20186 } },
            },
        },
        {
            key = "joc", label = "Judgement of the Crusader",
            icon = "Interface\\Icons\\Spell_Holy_HolySmite",
            families = {
                { ids = { 20303, 20302, 20301, 20300, 20188, 21183 } },
            },
        },
        {
            key = "is", label = "Insect Swarm",
            icon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
            families = {
                { ids = { 24977, 24976, 24975, 24974, 5570 } },
            },
        },
        {
            key = "ms", label = "Mortal Strike",
            icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
            families = {
                { ids = { 21553, 21552, 21551, 12294 } },
            },
        },
        {
            key = "castslow", label = "Mind-numbing / Tongues",
            icon = "Interface\\Icons\\Spell_Nature_NullifyDisease",
            families = {
                { ids = { 11399, 11398, 8694, 8693, 8692, 5760, 25810 } }, -- Mind-numbing Poison
                { ids = { 11719, 1714 } }, -- Curse of Tongues
            },
        },
    }

    local OFF_BY_DEFAULT = { joc = true, is = true, ms = true, castslow = true }
    local db = FF.DB("debufftracker", {
        locked = true,
        showDuration = true,
        iconSize = 28,
        textSize = 12,
    })
    db.show = db.show or {}
    db.custom = db.custom or {} -- { { id = number, show = true }, ... }
    for _, slot in ipairs(BUILTIN) do
        if db.show[slot.key] == nil then
            db.show[slot.key] = not OFF_BY_DEFAULT[slot.key]
        end
    end

    local ZOOM = 0.1 -- 20% zoom → crop 10% each side
    local GAP = 2
    local win, icons, ticker
    local pendingCustom = { id = "" }

    local function iconPath(file)
        if type(file) ~= "string" or file == "" then
            return "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        if file:find("\\") or file:find("/") then
            return file
        end
        return "Interface\\Icons\\" .. file
    end

    local function spellIcon(spellID)
        if not spellID then
            return nil
        end
        local ok, info = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and info then
            return info
        end
        local ok2, name, _, tex = pcall(GetSpellInfo, spellID)
        if ok2 and tex then
            return tex
        end
        return nil
    end

    -- Build lookup: spellID -> { slotKey, familyIndex, rankIndex, best }
    local idMap = {}
    local function rebuildMap()
        wipe(idMap)
        for _, slot in ipairs(BUILTIN) do
            for fi, fam in ipairs(slot.families) do
                for ri, id in ipairs(fam.ids) do
                    idMap[id] = { key = slot.key, family = fi, rank = ri, best = fi == 1 and ri == 1 }
                end
            end
        end
        for i, c in ipairs(db.custom) do
            local id = tonumber(c.id)
            if id then
                idMap[id] = { key = "custom:" .. i, family = 1, rank = 1, best = true, custom = i }
            end
        end
    end
    rebuildMap()

    local function activeSlots()
        local list = {}
        for _, slot in ipairs(BUILTIN) do
            if db.show[slot.key] then
                list[#list + 1] = slot
            end
        end
        for i, c in ipairs(db.custom) do
            if c.show ~= false and tonumber(c.id) then
                local id = tonumber(c.id)
                list[#list + 1] = {
                    key = "custom:" .. i,
                    label = tostring(id),
                    icon = spellIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark",
                    families = { { ids = { id } } },
                    custom = i,
                }
            end
        end
        return list
    end

    local function scanTarget()
        local found = {} -- [slotKey] = { spellId, expires, icon, best, family, rank, stacks }
        if not UnitExists("target") then
            return found
        end
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
            if not a then
                break
            end
            local spellId, expires, icon, stacks, name = a.spellId, a.expirationTime, a.icon, a.applications, a.name
            local meta = spellId and idMap[spellId]
            if meta then
                local cur = found[meta.key]
                -- Prefer stronger family, then better rank (lower index).
                if not cur or meta.family < cur.family or (meta.family == cur.family and meta.rank < cur.rank) then
                    found[meta.key] = {
                        spellId = spellId,
                        expires = expires,
                        icon = icon,
                        best = meta.best,
                        family = meta.family,
                        rank = meta.rank,
                        stacks = stacks or 0,
                        name = name,
                    }
                end
            end
        end
        return found
    end

    local function durText(expires)
        if not expires or not readable(expires) then
            return ""
        end
        local left = expires - GetTime()
        if left <= 0 then
            return ""
        end
        if left >= 60 then
            return ("%dm"):format(math.floor(left / 60 + 0.5))
        end
        return tostring(math.floor(left + 0.5))
    end

    local function ensureWin()
        if win then
            return win
        end
        win = CreateFrame("Frame", "FreshFixesDebuffTracker", UIParent)
        win:SetSize(200, 40)
        win:SetClampedToScreen(true)
        win:SetMovable(true)
        win:EnableMouse(false)
        FF.RestorePosition(win, "DebuffTracker", "CENTER", UIParent, "CENTER", 0, -120)

        win.title = CreateFrame("Frame", nil, win)
        win.title:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 0, 2)
        win.title:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, 2)
        win.title:SetHeight(UI.TITLE_H or 18)
        FF.Skin(win.title, "panel", false)
        win.title.text = FF.Text(win.title, "small")
        win.title.text:SetPoint("LEFT", 6, 0)
        win.title.text:SetText("Debuff Tracker - drag me")
        win.title:EnableMouse(true)
        win.title:RegisterForDrag("LeftButton")
        win.title:SetScript("OnDragStart", function()
            if not db.locked then
                win:StartMoving()
            end
        end)
        win.title:SetScript("OnDragStop", function()
            win:StopMovingOrSizing()
            FF.SavePosition(win, "DebuffTracker")
        end)
        win.title:Hide()

        icons = {}
        return win
    end

    local function applyDurFont(fs)
        local size = math.max(8, math.min(28, math.floor(tonumber(db.textSize) or 12)))
        if not pcall(fs.SetFont, fs, FF.FONT, size, "OUTLINE") then
            pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        end
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
    end

    local function iconBtn(i)
        local b = icons[i]
        if b then
            return b
        end
        b = CreateFrame("Frame", nil, win)
        b:SetSize(db.iconSize or 28, db.iconSize or 28)
        FF.Skin(b, "row")
        for _, e in ipairs(b.ffEdges or {}) do
            e:Hide()
        end
        if b.ffBg then
            b.ffBg:Hide()
        end
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
        b.overlay = b:CreateTexture(nil, "OVERLAY")
        b.overlay:SetAllPoints()
        b.overlay:SetColorTexture(0, 1, 0, 0.35)
        b.overlay:Hide()
        b.dur = b:CreateFontString(nil, "OVERLAY")
        b.dur:SetPoint("TOPLEFT", 0, 0)
        b.dur:SetPoint("BOTTOMRIGHT", 0, 0)
        applyDurFont(b.dur)
        b:EnableMouse(false)
        icons[i] = b
        return b
    end

    local function applyLock()
        ensureWin()
        win.title:SetShown(not db.locked)
        win:EnableMouse(not db.locked)
        if db.locked then
            win:RegisterForDrag()
        else
            win:RegisterForDrag("LeftButton")
            win:SetScript("OnDragStart", win.StartMoving)
            win:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                FF.SavePosition(self, "DebuffTracker")
            end)
        end
    end

    function M.Refresh()
        ensureWin()
        applyLock()
        local slots = activeSlots()
        local found = scanTarget()
        local size = db.iconSize or 28
        local n = #slots
        if n == 0 then
            win:Hide()
            return
        end
        win:SetSize(n * size + math.max(0, n - 1) * GAP, size)
        win:Show()

        for i = 1, math.max(n, #icons) do
            local b = iconBtn(i)
            local slot = slots[i]
            if slot then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (i - 1) * (size + GAP), 0)
                b:SetSize(size, size)
                b:Show()
                b.slot = slot
                local st = found[slot.key]
                b.state = st
                applyDurFont(b.dur)
                local tex = (st and st.icon) or iconPath(slot.icon)
                b.tex:SetTexture(tex)
                b.tex:SetTexCoord(ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
                if not st then
                    b.tex:SetDesaturated(true)
                    b.tex:SetVertexColor(0.55, 0.55, 0.55, 1)
                    b.overlay:Hide()
                    b.dur:SetText("")
                elseif st.best then
                    b.tex:SetDesaturated(false)
                    b.tex:SetVertexColor(1, 1, 1, 1)
                    b.overlay:SetColorTexture(0.15, 0.9, 0.2, 0.35)
                    b.overlay:Show()
                    b.dur:SetText(db.showDuration and durText(st.expires) or "")
                else
                    b.tex:SetDesaturated(false)
                    b.tex:SetVertexColor(1, 0.35, 0.35, 1)
                    b.overlay:SetColorTexture(0.9, 0.15, 0.1, 0.3)
                    b.overlay:Show()
                    b.dur:SetText(db.showDuration and durText(st.expires) or "")
                end
            else
                b.slot, b.state = nil, nil
                b:Hide()
            end
        end
    end

    local function tickDurations()
        if not (win and win:IsShown() and db.showDuration and icons) then
            return
        end
        for _, b in ipairs(icons) do
            if b:IsShown() and b.state and b.state.best ~= nil then
                b.dur:SetText(durText(b.state.expires))
            end
        end
    end

    local function startTicker()
        if ticker then
            return
        end
        ticker = C_Timer.NewTicker(0.2, tickDurations)
    end

    local function stopTicker()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end

    function M.Apply()
        rebuildMap()
        ensureWin()
        applyLock()
        M.Refresh()
        if db.showDuration then
            startTicker()
        else
            stopTicker()
        end
    end

    -- the game sends this frame only the target's aura changes
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function()
        M.Refresh()
    end)
    FF.On("FF_READY", function()
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterUnitEvent("UNIT_AURA", "target")
        M.Apply()
    end)
    FF.On("FF_ZONE", M.Apply)

    FF.Command("debuffs", function(arg)
        arg = (arg or ""):lower()
        if arg == "lock" or arg == "unlock" or arg == "toggle" then
            db.locked = not db.locked
            if arg == "lock" then
                db.locked = true
            elseif arg == "unlock" then
                db.locked = false
            end
            applyLock()
            FF.print(db.locked and "Debuff Tracker locked" or "Debuff Tracker unlocked — drag the title")
        else
            FF.print("debuffs lock | unlock | toggle")
        end
    end, "lock/unlock the debuff tracker")

    FF.Settings("DebuffTracker", function(L)
        L:Header("Debuff Tracker")
        L:Desc("Icons for core raid debuffs on your current target. Grey = missing, red = weaker/low rank, green = preferred debuff up.")
        L:Buttons({
            {
                "Unlock / lock frame",
                function()
                    db.locked = not db.locked
                    applyLock()
                    FF.print(db.locked and "Debuff Tracker locked" or "Debuff Tracker unlocked — drag the title")
                end,
            },
        })
        L:Toggle("Show duration text", db, "showDuration", {
            onChange = function()
                M.Apply()
            end,
        })
        L:Slider("Icon size", db, "iconSize", 16, 64, 1, {
            onChange = M.Refresh,
            fmt = function(v) return tostring(v) end,
        })
        L:Slider("Duration text size", db, "textSize", 8, 28, 1, {
            onChange = M.Refresh,
            fmt = function(v) return tostring(v) end,
            dep = function() return db.showDuration end,
        })

        L:Header("Built-in debuffs")
        for _, slot in ipairs(BUILTIN) do
            L:Toggle(slot.label, db.show, slot.key, {
                onChange = function()
                    M.Apply()
                end,
            })
        end

        L:Header("Custom debuffs")
        L:Desc("Add a harmful spell by Forever spell ID.")
        L:Input("Spell ID", pendingCustom, "id")
        L:Buttons({
            {
                "Add custom debuff",
                function()
                    local id = tonumber(pendingCustom.id)
                    if not id then
                        FF.print("Enter a numeric spell ID")
                        return
                    end
                    db.custom[#db.custom + 1] = { id = id, show = true }
                    pendingCustom.id = ""
                    M.Apply()
                    FF.print("Added custom debuff " .. id)
                end,
            },
        })
        for i, c in ipairs(db.custom) do
            local idx = i
            local id = tonumber(c.id) or 0
            L:Toggle(("Spell %d"):format(id), c, "show", {
                onChange = M.Apply,
                indent = 12,
            })
            L:Buttons({
                {
                    "Remove #" .. idx,
                    function()
                        table.remove(db.custom, idx)
                        M.Apply()
                    end,
                },
            }, { indent = 12 })
        end
    end)
end)
