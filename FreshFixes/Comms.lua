local _, FF = ...

-- One prefix for every module. Wire format:
--   single:  <mod>~<payload>
--   chunked: <mod>#<id>:<i>/<n>~<piece>     (reassembled before delivery)
-- <mod> is a short module tag ("C" consumes, "D" cooldowns, "G" gear, ...).
local PREFIX = "FFIXES"
local MAX = 255
local readable = FF.readable

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local send = C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
local Result = Enum.SendAddonMessageResult

---------------------------------------------------------------------------
-- Outgoing queue: token bucket that stays under the client's per-prefix
-- throttle, so big payloads (nickname lists) trickle out instead of failing.
---------------------------------------------------------------------------
local queue, head, tail = {}, 1, 0
local tokens, CAPACITY, REGEN = 8, 8, 1 -- messages, messages per second
local lastRefill = GetTime()
local pumping = false

-- Midnight-style clients block addon messages during encounters
-- ("chat messaging lockdown"). Hold the queue and resume afterwards.
local function locked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

local hold
local function pump()
    pumping = false
    if locked() then
        hold(true) -- resumed when the lockdown ends
        return
    end
    hold(false)
    local now = GetTime()
    tokens = math.min(CAPACITY, tokens + (now - lastRefill) * REGEN)
    lastRefill = now
    while head <= tail and tokens >= 1 do
        local m = queue[head]
        local result = send(PREFIX, m[1], m[2], m[3])
        if Result and result == Result.AddonMessageThrottle then
            tokens = 0
            break
        end
        queue[head] = nil
        head = head + 1
        tokens = tokens - 1
    end
    if head > tail then
        queue, head, tail = {}, 1, 0
    elseif not pumping then
        pumping = true
        C_Timer.After(1 / REGEN, pump)
    end
end

local function enqueue(msg, channel, target)
    tail = tail + 1
    queue[tail] = { msg, channel, target }
    if not pumping then
        pump()
    end
end

local function resume()
    if head > tail then
        hold(false)
    elseif not pumping then
        pump()
    end
end
local function resumeSoon()
    C_Timer.After(0, resume)
end
local function resumeAfterBoss()
    C_Timer.After(1, resume)
end
-- these are only listened to while the queue is held
local held = false
function hold(on)
    if held ~= on then
        held = on
        FF.Listen("ADDON_RESTRICTION_STATE_CHANGED", resumeSoon, on)
        FF.Listen("PLAYER_REGEN_ENABLED", resume, on)
        FF.Listen("ENCOUNTER_END", resumeAfterBoss, on)
    end
end

local nextId = 0
-- channel: "GUILD", "RAID", "PARTY", "INSTANCE_CHAT", "WHISPER" (target) or "GROUP" (auto)
function FF.Send(mod, payload, channel, target)
    if channel == "GROUP" then
        channel = FF.GroupChannel()
        if not channel then
            return
        end
    end
    local single = mod .. "~" .. payload
    if #single <= MAX then
        enqueue(single, channel, target)
        return
    end
    nextId = nextId % 99 + 1
    local size = MAX - 16
    local n = math.ceil(#payload / size)
    for i = 1, n do
        enqueue(("%s#%d:%d/%d~%s"):format(mod, nextId, i, n, payload:sub((i - 1) * size + 1, i * size)),
            channel, target)
    end
end

function FF.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
local receivers = {}
local MAX_CHUNKS = 256 -- cap on pieces per message
local MAX_PENDING = 32 -- cap on in-flight chunk sets
local pendingCount = 0
local partial = {} -- [senderKey..id] = { n=, got=, parts={}, t= }

-- fn(payload, channel, senderDisplay, senderKey, sender) - sender as the game gave it
function FF.OnComm(mod, fn)
    receivers[mod] = fn
end

local function deliver(mod, payload, channel, display, key, sender)
    local fn = receivers[mod]
    if fn then
        fn(payload, channel, display, key, sender)
    end
end

-- Drop half-received payloads after a minute (ticks only while some exist)
local sweeper
local function startSweep()
    if sweeper then
        return
    end
    sweeper = C_Timer.NewTicker(60, function()
        local now = GetTime()
        for slot, p in pairs(partial) do
            if now - (p.t or 0) > 60 then
                partial[slot] = nil
                pendingCount = pendingCount - 1
            end
        end
        if not next(partial) then
            sweeper:Cancel()
            sweeper = nil
        end
    end)
end

local function receive(_, prefix, msg, channel, sender)
    -- every addon's messages arrive here: rule out other prefixes first
    if not readable(prefix) or prefix ~= PREFIX then
        return
    end
    if not (readable(msg) and readable(channel) and readable(sender)) then
        return
    end
    local display, key = FF.Identity(sender)
    if not key then
        return
    end
    key = FF.CanonicalKey(key) -- "First-Realm" -> "first surname-realm"
    local mod, payload = msg:match("^(%w+)~(.*)$")
    if mod then
        deliver(mod, payload, channel, display, key, sender)
        return
    end
    local id, i, n, piece
    mod, id, i, n, piece = msg:match("^(%w+)#(%d+):(%d+)/(%d+)~(.*)$")
    if not mod then
        return
    end
    i, n = tonumber(i), tonumber(n)
    -- reject malformed or oversized chunk sets
    if not i or not n or n < 1 or n > MAX_CHUNKS or i < 1 or i > n or #piece > 255 then
        return
    end
    local slot = key .. mod .. id
    local p = partial[slot]
    if not p or p.n ~= n then
        if not p then
            if pendingCount >= MAX_PENDING then
                return
            end
            pendingCount = pendingCount + 1
        end
        p = { n = n, got = 0, parts = {} }
        partial[slot] = p
        startSweep()
    end
    if not p.parts[i] then
        p.parts[i] = piece
        p.got = p.got + 1
    end
    p.t = GetTime()
    if p.got == n then
        partial[slot] = nil
        pendingCount = pendingCount - 1
        deliver(mod, table.concat(p.parts), channel, display, key, sender)
    end
end
FF.On("CHAT_MSG_ADDON", receive)
FF.On("CHAT_MSG_ADDON_LOGGED", receive)


