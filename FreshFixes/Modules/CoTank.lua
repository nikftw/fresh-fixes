local _, FF = ...
local M = FF.Module("CoTank")

-- A small clickable frame for the other tank: health, their target, and
-- their debuffs (game-rendered when available). Secure attributes and size
-- only change out of combat.
-- Game-rendered debuff row (Blizzard AuraContainer), growing left. Keeps
-- working in combat when aura data is secret. Returns a container or nil.
local function auraContainer(parent, unit, filter, max, size, exclude)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not c then
        return
    end
    local span = max * size -- icons touch, no spacing
    local good = pcall(function()
        c:SetSize(span, size)
        c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        c:SetFlowLayoutAnchorPoint("RIGHT")
        c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
        c:SetFlowLayoutMaximumLineSize(span)
        c:SetUnit(unit)
        c.slot = c:AddAuraSlot("ff", filter, {
            maxFrameCount = max,
            candidateFilters = exclude and next(exclude) and { excludeSpellIDs = exclude } or nil,
            initializeFrame = function(button)
                if button.SetSize then
                    button:SetSize(size, size)
                end
            end,
        })
    end)
    if not good then
        c:Hide()
        return
    end
    return c
end

FF.Init("CoTank", function()
    local readable = FF.readable
    local db = FF.DB("cotank", {
        onlyWhenTank = true, debuffs = true, width = 200, height = 50, scale = 1,
        showTarget = false, targetIcon = true, targetName = true, targetHP = true, targetSize = 12,
        showPct = true, colorBy = "class", debuffCount = 4, debuffSize = 16,
        showPower = true, powerHeight = 4,
        bgAlpha = 70, hideDebuffs = "", debuffPos = "overlay", border = 0, nicknames = true, debuffFilter = "HARMFUL",
    })
    local MAX_AURAS = 8
    local btn, unit, pending, unlocked

    -- "12345, 67890" -> { [12345] = true, ... }
    local function hiddenSet()
        local set = {}
        for id in (db.hideDebuffs or ""):gmatch("%d+") do
            set[tonumber(id)] = true
        end
        return set
    end

    local function isTank(u)
        return UnitGroupRolesAssigned(u) == "TANK" or GetPartyAssignment("MAINTANK", u) or false
    end

    local function findCoTank()
        if not IsInGroup() then
            return
        end
        for _, u in ipairs(FF.GroupUnits()) do
            if not UnitIsUnit(u, "player") and isTank(u) then
                return u
            end
        end
    end

    -- Health colour: class, a single colour, or by HP value (red -> yellow -> green)
    local RED, YELLOW, GREEN = { 0.85, 0.2, 0.2 }, { 0.95, 0.78, 0.2 }, { 0.3, 0.8, 0.3 }
    local function gradient(p)
        local a, b = RED, YELLOW
        if p > 0.5 then
            a, b, p = YELLOW, GREEN, p - 0.5
        end
        p = p * 2
        return a[1] + (b[1] - a[1]) * p, a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p
    end

    -- When health is hidden from addons, the game evaluates this colour curve for us
    local curve
    local function colourCurve()
        if curve == nil then
            curve = false
            pcall(function()
                local c = C_CurveUtil.CreateColorCurve()
                c:SetType(Enum.LuaCurveType.Linear)
                c:AddPoint(0, CreateColor(RED[1], RED[2], RED[3]))
                c:AddPoint(0.5, CreateColor(YELLOW[1], YELLOW[2], YELLOW[3]))
                c:AddPoint(1, CreateColor(GREEN[1], GREEN[2], GREEN[3]))
                curve = c
            end)
        end
        return curve
    end

    local function fixedColour()
        local class = unit and select(2, UnitClass(unit))
        local c = db.colorBy == "class" and class and RAID_CLASS_COLORS[class]
            or db.healthColor or { r = GREEN[1], g = GREEN[2], b = GREEN[3] }
        return c.r, c.g, c.b
    end

    local function paint(r, g, b, tint)
        btn.health:SetStatusBarColor(r, g, b)
        if tint then
            btn.health.bg:SetColorTexture(r * 0.22, g * 0.22, b * 0.22, 0.9)
        else
            btn.health.bg:SetColorTexture(0.06, 0.06, 0.07, 0.9)
        end
    end

    local function colourHealth(cur, max)
        if db.colorBy ~= "health" then
            local r, g, b = fixedColour()
            paint(r, g, b, true)
            return
        end
        if readable(cur) and readable(max) and max and max > 0 then
            paint(gradient(math.min(1, cur / max)))
            return
        end
        local c = colourCurve()
        if c and UnitHealthPercent then
            local ok, col = pcall(UnitHealthPercent, unit, true, c)
            if ok and col and pcall(function() btn.health:SetStatusBarColor(col:GetRGB()) end) then
                btn.health.bg:SetColorTexture(0.06, 0.06, 0.07, 0.9)
                return
            end
        end
        paint(fixedColour()) -- can't tell: class colour
    end

    -- Border = the background showing around the health bar (0-3px).
    -- Debuffs either overlay the right end of the health bar (default) or sit
    -- in their own row underneath. Icons touch, at exactly the set size.
    local function layout()
        if not btn or InCombatLockdown() then
            pending = true
            return
        end
        btn:SetSize(db.width, db.height)
        btn:SetScale(db.scale)
        local bg = FF.C.bg
        FF.SetBg(btn, { bg[1], bg[2], bg[3], db.bgAlpha / 100 })
        local b, size = db.border, db.debuffSize
        local row = db.debuffs and db.debuffPos == "row"
        local th = db.showTarget and (db.targetSize + 4) or 0 -- target row
        local below = row and (math.max(size, th) + b) or (th > 0 and th + b or 0)
        btn.health:ClearAllPoints()
        btn.health:SetPoint("TOPLEFT", b, -b)
        btn.health:SetPoint("TOPRIGHT", -b, -b)
        local power = db.showPower and db.powerHeight or 0
        btn.health:SetHeight(math.max(8, db.height - 2 * b - below - power))
        btn.power:ClearAllPoints()
        btn.power:SetPoint("TOPLEFT", btn.health, "BOTTOMLEFT")
        btn.power:SetPoint("TOPRIGHT", btn.health, "BOTTOMRIGHT")
        btn.power:SetHeight(math.max(1, power))
        btn.power:SetShown(db.showPower)
        btn.tgt:SetShown(db.showTarget)
        btn.pct:SetShown(db.showPct)
        for i = 1, MAX_AURAS do
            btn.auras[i]:SetSize(size, size)
        end
        M.PlaceAuras(db.debuffCount)
        if btn.container then
            btn.container:ClearAllPoints()
            if row then
                btn.container:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -b, b)
            else
                btn.container:SetPoint("CENTER", btn, "CENTER", 0, 0)
            end
        end
        -- name left, percent right; overlaid debuffs float above both
        btn.pct:ClearAllPoints()
        btn.pct:SetPoint("RIGHT", btn.health, "RIGHT", -4, 0)
        btn.name:ClearAllPoints()
        btn.name:SetPoint("LEFT", btn.health, "LEFT", 4, 0)
        btn.name:SetPoint("RIGHT", btn.health, "RIGHT", -(db.showPct and 40 or 4), 0)
        -- target row: [raid icon] name ........ hp%
        local t, ts = btn.tgt, db.targetSize
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", b, b)
        t:SetPoint("BOTTOMRIGHT", row and -(b + db.debuffCount * size + 2) or -b, b)
        t:SetHeight(row and math.max(size, th) or th)
        t.icon:SetSize(ts + 2, ts + 2)
        t.icon:SetShown(db.targetIcon)
        t.name:SetFont(FF.FONT, ts, "OUTLINE")
        t.hp:SetFont(FF.FONT, ts, "OUTLINE")
        t.name:ClearAllPoints()
        t.name:SetPoint("LEFT", db.targetIcon and (ts + 7) or 4, 0)
        t.name:SetPoint("RIGHT", t.hp, db.targetHP and "LEFT" or "RIGHT", -4, 0)
        t.name:SetShown(db.targetName)
        t.hp:SetShown(db.targetHP)
        btn.sep:SetShown(db.showPower)
    end

    -- Overlay: n icons centred on the frame. Row: right-aligned along the bottom.
    function M.PlaceAuras(n)
        if not btn then
            return
        end
        local b, size = db.border, db.debuffSize
        local row = db.debuffPos == "row"
        for i = 1, MAX_AURAS do
            local t = btn.auras[i]
            t:ClearAllPoints()
            if row then
                t:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -b - (i - 1) * size, b)
            else
                t:SetPoint("CENTER", btn, "CENTER", (i - 1) * size - (n - 1) * size / 2, 0)
            end
        end
    end

    local function build()
        btn = CreateFrame("Button", "FreshFixesCoTank", UIParent, "SecureUnitButtonTemplate")
        FF.RestorePosition(btn, "CoTank", "CENTER", 0, -180)
        -- standard unit-frame clicks: left targets, right opens the unit menu
        btn:SetAttribute("type1", "target")
        btn:SetAttribute("type2", "togglemenu")
        btn:RegisterForClicks("AnyUp")
        btn:SetMovable(true)
        btn:SetClampedToScreen(true)
        btn:SetScript("OnDragStart", btn.StartMoving)
        btn:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            FF.SavePosition(self, "CoTank")
        end)
        FF.Skin(btn, "bg")
        for _, e in ipairs(btn.ffEdges or {}) do
            e:Hide() -- no border
        end

        btn.health = CreateFrame("StatusBar", nil, btn)
        btn.health:SetPoint("TOPLEFT", 2, -2)
        btn.health:SetPoint("TOPRIGHT", -2, -2)
        btn.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        btn.health.bg = btn.health:CreateTexture(nil, "BACKGROUND")
        btn.health.bg:SetAllPoints()
        btn.health.bg:SetColorTexture(0, 0, 0, 0.5)

        -- resource bar (mana / rage / energy), coloured by power type
        btn.power = CreateFrame("StatusBar", nil, btn)
        btn.power:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        btn.power.bg = btn.power:CreateTexture(nil, "BACKGROUND")
        btn.power.bg:SetAllPoints()
        btn.power.bg:SetColorTexture(0, 0, 0, 0.6)
        btn.sep = btn.power:CreateTexture(nil, "OVERLAY") -- 1px line between the bars
        btn.sep:SetPoint("TOPLEFT")
        btn.sep:SetPoint("TOPRIGHT")
        btn.sep:SetColorTexture(0, 0, 0, 1)
        btn.sep:SetHeight(FF.PixelHeight(btn, 1))

        -- text and debuffs live on a layer above the health bar
        btn.top = CreateFrame("Frame", nil, btn)
        btn.top:SetAllPoints()
        btn.top:SetFrameLevel(btn.health:GetFrameLevel() + 5)
        btn.name = FF.Text(btn.top, "outline")
        btn.name:SetJustifyH("LEFT")
        btn.name:SetWordWrap(false)
        btn.pct = FF.Text(btn.top, "outline")
        -- their target; refreshed a few times a second while shown (no events
        -- exist for another player's target)
        local t = CreateFrame("Frame", nil, btn.top)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetPoint("LEFT", 3, 0)
        t.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        t.name = t:CreateFontString(nil, "OVERLAY")
        t.name:SetJustifyH("LEFT")
        t.name:SetWordWrap(false)
        t.hp = t:CreateFontString(nil, "OVERLAY")
        t.hp:SetPoint("RIGHT", -4, 0)
        t.hp:SetJustifyH("RIGHT")
        local acc = 0
        t:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc >= 0.25 then
                acc = 0
                M.UpdateTarget()
            end
        end)
        btn.tgt = t

        btn.debuffLayer = CreateFrame("Frame", nil, btn)
        btn.debuffLayer:SetAllPoints()
        btn.debuffLayer:SetFrameLevel(btn.top:GetFrameLevel() + 5) -- above the text
        btn.auras = {}
        for i = 1, MAX_AURAS do
            local t = btn.debuffLayer:CreateTexture(nil, "OVERLAY", nil, 1)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t.edge = btn.debuffLayer:CreateTexture(nil, "OVERLAY") -- 1px outline
            t.edge:SetPoint("TOPLEFT", t, -1, 1)
            t.edge:SetPoint("BOTTOMRIGHT", t, 1, -1)
            t.edge:SetColorTexture(0, 0, 0, 1)
            t.edge:Hide()
            hooksecurefunc(t, "Show", function() t.edge:Show() end)
            hooksecurefunc(t, "Hide", function() t.edge:Hide() end)
            t.count = btn.debuffLayer:CreateFontString(nil, "OVERLAY")
            t.count:SetFontObject(FF.Fonts.outline)
            t.count:SetPoint("BOTTOMRIGHT", t, 2, -2)
            t:Hide()
            btn.auras[i] = t
        end

        -- Game-rendered debuffs when available (keeps working when auras are secret)
        btn.container = auraContainer(btn.debuffLayer, "player", db.debuffFilter, db.debuffCount, db.debuffSize, hiddenSet())
        if btn.container then
            btn.container:SetFrameLevel(btn.debuffLayer:GetFrameLevel() + 1)
        end

        btn.events = CreateFrame("Frame")
        btn.events:SetScript("OnEvent", function(_, event)
            if event == "UNIT_AURA" then
                M.UpdateAuras()
            elseif event == "UNIT_TARGET" then
                M.UpdateTarget()
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                M.UpdatePower()
            else
                M.UpdateHealth()
            end
        end)
        btn:Hide()
        layout()
    end

    -- Values may be hidden from addons; the status bar can still draw them
    function M.UpdatePower()
        if not unit or not db.showPower then
            return
        end
        local ptype, token = UnitPowerType(unit)
        local c = (PowerBarColor and (PowerBarColor[token] or PowerBarColor[ptype])) or { r = 0.3, g = 0.5, b = 1 }
        btn.power:SetStatusBarColor(c.r, c.g, c.b)
        pcall(btn.power.SetMinMaxValues, btn.power, 0, UnitPowerMax(unit))
        pcall(btn.power.SetValue, btn.power, UnitPower(unit))
    end

    local function setPct(fs, u)
        local cur, max = UnitHealth(u), UnitHealthMax(u)
        if readable(cur) and readable(max) and max and max > 0 then
            fs:SetText(("%d%%"):format(cur / max * 100))
            return
        end
        -- other players' health is hidden from addons here: let the game
        -- format and draw the percentage without us reading it
        -- (pct may be hidden from us: never test or compare it, just hand it over)
        local scale = CurveConstants and CurveConstants.ScaleTo100
        local ok, pct = pcall(UnitHealthPercent, u, true, scale)
        if ok then
            if scale and pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then
                return
            elseif not scale and readable(pct) and type(pct) == "number" then
                fs:SetFormattedText("%.0f%%", pct * 100)
                return
            end
        end
        fs:SetText("")
    end

    function M.UpdateHealth()
        if not unit then
            paint(fixedColour())
            return
        end
        local cur, max = UnitHealth(unit), UnitHealthMax(unit)
        pcall(btn.health.SetMinMaxValues, btn.health, 0, max)
        pcall(btn.health.SetValue, btn.health, cur)
        -- dead or offline: grey bar and a word instead of a number
        local dead, online = UnitIsDeadOrGhost(unit), UnitIsConnected(unit)
        local gone = (readable(online) and online == false and "Offline") or (readable(dead) and dead and "Dead")
        if gone then
            paint(0.35, 0.35, 0.37)
            pcall(btn.health.SetValue, btn.health, max)
            btn.pct:SetText(db.showPct and gone or "")
            return
        end
        colourHealth(cur, max)
        if db.showPct then
            setPct(btn.pct, unit)
        else
            btn.pct:SetText("")
        end
    end

    function M.UpdateTarget()
        local t = btn.tgt
        local tu = unit and (unit .. "target")
        -- in combat these can be hidden from addons: a hidden value must never
        -- be tested in an if (that errors), only passed on for the game to draw
        local exists = tu and UnitExists(tu)
        if not tu or not db.showTarget or (readable(exists) and not exists) then
            t.name:SetText("")
            t.hp:SetText("")
            t.icon:SetAlpha(0)
            return
        end
        if db.targetName and not pcall(t.name.SetText, t.name, UnitName(tu)) then
            t.name:SetText("")
        end
        if db.targetHP then
            setPct(t.hp, tu)
        end
        if db.targetIcon then
            local idx = GetRaidTargetIndex(tu)
            local shown = false
            if type(idx) == "nil" then -- type() is safe on hidden values
                shown = false
            elseif not readable(idx) then
                -- hidden: the game picks the cell of the 4x4 icon sheet for us
                shown = t.icon.SetSpriteSheetCell ~= nil and pcall(t.icon.SetSpriteSheetCell, t.icon, idx, 4, 4, 64, 64)
            elseif type(idx) == "number" and idx >= 1 and idx <= 8 then
                local c, r = (idx - 1) % 4, math.floor((idx - 1) / 4)
                t.icon:SetTexCoord(c / 4, (c + 1) / 4, r / 4, (r + 1) / 4)
                shown = true
            end
            t.icon:SetAlpha(shown and 1 or 0)
        end
    end


    -- One path for every refresh, so toggling debuffs always restores them
    function M.UpdateAuras()
        if not btn then
            return
        end
        for i = 1, MAX_AURAS do
            btn.auras[i]:Hide()
            btn.auras[i].count:SetText("")
        end
        if btn.container then
            local show = unit ~= nil and db.debuffs
            btn.container:SetShown(show)
            if show then
                pcall(btn.container.SetUnit, btn.container, unit) -- refresh after being hidden
            end
            return
        end
        if not unit or not db.debuffs then
            return
        end
        local hide, n = hiddenSet(), 0
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, db.debuffFilter)
            if not a or not readable(a.icon) or not readable(a.spellId) then
                break
            end
            if not hide[a.spellId] then
                n = n + 1
                local t = btn.auras[n]
                FF.SetIcon(t, a.icon)
                t:Show()
                if readable(a.applications) and a.applications and a.applications > 1 then
                    t.count:SetText(a.applications)
                end
                if n >= db.debuffCount then
                    break
                end
            end
        end
        M.PlaceAuras(n)
    end

    local function refresh()
        if not btn then
            return
        end
        layout()
        M.UpdateHealth()
        M.UpdatePower()
        M.UpdateTarget()
        M.UpdateAuras()
    end

    local function assign()
        if InCombatLockdown() then
            pending = true
            return
        end
        pending = false
        local u = findCoTank()
        local show = u and (not db.onlyWhenTank or isTank("player")) or unlocked
        if not btn then
            if not show then
                return
            end
            build()
        end
        unit = u
        btn:SetAttribute("unit", u)
        if btn.container and u then
            pcall(btn.container.SetUnit, btn.container, u)
        end
        btn.events:UnregisterAllEvents()
        if u then
            btn.events:RegisterUnitEvent("UNIT_HEALTH", u)
            btn.events:RegisterUnitEvent("UNIT_MAXHEALTH", u)
            if db.showPower then
                btn.events:RegisterUnitEvent("UNIT_POWER_UPDATE", u)
                btn.events:RegisterUnitEvent("UNIT_MAXPOWER", u)
                btn.events:RegisterUnitEvent("UNIT_DISPLAYPOWER", u)
            end
            btn.events:RegisterUnitEvent("UNIT_AURA", u)
            btn.events:RegisterUnitEvent("UNIT_TARGET", u)
            local name = UnitName(u) or ""
            btn.name:SetText(db.nicknames and FF.NickOr(FF.UnitKey(u), name) or name)
        else
            btn.name:SetText("")
        end
        refresh()
        btn:SetShown(show and true or false)
    end

    FF.On("GROUP_ROSTER_UPDATE", assign)
    FF.On("PLAYER_ROLES_ASSIGNED", assign)
    FF.On("FF_READY", assign)
    FF.On("PLAYER_REGEN_ENABLED", function()
        if pending then
            assign()
        end
    end)

    local function toggleLock()
        if InCombatLockdown() then
            FF.print("Not in combat")
            return
        end
        unlocked = not unlocked
        assign()
        if btn then
            if unlocked then
                btn:RegisterForDrag("LeftButton")
            else
                btn:RegisterForDrag() -- no buttons = not draggable (nil is rejected)
            end
            if not btn.anchor then
                local a = CreateFrame("Frame", nil, btn)
                a:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1)
                a:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 1)
                a:SetHeight(FF.UI.TITLE_H)
                FF.Skin(a, "panel", false)
                a.text = FF.Text(a, "small")
                a.text:SetPoint("LEFT", 5, 0)
                a.text:SetPoint("RIGHT", -5, 0)
                a.text:SetJustifyH("LEFT")
                a.text:SetText("Co-tank - drag me")
                a:EnableMouse(true)
                a:RegisterForDrag("LeftButton")
                a:SetScript("OnDragStart", function()
                    btn:StartMoving()
                end)
                a:SetScript("OnDragStop", function()
                    btn:StopMovingOrSizing()
                    FF.SavePosition(btn, "CoTank")
                end)
                btn.anchor = a
            end
            btn.anchor:SetShown(unlocked)
        end
    end

    FF.Settings("CoTank", function(L)
        L:Header("When to show")
        L:Toggle("Only when I'm a tank", db, "onlyWhenTank", { onChange = assign })
        L:Buttons({ { "Unlock / lock frame", toggleLock } })

        L:Header("Size")
        L:Slider("Width", db, "width", 100, 300, 5, { onChange = refresh })
        L:Slider("Height", db, "height", 24, 80, 1, { onChange = refresh })
        L:Slider("Scale", db, "scale", 0.5, 2, 0.05, { onChange = refresh })
        L:Slider("Background opacity", db, "bgAlpha", 0, 100, 5, { onChange = refresh, fmt = function(v) return v .. "%" end })
        L:Slider("Border", db, "border", 0, 3, 1, { onChange = refresh, fmt = function(v) return v .. " px" end })

        L:Header("Contents")
        L:Toggle("Their target", db, "showTarget", { onChange = refresh, tip = "A row under the health bar" })
        local tg = function() return db.showTarget end
        L:Toggle("Raid icon", db, "targetIcon", { dep = tg, indent = 12, onChange = refresh })
        L:Toggle("Name", db, "targetName", { dep = tg, indent = 12, onChange = refresh })
        L:Toggle("Health percent", db, "targetHP", { dep = tg, indent = 12, onChange = refresh })
        L:Slider("Target text size", db, "targetSize", 8, 24, 1, { dep = tg, indent = 12, onChange = refresh })
        L:Toggle("Health percent", db, "showPct", { onChange = refresh })
        L:Toggle("Resource bar", db, "showPower", { onChange = assign, tip = "Mana, rage or energy under the health bar" })
        L:Slider("Resource bar height", db, "powerHeight", 2, 12, 1, { dep = function() return db.showPower end, onChange = refresh, indent = 12 })
        L:Select("Health colour", db, "colorBy", { { "class", "Class colour" }, { "health", "By HP value" }, { "custom", "Single colour" } },
            { onChange = refresh, tip = "By HP value: green when full, yellow at half, red when low" })
        L:Color("Colour", db, "healthColor", { r = 0.3, g = 0.8, b = 0.3 }, { dep = function() return db.colorBy == "custom" end, onChange = refresh, indent = 12 })
        L:Toggle("Show nicknames", db, "nicknames", { onChange = assign, tip = "From the Nicknames module" })
        L:Toggle("Debuffs", db, "debuffs", { onChange = refresh })
        L:Select("Debuffs to show", db, "debuffFilter", { { "HARMFUL", "All debuffs" }, { "HARMFUL|RAID", "Only ones I can dispel" } },
            { dep = function() return db.debuffs end, onChange = refresh, indent = 12,
              tip = "Game-rendered debuffs pick this up after a reload" })
        local deb = function() return db.debuffs end
        L:Select("Debuff position", db, "debuffPos", { { "overlay", "Middle, on top of everything" }, { "row", "Own row underneath" } },
            { dep = deb, onChange = refresh, indent = 12 })
        L:Slider("Debuffs shown", db, "debuffCount", 1, MAX_AURAS, 1, { dep = deb, onChange = refresh, indent = 12,
            tip = "Game-rendered debuffs pick this up after a reload" })
        L:Slider("Debuff size", db, "debuffSize", 8, 32, 1, { dep = deb, onChange = refresh, indent = 12 })
        L:Input("Hide these debuffs (spell IDs)", db, "hideDebuffs", { dep = deb, indent = 12, width = 200, onChange = refresh,
            tip = "Comma separated spell IDs. Game-rendered debuffs pick this up after a reload." })

    end)

    FF.Command("cotank", toggleLock, "unlock/lock the co-tank frame")
end)
