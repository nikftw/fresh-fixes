local _, FF = ...
local M = FF.Module("Nicknames")

-- Nicknames on third-party unit frames. Each integration only runs when
-- that addon is loaded.
--   ElvUI : tags [ff:name], [ff:name:veryshort|short|medium|long], [ff:target]
--   Grid2 : status "Fresh Fixes Nickname" (assign it to a text indicator)
--   VuhDo : bar names replaced with nicknames
--   EllesmereUI (EUI) : raid + unit frames. EUI asks a fixed list of nickname
--           addons; we answer through the one it calls by name
--           (LiquidAPI.GetNicknameForEllesmereUI). If the real Liquid addon is
--           installed we chain to it instead of replacing it. EUI unit frames
--           also need EUI's own "Show nicknames" option turned on.
---------------------------------------------------------------------------
-- Grid2. Grid2 creates its statuses from its saved settings while it loads,
-- so ours must exist by then: register the moment Grid2 loads (as RG Aliases
-- does), not when our modules start at login - that was too late, and the
-- indicator stayed empty.
---------------------------------------------------------------------------
local grid2Status, grid2Hooked
local function grid2Name(unit)
    if not unit or not FF.readable(unit) or not UnitExists(unit) then
        return
    end
    return (M.ForUnit and M.ForUnit(unit)) or UnitName(unit)
end

local function hookGrid2()
    local Grid2 = _G.Grid2
    if grid2Hooked or not (Grid2 and Grid2.statusPrototype) then
        return
    end
    grid2Hooked = true
    local KEY = "Fresh Fixes Nickname"
    local status = Grid2.statusPrototype:new(KEY)
    status.IsActive = Grid2.statusLibrary.IsActive
    function status:GetText(unit)
        return grid2Name(unit)
    end
    function status:UNIT_NAME_UPDATE(_, unit)
        self:UpdateIndicators(unit)
    end
    function status:OnEnable()
        self:RegisterEvent("UNIT_NAME_UPDATE")
    end
    function status:OnDisable()
        self:UnregisterEvent("UNIT_NAME_UPDATE")
    end
    Grid2.setupFunc[KEY] = function(baseKey, dbx)
        Grid2:RegisterStatus(status, { "text" }, baseKey, dbx)
        return status
    end
    Grid2:DbSetStatusDefaultValue(KEY, { type = KEY, color1 = { r = 0.4, g = 0.8, b = 1, a = 1 } })
    grid2Status = status
end

-- Off only if the Nicknames module or its Grid2 option was turned off
local function grid2Wanted()
    local saved = FreshFixesDB or {}
    local modules = saved.core and saved.core.modules
    if modules and modules.Nicknames == false then
        return false
    end
    return not (saved.nicknames and saved.nicknames.grid2 == false)
end

do
    EventUtil.ContinueOnAddOnLoaded("Grid2", function()
        if grid2Wanted() then
            pcall(hookGrid2)
        end
    end)
end

local function refreshGrid2()
    if grid2Status and grid2Status.UpdateAllUnits then
        pcall(grid2Status.UpdateAllUnits, grid2Status)
    end
end

FF.Init("Nicknames", function()
    local readable = FF.readable
    local hooked = {}

    local function nameFor(unit)
        if not unit or not readable(unit) or not UnitExists(unit) then
            return
        end
        return M.ForUnit(unit) or UnitName(unit)
    end

    local function cut(s, n)
        if not s then
            return
        end
        if string.utf8sub then
            return string.utf8sub(s, 1, n)
        end
        return s:sub(1, n)
    end

    ---------------------------------------------------------------------------
    -- ElvUI
    ---------------------------------------------------------------------------
    local LENGTHS = { veryshort = 5, short = 10, medium = 15, long = 20 }

    local function hookElvUI()
        if hooked.elvui or not ElvUI then
            return
        end
        local E = unpack(ElvUI)
        if not (E and E.AddTag) then
            return
        end
        hooked.elvui = true
        local events = "UNIT_NAME_UPDATE INSTANCE_ENCOUNTER_ENGAGE_UNIT"
        E:AddTag("ff:name", events, function(unit)
            return nameFor(unit)
        end)
        for len, n in pairs(LENGTHS) do
            E:AddTag("ff:name:" .. len, events, function(unit)
                return cut(nameFor(unit), n)
            end)
        end
        E:AddTag("ff:target", "UNIT_TARGET", function(unit)
            return nameFor(unit .. "target")
        end)
        if E.AddTagInfo then
            local cat = "Fresh Fixes"
            pcall(E.AddTagInfo, E, "ff:name", cat, "Nickname, or the unit's name")
            for len, n in pairs(LENGTHS) do
                pcall(E.AddTagInfo, E, "ff:name:" .. len, cat, ("Nickname, max %d letters"):format(n))
            end
            pcall(E.AddTagInfo, E, "ff:target", cat, "Target's nickname")
        end
    end

    local function refreshElvUI()
        local oUF = ElvUF or (ElvUI and ElvUI[1] and ElvUI[1].oUF)
        if hooked.elvui and oUF and oUF.Tags and oUF.Tags.RefreshMethods then
            pcall(oUF.Tags.RefreshMethods, oUF.Tags, "ff:name")
            for len in pairs(LENGTHS) do
                pcall(oUF.Tags.RefreshMethods, oUF.Tags, "ff:name:" .. len)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- VuhDo
    ---------------------------------------------------------------------------
    local function hookVuhDo()
        if hooked.vuhdo or not VUHDO_getBarText then
            return
        end
        hooked.vuhdo = true
        local done = {}
        hooksecurefunc("VUHDO_getBarText", function(bar)
            local textName = bar and bar.GetName and bar:GetName() and (bar:GetName() .. "TxPnlUnN")
            local fs = textName and _G[textName]
            if not fs or done[fs] then
                return
            end
            done[fs] = true
            local button = bar:GetParent()
            hooksecurefunc(fs, "SetText", function(self, txt)
                if self.ffSetting or not txt or not readable(txt) then
                    return
                end
                local unit = button and button.GetAttribute and button:GetAttribute("unit")
                local nick = unit and M.ForUnit(unit)
                if not nick then
                    return
                end
                local real = UnitName(unit)
                local new = real and txt:find(real, 1, true) and txt:gsub(real:gsub("%p", "%%%0"), nick, 1)
                if new and new ~= txt then
                    self.ffSetting = true
                    self:SetText(new)
                    self.ffSetting = nil
                end
            end)
        end)
    end

    ---------------------------------------------------------------------------
    -- EllesmereUI
    ---------------------------------------------------------------------------
    local function ellesmereLoaded()
        return C_AddOns.IsAddOnLoaded("EllesmereUIRaidFrames") or C_AddOns.IsAddOnLoaded("EllesmereUIUnitFrames")
    end

    local function hookEllesmere()
        if hooked.ellesmere or not ellesmereLoaded() then
            return
        end
        hooked.ellesmere = true
        LiquidAPI = LiquidAPI or {}
        local previous = LiquidAPI.GetNicknameForEllesmereUI
        LiquidAPI.GetNicknameForEllesmereUI = function(name)
            return M.Get(name) or (previous and previous(name)) or nil
        end
    end

    local function refreshEllesmere()
        if hooked.ellesmere and _G._EUF_RefreshUnitNames then
            pcall(_G._EUF_RefreshUnitNames)
        end
    end

    ---------------------------------------------------------------------------
    local function hookAll()
        local db = M.db or {}
        if db.elvui ~= false then
            pcall(hookElvUI)
        end
        if db.grid2 ~= false then
            pcall(hookGrid2)
        end
        if db.vuhdo ~= false then
            pcall(hookVuhDo)
        end
        if db.ellesmere ~= false then
            pcall(hookEllesmere)
        end
    end

    -- Called by Nicknames.lua whenever the map changes.
    M.RefreshAddons = function()
        refreshElvUI()
        refreshGrid2()
        refreshEllesmere()
    end

    FF.On("FF_READY", hookAll)
    FF.On("ADDON_LOADED", function(_, name)
        if name == "ElvUI" or name == "Grid2" or name == "VuhDo"
            or name == "EllesmereUIRaidFrames" or name == "EllesmereUIUnitFrames" then
            hookAll()
        end
    end)
end)
