local _, FF = ...

-- Flat UI kit: layered dark surfaces ("Ink", as in our Speedrun addon),
-- 1px borders, no Blizzard templates. Everything Fresh Fixes draws goes
-- through these helpers so the theme applies everywhere.

local UI = {}
FF.UI = UI

-- Theme --------------------------------------------------------------------
-- bg = page, panel = header / sidebar (darkest), card = raised section,
-- row = inputs and list rows, hover, border / cardBd = 1px lines
FF.C = {
    bg = { 0.078, 0.082, 0.094, 0.95 },
    panel = { 0.039, 0.043, 0.047, 1 },
    card = { 0.106, 0.110, 0.125, 1 },
    cardBd = { 0.149, 0.153, 0.173, 1 },
    row = { 0.125, 0.129, 0.149, 1 },
    hover = { 0.165, 0.169, 0.192, 1 },
    border = { 0.173, 0.176, 0.192, 1 },
    text = { 0.929, 0.929, 0.929, 1 },
    muted = { 0.608, 0.608, 0.608, 1 },
    accent = { 0.498, 0.698, 1.000, 1 },
    good = { 0.38, 0.82, 0.5, 1 },
    bad = { 0.94, 0.4, 0.4, 1 },
    warn = { 0.98, 0.76, 0.3, 1 },
}
local C = FF.C

function FF.Hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Fonts --------------------------------------------------------------------
-- EllesmereUI's global font when it's installed (Arial Narrow otherwise).
-- Titles and headers get the game's smooth outline (SLUG) where supported.
FF.FONT = "Fonts\\ARIALN.TTF"
FF.MEDIA = "Interface\\AddOns\\FreshFixes\\Media\\"
local SIZES = { small = 11, normal = 12, header = 12, title = 15, outline = 12 }
local SMOOTH = { header = true, title = true }
FF.Fonts = {}
for name in pairs(SIZES) do
    local f = CreateFont("FreshFixesFont_" .. name)
    f:SetTextColor(C.text[1], C.text[2], C.text[3])
    FF.Fonts[name] = f
end

function FF.ApplyFonts()
    local E = EllesmereUI
    local ok, path = pcall(function() return E and E.GetFontPath and E.GetFontPath(nil) end)
    if ok and type(path) == "string" and path ~= "" then
        FF.FONT = path
    end
    for name, f in pairs(FF.Fonts) do
        local size, outline = SIZES[name], name:find("^outline")
        local flags = outline and "OUTLINE" or (SMOOTH[name] and "OUTLINE, SLUG" or "")
        if not pcall(f.SetFont, f, FF.FONT, size, flags) then
            pcall(f.SetFont, f, FF.FONT, size, outline and "OUTLINE" or "")
        end
        f:SetShadowOffset((outline or SMOOTH[name]) and 0 or 1, (outline or SMOOTH[name]) and 0 or -1)
        f:SetShadowColor(0, 0, 0, 0.6)
    end
end
FF.ApplyFonts()

-- Surfaces -----------------------------------------------------------------
local function px(t, horizontal)
    if horizontal then
        PixelUtil.SetHeight(t, 1, 1)
    else
        PixelUtil.SetWidth(t, 1, 1)
    end
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
end

-- bgKey: key into FF.C ("bg", "panel", "row") or a colour table. border=false: none.
function FF.Skin(f, bgKey, border)
    bgKey = bgKey or "bg"
    if not f.ffBg then
        f.ffBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.ffBg:SetAllPoints()
    end
    local c = type(bgKey) == "table" and bgKey or C[bgKey]
    f.ffBg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    if border ~= false then
        if not f.ffEdges then
            local e = {}
            for i = 1, 4 do
                e[i] = f:CreateTexture(nil, "BORDER", nil, 7)
            end
            e[1]:SetPoint("TOPLEFT")
            e[1]:SetPoint("TOPRIGHT")
            e[2]:SetPoint("BOTTOMLEFT")
            e[2]:SetPoint("BOTTOMRIGHT")
            e[3]:SetPoint("TOPLEFT")
            e[3]:SetPoint("BOTTOMLEFT")
            e[4]:SetPoint("TOPRIGHT")
            e[4]:SetPoint("BOTTOMRIGHT")
            px(e[1], true)
            px(e[2], true)
            px(e[3], false)
            px(e[4], false)
            f.ffEdges = e
        end
        FF.SetBorder(f, type(border) == "table" and border or C.border)
    end
    return f
end

function FF.SetBorder(f, c)
    if f.ffEdges then
        for i = 1, 4 do
            f.ffEdges[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

function FF.SetBg(f, c)
    if f.ffBg then
        f.ffBg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
end

function FF.Text(parent, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(FF.Fonts[font or "normal"])
    return fs
end

-- Tooltip --------------------------------------------------------------------
-- Our own flat tooltip (1px border, no Blizzard backdrop).
--   FF.Tip(owner, text [, title]) / FF.HideTip()
local tip
function FF.Tip(owner, text, title)
    if not text or text == "" then
        return
    end
    if not tip then
        tip = CreateFrame("Frame", "FreshFixesTooltip", UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        FF.Skin(tip, { 0.07, 0.07, 0.07, 0.97 })
        tip.title = FF.Text(tip, "header")
        tip.title:SetPoint("TOPLEFT", 8, -7)
        tip.title:SetJustifyH("LEFT")
        tip.body = FF.Text(tip)
        tip.body:SetJustifyH("LEFT")
        tip.body:SetWordWrap(true)
    end
    tip.title:SetText(title or "")
    tip.title:SetShown(title ~= nil)
    tip.body:ClearAllPoints()
    if title then
        tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -4)
    else
        tip.body:SetPoint("TOPLEFT", 8, -7)
    end
    tip.body:SetWidth(0)
    tip.body:SetText(text)
    local w = math.min(280, math.max(tip.body:GetStringWidth(), title and tip.title:GetStringWidth() or 0))
    tip.body:SetWidth(w)
    tip:SetSize(w + 16, tip.body:GetStringHeight() + (title and tip.title:GetStringHeight() + 4 or 0) + 14)
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 2)
    tip:Show()
end

function FF.HideTip()
    if tip then
        tip:Hide()
    end
end

local function tipEnter(self)
    if self.ffTip then
        FF.Tip(self, self.ffTip)
    end
end
local function tipLeave()
    FF.HideTip()
end

-- Button ---------------------------------------------------------------------
function UI.Button(parent, text, w, h, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 22)
    FF.Skin(b, "row")
    b.text = FF.Text(b)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.ffTip = tip
    b:SetScript("OnEnter", function(self)
        FF.SetBg(self, C.hover)
        FF.SetBorder(self, C.accent)
        self.text:SetTextColor(1, 1, 1)
        tipEnter(self)
    end)
    b:SetScript("OnLeave", function(self)
        FF.SetBg(self, C.row)
        FF.SetBorder(self, C.border)
        self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        tipLeave()
    end)
    b:SetScript("OnClick", onClick)
    function b:SetLabel(t)
        self.text:SetText(t)
    end
    return b
end

-- Close "x" for windows
function UI.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.text = FF.Text(b, "title")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("×")
    b.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(C.bad[1], C.bad[2], C.bad[3])
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end)
    b:SetScript("OnClick", onClick or function()
        parent:GetParent():Hide()
    end)
    return b
end

-- Toggle switch ----------------------------------------------------------------
function UI.Toggle(parent, get, set, tip)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(30, 14)
    FF.Skin(t, "row")
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetSize(10, 10)
    t.ffTip = tip
    function t:Refresh()
        local on = get() and true or false
        self.knob:ClearAllPoints()
        if on then
            FF.SetBg(self, { C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1 })
            FF.SetBorder(self, C.accent)
            self.knob:SetPoint("RIGHT", -2, 0)
            self.knob:SetColorTexture(1, 1, 1, 1)
        else
            FF.SetBorder(self, C.border)
            FF.SetBg(self, C.row)
            self.knob:SetPoint("LEFT", 2, 0)
            self.knob:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
        end
    end
    t:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    t:SetScript("OnEnter", function(self)
        FF.SetBorder(self, C.accent)
        tipEnter(self)
    end)
    t:SetScript("OnLeave", function(self)
        self:Refresh() -- restores the on/off border
        tipLeave()
    end)
    t:Refresh()
    return t
end

-- Slider -----------------------------------------------------------------------
function UI.Slider(parent, w, min, max, step, get, set, fmt)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w, 8)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then
        s:SetObeyStepOnDrag(true)
    end
    FF.Skin(s, "row")
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 14)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    s:SetThumbTexture(thumb)
    s.value = FF.Text(s, "small")
    s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    -- Wheel scrolls the settings page. Drag the slider to change it.
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local p = self:GetParent()
        while p and not p.GetVerticalScroll do
            p = p:GetParent()
        end
        local wheel = p and p:GetScript("OnMouseWheel")
        if wheel then
            wheel(p, delta)
        end
    end)
    local function show(v)
        if fmt then
            s.value:SetText(fmt(v))
        else
            s.value:SetText((step < 1) and ("%.2f"):format(v) or ("%d"):format(v))
        end
    end
    local quiet
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not quiet then
            set(v)
        end
    end)
    function s:Refresh()
        quiet = true
        local v = tonumber(get()) or min
        self:SetValue(v)
        show(v)
        quiet = false
        thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end
    s:Refresh()
    return s
end

-- Dropdown ---------------------------------------------------------------------
local menu, catcher
local function closeMenu()
    if menu then
        menu:Hide()
        catcher:Hide()
    end
end

local function openMenu(owner, options, onPick)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetScript("OnClick", closeMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
        FF.Skin(menu, "panel")
        menu.items = {}
    end
    local w = owner:GetWidth()
    for i, opt in ipairs(options) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(20)
            it.text = FF.Text(it)
            it.text:SetPoint("LEFT", 6, 0)
            it.text:SetPoint("RIGHT", -6, 0)
            it.text:SetJustifyH("LEFT")
            it.hl = it:CreateTexture(nil, "HIGHLIGHT")
            it.hl:SetAllPoints()
            it.hl:SetColorTexture(1, 1, 1, 0.08)
            menu.items[i] = it
        end
        it:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
        it:SetPoint("RIGHT", -1, 0)
        it.text:SetText(opt[2])
        it:SetScript("OnClick", function()
            closeMenu()
            onPick(opt[1])
        end)
        it:Show()
    end
    for i = #options + 1, #menu.items do
        menu.items[i]:Hide()
    end
    menu:SetSize(math.max(w, 120), #options * 20 + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    catcher:Show()
    menu:Show()
end

-- options = { {value, label}, ... }
function UI.Dropdown(parent, w, options, get, set)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(w, 20)
    FF.Skin(d, "row")
    d.text = FF.Text(d)
    d.text:SetPoint("LEFT", 6, 0)
    d.text:SetPoint("RIGHT", -16, 0)
    d.text:SetJustifyH("LEFT")
    d.arrow = FF.Text(d, "small")
    d.arrow:SetPoint("RIGHT", -5, 0)
    d.arrow:SetText("v")
    d.arrow:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    function d:Refresh()
        local v = get()
        local label = tostring(v)
        local opts = type(options) == "function" and options() or options
        for _, o in ipairs(opts) do
            if o[1] == v then
                label = o[2]
            end
        end
        self.text:SetText(label)
    end
    d:SetScript("OnClick", function(self)
        if menu and menu:IsShown() then
            closeMenu()
            return
        end
        openMenu(self, type(options) == "function" and options() or options, function(v)
            set(v)
            self:Refresh()
        end)
    end)
    d:SetScript("OnEnter", function(self)
        FF.SetBorder(self, C.accent)
        self.arrow:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    d:SetScript("OnLeave", function(self)
        FF.SetBorder(self, C.border)
        self.arrow:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end)
    d:Refresh()
    return d
end

-- Edit box -------------------------------------------------------------------
function UI.Input(parent, w, h, get, set, multiline)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, h or 20)
    FF.Skin(holder, "row")
    local e = CreateFrame("EditBox", nil, holder)
    e:SetFontObject(FF.Fonts.normal)
    e:SetAutoFocus(false)
    e:SetTextInsets(5, 5, 2, 2)
    if multiline then
        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", 1, -3)
        scroll:SetPoint("BOTTOMRIGHT", -1, 3)
        e:SetMultiLine(true)
        e:SetWidth(w - 4)
        scroll:SetScrollChild(e)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, e:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 30)))
        end)
        holder:SetScript("OnMouseDown", function()
            e:SetFocus()
        end)
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:SetScript("OnEditFocusLost", function(self)
            if set then
                set(self:GetText())
            end
        end)
    else
        e:SetAllPoints()
        e:SetScript("OnEnterPressed", e.ClearFocus)
        -- save on any focus loss (Enter, clicking elsewhere), not only Enter
        e:SetScript("OnEditFocusLost", function(self)
            local v = self:GetText()
            if set and v ~= tostring(get and get() or "") then
                set(v)
            end
        end)
        e:SetScript("OnEscapePressed", function(self)
            self:SetText(get and tostring(get() or "") or "")
            self:ClearFocus()
        end)
    end
    e:SetScript("OnEditFocusGained", function()
        FF.SetBorder(holder, C.accent)
    end)
    local lost = e:GetScript("OnEditFocusLost")
    e:SetScript("OnEditFocusLost", function(self)
        FF.SetBorder(holder, C.border)
        if lost then
            lost(self)
        end
    end)
    holder.edit = e
    function holder:Refresh()
        if get and not e:HasFocus() then
            e:SetText(tostring(get() or ""))
            e:SetCursorPosition(0)
        end
    end
    holder:Refresh()
    return holder
end

-- Colour swatch ----------------------------------------------------------------
function UI.Color(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(36, 16)
    FF.Skin(b, "row")
    b.swatch = b:CreateTexture(nil, "ARTWORK")
    b.swatch:SetPoint("TOPLEFT", 2, -2)
    b.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    function b:Refresh()
        local c = get()
        self.swatch:SetColorTexture(c.r, c.g, c.b, 1)
    end
    b:SetScript("OnClick", function(self)
        local c = get()
        local old = { r = c.r, g = c.g, b = c.b }
        local function apply()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            set({ r = r, g = g, b = bl })
            self:Refresh()
        end
        local function cancel()
            set(old)
            self:Refresh()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b, hasOpacity = false,
                swatchFunc = apply, cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    b:SetScript("OnEnter", function(self)
        FF.SetBorder(self, C.accent)
    end)
    b:SetScript("OnLeave", function(self)
        FF.SetBorder(self, C.border)
    end)
    b:Refresh()
    return b
end

-- Scroll area (mouse wheel + thin indicator) -------------------------------------
function UI.Scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, s)
    child:SetSize(1, 1)
    s:SetScrollChild(child)
    s.child = child
    local bar = s:CreateTexture(nil, "OVERLAY")
    bar:SetWidth(3)
    bar:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.6)
    s.bar = bar
    local function update()
        local max = math.max(0, child:GetHeight() - s:GetHeight())
        if max <= 0 then
            bar:Hide()
            s:SetVerticalScroll(0)
            return
        end
        local h = s:GetHeight()
        local size = math.max(20, h * h / child:GetHeight())
        bar:SetHeight(size)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", s, "TOPRIGHT", -1, -(s:GetVerticalScroll() / max) * (h - size))
        bar:Show()
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
        update()
    end)
    s:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        update()
    end)
    s.Update = update
    return s
end

-- Window -------------------------------------------------------------------------
-- Every title bar: 18px, small font centred vertically, 1px line below it.
UI.TITLE_H = 18

function UI.Window(id, title, w, h, opts)
    opts = opts or {}
    local name = "FreshFixes" .. id .. "Window"
    local f = CreateFrame("Frame", name, UIParent)
    f.id = id
    f:SetSize(w, h)
    f:SetFrameStrata(opts.strata or "MEDIUM")
    f:SetToplevel(true)
    -- only the top-left of the title bar has to stay on screen
    f:SetClampedToScreen(true)
    local function clampCorner()
        local cw, ch = f:GetSize()
        cw, ch = tonumber(cw) or w, tonumber(ch) or h
        f:SetClampRectInsets(0, -math.max(0, cw - 60), 0, math.max(0, ch - UI.TITLE_H))
    end
    clampCorner()
    f:HookScript("OnSizeChanged", clampCorner)
    f:SetMovable(true)
    f:EnableMouse(true)
    FF.Skin(f, "bg")
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(UI.TITLE_H)
    FF.Skin(bar, "panel", false)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if not f.locked then
            f:StartMoving()
        end
    end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        FF.SavePosition(f, id)
    end)
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    px(line, true)
    f.titleBar = bar
    f.title = FF.Text(bar, "small")
    -- pinned left and right so the text never shifts when it changes
    f.title:SetPoint("LEFT", 5, 0)
    f.title:SetPoint("RIGHT", -(UI.TITLE_H + 2), 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetText(title)
    f.close = UI.CloseButton(bar, function()
        f:Hide()
    end)
    f.close:SetSize(UI.TITLE_H, UI.TITLE_H)
    f.close.text:SetFontObject(FF.Fonts.normal)
    f.close:SetPoint("RIGHT", 0, 0)
    if not opts.keepOpen then
        tinsert(UISpecialFrames, name)
    end
    FF.RestorePosition(f, id, "CENTER")
    UI.windows = UI.windows or {}
    UI.windows[#UI.windows + 1] = f
    f:Hide()
    return f
end

-- A small on-screen display frame (bars, frames):
-- flat background that can be faded, drag when unlocked.
function UI.Display(id, w, h, point)
    local f = CreateFrame("Frame", "FreshFixes" .. id .. "Display", UIParent)
    f.id = id
    f:SetSize(w, h)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    FF.Skin(f, "bg")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FF.SavePosition(self, id)
    end)
    FF.RestorePosition(f, id, unpack(point or { "CENTER" }))
    function f:SetUnlocked(on)
        self:EnableMouse(on)
        FF.SetBorder(self, on and C.accent or C.border)
    end
    f:SetUnlocked(false)
    return f
end

---------------------------------------------------------------------------
-- Settings layout: modules describe settings, the options window draws them.
---------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

local ROW = 26
local LABEL_W = 230

function UI.Layout(parent, width)
    return setmetatable({ parent = parent, width = width, y = 8, refreshers = {}, widgets = {}, toggles = {}, labels = {} }, Layout)
end

function Layout:Take(h)
    local y = self.y
    self.y = self.y + h
    return -y
end

-- dep: function returning enabled (optionally false, "reason"); why: reason text
function Layout:Track(w, dep, why)
    self.widgets[#self.widgets + 1] = { w = w, dep = dep, why = why, after = #self.toggles }
    if w.Refresh then
        self.refreshers[#self.refreshers + 1] = w
    end
    return w
end

-- Why a setting is greyed out: an explicit reason, or the nearest switch
-- above it that is available but turned off.
local function plain(text)
    return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

function Layout:Reason(it, why)
    if it.why or why then
        return it.why or why
    end
    for i = it.after, 1, -1 do
        local t = self.toggles[i]
        if (not t.dep or t.dep()) and not t.get() then
            return ('Turn on "%s" first.'):format(plain(t.text))
        end
    end
    return "Not available with the current settings."
end

local function blockerEnter(self)
    FF.Tip(self, self.why, "Unavailable")
end

function Layout:Refresh()
    for _, w in ipairs(self.refreshers) do
        w:Refresh()
    end
    for _, it in ipairs(self.widgets) do
        if it.dep then
            local ok, why = it.dep()
            local on = ok and true or false
            it.w:SetAlpha(on and 1 or 0.35)
            if it.w.EnableMouse then
                it.w:EnableMouse(on)
            end
            if not on and not it.blocker then
                local b = CreateFrame("Frame", nil, self.parent)
                b:SetAllPoints(it.w)
                b:SetFrameLevel((it.w.GetFrameLevel and it.w:GetFrameLevel() or self.parent:GetFrameLevel()) + 5)
                b:EnableMouse(true)
                b:SetScript("OnEnter", blockerEnter)
                b:SetScript("OnLeave", tipLeave)
                it.blocker = b
            end
            if it.blocker then
                it.blocker.why = not on and self:Reason(it, type(why) == "string" and why or nil) or nil
                it.blocker:SetShown(not on)
            end
        end
    end
end

local function label(self, text, y, tip, indent)
    self.labels[#self.labels + 1] = { text = text, y = -y, header = self.header }
    local fs = FF.Text(self.parent)
    fs:SetPoint("TOPLEFT", 12 + (indent or 0), y - 5)
    fs:SetWidth(LABEL_W - (indent or 0))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    if tip then
        local hit = CreateFrame("Frame", nil, self.parent)
        hit:SetAllPoints(fs)
        hit.ffTip = tip
        hit:SetScript("OnEnter", tipEnter)
        hit:SetScript("OnLeave", tipLeave)
    end
    return fs
end

local function changed(o)
    if o and o.onChange then
        o.onChange()
    end
end

-- A raised card behind a section: from its header to the next one
function Layout:CloseCard()
    local top = self.cardTop
    if not top then
        return
    end
    self.cardTop = nil
    local h, w, p = self.y - top + 4, self.width - 12, self.parent
    -- drawn as background textures on the page, so text and widgets sit on top
    local fill = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetPoint("TOPLEFT", 6, -top)
    fill:SetSize(w, h)
    fill:SetColorTexture(C.card[1], C.card[2], C.card[3], C.card[4])
    for i, side in ipairs({ { 0, 0, w, 1 }, { 0, -(h - 1), w, 1 }, { 0, 0, 1, h }, { w - 1, 0, 1, h } }) do
        local t = p:CreateTexture(nil, "BACKGROUND", nil, -7)
        t:SetPoint("TOPLEFT", 6 + side[1], -top + side[2])
        t:SetSize(side[3], side[4])
        t:SetColorTexture(C.cardBd[1], C.cardBd[2], C.cardBd[3], 1)
    end
    self.y = self.y + 12
end

function Layout:Header(text)
    self:CloseCard()
    self.cardTop = self.y
    local y = self:Take(32)
    self.header = text
    self.labels[#self.labels + 1] = { text = text, y = -y, isHeader = true }
    local fs = FF.Text(self.parent, "small")
    fs:SetPoint("TOPLEFT", 12, y - 14)
    fs:SetText(text:upper())
    fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    return fs
end

function Layout:Desc(text)
    local fs = FF.Text(self.parent, "small")
    fs:SetPoint("TOPLEFT", 12, -self.y - 2)
    fs:SetWidth(self.width - 24)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    fs:SetText(text)
    self.y = self.y + fs:GetStringHeight() + 8
    return fs
end

-- o = { tip, dep = function() return enabled end, onChange, indent }
function Layout:Toggle(text, db, key, o)
    o = o or {}
    local y = self:Take(ROW)
    local fs = label(self, text, y, o.tip, o.indent)
    local t = UI.Toggle(self.parent, function()
        if o.invert then
            return not db[key]
        end
        return db[key]
    end, function(v)
        if o.invert then
            v = not v or nil
        end
        db[key] = v
        changed(o)
        self:Refresh()
    end, o.tip)
    t:SetPoint("TOPLEFT", LABEL_W + 20, y - 4)
    self:Track(fs, o.dep, o.why)
    self:Track(t, o.dep, o.why)
    self.toggles[#self.toggles + 1] = { text = text, dep = o.dep, get = function()
        if o.invert then
            return not db[key]
        end
        return db[key]
    end }
    return t
end

function Layout:Slider(text, db, key, min, max, step, o)
    o = o or {}
    local y = self:Take(ROW)
    local fs = label(self, text, y, o.tip, o.indent)
    local s = UI.Slider(self.parent, o.width or 180, min, max, step, function()
        return db[key]
    end, function(v)
        db[key] = v
        changed(o)
    end, o.fmt)
    s:SetPoint("TOPLEFT", LABEL_W + 20, y - 6)
    self:Track(fs, o.dep, o.why)
    return self:Track(s, o.dep, o.why)
end

function Layout:Select(text, db, key, options, o)
    o = o or {}
    local y = self:Take(ROW)
    local fs = label(self, text, y, o.tip, o.indent)
    local d = UI.Dropdown(self.parent, o.width or 180, options, function()
        return db[key]
    end, function(v)
        db[key] = v
        changed(o)
        self:Refresh()
    end)
    d:SetPoint("TOPLEFT", LABEL_W + 20, y - 3)
    self:Track(fs, o.dep, o.why)
    return self:Track(d, o.dep, o.why)
end

function Layout:Input(text, db, key, o)
    o = o or {}
    local h = o.lines and (o.lines * 15 + 8) or 20
    local y = self:Take(math.max(ROW, h + 6))
    local fs = label(self, text, y, o.tip, o.indent)
    local box = UI.Input(self.parent, o.width or 220, h, function()
        if o.get then
            return o.get()
        end
        return db[key]
    end, function(v)
        if o.set then
            o.set(v)
        else
            db[key] = o.number and tonumber(v) or v
        end
        changed(o)
        self:Refresh()
    end, o.lines ~= nil)
    box:SetPoint("TOPLEFT", LABEL_W + 20, y - 3)
    self:Track(fs, o.dep, o.why)
    return self:Track(box, o.dep, o.why)
end

function Layout:Color(text, db, key, default, o)
    o = o or {}
    local y = self:Take(ROW)
    local fs = label(self, text, y, o.tip, o.indent)
    local c = UI.Color(self.parent, function()
        local v = db[key] or default
        return { r = v.r, g = v.g, b = v.b }
    end, function(v)
        db[key] = v
        changed(o)
    end)
    c:SetPoint("TOPLEFT", LABEL_W + 20, y - 5)
    self:Track(fs, o.dep, o.why)
    return self:Track(c, o.dep, o.why)
end

-- buttons = { { "Text", fn, tip }, ... }
function Layout:Buttons(buttons, o)
    o = o or {}
    local y = self:Take(30)
    local x = 12
    for _, b in ipairs(buttons) do
        local w = math.max(80, #b[1] * 7 + 20)
        local btn = UI.Button(self.parent, b[1], w, 22, b[2], b[3])
        btn:SetPoint("TOPLEFT", x, y - 4)
        x = x + w + 6
        self.labels[#self.labels + 1] = { text = b[1], y = -y, header = self.header }
        self:Track(btn, o.dep, o.why)
    end
end

-- Free-form block: fn(frame, width) returns its height
function Layout:Custom(height, fn)
    local y = self:Take(height)
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetPoint("TOPLEFT", 0, y)
    f:SetSize(self.width, height)
    fn(f, self.width)
    return f
end

-- "Show the title bar" for a list window. getWin returns the window (or nil).
function Layout:TitleToggle(db, getWin, o)
    o = o or {}
    return self:Toggle("Show the title bar", db, "showTitle", { dep = o.dep, indent = o.indent,
        tip = "Without it, drag the window by its rows", onChange = function()
            local w = getWin()
            if w then
                w:SetTitleShown(db.showTitle)
            end
        end })
end

function Layout:Space(h)
    self.y = self.y + (h or 8)
end
