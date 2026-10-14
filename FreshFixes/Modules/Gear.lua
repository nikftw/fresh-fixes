local _, FF = ...
local M = FF.Module("Gear")

-- Gear & enchant checker (Northern Sky / MRT style). Checks your own gear:
-- missing enchants, empty gem sockets, empty slots and item level. On ready
-- check everyone reports; "Raid request" (/ff gear) asks the raid and opens
-- the report window.
-- Comms tag "G":  S<ilvl>;<enchant slots>;<gem slots>;<empty slots>  ·  Q (ask)
FF.Init("Gear", function()
    local readable = FF.readable
    local db = FF.DB("gear", {
        onReadyCheck = false, summary = false, enchants = true, gems = false, empty = true,
        raidWarning = false, sound = false, soundKit = "RAID_WARNING", minIlvl = 0, summaryDelay = 8, showTitle = true,
    })
    -- Enchantable slots (Forever's rules may differ - change them in settings).
    if not db.slots then
        db.slots = { [1] = false, [2] = true, [3] = true, [15] = true, [5] = true, [9] = true, [10] = true,
            [7] = true, [8] = true, [16] = true, [17] = true, [18] = true }
    end

    local SLOT_NAMES = {
        [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
        [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1",
        [14] = "Trinket 2", [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
    }

    local getInstant = C_Item.GetItemInfoInstant
    local function itemInfo(link)
        local _, _, _, equipLoc, _, classID, subclassID = getInstant(link)
        return equipLoc, classID, subclassID
    end

    local function canEnchant(slot, link)
        if not db.slots[slot] then
            return false
        end
        local equipLoc, classID, subclassID = itemInfo(link)
        if slot == 17 then
            -- weapons and shields only (not held-in-off-hand items)
            return classID == 2 or (classID == 4 and subclassID == 6)
        elseif slot == 18 then
            -- ranged weapons, not wands / relics
            return classID == 2 and subclassID ~= 19 and select(2, UnitClass("player")) == "HUNTER"
        end
        return equipLoc ~= nil
    end

    local function hasEnchant(link)
        local enchant = link:match("item:%d+:(%d*)")
        return enchant and enchant ~= "" and enchant ~= "0"
    end

    local function emptySockets(link)
        local stats = C_Item.GetItemStats(link) or {}
        local sockets = 0
        for k, v in pairs(stats) do
            if type(k) == "string" and k:find("^EMPTY_SOCKET_") then
                sockets = sockets + v
            end
        end
        if sockets == 0 then
            return 0
        end
        local filled = 0
        for i = 1, sockets do
            local gem = C_Item.GetItemGem and C_Item.GetItemGem(link, i)
            if gem then
                filled = filled + 1
            end
        end
        return sockets - filled
    end

    -- Returns { ilvl, enchants = {slots}, gems = {slots}, empty = {slots}, items = {[slot] = itemID} }
    function M.Scan()
        local r = { enchants = {}, gems = {}, empty = {}, items = {} }
        local _, equipped = GetAverageItemLevel()
        r.ilvl = readable(equipped) and math.floor((equipped or 0) + 0.5) or 0
        local twoHand = false
        local mh = GetInventoryItemLink("player", 16)
        if mh then
            local loc = itemInfo(mh)
            twoHand = loc == "INVTYPE_2HWEAPON" or loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT"
        end
        for slot = 1, 18 do
            if slot ~= 4 then
                local link = GetInventoryItemLink("player", slot)
                if not link then
                    local optional = (slot == 17 and twoHand) or slot == 18
                    if db.empty and not optional then
                        r.empty[#r.empty + 1] = slot
                    end
                else
                    r.items[slot] = tonumber(link:match("item:(%d+)"))
                    if db.enchants and canEnchant(slot, link) and not hasEnchant(link) then
                        r.enchants[#r.enchants + 1] = slot
                    end
                    if db.gems and emptySockets(link) > 0 then
                        r.gems[#r.gems + 1] = slot
                    end
                end
            end
        end
        return r
    end

    local function names(slots)
        local out = {}
        for i, s in ipairs(slots) do
            out[i] = SLOT_NAMES[s] or tostring(s)
        end
        return table.concat(out, ", ")
    end

    local function problems(r)
        local out = {}
        if #r.enchants > 0 then
            out[#out + 1] = "Enchant: " .. names(r.enchants)
        end
        if #r.gems > 0 then
            out[#out + 1] = "Gem: " .. names(r.gems)
        end
        if #r.empty > 0 then
            out[#out + 1] = "Empty: " .. names(r.empty)
        end
        if db.minIlvl > 0 and r.ilvl > 0 and r.ilvl < db.minIlvl then
            out[#out + 1] = ("Item level %d (want %d)"):format(r.ilvl, db.minIlvl)
        end
        return out
    end

    local function encode(r)
        local items = {}
        for slot, id in pairs(r.items or {}) do
            items[#items + 1] = slot .. ":" .. id
        end
        return ("S%d;%s;%s;%s;%s"):format(r.ilvl, table.concat(r.enchants, ","), table.concat(r.gems, ","),
            table.concat(r.empty, ","), table.concat(items, ","))
    end

    local function decode(s)
        local ilvl, e, g, x, it = s:match("^S(%d+);([%d,]*);([%d,]*);([%d,]*);?([%d:,]*)$")
        if not ilvl then
            return
        end
        local items = {}
        for slot, id in (it or ""):gmatch("(%d+):(%d+)") do
            items[tonumber(slot)] = tonumber(id)
        end
        local function list(str)
            local t = {}
            for n in str:gmatch("%d+") do
                t[#t + 1] = tonumber(n)
            end
            return t
        end
        return { ilvl = tonumber(ilvl), enchants = list(e), gems = list(g), empty = list(x), items = items }
    end

    ---------------------------------------------------------------------------
    -- Raid view
    ---------------------------------------------------------------------------
    local reports = {} -- [key] = { name, class, r, t }
    local win, collecting

    local function store(key, display, r)
        local u = FF.UnitByKey(key)
        reports[key] = { name = display:match("^[^%-]+"), class = u and select(2, UnitClass(u)), r = r, t = GetTime() }
    end

    -- Paper-doll order for the slot icons
    local ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
    local SLOT_KEY = {
        [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [15] = "BackSlot", [5] = "ChestSlot",
        [9] = "WristSlot", [10] = "HandsSlot", [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot",
        [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
        [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot",
    }
    local emptyIcon = {}
    local function slotIcon(slot, id)
        if id then
            return C_Item.GetItemIconByID(id) or 134400
        end
        if emptyIcon[slot] == nil then
            local _, tex = GetInventorySlotInfo(SLOT_KEY[slot])
            emptyIcon[slot] = tex or 134400
        end
        return emptyIcon[slot]
    end

    local function lookup(list)
        local t = {}
        for _, v in ipairs(list) do
            t[v] = true
        end
        return t
    end

    -- Everyone who reported; players with issues first, then by item level.
    -- Each row: name, an icon per slot (E = missing enchant, G = empty gem
    -- socket, dimmed = empty slot), item level.
    function M.RefreshWindow()
        if not win or not win:IsShown() then
            return
        end
        local list, withIssues = {}, 0
        for _, rep in pairs(reports) do
            rep.issues = #rep.r.enchants + #rep.r.gems + #rep.r.empty
                + ((db.minIlvl > 0 and rep.r.ilvl > 0 and rep.r.ilvl < db.minIlvl) and 1 or 0)
            if rep.issues > 0 then
                withIssues = withIssues + 1
            end
            list[#list + 1] = rep
        end
        table.sort(list, function(a, b)
            if (a.issues > 0) ~= (b.issues > 0) then
                return a.issues > 0
            end
            if a.r.ilvl ~= b.r.ilvl then
                return a.r.ilvl > b.r.ilvl
            end
            return a.name < b.name
        end)
        local rows = {}
        for _, rep in ipairs(list) do
            local r = rep.r
            local ench, gems, empty = lookup(r.enchants), lookup(r.gems), lookup(r.empty)
            local badges = {}
            for _, slot in ipairs(ORDER) do
                local id = r.items and r.items[slot]
                local mark = (ench[slot] and "|cffff5050E|r" or "") .. (gems[slot] and "|cffffc040G|r" or "")
                badges[#badges + 1] = { icon = slotIcon(slot, id), text = mark, dim = not id }
                if empty[slot] then
                    badges[#badges].text = "|cffff5050X|r"
                end
            end
            local p = problems(r)
            local low = db.minIlvl > 0 and r.ilvl > 0 and r.ilvl < db.minIlvl
            rows[#rows + 1] = {
                text = FF.ClassColor(rep.class, rep.name) .. (rep.issues > 0 and ("  |cffff6060" .. rep.issues .. "|r") or ""),
                right = (low and "|cffff6060" or "") .. r.ilvl .. (low and "|r" or ""),
                badges = badges,
                tooltip = rep.name .. "\nItem level " .. r.ilvl .. (#p > 0 and ("\n" .. table.concat(p, "\n")) or "\nNo issues"),
            }
        end
        win.title:SetText(("Gear Check  %s%d reports, %d with issues|r"):format(FF.Hex(FF.C.muted), #list, withIssues))
        win:SetRows(rows)
    end

    local function makeWin()
        if not win then
            win = FF.ListWindow("Gear", "Gear Check", 120 + #ORDER * 18 + 34, 41)
            win.rightWidth = 24 -- item levels line up, so the slot icons do too
            win:SetTitleShown(db.showTitle)
        end
    end

    local function summarize()
        local got = collecting
        collecting = nil
        if not got then
            return
        end
        local issues, silent = {}, {}
        for _, u in ipairs(FF.GroupUnits()) do
            local key = FF.UnitKey(u)
            local name = UnitName(u) or "?"
            local rep = key and got[key]
            if not rep then
                silent[#silent + 1] = name
            else
                local p = problems(rep)
                if #p > 0 then
                    issues[#issues + 1] = ("%s (%d): %s"):format(name, rep.ilvl, table.concat(p, "; "))
                end
            end
        end
        FF.print("Gear check:")
        if #issues == 0 then
            print("  |cff00ff00No missing enchants, gems or items|r")
        end
        for _, l in ipairs(issues) do
            print("  " .. l)
        end
        if #silent > 0 then
            print("  |cff9d9d9dNo report:|r " .. table.concat(silent, ", "))
        end
    end

    local function report()
        local r = M.Scan()
        local display, key = FF.UnitIdentity("player")
        if key then
            store(key, display, r)
            if collecting then
                collecting[key] = r
            end
        end
        if IsInGroup() then
            FF.Send("G", encode(r), "GROUP")
        end
        M.RefreshWindow()
        return r
    end

    FF.OnComm("G", function(payload, channel, display, key)
        if channel == "GUILD" or channel == "WHISPER" or key == FF.UnitKey("player") then
            return
        end
        if payload == "Q" then
            C_Timer.After(math.random() * 2, report)
            return
        end
        local r = decode(payload)
        if r then
            store(key, display, r)
            if collecting then
                collecting[key] = r
            end
            M.RefreshWindow()
        end
    end)

    FF.On("READY_CHECK", function()
        if not db.onReadyCheck then
            return
        end
        if db.summary and FF.IsGroupLead() then
            collecting = {}
            C_Timer.After(db.summaryDelay, summarize)
        end
        local p = problems(report())
        if #p > 0 then
            if db.raidWarning then
                FF.Alert(table.concat(p, "  "))
            end
            if db.sound then
                FF.PlaySound(db.soundKit)
            end
        end
    end)

    FF.Settings("Gear", function(L)
        L:Header("What to check")
        L:Toggle("Missing enchants", db, "enchants")
        L:Toggle("Empty gem sockets", db, "gems")
        L:Toggle("Empty gear slots", db, "empty", { tip = "Shirt, tabard, ranged and a two-hander's off hand are ignored" })
        L:Slider("Warn below item level", db, "minIlvl", 0, 400, 1, { fmt = function(v) return v == 0 and "off" or tostring(v) end })

        L:Header("Slots that need an enchant")
        L:Desc("Forever's enchant rules may differ from Classic. Off hand counts only for weapons and shields; ranged only for hunters' weapons.")
        -- character sheet order
        for _, slot in ipairs({ 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 16, 17, 18 }) do
            L:Toggle(SLOT_NAMES[slot], db.slots, slot, { dep = function() return db.enchants end, indent = 12 })
        end

        L:Header("When and how")
        L:Toggle("Check on ready check", db, "onReadyCheck")
        L:Toggle("Raid warning text", db, "raidWarning")
        L:Toggle("Sound", db, "sound")
        L:Select("Sound to play", db, "soundKit", FF.SoundChoices, { dep = function() return db.sound end,
            onChange = function() FF.PlaySound(db.soundKit) end })
        L:Toggle("Raid summary for lead/assist", db, "summary")
        L:Slider("Wait for reports", db, "summaryDelay", 3, 20, 1, { dep = function() return db.summary end,
            fmt = function(v) return v .. " s" end })
        L:Buttons({
            { "Raid request", function() FF.Run("gear") end, "Asks the raid for their gear and opens the report window - run once at the start of a raid" },
        })
        L:TitleToggle(db, function() return win end)
    end)

    -- Fresh report: ask everyone for their gear and open the window
    FF.Command("gear", function()
        wipe(reports)
        makeWin()
        win:Show()
        report() -- ours, also sent to the group
        if IsInGroup() then
            FF.Send("G", "Q", "GROUP")
        end
        M.RefreshWindow()
    end, "raid request: ask the raid for their gear and open the report window")
end)
