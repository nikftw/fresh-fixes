local _, FF = ...
local M = FF.Module("QoL")

-- More Leatrix Plus features: social filters, chat, interface text/frames,
-- tooltip, system/sound. Part of the "Quality of Life" module; every
-- feature is a toggle in /ff options and does nothing while off.
FF.Init("QoL", function()
    local readable = FF.readable
    local db = FF.DB("qolextra", {
        -- social
        blockPartyInvites = false, blockFriendRequests = false, blockSharedQuests = false,
        blockPetDuels = false,
        -- text
        hideZoneText = false, hideKeybindText = false, hideMacroText = false, noHitIndicators = false,
        -- frames
        noAlerts = false, hideTalkingHead = false, hideBossBanner = false, hideEventToasts = false,
        hideCleanupButtons = false,
        -- tooltip
        tipGuildRank = true, tipTarget = true, tipHideInCombat = false,
        -- system
        noScreenEffects = false, combatPlates = false, noConfirmLoot = false, fasterMovieSkip = true,
        quietRestedEmotes = false, keepAudioSynced = false, trainAll = true, lootSparkles = true,
    })
    db.mute = db.mute or {} -- [soundFileID] = true

    ---------------------------------------------------------------------------
    -- Social
    ---------------------------------------------------------------------------
    M.On("PARTY_INVITE_REQUEST", function() return db.blockPartyInvites end, function(_, name)
        if db.blockPartyInvites and not FF.IsFriendOrGuild(name) then
            DeclineGroup()
            StaticPopup_Hide("PARTY_INVITE")
        end
    end)

    M.On("BN_FRIEND_INVITE_ADDED", function() return db.blockFriendRequests end, function()
        if not db.blockFriendRequests or not BNGetNumFriendInvites then
            return
        end
        for i = BNGetNumFriendInvites(), 1, -1 do
            local id = BNGetFriendInviteInfo(i)
            if id then
                BNDeclineFriendInvite(id)
            end
        end
    end)

    M.On("QUEST_DETAIL", function() return db.blockSharedQuests end, function()
        if db.blockSharedQuests and UnitIsPlayer("npc") and not FF.IsFriendOrGuild(UnitName("npc")) then
            DeclineQuest()
        end
    end)

    M.On("PET_BATTLE_PVP_DUEL_REQUESTED", function() return db.blockPetDuels end, function()
        if db.blockPetDuels and C_PetBattles and C_PetBattles.CancelPVPDuel then
            C_PetBattles.CancelPVPDuel()
            StaticPopup_Hide("PET_BATTLE_PVP_DUEL_REQUESTED")
        end
    end)



    ---------------------------------------------------------------------------
    -- Interface text and frames
    ---------------------------------------------------------------------------
    local BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

    local function applyButtonText()
        for _, prefix in ipairs(BUTTONS) do
            for i = 1, 12 do
                local b = _G[prefix .. i]
                if b then
                    local hotkey = b.HotKey or _G[prefix .. i .. "HotKey"]
                    local name = b.Name or _G[prefix .. i .. "Name"]
                    if hotkey then
                        hotkey:SetAlpha(db.hideKeybindText and 0 or 1)
                    end
                    if name then
                        name:SetAlpha(db.hideMacroText and 0 or 1)
                    end
                end
            end
        end
    end

    local function silence(frame)
        if frame then
            frame:UnregisterAllEvents()
            frame:Hide()
        end
    end

    local function hideForever(region)
        if region then
            region:SetAlpha(0)
            if region.Hide then
                region:Hide()
            end
        end
    end

    local function applyFrames()
        if db.hideZoneText then
            silence(ZoneTextFrame)
            silence(SubZoneTextFrame)
        end
        if db.noAlerts then
            silence(AlertFrame)
        end
        if db.hideBossBanner then
            silence(BossBanner)
        end
        if db.hideEventToasts then
            silence(EventToastManagerFrame)
        end
        if db.noHitIndicators then
            hideForever(PlayerHitIndicator)
            hideForever(PetHitIndicator)
            local hit = PlayerFrame and PlayerFrame.PlayerFrameContent
                and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
                and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator
            hideForever(hit)
        end
        if db.hideCleanupButtons then
            hideForever(BagItemAutoSortButton)
            hideForever(BankItemAutoSortButton)
        end
        applyButtonText()
    end

    -- Talking head: close it as soon as it opens
    M.On("TALKINGHEAD_REQUESTED", function() return db.hideTalkingHead end, function()
        if db.hideTalkingHead and TalkingHeadFrame then
            if TalkingHeadFrame.CloseImmediately then
                TalkingHeadFrame:CloseImmediately()
            else
                TalkingHeadFrame:Hide()
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Tooltip: guild rank, unit's target, hide world units in combat
    ---------------------------------------------------------------------------
    local function onUnitTip(tip)
        if tip ~= GameTooltip then
            return
        end
        local _, unit = tip:GetUnit()
        if not unit or not readable(unit) then
            return
        end
        if db.tipHideInCombat and InCombatLockdown() and not IsShiftKeyDown()
            and not (UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player")) then
            tip:Hide()
            return
        end
        if db.tipGuildRank and UnitIsPlayer(unit) then
            local guild, rank = GetGuildInfo(unit)
            if readable(guild) and guild and guild == GetGuildInfo("player") and rank then
                tip:AddLine("Rank: |cffffffff" .. rank .. "|r", 0.4, 0.8, 1)
            end
        end
        if db.tipTarget then
            local target = UnitName(unit .. "target")
            if readable(target) and target then
                local _, class = UnitClass(unit .. "target")
                tip:AddLine("Target: " .. (UnitIsUnit(unit .. "target", "player") and "|cffff4040YOU|r"
                    or FF.ClassColor(class, target)), 0.4, 0.8, 1)
            end
        end
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTip)

    ---------------------------------------------------------------------------
    -- System
    ---------------------------------------------------------------------------
    local function applySystem()
        if db.noScreenEffects then
            SetCVar("ffxDeath", 0)
            SetCVar("ffxNether", 0)
            pcall(SetCVar, "ffxVenari", 0)
        end
        if db.keepAudioSynced then
            SetCVar("Sound_OutputDriverIndex", "0")
        end
        for id in pairs(db.mute) do
            if MuteSoundFile then
                MuteSoundFile(id)
            end
        end
    end

    M.On("PLAYER_REGEN_DISABLED", function() return db.combatPlates end, function()
        if db.combatPlates then
            SetCVar("nameplateShowEnemies", 1)
        end
    end)
    M.On("PLAYER_REGEN_ENABLED", function() return db.combatPlates end, function()
        if db.combatPlates then
            SetCVar("nameplateShowEnemies", 0)
        end
    end)

    M.On("CONFIRM_LOOT_ROLL", function() return db.noConfirmLoot end, function(_, rollID, rollType)
        if db.noConfirmLoot then
            ConfirmLootRoll(rollID, rollType)
            StaticPopup_Hide("CONFIRM_LOOT_ROLL")
        end
    end)
    M.On("LOOT_BIND_CONFIRM", function() return db.noConfirmLoot end, function(_, slot)
        if db.noConfirmLoot then
            ConfirmLootSlot(slot)
            StaticPopup_Hide("LOOT_BIND")
        end
    end)

    M.On("PLAYER_UPDATE_RESTING", function() return db.quietRestedEmotes end, function()
        if db.quietRestedEmotes then
            SetCVar("Sound_EnableEmoteSounds", IsResting() and 0 or 1)
        end
    end)

    M.On("VOICE_CHAT_OUTPUT_DEVICES_UPDATED", function() return db.keepAudioSynced end, function()
        if db.keepAudioSynced and Sound_GameSystem_RestartSoundSystem and not InCinematic() then
            SetCVar("Sound_OutputDriverIndex", "0")
            Sound_GameSystem_RestartSoundSystem()
        end
    end)

    -- Escape skips cinematics without the "are you sure" prompt
    local function hookMovies()
        if CinematicFrame and not CinematicFrame.ffHooked then
            CinematicFrame.ffHooked = true
            CinematicFrame:HookScript("OnKeyDown", function(_, key)
                if db.fasterMovieSkip and key == "ESCAPE" and CinematicFrame:IsShown()
                    and CinematicFrame.closeDialog and CinematicFrame.closeDialog.confirmButton then
                    CinematicFrame.closeDialog:Hide()
                    CinematicFrame.closeDialog.confirmButton:Click()
                end
            end)
        end
        if MovieFrame and not MovieFrame.ffHooked then
            MovieFrame.ffHooked = true
            MovieFrame:HookScript("OnKeyUp", function(self, key)
                if db.fasterMovieSkip and key == "ESCAPE" and self:IsShown() and self.StopMovie then
                    self:StopMovie()
                end
            end)
        end
    end

    -- Trainer: "Train all", beside the game's Train button. Forever's
    -- GetTrainerServiceInfo does not keep the service type in a fixed slot
    -- (same approach as Naowh), and a button parked on the frame corner
    -- covers the spell list so the normal Train button never receives clicks.
    local SERVICE_KINDS = { available = true, unavailable = true, used = true, header = true }

    local function serviceInfo(i)
        local values = { GetTrainerServiceInfo(i) }
        local name = values[1]
        if not (readable(name) and type(name) == "string" and name ~= "") then
            return
        end
        local kind
        for k = 2, #values do
            local v = values[k]
            if readable(v) and type(v) == "string" and SERVICE_KINDS[v] then
                kind = v
                break
            end
        end
        return name, kind
    end

    local function buyAvailable()
        local money = GetMoney() or 0
        local list, count = {}, GetNumTrainerServices() or 0
        for i = 1, count do
            local name, kind = serviceInfo(i)
            local cost = GetTrainerServiceCost(i)
            if not (readable(cost) and type(cost) == "number") then
                cost = 0
            end
            local level = select(4, GetTrainerServiceInfo(i))
            local open = kind == "available" or (kind == nil and readable(level) and type(level) == "number"
                and level > 0 and level <= (UnitLevel("player") or 0))
            if name and open and cost <= money then
                list[#list + 1] = { index = i, name = name, cost = cost }
            end
        end
        -- Highest index first: buying reindexes the list under it.
        table.sort(list, function(a, b)
            return a.index > b.index
        end)
        local n = 0
        for _, o in ipairs(list) do
            if o.cost <= money and serviceInfo(o.index) == o.name then
                BuyTrainerService(o.index)
                money = money - o.cost
                n = n + 1
            end
        end
        if n > 0 then
            FF.print(("Trained %d skills"):format(n))
        end
    end

    local function placeTrainAll()
        local frame = ClassTrainerFrame
        local train = ClassTrainerTrainButton or (frame and frame.TrainButton)
        local b = frame and frame.ffTrainAll
        if not db.trainAll or not frame or not train then
            if b then
                b:Hide()
            end
            return
        end
        if not b then
            b = FF.UI.Button(frame, "Train all", 80, train:GetHeight() or 22, buyAvailable)
            frame.ffTrainAll = b
        end
        local h = train:GetHeight()
        b:SetHeight(h and h > 1 and h or 22)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", train, "LEFT", -2, 0)
        b:SetFrameLevel(train:GetFrameLevel() + 2)
        b:Show()
    end

    local function hookTrainer()
        local frame = ClassTrainerFrame
        if not frame or frame.ffTrainHook then
            return
        end
        frame.ffTrainHook = true
        frame:HookScript("OnShow", placeTrainAll)
    end

    M.On("ADDON_LOADED", function() return true end, function(_, name)
        if name == "Blizzard_TrainerUI" then
            hookTrainer()
            placeTrainAll()
        end
    end)
    M.On("TRAINER_SHOW", function() return db.trainAll end, function()
        hookTrainer()
        placeTrainAll()
    end)

    FF.On("FF_READY", function()
        applyFrames()
        applySystem()
        hookMovies()
        hookTrainer()
        placeTrainAll()
    end)

    -- Optional overrides; nil means "leave the game's setting alone"
    local function applyFonts()
        if db.questFont and QuestFont then
            local font, _, flags = QuestFont:GetFont()
            QuestFont:SetFont(font, db.questFont, flags)
        end
        if db.weather then
            SetCVar("weatherDensity", db.weather)
        end
    end
    FF.On("FF_READY", applyFonts)

    -- Loot sparkles: the sparkle effect on lootable corpses, with outlines off.
    -- The previous values are kept so turning it off puts them back.
    local SPARKLE_CVARS = {
        outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
        raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0",
    }
    local function applySparkles()
        if db.lootSparkles then
            db.sparkleSaved = db.sparkleSaved or {}
            for cvar, v in pairs(SPARKLE_CVARS) do
                local ok, cur = pcall(GetCVar, cvar)
                if ok and cur ~= nil and db.sparkleSaved[cvar] == nil and cur ~= v then
                    db.sparkleSaved[cvar] = cur
                end
                pcall(SetCVar, cvar, v)
            end
        elseif db.sparkleSaved then
            for cvar, v in pairs(db.sparkleSaved) do
                pcall(SetCVar, cvar, v)
            end
            db.sparkleSaved = nil
        end
    end
    FF.On("FF_READY", function()
        if db.lootSparkles then
            applySparkles()
        end
    end)

    FF.Settings("QoL", function(L)
        local main = FF.modules.QoL.main
        local mdb = main.db
        local function T(text, d, key, fn, tip)
            L:Toggle(text, d, key, { tip = tip, onChange = function()
                if fn then
                    fn()
                end
                M.Relisten()
            end })
        end

        L:Header("Vendors")
        T("Auto repair", mdb, "repair")
        L:Toggle("Use guild funds first", mdb, "guildRepair", { dep = function() return mdb.repair end, indent = 12 })
        L:Toggle("Print repair cost", mdb, "repairSummary", { dep = function() return mdb.repair end, indent = 12 })
        T("Sell grey items (hold Shift to skip)", mdb, "sellJunk")
        L:Toggle("Print what was sold", mdb, "sellSummary", { dep = function() return mdb.sellJunk end, indent = 12 })
        T("'Train all' button at trainers", db, "trainAll", placeTrainAll)

        L:Header("Looting and items")
        T("Faster auto loot", mdb, "fasterLoot")
        T("Skip loot roll / bind confirmations", db, "noConfirmLoot")
        T("Pre-fill DELETE when destroying items", mdb, "easyDelete")

        L:Header("Quests and NPCs")
        T("Auto accept and turn in quests", mdb, "autoQuests", nil, "Hold Shift to skip")
        T("Skip single-option gossip", mdb, "skipGossip")

        L:Header("Invites and requests")
        T("Decline duels (except friends/guild)", mdb, "declineDuels")
        T("Block pet battle duels", db, "blockPetDuels")
        T("Decline guild invites", mdb, "declineGuildInvites")
        T("Accept invites from friends/guild", mdb, "acceptGroupInvites")
        T("Block party invites from everyone else", db, "blockPartyInvites")
        T("Block Battle.net friend requests", db, "blockFriendRequests")
        T("Block shared quests from strangers", db, "blockSharedQuests")

        L:Header("Death and summons")
        T("Accept summons (out of combat)", mdb, "acceptSummons")
        T("Accept resurrects (not during a boss)", mdb, "acceptResurrect")
        T("Auto release in battlegrounds", mdb, "autoReleasePvP")

        L:Header("Interface")
        T("Hide red error text", mdb, "hideErrors", main.applyErrors)
        T("Hide zone text (reload)", db, "hideZoneText")
        T("Hide keybind text on action bars", db, "hideKeybindText", applyButtonText)
        T("Hide macro text on action bars", db, "hideMacroText", applyButtonText)
        T("Hide portrait damage numbers (reload)", db, "noHitIndicators")
        T("Hide alert toasts (reload)", db, "noAlerts")
        T("Hide talking head", db, "hideTalkingHead")
        T("Hide boss banner (reload)", db, "hideBossBanner")
        T("Hide event toasts (reload)", db, "hideEventToasts")
        T("Hide bag clean-up buttons (reload)", db, "hideCleanupButtons")
        T("Hide action bar gryphons", mdb, "hideGryphons", main.applyGryphons)
        L:Slider("Quest text size", db, "questFont", 8, 24, 1, { onChange = applyFonts,
            fmt = function(v) return v and tostring(v) or "game" end })

        L:Header("Tooltip")
        T("Show guild rank", db, "tipGuildRank")
        T("Show the unit's target", db, "tipTarget")
        T("Hide world units in combat", db, "tipHideInCombat", nil, "Hold Shift to show them")

        L:Header("Camera and graphics")
        T("Extended camera distance", mdb, "maxCamera", main.applyCamera)
        L:Slider("Max distance factor", mdb, "cameraFactor", 1, 2.6, 0.1, { dep = function() return mdb.maxCamera end,
            onChange = main.applyCamera, indent = 12 })
        T("Disable screen glow", mdb, "noScreenGlow", main.applyGlow)
        T("No death screen effects", db, "noScreenEffects", applySystem)
        T("Enemy nameplates only in combat", db, "combatPlates")
        L:Slider("Weather density", db, "weather", 0, 3, 1, { onChange = applyFonts,
            fmt = function(v) return v and tostring(v) or "game" end })
        T("Escape skips cinematics instantly", db, "fasterMovieSkip")
        L:Toggle("Loot sparkles (items and corpses)", db, "lootSparkles", { onChange = applySparkles,
            tip = "Shows the loot sparkle effect with outlines turned off. Turning it off restores your previous outline settings." })

        L:Header("Sound")
        T("Silence emote sounds while resting", db, "quietRestedEmotes")
        T("Keep audio on the system output device", db, "keepAudioSynced", applySystem)
        L:Input("Muted sound file IDs", db, "_mute", {
            lines = 2,
            get = function()
                local ids = {}
                for id in pairs(db.mute) do
                    ids[#ids + 1] = tostring(id)
                end
                table.sort(ids)
                return table.concat(ids, ", ")
            end,
            set = function(v)
                for id in pairs(db.mute) do
                    if UnmuteSoundFile then
                        UnmuteSoundFile(id)
                    end
                end
                wipe(db.mute)
                for id in v:gmatch("%d+") do
                    db.mute[tonumber(id)] = true
                end
                applySystem()
            end,
            tip = "Comma separated sound file IDs (wago.tools / wowhead list them)",
        })
    end)

    FF.Command("qol", function()
        FF.ShowOptions("QoL")
    end, "quality of life settings")
end)
