local _, FF = ...
local M = FF.Module("MouseRing")

-- Mouse rings: any number of rings around the cursor. Each ring is plain or
-- shows a timer (global cooldown, cast/channel, or one spell's cooldown) as a
-- sweep, with its own size, thickness, colour, opacity and when-to-show.
-- Timed rings choose fill/empty, clockwise/anticlockwise and what to show
-- when idle. Any ring can recolour when the target is out of range.
-- Cursor-wide extras: hide rules, idle fade, centre dot, trail.
-- Frames exist only once shown; per-frame work only while something is shown.
FF.Init("MouseRing", function()
    local readable = FF.readable
    local db = FF.DB("mousering", {
        enabled = true,
        hideRightClick = false, hideAFK = false, hideMounted = false,
        fadeIdle = false, fadeDelay = 3, idleAlpha = 30,
        dot = false, dotSize = 6, dotClassColor = false,
        trail = false, trailShape = "glow", trailSize = 16, trailLength = 20, trailDuration = 0.5,
        trailBrightness = 80, trailClassColor = true, trailSparkle = false,
    })

    -- Timed-ring defaults per kind. GCD/spell: sits full, empties when
    -- triggered and refills clockwise. Cast: hidden until you cast, fills.
    local function timerDefaults(r)
        r.anim = r.anim or "fill"
        r.dir = r.dir or "cw"
        r.idle = r.idle or (r.kind == "cast" and "hide" or "full")
    end

    local function newRing(kind, name)
        local r = {
            name = name or "Ring", enabled = true, kind = kind or "plain", size = 48, thickness = 4,
            classColor = kind ~= "gcd" and kind ~= "cast", alpha = 80, trackAlpha = 20,
            show = kind == "gcd" and "always" or "combat", edge = false, range = false,
        }
        timerDefaults(r)
        return r
    end

    db.rings = db.rings or {} -- none until you add one

    local MEDIA = FF.MEDIA
    local KINDS = {
        { "plain", "Plain ring" }, { "gcd", "Global cooldown" }, { "cast", "Cast / channel bar" },
        { "spell", "Spell cooldown" },
    }
    local SHOWS = { { "always", "Always" }, { "combat", "In combat" }, { "ooc", "Out of combat" } }
    local TRAIL_SHAPES = { { "glow", "Glow" }, { "disc", "Dot" }, { "ring_t2", "Ring" } }

    -- Melee range check: an ability every class of that type has. Override per character.
    local MELEE_SPELLS = {
        WARRIOR = 78, ROGUE = 1752, PALADIN = 20271, HUNTER = 2973, DRUID = 6807,
        SHAMAN = 17364, DEATHKNIGHT = 49998, MONK = 100780, DEMONHUNTER = 162243,
    }

    local _, myClass = UnitClass("player")
    local function classRGB()
        local c = RAID_CLASS_COLORS[myClass]
        if c then
            return c.r, c.g, c.b
        end
        return 1, 1, 1
    end
    local function pick(useClass, c, default)
        if useClass then
            return classRGB()
        end
        c = c or default
        return c.r, c.g, c.b
    end

    local function spellID(v)
        if tonumber(v) then
            return tonumber(v)
        end
        if type(v) ~= "string" or v == "" then
            return
        end
        local info = C_Spell.GetSpellInfo(v)
        return info and info.spellID
    end

    local holder, trailFrame
    local frames = {} -- [index] = ring frame
    local lastX, lastY, lastMove = 0, 0, 0
    local outOfRange = {} -- [ring index] = true while its target is out of range

    ---------------------------------------------------------------------------
    -- Ring frames
    ---------------------------------------------------------------------------
    local function ringFrame(i)
        local f = frames[i]
        if f then
            return f
        end
        f = CreateFrame("Frame", nil, holder)
        f:SetPoint("CENTER")
        f.track = f:CreateTexture(nil, "ARTWORK")
        f.track:SetAllPoints()
        f.full = f:CreateTexture(nil, "ARTWORK", nil, 1) -- spell ready, sweep-fills rings
        f.full:SetAllPoints()
        f.full:Hide()
        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetAllPoints()
        f.cd:SetDrawEdge(false)
        f.cd:SetDrawBling(false)
        f.cd:SetHideCountdownNumbers(true)
        f.activeUntil = 0
        frames[i] = f
        return f
    end

    local function ringColour(r, i)
        if r.range and outOfRange[i] then
            local c = r.rangeColor or { r = 1, g = 0.15, b = 0.15 }
            return c.r, c.g, c.b
        end
        return pick(r.classColor, r.color, { r = 1, g = 1, b = 1 })
    end

    -- Anticlockwise = the sweep mirrored left-right (if the client supports it)
    local function setDirection(cd, dir)
        if not cd.SetTexCoordRange or not CreateVector2D then
            return
        end
        if dir == "ccw" then
            pcall(cd.SetTexCoordRange, cd, CreateVector2D(1, 0), CreateVector2D(0, 1))
        else
            pcall(cd.SetTexCoordRange, cd, CreateVector2D(0, 0), CreateVector2D(1, 1))
        end
    end

    local function styleRing(i)
        local r = db.rings[i]
        local f = ringFrame(i)
        local tex = MEDIA .. "ring_t" .. math.max(1, math.min(8, r.thickness))
        f:SetSize(r.size, r.size)
        f:SetFrameLevel(holder:GetFrameLevel() + i * 3)
        local cr, cg, cb = ringColour(r, i)
        f.track:SetTexture(tex)
        local timed = r.kind ~= "plain"
        -- the track can have its own colour (otherwise the ring colour)
        local tc = timed and r.ownTrack and r.trackColor and not (r.range and outOfRange[i]) and r.trackColor
        if tc then
            f.track:SetVertexColor(tc.r, tc.g, tc.b)
        else
            f.track:SetVertexColor(cr, cg, cb)
        end
        f.track:SetAlpha((timed and r.trackAlpha or r.alpha) / 100)
        f.full:SetTexture(tex)
        f.full:SetVertexColor(cr, cg, cb, r.alpha / 100)
        f.cd:SetShown(timed)
        if timed then
            if f.cd.SetSwipeTexture then
                f.cd:SetSwipeTexture(tex)
            end
            f.cd:SetSwipeColor(cr, cg, cb, r.alpha / 100)
            -- swipe colours the remaining time; reversed it colours the elapsed time
            f.cd:SetReverse(r.anim == "fill")
            f.cd:SetDrawEdge(r.edge and true or false)
            setDirection(f.cd, r.dir)
        end
    end

    local function styleAll()
        if not holder then
            return
        end
        for i = 1, #db.rings do
            styleRing(i)
        end
        for i = #db.rings + 1, #frames do
            frames[i]:Hide()
        end
        holder.dot:SetShown(db.dot)
        holder.dot:SetSize(db.dotSize, db.dotSize)
        holder.dot:SetVertexColor(pick(db.dotClassColor, db.dotColor, { r = 1, g = 1, b = 1 }))
    end

    ---------------------------------------------------------------------------
    -- Timers
    ---------------------------------------------------------------------------
    local cooldownOf = FF.SpellCooldown

    -- Hidden cooldown: let the Cooldown widget draw it without us reading it.
    local function drawHidden(f, id)
        if f.cd.SetCooldownFromDurationObject then
            local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, id)
            if ok and dur and pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur) then
                return true
            end
        end
        local cd = C_Spell.GetSpellCooldown(id)
        return cd and pcall(f.cd.SetCooldown, f.cd, cd.startTime, cd.duration) or false
    end

    -- Hasted global cooldown estimate, for showing/hiding the ring
    local function gcdEstimate()
        local haste = GetHaste and GetHaste() or 0
        if not readable(haste) or type(haste) ~= "number" then
            haste = 0
        end
        return math.max(0.75, 1.5 / (1 + haste / 100))
    end

    -- Global cooldown: Forever has no 61304 "Global Cooldown" spell, so it is
    -- read from the spell just cast. When those times are secret (combat), the
    -- game can still draw them; otherwise a hasted 1.5s estimate is used.
    local function startGCD(f, castID, now)
        local start, duration, hidden = cooldownOf(castID)
        if start and duration <= 1.5 then
            f.cd:SetCooldown(start, duration)
            f.activeUntil = start + duration
            return
        end
        local info = C_Spell.GetSpellCooldown(castID)
        local onGCD = info and info.isOnGCD
        if readable(onGCD) and onGCD == false and not hidden then
            return -- spell doesn't trigger the global cooldown
        end
        if hidden and drawHidden(f, castID) then
            f.activeUntil = now + gcdEstimate()
            return
        end
        local est = gcdEstimate()
        f.cd:SetCooldown(now, est)
        f.activeUntil = now + est
    end

    local function updateCooldowns(event, castID)
        if not holder then
            return
        end
        local now = GetTime()
        for i, r in ipairs(db.rings) do
            local f = frames[i]
            if f and r.enabled then
                if r.kind == "gcd" then
                    if event == "CAST" and castID and now >= f.activeUntil - 0.1 then
                        startGCD(f, castID, now)
                    elseif now >= f.activeUntil then
                        f.cd:Clear()
                        f.activeUntil = 0
                    end
                elseif r.kind == "spell" then
                    local id = spellID(r.spell)
                    local start, duration, hidden
                    if id then
                        start, duration, hidden = cooldownOf(id)
                        if duration and duration <= 1.5 then
                            start = nil -- only the global cooldown
                        end
                    end
                    if start then
                        f.cd:SetCooldown(start, duration)
                        f.activeUntil = start + duration
                    elseif hidden then
                        -- isActive / isOnGCD stay readable when the times are secret
                        local info = C_Spell.GetSpellCooldown(id)
                        local active, onGCD = info and info.isActive, info and info.isOnGCD
                        if readable(active) and active ~= nil then
                            if active and not (readable(onGCD) and onGCD) and drawHidden(f, id) then
                                f.activeUntil = math.huge
                            elseif not active then
                                f.cd:Clear()
                                f.activeUntil = 0
                            end
                        elseif drawHidden(f, id) then
                            f.activeUntil = now + 2
                        end
                    else
                        f.cd:Clear()
                        f.activeUntil = 0
                    end
                end
            end
        end
    end

    local function castUpdate(event)
        if not holder then
            return
        end
        local startMS, endMS
        if event == "UNIT_SPELLCAST_START" then
            startMS, endMS = select(4, UnitCastingInfo("player"))
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            startMS, endMS = select(4, UnitChannelInfo("player"))
        end
        local ok = readable(startMS) and readable(endMS) and startMS and endMS
        for i, r in ipairs(db.rings) do
            local f = frames[i]
            if f and r.kind == "cast" then
                if ok then
                    f.cd:SetCooldown(startMS / 1000, (endMS - startMS) / 1000)
                    f.activeUntil = endMS / 1000
                else
                    f.cd:Clear()
                    f.activeUntil = 0
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Trail
    ---------------------------------------------------------------------------
    local points, dots = {}, {}

    local function hueRGB(h)
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local q, t = 1 - f, f
        i = i % 6
        if i == 0 then
            return 1, t, 0
        elseif i == 1 then
            return q, 1, 0
        elseif i == 2 then
            return 0, 1, t
        elseif i == 3 then
            return 0, q, 1
        elseif i == 4 then
            return t, 0, 1
        end
        return 1, 0, q
    end

    local function updateTrail(x, y, now)
        if not db.trail then
            if trailFrame then
                trailFrame:Hide()
            end
            return
        end
        if not trailFrame then
            trailFrame = CreateFrame("Frame", nil, UIParent)
            trailFrame:SetAllPoints(UIParent)
            trailFrame:SetFrameStrata("TOOLTIP")
        end
        trailFrame:Show()
        local p = points[1]
        if not p or math.abs(p.x - x) + math.abs(p.y - y) > 2 then
            table.insert(points, 1, { x = x, y = y, t = now })
        end
        while #points > db.trailLength or (points[#points] and now - points[#points].t > db.trailDuration) do
            table.remove(points)
        end
        local tr, tg, tb = pick(db.trailClassColor, db.trailColor, { r = 1, g = 1, b = 1 })
        local tex = MEDIA .. db.trailShape
        for i = 1, math.max(#points, #dots) do
            local d = dots[i]
            local pt = points[i]
            if pt then
                if not d then
                    d = trailFrame:CreateTexture(nil, "ARTWORK")
                    d:SetBlendMode("ADD")
                    dots[i] = d
                end
                local life = 1 - (now - pt.t) / db.trailDuration
                local size = db.trailSize * (0.4 + 0.6 * life)
                d:SetTexture(tex)
                d:SetSize(size, size)
                d:ClearAllPoints()
                d:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pt.x, pt.y)
                if db.trailSparkle then
                    d:SetVertexColor(hueRGB((i / db.trailLength + now * 0.5) % 1))
                else
                    d:SetVertexColor(tr, tg, tb)
                end
                d:SetAlpha(math.max(0, life) * db.trailBrightness / 100)
                d:Show()
            elseif d then
                d:Hide()
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Out of range (per ring): melee by default, or a spell's range
    ---------------------------------------------------------------------------
    local function inRange(spell)
        if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
            return true
        end
        local id = spellID(spell) or MELEE_SPELLS[myClass]
        if id then
            local r = C_Spell.IsSpellInRange(id, "target")
            if readable(r) and r ~= nil then
                return r and true or false
            end
        end
        if not InCombatLockdown() and CheckInteractDistance then
            local ok, r = pcall(CheckInteractDistance, "target", 3)
            if ok and readable(r) then
                return r and true or false
            end
        end
        return true
    end

    local rangeAcc = 0
    local function checkRange(dt)
        rangeAcc = rangeAcc + dt
        if rangeAcc < 0.2 then
            return
        end
        rangeAcc = 0
        local changed
        for i, r in ipairs(db.rings) do
            local out = r.enabled and r.range and not inRange(r.rangeSpell) or nil
            if out ~= outOfRange[i] then
                outOfRange[i] = out
                changed = true
            end
        end
        if changed then
            styleAll()
        end
    end

    ---------------------------------------------------------------------------
    -- Visibility
    ---------------------------------------------------------------------------
    local function ringWanted(r, inCombat)
        if not r.enabled then
            return false
        end
        if r.show == "combat" then
            return inCombat
        elseif r.show == "ooc" then
            return not inCombat
        end
        return true
    end

    local function onUpdate(self, dt)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        x, y = x / s, y / s
        local now = GetTime()
        if math.abs(x - lastX) + math.abs(y - lastY) > 0.5 then
            lastX, lastY, lastMove = x, y, now
        end
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

        local alpha = 1
        if db.hideRightClick and ((IsMouselooking and IsMouselooking()) or IsMouseButtonDown("RightButton")) then
            alpha = 0
        elseif db.fadeIdle and now - lastMove > db.fadeDelay then
            alpha = db.idleAlpha / 100
        end
        self:SetAlpha(alpha)

        local inCombat = UnitAffectingCombat("player")
        for i, r in ipairs(db.rings) do
            local f = frames[i]
            if f then
                local show = ringWanted(r, inCombat)
                local idle = r.kind ~= "plain" and now >= f.activeUntil
                if show and idle and r.idle == "hide" then
                    show = false
                end
                f:SetShown(show)
                -- idle: a full ring, or just the dim track
                f.full:SetShown(show and idle and r.idle == "full")
            end
        end
        updateTrail(x, y, now)
        checkRange(dt)
    end

    local listenRings -- set up below (needs update itself)
    local function update()
        listenRings()
        local show = db.enabled and not (db.hideAFK and UnitIsAFK("player"))
            and not (db.hideMounted and IsMounted())
        if show then
            local inCombat = UnitAffectingCombat("player")
            local any = db.dot or db.trail
            for _, r in ipairs(db.rings) do
                any = any or ringWanted(r, inCombat)
            end
            show = any
        end
        if show then
            if not holder then
                holder = CreateFrame("Frame", nil, UIParent)
                holder:SetFrameStrata("TOOLTIP")
                holder:SetSize(1, 1)
                holder.dot = holder:CreateTexture(nil, "OVERLAY", nil, 7)
                holder.dot:SetPoint("CENTER")
                holder.dot:SetTexture(MEDIA .. "disc")
                holder:SetScript("OnUpdate", onUpdate)
            end
            styleAll()
            updateCooldowns()
            holder:Show()
        else
            if holder then
                holder:Hide()
            end
            if trailFrame then
                trailFrame:Hide()
                wipe(points)
            end
        end
    end
    M.Update = update

    local castEvents = CreateFrame("Frame")
    castEvents:SetScript("OnEvent", function(_, event, _, _, castID)
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            updateCooldowns("CAST", readable(castID) and castID or nil)
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
            castUpdate(event)
        end
    end)
    local function targetChanged()
        rangeAcc = 1
    end

    -- Listen only for what the configured rings need
    listenRings = function()
        local spell, cast, gcd, range, combat = false, false, false, false, false
        if db.enabled then
            for _, r in ipairs(db.rings) do
                if r.enabled then
                    spell = spell or r.kind == "spell"
                    cast = cast or r.kind == "cast"
                    gcd = gcd or r.kind == "gcd"
                    range = range or r.range
                    combat = combat or r.show ~= "always"
                end
            end
        end
        castEvents:UnregisterAllEvents()
        if gcd or cast then
            castEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            castEvents:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            castEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        end
        if cast then -- STOP also fires after an interrupt / failure
            castEvents:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
            castEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        end
        FF.Listen("SPELL_UPDATE_COOLDOWN", updateCooldowns, spell)
        FF.Listen("PLAYER_TARGET_CHANGED", targetChanged, range)
        FF.Listen("PLAYER_REGEN_DISABLED", update, combat)
        FF.Listen("PLAYER_REGEN_ENABLED", update, combat)
        FF.Listen("PLAYER_FLAGS_CHANGED", update, db.enabled and db.hideAFK)
        FF.Listen("PLAYER_MOUNT_DISPLAY_CHANGED", update, db.enabled and db.hideMounted)
    end

    FF.On("FF_ZONE", update)
    FF.On("FF_READY", update)

    ---------------------------------------------------------------------------
    -- Settings
    ---------------------------------------------------------------------------

    FF.Settings("MouseRing", function(L)
        local on = function() return db.enabled end
        local function dep(f)
            return function() return db.enabled and f() end
        end
        local function rebuild()
            FF.RebuildSettings("MouseRing")
        end
        L:Toggle("Enabled", db, "enabled", { onChange = update, tip = "Turns every ring on or off straight away" })

        L:Header("Rings")
        L:Desc("Add as many rings as you like. Rings sit on top of each other around the cursor - use different sizes to nest them.")
        L:Buttons({ { "Add ring", function()
            table.insert(db.rings, newRing("plain", "Ring " .. (#db.rings + 1)))
            update()
            rebuild()
        end } }, { dep = on })

        for i, r in ipairs(db.rings) do
            local live = function() return db.enabled and r.enabled end
            local timed = function() return live() and r.kind ~= "plain" end
            L:Header(i .. ". " .. r.name)
            L:Toggle("Enabled", r, "enabled", { dep = on, onChange = update })
            L:Input("Name", r, "name", { dep = live, onChange = rebuild })
            L:Select("Shows", r, "kind", KINDS, { dep = live, onChange = function()
                update()
                rebuild()
            end })
            if r.kind == "spell" then
                L:Input("Spell (name or ID)", r, "spell", { dep = live, onChange = updateCooldowns, indent = 12,
                    tip = "The sweep shows this spell's cooldown (the global cooldown is ignored)" })
            end
            L:Select("When", r, "show", SHOWS, { dep = live, onChange = update })
            L:Slider("Size", r, "size", 16, 160, 2, { dep = live, onChange = styleAll })
            L:Slider("Thickness", r, "thickness", 1, 8, 1, { dep = live, onChange = styleAll })
            L:Slider("Opacity", r, "alpha", 5, 100, 5, { dep = live, onChange = styleAll, fmt = function(v) return v .. "%" end })
            L:Toggle("Class colour", r, "classColor", { dep = live, onChange = styleAll })
            L:Color("Colour", r, "color", { r = 1, g = 1, b = 1 }, { dep = function() return live() and not r.classColor end, onChange = styleAll, indent = 12 })
            if r.kind ~= "plain" then
                L:Slider("Track opacity", r, "trackAlpha", 0, 100, 5, { dep = timed, onChange = styleAll,
                    fmt = function(v) return v .. "%" end, tip = "The dim ring behind the sweep" })
                L:Toggle("Own track colour", r, "ownTrack", { dep = timed, onChange = styleAll, tip = "Off: the track uses the ring colour" })
                L:Color("Track colour", r, "trackColor", { r = 1, g = 1, b = 1 }, { dep = function() return timed() and r.ownTrack end,
                    onChange = styleAll, indent = 12 })
                L:Select("While running", r, "anim", { { "fill", "Refill (starts empty, fills up)" }, { "empty", "Drain (starts full, empties)" } },
                    { dep = timed, onChange = styleAll, width = 220 })
                L:Select("Direction", r, "dir", { { "cw", "Clockwise" }, { "ccw", "Anticlockwise" } }, { dep = timed, onChange = styleAll })
                L:Select(r.kind == "cast" and "When not casting" or (r.kind == "gcd" and "When off the GCD" or "When off cooldown"),
                    r, "idle", { { "full", "Full ring" }, { "track", "Only the dim track" }, { "hide", "Hide the ring" } },
                    { dep = timed, onChange = styleAll })
                L:Toggle("Bright edge on the sweep", r, "edge", { dep = timed, onChange = styleAll })
            end
            L:Toggle("Recolour when out of range", r, "range", { dep = live, onChange = update })
            local rg = function() return live() and r.range end
            L:Color("Out of range colour", r, "rangeColor", { r = 1, g = 0.15, b = 0.15 }, { dep = rg, onChange = styleAll, indent = 12 })
            L:Input("Range of spell (blank = melee)", r, "rangeSpell", { dep = rg, indent = 12, width = 160,
                tip = "Name or ID of a spell you know, e.g. a heal for 40 yards" })
            L:Buttons({
                { "Move up", function()
                    if i > 1 then
                        db.rings[i], db.rings[i - 1] = db.rings[i - 1], db.rings[i]
                        update()
                        rebuild()
                    end
                end },
                { "Remove ring", function()
                    table.remove(db.rings, i)
                    update()
                    rebuild()
                end },
            }, { dep = on })
        end

        L:Header("Hiding")
        L:Toggle("Hide while right-click is held", db, "hideRightClick", { dep = on, tip = "While turning the camera" })
        L:Toggle("Hide while away (AFK)", db, "hideAFK", { dep = on, onChange = update })
        L:Toggle("Hide while mounted", db, "hideMounted", { dep = on, onChange = update })
        L:Toggle("Fade when the cursor is still", db, "fadeIdle", { dep = on })
        L:Slider("Fade after", db, "fadeDelay", 0.5, 10, 0.5, { dep = dep(function() return db.fadeIdle end), indent = 12,
            fmt = function(v) return ("%.1f s"):format(v) end })
        L:Slider("Idle opacity", db, "idleAlpha", 0, 100, 5, { dep = dep(function() return db.fadeIdle end), indent = 12,
            fmt = function(v) return v .. "%" end })

        L:Header("Centre dot")
        L:Toggle("Centre dot", db, "dot", { dep = on, onChange = update })
        L:Slider("Dot size", db, "dotSize", 2, 24, 1, { dep = dep(function() return db.dot end), onChange = styleAll, indent = 12 })
        L:Toggle("Class colour dot", db, "dotClassColor", { dep = dep(function() return db.dot end), onChange = styleAll, indent = 12 })
        L:Color("Dot colour", db, "dotColor", { r = 1, g = 1, b = 1 }, { dep = dep(function() return db.dot and not db.dotClassColor end), onChange = styleAll, indent = 12 })

        L:Header("Trail")
        L:Toggle("Cursor trail", db, "trail", { dep = on, onChange = update })
        local t = dep(function() return db.trail end)
        L:Select("Trail shape", db, "trailShape", TRAIL_SHAPES, { dep = t, indent = 12 })
        L:Slider("Trail size", db, "trailSize", 4, 64, 1, { dep = t, indent = 12 })
        L:Slider("Trail length", db, "trailLength", 5, 60, 1, { dep = t, indent = 12, tip = "Number of points" })
        L:Slider("Trail duration", db, "trailDuration", 0.1, 3, 0.1, { dep = t, indent = 12, fmt = function(v) return ("%.1f s"):format(v) end })
        L:Slider("Trail brightness", db, "trailBrightness", 10, 100, 5, { dep = t, indent = 12, fmt = function(v) return v .. "%" end })
        L:Toggle("Rainbow (each point its own colour)", db, "trailSparkle", { dep = t, indent = 12 })
        L:Toggle("Class colour trail", db, "trailClassColor", { dep = dep(function() return db.trail and not db.trailSparkle end), indent = 12 })
        L:Color("Trail colour", db, "trailColor", { r = 1, g = 1, b = 1 }, {
            dep = dep(function() return db.trail and not db.trailSparkle and not db.trailClassColor end), indent = 12 })
    end)

    FF.Command("ring", function()
        db.enabled = not db.enabled
        update()
        FF.print("Mouse rings", db.enabled and "on" or "off")
    end, "turn the mouse rings on/off")
end)
