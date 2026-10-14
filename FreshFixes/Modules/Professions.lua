local _, FF = ...
local M = FF.Module("Professions")

-- Professions export for the FF website (part of Import & Export), for the
-- logged-in character only. Nothing is saved and nothing listens in the
-- background. "Export" reads skills and opens a small window with a button
-- per crafting profession: Forever doesn't let addons open professions by
-- themselves, so each one is a (secure) click; the recipes are read, the
-- profession closes again, and the PROF:1 string pops up when all are done.
FF.Init("Profiles", function()
    local readable = FF.readable
    local busy

    local function character()
        local display = FF.UnitIdentity("player")
        local _, class = UnitClass("player")
        return {
            name = display, class = class, race = UnitRace("player"), level = UnitLevel("player"),
            faction = UnitFactionGroup("player"), guild = IsInGuild() and GetGuildInfo("player") or nil,
            professions = {},
        }
    end

    local function entry(c, id, name)
        for _, p in ipairs(c.professions) do
            if (id and p.skillLine == id) or p.name == name then
                return p
            end
        end
        local p = { skillLine = id, name = name }
        c.professions[#c.professions + 1] = p
        return p
    end

    -- Skill levels (no window needed)
    local function readSkills(c)
        for _, idx in pairs({ GetProfessions() }) do
            local name, _, rank, max, _, offset, skillLine = GetProfessionInfo(idx)
            if readable(name) and name then
                local p = entry(c, skillLine, name)
                p.rank, p.max = rank, max
                p.spellOffset = offset -- for the fetch button; not exported
            end
        end
    end

    -- Learned recipes from the profession window that is open right now.
    -- Returns the profession's (parent) skill line id and name when read.
    local function readOpenWindow(c)
        local T = C_TradeSkillUI
        if T.IsTradeSkillLinked() or T.IsTradeSkillGuild() or T.IsNPCCrafting() then
            return
        end
        if T.IsTradeSkillReady and not T.IsTradeSkillReady() then
            return -- recipe list still loading
        end
        local info = T.GetBaseProfessionInfo()
        if not info or not info.professionName then
            return
        end
        local recipes = {}
        for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
            local r = T.GetRecipeInfo(id)
            if r and r.learned then
                recipes[#recipes + 1] = id
            end
        end
        if #recipes == 0 then
            return
        end
        table.sort(recipes)
        local id = info.parentProfessionID or info.professionID
        local p = entry(c, id, info.professionName)
        p.rank, p.max = info.skillLevel or p.rank, info.maxSkillLevel or p.max
        p.recipes, p.scanned = recipes, GetServerTime()
        return id, info.professionName
    end

    -- No recipe list to read
    local GATHERING = { [182] = true, [393] = true, [356] = true }

    -- The spell that opens a profession: from its spellbook slot, else by name
    local function openSpell(p)
        local slot = p.spellOffset and p.spellOffset + 1
        if slot then
            local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if info and info.spellID then
                return info.spellID
            end
        end
        return p.skillLine == 186 and "Smelting" or p.name
    end

    local panel, watcher, session

    local function closeProfession()
        if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then
            pcall(C_TradeSkillUI.CloseTradeSkill)
        end
    end

    local function finish()
        if not session then
            return
        end
        if InCombatLockdown() then
            C_Timer.After(1, finish) -- the window holds secure buttons
            return
        end
        local s = session
        session = nil
        busy = false
        if watcher then
            watcher:Cancel()
            watcher = nil
        end
        if panel then
            panel:Hide()
        end
        for _, p in ipairs(s.c.professions) do
            p.spellOffset = nil
        end
        if s.done then
            s.done(s.c)
        end
    end

    local function refreshPanel()
        local left = 0
        for _, b in ipairs(panel.buttons) do
            local p = b.prof
            if b:IsShown() and p then
                if p.recipes then
                    b.status:SetText(FF.Hex(FF.C.good) .. #p.recipes .. " recipes|r")
                    FF.SetBorder(b, FF.C.good)
                else
                    b.status:SetText(FF.Hex(FF.C.muted) .. "click to read|r")
                    left = left + 1
                end
            end
        end
        return left
    end

    local function buildPanel()
        panel = FF.UI.Window("ProfFetch", "Fetch professions", 260, 100, { keepOpen = true, strata = "DIALOG" })
        panel.buttons = {} -- closes itself once every profession is read (or with X)
        panel:HookScript("OnHide", finish)
    end

    local function fetch(done)
        if busy then
            FF.print("Already fetching - use the Fetch professions window.")
            return
        end
        if InCombatLockdown() then
            FF.print("Can't fetch professions in combat.")
            return
        end
        local c = character()
        readSkills(c)
        readOpenWindow(c)
        local crafting = {}
        for _, p in ipairs(c.professions) do
            if p.skillLine and not GATHERING[p.skillLine] then
                crafting[#crafting + 1] = p
            end
        end
        if #crafting == 0 then
            if done then
                done(c)
            end
            return
        end
        busy = true
        session = { c = c, done = done }
        if not panel then
            buildPanel()
        end
        for i, p in ipairs(crafting) do
            local b = panel.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
                b:SetSize(244, 24)
                b:SetPoint("TOPLEFT", 8, -(FF.UI.TITLE_H + 9) - (i - 1) * 28)
                b:RegisterForClicks("AnyUp", "AnyDown")
                FF.Skin(b, "row")
                b.label = FF.Text(b)
                b.label:SetPoint("LEFT", 8, 0)
                b.status = FF.Text(b, "small")
                b.status:SetPoint("RIGHT", -8, 0)
                b:HookScript("OnEnter", function(self) FF.SetBg(self, FF.C.hover) end)
                b:HookScript("OnLeave", function(self) FF.SetBg(self, FF.C.row) end)
                panel.buttons[i] = b
            end
            b.prof = p
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", openSpell(p))
            b.label:SetText(p.name)
            FF.SetBorder(b, FF.C.border)
            b:Show()
        end
        for i = #crafting + 1, #panel.buttons do
            panel.buttons[i]:Hide()
            panel.buttons[i].prof = nil
        end
        panel:SetHeight(FF.UI.TITLE_H + 9 + #crafting * 28 + 4)
        refreshPanel()
        panel:Show()
        -- Only while this window is open: read whichever profession gets opened
        watcher = C_Timer.NewTicker(0.4, function()
            if not session then
                return
            end
            local id = readOpenWindow(session.c)
            if id then
                closeProfession()
                if refreshPanel() == 0 then
                    C_Timer.After(0.6, finish)
                end
            end
        end)
    end

    local function export()
        fetch(function(c)
            FF.ShowText("Professions export", FF.Encode("PROF", 1, {
                exported = GetServerTime(), addon = FF.version, characters = { c },
            }))
        end)
    end
    M.Export = export

    -- Section on the Import & Export page
    function M.Section(L)
        L:Header("Professions")
        L:Desc("Export this character's professions and recipes for the FF website. Click each profession in the window that opens; the string appears when they're all read.")
        L:Buttons({ { "Export professions", export } })
    end

    FF.Command("prof", export, "export this character's professions for the website")
end)
