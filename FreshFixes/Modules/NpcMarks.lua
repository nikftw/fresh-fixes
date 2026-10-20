local _, FF = ...
FF.Module("NpcMarks")

-- Auto-mark NPCs: give each raid marker a list of NPC IDs; hovering such a mob
-- while holding the chosen key marks it. Event-driven only (mouseover), no
-- polling. Never re-marks a unit that already has the right marker.
FF.Init("NpcMarks", function()
    local readable = FF.readable
    local db = FF.DB("npcmarks", { modifier = "SHIFT" })
    db.ids = db.ids or {} -- [1..8] = "12459, 12457"

    local MARKS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
    local byNpc = {} -- [npcID] = marker
    local function rebuild()
        byNpc = {}
        for i = 1, 8 do
            local list = db.ids[i]
            if type(list) == "string" then
                for id in list:gmatch("%d+") do
                    id = tonumber(id)
                    if id and byNpc[id] == nil then byNpc[id] = i end
                end
            end
        end
    end
    rebuild()

    local MODS = {
        SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown,
        NONE = function() return true end,
    }
    local function canMark()
        return not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    local function npcID(unit)
        local guid = UnitGUID(unit)
        if not readable(guid) or type(guid) ~= "string" then return end
        local kind, _, _, _, _, id = strsplit("-", guid)
        if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    end

    local function onMouseover()
        local held = MODS[db.modifier] or MODS.SHIFT
        if not held() or not next(byNpc) then return end
        if not UnitExists("mouseover") or UnitIsPlayer("mouseover") or UnitIsDead("mouseover") then return end
        local id = npcID("mouseover")
        local mark = id and byNpc[id]
        if not mark or not canMark() then return end
        local current = GetRaidTargetIndex("mouseover")
        if not readable(current) or current == mark then return end
        SetRaidTarget("mouseover", mark)
    end

    local function apply()
        FF.Listen("UPDATE_MOUSEOVER_UNIT", onMouseover, next(byNpc) ~= nil)
    end
    FF.On("FF_READY", apply)

    -- Player always-mark (Group Setup) using the same marker?
    local function clash(i)
        local g = FreshFixesDB and FreshFixesDB.groups
        if not (g and g.autoMark and FF.IsEnabled("Groups")) then return false end
        local list = g.marks and g.marks[i]
        return type(list) == "string" and list:find("%S") ~= nil
    end

    FF.Settings("NpcMarks", function(L)
        L:Header("Auto-mark NPCs")
        L:Desc("List NPC IDs for each marker (comma separated). Hover one of those mobs while holding the key below to mark it. Needs lead or assist in raids; works solo and in parties.")
        L:Select("Mark while holding", db, "modifier", {
            { "SHIFT", "Shift" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "NONE", "Nothing (always on hover)" },
        }, { width = 200 })
        for i = 1, 8 do
            local box = L:Input(("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t  %s"):format(i, MARKS[i]), db.ids, i, {
                width = 260, indent = 12, onChange = function() rebuild(); apply() end,
                tip = "NPC IDs, e.g. 12459, 12457",
            })
            local warn = CreateFrame("Frame", nil, box)
            warn:SetSize(16, 16)
            warn:SetPoint("LEFT", box, "RIGHT", 6, 0)
            local t = warn:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
            warn:EnableMouse(true)
            warn:SetScript("OnEnter", function(self)
                FF.Tip(self, ("Group Setup's always-mark players also uses %s. Both will fight over it."):format(MARKS[i]), "Marker in use")
            end)
            warn:SetScript("OnLeave", FF.HideTip)
            local function check() warn:SetShown(clash(i)) end
            box:HookScript("OnShow", check)
            check()
        end
    end)
end)
