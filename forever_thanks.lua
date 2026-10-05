local addonName = ...
local VERSION = "0.1.0-beta.10"
local LOAD_SETTLE_SECONDS, AURA_QUIET_SECONDS, MAX_APPLICATION_AGE = 5, 1, 5
local DEFAULT_DELAY = 5
local POSITIVE_EMOTES = {"SALUTE", "BOW", "WAVE", "CHEER", "APPLAUD"}
local messages = {
    "Ayyy, that is nice! Appreciate you and your buffs!",
    "Much appreciated! You are a buffing legend.",
    "Ayy, thank you! That buff is going to help a lot.",
    "Thanks for the buff! I owe you one.",
    "Nice! Appreciate you looking out for me.",
    "Thank you kindly for the buff!",
    "You are awesome - thanks for the buff!",
    "Ayyy, appreciate the buffs! You rock.",
    "That buff is the bee's knees! Cheers, mate!",
    "You're a diamond geezer - cheers for the buff!",
    "That buff's proper mint. Nice one!",
    "Cheers, my china plate! Lovely buff.",
    "That's a bit of all right! Ta for the buff!",
    "Respect, fam - appreciate the buff!",
    "Big up yourself! Thanks for looking out.",
    "That buff's fire, no cap. Appreciate you!",
    "You're a real one. Thanks for the buff!",
    "Buff game on point! Much love!",
    "Now we're cooking! Thanks for the sweet buff!",
    "That's smooth, cool cat. Thanks for the buff!",
    "Right on! That buff's got me grooving.",
    "Groovy stuff! Appreciate the magical hookup!",
    "Cheers, legend! That buff's a beaut.",
    "Good on ya, mate! Thanks for the buff!",
    "Sweet as! Chur for the buff!",
    "Shot, bru! That's a lekker buff!",
    "That's class! Cheers a million for the buff!",
    "Beauty, eh? Thanks a bunch for the buff!",
}
local frame = CreateFrame("Frame")
local db, seen, ready = nil, {}, false
local pending, lastSent = {}, {}
local generation, lastMessage, lastAttempt = 0, nil, -math.huge
local lastEmote
local sent, failures, restricted = 0, 0, 0
local inWorld, settling, worldGeneration, lastAuraUpdate = false, true, 0, 0
local minimapButton

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

local function Trim(value)
    return (value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function NormalizeIgnoredBuff(value)
    value = Trim(value)
    if value == "" then return nil end
    local id = tonumber(value)
    if id then return "id:" .. math.floor(id), tostring(math.floor(id)) end
    return "name:" .. value:lower(), value
end

local function IsIgnoredBuff(spellId, spell)
    if not db or type(db.ignoredBuffs) ~= "table" then return false end
    if type(spellId) == "number" and db.ignoredBuffs["id:" .. spellId] then return true end
    if type(spell) == "string" and db.ignoredBuffs["name:" .. spell:lower()] then return true end
    return false
end

local function IsGroupCaster(guid)
    if not guid or type(UnitGUID) ~= "function" then return false end
    local partyCount = type(GetNumPartyMembers) == "function" and GetNumPartyMembers() or 0
    local raidCount = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 0
    local i
    for i = 1, partyCount do
        if UnitGUID("party" .. i) == guid then return true end
    end
    for i = 1, raidCount do
        if UnitGUID("raid" .. i) == guid then return true end
    end
    if partyCount == 0 and raidCount == 0 and type(GetNumGroupMembers) == "function" then
        local count = GetNumGroupMembers()
        local raid = type(IsInRaid) == "function" and IsInRaid()
        local prefix = raid and "raid" or "party"
        for i = 1, count do
            if UnitGUID(prefix .. i) == guid then return true end
        end
    end
    return false
end

local function ShouldSkip(guid)
    if not db.enabled then return true end
    if not db.groups and IsInGroup() then return true end
    if db.channel == "WHISPER" and db.skipGroupWhispers and IsGroupCaster(guid) then
        return true
    end
    return false
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

local function ChooseEmote()
    if db.emoteStyle ~= "RANDOM" then return "THANK" end
    local index
    repeat
        index = math.random(#POSITIVE_EMOTES)
    until #POSITIVE_EMOTES == 1 or POSITIVE_EMOTES[index] ~= lastEmote
    lastEmote = POSITIVE_EMOTES[index]
    return lastEmote
end

local function SendThanks(name, spell, emoteName)
    if db.channel == "EMOTE" then
        local emote = C_ChatInfo and C_ChatInfo.PerformEmote
        if type(emote) == "function" then
            -- Like Blizzard's chat UI, interpret the return as "restricted".
            local ok, restricted = pcall(emote, ChooseEmote(), emoteName)
            return ok and Readable(restricted) and not restricted
        end
        -- Older DoEmote return values differ; count only the API request.
        if type(DoEmote) == "function" then return pcall(DoEmote, ChooseEmote(), emoteName) end
        return false
    end
    local text = Message(spell)
    if #text > 255 then Say("Message too long; shorten /ft message."); return false end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then return false end
    return pcall(send, text, "WHISPER", nil, name)
end
local function Queue(guid, spell, spellId)
    local now = GetTime()
    if pending[guid] or (lastSent[guid] and now - lastSent[guid] < db.cooldown) then return end
    if IsIgnoredBuff(spellId, spell) then return end
    local ok, name, realm = pcall(UnitNameFromGUID, guid)
    if not ok or not Readable(name) or not Readable(realm)
        or type(name) ~= "string" or name == "" then return end
    -- Emotes need the plain name; whispers retain the realm-qualified address.
    -- Never inspect or change the player's selected target.
    local emoteName = name
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    local ticket = generation
    pending[guid] = true
    C_Timer.After(db.delay, function()
        if ticket ~= generation then return end
        pending[guid] = nil
        if not inWorld or settling or not ready or ShouldSkip(guid)
            or InCombatLockdown() then return end
        local time = GetTime()
        -- Cap bursts from multiple players as well as repeated buffs from one player.
        if time - lastAttempt < 3 then return end
        if lastSent[guid] and time - lastSent[guid] < db.cooldown then return end
        lastAttempt, lastSent[guid] = time, time
        local success = SendThanks(name, spell, emoteName)
        if success then
            sent = sent + 1
            if db.debug then Say(db.channel .. " requested for " .. name .. " (" .. spell .. ").") end
        else
            failures = failures + 1
            Say(db.channel .. " unavailable or blocked by the client. /ft status shows diagnostics.")
        end
    end)
end

local function Scan(baseline)
    if not db or not Available() then return end
    if not inWorld then ready = false; return end
    if InCombatLockdown() then ready = false; return end
    local mine = UnitGUID("player")
    if not Readable(mine) or type(mine) ~= "string" then ready = false; return end
    local current, candidates = {}, {}
    local now = GetTime()
    for index = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not Readable(aura) then
            restricted = restricted + 1; ready = false; CancelPending(); return
        end
        if not aura then break end
        local id, duration, expires, spellId = aura.auraInstanceID, aura.duration, aura.expirationTime, aura.spellId
        if not Readable(id) or not Readable(duration) or not Readable(expires) then
            restricted = restricted + 1; ready = false; CancelPending(); return
        end
        if type(id) == "number" then
            current[id] = type(expires) == "number" and expires or 0
            local fresh = seen[id] == nil or current[id] > seen[id] + 1
            -- Old auras can arrive even after the loading baseline. Their
            -- remaining lifetime is shorter than a newly applied/refreshed buff.
            local age = type(duration) == "number" and now - (current[id] - duration) or math.huge
            if ready and not settling and not baseline and db.enabled and fresh
                and type(duration) == "number" and duration > 120
                and current[id] > now and age >= -1 and age <= MAX_APPLICATION_AGE
                and (db.groups or not IsInGroup()) then
                local got, guid = pcall(C_UnitAuras.GetAuraCasterGUID, "player", id)
                if got and Readable(guid) and type(guid) == "string"
                    and guid:match("^Player%-") and guid ~= mine then
                    local spell = aura.name
                    if not Readable(spell) or type(spell) ~= "string" then spell = "the buff" end
                    if not IsIgnoredBuff(spellId, spell) then
                        candidates[#candidates + 1] = {guid, spell, spellId}
                    end
                end
            end
        end
    end
    seen, ready = current, not settling
    for _, candidate in ipairs(candidates) do Queue(candidate[1], candidate[2], candidate[3]) end
    for guid, time in pairs(lastSent) do
        if GetTime() - time > db.cooldown then lastSent[guid] = nil end
    end
end

local function Baseline()
    ready = false
    CancelPending()
    Scan(true)
end

local function EnterWorld()
    inWorld, settling = true, true
    worldGeneration = worldGeneration + 1
    local ticket, earliest = worldGeneration, GetTime() + LOAD_SETTLE_SECONDS
    lastAuraUpdate = GetTime()
    Baseline()
    local function FinishBaseline()
        if ticket ~= worldGeneration or not inWorld then return end
        local wait = math.max(earliest, lastAuraUpdate + AURA_QUIET_SECONDS) - GetTime()
        if wait > 0 then C_Timer.After(wait, FinishBaseline); return end
        settling = false
        -- Take one final silent snapshot, including auras with no UNIT_AURA yet.
        Baseline()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(LOAD_SETTLE_SECONDS, FinishBaseline)
    end
end

local function CreateMinimapButton()
    local minimap = Minimap or MinimapCluster
    if minimapButton or not minimap then return end
    minimapButton = CreateFrame("Button", "ForeverThanksMinimapButton", minimap)
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetPoint("TOPRIGHT", minimap, "TOPRIGHT", -4, -4)
    minimapButton:SetNormalTexture("Interface\\AddOns\\forever_thanks\\icon")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:SetScript("OnClick", function()
        if OpenForeverThanksOptions then OpenForeverThanksOptions() end
    end)
    minimapButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Thanks")
        GameTooltip:AddLine("Click to open options.", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton:Show()
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        if type(ForeverThanksDB) ~= "table" then ForeverThanksDB = {} end
        db = ForeverThanksDB
        if type(db.enabled) ~= "boolean" then db.enabled = true end
        -- Whisper is the default; preserve only an explicitly selected emote mode.
        if db.channel ~= "EMOTE" then db.channel = "WHISPER" end
        if type(db.groups) ~= "boolean" then db.groups = true end
        if type(db.skipGroupWhispers) ~= "boolean" then db.skipGroupWhispers = false end
        if db.emoteStyle ~= "RANDOM" and db.emoteStyle ~= "THANK" then db.emoteStyle = "THANK" end
        if type(db.delay) ~= "number" or db.delay ~= db.delay then db.delay = DEFAULT_DELAY end
        db.delay = math.max(0, math.min(60, db.delay))
        if type(db.ignoredBuffs) ~= "table" then db.ignoredBuffs = {} end
        CreateMinimapButton()
        if type(db.cooldown) ~= "number" or db.cooldown ~= db.cooldown then db.cooldown = 60 end
        db.cooldown = math.max(30, math.min(3600, db.cooldown))
        if type(db.message) ~= "string" or db.message == "" or #db.message > 200 then db.message = nil end
        if not Available() then Say("Required Forever APIs are missing; automatic thanks is inactive.") end
        Say(VERSION .. " loaded. /ft status or /ft help.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnterWorld()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Baseline()
    elseif event == "PLAYER_LEAVING_WORLD" then
        inWorld, settling, ready = false, true, false
        worldGeneration = worldGeneration + 1
        CancelPending()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ready = false
        CancelPending()
    elseif event == "UNIT_AURA" and Readable(arg) and arg == "player" then
        if not inWorld then return end
        lastAuraUpdate = GetTime()
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
    elseif cmd == "channel" or cmd == "mode" then
        local channel = rest:upper()
        if channel == "WHISPER" or channel == "EMOTE" then
            if db.channel ~= channel then CancelPending() end
            db.channel = channel
            Say("Thank-you mode: " .. channel:lower() .. ".")
        else Say("Use /ft mode whisper | emote (default: whisper).") end
    elseif cmd == "groups" and (rest == "on" or rest == "off") then
        db.groups = rest == "on"; Baseline()
        Say("Thanks while grouped: " .. (db.groups and "on" or "off"))
    elseif cmd == "groupwhisper" and (rest == "on" or rest == "off") then
        db.skipGroupWhispers = rest == "off"
        CancelPending()
        Say("Group whispers: " .. (db.skipGroupWhispers and "off" or "on"))
    elseif cmd == "emotes" and (rest == "random" or rest == "thank") then
        db.emoteStyle = rest == "random" and "RANDOM" or "THANK"
        CancelPending()
        Say("Emote style: " .. rest .. ".")
    elseif cmd == "delay" then
        local seconds = tonumber(rest)
        if seconds and seconds >= 0 and seconds <= 60 then
            db.delay = math.floor(seconds * 10 + 0.5) / 10
            CancelPending()
            Say("Reply delay: " .. db.delay .. "s.")
        else Say("Use /ft delay 0-60 (default 5 seconds).") end
    elseif cmd == "ignore" then
        local action, value = string.match(rest, "^(%S+)%s*(.-)%s*$")
        action = string.lower(action or "")
        if action == "add" then
            local key, label = NormalizeIgnoredBuff(value)
            if key then db.ignoredBuffs[key] = label; Say("Ignoring buff: " .. label .. ".")
            else Say("Use /ft ignore add <spell name or spell ID>.") end
        elseif action == "remove" then
            local key, label = NormalizeIgnoredBuff(value)
            if key and db.ignoredBuffs[key] then db.ignoredBuffs[key] = nil; Say("No longer ignoring: " .. label .. ".")
            else Say("That buff is not in the ignore list.") end
        elseif action == "clear" then
            db.ignoredBuffs = {}; Say("Buff ignore list cleared.")
        elseif action == "list" then
            local count = 0
            for _, label in pairs(db.ignoredBuffs) do count = count + 1; Say("Ignored: " .. label) end
            if count == 0 then Say("Buff ignore list is empty.") end
        else Say("Use /ft ignore add|remove|list|clear <spell name or spell ID>.") end
    elseif cmd == "gui" or cmd == "options" then
        if OpenForeverThanksOptions then OpenForeverThanksOptions() end
    elseif cmd == "cooldown" then
        local seconds = tonumber(rest)
        if seconds and seconds >= 30 and seconds <= 3600 then
            db.cooldown = math.floor(seconds); Say("Per-player cooldown: " .. db.cooldown .. "s.")
        else Say("Use /ft cooldown 30-3600 (default 60 seconds).") end
    elseif cmd == "message" then
        if rest == "random" or rest == "default" then db.message = nil; Say("28 rotating messages enabled.")
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
            .. "; " .. (settling and "settling after loading" or (ready and "watching" or "waiting for safe baseline")) .. ".")
        Say("Buff duration >120s; cooldown " .. db.cooldown .. "s; groups " .. (db.groups and "on" or "off") .. ".")
        Say("Channel: " .. db.channel:lower() .. ", delay " .. db.delay .. "s. This login: chat requests=" .. sent .. ", send errors=" .. failures .. ", restricted scans=" .. restricted .. ".")
        Say("Out of combat only. Existing buffs on login/zoning/combat exit are ignored.")
        Say("After loading: 5s minimum, then 1s without aura updates. Applications older than 5s are skipped.")
    else
        Say("/ft on | off | status | preview | debug | gui")
        Say("/ft mode whisper | emote (default: whisper)")
        Say("/ft groups on|off ; /ft groupwhisper on|off ; /ft cooldown 60 ; /ft delay 5")
        Say("/ft emotes thank|random ; /ft ignore add|remove|list|clear <name or ID>")
    end
end

local optionsFrame

local function OptionsLabel(parent, text, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then label:SetWidth(width) end
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label
end

local function OptionsButton(parent, text, x, y, width, height, handler)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetWidth(width or 100)
    button:SetHeight(height or 24)
    button:SetText(text)
    button:SetScript("OnClick", handler)
    return button
end

local function OptionsCheck(parent, text, x, y, handler)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetScript("OnClick", handler)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(text)
    return check
end

local function OptionsEdit(parent, x, y, width, height)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetWidth(width)
    edit:SetHeight(height or 24)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    return edit
end

local function SortedIgnoredBuffs()
    local values = {}
    for _, label in pairs(db.ignoredBuffs or {}) do values[#values + 1] = label end
    table.sort(values, function(a, b) return string.lower(a) < string.lower(b) end)
    return values
end

local function RefreshOptions()
    if not optionsFrame or not db then return end
    optionsFrame.enabled:SetChecked(db.enabled)
    optionsFrame.grouped:SetChecked(db.groups)
    optionsFrame.groupWhisper:SetChecked(db.skipGroupWhispers)
    optionsFrame.randomEmotes:SetChecked(db.emoteStyle == "RANDOM")
    optionsFrame.delay:SetText(tostring(db.delay))
    optionsFrame.cooldown:SetText(tostring(db.cooldown))
    optionsFrame.message:SetText(db.message or "")
    optionsFrame.modeText:SetText("Mode: " .. db.channel:lower())
    optionsFrame.status:SetText("Saved automatically. Current mode: " .. db.channel:lower()
        .. "; delay: " .. db.delay .. "s; cooldown: " .. db.cooldown .. "s.")
    local ignored = SortedIgnoredBuffs()
    optionsFrame.ignoreList:SetText(#ignored == 0 and "Ignored buffs: none" or "Ignored buffs: " .. table.concat(ignored, ", "))
end

local function CommitOptionsNumber(edit, minimum, maximum, field, label)
    local value = tonumber(edit:GetText())
    if not value or value < minimum or value > maximum then
        RefreshOptions()
        Say("Use " .. minimum .. "-" .. maximum .. " for " .. label .. ".")
        return
    end
    db[field] = field == "delay" and math.floor(value * 10 + 0.5) / 10 or math.floor(value)
    CancelPending()
    RefreshOptions()
end

local function CreateOptions()
    local f = CreateFrame("Frame", "ForeverThanksOptions", UIParent)
    f:SetWidth(500)
    f:SetHeight(610)
    f:SetPoint("CENTER")
    if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
    if f.EnableMouse then f:EnableMouse(true) end
    if f.SetMovable then f:SetMovable(true) end
    if type(f.SetBackdrop) == "function" then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 11, top = 11, bottom = 11},
        })
        if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0.95) end
    else
        local background = f:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
        background:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
        background:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
        f.background = background
    end
    f:SetScript("OnMouseDown", function() f:StartMoving() end)
    f:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -18)
    title:SetText("Forever Thanks")
    local version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -40)
    version:SetText(VERSION .. " options")

    OptionsButton(f, "X", 452, -18, 28, 24, function() f:Hide() end)
    f.status = OptionsLabel(f, "", 20, -62, 450)

    f.enabled = OptionsCheck(f, "Enable automatic thank-yous", 20, -92, function(button)
        db.enabled = button:GetChecked() and true or false
        CancelPending()
        if db.enabled then Baseline() end
        RefreshOptions()
    end)
    f.grouped = OptionsCheck(f, "Allow thank-yous while grouped", 20, -124, function(button)
        db.groups = button:GetChecked() and true or false
        Baseline()
        RefreshOptions()
    end)
    f.groupWhisper = OptionsCheck(f, "Do not whisper party/raid buff casters", 20, -156, function(button)
        db.skipGroupWhispers = button:GetChecked() and true or false
        CancelPending()
        RefreshOptions()
    end)
    f.randomEmotes = OptionsCheck(f, "Use random positive emotes instead of THANK", 20, -188, function(button)
        db.emoteStyle = button:GetChecked() and "RANDOM" or "THANK"
        CancelPending()
        RefreshOptions()
    end)

    f.modeText = OptionsLabel(f, "", 20, -225, 180)
    OptionsButton(f, "Whisper", 210, -218, 100, 24, function()
        if db.channel ~= "WHISPER" then CancelPending() end
        db.channel = "WHISPER"
        RefreshOptions()
    end)
    OptionsButton(f, "Emote", 320, -218, 100, 24, function()
        if db.channel ~= "EMOTE" then CancelPending() end
        db.channel = "EMOTE"
        RefreshOptions()
    end)

    OptionsLabel(f, "Reply delay (seconds)", 20, -266, 170)
    f.delay = OptionsEdit(f, 190, -258, 70, 24)
    f.delay:SetScript("OnEnterPressed", function(edit)
        CommitOptionsNumber(edit, 0, 60, "delay", "delay")
        edit:ClearFocus()
    end)
    OptionsLabel(f, "Cooldown per caster (seconds)", 280, -266, 170)
    f.cooldown = OptionsEdit(f, 450, -258, 35, 24)
    f.cooldown:SetScript("OnEnterPressed", function(edit)
        CommitOptionsNumber(edit, 30, 3600, "cooldown", "cooldown")
        edit:ClearFocus()
    end)

    OptionsLabel(f, "Custom whisper (leave blank for rotating replies; %s = buff name)", 20, -306, 450)
    f.message = OptionsEdit(f, 20, -330, 350, 24)
    OptionsButton(f, "Save message", 380, -330, 105, 24, function()
        local text = Trim(f.message:GetText())
        if text == "" or text:lower() == "random" or text:lower() == "default" then
            db.message = nil
        elseif #text <= 200 and not text:find("[\r\n|]") then
            db.message = text
        else
            Say("Message must be 1-200 characters and contain no line breaks or |.")
        end
        RefreshOptions()
    end)

    OptionsLabel(f, "Ignored buffs (enter a spell name or spell ID)", 20, -374, 400)
    f.ignoreInput = OptionsEdit(f, 20, -398, 230, 24)
    OptionsButton(f, "Add", 260, -398, 65, 24, function()
        local key, label = NormalizeIgnoredBuff(f.ignoreInput:GetText())
        if key then db.ignoredBuffs[key] = label; f.ignoreInput:SetText(""); CancelPending(); RefreshOptions()
        else Say("Enter a spell name or spell ID first.") end
    end)
    OptionsButton(f, "Remove", 330, -398, 70, 24, function()
        local key, label = NormalizeIgnoredBuff(f.ignoreInput:GetText())
        if key and db.ignoredBuffs[key] then db.ignoredBuffs[key] = nil; f.ignoreInput:SetText(""); CancelPending(); RefreshOptions()
        else Say("That buff is not in the ignore list.") end
    end)
    OptionsButton(f, "Clear", 405, -398, 80, 24, function()
        db.ignoredBuffs = {}
        CancelPending()
        RefreshOptions()
    end)
    f.ignoreList = OptionsLabel(f, "", 20, -432, 465)
    f.ignoreList:SetHeight(55)

    OptionsButton(f, "Reset defaults", 20, -520, 120, 26, function()
        db.enabled = true
        db.channel = "WHISPER"
        db.groups = true
        db.skipGroupWhispers = false
        db.emoteStyle = "THANK"
        db.delay = DEFAULT_DELAY
        db.cooldown = 60
        db.message = nil
        db.ignoredBuffs = {}
        CancelPending()
        Baseline()
        RefreshOptions()
    end)
    OptionsButton(f, "Close", 385, -520, 100, 26, function() f:Hide() end)
    f:SetScript("OnShow", RefreshOptions)
    return f
end

OpenForeverThanksOptions = function()
    if not db then return end
    if not optionsFrame then optionsFrame = CreateOptions() end
    RefreshOptions()
    optionsFrame:Show()
end
