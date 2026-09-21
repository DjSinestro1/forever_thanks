local addonName = ...
local VERSION = "0.1.0-beta.1"
local messages = {
    "Ayyy, that is nice! Appreciate you and your buffs!",
    "Much appreciated! You are a buffing legend.",
    "Ayy, thank you! That buff is going to help a lot.",
    "Thanks for the buff! I owe you one.",
    "Nice! Appreciate you looking out for me.",
    "Thank you kindly for the buff!",
    "You are awesome - thanks for the buff!",
    "Ayyy, appreciate the buffs! You rock.",
}
local frame = CreateFrame("Frame")
local db, seen, ready = nil, {}, false
local pending, lastSent = {}, {}
local generation, lastMessage, lastAttempt = 0, nil, -math.huge
local sent, failures, restricted = 0, 0, 0

local function Say(text)
    print("|cff66ddffforever_thanks:|r " .. text)
end

local function Readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Available()
    return C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function"
        and type(C_UnitAuras.GetAuraCasterGUID) == "function"
        and type(UnitNameFromGUID) == "function"
        and C_Timer and type(C_Timer.After) == "function"
        and C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function"
end

local function CancelPending()
    generation = generation + 1
    pending = {}
end

local function Message(spell)
    if db.message then
        return (db.message:gsub("%%s", function() return spell end))
    end
    local index = math.random(#messages - (lastMessage and 1 or 0))
    if lastMessage and index >= lastMessage then index = index + 1 end
    lastMessage = index
    return messages[index]
end

local function Queue(guid, spell)
    local now = GetTime()
    if pending[guid] or (lastSent[guid] and now - lastSent[guid] < db.cooldown) then return end
    local ok, name, realm = pcall(UnitNameFromGUID, guid)
    if not ok or not Readable(name) or not Readable(realm)
        or type(name) ~= "string" or name == "" then return end
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    local ticket = generation
    pending[guid] = true
    C_Timer.After(1, function()
        if ticket ~= generation then return end
        pending[guid] = nil
        if not db.enabled or InCombatLockdown() or (not db.groups and IsInGroup()) then return end
        local time = GetTime()
        -- Cap bursts from multiple players as well as repeated buffs from one player.
        if time - lastAttempt < 3 then return end
        if lastSent[guid] and time - lastSent[guid] < db.cooldown then return end
        local text = Message(spell)
        if #text > 255 then Say("Message too long; use /ft message with shorter text."); return end
        lastAttempt, lastSent[guid] = time, time
        local success = pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, name)
        if success then
            sent = sent + 1
            if db.debug then Say("Whisper requested for " .. name .. " (" .. spell .. ").") end
        else
            failures = failures + 1
            Say("Whisper blocked by the client. /ft status shows diagnostics.")
        end
    end)
end

local function Scan(baseline)
    if not db or not Available() then return end
    if InCombatLockdown() then ready = false; return end
    local mine = UnitGUID("player")
    if not Readable(mine) or type(mine) ~= "string" then ready = false; return end
    local current, candidates = {}, {}
    for index = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not Readable(aura) then
            restricted = restricted + 1; ready = false; CancelPending(); return
        end
        if not aura then break end
        local id, duration, expires = aura.auraInstanceID, aura.duration, aura.expirationTime
        if not Readable(id) or not Readable(duration) or not Readable(expires) then
            restricted = restricted + 1; ready = false; CancelPending(); return
        end
        if type(id) == "number" then
            current[id] = type(expires) == "number" and expires or 0
            local fresh = seen[id] == nil or current[id] > seen[id] + 1
            if ready and not baseline and db.enabled and fresh
                and type(duration) == "number" and duration > 120
                and (db.groups or not IsInGroup()) then
                local got, guid = pcall(C_UnitAuras.GetAuraCasterGUID, "player", id)
                if got and Readable(guid) and type(guid) == "string"
                    and guid:match("^Player%-") and guid ~= mine then
                    local spell = aura.name
                    if not Readable(spell) or type(spell) ~= "string" then spell = "the buff" end
                    candidates[#candidates + 1] = {guid, spell}
                end
            end
        end
    end
    seen, ready = current, true
    for _, candidate in ipairs(candidates) do Queue(candidate[1], candidate[2]) end
    for guid, time in pairs(lastSent) do
        if GetTime() - time > db.cooldown then lastSent[guid] = nil end
    end
end

local function Baseline()
    ready = false
    CancelPending()
    Scan(true)
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        if type(ForeverThanksDB) ~= "table" then ForeverThanksDB = {} end
        db = ForeverThanksDB
        if type(db.enabled) ~= "boolean" then db.enabled = true end
        if type(db.groups) ~= "boolean" then db.groups = true end
        if type(db.cooldown) ~= "number" or db.cooldown ~= db.cooldown then db.cooldown = 60 end
        db.cooldown = math.max(30, math.min(3600, db.cooldown))
        if type(db.message) ~= "string" or db.message == "" or #db.message > 200 then db.message = nil end
        if not Available() then Say("Required Forever APIs are missing; automatic thanks is inactive.") end
        Say(VERSION .. " loaded. /ft status or /ft help.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        Baseline()
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_REGEN_DISABLED" then
        ready = false
        CancelPending()
    elseif event == "UNIT_AURA" and Readable(arg) and arg == "player" then
        Scan(false)
    end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_AURA"}) do
    frame:RegisterEvent(event)
end

SLASH_FOREVERTHANKS1 = "/ft"
SLASH_FOREVERTHANKS2 = "/foreverthanks"
SLASH_FOREVERTHANKS3 = "/forever_thanks"
SlashCmdList.FOREVERTHANKS = function(input)
    if not db then return end
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"; Baseline()
        Say(db.enabled and "Enabled." or "Disabled.")
    elseif cmd == "groups" and (rest == "on" or rest == "off") then
        db.groups = rest == "on"; Baseline()
        Say("Thanks while grouped: " .. (db.groups and "on" or "off"))
    elseif cmd == "cooldown" then
        local seconds = tonumber(rest)
        if seconds and seconds >= 30 and seconds <= 3600 then
            db.cooldown = math.floor(seconds); Say("Per-player cooldown: " .. db.cooldown .. "s.")
        else Say("Use /ft cooldown 30-3600 (default 60 seconds).") end
    elseif cmd == "message" then
        if rest == "random" or rest == "default" then db.message = nil; Say("Eight rotating messages enabled.")
        elseif rest ~= "" and #rest <= 200 and not rest:find("[\r\n|]") then
            db.message = rest; Say("Custom message saved. %s inserts the buff name.")
        else Say("Use /ft message <text, up to 200 bytes> or /ft message random.") end
    elseif cmd == "preview" then
        Say("Preview only (not sent): " .. Message("Blessing of Might"))
    elseif cmd == "debug" then
        db.debug = not db.debug; Say("Debug: " .. (db.debug and "on" or "off"))
    elseif cmd == "status" or cmd == "" then
        Say(VERSION .. "; " .. (db.enabled and "enabled" or "disabled")
            .. "; APIs " .. (Available() and "available" or "missing")
            .. "; " .. (ready and "watching" or "waiting for safe baseline") .. ".")
        Say("Buff duration >120s; cooldown " .. db.cooldown .. "s; groups " .. (db.groups and "on" or "off") .. ".")
        Say("This login: whisper requests=" .. sent .. ", send errors=" .. failures .. ", restricted scans=" .. restricted .. ".")
        Say("Out of combat only. Existing buffs on login/zoning/combat exit are ignored.")
    else
        Say("/ft on | off | status | preview | debug")
        Say("/ft groups on|off ; /ft cooldown 60 ; /ft message <text>|random")
    end
end
