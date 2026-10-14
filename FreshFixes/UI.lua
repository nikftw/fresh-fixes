local _, FF = ...

-- One small list-window widget shared by every module (Gear, Cooldowns,
-- Summons, Consumes, Resurrections). Rows are created on demand and reused.

-- Display name: the guild nickname when the Nicknames module has one
function FF.NickOr(key, name)
    local nicks = FF.modules.Nicknames
    local nick = key and nicks and nicks.loaded and nicks.Get and nicks.Get(key)
    return nick or name
end

function FF.ClassColor(class, text)
    local c = class and RAID_CLASS_COLORS[class]
    if not c then
        return text
    end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text)
end

function FF.Clock(sec)
    if sec >= 3600 then
        return ("%dh%02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
    end
    return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

function FF.SavePosition(f, id)
    local p, _, rp, x, y = f:GetPoint()
    FF.core.pos = FF.core.pos or {}
    FF.core.pos[id] = { p, rp, x, y }
end

function FF.RestorePosition(f, id, ...)
    local pos = FF.core.pos and FF.core.pos[id]
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint(...)
    end
end

local function rowEnter(row)
    local d = row.data
    if d and d.tooltip then
        FF.Tip(row, d.tooltip)
    end
end

local function rowLeave()
    FF.HideTip()
end

local function rowClick(row, button)
    local d = row.data
    if d and d.onClick then
        d.onClick(d, button)
    end
end


-- Game icons drawn small. Never pass a filter mode above LINEAR here:
-- TRILINEAR hard-crashes this client (ASSERT m_filter <= GxTex_Linear).
-- Sizes are snapped to whole screen pixels instead.
local function setIcon(tex, file)
    tex:SetTexture(file)
end
FF.SetIcon = setIcon

-- A height that is a whole number of screen pixels at this frame's scale.
-- 18 UI units at e.g. 0.89 scale is 16.02px: rows then alternate 16/17px and
-- their text centres round differently (5px vs 6px from the bottom).
function FF.PixelHeight(frame, h)
    local px = PixelUtil.GetNearestPixelSize(h, frame:GetEffectiveScale(), h)
    return type(px) == "number" and px > 0 and px or h
end

local function makeRow(f, i)
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(f.rowH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- with the title bar hidden, drag the window by its rows
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function()
        if not f.locked and (f.dragRows or not f.titleBar:IsShown()) then
            f:StartMoving()
        end
    end)
    r:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        FF.SavePosition(f, f.id)
    end)

    -- each row has its own background, so a borderless window shows nothing
    -- around or between rows (no 1px gaps from rounding)
    r.bg = r:CreateTexture(nil, "BACKGROUND", nil, -8)
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(FF.C.bg[1], FF.C.bg[2], FF.C.bg[3], FF.C.bg[4])

    r.fill = r:CreateTexture(nil, "BACKGROUND")
    r.fill:SetPoint("TOPLEFT")
    r.fill:SetPoint("BOTTOMLEFT")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(f.rowH - 4, f.rowH - 4)
    r.icon:SetPoint("LEFT", 2, 0)

    r.right = FF.Text(r, "small")
    r.right:SetPoint("RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")

    r.badges = {} -- small icons with overlay text, right-aligned before .right

    r.text = FF.Text(r, "small")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.text:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    r:SetScript("OnEnter", rowEnter)
    r:SetScript("OnLeave", rowLeave)
    r:SetScript("OnClick", rowClick)
    return r
end

-- Badges: full row height, no gaps, stacked right against the .right text
local function setBadges(self, r, list)
    list = list or {}
    local size = FF.PixelHeight(self, self.rowH)
    local anchor, n = r.right, #list
    for i = n, 1, -1 do
        local b = r.badges[i]
        if not b then
            b = CreateFrame("Frame", nil, r)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFont(FF.FONT, 10, "OUTLINE")
            b.textSize = 10
            b.text:SetPoint("BOTTOMRIGHT", 1, -1)
            r.badges[i] = b
        end
        local d = list[i]
        -- Pinned to the row's own top and bottom (not centred on the text,
        -- whose rounding pushed icons 1px into the next row)
        b:ClearAllPoints()
        if anchor == r.right then
            local rw = (self.rightWidth and self.rightWidth > 0) and self.rightWidth or r.right:GetStringWidth()
            local x = -(4 + rw + 6)
            b:SetPoint("TOPRIGHT", r, "TOPRIGHT", x, 0)
            b:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", x, 0)
        else
            b:SetPoint("TOPRIGHT", anchor, "TOPLEFT")
            b:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT")
        end
        b:SetWidth(size)
        setIcon(b.tex, d.icon)
        b.tex:SetDesaturated(d.dim and true or false)
        b.tex:SetAlpha(d.dim and 0.5 or 1)
        local fs = math.max(9, math.floor(size * 0.55))
        if b.textSize ~= fs then
            b.text:SetFont(FF.FONT, fs, "OUTLINE")
            b.textSize = fs
        end
        b.text:SetText(d.text or "")
        b:Show()
        anchor = b
    end
    for i = n + 1, #r.badges do
        r.badges[i]:Hide()
    end
    r.text:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
end

-- rows: { text, right, icon, coords, bar (0-1), barColor {r,g,b}, header, tooltip, onClick(d, button),
--         badges = { { icon, text, dim }, ... } }
local function setRows(self, rows)
    self.lastRows = rows
    local n = math.min(#rows, self.maxRows)
    local inset = self.noBorder and 0 or 1
    local rowH = FF.PixelHeight(self, self.rowH)
    self.titleBar:SetHeight(rowH)
    local titled = self.titleBar:IsShown()
    local top = titled and (self.titleBar:GetHeight() + inset) or inset
    for i = 1, n do
        local r = self.rows[i] or makeRow(self, i)
        self.rows[i] = r
        r:ClearAllPoints()
        r:SetHeight(rowH)
        if self.perColumn then
            -- grid: fill each column top to bottom, then the next column
            local col, line = math.floor((i - 1) / self.perColumn), (i - 1) % self.perColumn
            r:SetWidth(self.colWidth)
            if line > 0 then
                r:SetPoint("TOPLEFT", self.rows[i - 1], "BOTTOMLEFT")
            elseif titled then
                r:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT", col * self.colWidth, 0)
            else
                r:SetPoint("TOPLEFT", inset + col * self.colWidth, -inset)
            end
        elseif i > 1 then
            r:SetPoint("TOPLEFT", self.rows[i - 1], "BOTTOMLEFT")
            r:SetPoint("TOPRIGHT", self.rows[i - 1], "BOTTOMRIGHT")
        elseif titled then
            r:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT")
            r:SetPoint("TOPRIGHT", self.titleBar, "BOTTOMRIGHT")
        else
            r:SetPoint("TOPLEFT", inset, -inset)
            r:SetPoint("TOPRIGHT", -inset, -inset)
        end
        r.right:SetWidth(self.rightWidth or 0)
        local d = rows[i]
        r.data = d
        r.text:SetFontObject(d.header and FF.Fonts.header or FF.Fonts.small)
        if d.header then
            r.text:SetTextColor(FF.C.accent[1], FF.C.accent[2], FF.C.accent[3])
        else
            r.text:SetTextColor(FF.C.text[1], FF.C.text[2], FF.C.text[3])
        end
        r.text:SetText(d.text or "")
        r.right:SetText(d.right or "")
        setBadges(self, r, d.badges)
        if d.icon then
            setIcon(r.icon, d.icon)
            local size = self.iconFull and rowH or (rowH - 4) -- iconFull: square, edge to edge
            r.icon:ClearAllPoints()
            if self.iconFull then
                r.icon:SetPoint("TOPLEFT")
                r.icon:SetPoint("BOTTOMLEFT")
            else
                r.icon:SetPoint("LEFT", 2, 0)
                r.icon:SetHeight(size)
            end
            if d.coords then
                r.icon:SetTexCoord(d.coords[1], d.coords[2], d.coords[3], d.coords[4])
            else
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            r.icon:SetWidth(size)
            r.icon:Show()
        else
            r.icon:SetWidth(1)
            r.icon:Hide()
        end
        if d.bar then
            r.fill:ClearAllPoints()
            if self.barRight then
                r.fill:SetPoint("TOPRIGHT")
                r.fill:SetPoint("BOTTOMRIGHT")
            else
                r.fill:SetPoint("TOPLEFT")
                r.fill:SetPoint("BOTTOMLEFT")
            end
            local c = d.barColor or FF.C.accent
            r.fill:SetColorTexture(c[1], c[2], c[3], 0.3)
            r.fill:SetWidth(math.max(1, (self.perColumn and self.colWidth or (self:GetWidth() - 2 * inset)) * math.min(1, math.max(0, d.bar))))
            r.fill:Show()
        else
            r.fill:Hide()
        end
        r:Show()
    end
    for i = n + 1, #self.rows do
        self.rows[i]:Hide()
        self.rows[i].data = nil
    end
    if self.perColumn then
        local cols = math.max(1, math.ceil(n / self.perColumn))
        self:SetWidth(cols * self.colWidth + 2 * inset)
        self:SetHeight(top + math.min(n, self.perColumn) * rowH + inset)
    else
        self:SetHeight(top + n * rowH + inset)
    end
end

-- No 1px outline: rows then run edge to edge
local function setBorderShown(self, on)
    self.noBorder = not on
    for _, e in ipairs(self.ffEdges or {}) do
        e:SetShown(on and true or false)
    end
    if self.ffBg then
        self.ffBg:SetShown(on and true or false)
    end
    local inset = on and 1 or 0
    self.titleBar:ClearAllPoints()
    self.titleBar:SetPoint("TOPLEFT", inset, -inset)
    self.titleBar:SetPoint("TOPRIGHT", -inset, -inset)
    if self.lastRows then
        self:SetRows(self.lastRows)
    end
end

local function setTitleShown(self, on)
    self.titleBar:SetShown(on and true or false)
    if self.lastRows then
        self:SetRows(self.lastRows)
    end
end

-- Flat list window used by Cooldowns, Summons, Gear, Consumes, Resurrections.
function FF.ListWindow(id, title, width, maxRows)
    local f = FF.UI.Window(id, title, width, 60, { keepOpen = true })
    f.maxRows, f.rows = maxRows or 30, {}
    f.rowH = 18
    f.SetRows = setRows
    f.SetTitleShown = setTitleShown -- rightWidth = fixed width for the right column
    f.SetBorderShown = setBorderShown
    -- f:SetGrid(perColumn, columns, colWidth): rows beyond perColumn * columns are dropped
    function f:SetGrid(per, cols, colW)
        self.perColumn, self.colWidth = per, colW
        self.maxRows = per * cols
        if self.lastRows then
            self:SetRows(self.lastRows)
        end
    end
    setBorderShown(f, false) -- list windows: no outer border, no padding
    return f
end

-- Shared sound choices for alert settings
FF.SoundChoices = {
    { "RAID_WARNING", "Raid warning" },
    { "READY_CHECK", "Ready check" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
    { "UI_RAID_BOSS_WHISPER_WARNING", "Boss whisper" },
    { "PVP_THROUGH_QUEUE", "Queue pop" },
    { "TELL_MESSAGE", "Whisper" },
    { "MAP_PING", "Map ping" },
    { "IG_QUEST_LOG_ABANDON_QUEST", "Low thud" },
    { "none", "No sound" },
}

function FF.PlaySound(key)
    local id = key and key ~= "none" and SOUNDKIT[key]
    if id then
        PlaySound(id, "Master")
    end
end

-- Raid-warning style centre-screen message
function FF.Alert(text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
    end
end

