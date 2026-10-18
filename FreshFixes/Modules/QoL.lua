local _, FF = ...
local M = FF.Module("QoL")

-- Leatrix-Plus-style tweaks, each one a toggle in /ff options.
-- Only the events a feature needs are registered.
FF.Init("QoL", function()
    -- Event handlers that only listen while their setting is on (M.Relisten
    -- re-checks after a settings change). Shared with QoL_Extra.lua.
    M.listeners = M.listeners or {}
    local function on(event, cond, fn)
        M.listeners[#M.listeners + 1] = { event, fn, cond }
    end
    M.On = on
    function M.Relisten()
        for _, l in ipairs(M.listeners) do
            FF.Listen(l[1], l[2], l[3]() and true or false)
        end
    end
    FF.On("FF_READY", function()
        M.Relisten()
    end)
    local db = FF.DB("qol", {
        repair = true, guildRepair = true, sellJunk = true, fasterLoot = true,
        declineDuels = false, declineGuildInvites = false, acceptGroupInvites = false,
        acceptSummons = false, acceptResurrect = false, autoReleasePvP = false,
        hideErrors = false, autoQuests = true, skipGossip = true,
        easyDelete = true, noScreenGlow = true, hideGryphons = false,
        repairSummary = false, sellSummary = false,
    })

    local numSlots, useItem = C_Container.GetContainerNumSlots, C_Container.UseContainerItem

    local function slotInfo(bag, slot)
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then
            return i.quality, i.hasNoValue, i.isLocked
        end
    end

    ---------------------------------------------------------------------------
    -- Merchant: repair + sell junk
    ---------------------------------------------------------------------------
    local function sellJunk()
        local sold = 0
        local queue = {}
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, numSlots(bag) or 0 do
                local quality, noValue, locked = slotInfo(bag, slot)
                if quality == 0 and not noValue and not locked then
                    queue[#queue + 1] = { bag, slot }
                end
            end
        end
        local i = 0
        local function nextItem()
            i = i + 1
            local q = queue[i]
            if not q or not MerchantFrame:IsShown() then
                if sold > 0 then
                    if db.sellSummary then
                        FF.print(("Sold %d junk item%s"):format(sold, sold == 1 and "" or "s"))
                    end
                end
                return
            end
            useItem(q[1], q[2])
            sold = sold + 1
            C_Timer.After(0.15, nextItem)
        end
        nextItem()
    end

    local function repair()
        if not CanMerchantRepair() then
            return
        end
        local cost, needed = GetRepairAllCost()
        if not needed or cost <= 0 then
            return
        end
        local useGuild = db.guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
        if useGuild then
            local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
            useGuild = limit == -1 or (limit and limit >= cost)
        end
        if useGuild then
            RepairAllItems(true)
            if db.repairSummary then
                FF.print("Repaired (guild):", GetCoinTextureString(cost))
            end
        elseif GetMoney() >= cost then
            RepairAllItems()
            if db.repairSummary then
                FF.print("Repaired:", GetCoinTextureString(cost))
            end
        else
            FF.print("Not enough gold to repair")
        end
    end

    on("MERCHANT_SHOW", function() return db.repair or db.sellJunk end, function()
        if IsShiftKeyDown() then
            return
        end
        if db.repair then
            repair()
        end
        if db.sellJunk then
            sellJunk()
        end
    end)

    ---------------------------------------------------------------------------
    -- Faster auto loot
    ---------------------------------------------------------------------------
    local lastLoot = 0
    on("LOOT_READY", function() return db.fasterLoot end, function()
        if not db.fasterLoot or GetTime() - lastLoot < 0.3 then
            return
        end
        lastLoot = GetTime()
        if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Popups: duels, invites, summons, resurrects
    ---------------------------------------------------------------------------
    on("DUEL_REQUESTED", function() return db.declineDuels end, function(_, name)
        if db.declineDuels and not FF.IsFriendOrGuild(name) then
            CancelDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
        end
    end)

    on("GUILD_INVITE_REQUEST", function() return db.declineGuildInvites end, function()
        if db.declineGuildInvites then
            DeclineGuild()
            StaticPopup_Hide("GUILD_INVITE")
        end
    end)

    on("PARTY_INVITE_REQUEST", function() return db.acceptGroupInvites end, function(_, name)
        if db.acceptGroupInvites and FF.readable(name) and FF.IsFriendOrGuild(name) then
            AcceptGroup()
            StaticPopup_Hide("PARTY_INVITE")
        end
    end)

    on("CONFIRM_SUMMON", function() return db.acceptSummons end, function()
        if not db.acceptSummons then
            return
        end
        C_Timer.After(1, function()
            if not InCombatLockdown() and not UnitAffectingCombat("player") then
                if C_SummonInfo and C_SummonInfo.ConfirmSummon then
                    C_SummonInfo.ConfirmSummon()
                elseif ConfirmSummon then
                    ConfirmSummon()
                end
                StaticPopup_Hide("CONFIRM_SUMMON")
            end
        end)
    end)

    on("RESURRECT_REQUEST", function() return db.acceptResurrect end, function()
        if db.acceptResurrect and not (IsEncounterInProgress and IsEncounterInProgress()) then
            AcceptResurrect()
            StaticPopup_Hide("RESURRECT")
            StaticPopup_Hide("RESURRECT_NO_SICKNESS")
            StaticPopup_Hide("RESURRECT_NO_TIMER")
        end
    end)

    on("PLAYER_DEAD", function() return db.autoReleasePvP end, function()
        if db.autoReleasePvP then
            local _, instanceType = IsInInstance()
            if instanceType == "pvp" then
                C_Timer.After(0.5, RepopMe)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Quests & gossip (hold Shift to skip)
    ---------------------------------------------------------------------------
    local Gossip = C_GossipInfo
    on("QUEST_DETAIL", function() return db.autoQuests end, function()
        if db.autoQuests and not IsShiftKeyDown() then
            AcceptQuest()
        end
    end)
    on("QUEST_PROGRESS", function() return db.autoQuests end, function()
        if db.autoQuests and not IsShiftKeyDown() and IsQuestCompletable() then
            CompleteQuest()
        end
    end)
    on("QUEST_COMPLETE", function() return db.autoQuests end, function()
        if db.autoQuests and not IsShiftKeyDown() and GetNumQuestChoices() <= 1 then
            GetQuestReward(GetNumQuestChoices())
        end
    end)
    on("GOSSIP_SHOW", function() return db.autoQuests or db.skipGossip end, function()
        if IsShiftKeyDown() or not Gossip then
            return
        end
        if db.autoQuests then
            for _, q in ipairs(Gossip.GetActiveQuests and Gossip.GetActiveQuests() or {}) do
                if q.isComplete then
                    Gossip.SelectActiveQuest(q.questID)
                    return
                end
            end
            local available = Gossip.GetAvailableQuests and Gossip.GetAvailableQuests() or {}
            if available[1] then
                Gossip.SelectAvailableQuest(available[1].questID)
                return
            end
        end
        if db.skipGossip then
            local options = Gossip.GetOptions and Gossip.GetOptions() or {}
            local active = Gossip.GetActiveQuests and Gossip.GetActiveQuests() or {}
            local available = Gossip.GetAvailableQuests and Gossip.GetAvailableQuests() or {}
            if #options == 1 and #active == 0 and #available == 0 and options[1].gossipOptionID then
                Gossip.SelectOption(options[1].gossipOptionID)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Settings applied once (and when toggled)
    ---------------------------------------------------------------------------
    local function applyErrors()
        if not UIErrorsFrame then
            return
        end
        if db.hideErrors then
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        else
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
    end

    local function applyGlow()
        if db.noScreenGlow then
            SetCVar("ffxGlow", 0)
        end
    end

    local function applyGryphons()
        local show = not db.hideGryphons
        if MainMenuBar and MainMenuBar.EndCaps then
            MainMenuBar.EndCaps:SetShown(show)
        end
        if MainMenuBarLeftEndCap then
            MainMenuBarLeftEndCap:SetShown(show)
            MainMenuBarRightEndCap:SetShown(show)
        end
    end

    -- Typing DELETE for good items
    local function hookDelete()
        local d = StaticPopupDialogs.DELETE_GOOD_ITEM
        if d and not d.ffHooked then
            d.ffHooked = true
            local orig = d.OnShow
            d.OnShow = function(self, ...)
                if orig then
                    orig(self, ...)
                end
                local box = self.editBox or self.EditBox
                if db.easyDelete and box then
                    box:SetText(DELETE_ITEM_CONFIRM_STRING)
                end
            end
        end
    end

    FF.On("FF_READY", function()
        applyErrors()
        applyGlow()
        applyGryphons()
        hookDelete()
    end)

    -- The settings page (QoL_Extra.lua) needs these
    M.main = {
        db = db, applyErrors = applyErrors,
        applyGlow = applyGlow, applyGryphons = applyGryphons,
    }
end)
