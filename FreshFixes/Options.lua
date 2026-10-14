local _, FF = ...

-- /ff main menu. Left: every module with an on/off switch.
-- Right: the selected module's settings, described by the module itself:
--   FF.Settings("Key", function(L) L:Header("..."); L:Toggle(...) ... end)
local C = FF.C
local builders, pages = {}, {}
local win, selected

function FF.Settings(key, builder)
    builders[key] = builder
end

local NAV_W, WIN_W, WIN_H = 210, 820, 560

local function entries()
    local list = {}
    for _, e in ipairs(FF.catalog) do
        list[#list + 1] = e
    end
    return list
end

local function needsReload()
    for _, e in ipairs(FF.catalog) do
        local m = FF.modules[e.key]
        if FF.IsEnabled(e.key) ~= (m and m.loaded or false) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function buildPage(e)
    local holder = CreateFrame("Frame", nil, win.right)
    holder:SetAllPoints()

    local title = FF.Text(holder, "title")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(e.title)
    local desc = FF.Text(holder, "small")
    desc:SetPoint("TOPLEFT", 14, -32)
    desc:SetPoint("RIGHT", -14, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    desc:SetText(e.desc or "")

    local scroll = FF.UI.Scroll(holder)
    scroll:SetPoint("TOPLEFT", 0, -54)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    local width = WIN_W - NAV_W - 24
    scroll.child:SetWidth(width)

    local L = FF.UI.Layout(scroll.child, width)
    local m = FF.modules[e.key]
    if not (m and m.loaded) then
        L:Header("Module is off")
        L:Desc(FF.IsEnabled(e.key)
            and "This module was just turned on. Reload the UI to load it and see its settings."
            or "Turn the switch on the left on, then reload the UI to use this module. While off it uses no memory.")
    else
        if builders[e.key] then
            builders[e.key](L)
        end
    end
    L:CloseCard()
    scroll.child:SetHeight(L.y + 12)
    holder.layout, holder.scroll = L, scroll
    holder:Hide()
    return holder
end

local function showPage(key)
    selected = key
    for _, e in ipairs(FF.catalog) do
        if e.key == key and win.title then
            win.title:SetText(("Fresh Fixes  %s/|r  %s%s|r"):format(FF.Hex(C.muted), FF.Hex(C.accent), e.title))
        end
    end
    if win.results then
        win.results:Hide()
    end
    for k, p in pairs(pages) do
        p:SetShown(k == key)
    end
    local page = pages[key]
    if not page then
        for _, e in ipairs(entries()) do
            if e.key == key then
                page = buildPage(e)
                pages[key] = page
            end
        end
    end
    if page then
        page:Show()
        page.layout:Refresh()
        page.scroll.Update()
    end
    for _, row in ipairs(win.navRows) do
        local on = row.key == key
        row.sel:SetShown(on)
        FF.SetBg(row, on and C.hover or C.panel)
    end
end

---------------------------------------------------------------------------
-- Search: every page's headers, labels and buttons. Pages are built the
-- first time you search (only then), so this costs nothing until used.
---------------------------------------------------------------------------
local function pageFor(e)
    if not pages[e.key] then
        pages[e.key] = buildPage(e)
    end
    return pages[e.key]
end

local function flash(page, y)
    local child = page.scroll.child
    if not page.flash then
        page.flash = child:CreateTexture(nil, "BACKGROUND", nil, 1)
        page.flash:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        page.flashTimer = CreateFrame("Frame", nil, page)
    end
    local t = page.flash
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    t:SetSize(child:GetWidth() - 8, 26)
    t:Show()
    local left = 1.6
    page.flashTimer:SetScript("OnUpdate", function(self, dt)
        left = left - dt
        t:SetAlpha(math.max(0, left / 1.6) * 0.3)
        if left <= 0 then
            t:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function goTo(key, y)
    showPage(key)
    local page = pages[key]
    if page and y then
        local sc = page.scroll
        local max = math.max(0, sc.child:GetHeight() - sc:GetHeight())
        sc:SetVerticalScroll(math.max(0, math.min(max, y - 40)))
        sc.Update()
        flash(page, y)
    end
end

local function plain(text)
    return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

local function search(query)
    local res = win.results
    query = plain(query or ""):lower()
    if #query < 2 then
        res:Hide()
        showPage(selected or FF.catalog[1].key)
        return
    end
    for _, p in pairs(pages) do
        p:Hide()
    end
    local found = {}
    for _, e in ipairs(entries()) do
        if (e.title .. " " .. (e.desc or "")):lower():find(query, 1, true) then
            found[#found + 1] = { key = e.key, title = e.title, text = e.desc or "", y = nil }
        end
        local page = pageFor(e)
        page:Hide()
        for _, l in ipairs(page.layout.labels) do
            local t = plain(l.text)
            if t:lower():find(query, 1, true) then
                found[#found + 1] = { key = e.key, title = e.title .. (l.header and not l.isHeader and ("  >  " .. l.header) or ""),
                    text = t, y = l.y }
            end
        end
    end
    res.rows = res.rows or {}
    local child = res.scroll.child
    for i, f in ipairs(found) do
        local r = res.rows[i]
        if not r then
            r = CreateFrame("Button", nil, child)
            r:SetHeight(36)
            FF.Skin(r, "row")
            r.text = FF.Text(r)
            r.text:SetPoint("TOPLEFT", 10, -5)
            r.text:SetPoint("RIGHT", -10, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            r.sub = FF.Text(r, "small")
            r.sub:SetPoint("BOTTOMLEFT", 10, 5)
            r.sub:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            r:SetScript("OnEnter", function(self)
                FF.SetBg(self, C.hover)
            end)
            r:SetScript("OnLeave", function(self)
                FF.SetBg(self, C.row)
            end)
            r:SetScript("OnClick", function(self)
                goTo(self.key, self.y)
            end)
            res.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, -(i - 1) * 40)
        r:SetPoint("RIGHT", -12, 0)
        r.key, r.y = f.key, f.y
        r.text:SetText(f.text ~= "" and f.text or f.title)
        r.sub:SetText(f.title)
        r:Show()
    end
    for i = #found + 1, #res.rows do
        res.rows[i]:Hide()
    end
    res.count:SetText(#found == 0 and "Nothing matches." or (#found == 1 and "1 result" or (#found .. " results")))
    child:SetHeight(#found * 40 + 8)
    res:Show()
    res.scroll:SetVerticalScroll(0)
    res.scroll.Update()
end

local function buildSearch(nav)
    local box = FF.UI.Input(nav, NAV_W - 17, 22)
    box:SetPoint("TOPLEFT", 8, -8)
    local e = box.edit
    local hint = FF.Text(box, "small")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    hint:SetText("Search settings...")
    e:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        hint:SetShown(t == "")
        search(t)
    end)
    e:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = win.results.rows and win.results.rows[1]
        if win.results:IsShown() and first and first:IsShown() then
            goTo(first.key, first.y)
        end
    end)
    win.search = e

    local res = CreateFrame("Frame", nil, win.right)
    res:SetAllPoints()
    local title = FF.Text(res, "title")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Search")
    res.count = FF.Text(res, "small")
    res.count:SetPoint("TOPLEFT", 14, -32)
    res.count:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    res.scroll = FF.UI.Scroll(res)
    res.scroll:SetPoint("TOPLEFT", 0, -54)
    res.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    res.scroll.child:SetWidth(WIN_W - NAV_W - 24)
    res:Hide()
    win.results = res
end

-- A module was switched on/off: its page changes, and a reload is needed.
local function moduleToggled(key)
    for _, row in ipairs(win.navRows) do
        row:Dim()
    end
    if pages[key] then
        pages[key]:Hide()
        pages[key] = nil
    end
    win.reload:SetShown(needsReload())
    if selected == key then
        showPage(key)
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function build()
    win = FF.UI.Window("Options", "Fresh Fixes  " .. FF.Hex(C.muted) .. FF.version .. "|r", WIN_W, WIN_H, { strata = "HIGH" })

    local nav = CreateFrame("Frame", nil, win)
    nav:SetPoint("TOPLEFT", 1, -(FF.UI.TITLE_H + 1))
    nav:SetPoint("BOTTOMLEFT", 1, 36)
    nav:SetWidth(NAV_W)
    FF.Skin(nav, "panel", false)
    local navLine = nav:CreateTexture(nil, "BORDER")
    navLine:SetPoint("TOPRIGHT")
    navLine:SetPoint("BOTTOMRIGHT")
    navLine:SetWidth(1)
    navLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)

    local navScroll = FF.UI.Scroll(nav)
    navScroll:SetPoint("TOPLEFT", 0, -38)
    navScroll:SetPoint("BOTTOMRIGHT")
    win.navRows = {}
    local y = 0
    for _, e in ipairs(entries()) do
        local row = CreateFrame("Button", nil, navScroll.child)
        row:SetHeight(28)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", -1, 0)
        FF.Skin(row, "panel", false)
        row.key = e.key
        row.sel = row:CreateTexture(nil, "ARTWORK")
        row.sel:SetPoint("TOPLEFT")
        row.sel:SetPoint("BOTTOMLEFT")
        row.sel:SetWidth(3)
        row.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        row.sel:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 10, 0)
        row.icon:SetTexture(e.icon or 134400)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = FF.Text(row)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetText(e.title)
        function row:Dim()
            local on = FF.IsEnabled(e.key)
            local c = on and C.text or C.muted
            self.text:SetTextColor(c[1], c[2], c[3])
            self.icon:SetDesaturated(not on)
            self.icon:SetAlpha(on and 1 or 0.5)
        end
        row:Dim()
        if not e.core then
            row.toggle = FF.UI.Toggle(row, function()
                return FF.IsEnabled(e.key)
            end, function(v)
                FF.core.modules[e.key] = v
                moduleToggled(e.key)
            end, "Turn " .. e.title .. " on or off (needs a UI reload)")
            row.toggle:SetPoint("RIGHT", -10, 0)
        end
        row:SetScript("OnClick", function()
            if win.search:GetText() ~= "" then
                win.search:SetText("") -- also returns to the selected page
            end
            showPage(e.key)
        end)
        row:SetScript("OnEnter", function(self)
            if selected ~= self.key then
                FF.SetBg(self, C.row)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if selected ~= self.key then
                FF.SetBg(self, C.panel)
            end
        end)
        win.navRows[#win.navRows + 1] = row
        y = y + 28
    end
    navScroll.child:SetHeight(y)

    win.right = CreateFrame("Frame", nil, win)
    win.right:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
    win.right:SetPoint("BOTTOMRIGHT", -1, 36)
    buildSearch(nav)

    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(34)
    FF.Skin(foot, "panel", false)
    local footLine = foot:CreateTexture(nil, "BORDER")
    footLine:SetPoint("TOPLEFT")
    footLine:SetPoint("TOPRIGHT")
    footLine:SetHeight(1)
    footLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local hint = FF.Text(foot, "small")
    hint:SetPoint("LEFT", 12, 0)
    hint:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    hint:SetText("Switch modules on/off on the left. /ff help lists commands.")
    local reset = FF.UI.Button(foot, "Reset positions", 120, 24, function()
        FF.core.pos = {}
        ReloadUI()
    end, "Moves every Fresh Fixes window and display back to its default spot (reloads the UI)")
    reset:SetPoint("RIGHT", -8, 0)
    win.reload = FF.UI.Button(foot, "Reload UI to apply", 150, 24, ReloadUI)
    win.reload:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    FF.SetBorder(win.reload, C.warn)
    win.reload:SetShown(needsReload())

    win:SetScript("OnShow", function()
        win.reload:SetShown(needsReload())
        if win.search:GetText() ~= "" then
            win.search:SetText("")
        end
        for _, row in ipairs(win.navRows) do
            if row.toggle then
                row.toggle:Refresh()
            end
        end
        if selected and pages[selected] then
            pages[selected].layout:Refresh()
        end
    end)
    showPage(FF.catalog[1].key)
end

-- Rebuild a module's page (for pages whose contents change, e.g. tracker lists).
function FF.RebuildSettings(key)
    if not win then
        return
    end
    local keep = pages[key] and pages[key].scroll:GetVerticalScroll() or 0
    if pages[key] then
        pages[key]:Hide()
        pages[key] = nil
    end
    if selected == key and win:IsShown() then
        showPage(key)
        -- stay where you were instead of jumping back to the top
        local sc = pages[key] and pages[key].scroll
        if sc then
            local max = math.max(0, sc.child:GetHeight() - sc:GetHeight())
            sc:SetVerticalScroll(math.min(keep, max))
            sc.Update()
        end
    end
end

function FF.ShowOptions(key)
    if not win then
        build()
    end
    if win:IsShown() and not key then
        win:Hide()
        return
    end
    win:Show()
    if key then
        showPage(key)
    end
end
