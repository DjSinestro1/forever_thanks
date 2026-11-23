-- Run from the repository root with Lua 5.1; no game or network access.
local tests, passed = {}, 0
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function harness(saved, character)
    saved = saved or {}
    local useDefaultDelay = saved.__defaultDelay
    saved.__defaultDelay = nil
    if not useDefaultDelay and saved.delay == nil then saved.delay = 1 end
    local h = {auras = {}, now = 100, tasks = {}, sent = {}, chatRequests = {}, emotes = {}, output = {}, combat = false, grouped = false}
    local env = setmetatable({ForeverThanksDB = saved, ForeverThanksCharDB = character or {}, SlashCmdList = {}}, {__index = _G})
    env.print = function(text) h.output[#h.output + 1] = text end
    env.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    env.CreateFrame = function(kind, name)
        local function widget()
            local f = {scripts = {}}
            setmetatable(f, {__index = function(_, key)
                if key:find("^Set") or key:find("^Register") then return function() end end
            end})
            function f:SetScript(event, fn) self.scripts[event] = fn end
            function f:SetText(text) self.text = text end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:CreateFontString() return widget() end
            function f:CreateTexture() return widget() end
            return f
        end
        local f = widget()
        if name == "ForeverThanksEmotePrompt" then h.prompt = f end
        if not kind or (kind == "Frame" and not name) then
            function f:SetScript(event, fn) if event == "OnEvent" then h.handler = fn end end
        end
        return f
    end
    env.GetTime = function() return h.now end
    env.InCombatLockdown = function() return h.combat end
    env.GetUnitSpeed = function(unit)
        eq(unit, "player")
        if h.speedError then error("restricted") end
        return h.speed or 0
    end
    env.IsFalling = function() return h.falling or false end
    env.IsInInstance = function() return not h.outdoors end
    env.ChatFrameUtil = {
        OpenChat = function(text)
            assert(h.click, "Opening chat requires a deliberate prompt click")
            if h.openError then error("chat unavailable") end
            h.draft, h.chatActive = text, true
        end,
        GetActiveWindow = function() return h.chatActive end,
    }
    env.IsInGroup = function() return h.grouped end
    env.GetNumPartyMembers = function() return h.party and 1 or 0 end
    env.GetNumRaidMembers = function() return h.raid and 1 or 0 end
    env.UnitGUID = function(unit)
        if unit == "player" then return "Player-Self" end
        if unit == "party1" and h.party then return h.party end
        if unit == "raid1" and h.raid then return h.raid end
        return nil
    end
    env.UnitName = function() error("Must not read the selected target") end
    env.TargetUnit = function() error("Must not change the selected target") end
    env.ClearTarget = function() error("Must not clear the selected target") end
    env.UnitNameFromGUID = function(guid)
        if h.noName then return nil end
        return h.casterName or guid:gsub("Player%-", ""), "Realm"
    end
    env.C_Timer = {After = function(delay, fn) h.tasks[#h.tasks + 1] = {h.now + delay, fn} end}
    env.C_ChatInfo = {SendChatMessage = function(text, channel, language, recipient)
        h.chatRequests[#h.chatRequests + 1] = channel
        assert(channel ~= "EMOTE", "Addon must never directly send custom emotes")
        if h.sendError then error("blocked") end
        h.sent[#h.sent + 1] = {text = text, channel = channel, recipient = recipient}
    end}
    env.C_ChatInfo.PerformEmote = function(token, target, suppressMoveError)
        h.emotes[#h.emotes + 1] = {token = token, target = target, suppressMoveError = suppressMoveError}
        if h.emoteError then error("blocked") end
        if h.emoteReturnNil then return nil end
        return h.emoteRejected or false
    end
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(_, i, filter)
            eq(filter, "HELPFUL")
            if h.readError then error("restricted") end
            return h.auras[i]
        end,
        GetAuraCasterGUID = function(_, id)
            for _, a in ipairs(h.auras) do if a.auraInstanceID == id then return a.guid end end
        end,
    }
    local chunk = assert(loadfile("forever_thanks.lua")); setfenv(chunk, env); chunk("forever_thanks")
    function h:event(event, arg) self.handler(nil, event, arg) end
    function h:cmd(command) env.SlashCmdList.FOREVERTHANKS(command) end
    function h:prepare()
        assert(self.prompt and self.prompt.shown, "No custom emote prompt")
        self.click = true
        self.prompt.prepare.scripts.OnClick()
        self.click = false
    end
    function h:enter()
        -- Simulate the user's native chat submission, not an addon API call.
        assert(self.chatActive and self.draft)
        self.sent[#self.sent + 1] = {text = self.draft:gsub("^/em ", ""), channel = "EMOTE", manual = true}
        self.chatActive, self.draft = false, nil
    end
    function h:advance(seconds)
        local finish = self.now + seconds
        while true do
            local nextIndex
            for i, item in ipairs(self.tasks) do
                if item[1] <= finish and (not nextIndex or item[1] < self.tasks[nextIndex][1]) then nextIndex = i end
            end
            if not nextIndex then break end
            local item = table.remove(self.tasks, nextIndex)
            self.now = item[1]; item[2]()
        end
        self.now = finish
    end
    function h:add(id, duration, guid, name, spellId)
        local aura = {auraInstanceID = id, duration = duration, expirationTime = self.now + duration,
            spellId = spellId, guid = guid or "Player-BuffFriend", name = name or "Blessing of Might", sourceUnit = nil}
        self.auras[#self.auras + 1] = aura
        return aura
    end
    function h:change() self:event("UNIT_AURA", "player") end
    h:event("ADDON_LOADED", "forever_thanks")
    h.env = env
    return h
end
local function active(saved, character)
    local h = harness(saved, character); h:event("PLAYER_ENTERING_WORLD"); h:advance(6); return h
end

test("nil sourceUnit resolves caster and delayed realm-qualified whisper", function()
    local h = active({channel = "WHISPER"}); h:add(1, 3600); h:change(); eq(#h.sent, 0)
    h:advance(1); eq(#h.sent, 1); eq(h.sent[1].recipient, "BuffFriend-Realm"); eq(h.sent[1].channel, "WHISPER")
end)
test("strict five-minute boundary in both modes; short, permanent, missing duration ignored", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        for _, duration in ipairs({0, 15, 119, 120, 121, 180, 299, 300, 301}) do
            local h = active({channel = mode}); h:add(1, duration); h:change(); h:advance(1)
            eq(#h.sent + #h.emotes, duration > 300 and 1 or 0)
        end
        local h = active({channel = mode}); h:add(1, 301).duration = nil
        h:change(); h:advance(1); eq(#h.sent + #h.emotes, 0)
    end
end)

test("talented three-minute Battle Shout never thanks the warrior on repeated refreshes", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        local h = active({channel = mode})
        local buff = h:add(1, 180, "Player-Warrior", "Battle Shout")
        for i = 1, 5 do
            buff.expirationTime = h.now + 180; h:change(); h:advance(180)
        end
        eq(#h.sent + #h.emotes, 0)
    end
end)
test("self, NPC, unknown GUID excluded", function()
    for _, guid in ipairs({"Player-Self", "Creature-123", ""}) do
        local h = active(); h:add(1, 3600, guid); h:change(); h:advance(1); eq(#h.sent, 0)
    end
end)
test("existing login buffs never thanked", function()
    local h = harness(); h:add(1, 3600); h:event("PLAYER_ENTERING_WORLD"); h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("duplicates and multiple buffs from one caster coalesce", function()
    local h = active(); h:add(1, 3600); h:add(2, 1800); h:change(); h:change(); h:advance(1); eq(#h.sent, 1)
    h:change(); h:advance(70); eq(#h.sent, 1)
end)
test("per-caster cooldown then refresh allowed; random message changes", function()
    local h = active(); local a = h:add(1, 3600); h:change(); h:advance(1)
    h:advance(10); a.expirationTime = a.expirationTime + 10; h:change(); h:advance(1); eq(#h.sent, 1)
    h:advance(60); a.expirationTime = a.expirationTime + 60; h:change(); h:advance(1); eq(#h.sent, 2)
    assert(h.sent[1].text ~= h.sent[2].text)
end)
test("global burst guard across different casters", function()
    local h = active(); h:add(1, 3600, "Player-A"); h:add(2, 3600, "Player-B"); h:change(); h:advance(1); eq(#h.sent, 1)
    h:advance(2.9); eq(#h.sent, 1)
    h:advance(0.1); eq(#h.sent, 2)
end)

test("Fortitude followed by Wisdom queues both default THANK replies without a target", function()
    local h = active({channel = "EMOTE", emoteStyle = "THANK"})
    h:add(1, 3600, "Player-Priest", "Power Word: Fortitude")
    h:change(); h:advance(0.5)
    h:add(2, 3600, "Player-Paladin", "Blessing of Wisdom")
    h:change(); h:advance(0.5)
    eq(#h.emotes, 1); eq(h.emotes[1].target, "Priest"); eq(h.emotes[1].token, "THANK")
    h:advance(0.5); eq(#h.emotes, 1)
    h:cmd("status"); assert(h.output[#h.output]:find("anti-spam spacing: Blessing of Wisdom", 1, true))
    h:advance(2.5)
    eq(#h.emotes, 2); eq(h.emotes[2].target, "Paladin"); eq(h.emotes[2].token, "THANK")
    eq(#h.sent, 0)
end)

test("anti-spam waiting coalesces caster buffs and is canceled by disable or zoning", function()
    for _, cancel in ipairs({"off", "zone", "none"}) do
        local h = active({channel = "EMOTE"})
        h:add(1, 3600, "Player-Priest"); h:add(2, 3600, "Player-Paladin")
        h:change(); h:advance(1); eq(#h.emotes, 1)
        h:add(3, 3600, "Player-Paladin"); h:change()
        if cancel == "off" then h:cmd("off")
        elseif cancel == "zone" then h:event("PLAYER_LEAVING_WORLD") end
        h:advance(10)
        eq(#h.emotes, cancel == "none" and 2 or 1)
    end
end)

test("large buff bursts stay spaced, expire old replies, and leave no retry timers", function()
    local h = active({channel = "EMOTE"})
    for i = 1, 8 do h:add(i, 3600, "Player-Caster" .. i) end
    h:change(); h:advance(30)
    eq(#h.emotes, 4); eq(#h.tasks, 0)
end)
test("both modes preserve queued replies on combat entry and thank new combat buffs", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        local h = active({channel = mode})
        h:add(1, 3600); h:change(); h.combat = true; h:event("PLAYER_REGEN_DISABLED")
        h:advance(1); eq(#h.sent + #h.emotes, 1)
        h:advance(4); h:add(2, 3600, "Player-Other"); h:change()
        h:advance(1); eq(#h.sent + #h.emotes, 2)
        h.combat = false; h:event("PLAYER_REGEN_ENABLED"); h:change(); h:advance(1)
        eq(#h.sent + #h.emotes, 2)
    end
end)

test("combat exit does not discard a pending reply", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        local h = active({channel = mode})
        h.combat = true; h:event("PLAYER_REGEN_DISABLED")
        h:add(1, 3600); h:change(); h.combat = false; h:event("PLAYER_REGEN_ENABLED")
        h:advance(1); eq(#h.sent + #h.emotes, 1)
    end
end)

test("unreadable combat data cancels pending and is silently baselined when readable", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        local h = active({channel = mode})
        h:add(1, 3600); h:change(); h.combat = true; h.readError = true
        h:event("PLAYER_REGEN_DISABLED"); h:advance(1); eq(#h.sent + #h.emotes, 0)
        h:add(2, 3600); h:change(); h.combat = false; h.readError = false
        h:event("PLAYER_REGEN_ENABLED"); h:advance(1); eq(#h.sent + #h.emotes, 0)
        h:add(3, 3600); h:change(); h:advance(1); eq(#h.sent + #h.emotes, 1)
    end
end)
test("zoning cancels pending", function()
    local h = active(); h:add(1, 3600); h:change(); h:event("PLAYER_LEAVING_WORLD")
    h:event("PLAYER_ENTERING_WORLD"); h:advance(1); eq(#h.sent, 0)
end)
test("disable cancels pending; enable does not thank old buffs", function()
    local h = active(); h:add(1, 3600); h:change(); h:cmd("off"); h:advance(1); eq(#h.sent, 0)
    h:cmd("on"); h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("group setting", function()
    local h = active(); h.grouped = true; h:cmd("groups off"); h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h:cmd("groups on"); h:add(2, 3600); h:change(); h:advance(1); eq(#h.sent, 1)
end)
test("secret fields and thrown reads fail closed", function()
    for _, field in ipairs({"duration", "expirationTime", "auraInstanceID", "guid"}) do
        local h = active(); h:add(1, 3600)[field] = {secret = true}; h:change(); h:advance(1); eq(#h.sent, 0)
    end
    local h = active(); h.readError = true; h:change(); h.readError = false
    h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("unknown caster names skipped", function()
    local h = active(); h.noName = true; h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("custom message literal percent handling; preview never sends", function()
    local h = active(); h:cmd("message Thanks for %s! 100% appreciated."); h:cmd("preview"); eq(#h.sent, 0)
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "Thanks for Blessing of Might! 100% appreciated.")
    h:cmd("message random"); eq(h.env.ForeverThanksDB.message, nil)
end)

test("custom whispers expand caster name and buff while retaining the realm-qualified recipient", function()
    local h = active()
    h.casterName = "Steamboots"
    h:cmd("message Thank you {name} for the %s!")
    h:add(1, 3600); h:change(); h.casterName = "Someone Else"; h:advance(1)
    eq(h.sent[1].text, "Thank you Steamboots for the Blessing of Might!")
    eq(h.sent[1].recipient, "Steamboots-Realm")
end)

test("caster and buff placeholders support repeats, literal percents, preview, and saved custom messages", function()
    local saved = {message = "{name}, thanks for %s! {name}: %s, 100% appreciated."}
    local h = active(saved); h.casterName = "Buff Friend"
    h:cmd("preview"); eq(#h.sent, 0)
    assert(h.output[#h.output]:find("BuffFriend", 1, true))
    assert(not h.output[#h.output]:find("{name}", 1, true))
    h:add(1, 3600, nil, "Power 100%"); h:change(); h:advance(1)
    eq(h.sent[1].text, "Buff Friend, thanks for Power 100%! Buff Friend: Power 100%, 100% appreciated.")
    h = active(saved); h.casterName = "Buff Friend"
    h:add(1, 3600); h:change(); h:advance(1)
    assert(h.sent[1].text:find("Buff Friend, thanks for Blessing of Might!", 1, true))
end)
test("saved settings honored and corrupt defaults normalized", function()
    local h = active({enabled = false, cooldown = 100, groups = false}); h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h = active({cooldown = "bad", message = 7}); eq(h.env.ForeverThanksDB.cooldown, 60); eq(h.env.ForeverThanksDB.message, nil)
    h:cmd("cooldown 5"); eq(h.env.ForeverThanksDB.cooldown, 60)
    h:cmd("cooldown 90"); eq(h.env.ForeverThanksDB.cooldown, 90)
end)

test("ten-second cooldown is accepted by command, persists on reload, and keeps its bounds", function()
    local h = active()
    h:cmd("cooldown 10"); eq(h.env.ForeverThanksDB.cooldown, 10)
    h = active(h.env.ForeverThanksDB); eq(h.env.ForeverThanksDB.cooldown, 10)
    for _, invalid in ipairs({"0", "-1", "5", "9", "9.9", "3601", "bad"}) do
        h:cmd("cooldown " .. invalid); eq(h.env.ForeverThanksDB.cooldown, 10)
    end
    h:cmd("cooldown 3600"); eq(h.env.ForeverThanksDB.cooldown, 3600)
    h = active({cooldown = 5}); eq(h.env.ForeverThanksDB.cooldown, 10)
end)

test("ten-second cooldown prevents early repeats and permits both modes at the boundary", function()
    for _, mode in ipairs({"WHISPER", "EMOTE"}) do
        local h = active({cooldown = 10, delay = 0, channel = mode})
        h:add(1, 3600); h:change(); h:advance(0)
        eq(#h.sent + #h.emotes, 1)
        h:advance(9); h:add(2, 3600); h:change(); h:advance(0)
        eq(#h.sent + #h.emotes, 1)
        h:advance(1); h:add(3, 3600); h:change(); h:advance(0)
        eq(#h.sent + #h.emotes, 2)
    end
end)

test("existing shared messages remain the default and character scope is opt-in", function()
    local shared = {message = "Shared thanks, {name}!"}
    local h = active(shared)
    eq(h.env.ForeverThanksCharDB.useCharacterMessage, false)
    eq(h.env.ForeverThanksCharDB.message, nil)
    h:add(1, 3600); h:change(); h:advance(1)
    eq(h.sent[1].text, "Shared thanks, BuffFriend!")
    eq(shared.message, "Shared thanks, {name}!")
end)

test("roleplay alts retain independent messages, shared fallback selection, and placeholders", function()
    local shared = {message = "Shared thanks!"}
    local mage, rogue = {}, {}
    local h = active(shared, mage)
    h:cmd("messagescope character"); h:cmd("message My arcane thanks, {name}, for %s!")
    eq(shared.message, "Shared thanks!")
    h = active(shared, rogue)
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "Shared thanks!")
    h:cmd("messagescope character"); h:cmd("message You have my gratitude, {name}.")
    h = active(shared, mage)
    h:add(1, 3600); h:change(); h:advance(1)
    eq(h.sent[1].text, "My arcane thanks, BuffFriend, for Blessing of Might!")
    h:cmd("messagescope global"); h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
    eq(h.sent[2].text, "Shared thanks!"); eq(mage.message, "My arcane thanks, {name}, for %s!")
    h:cmd("messagescope character")
    h = active(shared, rogue)
    h:add(1, 3600); h:change(); h:advance(1)
    eq(h.sent[1].text, "You have my gratitude, BuffFriend.")
end)

test("message edits and random replies affect only the selected scope", function()
    local shared = {message = "Shared thanks!"}
    local character = {useCharacterMessage = true, message = "Character thanks!"}
    local h = active(shared, character)
    h:cmd("message random"); eq(character.message, nil); eq(shared.message, "Shared thanks!")
    h:add(1, 3600); h:change(); h:advance(1); assert(h.sent[1].text ~= "Shared thanks!")
    h:cmd("message Character restored."); h:cmd("messagescope global")
    h:cmd("message Shared revised."); eq(shared.message, "Shared revised.")
    eq(character.message, "Character restored.")
    h:cmd("message random"); eq(shared.message, nil); eq(character.message, "Character restored.")
end)

test("changing scope cancels pending replies and preview uses the selected message", function()
    local shared = {message = "Shared thanks!"}
    local character = {message = "My thanks, {name}!"}
    local h = active(shared, character)
    h:add(1, 3600); h:change(); h:cmd("messagescope character"); h:advance(1)
    eq(#h.sent, 0)
    h:cmd("preview"); eq(#h.sent, 0)
    assert(h.output[#h.output]:find("My thanks, BuffFriend!", 1, true))
    h:add(2, 3600); h:change(); h:advance(1)
    eq(h.sent[1].text, "My thanks, BuffFriend!")
end)

test("invalid character settings are normalized and custom message validation is unchanged", function()
    local shared = {message = "Shared thanks!"}
    local h = active(shared, "bad")
    eq(h.env.ForeverThanksCharDB.useCharacterMessage, false)
    h = active(shared, {useCharacterMessage = true, message = 42})
    eq(h.env.ForeverThanksCharDB.message, nil)
    h:cmd("message A valid character reply.")
    for _, invalid in ipairs({string.rep("x", 201), "bad|reply", "bad\nreply"}) do
        h:cmd("message " .. invalid)
        eq(h.env.ForeverThanksCharDB.message, "A valid character reply.")
    end
    eq(shared.message, "Shared thanks!")
end)
test("saved whisper lists send one automatic realm-qualified whisper with placeholders and no repeat", function()
    local h = active({useWhisperList = true, whisperReplies = {"Cheers {name} for %s!", "Thanks {name}!"}, message = "Inactive single reply"})
    for i = 1, 12 do
        h:add(i, 3600, "Player-Paladin", "Blessing of Wisdom"); h:change(); h:advance(1)
        eq(#h.sent, i); eq(h.sent[i].channel, "WHISPER"); eq(h.sent[i].recipient, "Paladin-Realm")
        assert(h.sent[i].text == "Cheers Paladin for Blessing of Wisdom!" or h.sent[i].text == "Thanks Paladin!")
        if i > 1 then assert(h.sent[i].text ~= h.sent[i-1].text) end
        h:advance(61)
    end
    eq(#h.emotes, 0); eq(h.draft, nil)
end)

test("whisper lists trim and deduplicate saved replies and support a one-entry list", function()
    local saved = {useWhisperList = true, whisperReplies = {"  Thanks {name}!  ", "Thanks {name}!", "Cheers!"}}
    local h = active(saved)
    eq(#saved.whisperReplies, 2); eq(saved.whisperReplies[1], "Thanks {name}!")
    h = active({useWhisperList = true, whisperReplies = {"Thanks for %s, {name}. 100% appreciated."}})
    h:add(1, 3600, nil, "Power 100%"); h:change(); h:advance(1)
    eq(h.sent[1].text, "Thanks for Power 100%, BuffFriend. 100% appreciated.")
    h:advance(61); h:add(2, 3600); h:change(); h:advance(1); eq(#h.sent, 2)
end)

test("whisper lists persist through reload and shared and character lists stay independent", function()
    local shared = {useWhisperList = true, whisperReplies = {"Shared {name}!"}, message = "Old shared single"}
    local mage = {useCharacterMessage = true, useWhisperList = true, whisperReplies = {"My arcane thanks, {name}!"}}
    local h = active(shared, mage)
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "My arcane thanks, BuffFriend!")
    h = active(shared, mage)
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "My arcane thanks, BuffFriend!")
    h:cmd("messagescope global"); h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
    eq(h.sent[2].text, "Shared BuffFriend!")
    eq(mage.whisperReplies[1], "My arcane thanks, {name}!"); eq(shared.message, "Old shared single")
    h = active(shared, {})
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "Shared BuffFriend!")
end)

test("single-message commands deactivate a list without deleting it and random restores defaults", function()
    local shared = {useWhisperList = true, whisperReplies = {"Saved list reply"}}
    local h = active(shared)
    h:cmd("message One reply, {name}!")
    eq(shared.useWhisperList, false); eq(shared.whisperReplies[1], "Saved list reply")
    h:add(1, 3600); h:change(); h:advance(1); eq(h.sent[1].text, "One reply, BuffFriend!")
    h:cmd("message random"); eq(shared.useWhisperList, false); eq(shared.message, nil)
    h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
    assert(h.sent[2].text ~= "Saved list reply")
end)

test("invalid saved whisper lists fail safely without replacing existing single messages", function()
    for _, invalid in ipairs({"bad", {}, {42}, {"bad|text"}, {string.rep("x", 201)}, {"bad\ntext"}, {[1]="good", [3]="gap", [4]="last"}}) do
        local saved = {useWhisperList = true, whisperReplies = invalid, message = "Safe fallback"}
        local h = active(saved)
        h:add(1, 3600); h:change(); h:advance(1)
        eq(h.sent[1].text, "Safe fallback")
        eq(saved.message, "Safe fallback")
    end
end)

test("whisper lists preserve disable, group filters, cooldown, and expanded-length protection", function()
    local h = active({useWhisperList = true, whisperReplies = {"Thanks {name}!"}, skipGroupWhispers = true})
    h.party = "Player-BuffFriend"; h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h.party = nil; h:add(2, 3600); h:change(); h:advance(1); eq(#h.sent, 1)
    h:add(3, 3600); h:change(); h:advance(1); eq(#h.sent, 1)
    h:cmd("off"); h:add(4, 3600, "Player-Other"); h:change(); h:advance(1); eq(#h.sent, 1)
    h = active({useWhisperList = true, whisperReplies = {string.rep("%s", 100)}})
    h:add(1, 3600); h:change(); h:advance(1); eq(#h.chatRequests, 0)
end)

test("whisper lists never change built-in or custom emote replies", function()
    local saved = {channel = "EMOTE", useWhisperList = true, whisperReplies = {"Whisper only"}}
    local h = active(saved); h:add(1, 3600); h:change(); h:advance(1)
    eq(#h.sent, 0); eq(#h.emotes, 1); eq(h.emotes[1].token, "THANK")
    saved.emoteText = "thanks {name}!"
    h = active(saved); h:add(1, 3600); h:change(); h:advance(1)
    eq(#h.sent, 0); h:prepare(); eq(h.draft, "/em thanks BuffFriend!")
end)

test("new installations default to a five-second reply delay", function()
    local h = harness({__defaultDelay = true}); eq(h.env.ForeverThanksDB.delay, 5)
end)
test("configured five-second delay is honored", function()
    local h = active({delay = 5}); h:add(1, 3600); h:change(); h:advance(4); eq(#h.sent, 0)
    h:advance(1); eq(#h.sent, 1)
end)
test("group whisper suppression checks the actual caster", function()
    local h = active({skipGroupWhispers = true}); h.grouped = true; h.party = "Player-BuffFriend"
    h:add(1, 3600, "Player-BuffFriend"); h:change(); h:advance(1); eq(#h.sent, 0)
    h:add(2, 3600, "Player-Outsider"); h:change(); h:advance(1); eq(#h.sent, 1)
end)
test("ignored buff names and IDs prevent pending replies", function()
    local h = active(); h:cmd("ignore add Blessing of Might"); h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h:cmd("ignore remove Blessing of Might"); h:add(2, 3600, nil, "Other Buff", 12345); h:cmd("ignore add 12345")
    h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("random emote mode uses a positive targeted emote", function()
    local h = active({channel = "EMOTE", emoteStyle = "RANDOM"}); h:add(1, 3600); h:change(); h:advance(1)
    local allowed = {SALUTE = true, BOW = true, WAVE = true, CHEER = true, APPLAUD = true}
    eq(#h.emotes, 1); assert(allowed[h.emotes[1].token]); eq(h.emotes[1].target, "BuffFriend")
end)
test("send error handled without retry storm", function()
    local h = active(); h.sendError = true; h:add(1, 3600); h:change(); h:advance(1); h:change(); h:advance(1)
    eq(#h.sent, 0); h:cmd("status"); assert(table.concat(h.output):find("send errors=1", 1, true))
end)
test("new and upgraded settings use WHISPER with caster recipient", function()
    for _, saved in ipairs({{}, {enabled = true, message = "Thanks!"}, {channel = "RAID"}, {channel = "SAY"}}) do
        local h = active(saved); h:add(1, 3600); h:change(); h:advance(1)
        eq(h.env.ForeverThanksDB.channel, "WHISPER"); eq(h.sent[1].channel, "WHISPER"); eq(h.sent[1].recipient, "BuffFriend-Realm")
    end
end)
test("legacy channel command cannot re-enable SAY", function()
    local h = active(); h:cmd("channel whisper"); eq(h.env.ForeverThanksDB.channel, "WHISPER")
    h:cmd("channel raid"); eq(h.env.ForeverThanksDB.channel, "WHISPER")
    local reloaded = active(h.env.ForeverThanksDB)
    reloaded:add(1, 3600); reloaded:change(); reloaded:advance(1); eq(reloaded.sent[1].channel, "WHISPER")
    h:cmd("channel SaY"); h:add(1, 3600); h:change(); h:advance(1)
    eq(h.env.ForeverThanksDB.channel, "WHISPER")
    eq(h.sent[1].channel, "WHISPER"); eq(h.sent[1].recipient, "BuffFriend-Realm")
end)
test("legacy channel command during delay preserves whisper and cooldown", function()
    local h = active(); h:add(1, 3600); h:change(); h:cmd("channel whisper"); h:advance(1)
    eq(h.sent[1].channel, "WHISPER"); h:cmd("channel say"); h:add(2, 3600); h:change(); h:advance(1); eq(#h.sent, 1)
end)
test("28 unique replies with no consecutive random repeat", function()
    local h = active(); local replies, previous = {}, nil
    for i = 1, 400 do
        h:advance(61); h.auras = {}; h:change(); h:add(i, 3600); h:change(); h:advance(1)
        local text = h.sent[#h.sent].text
        assert(text ~= previous); previous = text; replies[text] = true
    end
    local count = 0; for _ in pairs(replies) do count = count + 1 end; eq(count, 28)
end)
test("outdoor WHISPER is attempted automatically without drafts or input", function()
    local h = active(); h.outdoors = true; h:add(1, 3600); h:change(); h:advance(1)
    eq(#h.sent, 1); eq(h.sent[1].channel, "WHISPER"); eq(h.sent[1].recipient, "BuffFriend-Realm"); eq(h.draft, nil)
    h:cmd("send"); h:advance(0); eq(#h.sent, 1); eq(h.draft, nil)
end)
test("blocked outdoor WHISPER is reported without automatic retries", function()
    local h = active(); h.outdoors = true; h.sendError = true
    h:add(1, 3600); h:change(); h:advance(1); h:change(); h:advance(10)
    eq(#h.sent, 0); eq(h.draft, nil)
    h:cmd("status"); assert(table.concat(h.output):find("send errors=1", 1, true))
end)
test("optional targeted emote persists and sends no whisper", function()
    local h = active(); h:cmd("mode EmOtE"); eq(h.env.ForeverThanksDB.channel, "EMOTE")
    h:cmd("mode raid"); eq(h.env.ForeverThanksDB.channel, "EMOTE")
    h = active(h.env.ForeverThanksDB); h:add(1, 3600); h:change(); h:advance(1)
    eq(#h.sent, 0); eq(#h.emotes, 1)
    eq(h.emotes[1].token, "THANK"); eq(h.emotes[1].target, "BuffFriend")
    h:cmd("status"); assert(table.concat(h.output):find("send errors=0", 1, true))
    h:cmd("mode whisper"); h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
    eq(#h.sent, 1); eq(#h.emotes, 1); eq(h.sent[1].channel, "WHISPER")
end)
test("emote uses existing cooldown and short/self filters", function()
    local h = active({channel = "EMOTE"})
    h:add(1, 120); h:add(2, 3600, "Player-Self"); h:change(); h:advance(1)
    eq(#h.emotes, 0)
    h:add(3, 3600); h:change(); h:advance(1); eq(#h.emotes, 1)
    h:add(4, 3600); h:change(); h:advance(10); eq(#h.emotes, 1); eq(#h.sent, 0)
end)
test("mode changes cancel pending replies without resetting cooldown", function()
    local h = active(); h:add(1, 3600); h:change(); h:cmd("channel emote"); h:advance(1)
    eq(#h.sent, 0); eq(#h.emotes, 0)
    h:add(2, 3600); h:change(); h:advance(1); eq(#h.emotes, 1)
    h:cmd("mode whisper"); h:add(3, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
end)
test("disable still cancels queued emotes", function()
    local h = active({channel = "EMOTE"}); h:add(1, 3600); h:change(); h:cmd("off")
    h:advance(1); eq(#h.emotes, 0); eq(#h.sent, 0)
end)
test("emote restricted=true and thrown errors are counted without retry or whisper fallback", function()
    for _, flag in ipairs({"emoteRejected", "emoteError"}) do
        local h = active({channel = "EMOTE"}); h[flag] = true
        h:add(1, 3600); h:change(); h:advance(1); h:change(); h:advance(10)
        eq(#h.emotes, 1); eq(#h.sent, 0); h:cmd("status")
        assert(table.concat(h.output):find("send errors=1", 1, true))
    end
end)
test("legacy emote fallback and missing API handled", function()
    local h = active({channel = "EMOTE"}); h.env.C_ChatInfo.PerformEmote = nil
    h.env.DoEmote = function(token, target) h.emotes[1] = {token = token, target = target} end
    h:add(1, 3600); h:change(); h:advance(1)
    eq(h.emotes[1].target, "BuffFriend"); eq(h.emotes[1].token, "THANK"); eq(#h.sent, 0)
    h = active({channel = "EMOTE"}); h.env.C_ChatInfo.PerformEmote = nil
    h:add(1, 3600); h:change(); h:advance(1); h:cmd("status")
    eq(#h.sent, 0); assert(table.concat(h.output):find("send errors=1", 1, true))
end)
test("emote bypasses custom whisper formatting and preview sends nothing", function()
    local h = active({channel = "EMOTE", message = string.rep("%s", 100)})
    h:cmd("preview"); eq(#h.emotes, 0)
    h:add(1, 3600); h:change(); h:advance(1); eq(#h.emotes, 1); eq(#h.sent, 0)
end)
test("plain caster name including spaces is retained for delayed emotes, not whispers", function()
    local h = active({channel = "EMOTE"}); h.casterName = "Buff Friend"
    h:add(1, 3600); h:change(); h.casterName = "Somebody Else"; h:advance(1)
    eq(h.emotes[1].target, "Buff Friend"); eq(#h.sent, 0)
    h:cmd("mode whisper"); h.casterName = "Buff Friend"; h:advance(61)
    h:add(2, 3600); h:change(); h:advance(1)
    eq(h.sent[1].recipient, "Buff Friend-Realm"); eq(#h.emotes, 1)
end)
test("nil emote restriction flag is not reported as blocked", function()
    local h = active({channel = "EMOTE"}); h.emoteReturnNil = true
    h:add(1, 3600); h:change(); h:advance(1); h:cmd("status")
    eq(#h.emotes, 1); assert(table.concat(h.output):find("send errors=0", 1, true))
end)

test("default THANK for Wisdom does not depend on readable movement information", function()
    for _, kind in ipairs({"moving", "missing", "secret", "error"}) do
        local h = active({channel = "EMOTE", emoteStyle = "THANK"})
        if kind == "moving" then h.speed = 7; h.falling = true
        elseif kind == "missing" then h.env.GetUnitSpeed = nil
        elseif kind == "secret" then h.speed = {secret = true}
        else h.speedError = true end
        h:add(1, 3600, "Player-Paladin", "Blessing of Wisdom"); h:change(); h:advance(1)
        eq(#h.emotes, 1); eq(h.emotes[1].token, "THANK"); eq(h.emotes[1].target, "Paladin")
    end
end)

test("custom text emotes expand names and buffs but require clicking Prepare and pressing Enter", function()
    local h = active({message = "Whisper unchanged."})
    h:cmd("mode custom")
    h:cmd("emotetext /em thank you {name} for this amazing %s, 100% appreciated!")
    h.speed = 7; h.falling = true; h.speedError = true
    h:add(1, 3600, "Player-Paladin", "Blessing of Wisdom"); h:change(); h:advance(1)
    eq(#h.sent, 0); eq(h.draft, nil); assert(h.prompt.shown)
    h:prepare(); eq(#h.sent, 0); h:enter()
    eq(#h.sent, 1); eq(h.sent[1].channel, "EMOTE"); eq(h.sent[1].recipient, nil)
    eq(h.sent[1].text, "thank you Paladin for this amazing Blessing of Wisdom, 100% appreciated!")
    eq(#h.emotes, 0); eq(h.env.ForeverThanksDB.message, "Whisper unchanged.")
end)

test("custom emote uses the Emote mode, built-in blank fallback, and separate character storage", function()
    local shared = {emoteText = "shared thanks {name}!", message = "Shared whisper."}
    local character = {useCharacterMessage = true, message = "My whisper."}
    local h = active(shared, character); h:cmd("mode custom")
    h:cmd("preview"); eq(#h.sent, 0); eq(#h.emotes, 0)
    assert(h.output[#h.output]:find("Thank emote", 1, true))
    h:cmd("emotetext /me salutes {name} for %s!")
    eq(character.emoteText, "salutes {name} for %s!"); eq(shared.emoteText, "shared thanks {name}!")
    h = active(shared, character)
    eq(shared.channel, "EMOTE")
    h:add(1, 3600); h:change(); h:advance(1)
    h:prepare(); h:enter()
    eq(h.sent[1].text, "salutes BuffFriend for Blessing of Might!")
    h:cmd("emotetext default"); eq(character.emoteText, nil); eq(shared.emoteText, "shared thanks {name}!")
    eq(character.message, "My whisper.")
    h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
    eq(#h.sent, 1); eq(#h.emotes, 1); eq(h.emotes[1].token, "THANK")
end)

test("custom emote validation strips only emote prefixes and rejects commands and invalid text", function()
    local h = active({channel = "CUSTOM_EMOTE"})
    for _, prefix in ipairs({"/em ", "/emote ", "/e ", "/me "}) do
        h:cmd("emotetext " .. prefix .. "thanks {name}!")
        eq(h.env.ForeverThanksDB.emoteText, "thanks {name}!")
    end
    for _, text in ipairs({"/run evil()", "/dance", "bad|text", "bad\ntext", string.rep("x", 201)}) do
        h:cmd("emotetext " .. text)
        eq(h.env.ForeverThanksDB.emoteText, "thanks {name}!")
    end
    h:cmd("emotetext "); eq(h.env.ForeverThanksDB.emoteText, nil)
end)

test("custom emote length and unavailable chat fail without sending or falling back", function()
    local h = active({channel = "CUSTOM_EMOTE", emoteText = string.rep("%s", 100)})
    h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0); eq(#h.emotes, 0)
    eq(h.prompt, nil)
    h = active({channel = "EMOTE", emoteText = "thanks {name}!"}); h.openError = true
    h:add(1, 3600); h:change(); h:advance(1); h:change(); h:advance(10)
    h:prepare(); assert(h.prompt.shown); eq(h.draft, nil)
    eq(#h.sent, 0); eq(#h.emotes, 0)
    h:cmd("status"); assert(table.concat(h.output):find("prepared=0 (not confirmed sent)", 1, true))
end)

test("custom text mode respects disabling, scope changes, filters, and same-caster cooldown", function()
    for _, cancel in ipairs({"off", "mode whisper", "messagescope character", "zone"}) do
        local h = active({channel = "EMOTE", emoteText = "thanks {name}!"})
        h:add(1, 3600); h:change()
        if cancel == "zone" then h:event("PLAYER_LEAVING_WORLD") else h:cmd(cancel) end
        h:advance(12); eq(#h.sent, 0); eq(#h.emotes, 0)
    end
    local h = active({channel = "EMOTE", emoteText = "thanks {name}!", skipGroupWhispers = true})
    h.party = "Player-BuffFriend"
    h:add(1, 300); h:add(2, 3600, "Player-Self"); h:change(); h:advance(1); eq(#h.sent, 0)
    h:add(3, 3600); h:change(); h:advance(1); eq(#h.sent, 0); h:prepare(); h:enter()
    eq(#h.sent, 1); eq(h.sent[1].channel, "EMOTE")
    h:add(4, 3600); h:change(); h:advance(10); eq(#h.sent, 1)
end)

test("old custom mode migrates into Emote while keeping saved roleplay text", function()
    local shared = {channel = "CUSTOM_EMOTE", emoteText = "My gratitude, {name}!", message = "Whisper stays."}
    local h = active(shared)
    eq(shared.channel, "EMOTE"); eq(shared.emoteText, "My gratitude, {name}!")
    h:add(1, 3600); h:change(); h:advance(1)
    h:prepare(); h:enter()
    eq(h.sent[1].channel, "EMOTE"); eq(h.sent[1].text, "My gratitude, BuffFriend!")
    eq(#h.emotes, 0)
    h:cmd("mode whisper"); eq(shared.message, "Whisper stays.")
    h:cmd("mode custom"); eq(shared.channel, "EMOTE")
end)

test("Emote with custom text only prepares text; blank restores automatic Thank or random", function()
    for _, style in ipairs({"THANK", "RANDOM"}) do
        local h = active({channel = "EMOTE", emoteStyle = style})
        h:cmd("emotetext thank you {name} for %s!")
        h.speed = 7; h.speedError = true
        h:add(1, 3600); h:change(); h:advance(1)
        eq(#h.sent, 0); h:prepare(); h:enter()
        eq(#h.sent, 1); eq(h.sent[1].channel, "EMOTE"); eq(#h.emotes, 0)
        h:cmd("emotetext "); h.speedError = false; h.speed = 0
        h:advance(61); h:add(2, 3600); h:change(); h:advance(1)
        eq(#h.sent, 1); eq(#h.emotes, 1)
        if style == "THANK" then eq(h.emotes[1].token, "THANK") end
    end
end)

test("custom emotes never call protected sending APIs, indoors or outdoors, moving or in combat", function()
    for _, outdoors in ipairs({false, true}) do
        local h = active({channel = "EMOTE", emoteText = "{name}, thanks for %s!"})
        h.outdoors, h.combat, h.speed, h.sendError = outdoors, true, 7, true
        h:add(1, 3600, "Player-Paladin", "Blessing of Wisdom"); h:change(); h:advance(1)
        eq(#h.sent, 0); eq(#h.emotes, 0); eq(h.draft, nil)
        h:prepare()
        eq(h.draft, "/em Paladin, thanks for Blessing of Wisdom!")
        eq(#h.sent, 0); eq(#h.chatRequests, 0); eq(h.prompt.shown, false)
        h:cmd("status"); assert(table.concat(h.output):find("prepared=1 (not confirmed sent)", 1, true))
    end
end)

test("custom prompt never overwrites existing chat and missing chat API stays local", function()
    local h = active({channel = "EMOTE", emoteText = "thanks {name}!"})
    h:add(1, 3600); h:change(); h:advance(1)
    h.chatActive, h.draft = true, "My unfinished message"
    h:prepare(); eq(h.draft, "My unfinished message"); assert(h.prompt.shown)
    h.chatActive = false; h.env.ChatFrameUtil.OpenChat = nil
    h:prepare(); eq(h.draft, "My unfinished message"); eq(#h.sent, 0)
end)

test("visible custom prompt is canceled by disable, zoning, settings, filters, or restricted data", function()
    for _, cancel in ipairs({"off", "zone", "mode whisper", "messagescope character", "emotetext new text", "ignore add Blessing of Might", "read", "groups off"}) do
        local h = active({channel = "EMOTE", emoteText = "thanks {name}!"})
        h:add(1, 3600); h:change(); h:advance(1); assert(h.prompt.shown)
        local click = h.prompt.prepare.scripts.OnClick
        if cancel == "zone" then h:event("PLAYER_LEAVING_WORLD")
        elseif cancel == "read" then h.readError = true; h:change()
        else h:cmd(cancel) end
        eq(h.prompt.shown, false)
        h.click = true; click(); h.click = false
        eq(#h.sent, 0); eq(h.draft, nil)
    end
end)

test("custom drafts coalesce casters, preserve their names, support Skip, and expire", function()
    local h = active({channel = "EMOTE", emoteText = "thanks {name} for %s!"})
    h:add(1, 3600, "Player-Priest", "Fortitude"); h:add(2, 3600, "Player-Paladin", "Wisdom")
    h:change(); h:advance(1)
    h:add(3, 3600, "Player-Priest"); h:change(); h:advance(2)
    eq(h.prompt.title.text, "Custom emote ready (2)")
    h.casterName = "Wrong Person"; h:prepare()
    eq(h.draft, "/em thanks Priest for Fortitude!"); h:enter()
    assert(h.prompt.preview.text:find("Paladin - Wisdom", 1, true))
    h.prompt.skip.scripts.OnClick(); eq(h.prompt.shown, false)
    h:advance(61); h:add(4, 3600, "Player-Paladin"); h:change(); h:advance(1)
    assert(h.prompt.shown); h:advance(60); eq(h.prompt.shown, false)
    eq(#h.sent, 1); eq(#h.tasks, 0)
end)

test("custom prompt queue is capped at five and expires without opening chat", function()
    local h = active({channel = "EMOTE", emoteText = "thanks {name}!"})
    for i = 1, 8 do h:add(i, 3600, "Player-Caster" .. i) end
    h:change(); h:advance(1)
    eq(h.prompt.title.text, "Custom emote ready (5)")
    h:advance(60); eq(h.prompt.shown, false); eq(h.draft, nil); eq(#h.sent, 0); eq(#h.tasks, 0)
end)

test("random animated emotes wait until stopped, retaining the caster", function()
    for _, style in ipairs({"RANDOM"}) do
        local h = active({channel = "EMOTE", emoteStyle = style})
        h:add(1, 3600); h:change(); h.speed = 7 -- Movement begins during the reply delay.
        h:advance(3); eq(#h.emotes, 0)
        h.casterName = "Somebody Else"; h.speed = 0; h:advance(0.5)
        eq(#h.emotes, 1); eq(h.emotes[1].target, "BuffFriend")
        eq(h.emotes[1].suppressMoveError, true)
        h:change(); h:advance(20); eq(#h.emotes, 1)
    end
end)

test("movement wait expires without a late emote or consuming the caster cooldown", function()
    local h = active({channel = "EMOTE", emoteStyle = "RANDOM"}); h.speed = 7
    h:add(1, 3600); h:change(); h:advance(12); eq(#h.emotes, 0); eq(#h.tasks, 0)
    h.speed = 0; h:advance(1); eq(#h.emotes, 0)
    h:add(2, 3600); h:change(); h:advance(1); eq(#h.emotes, 1)
end)

test("a delayed timer cannot send a stale emote after the movement deadline", function()
    local h = active({channel = "EMOTE", emoteStyle = "RANDOM"}); h.speed = 7
    h:add(1, 3600); h:change(); h:advance(1)
    local task = table.remove(h.tasks, 1)
    h.now = h.now + 11; h.speed = 0; task[2]()
    eq(#h.emotes, 0); eq(#h.tasks, 0)
end)

test("falling and missing, secret, or thrown movement reads never select an emote", function()
    for _, kind in ipairs({"falling", "missing", "secret", "error"}) do
        local h = active({channel = "EMOTE", emoteStyle = "RANDOM"})
        if kind == "falling" then h.falling = true
        elseif kind == "missing" then h.env.GetUnitSpeed = nil
        elseif kind == "secret" then h.speed = {secret = true}
        else h.speedError = true end
        h:add(1, 3600); h:change(); h:advance(12)
        eq(#h.emotes, 0); eq(#h.tasks, 0)
    end
end)

test("whispers ignore movement and send during combat", function()
    local h = active(); h.speed = 7; h.falling = true; h.combat = true
    h:event("PLAYER_REGEN_DISABLED"); h:add(1, 3600); h:change(); h:advance(1)
    eq(#h.sent, 1); eq(h.sent[1].recipient, "BuffFriend-Realm")
end)

test("movement wait respects combat transitions, cancellation, and per-caster coalescing", function()
    local h = active({channel = "EMOTE", emoteStyle = "RANDOM"}); h.speed = 7
    h:add(1, 3600); h:change(); h:advance(1)
    h:add(2, 3600); h:change(); h.combat = true; h:event("PLAYER_REGEN_DISABLED")
    h.speed = 0; h:advance(0.5); eq(#h.emotes, 1)
    for _, cancel in ipairs({"off", "mode whisper", "zone"}) do
        h = active({channel = "EMOTE", emoteStyle = "RANDOM"}); h.speed = 7
        h:add(1, 3600); h:change(); h:advance(2)
        if cancel == "zone" then h:event("PLAYER_LEAVING_WORLD") else h:cmd(cancel) end
        h.speed = 0; h:advance(12); eq(#h.emotes, 0); eq(#h.sent, 0)
    end
end)

test("secret player and group GUIDs are handled safely during combat", function()
    local h = active({skipGroupWhispers = true}); h.combat = true
    h.party = {secret = true}; h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h.env.UnitGUID = function() return {secret = true} end
    h:change(); h:advance(1); eq(#h.sent, 0)
end)
for _, mode in ipairs({"EMOTE", "WHISPER"}) do
    local function replies(h) return #h.sent + #h.emotes end
    test(mode .. ": restored login buffs arrive in batches silently, then new buffs work", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD")
        h:advance(0.5); h:add(1, 3600).expirationTime = h.now + 1800; h:change()
        h:advance(2); h:add(2, 3600).expirationTime = h.now + 1700; h:change()
        h:advance(4); eq(replies(h), 0)
        h:add(3, 3600); h:change(); h:advance(1); eq(replies(h), 1)
    end)
    test(mode .. ": portal restores changed aura IDs without thanks, refresh later works", function()
        local h = active({channel = mode}); h:add(1, 3600); h:change(); h:advance(1)
        h:advance(61); h:event("PLAYER_LEAVING_WORLD"); h.auras = {}
        h:event("PLAYER_ENTERING_WORLD"); h:advance(1)
        local old = h:add(99, 3600); old.expirationTime = h.now + 1800; h:change()
        h:advance(6); eq(replies(h), 1)
        old.expirationTime = h.now + 3600; h:change(); h:advance(1); eq(replies(h), 2)
    end)
    test(mode .. ": late old buff beyond settling deadline is skipped, new buff works", function()
        local h = active({channel = mode}); h:advance(20)
        local old = h:add(1, 3600); old.expirationTime = h.now + 1800
        h:change(); h:advance(1); eq(replies(h), 0)
        h:add(2, 3600); h:change(); h:advance(1); eq(replies(h), 1)
    end)
    test(mode .. ": full-duration buff during settling is baselined, not sent later", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD"); h:advance(1)
        h:add(1, 3600); h:change(); h:advance(6); h:change(); h:advance(1)
        eq(replies(h), 0)
    end)
    test(mode .. ": updates near deadline extend settling until quiet", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD")
        h:advance(4.8); h:add(1, 3600); h:change(); h:advance(0.5)
        h:add(2, 3600); h:change(); h:advance(0.9); h:cmd("status")
        assert(table.concat(h.output):find("settling after loading", 1, true))
        h:advance(1); eq(replies(h), 0)
        h:add(3, 3600); h:change(); h:advance(1); eq(replies(h), 1)
    end)
    test(mode .. ": final snapshot catches restoration without an aura event", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD"); h:advance(4)
        h:add(1, 3600); h:advance(2); h:change(); h:advance(1); eq(replies(h), 0)
    end)
    test(mode .. ": rapid transfers invalidate old timers and suppress between-world events", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD"); h:advance(4)
        h:event("PLAYER_LEAVING_WORLD"); h:add(1, 3600); h:change(); h:advance(4)
        eq(replies(h), 0)
        h:event("PLAYER_ENTERING_WORLD"); h:advance(2); h:add(2, 3600); h:change()
        h:advance(4); eq(replies(h), 0)
        h:add(3, 3600); h:change(); h:advance(1); eq(replies(h), 1)
    end)
    test(mode .. ": settings changes do not cancel settling or enable early replies", function()
        local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD"); h:advance(1)
        h:cmd("off"); h:cmd("on"); h:cmd("groups on")
        h:cmd("mode " .. (mode == "EMOTE" and "whisper" or "emote")); h:cmd("mode " .. mode:lower())
        h:add(1, 3600); h:change(); h:advance(5); eq(replies(h), 0)
        h:add(2, 3600); h:change(); h:advance(1); eq(replies(h), 1)
    end)
    test(mode .. ": combat or unreadable data during settling cannot replay old buffs", function()
        for _, kind in ipairs({"combat", "restricted"}) do
            local h = harness({channel = mode}); h:event("PLAYER_ENTERING_WORLD")
            if kind == "combat" then h.combat = true; h:event("PLAYER_REGEN_DISABLED") else h.readError = true end
            h:add(1, 3600); h:change(); h:advance(6)
            h.combat = false; h.readError = false
            if kind == "combat" then h:event("PLAYER_REGEN_ENABLED") else h:change() end
            h:advance(1); eq(replies(h), 0)
            h:add(2, 3600); h:change(); h:advance(1); eq(replies(h), 1)
        end
    end)
end
for _, item in ipairs(tests) do
    item[2](); passed = passed + 1; print("PASS " .. item[1])
end
print(passed .. " tests passed")
dofile("tests/minimap.lua")("forever_thanks")
dofile("tests/options.lua")("forever_thanks")
