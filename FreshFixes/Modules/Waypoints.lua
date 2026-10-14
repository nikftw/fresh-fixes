local _, FF = ...
local M = FF.Module("Waypoints")

-- Built-in waypoint (no other addon needed). Follows RestedXP's guide arrow
-- (the current step's "goto"), places Blizzard's map waypoint there and
-- super-tracks it. The game then gives us an on-screen navigation frame
-- at that spot; we draw a map pin on it with the distance, and an arrow around the screen edge while it is off screen.
-- Also: /ff way <x> <y> [name] for a manual waypoint in the current zone.
FF.Init("Waypoints", function()
    local readable = FF.readable
    local MEDIA = FF.MEDIA
    local db = FF.DB("waypoints", {
        enabled = true, marker = true, markerSize = 28, distance = true, eta = false, textSize = 12,
        arrow = true, arrowSize = 40, edge = 38, hideBlizzard = true, fadeNear = true, arrive = 5,
    })

    local current       -- { mapID, x, y, name, source = "rxp" | "manual" }
    local ticker, frame

    ---------------------------------------------------------------------------
    -- Waypoint placement (Blizzard user waypoint + super tracking)
    ---------------------------------------------------------------------------
    local function setWaypoint(mapID, x, y, name, source)
        if not C_Map.CanSetUserWaypointOnMap(mapID) then
            return false
        end
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
        if not ok then
            return false
        end
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        current = { mapID = mapID, x = x, y = y, name = name, source = source }
        M.Watch(true)
        M.Show()
        return true
    end

    local function clearWaypoint()
        if not current then
            return
        end
        current = nil
        M.Watch(false)
        pcall(C_Map.ClearUserWaypoint)
        if frame then
            frame:Hide()
        end
    end
    M.Set, M.Clear = setWaypoint, clearWaypoint

    ---------------------------------------------------------------------------
    -- RestedXP guide arrow
    ---------------------------------------------------------------------------
    local function arrowElement()
        local af = _G.RXPG_ARROW
        if not af or not af:IsShown() then
            return
        end
        local el = af.element
        if type(el) == "table" and tonumber(el.zone) and tonumber(el.x) and tonumber(el.y) then
            return el
        end
    end

    local function tick()
        if not db.enabled or (current and current.source == "manual") then
            return
        end
        local el = arrowElement()
        if not el then
            if current and current.source == "rxp" then
                clearWaypoint()
            end
            return
        end
        local mapID, x, y = tonumber(el.zone), tonumber(el.x), tonumber(el.y)
        if current and current.mapID == mapID and math.abs(current.x - x) < 0.05 and math.abs(current.y - y) < 0.05 then
            return
        end
        setWaypoint(mapID, x, y, nil, "rxp")
    end

    -- Poll the guide arrow only while it's on screen
    local hookedArrow
    local function start()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        local arrow = _G.RXPG_ARROW
        if db.enabled and arrow then
            if not hookedArrow then
                hookedArrow = true
                arrow:HookScript("OnShow", function()
                    start()
                end)
                arrow:HookScript("OnHide", function()
                    start()
                end)
            end
            if arrow:IsShown() then
                ticker = C_Timer.NewTicker(1, tick)
            end
            tick()
        elseif not db.enabled and current and current.source == "rxp" then
            clearWaypoint()
        end
    end

    ---------------------------------------------------------------------------
    -- On-screen marker and edge arrow
    ---------------------------------------------------------------------------
    local function colour()
        local c = db.color or { r = 1, g = 0.82, b = 0.2 }
        return c.r, c.g, c.b
    end

    local function navFrame()
        return C_Navigation.GetFrame()
    end

    local function yards()
        local d = C_Navigation.GetDistance()
        if readable(d) and type(d) == "number" and d > 0 then
            return d
        end
    end

    -- Blizzard's own marker: hidden while ours is up, given back afterwards
    local hidBlizzard
    local function hideBlizzard()
        local st = _G.SuperTrackedFrame
        if not st then
            return
        end
        if db.hideBlizzard and current and frame and frame:IsShown() then
            if st:IsShown() then
                st:Hide()
                hidBlizzard = true
            end
        elseif hidBlizzard then
            hidBlizzard = nil
            if C_SuperTrack.IsSuperTrackingAnything() then
                st:Show()
            end
        end
    end

    -- "120 yd  ·  45s": ETA from your current speed (mounts and buffs
    -- included); left out while you're standing still
    local function distText(dist)
        if not dist then
            return
        end
        local parts = {}
        if db.distance then
            parts[1] = ("%d yd"):format(math.floor(dist))
        end
        if db.eta then
            local speed = GetUnitSpeed("player")
            if readable(speed) and type(speed) == "number" and speed > 0 then
                local t = math.floor(dist / speed + 0.5)
                parts[#parts + 1] = t >= 60 and ("%dm %02ds"):format(math.floor(t / 60), t % 60) or (t .. "s")
            end
        end
        return #parts > 0 and table.concat(parts, "  ·  ") or nil
    end

    local function update(self)
        local nav = current and navFrame()
        if not nav then
            self.pin:Hide()
            self.arrow:Hide()
            return
        end
        local nx, ny = nav:GetCenter()
        if not nx then
            self.pin:Hide()
            self.arrow:Hide()
            return
        end
        -- navigation frame centre in UIParent units
        local scale = nav:GetEffectiveScale() / UIParent:GetEffectiveScale()
        nx, ny = nx * scale, ny * scale
        local w, h = UIParent:GetSize()
        local dist = yards()
        local near = dist and dist <= db.arrive
        local margin = math.min(w, h) * 0.06
        local clamped = nx < margin or nx > w - margin or ny < margin or ny > h - margin

        local r, g, b = colour()
        if near then
            self.pin:Hide()
            self.arrow:Hide()
            return
        end
        if clamped and db.arrow then
            self.pin:Hide()
            local dx, dy = nx - w / 2, ny - h / 2
            local ang = math.atan2(dy, dx)
            local rx, ry = w * db.edge / 100, h * db.edge / 100
            self.arrow:ClearAllPoints()
            self.arrow:SetPoint("CENTER", UIParent, "CENTER", math.cos(ang) * rx, math.sin(ang) * ry)
            self.arrow:SetSize(db.arrowSize, db.arrowSize)
            self.arrow.tex:SetRotation(ang - math.pi / 2)
            self.arrow.edge:SetRotation(ang - math.pi / 2)
            self.arrow.tex:SetVertexColor(r, g, b)
            M.Label(self.arrow, distText(dist))
            self.arrow:Show()
        elseif not clamped and db.marker then
            self.arrow:Hide()
            local p = self.pin
            p:ClearAllPoints()
            p:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", nx, ny)
            local sz = db.markerSize
            p.tex:SetSize(sz, sz)
            p.edge:SetSize(sz, sz)
            p.beam:SetSize(sz * 0.5, sz * 2)
            p.glow:SetSize(sz * 1.6, sz * 0.6)
            p.tex:SetVertexColor(r, g, b)
            p.beam:SetVertexColor(r, g, b, 0.7)
            p.glow:SetVertexColor(r, g, b)
            p.name:SetText(current.name or "")
            M.Label(p, distText(dist))
            local a = 1
            if db.fadeNear and dist and dist < 40 then
                a = 0.35 + 0.65 * (dist - db.arrive) / math.max(1, 40 - db.arrive)
            end
            p:SetAlpha(a)
            p:Show()
        else
            self.pin:Hide()
            self.arrow:Hide()
        end
    end

    local function build()
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetAllPoints(UIParent)
        frame:SetFrameStrata("BACKGROUND")

        -- distance in a small dark pill
        local function label(parent)
            local bg = parent:CreateTexture(nil, "BORDER")
            bg:SetColorTexture(0, 0, 0, 0.6)
            parent.pill = bg
            parent.dist = parent:CreateFontString(nil, "OVERLAY")
            bg:SetPoint("TOPLEFT", parent.dist, "TOPLEFT", -4, 2)
            bg:SetPoint("BOTTOMRIGHT", parent.dist, "BOTTOMRIGHT", 4, -2)
        end

        -- pin: ground glow + light beam, outlined pin above them
        local pin = CreateFrame("Frame", nil, frame)
        pin:SetSize(200, 80)
        pin.glow = pin:CreateTexture(nil, "BACKGROUND")
        pin.glow:SetTexture(MEDIA .. "glow")
        pin.glow:SetBlendMode("ADD")
        pin.glow:SetPoint("CENTER", pin, "BOTTOM", 0, 0)
        pin.beam = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
        pin.beam:SetTexture(MEDIA .. "beam")
        pin.beam:SetBlendMode("ADD")
        pin.beam:SetPoint("BOTTOM", 0, 0)
        pin.edge = pin:CreateTexture(nil, "ARTWORK")
        pin.edge:SetTexture(MEDIA .. "pin_edge")
        pin.edge:SetVertexColor(0, 0, 0, 0.85)
        pin.edge:SetPoint("BOTTOM", pin.beam, "TOP", 0, -4)
        pin.tex = pin:CreateTexture(nil, "ARTWORK", nil, 1)
        pin.tex:SetTexture(MEDIA .. "pin")
        pin.tex:SetPoint("CENTER", pin.edge)
        label(pin)
        pin.dist:SetPoint("BOTTOM", pin.tex, "TOP", 0, 4)
        pin.name = pin:CreateFontString(nil, "OVERLAY")
        pin.name:SetPoint("BOTTOM", pin.dist, "TOP", 0, 5)
        pin.name:SetWidth(260)
        pin.name:SetWordWrap(true)
        local pulse = pin:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local a = pulse:CreateAnimation("Alpha")
        a:SetTarget(pin.glow)
        a:SetFromAlpha(0.9)
        a:SetToAlpha(0.35)
        a:SetDuration(1.1)
        a:SetSmoothing("IN_OUT")
        pulse:Play()
        frame.pin = pin

        local arrow = CreateFrame("Frame", nil, frame)
        arrow.edge = arrow:CreateTexture(nil, "ARTWORK")
        arrow.edge:SetAllPoints()
        arrow.edge:SetTexture(MEDIA .. "arrow_edge")
        arrow.edge:SetVertexColor(0, 0, 0, 0.85)
        arrow.tex = arrow:CreateTexture(nil, "ARTWORK", nil, 1)
        arrow.tex:SetAllPoints()
        arrow.tex:SetTexture(MEDIA .. "arrow")
        label(arrow)
        arrow.dist:SetPoint("TOP", arrow, "BOTTOM", 0, -4)
        frame.arrow = arrow

        local acc = 0
        frame:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt
            if acc >= 0.02 then
                acc = 0
                update(self)
            end
        end)
        frame:SetScript("OnShow", hideBlizzard)
        frame:SetScript("OnHide", hideBlizzard)
        if _G.SuperTrackedFrame then
            hooksecurefunc(SuperTrackedFrame, "Show", hideBlizzard)
            hooksecurefunc(SuperTrackedFrame, "SetShown", hideBlizzard)
        end
    end

    function M.Label(p, text)
        p.dist:SetText(text or "")
        p.pill:SetShown(text ~= nil)
    end

    function M.Style()
        if not frame then
            return
        end
        local fs = db.textSize
        frame.pin.name:SetFont(FF.FONT, fs, "OUTLINE")
        frame.pin.dist:SetFont(FF.FONT, math.max(8, fs - 1), "OUTLINE")
        frame.arrow.dist:SetFont(FF.FONT, math.max(8, fs - 1), "OUTLINE")
        hideBlizzard()
    end

    function M.Show()
        if not frame then
            build()
        end
        M.Style()
        frame:Show()
    end

    -- Someone else (map click, quest tracking) took over the super tracking
    local function trackingChanged()
        if current and not C_SuperTrack.IsSuperTrackingUserWaypoint() then
            if frame then
                frame:Hide()
            end
        elseif current and frame then
            frame:Show()
        end
    end
    local function waypointChanged()
        if current and not C_Map.HasUserWaypoint() then
            current = nil -- removed from the map by the player
            M.Watch(false)
            if frame then
                frame:Hide()
            end
        end
    end
    -- only while one of our waypoints is placed
    function M.Watch(on)
        FF.Listen("SUPER_TRACKING_CHANGED", trackingChanged, on)
        FF.Listen("USER_WAYPOINT_UPDATED", waypointChanged, on)
    end

    FF.On("FF_READY", function()
        C_Timer.After(3, start) -- RXP builds its arrow after login
    end)
    FF.On("ADDON_LOADED", function(_, name)
        if name == "RXPGuides" then
            C_Timer.After(2, start)
        end
    end)

    ---------------------------------------------------------------------------
    -- /ff way
    ---------------------------------------------------------------------------
    FF.Command("way", function(rest)
        if rest:lower() == "clear" or rest == "" then
            clearWaypoint()
            start()
            return
        end
        local x, y, name = rest:gsub(",", " "):match("^%s*([%d%.]+)%s+([%d%.]+)%s*(.-)%s*$")
        local mapID = C_Map.GetBestMapForUnit("player")
        if not (x and mapID) then
            FF.print("Usage: /ff way <x> <y> [name]  or  /ff way clear")
            return
        end
        if not setWaypoint(mapID, tonumber(x), tonumber(y), name ~= "" and name or nil, "manual") then
            FF.print("Can't place a waypoint on this map.")
        end
    end, "waypoint: 'way <x> <y> [name]' in this zone, 'way clear' back to the guide")

    ---------------------------------------------------------------------------
    -- Settings
    ---------------------------------------------------------------------------

    FF.Settings("Waypoints", function(L)
        L:Desc("Built-in waypoint: follows RestedXP's guide arrow and pins the current step in the world, with an arrow at the screen edge when it's off screen. /ff way <x> <y> places one by hand.")
        local status = L:Custom(22, function(f)
            f.text = FF.Text(f, "small")
            f.text:SetPoint("TOPLEFT", 12, -2)
            f.text:SetJustifyH("LEFT")
        end)
        L:Track({
            Refresh = function()
                local rxp = _G.RXPG_ARROW ~= nil
                status.text:SetText("RestedXP guides: " .. (rxp and (FF.Hex(FF.C.good) .. "found|r")
                    or (FF.Hex(FF.C.muted) .. "not loaded - manual waypoints only|r")))
            end,
        })
        L:Header("Guide")
        L:Toggle("Follow the RestedXP guide", db, "enabled", { onChange = start })
        L:Buttons({
            { "Point at the current step", function()
                if current and current.source == "manual" then
                    clearWaypoint()
                end
                current = nil
                start()
            end },
            { "Clear waypoint", function()
                clearWaypoint()
            end },
        })

        L:Header("Marker")
        L:Toggle("Show the marker in the world", db, "marker")
        local mk = function() return db.marker end
        L:Slider("Marker size", db, "markerSize", 12, 64, 1, { dep = mk, indent = 12 })
        L:Toggle("Fade when getting close", db, "fadeNear", { dep = mk, indent = 12 })
        L:Toggle("Show distance", db, "distance")
        L:Toggle("Show ETA", db, "eta", { tip = "Time to arrive at your current speed (hidden while standing still)" })
        L:Slider("Text size", db, "textSize", 8, 20, 1, { onChange = M.Style })
        L:Slider("Hide when within", db, "arrive", 0, 30, 1, { fmt = function(v) return v .. " yd" end })
        L:Color("Colour", db, "color", { r = 1, g = 0.82, b = 0.2 })

        L:Header("Off-screen arrow")
        L:Toggle("Edge arrow when off screen", db, "arrow")
        local ar = function() return db.arrow end
        L:Slider("Arrow size", db, "arrowSize", 20, 80, 2, { dep = ar, indent = 12 })
        L:Slider("Distance from centre", db, "edge", 15, 48, 1, { dep = ar, indent = 12, fmt = function(v) return v .. "%" end })

        L:Header("Blizzard")
        L:Toggle("Hide Blizzard's own waypoint marker", db, "hideBlizzard", { onChange = M.Style,
            tip = "While a Fresh Fixes waypoint is shown" })
    end)
end)
