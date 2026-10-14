local _, FF = ...
local M = FF.Module("Map")

-- World map frame tweaks (Leatrix Maps style): scale, no fade while moving,
-- drag the windowed map. Reveal and icons live in MapReveal.lua.
FF.Init("Map", function()
    local db = FF.DB("map", { scale = 1, noFade = true, unlock = false })
    M.mapdb = db

    local function setupWorldMap()
        if not WorldMapFrame or M.hooked then
            return
        end
        M.hooked = true
        WorldMapFrame:HookScript("OnShow", function()
            if db.scale ~= 1 and not InCombatLockdown() then
                WorldMapFrame:SetScale(db.scale)
            end
        end)

        -- Leatrix Maps "unlock map frame": drag the windowed map by its title area
        local drag = WorldMapFrame.BorderFrame and (WorldMapFrame.BorderFrame.TitleContainer or WorldMapFrame.BorderFrame)
        if drag and drag.HookScript then
            WorldMapFrame:SetMovable(true)
            WorldMapFrame:SetClampedToScreen(true)
            drag:HookScript("OnMouseDown", function(_, button)
                if db.unlock and button == "LeftButton" and not InCombatLockdown()
                    and not (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) then
                    WorldMapFrame:StartMoving()
                end
            end)
            drag:HookScript("OnMouseUp", function()
                if db.unlock then
                    WorldMapFrame:StopMovingOrSizing()
                end
            end)
        end
    end

    local function applyFade()
        pcall(SetCVar, "mapFade", db.noFade and "0" or "1")
    end

    FF.On("FF_READY", function()
        setupWorldMap()
        applyFade()
    end)

    M.applyFade = applyFade
    M.applyScale = function()
        if WorldMapFrame and not InCombatLockdown() then
            WorldMapFrame:SetScale(db.scale)
        end
    end
end)
