-- Run from the repository root with Lua 5.1; no game or network access.
local tests, passed = {}, 0
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function harness(saved)
    local h = {auras = {}, now = 100, tasks = {}, sent = {}, output = {}, combat = false, grouped = false}
    local env = setmetatable({ForeverThanksDB = saved, SlashCmdList = {}}, {__index = _G})
    env.print = function(text) h.output[#h.output + 1] = text end
    env.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    env.CreateFrame = function()
        return {RegisterEvent = function() end, SetScript = function(_, _, fn) h.handler = fn end}
    end
    env.GetTime = function() return h.now end
    env.InCombatLockdown = function() return h.combat end
    env.IsInGroup = function() return h.grouped end
    env.UnitGUID = function() return "Player-Self" end
    env.UnitNameFromGUID = function(guid)
        if h.noName then return nil end
        return guid:gsub("Player%-", ""), "Realm"
    end
    env.C_Timer = {After = function(delay, fn) h.tasks[#h.tasks + 1] = {h.now + delay, fn} end}
    env.C_ChatInfo = {SendChatMessage = function(text, channel, language, recipient)
        if h.sendError then error("blocked") end
        h.sent[#h.sent + 1] = {text = text, channel = channel, recipient = recipient}
    end}
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
        self.now = self.now + seconds
        local tasks = self.tasks; self.tasks = {}
        for _, item in ipairs(tasks) do
            if item[1] <= self.now then item[2]() else self.tasks[#self.tasks + 1] = item end
        end
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
local function active(saved) local h = harness(saved); h:event("PLAYER_ENTERING_WORLD"); return h end

test("nil sourceUnit resolves caster and delayed realm-qualified whisper", function()
    local h = active(); h:add(1, 3600); h:change(); eq(#h.sent, 0)
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
for _, item in ipairs(tests) do
    item[2](); passed = passed + 1; print("PASS " .. item[1])
end
print(passed .. " tests passed")
