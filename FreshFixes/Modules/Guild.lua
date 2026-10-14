local _, FF = ...
local M = FF.Module("Guild")

-- Guild roster export. Plain text, one member a line. This client does not
-- let addons write public or officer notes (C_GuildInfo.SetNote is reserved
-- for the Blizzard UI), so there is no import.
FF.Init("Profiles", function()
    local NOTE_FORMAT = "# Name | Public note | Officer note"

    local function members()
        local list = {}
        for _, r in pairs(FF.GuildRoster()) do
            list[#list + 1] = r
        end
        table.sort(list, function(a, b)
            if a.rankIndex ~= b.rankIndex then
                return (a.rankIndex or 99) < (b.rankIndex or 99)
            end
            return a.name < b.name
        end)
        return list
    end

    local function export()
        if not IsInGuild() then
            FF.print("You're not in a guild.")
            return
        end
        FF.RequestGuildRoster()
        C_Timer.After(1, function() -- give the roster a moment to arrive
            local lines = { NOTE_FORMAT }
            for _, r in ipairs(members()) do
                lines[#lines + 1] = ("%s | %s | %s"):format(r.name, r.note or "", r.officerNote or "")
            end
            FF.ShowText(("Guild roster (%d members)"):format(#lines - 1), table.concat(lines, "\n"))
        end)
    end

    function M.Section(L)
        L:Header("Guild roster")
        L:Desc("Export every member as plain text: Name | Public note | Officer note. This game does not let addons change guild notes.")
        L:Buttons({
            { "Export roster", export },
        })
    end

    FF.Command("guild", function()
        export()
    end, "export the guild roster")
end)
