local _, FF = ...

-- One reusable copy/paste window for every export and import.
-- Created on first use only.
local box

local function build()
    local f = FF.UI.Window("TextBox", "", 600, 440, { strata = "DIALOG" })

    local area = CreateFrame("Frame", nil, f)
    area:SetPoint("TOPLEFT", 8, -(FF.UI.TITLE_H + 8))
    area:SetPoint("BOTTOMRIGHT", -8, 40)
    FF.Skin(area, "panel")

    local scroll = FF.UI.Scroll(area)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -6, 4)

    local edit = CreateFrame("EditBox", nil, scroll.child)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(FF.Fonts.normal)
    edit:SetPoint("TOPLEFT")
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    edit:SetScript("OnTextChanged", function(self)
        scroll.child:SetHeight(math.max(self:GetHeight(), 10))
        scroll.Update()
    end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
        local top = -y
        local view = scroll:GetVerticalScroll()
        if top < view then
            scroll:SetVerticalScroll(top)
        elseif top + h > view + scroll:GetHeight() then
            scroll:SetVerticalScroll(top + h - scroll:GetHeight())
        end
        scroll.Update()
    end)
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)
    f.edit = edit

    f.ok = FF.UI.Button(f, "Close", 110, 24, function()
        if f.onAccept then
            f.onAccept(edit:GetText())
        else
            f:Hide()
        end
    end)
    f.ok:SetPoint("BOTTOMRIGHT", -8, 8)

    f.status = FF.Text(f, "small")
    f.status:SetPoint("BOTTOMLEFT", 10, 14)
    f.status:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(FF.C.muted[1], FF.C.muted[2], FF.C.muted[3])
    return f
end

-- Export: FF.ShowText("Title", text)
-- Import: FF.ShowText("Title", "", function(text) ... end, "Import")
--   the callback may return an error string to keep the window open.
function FF.ShowText(title, text, onAccept, acceptLabel)
    box = box or build()
    box.title:SetText(title)
    box.status:SetText(onAccept and ("Paste a string, then press " .. (acceptLabel or "Import"))
        or "Ctrl+A, Ctrl+C to copy")
    box.onAccept = onAccept and function(t)
        local err = onAccept(t)
        if err then
            box.status:SetText(FF.Hex(FF.C.bad) .. err .. "|r")
        else
            box:Hide()
        end
    end
    box.ok:SetLabel(onAccept and (acceptLabel or "Import") or "Close")
    box.edit:SetText(text or "")
    box:Show()
    box.edit:SetFocus()
    if text and text ~= "" then
        box.edit:HighlightText()
    end
end
