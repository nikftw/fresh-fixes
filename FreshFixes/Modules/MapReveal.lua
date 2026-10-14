local _, FF = ...
local M = FF.Module("Map")

-- Unexplored-area reveal and extra map icons (Leatrix Maps style), drawn from
-- Blizzard's own data for this build (Modules\MapData.lua, generated).
--  * Reveal: hooks the map's exploration pin and draws every overlay the
--    player hasn't explored yet, with the same tiling math Blizzard uses.
--  * Icons: flight points from Blizzard's data (MapData.lua) and Leatrix's
--    hand-placed icons (MapIcons.lua): spirit healers, boats, portals, zone
--    crossings, dungeon and raid entrances.

-- Pin template mixin (FreshFixes\MapPins.xml). Filled in at login, before any
-- pin is created; the template only resolves it when a pin is made.
FreshFixesMapPinMixin = FreshFixesMapPinMixin or {}

FF.Init("Map", function()
    local readable = FF.readable
    local db = FF.DB("mapreveal", {
        reveal = true, tint = false, icons = true,
        flights = true, myFactionOnly = true, instances = true,
        spirits = true, travel = true, arrows = true, iconScale = 1,
    })

    local TEMPLATE = "FreshFixesMapPinTemplate"
    local KINDS = {
        FlightA = { atlas = "TaxiNode_Alliance", label = "Flight point" },
        FlightH = { atlas = "TaxiNode_Horde", label = "Flight point" },
        FlightN = { atlas = "TaxiNode_Neutral", label = "Flight point" },
        Dungeon = { atlas = "Dungeon", label = "Dungeon", size = 24 },
        Raid = { atlas = "Raid", label = "Raid", size = 24 },
        Spirit = { atlas = "Vehicle-TempleofKotmogu-GreenBall", label = "Spirit healer", size = 16 },
        Boat = { atlas = "Vehicle-TempleofKotmogu-CyanBall", label = "Boat", size = 18 },
        Zeppelin = { atlas = "Vehicle-TempleofKotmogu-CyanBall", label = "Zeppelin", size = 18 },
        Tram = { atlas = "Vehicle-TempleofKotmogu-CyanBall", label = "Tram", size = 18 },
        Portal = { atlas = "Vehicle-TempleofKotmogu-CyanBall", label = "Portal", size = 18 },
        Arrow = { atlas = "Garr_LevelUpgradeArrow", label = "Zone crossing", size = 18 },
    }

    ---------------------------------------------------------------------------
    -- Reveal
    ---------------------------------------------------------------------------
    local cache = {}

    local function overlaysFor(artID)
        if cache[artID] ~= nil then
            return cache[artID]
        end
        local s = FF.MapReveal and FF.MapReveal[artID]
        local list = false
        if s then
            list = {}
            for entry in s:gmatch("[^;]+") do
                local w, h, x, y, ids = entry:match("^(%d+):(%d+):(%d+):(%d+)=(.+)$")
                if w then
                    local files = {}
                    for id in ids:gmatch("%d+") do
                        files[#files + 1] = tonumber(id)
                    end
                    list[#list + 1] = {
                        w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y),
                        files = files, key = w .. ":" .. h .. ":" .. x .. ":" .. y,
                    }
                end
            end
        end
        cache[artID] = list
        return list
    end

    local function fileSize(px)
        local f = 16
        while f < px do
            f = f * 2
        end
        return f
    end

    local function refreshReveal(pin)
        local pool = pin.ffTextures
        if not pool then
            pool = {}
            pin.ffTextures = pool
        end
        for _, t in ipairs(pool) do
            t:Hide()
        end
        if not db.reveal then
            return
        end
        local map = pin:GetMap()
        local mapID = map and map:GetMapID()
        local artID = mapID and C_Map.GetMapArtID(mapID)
        local overlays = artID and overlaysFor(artID)
        if not overlays then
            return
        end
        local explored = {}
        for _, e in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
            explored[e.textureWidth .. ":" .. e.textureHeight .. ":" .. e.offsetX .. ":" .. e.offsetY] = true
        end
        local layers = C_Map.GetMapArtLayers(mapID)
        local container = map.GetCanvasContainer and map:GetCanvasContainer()
        local layer = layers and layers[container and container.GetCurrentLayerIndex and container:GetCurrentLayerIndex() or 1]
        if not layer then
            return
        end
        local TW, TH = layer.tileWidth, layer.tileHeight
        local n = 0
        for _, o in ipairs(overlays) do
            if not explored[o.key] then
                local wide, tall = math.ceil(o.w / TW), math.ceil(o.h / TH)
                for j = 1, tall do
                    local ph, fh = TH, TH
                    if j == tall then
                        ph = o.h % TH
                        if ph == 0 then
                            ph = TH
                        end
                        fh = fileSize(ph)
                    end
                    for k = 1, wide do
                        local pw, fw = TW, TW
                        if k == wide then
                            pw = o.w % TW
                            if pw == 0 then
                                pw = TW
                            end
                            fw = fileSize(pw)
                        end
                        local file = o.files[(j - 1) * wide + k]
                        if file then
                            n = n + 1
                            local t = pool[n]
                            if not t then
                                t = pin:CreateTexture(nil, "ARTWORK", nil, -1)
                                pool[n] = t
                            end
                            t:ClearAllPoints()
                            t:SetSize(pw, ph)
                            t:SetTexCoord(0, pw / fw, 0, ph / fh)
                            t:SetPoint("TOPLEFT", pin, "TOPLEFT", o.x + TW * (k - 1), -(o.y + TH * (j - 1)))
                            t:SetTexture(file) -- no TRILINEAR: it can hard-crash this client
                            if db.tint then
                                local c = db.tintColor or { r = 0.6, g = 0.6, b = 0.85 }
                                t:SetVertexColor(c.r, c.g, c.b)
                            else
                                t:SetVertexColor(1, 1, 1)
                            end
                            t:Show()
                        end
                    end
                end
            end
        end
    end

    local function hookExploration(map)
        if not map or not map.EnumeratePinsByTemplate then
            return
        end
        for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
            if not pin.ffHooked and pin.RefreshOverlays then
                pin.ffHooked = true
                hooksecurefunc(pin, "RefreshOverlays", refreshReveal)
                refreshReveal(pin)
            end
        end
    end

    local function refreshAllReveal()
        for _, map in ipairs({ WorldMapFrame, BattlefieldMapFrame }) do
            if map and map.EnumeratePinsByTemplate then
                for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                    refreshReveal(pin)
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Icons
    ---------------------------------------------------------------------------
    -- World -> map position. Which vector component the API wants first is
    -- calibrated once against the player's own position (out of instances).
    local function calibrate()
        if IsInInstance() then
            return
        end
        local a, b, _, inst = UnitPosition("player")
        local map = C_Map.GetBestMapForUnit("player")
        local real = map and C_Map.GetPlayerMapPosition(map, "player")
        if not (readable(a) and a and real and inst) then
            return
        end
        local rx, ry = real:GetXY()
        local function dist(v1, v2)
            local _, p = C_Map.GetMapPosFromWorldPos(inst, CreateVector2D(v1, v2), map)
            if not p then
                return 99
            end
            local x, y = p:GetXY()
            return math.abs(x - rx) + math.abs(y - ry)
        end
        local straight, swapped = dist(a, b), dist(b, a)
        if math.min(straight, swapped) < 0.02 then
            FF.core.mapSwap = swapped < straight
        end
    end

    local function toMap(icon, mapID)
        local a, b = icon[3], icon[4]
        if FF.core.mapSwap then
            a, b = b, a
        end
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, icon[2], CreateVector2D(a, b), mapID)
        if ok and pos then
            local x, y = pos:GetXY()
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                return x, y
            end
        end
    end

    local faction = UnitFactionGroup("player")
    local TRAVEL = { Boat = true, Zeppelin = true, Tram = true, Portal = true }
    -- side: "A" / "H" / "N" (or nil) - whose icon it is
    local function wanted(kind, side)
        if kind:find("^Flight") then
            side = kind:sub(-1)
            if not db.flights then
                return false
            end
        elseif kind == "Dungeon" or kind == "Raid" then
            return db.instances
        elseif kind == "Spirit" then
            return db.spirits
        elseif kind == "Arrow" then
            return db.arrows
        elseif TRAVEL[kind] then
            if not db.travel then
                return false
            end
        end
        if db.myFactionOnly and ((side == "A" and faction ~= "Alliance") or (side == "H" and faction ~= "Horde")) then
            return false
        end
        return true
    end

    local providers = {}

    local function setupPins()
        if not (MapCanvasPinMixin and MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then
            return
        end
        Mixin(FreshFixesMapPinMixin, MapCanvasPinMixin)

        function FreshFixesMapPinMixin:OnLoad()
            self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
            self:SetScalingLimits(1, 1.0, 1.2)
        end

        function FreshFixesMapPinMixin:OnAcquired(icon, x, y)
            self.icon = icon
            local k = KINDS[icon[1]] or KINDS.Portal
            local size = (k.size or 20) * (db.iconScale or 1)
            self:SetSize(size, size)
            if C_Texture.GetAtlasInfo(k.atlas) then
                self.Texture:SetAtlas(k.atlas)
            else
                self.Texture:SetTexture("Interface\\Minimap\\POIIcons")
            end
            self.Texture:SetRotation(icon[1] == "Arrow" and (icon[7] or 0) or 0)
            self:SetPosition(x, y)
        end

        function FreshFixesMapPinMixin:OnMouseEnter()
            local icon = self.icon
            local name = icon[5] or ""
            local desc = icon[6] or (KINDS[icon[1]] and KINDS[icon[1]].label)
            if desc and desc ~= name and name ~= "" then
                FF.Tip(self, desc, name)
            else
                FF.Tip(self, name ~= "" and name or desc)
            end
        end

        -- Zone crossings, boats and portals open the zone they lead to
        function FreshFixesMapPinMixin:OnMouseClickAction(button)
            local link = self.icon and self.icon[8]
            if button == "LeftButton" and type(link) == "number" and link > 0 then
                self:GetMap():SetMapID(link)
            end
        end

        function FreshFixesMapPinMixin:OnMouseLeave()
            FF.HideTip()
        end

        local function newProvider()
            local p = CreateFromMixins(MapCanvasDataProviderMixin)
            function p:RemoveAllData()
                self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
            end
            function p:RefreshAllData()
                self:RemoveAllData()
                if not db.icons then
                    return
                end
                local map = self:GetMap()
                local mapID = map:GetMapID()
                local info = mapID and C_Map.GetMapInfo(mapID)
                if not info or (info.mapType or 0) < 3 then
                    return -- zones, cities and dungeons only (not continents)
                end
                local function add(icon)
                    if wanted(icon[1]) then
                        local x, y = toMap(icon, mapID)
                        if x then
                            map:AcquirePin(TEMPLATE, icon, x, y)
                        end
                    end
                end
                -- Hand-placed icons for this zone (Leatrix data), already in map coordinates
                for _, icon in ipairs(FF.MapZoneIcons and FF.MapZoneIcons[mapID] or {}) do
                    if wanted(icon[1], icon[2]) then
                        map:AcquirePin(TEMPLATE, icon, icon[3], icon[4])
                    end
                end
                for _, icon in ipairs(FF.MapIcons or {}) do
                    add(icon)
                end
            end
            function p:OnMapChanged()
                self:RefreshAllData()
            end
            return p
        end

        providers.world = newProvider()
        WorldMapFrame:AddDataProvider(providers.world)
    end

    local function attachBattlefield()
        if BattlefieldMapFrame and not providers.battlefield and providers.world then
            local p = CreateFromMixins(providers.world)
            providers.battlefield = p
            BattlefieldMapFrame:AddDataProvider(p)
            BattlefieldMapFrame:HookScript("OnShow", function()
                hookExploration(BattlefieldMapFrame)
            end)
        end
    end

    local function refreshIcons()
        for _, p in pairs(providers) do
            if p:GetMap() then
                p:RefreshAllData()
            end
        end
    end

    FF.On("FF_READY", function()
        pcall(setupPins)
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function()
                hookExploration(WorldMapFrame)
            end)
        end
        attachBattlefield()
        C_Timer.After(5, calibrate)
    end)
    FF.On("ADDON_LOADED", function(_, name)
        if name == "Blizzard_BattlefieldMap" then
            attachBattlefield()
        end
    end)
    FF.On("FF_ZONE", function()
        C_Timer.After(2, calibrate)
    end)

    FF.Settings("Map", function(L)
        local mdb = M.mapdb
        L:Header("Unexplored areas")
        L:Toggle("Show unexplored areas", db, "reveal", { onChange = refreshAllReveal })
        L:Toggle("Tint unexplored areas", db, "tint", { dep = function() return db.reveal end, onChange = refreshAllReveal, indent = 12 })
        L:Color("Tint colour", db, "tintColor", { r = 0.6, g = 0.6, b = 0.85 }, {
            dep = function() return db.reveal and db.tint end, onChange = refreshAllReveal, indent = 12 })

        L:Header("Map icons")
        L:Toggle("Show extra map icons", db, "icons", { onChange = refreshIcons })
        local on = function() return db.icons end
        L:Slider("Icon size", db, "iconScale", 0.5, 2, 0.05, { dep = on, onChange = refreshIcons })
        L:Toggle("Flight points", db, "flights", { dep = on, onChange = refreshIcons, indent = 12 })
        L:Toggle("Dungeon and raid entrances", db, "instances", { dep = on, onChange = refreshIcons, indent = 12 })
        L:Toggle("Spirit healers", db, "spirits", { dep = on, onChange = refreshIcons, indent = 12 })
        L:Toggle("Boats, zeppelins, trams and portals", db, "travel", { dep = on, onChange = refreshIcons, indent = 12 })
        L:Toggle("Zone crossings (click to open)", db, "arrows", { dep = on, onChange = refreshIcons, indent = 12 })
        L:Toggle("Only my faction's travel points", db, "myFactionOnly", { dep = on, onChange = refreshIcons })

        L:Header("World map frame")
        L:Slider("Map scale", mdb, "scale", 0.4, 1.5, 0.05, { onChange = M.applyScale })
        L:Toggle("Disable map fade while moving", mdb, "noFade", { onChange = M.applyFade })
        L:Buttons({ { "Unlock / lock map", function()
            mdb.unlock = not mdb.unlock
        end } })
    end)
end)
