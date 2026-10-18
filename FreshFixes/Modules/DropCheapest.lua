local _, FF = ...
local M = FF.Module("DropCheapest")

-- Drop the cheapest thing: small window with free bag slots + N junk icons.
-- Left-click an icon to delete. Never automatic. Above-grey asks to confirm.
FF.Init("DropCheapest", function()
    local C, UI = FF.C, FF.UI
    local db = FF.DB("dropcheapest", {
        button = true,
        maxQuality = 0,
        skipBound = true,
        showCount = 4,
        hideBackground = false,
    })
    if type(rawget(db, "showCount")) ~= "number" then db.showCount = 4 end
    db.width = nil -- retired: width follows icon count

    local ICON = 28
    local GAP = 2
    local PAD = 4
    local HEAD = 18
    local PRICE_H = 14

    local CC = C_Container or {}
    local numSlots = CC.GetContainerNumSlots or GetContainerNumSlots
    local pickup = CC.PickupContainerItem or PickupContainerItem
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

    local function slotInfo(bag, slot)
        if CC.GetContainerItemInfo then
            local i = CC.GetContainerItemInfo(bag, slot)
            if i then
                return i.hyperlink, i.stackCount, i.quality, i.isLocked, i.isBound, i.itemID
            end
        elseif GetContainerItemInfo then
            local _, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
            return link, count, quality, locked, nil, itemID
        end
    end

    local function isQuest(bag, slot)
        if CC.GetContainerItemQuestInfo then
            local q = CC.GetContainerItemQuestInfo(bag, slot)
            return q and (q.isQuestItem or q.questID) and true
        elseif GetContainerItemQuestInfo then
            local isQ, id = GetContainerItemQuestInfo(bag, slot)
            return isQ or id
        end
    end

    local function vendorPrice(link, itemID)
        -- Prefer GetItemInfo sellPrice (11th return). Optional Forever helpers next.
        local _, _, _, _, _, _, _, _, _, _, price = getItemInfo(link or itemID)
        if type(price) == "number" and price > 0 then
            return price
        end
        if C_Item then
            for _, fn in ipairs({ C_Item.GetItemSellPriceByID, C_Item.GetItemSellPrice }) do
                if type(fn) == "function" then
                    local ok, p = pcall(fn, itemID or link)
                    if ok and type(p) == "number" and p > 0 then
                        return p
                    end
                end
            end
        end
        return type(price) == "number" and price or 0
    end

    local function resolveItem(link, itemID, quality)
        local name, _, q, _, _, _, _, _, _, texture, sell, classID = getItemInfo(link or itemID)
        if not name and itemID and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        if quality == nil or quality < 0 then quality = q end
        local price = type(sell) == "number" and sell or 0
        if price <= 0 then
            price = vendorPrice(link, itemID)
        end
        return name, quality, texture, price, classID
    end

    local function bagFree()
        local free, total = 0, 0
        for bag = 0, NUM_BAG_SLOTS or 4 do
            local n = numSlots(bag) or 0
            total = total + n
            for slot = 1, n do
                local link = slotInfo(bag, slot)
                if not link then free = free + 1 end
            end
        end
        return free, total
    end

    local function findAll(limit)
        limit = math.max(1, math.floor(tonumber(limit) or db.showCount or 4))
        local list = {}
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, numSlots(bag) or 0 do
                local link, count, quality, locked, bound, itemID = slotInfo(bag, slot)
                if link and not locked then
                    local name, q, texture, price, classID = resolveItem(link, itemID, quality)
                    if type(q) == "number" and q <= (db.maxQuality or 0) then
                        local ok = not isQuest(bag, slot) and classID ~= 12
                            and (price > 0 or q == 0)
                            and not (bound and db.skipBound and q > 0)
                        if ok then
                            list[#list + 1] = {
                                bag = bag, slot = slot, link = link, count = count or 1,
                                quality = q, value = price * (count or 1),
                                name = name, texture = texture,
                            }
                        end
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if a.quality ~= b.quality then return a.quality < b.quality end
            if a.value ~= b.value then return a.value < b.value end
            return (a.link or "") < (b.link or "")
        end)
        while #list > limit do list[#list] = nil end
        return list
    end

    local function find()
        return findAll(1)[1]
    end
    M.Find = find
    M.FindAll = findAll

    -- Plain text for the icon row (custom fonts can break |T coin textures mid-refresh).
    local function moneyPlain(v)
        v = tonumber(v) or 0
        if v <= 0 then
            return "-"
        end
        local g = math.floor(v / 10000)
        local s = math.floor((v % 10000) / 100)
        local c = v % 100
        if g > 0 then
            return ("%dg%02ds"):format(g, s)
        end
        if s > 0 then
            return ("%ds%02dc"):format(s, c)
        end
        return ("%dc"):format(c)
    end
    local function money(v)
        v = tonumber(v) or 0
        if v <= 0 then
            return "no value"
        end
        if type(GetCoinTextureString) == "function" then
            local ok, text = pcall(GetCoinTextureString, v)
            if ok and type(text) == "string" then
                return text
            end
        end
        return moneyPlain(v)
    end
    local function describe(it)
        return ("%s%s (%s)"):format(it.link, it.count > 1 and ("x" .. it.count) or "", money(it.value))
    end

    local function delete(it)
        if InCombatLockdown() or CursorHasItem() then return end
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
        if M.Refresh then M.Refresh() end
    end

    StaticPopupDialogs.FF_DROP_CHEAPEST = {
        text = "Delete %s?",
        button1 = YES, button2 = NO,
        OnAccept = function(_, it) delete(it) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    local function dropItem(it)
        if not it then
            FF.print("Nothing cheap enough to drop")
            return
        end
        if it.quality > 0 then
            local p = StaticPopup_Show("FF_DROP_CHEAPEST", describe(it))
            if p then p.data = it end
        else
            delete(it)
        end
    end

    function M.Drop()
        dropItem(find())
    end

    function M.Preview()
        local list = findAll(db.showCount or 4)
        if #list == 0 then
            FF.print("Nothing cheap enough to drop")
            return
        end
        for i, it in ipairs(list) do
            FF.print(("%d. Would drop %s"):format(i, describe(it)))
        end
    end

    FF.Command("drop", function(arg)
        arg = (arg or ""):lower()
        if arg == "show" or arg == "?" then
            M.Preview()
        elseif arg == "hide" then
            db.button = false
            if M.Apply then M.Apply() end
        elseif arg == "toggle" then
            db.button = not db.button
            if M.Apply then M.Apply() end
        else
            M.Drop()
        end
    end, "delete the cheapest junk item (/ff drop show to preview)")

    ---------------------------------------------------------------------------
    -- Window: row 1 = free/total slots · row 2 = exactly N junk icons
    ---------------------------------------------------------------------------
    local win, icons = nil, {}

    local function showCount()
        return math.max(1, math.min(12, math.floor(tonumber(db.showCount) or 4)))
    end

    local function frameW(n)
        return PAD * 2 + n * ICON + math.max(0, n - 1) * GAP
    end

    local function iconBtn(i)
        local b = icons[i]
        if b then
            if not b.price then
                b.price = FF.Text(win, "small")
                b.price:SetJustifyH("CENTER")
            end
            return b
        end
        b = CreateFrame("Button", nil, win)
        b:SetSize(ICON, ICON)
        FF.Skin(b, "row")
        b:RegisterForClicks("LeftButtonUp")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.price = FF.Text(win, "small")
        b.price:SetJustifyH("CENTER")
        b:SetScript("OnEnter", function(self)
            if not self.it then return end
            FF.SetBorder(self, C.accent)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.it.link)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Vendor: " .. money(self.it.value), 1, 0.82, 0)
            GameTooltip:AddLine("Click to delete", 0.2, 1, 0.2)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            FF.SetBorder(self, C.border)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            if self.it then dropItem(self.it) end
        end)
        icons[i] = b
        return b
    end

    local function build()
        if win then return end
        local n = showCount()
        win = UI.Display("DropCheapest", frameW(n), PAD + HEAD + GAP + ICON + PRICE_H + PAD, { "BOTTOMRIGHT", -320, 120 })
        win:EnableMouse(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() then self:StartMoving() end
        end)
        win:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            FF.SavePosition(self, "DropCheapest")
        end)
        -- Hide Display chrome edges for a flat look like the reference.
        for _, e in ipairs(win.ffEdges or {}) do e:Hide() end

        win.head = CreateFrame("Frame", nil, win)
        win.head:SetPoint("TOPLEFT", PAD, -PAD)
        win.head:SetPoint("TOPRIGHT", -PAD, -PAD)
        win.head:SetHeight(HEAD - 2)
        win.bag = win.head:CreateTexture(nil, "ARTWORK")
        win.bag:SetSize(14, 14)
        win.bag:SetPoint("LEFT", 0, 0)
        win.bag:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
        win.bag:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        win.slots = FF.Text(win.head, "small")
        win.slots:SetPoint("LEFT", win.bag, "RIGHT", 4, 0)
        win.slots:SetJustifyH("LEFT")
    end

    local function applyChrome()
        if not win then
            return
        end
        if win.ffBg then
            win.ffBg:SetShown(not db.hideBackground)
        end
    end

    function M.Refresh()
        if not win or not win:IsShown() then return end
        local n = showCount()
        local list = findAll(n)
        -- Exactly the configured count of icon slots (empty slots if fewer junk stacks).
        local shown = n
        local free, total = bagFree()
        win.slots:SetText(("%d / %d"):format(free, total))

        local w = math.max(frameW(shown), 72)
        win:SetWidth(w)
        win:SetHeight(PAD + HEAD + GAP + ICON + PRICE_H + PAD)

        for i = 1, 12 do
            local b = iconBtn(i)
            if i <= shown then
                local it = list[i]
                local x = PAD + (i - 1) * (ICON + GAP)
                local y = -(PAD + HEAD + GAP)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, y)
                b:Show()
                b.price:ClearAllPoints()
                b.price:SetPoint("TOP", win, "TOPLEFT", x + ICON / 2, y - ICON - 1)
                b.price:SetWidth(math.max(ICON + GAP * 2, 40))
                if it then
                    b.it = it
                    b.tex:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.tex:SetVertexColor(1, 1, 1, 1)
                    b.tex:Show()
                    b.price:SetText(moneyPlain(it.value))
                    b.price:Show()
                    b:SetAlpha(1)
                    b:EnableMouse(true)
                else
                    b.it = nil
                    b.tex:Hide()
                    b.price:SetText("")
                    b.price:Hide()
                    b:SetAlpha(0.45)
                    b:EnableMouse(false)
                end
            else
                b.it = nil
                if b.price then b.price:Hide() end
                b:Hide()
            end
        end
    end

    function M.Apply()
        if not db.button then
            if win then win:Hide() end
            return
        end
        build()
        applyChrome()
        win:Show()
        M.Refresh()
    end

    FF.On("FF_READY", M.Apply)
    FF.On("BAG_UPDATE", function()
        if win and win:IsShown() then M.Refresh() end
    end)
    FF.On("PLAYER_ENTERING_WORLD", function()
        if db.button then M.Apply() end
    end)
    if C_Item and C_Item.GetItemInfo then
        FF.On("GET_ITEM_INFO_RECEIVED", function()
            if win and win:IsShown() then M.Refresh() end
        end)
    end

    FF.Settings("DropCheapest", function(L)
        L:Header("Drop cheapest item")
        L:Desc("Shows free bag slots and the cheapest junk icons with vendor sell price. Left-click an icon to delete. Quest items are never touched; anything above grey always asks first. Shift-drag to move.")
        L:Toggle("Show the drop window", db, "button", { onChange = M.Apply })
        L:Toggle("Hide window background", db, "hideBackground", {
            onChange = function()
                if win then
                    applyChrome()
                else
                    M.Apply()
                end
            end,
            tip = "Off by default. On leaves only the bag count, icons, and prices.",
            dep = function() return db.button end,
        })
        L:Slider("Icons to show", db, "showCount", 1, 12, 1, {
            onChange = M.Apply,
            fmt = function(v) return tostring(v) end,
            tip = "Exactly this many icon slots. Frame width follows the count.",
            dep = function() return db.button end,
        })
        L:Select("Highest quality to consider", db, "maxQuality", {
            { 0, "Poor (grey) only" },
            { 1, "Common (white) too" },
        }, { onChange = function() if M.Refresh then M.Refresh() end end })
        L:Toggle("Skip soulbound items (above grey)", db, "skipBound", {
            onChange = function() if M.Refresh then M.Refresh() end end,
        })
    end)
end)
