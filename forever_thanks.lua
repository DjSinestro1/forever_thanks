local addonName = ...
local VERSION = "0.1.0.23"
local LOAD_SETTLE_SECONDS, AURA_QUIET_SECONDS, MAX_APPLICATION_AGE = 5, 1, 5
local DEFAULT_DELAY = 5
local MIN_COOLDOWN, MAX_COOLDOWN = 10, 3600
local MIN_BUFF_DURATION = 300
local MOVEMENT_WAIT_SECONDS = 10
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
local db, charDB, seen, ready = nil, nil, {}, false
local pending, lastSent = {}, {}
local emoteDrafts, emotePrompt, prepared = {}, nil, 0
local generation, lastMessage, lastAttempt = 0, nil, -math.huge
local lastEmote
local sent, failures, restricted = 0, 0, 0
local inWorld, settling, worldGeneration, lastAuraUpdate = false, true, 0, 0
local minimapButton, minimapLibrary, minimapLauncher, minimapVisible, positionMinimap
local lastDecision = "No reply considered yet"

local function Say(text)
    print("|cff66ddffforever_thanks:|r " .. text)
end

local function NoteDecision(text)
    if db and db.debug and text ~= lastDecision then Say(text) end
    lastDecision = text
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
    emoteDrafts = {}
    if emotePrompt then emotePrompt:Hide() end
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
    local function Matches(unit)
        local ok, member = pcall(UnitGUID, unit)
        -- Do not risk whispering a group member when membership is hidden.
        if not ok or not Readable(member) then return true end
        return member == guid
    end
    for i = 1, partyCount do
        if Matches("party" .. i) then return true end
    end
    for i = 1, raidCount do
        if Matches("raid" .. i) then return true end
    end
    if partyCount == 0 and raidCount == 0 and type(GetNumGroupMembers) == "function" then
        local count = GetNumGroupMembers()
        local raid = type(IsInRaid) == "function" and IsInRaid()
        local prefix = raid and "raid" or "party"
        for i = 1, count do
            if Matches(prefix .. i) then return true end
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

local function MessageSettings()
    return charDB.useCharacterMessage and charDB or db
end

local function SetMessageScope(character)
    charDB.useCharacterMessage = character
    CancelPending()
end

local function ExpandText(text, spell, casterName)
    text = text:gsub("{name}", function() return casterName end)
    return (text:gsub("%%s", function() return spell end))
end

local function ParseWhisperReplies(text)
    local replies, unique, lineNumber = {}, {}, 0
    if #text > 50000 then return nil, "Too much text. Use up to 100 replies, 200 bytes each.", 0, #text end
    for start, raw in (text .. "\n"):gmatch("()([^\n]*)\n") do
        lineNumber = lineNumber + 1
        local line = Trim(raw)
        if line ~= "" then
            local problem
            if #line > 200 then problem = "reply is longer than 200 bytes."
            elseif line:find("[%c|]") then problem = "remove control characters or |."
            elseif not unique[line] and #replies >= 100 then problem = "use no more than 100 different replies." end
            if problem then return nil, "Line " .. lineNumber .. ": " .. problem, start - 1, start - 1 + #raw end
            if not unique[line] then replies[#replies + 1] = line; unique[line] = true end
        end
    end
    return replies
end

local function NormalizeWhisperReplies(settings)
    local list = settings.whisperReplies
    if type(list) ~= "table" or #list == 0 or #list > 100 then list = nil end
    if list then
        local count = 0
        for key, text in pairs(list) do
            if type(key) ~= "number" or key < 1 or key > #list or key % 1 ~= 0
                or type(text) ~= "string" or #text > 200 or text:find("[%c|]") then list = nil; break end
            count = count + 1
        end
        if list and count ~= #list then list = nil end
    end
    local normalized = list and ParseWhisperReplies(table.concat(list, "\n"))
    settings.whisperReplies = normalized and #normalized > 0 and normalized or nil
    settings.useWhisperList = settings.useWhisperList == true and settings.whisperReplies ~= nil
end

local function SaveWhisperMessage(text)
    text = Trim(text)
    if text == "" or text:lower() == "random" or text:lower() == "default" then text = nil
    elseif #text > 200 or text:find("[%c|]") then
        Say("Message must be 1-200 bytes and contain no control characters or |.")
        return false
    end
    local settings = MessageSettings()
    settings.message, settings.useWhisperList = text, false
    CancelPending()
    Say(text and "Custom whisper saved. The saved reply list is inactive until saved in Edit replies."
        or "28 built-in rotating whispers enabled for the selected scope.")
    return true
end

local function WhisperReplySummary()
    local settings = MessageSettings()
    if settings.useWhisperList then return "Replies: Custom list (" .. #settings.whisperReplies .. ")" end
    return settings.message and "Replies: Single message" or "Replies: Built-in (28)"
end

local function NormalizeEmoteText(text)
    if type(text) ~= "string" then return nil, false end
    text = Trim(text)
    if text == "" or text:lower() == "default" then return nil, true end
    if text:sub(1, 1) == "/" then
        local command, body = text:match("^/(%a+)%s+(.+)$")
        command = command and command:lower()
        if command ~= "em" and command ~= "emote" and command ~= "e" and command ~= "me" then return nil, false end
        text = Trim(body)
    end
    if text == "" or #text > 200 or text:find("[%c|]") then return nil, false end
    return text, true
end

local function SaveEmoteText(text)
    local value, valid = NormalizeEmoteText(text)
    if not valid then
        Say("Enter custom emote text up to 200 bytes, with no controls or |. Do not enter other slash commands.")
        return false
    end
    MessageSettings().emoteText = value
    CancelPending()
    Say(value and "Custom emote saved. Buffs show a Prepare emote button; click it, then press Enter to send."
        or "Custom emote cleared; built-in Thank or random emotes enabled.")
    return true
end

local function Message(spell, casterName)
    local settings = MessageSettings()
    local pool = settings.useWhisperList and settings.whisperReplies or messages
    if not settings.useWhisperList and settings.message then
        lastMessage = settings.message
        return ExpandText(settings.message, spell, casterName)
    end
    local previous
    if #pool > 1 then
        for i, text in ipairs(pool) do if text == lastMessage then previous = i; break end end
    end
    local index = math.random(#pool - (previous and 1 or 0))
    if previous and index >= previous then index = index + 1 end
    lastMessage = pool[index]
    return ExpandText(lastMessage, spell, casterName)
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

local function StandingStill()
    if type(GetUnitSpeed) ~= "function" then return false, "movement API unavailable" end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if not ok or not Readable(speed) or type(speed) ~= "number" then return false, "movement information unreadable" end
    if speed ~= 0 then return false, "player moving" end
    if type(IsFalling) == "function" then
        local got, falling = pcall(IsFalling, "player")
        if not got or not Readable(falling) then return false, "falling information unreadable" end
        if falling then return false, "player falling" end
    end
    return true
end

local function ValidEmoteDraft(entry)
    return inWorld and ready and not settling and not ShouldSkip(entry.guid)
        and db.channel == "EMOTE" and MessageSettings().emoteText == entry.template
        and not IsIgnoredBuff(entry.spellId, entry.spell) and GetTime() < entry.expires
end

local RefreshEmotePrompt
local function RemoveEmoteDraft()
    local entry = table.remove(emoteDrafts, 1)
    if entry then pending[entry.guid] = nil end
    RefreshEmotePrompt()
end

local function PrepareEmoteDraft()
    -- Only called by the visible button. Enter in Blizzard's chat box sends it.
    local entry = emoteDrafts[1]
    if not entry or not ValidEmoteDraft(entry) then RefreshEmotePrompt(); return end
    local chat = ChatFrameUtil
    if not chat or type(chat.OpenChat) ~= "function" then
        Say("Chat is unavailable; the custom emote has not been sent.")
        return
    end
    if chat.GetActiveWindow and chat.GetActiveWindow() then
        Say("Finish or close your current chat message, then click Prepare emote.")
        return
    end
    local ok = pcall(chat.OpenChat, "/em " .. entry.text)
    if not ok then Say("Could not prepare the emote; nothing was sent."); return end
    lastSent[entry.guid] = GetTime()
    prepared = prepared + 1
    NoteDecision("Custom emote prepared for " .. entry.name .. "; press Enter to send")
    RemoveEmoteDraft()
end

RefreshEmotePrompt = function()
    for i = #emoteDrafts, 1, -1 do
        if not ValidEmoteDraft(emoteDrafts[i]) then
            pending[emoteDrafts[i].guid] = nil
            table.remove(emoteDrafts, i)
        end
    end
    if #emoteDrafts == 0 then
        if emotePrompt then emotePrompt:Hide() end
        return
    end
    if not emotePrompt then
        local f = CreateFrame("Frame", "ForeverThanksEmotePrompt", UIParent)
        emotePrompt = f
        f:SetWidth(420); f:SetHeight(176)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        f:SetFrameStrata("DIALOG")
        local background = f:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(f)
        background:SetColorTexture(0, 0, 0, 0.9)
        local function Label(font, y, height)
            local label = f:CreateFontString(nil, "OVERLAY", font)
            label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
            label:SetWidth(396); label:SetHeight(height)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("TOP")
            return label
        end
        f.title = Label("GameFontNormalLarge", -12, 20)
        f.preview = Label("GameFontHighlightSmall", -38, 68)
        Label("GameFontNormalSmall", -112, 16):SetText("Prepare fills chat. Press Enter to send, or Escape to cancel.")
        local function Button(text, x, width, action)
            local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            button:SetPoint("TOPLEFT", f, "TOPLEFT", x, -138)
            button:SetWidth(width); button:SetHeight(26)
            button:SetText(text)
            button:SetScript("OnClick", action)
            return button
        end
        f.prepare = Button("Prepare emote", 12, 150, PrepareEmoteDraft)
        f.skip = Button("Skip", 324, 84, RemoveEmoteDraft)
    end
    local entry = emoteDrafts[1]
    emotePrompt.title:SetText("Custom emote ready (" .. #emoteDrafts .. ")")
    emotePrompt.preview:SetText(entry.name .. " - " .. entry.spell .. "\n\n" .. entry.text)
    emotePrompt:Show()
end

local function QueueEmoteDraft(guid, spell, spellId, name)
    local template = MessageSettings().emoteText
    local text = ExpandText(template, spell, name)
    -- Leave space for /em in the normal chat edit box's 255-byte limit.
    if #text > 251 then
        pending[guid] = nil
        Say("Custom emote too long after inserting names; shorten your text.")
        return
    end
    if #emoteDrafts >= 5 then pending[guid] = nil; NoteDecision("Custom emote queue full"); return end
    emoteDrafts[#emoteDrafts + 1] = {guid = guid, name = name, spell = spell, spellId = spellId,
        template = template, text = text, expires = GetTime() + 60}
    NoteDecision("Custom emote ready for " .. name .. "; waiting for Prepare emote and Enter")
    RefreshEmotePrompt()
    C_Timer.After(60, RefreshEmotePrompt)
end

local function SendThanks(name, spell, emoteName)
    if db.channel == "EMOTE" then
        -- Never send custom text from a timer, even inside an instance.
        if MessageSettings().emoteText then return false end
        local emote = C_ChatInfo and C_ChatInfo.PerformEmote
        if type(emote) == "function" then
            -- Like Blizzard's chat UI, interpret the return as "restricted".
            local ok, restricted = pcall(emote, ChooseEmote(), emoteName, true)
            return ok and Readable(restricted) and not restricted
        end
        -- Older DoEmote return values differ; count only the API request.
        if type(DoEmote) == "function" then return pcall(DoEmote, ChooseEmote(), emoteName) end
        return false
    end
    local text = Message(spell, emoteName)
    if #text > 255 then Say("Reply too long after inserting names; shorten your custom text."); return false end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then return false end
    return pcall(send, text, "WHISPER", nil, name)
end
local function Queue(guid, spell, spellId)
    local now = GetTime()
    if pending[guid] then return end
    if lastSent[guid] and now - lastSent[guid] < db.cooldown then
        NoteDecision("Skipped " .. spell .. ": per-caster cooldown (" .. math.ceil(db.cooldown - (now - lastSent[guid])) .. "s left)")
        return
    end
    if IsIgnoredBuff(spellId, spell) then return end
    local ok, name, realm = pcall(UnitNameFromGUID, guid)
    if not ok or not Readable(name) or not Readable(realm)
        or type(name) ~= "string" or name == "" then return end
    -- Emotes need the plain name; whispers retain the realm-qualified address.
    -- Never inspect or change the player's selected target.
    local emoteName = name
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    local ticket = generation
    local deadline = now + db.delay + MOVEMENT_WAIT_SECONDS
    pending[guid] = true
    NoteDecision("Queued " .. db.channel:lower() .. " for " .. spell .. " after the reply delay")
    local function Attempt()
        if ticket ~= generation then return end
        if not inWorld or settling or not ready or ShouldSkip(guid) then
            pending[guid] = nil
            NoteDecision("Canceled reply: disabled, group filter, loading, or unreadable buff data")
            return
        end
        local time = GetTime()
        local animated = db.channel == "EMOTE" and db.emoteStyle == "RANDOM" and not MessageSettings().emoteText
        if time > deadline then
            pending[guid] = nil
            NoteDecision("Reply expired while waiting for movement or anti-spam spacing")
            return
        end
        if animated then
            local still, reason = StandingStill()
            if not still then
                if time < deadline then
                    NoteDecision("Waiting for random emote: " .. reason)
                    C_Timer.After(math.min(0.5, deadline - time), Attempt)
                else
                    pending[guid] = nil
                    NoteDecision("Random emote expired: " .. reason)
                end
                return
            end
        end
        -- Cap bursts from multiple players as well as repeated buffs from one player.
        if lastSent[guid] and time - lastSent[guid] < db.cooldown then
            pending[guid] = nil
            NoteDecision("Skipped reply: per-caster cooldown")
            return
        end
        if db.channel == "EMOTE" and MessageSettings().emoteText then
            QueueEmoteDraft(guid, spell, spellId, emoteName)
            return
        end
        local spacingWait = 3 - (time - lastAttempt)
        if spacingWait > 0 then
            if time + spacingWait <= deadline then
                NoteDecision("Waiting for anti-spam spacing: " .. spell)
                C_Timer.After(spacingWait, Attempt)
            else
                pending[guid] = nil
                NoteDecision("Reply expired while waiting for anti-spam spacing")
            end
            return
        end
        pending[guid] = nil
        lastAttempt, lastSent[guid] = time, time
        local success = SendThanks(name, spell, emoteName)
        if success then
            sent = sent + 1
            NoteDecision(db.channel:lower() .. " request sent for " .. spell)
            if db.debug then Say(db.channel .. " requested for " .. name .. " (" .. spell .. ").") end
        else
            failures = failures + 1
            NoteDecision(db.channel:lower() .. " request blocked, unavailable, or rejected by the client")
            Say(db.channel .. " unavailable or blocked by the client. /ft status shows diagnostics.")
        end
    end
    C_Timer.After(db.delay, Attempt)
end

local function Scan(baseline)
    if not db or not Available() then return end
    if not inWorld then ready = false; return end
    local gotMine, mine = pcall(UnitGUID, "player")
    if not gotMine or not Readable(mine) or type(mine) ~= "string" then
        ready = false; CancelPending(); return
    end
    local current, candidates = {}, {}
    local now = GetTime()
    for index = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok or not Readable(aura) then
            restricted = restricted + 1; ready = false; CancelPending(); return
        end
        if not aura then break end
        local id, duration, expires, spellId = aura.auraInstanceID, aura.duration, aura.expirationTime, aura.spellId
        if not Readable(spellId) then spellId = nil end
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
                and type(duration) == "number" and duration > MIN_BUFF_DURATION
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

local function MinimapTooltip(tooltip)
    tooltip:SetText("Forever Thanks")
    tooltip:AddLine("Click to open or close options.", 1, 1, 1)
    tooltip:AddLine("Drag to move around the minimap.", 1, 1, 1)
end

local function ToggleMinimapOptions()
    if OpenForeverThanksOptions then OpenForeverThanksOptions(true) end
end

local function RegisterSharedMinimapButton()
    if minimapLibrary then return true end
    if not LibStub or not Minimap then return false end
    local library = LibStub("LibDBIcon-1.0", true)
    local broker = LibStub("LibDataBroker-1.1", true)
    if not library or not broker then return false end
    local ok, button = pcall(function()
        local existing = library:GetMinimapButton("forever_thanks")
        if existing then return existing end
        minimapLauncher = minimapLauncher or broker:NewDataObject("forever_thanks", {
            type = "launcher", label = "Forever Thanks",
            icon = "Interface\\AddOns\\forever_thanks\\minimap.tga",
            OnClick = ToggleMinimapOptions, OnTooltipShow = MinimapTooltip,
        })
        -- Registration notifies button bags through LibDBIcon_IconCreated.
        library:Register("forever_thanks", minimapLauncher, db.minimap)
        return library:GetMinimapButton("forever_thanks")
    end)
    if not ok or not button then return false end
    if minimapButton and minimapButton ~= button then
        minimapButton:SetScript("OnUpdate", nil)
        minimapButton:Hide()
    end
    minimapButton, minimapLibrary, positionMinimap = button, library, nil
    minimapVisible = db.showMinimap
    return true
end

local function CreateMinimapButton()
    if not db or not db.showMinimap then return end
    local minimap = Minimap or MinimapCluster
    if minimapButton or not minimap then return end
    minimapButton = CreateFrame("Button", "ForeverThanksMinimapButton", minimap)
    local button = minimapButton
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(minimap:GetFrameLevel() + 10)
    minimapButton:SetNormalTexture("Interface\\AddOns\\forever_thanks\\minimap.tga")
    local icon = minimapButton:GetNormalTexture()
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
    icon:SetWidth(24)
    icon:SetHeight(24)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local function Position()
        -- A retired or collected fallback must not move a manager's button.
        if minimapButton ~= button or button:GetParent() ~= minimap then return end
        local angle = db.minimap.minimapPos * math.pi / 180
        local x, y = math.cos(angle), math.sin(angle)
        if GetMinimapShape and GetMinimapShape() == "SQUARE" then
            local scale = math.max(math.abs(x), math.abs(y))
            x, y = x / scale, y / scale
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", minimap, "CENTER",
            (minimap:GetWidth() / 2 + 8) * x, (minimap:GetHeight() / 2 + 8) * y)
    end
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function()
        if minimapButton ~= button or button:GetParent() ~= minimap then return end
        GameTooltip:Hide()
        button:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = minimap:GetCenter()
            if not cx or not cy then return end
            local scale = minimap:GetEffectiveScale()
            db.minimapAngle = math.atan2(y / scale - cy, x / scale - cx)
            db.minimap.minimapPos = (db.minimapAngle * 180 / math.pi) % 360
            Position()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function()
        button:SetScript("OnUpdate", nil)
    end)
    minimapButton:SetScript("OnClick", ToggleMinimapOptions)
    minimapButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button or this, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Position()
    minimapButton:Show()
    minimapVisible, positionMinimap = true, Position
    if minimap.HookScript then minimap:HookScript("OnSizeChanged", Position) end
    if hooksecurefunc and minimap.SetMaskTexture then hooksecurefunc(minimap, "SetMaskTexture", Position) end
end

local function UpdateMinimapVisibility()
    if not db then return end
    db.minimap.hide = not db.showMinimap
    if RegisterSharedMinimapButton() then
        if minimapVisible ~= db.showMinimap then
            db.minimap.hide = not db.showMinimap
            if db.minimap.hide then minimapLibrary:Hide("forever_thanks")
            elseif minimapButton:GetParent() == Minimap then minimapLibrary:Show("forever_thanks")
            else minimapButton:Show() end
            minimapVisible = db.showMinimap
        end
        -- Never refresh or reposition a button just because the player zoned.
        return
    end
    if db.showMinimap then
        CreateMinimapButton()
        if positionMinimap then positionMinimap() end
        if minimapButton and minimapVisible ~= true then minimapButton:Show() end
    elseif minimapButton then
        minimapButton:SetScript("OnUpdate", nil)
        if GameTooltip then GameTooltip:Hide() end
        minimapButton:Hide()
    end
    if minimapButton then minimapVisible = db.showMinimap end
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg ~= addonName then
        if db then UpdateMinimapVisibility() end
        return
    end
    if event == "ADDON_LOADED" and arg == addonName then
        if type(ForeverThanksDB) ~= "table" then ForeverThanksDB = {} end
        db = ForeverThanksDB
        if type(ForeverThanksCharDB) ~= "table" then ForeverThanksCharDB = {} end
        charDB = ForeverThanksCharDB
        if type(charDB.useCharacterMessage) ~= "boolean" then charDB.useCharacterMessage = false end
        if type(charDB.message) ~= "string" or charDB.message == "" or #charDB.message > 200 then charDB.message = nil end
        NormalizeWhisperReplies(charDB)
        charDB.emoteText = NormalizeEmoteText(charDB.emoteText)
        if type(db.enabled) ~= "boolean" then db.enabled = true end
        -- Whisper is the default; preserve only an explicitly selected emote mode.
        if db.channel == "CUSTOM_EMOTE" then db.channel = "EMOTE" end
        if db.channel ~= "EMOTE" then db.channel = "WHISPER" end
        db.emoteText = NormalizeEmoteText(db.emoteText)
        if type(db.groups) ~= "boolean" then db.groups = true end
        if type(db.skipGroupWhispers) ~= "boolean" then db.skipGroupWhispers = false end
        if db.emoteStyle ~= "RANDOM" and db.emoteStyle ~= "THANK" then db.emoteStyle = "THANK" end
        if type(db.delay) ~= "number" or db.delay ~= db.delay then db.delay = DEFAULT_DELAY end
        db.delay = math.max(0, math.min(60, db.delay))
        if type(db.ignoredBuffs) ~= "table" then db.ignoredBuffs = {} end
        if type(db.showMinimap) ~= "boolean" then db.showMinimap = true end
        if type(db.minimap) ~= "table" then db.minimap = {} end
        local pos = db.minimap.minimapPos
        if type(pos) ~= "number" or pos ~= pos or math.abs(pos) == math.huge then
            local angle = db.minimapAngle
            if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = math.pi * 1.25 end
            pos = angle * 180 / math.pi
        end
        db.minimap.minimapPos = pos % 360
        db.minimap.hide = not db.showMinimap
        UpdateMinimapVisibility()
        if type(db.cooldown) ~= "number" or db.cooldown ~= db.cooldown then db.cooldown = 60 end
        db.cooldown = math.max(MIN_COOLDOWN, math.min(MAX_COOLDOWN, db.cooldown))
        if type(db.message) ~= "string" or db.message == "" or #db.message > 200 then db.message = nil end
        NormalizeWhisperReplies(db)
        if not Available() then Say("Required Forever APIs are missing; automatic thanks is inactive.") end
        Say(VERSION .. " loaded. /ft status or /ft help.")
    elseif event == "PLAYER_LOGIN" then
        UpdateMinimapVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMinimapVisibility()
        EnterWorld()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        Scan(false)
    elseif event == "PLAYER_LEAVING_WORLD" then
        inWorld, settling, ready = false, true, false
        worldGeneration = worldGeneration + 1
        CancelPending()
    elseif event == "UNIT_AURA" and Readable(arg) and arg == "player" then
        if not inWorld then return end
        lastAuraUpdate = GetTime()
        Scan(false)
    end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
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
        -- Keep the previous command aliases working without a third reply mode.
        if channel == "CUSTOM" or channel == "CUSTOM_EMOTE" then channel = "EMOTE" end
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
            if key then db.ignoredBuffs[key] = label; CancelPending(); Say("Ignoring buff: " .. label .. ".")
            else Say("Use /ft ignore add <spell name or spell ID>.") end
        elseif action == "remove" then
            local key, label = NormalizeIgnoredBuff(value)
            if key and db.ignoredBuffs[key] then db.ignoredBuffs[key] = nil; CancelPending(); Say("No longer ignoring: " .. label .. ".")
            else Say("That buff is not in the ignore list.") end
        elseif action == "clear" then
            db.ignoredBuffs = {}; CancelPending(); Say("Buff ignore list cleared.")
        elseif action == "list" then
            local count = 0
            for _, label in pairs(db.ignoredBuffs) do count = count + 1; Say("Ignored: " .. label) end
            if count == 0 then Say("Buff ignore list is empty.") end
        else Say("Use /ft ignore add|remove|list|clear <spell name or spell ID>.") end
    elseif cmd == "gui" or cmd == "options" then
        if OpenForeverThanksOptions then OpenForeverThanksOptions() end
    elseif cmd == "minimap" and (rest == "on" or rest == "off") then
        db.showMinimap = rest == "on"
        UpdateMinimapVisibility()
        Say("Minimap button: " .. rest .. ". Settings remain available with /ft gui.")
    elseif cmd == "cooldown" then
        local seconds = tonumber(rest)
        if seconds and seconds >= MIN_COOLDOWN and seconds <= MAX_COOLDOWN then
            db.cooldown = math.floor(seconds); Say("Per-player cooldown: " .. db.cooldown .. "s.")
        else Say("Use /ft cooldown " .. MIN_COOLDOWN .. "-" .. MAX_COOLDOWN .. " (default 60 seconds).") end
    elseif cmd == "messagescope" and (rest == "global" or rest == "character") then
        SetMessageScope(rest == "character")
        Say("Custom whisper scope: " .. rest .. ". Existing messages in the other scope are preserved.")
    elseif cmd == "emotetext" then
        SaveEmoteText(rest)
    elseif cmd == "message" then
        SaveWhisperMessage(rest)
    elseif cmd == "preview" then
        local text
        if db.channel == "EMOTE" then
            local custom = MessageSettings().emoteText
            text = custom and ExpandText(custom, "Blessing of Might", "BuffFriend")
                or (db.emoteStyle == "RANDOM" and "Random animated emote" or "Thank emote")
        else
            text = Message("Blessing of Might", "BuffFriend")
        end
        Say("Preview only (not sent): " .. text)
    elseif cmd == "debug" then
        db.debug = not db.debug; Say("Debug: " .. (db.debug and "on" or "off"))
    elseif cmd == "status" or cmd == "" then
        Say(VERSION .. "; " .. (db.enabled and "enabled" or "disabled")
            .. "; APIs " .. (Available() and "available" or "missing")
            .. "; " .. (settling and "settling after loading" or (ready and "watching" or "waiting for safe baseline")) .. ".")
        Say("Buff duration >" .. MIN_BUFF_DURATION .. "s; cooldown " .. db.cooldown .. "s; groups " .. (db.groups and "on" or "off") .. ".")
        Say("Channel: " .. db.channel:lower() .. ", delay " .. db.delay .. "s; message scope: " .. (charDB.useCharacterMessage and "character" or "global") .. ". This login: chat requests=" .. sent .. ", send errors=" .. failures .. ", restricted scans=" .. restricted .. ".")
        Say("Combat replies allowed when client data is readable; random animations wait up to 10s for movement. Minimap: " .. (db.showMinimap and "on" or "off") .. ".")
        Say("Custom emotes require Prepare emote, then Enter; pending=" .. #emoteDrafts .. ", prepared=" .. prepared .. " (not confirmed sent).")
        Say(WhisperReplySummary())
        Say("After loading: 5s minimum, then 1s quiet. Applications older than 5s skipped. Last decision: " .. lastDecision .. ".")
    else
        Say("/ft on | off | status | preview | debug | gui")
        Say("/ft mode whisper | emote (default: whisper)")
        Say("/ft groups on|off ; /ft groupwhisper on|off ; /ft cooldown 60 ; /ft delay 5")
        Say("/ft emotes thank|random ; /ft ignore add|remove|list|clear <name or ID>")
        Say("/ft minimap on|off")
        Say("/ft messagescope global|character ; /ft message <text>|random")
        Say("/ft emotetext <text>|default ; custom text needs Prepare emote, then Enter; blank emotes are automatic")
    end
end

local optionsFrame, whisperEditor
local updatingOptions = false

local function UpdateOptionsStatus()
    optionsFrame.status:SetText("Saved automatically. Current mode: " .. db.channel:lower()
        .. "; delay: " .. db.delay .. "s; cooldown: " .. db.cooldown .. "s.")
end

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
    optionsFrame.showMinimap:SetChecked(db.showMinimap)
    optionsFrame.characterMessage:SetChecked(charDB.useCharacterMessage)
    updatingOptions = true
    optionsFrame.delay:SetText(tostring(db.delay))
    optionsFrame.cooldown:SetText(tostring(db.cooldown))
    updatingOptions = false
    local emoteMode = db.channel == "EMOTE"
    optionsFrame.message:SetText(emoteMode and (MessageSettings().emoteText or "") or (MessageSettings().message or ""))
    optionsFrame.messageLabel:SetText((emoteMode and "Custom emote" or "Custom whisper") .. " (" .. (charDB.useCharacterMessage and "this character" or "shared") .. "): {name} = caster, %s = buff")
    optionsFrame.messageHint:SetText(emoteMode and "Custom: click Prepare, then Enter. Blank: automatic emotes."
        or (MessageSettings().useWhisperList and "List active. Save message switches back to a single reply."
            or "Blank = rotating replies. Click Save message."))
    optionsFrame.replySummary:SetText(WhisperReplySummary())
    if emoteMode then optionsFrame.replySummary:Hide(); optionsFrame.editReplies:Hide()
    else optionsFrame.replySummary:Show(); optionsFrame.editReplies:Show() end
    if whisperEditor and (emoteMode or whisperEditor.settings ~= MessageSettings()) then whisperEditor:Hide() end
    optionsFrame.modeText:SetText("Mode: " .. db.channel:lower())
    UpdateOptionsStatus()
    local ignored = SortedIgnoredBuffs()
    optionsFrame.ignoreList:SetText(#ignored == 0 and "Ignored buffs: none" or "Ignored buffs: " .. table.concat(ignored, ", "))
end

local function CommitOptionsNumber(edit, minimum, maximum, field, label, finished)
    if updatingOptions then return end
    edit = edit or this
    local value = tonumber(edit:GetText())
    if not value or value ~= value or value < minimum or value > maximum then
        -- Allow incomplete numbers while typing; restore only this field on exit.
        if not finished then return end
        Say("Use " .. minimum .. "-" .. maximum .. " for " .. label .. ".")
    else
        value = field == "delay" and math.floor(value * 10 + 0.5) / 10 or math.floor(value)
        if db[field] ~= value then
            db[field] = value
            CancelPending()
        end
        UpdateOptionsStatus()
    end
    if finished then
        updatingOptions = true
        edit:SetText(tostring(db[field]))
        updatingOptions = false
    end
end

local function BindOptionsNumber(edit, minimum, maximum, field, label)
    edit:SetScript("OnTextChanged", function(self)
        CommitOptionsNumber(self, minimum, maximum, field, label, false)
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        CommitOptionsNumber(self, minimum, maximum, field, label, true)
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self = self or this
        CommitOptionsNumber(self, minimum, maximum, field, label, true)
        self:ClearFocus()
    end)
end

local function OpenWhisperRepliesEditor()
    if not whisperEditor then
        local f = CreateFrame("Frame", "ForeverThanksWhisperReplies", optionsFrame)
        whisperEditor = f
        f:SetWidth(500); f:SetHeight(430)
        f:SetPoint("CENTER", optionsFrame, "CENTER", 0, 0)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        local background = f:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(f)
        background:SetColorTexture(0.03, 0.03, 0.03, 1)
        f.title = OptionsLabel(f, "", 20, -20, 420)
        local hint = OptionsLabel(f, "One whisper per line. {name} = caster; %s = buff.\nUp to 100 replies, 200 bytes per reply.", 20, -48, 450)
        hint:SetHeight(36)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -96)
        scroll:SetWidth(438); scroll:SetHeight(230)
        local inputBackground = f:CreateTexture(nil, "BACKGROUND")
        inputBackground:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -96)
        inputBackground:SetWidth(438); inputBackground:SetHeight(230)
        inputBackground:SetColorTexture(0.12, 0.12, 0.12, 1)
        f.edit = CreateFrame("EditBox", nil, scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetAutoFocus(false)
        f.edit:SetFontObject("GameFontHighlight")
        f.edit:SetWidth(426); f.edit:SetHeight(230)
        f.edit:SetTextInsets(6, 6, 6, 6)
        f.edit:SetMaxLetters(0)
        scroll:SetScrollChild(f.edit)
        f.scroll = scroll
        f.validation = OptionsLabel(f, "", 20, -342, 450)
        f.validation:SetHeight(36)
        f.edit:SetScript("OnTextChanged", function()
            local list, problem = ParseWhisperReplies(f.edit:GetText())
            f.validation:SetText(problem or (#list .. " replies. Blank and duplicate lines are ignored."))
            f.validation:SetTextColor(problem and 1 or 0.4, problem and 0.3 or 1, problem and 0.3 or 0.4)
            scroll:UpdateScrollChildRect()
        end)
        f.edit:SetScript("OnCursorChanged", function(_, x, y, width, height)
            if not y then return end
            local offset = scroll:GetVerticalScroll()
            local top, bottom = -y, -y + height + 12
            if bottom > offset + scroll:GetHeight() then
                scroll:SetVerticalScroll(bottom - scroll:GetHeight())
            elseif top < offset then scroll:SetVerticalScroll(math.max(0, top)) end
        end)
        f.edit:SetScript("OnEscapePressed", function() f:Hide() end)
        local function Save(list)
            if f.settings ~= MessageSettings() or db.channel ~= "WHISPER" then
                Say("Whisper mode or reply scope changed. Reopen Edit replies."); f:Hide(); return
            end
            local settings = f.settings
            settings.whisperReplies = #list > 0 and list or nil
            settings.useWhisperList = #list > 0
            if #list == 0 then settings.message = nil end
            CancelPending()
            f:Hide()
            RefreshOptions()
            Say(#list > 0 and (#list .. " custom whispers saved. A random reply is used for each qualifying buff.")
                or "Built-in rotating whispers restored for the selected scope.")
        end
        f.save = OptionsButton(f, "Save", 20, -390, 90, 26, function()
            local list, problem, first, last = ParseWhisperReplies(f.edit:GetText())
            if not list then
                f.validation:SetText(problem)
                f.edit:SetFocus()
                f.edit:HighlightText(first, last)
                return
            end
            Save(list)
        end)
        f.cancel = OptionsButton(f, "Cancel", 390, -390, 90, 26, function() f:Hide() end)
        f.restore = OptionsButton(f, "Restore defaults", 125, -390, 150, 26, function() Save({}) end)
        OptionsButton(f, "X", 452, -16, 28, 24, function() f:Hide() end)
        f:SetScript("OnHide", function() f.edit:ClearFocus() end)
    end
    local settings = MessageSettings()
    whisperEditor.settings = settings
    whisperEditor.title:SetText("Whisper replies - " .. (charDB.useCharacterMessage and "this character" or "shared"))
    local initial = settings.whisperReplies or (settings.message and {settings.message}) or messages
    whisperEditor.edit:SetText(table.concat(initial, "\n"))
    whisperEditor.edit:SetCursorPosition(0)
    whisperEditor.scroll:SetVerticalScroll(0)
    whisperEditor:Show()
end

local function CreateOptions()
    local f = CreateFrame("Frame", "ForeverThanksOptions", UIParent)
    f:SetWidth(500)
    f:SetHeight(642)
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
    f.randomEmotes = OptionsCheck(f, "Use random animations when custom emote text is blank", 20, -188, function(button)
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
    BindOptionsNumber(f.delay, 0, 60, "delay", "delay")
    OptionsLabel(f, "Cooldown per caster (10-3600s)", 280, -266, 170)
    f.cooldown = OptionsEdit(f, 450, -258, 35, 24)
    BindOptionsNumber(f.cooldown, MIN_COOLDOWN, MAX_COOLDOWN, "cooldown", "cooldown")

    f.characterMessage = OptionsCheck(f, "Use character-specific reply text", 20, -302, function(button)
        button = button or this
        SetMessageScope(button:GetChecked() and true or false)
        RefreshOptions()
    end)
    f.messageLabel = OptionsLabel(f, "", 20, -338, 450)
    f.message = OptionsEdit(f, 20, -362, 350, 24)
    OptionsButton(f, "Save message", 380, -362, 105, 24, function()
        if db.channel == "EMOTE" then SaveEmoteText(f.message:GetText()); RefreshOptions(); return end
        SaveWhisperMessage(f.message:GetText())
        RefreshOptions()
    end)
    f.messageHint = OptionsLabel(f, "", 20, -391, 450)
    f.replySummary = OptionsLabel(f, "", 20, -420, 340)
    f.editReplies = OptionsButton(f, "Edit replies", 380, -412, 105, 24, OpenWhisperRepliesEditor)

    OptionsLabel(f, "Ignored buffs (enter a spell name or spell ID)", 20, -446, 400)
    f.ignoreInput = OptionsEdit(f, 20, -470, 230, 24)
    OptionsButton(f, "Add", 260, -470, 65, 24, function()
        local key, label = NormalizeIgnoredBuff(f.ignoreInput:GetText())
        if key then db.ignoredBuffs[key] = label; f.ignoreInput:SetText(""); CancelPending(); RefreshOptions()
        else Say("Enter a spell name or spell ID first.") end
    end)
    OptionsButton(f, "Remove", 330, -470, 70, 24, function()
        local key, label = NormalizeIgnoredBuff(f.ignoreInput:GetText())
        if key and db.ignoredBuffs[key] then db.ignoredBuffs[key] = nil; f.ignoreInput:SetText(""); CancelPending(); RefreshOptions()
        else Say("That buff is not in the ignore list.") end
    end)
    OptionsButton(f, "Clear", 405, -470, 80, 24, function()
        db.ignoredBuffs = {}
        CancelPending()
        RefreshOptions()
    end)
    f.ignoreList = OptionsLabel(f, "", 20, -504, 465)
    f.ignoreList:SetHeight(55)

    f.showMinimap = OptionsCheck(f, "Show minimap button", 20, -558, function(button)
        button = button or this
        db.showMinimap = button:GetChecked() and true or false
        UpdateMinimapVisibility()
        RefreshOptions()
    end)

    OptionsButton(f, "Reset defaults", 20, -592, 120, 26, function()
        if whisperEditor then whisperEditor:Hide() end
        db.enabled = true
        db.channel = "WHISPER"
        db.groups = true
        db.skipGroupWhispers = false
        db.emoteStyle = "THANK"
        db.delay = DEFAULT_DELAY
        db.cooldown = 60
        MessageSettings().message = nil
        MessageSettings().emoteText = nil
        MessageSettings().whisperReplies = nil
        MessageSettings().useWhisperList = false
        db.ignoredBuffs = {}
        db.showMinimap = true
        UpdateMinimapVisibility()
        CancelPending()
        Baseline()
        RefreshOptions()
    end)
    OptionsButton(f, "Close", 385, -592, 100, 26, function() f:Hide() end)
    f:SetScript("OnShow", RefreshOptions)
    f:SetScript("OnHide", function()
        if whisperEditor then whisperEditor:Hide() end
        CommitOptionsNumber(f.delay, 0, 60, "delay", "delay", true)
        CommitOptionsNumber(f.cooldown, MIN_COOLDOWN, MAX_COOLDOWN, "cooldown", "cooldown", true)
    end)
    return f
end

OpenForeverThanksOptions = function(toggle)
    if not db then return end
    if toggle and optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide(); return end
    if not optionsFrame then optionsFrame = CreateOptions() end
    RefreshOptions()
    optionsFrame:Show()
end
