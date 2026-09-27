-- Run from the repository root with Lua 5.1; no game or network access.
local tests, passed = {}, 0
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function harness(saved)
    local h = {auras = {}, now = 100, tasks = {}, sent = {}, emotes = {}, output = {}, combat = false, grouped = false}
    local env = setmetatable({ForeverThanksDB = saved, SlashCmdList = {}}, {__index = _G})
    env.print = function(text) h.output[#h.output + 1] = text end
    env.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    env.CreateFrame = function()
        return {RegisterEvent = function() end, SetScript = function(_, _, fn) h.handler = fn end}
    end
    env.GetTime = function() return h.now end
    env.InCombatLockdown = function() return h.combat end
    env.IsInInstance = function() return not h.outdoors end
    env.ChatFrameUtil = {OpenChat = function(text) h.draft = text end}
    env.IsInGroup = function() return h.grouped end
    env.UnitGUID = function() return "Player-Self" end
    env.UnitName = function() error("Must not read the selected target") end
    env.TargetUnit = function() error("Must not change the selected target") end
    env.ClearTarget = function() error("Must not clear the selected target") end
    env.UnitNameFromGUID = function(guid)
        if h.noName then return nil end
        return h.casterName or guid:gsub("Player%-", ""), "Realm"
    end
    env.C_Timer = {After = function(delay, fn) h.tasks[#h.tasks + 1] = {h.now + delay, fn} end}
    env.C_ChatInfo = {SendChatMessage = function(text, channel, language, recipient)
        if h.sendError then error("blocked") end
        h.sent[#h.sent + 1] = {text = text, channel = channel, recipient = recipient}
    end}
    env.C_ChatInfo.PerformEmote = function(token, target)
        h.emotes[#h.emotes + 1] = {token = token, target = target}
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
    function h:add(id, duration, guid, name)
        local aura = {auraInstanceID = id, duration = duration, expirationTime = self.now + duration,
            guid = guid or "Player-BuffFriend", name = name or "Blessing of Might", sourceUnit = nil}
        self.auras[#self.auras + 1] = aura
        return aura
    end
    function h:change() self:event("UNIT_AURA", "player") end
    h:event("ADDON_LOADED", "forever_thanks")
    h.env = env
    return h
end
local function active(saved) local h = harness(saved); h:event("PLAYER_ENTERING_WORLD"); h:advance(6); return h end

test("nil sourceUnit resolves caster and delayed realm-qualified whisper", function()
    local h = active({channel = "WHISPER"}); h:add(1, 3600); h:change(); eq(#h.sent, 0)
    h:advance(1); eq(#h.sent, 1); eq(h.sent[1].recipient, "BuffFriend-Realm"); eq(h.sent[1].channel, "WHISPER")
end)
test("strict two-minute boundary; short, permanent, missing duration ignored", function()
    for _, duration in ipairs({0, 15, 119, 120}) do
        local h = active(); h:add(1, duration); h:change(); h:advance(1); eq(#h.sent, 0)
    end
    local h = active(); h:add(1, 121).duration = nil; h:change(); h:advance(1); eq(#h.sent, 0)
    h = active(); h:add(1, 121); h:change(); h:advance(1); eq(#h.sent, 1)
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
end)
test("combat cancels pending, ignores combat buffs and rebaselines", function()
    local h = active(); h:add(1, 3600); h:change(); h.combat = true; h:event("PLAYER_REGEN_DISABLED")
    h:add(2, 3600, "Player-Other"); h:change(); h:advance(1); eq(#h.sent, 0)
    h.combat = false; h:event("PLAYER_REGEN_ENABLED"); h:change(); h:advance(1); eq(#h.sent, 0)
    h:add(3, 3600, "Player-New"); h:change(); h:advance(1); eq(#h.sent, 1)
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
test("saved settings honored and corrupt defaults normalized", function()
    local h = active({enabled = false, cooldown = 100, groups = false}); h:add(1, 3600); h:change(); h:advance(1); eq(#h.sent, 0)
    h = active({cooldown = "bad", message = 7}); eq(h.env.ForeverThanksDB.cooldown, 60); eq(h.env.ForeverThanksDB.message, nil)
    h:cmd("cooldown 5"); eq(h.env.ForeverThanksDB.cooldown, 60)
    h:cmd("cooldown 90"); eq(h.env.ForeverThanksDB.cooldown, 90)
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
test("emote combat and disable cancel queued replies", function()
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "off"}) do
        local h = active({channel = "EMOTE"}); h:add(1, 3600); h:change()
        if event == "off" then h:cmd(event) else h.combat = true; h:event(event) end
        h:advance(1); eq(#h.emotes, 0); eq(#h.sent, 0)
    end
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
        assert(h.output[#h.output - 4]:find("settling", 1, true))
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
