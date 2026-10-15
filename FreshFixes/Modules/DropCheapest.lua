local _, FF = ...
local M = FF.Module("DropCheapest")

-- Drop the cheapest thing: finds the lowest-value stack in your bags (sell
-- price x count, grey items first) and deletes it when YOU click the button
-- or run /ff drop. Never automatic: deleting needs a hardware event.
-- Anything above grey asks for confirmation first.
FF.Init("DropCheapest", function()
    local db = FF.DB("dropcheapest", {
        button = true, maxQuality = 0, skipBound = true,
    })

    -- C_Container on current clients, old globals as a fallback
    local CC = C_Container or {}
    local numSlots = CC.GetContainerNumSlots or GetContainerNumSlots
    local pickup = CC.PickupContainerItem or PickupContainerItem
    local function slotInfo(bag, slot)
        if CC.GetContainerItemInfo then
            local i = CC.GetContainerItemInfo(bag, slot)
            if i then
                return i.hyperlink, i.stackCount, i.quality, i.isLocked, i.isBound
            end
        elseif GetContainerItemInfo then
            local _, count, locked, quality, _, _, link, _, _, _, bound = GetContainerItemInfo(bag, slot)
            return link, count, quality, locked, bound
        end
    end
    local function isQuest(bag, slot)
        local q
        if CC.GetContainerItemQuestInfo then
            q = CC.GetContainerItemQuestInfo(bag, slot)
            return q and (q.isQuestItem or q.questID) and true
        elseif GetContainerItemQuestInfo then
            local isQ, id = GetContainerItemQuestInfo(bag, slot)
            return isQ or id
        end
    end

    -- Cheapest candidate: lowest quality bucket first (grey before white),
    -- then lowest stack value. Returns a table or nil.
    local function find()
        local best
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, numSlots(bag) or 0 do
                local link, count, quality, locked, bound = slotInfo(bag, slot)
                if link and not locked and quality and quality <= db.maxQuality then
                    local _, _, _, _, _, _, _, _, _, _, price, classID = GetItemInfo(link)
                    price = price or 0
                    local ok = not isQuest(bag, slot) and classID ~= 12 -- 12 = quest
                        and (price > 0 or quality == 0)
                        and not (bound and db.skipBound and quality > 0)
                    if ok then
                        local value = price * (count or 1)
                        if not best or quality < best.quality
                            or (quality == best.quality and value < best.value) then
                            best = { bag = bag, slot = slot, link = link, count = count or 1,
                                quality = quality, value = value }
                        end
                    end
                end
            end
        end
        return best
    end
    M.Find = find

    local function money(v)
        return v > 0 and GetCoinTextureString(v) or "no value"
    end
    local function describe(it)
        return ("%s%s (%s)"):format(it.link, it.count > 1 and ("x" .. it.count) or "", money(it.value))
    end

    local function delete(it)
        if InCombatLockdown() or CursorHasItem() then
            return
        end
        local link = slotInfo(it.bag, it.slot)
        if link ~= it.link then
            FF.print("Bags changed, try again")
            return
        end
        ClearCursor()
        pickup(it.bag, it.slot)
        if CursorHasItem() then
            DeleteCursorItem()
            FF.print("Deleted " .. describe(it))
        end
    end

    StaticPopupDialogs.FF_DROP_CHEAPEST = {
        text = "Delete %s?",
        button1 = YES, button2 = NO,
        OnAccept = function(_, it)
            delete(it) -- the click on "Yes" is the hardware event
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    -- Must be called from a click / slash command / keybind
    function M.Drop()
        local it = find()
        if not it then
            FF.print("Nothing cheap enough to drop")
            return
        end
        if it.quality > 0 then
            local p = StaticPopup_Show("FF_DROP_CHEAPEST", describe(it))
            if p then
                p.data = it
            end
        else
            delete(it)
        end
    end

    function M.Preview()
        local it = find()
        FF.print(it and ("Would drop " .. describe(it)) or "Nothing cheap enough to drop")
    end

    FF.Command("drop", function(arg)
        if arg == "show" or arg == "?" then
            M.Preview()
        else
            M.Drop()
        end
    end, "delete the cheapest junk item (/ff drop show to preview)")

    ---------------------------------------------------------------------------
    -- Small movable button; tooltip shows what a click would delete
    ---------------------------------------------------------------------------
    local btn
    local function applyButton()
        if not db.button then
            if btn then
                btn:Hide()
            end
            return
        end
        if not btn then
            btn = CreateFrame("Button", "FreshFixesDropCheapestButton", UIParent)
            btn:SetSize(32, 32)
            btn:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_10")
            btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            btn:SetMovable(true)
            btn:SetClampedToScreen(true)
            btn:RegisterForDrag("LeftButton")
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnDragStart", function(self)
                if IsShiftKeyDown() then
                    self:StartMoving()
                end
            end)
            btn:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local point, _, rel, x, y = self:GetPoint()
                db.pos = { point, rel, x, y }
            end)
            btn:SetScript("OnClick", function()
                M.Drop()
                GameTooltip:Hide()
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine("Drop cheapest item")
                local it = find()
                if it then
                    GameTooltip:AddLine(describe(it), 1, 1, 1)
                else
                    GameTooltip:AddLine("Nothing cheap enough to drop", 0.6, 0.6, 0.6)
                end
                GameTooltip:AddLine("Click to delete, Shift-drag to move", 0.2, 1, 0.2)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        btn:ClearAllPoints()
        local p = db.pos
        if p then
            btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            btn:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -320, 120)
        end
        btn:Show()
    end
    FF.On("FF_READY", applyButton)

    FF.Settings("DropCheapest", function(L)
        L:Header("Drop cheapest item")
        L:Desc("Deletes the lowest-value stack in your bags (grey items first). Only when you click the button or run /ff drop; /ff drop show previews it. Quest items are never touched; anything above grey always asks first.")
        L:Toggle("Show the drop button (Shift-drag to move)", db, "button", { onChange = applyButton })
        L:Select("Highest quality to consider", db, "maxQuality", { { 0, "Poor (grey) only" }, { 1, "Common (white) too" } })
        L:Toggle("Skip soulbound items (above grey)", db, "skipBound")
    end)
end)
