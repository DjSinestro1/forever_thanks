-- Mock the button API to check placement, click, tooltip, and drag behavior.
return function(addon)
    local env = setmetatable({SlashCmdList = {}}, {__index = _G})
    local handler, button, tooltipOwner, opened
    local shape = "ROUND"
    local function noop() end
    local map = {
        GetFrameLevel = function() return 4 end,
        GetWidth = function() return 140 end,
        GetHeight = function() return 140 end,
        GetCenter = function() return 100, 100 end,
        GetEffectiveScale = function() return 2 end,
    }
    env.Minimap = map
    env.GetMinimapShape = function() return shape end
    function map:HookScript(event, callback) self[event] = callback end
    function map:SetMaskTexture() if self.maskChanged then self.maskChanged() end end
    env.hooksecurefunc = function(target, method, callback)
        assert(target == map and method == "SetMaskTexture")
        target.maskChanged = callback
    end
    env.GameTooltip = {SetOwner = function(_, owner) tooltipOwner = owner end,
        SetText = noop, AddLine = noop, Show = noop, Hide = noop}
    env.DEFAULT_CHAT_FRAME = {AddMessage = noop}
    env.print = noop
    env.GetTime = function() return 100 end
    env.GetCursorPosition = function() return 600, 200 end
    env.CreateFrame = function(kind, name, parent)
        local f = {scripts = {}, SetWidth = noop, SetHeight = noop,
            SetFrameStrata = noop, RegisterEvent = noop,
            SetHighlightTexture = noop, ClearAllPoints = noop, parent = parent}
        function f:GetParent() return self.parent end
        function f:SetParent(value) self.parent = value end
        function f:SetScript(event, callback)
            self.scripts[event] = callback
            if not name and event == "OnEvent" then handler = callback end
        end
        function f:SetNormalTexture(path)
            self.path = path
            self.texture = {ClearAllPoints = noop, SetPoint = noop,
                SetWidth = noop, SetHeight = noop}
        end
        function f:GetNormalTexture() return self.texture end
        function f:SetFrameLevel(level) self.level = level end
        function f:SetPoint(...) self.point = {...} end
        function f:RegisterForClicks(...) self.clicks = {...} end
        function f:RegisterForDrag(...) self.drag = {...} end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        if name and name:find("MinimapButton") then button = f end
        return f
    end
    local savedName = addon == "OctoThanks" and "OctoThanksDB" or "ForeverThanksDB"
    env[savedName] = {}
    local chunk = assert(loadfile(addon .. ".lua"))
    setfenv(chunk, env)
    chunk(addon)
    if addon == "forever_thanks" then handler(nil, "ADDON_LOADED", addon) end
    assert(button and button.shown)
    assert(button.path == "Interface\\AddOns\\" .. addon .. "\\minimap.tga")
    assert(button.level > map:GetFrameLevel())
    assert(button.point[1] == "CENTER" and button.point[2] == map)
    assert(button.point[4] < 0 and button.point[5] < 0)
    local radius = math.sqrt(button.point[4]^2 + button.point[5]^2)
    assert(radius > map:GetWidth() / 2)
    env.this = button
    button.scripts.OnEnter() -- Vanilla passes this instead of self.
    assert(tooltipOwner == button)
    button.scripts.OnEnter(button) -- Forever supplies self.
    assert(tooltipOwner == button)
    local openName = addon == "OctoThanks" and "OpenOctoThanksOptions" or "OpenForeverThanksOptions"
    env[openName] = function(toggle) assert(toggle == true); opened = true end
    button.scripts.OnClick()
    assert(opened)
    button.scripts.OnDragStart()
    button.scripts.OnUpdate()
    assert(math.abs(button.point[4] - 78) < 0.001)
    assert(math.abs(button.point[5]) < 0.001)
    assert(env[savedName].minimapAngle == 0)
    button.scripts.OnDragStop()
    assert(button.scripts.OnUpdate == nil)
    env[savedName].minimap.minimapPos = 225
    shape = "SQUARE"; map:SetMaskTexture()
    assert(math.abs(button.point[4] + 78) < 0.001 and math.abs(button.point[5] + 78) < 0.001)
    map.GetWidth = function() return 200 end
    map.GetHeight = function() return 160 end
    map.OnSizeChanged()
    assert(math.abs(button.point[4] + 108) < 0.001 and math.abs(button.point[5] + 88) < 0.001)
    shape = "ROUND"; map:SetMaskTexture()
    assert(math.abs(button.point[4] + 108 / math.sqrt(2)) < 0.001)
    -- A collector that reparents a fallback owns its placement too.
    local collectedParent = {}
    button:SetParent(collectedParent)
    button:SetPoint("BAG")
    map.OnSizeChanged(); map:SetMaskTexture()
    assert(button.point[1] == "BAG")
    env.SlashCmdList.FOREVERTHANKS("minimap off")
    assert(env[savedName].showMinimap == false and not button.shown)
    handler(nil, "PLAYER_ENTERING_WORLD")
    assert(not button.shown)
    env.SlashCmdList.FOREVERTHANKS("minimap on")
    assert(env[savedName].showMinimap == true and button.shown)
    assert(env[savedName].minimap.minimapPos == 225)
    -- A hidden preference must survive constructing a new addon instance.
    env.SlashCmdList.FOREVERTHANKS("minimap off")
    button = nil
    chunk = assert(loadfile(addon .. ".lua")); setfenv(chunk, env); chunk(addon)
    handler(nil, "ADDON_LOADED", addon)
    assert(button == nil and env[savedName].showMinimap == false)
    env.SlashCmdList.FOREVERTHANKS("minimap on")
    assert(button and button.shown)
    print("PASS " .. addon .. " standalone minimap: round/square, resizing, collection, tooltip, click, and saved visibility")

    local function sharedHarness(saved, initialLibrary, collect)
        local e = setmetatable({SlashCmdList = {}, ForeverThanksDB = saved or {}, Minimap = map}, {__index = _G})
        local h = {creates = 0, registerCalls = 0, showCalls = 0, hideCalls = 0, bag = {}}
        e.print = noop; e.GetTime = function() return 100 end
        e.GameTooltip = env.GameTooltip
        e.CreateFrame = function(kind, name, parent)
            local f = env.CreateFrame(kind, name, parent)
            if name == "ForeverThanksMinimapButton" then h.fallback = f; h.creates = h.creates + 1 end
            function f:SetScript(event, callback)
                self.scripts[event] = callback
                if not name and event == "OnEvent" then h.handler = callback end
            end
            return f
        end
        e.GetMinimapShape = function() return "SQUARE" end
        e.hooksecurefunc = env.hooksecurefunc
        e.GetCursorPosition = env.GetCursorPosition
        local broker = {NewDataObject = function(_, name, object)
            assert(name == "forever_thanks"); h.object = object; return object
        end}
        local library = {}
        function library:GetMinimapButton(name) assert(name == "forever_thanks"); return h.registered end
        function library:GetButtonList() return h.registered and {"forever_thanks"} or {} end
        function library:Register(name, object, db)
            h.registerCalls = h.registerCalls + 1
            if initialLibrary == "broken" then error("Unavailable icon library") end
            assert(name == "forever_thanks" and object.type == "launcher")
            local f = e.CreateFrame("Button", "LibDBIcon10_forever_thanks", map)
            f.db, f.dataObject = db, object
            h.registered = f
            function f:Show()
                h.showCalls = h.showCalls + 1
                self.shown = not collect or h.bagOpen == true
            end
            function f:Hide() h.hideCalls = h.hideCalls + 1; self.shown = false end
            if db.hide then f:Hide() else f:Show() end
            -- Model Leatrix's IconCreated callback and bag-owned position.
            if collect then f:SetParent(h.bag); f:SetPoint("BAG"); f:Hide() end
        end
        function library:Hide(name) self:GetMinimapButton(name):Hide() end
        function library:Show(name)
            local f = self:GetMinimapButton(name); f:Show(); f:SetPoint("LIBRARY_POSITION")
        end
        function h:enableLibrary()
            e.LibStub = function(name, silent)
                assert(silent == true)
                return name == "LibDBIcon-1.0" and library or name == "LibDataBroker-1.1" and broker or nil
            end
        end
        function h:event(event, arg) self.handler(nil, event, arg) end
        function h:cmd(text) e.SlashCmdList.FOREVERTHANKS(text) end
        if initialLibrary then h:enableLibrary() end
        local c = assert(loadfile("forever_thanks.lua")); setfenv(c, e); c("forever_thanks")
        h:event("ADDON_LOADED", "forever_thanks")
        h.env, h.library = e, library
        return h
    end
    local h = sharedHarness({minimapAngle = math.pi / 3}, true, true)
    assert(h.creates == 0 and h.registerCalls == 1)
    assert(h.library:GetButtonList()[1] == "forever_thanks")
    assert(h.registered.db == h.env.ForeverThanksDB.minimap)
    assert(math.abs(h.registered.db.minimapPos - 60) < 0.001)
    assert(h.object.icon == "Interface\\AddOns\\forever_thanks\\minimap.tga")
    local shows = h.showCalls
    for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD", "ADDON_LOADED"}) do
        h:event(event, "OtherAddon")
    end
    assert(h.showCalls == shows and h.registerCalls == 1)
    assert(h.registered.point[1] == "BAG" and not h.registered.shown)
    local clicked, tooltipTitle
    h.env.OpenForeverThanksOptions = function(toggle) assert(toggle == true); clicked = true end
    h.object.OnClick(); assert(clicked)
    h.object.OnTooltipShow({SetText = function(_, text) tooltipTitle = text end, AddLine = noop})
    assert(tooltipTitle == "Forever Thanks")
    h:cmd("minimap off"); assert(h.registered.db.hide and not h.registered.shown)
    h.bagOpen = true; h:cmd("minimap on")
    assert(not h.registered.db.hide and h.registered.shown and h.registered.point[1] == "BAG")
    h.registered.db.minimapPos = 300
    h = sharedHarness(h.env.ForeverThanksDB, true, false)
    assert(h.registered.db.minimapPos == 300)
    h = sharedHarness({showMinimap = false}, true, true)
    assert(h.registered.db.hide and not h.registered.shown and h.creates == 0)
    h:cmd("minimap on"); assert(not h.registered.db.hide and not h.registered.shown)
    assert(h.registered.point[1] == "BAG")
    -- A later-loaded collector replaces, rather than duplicates, our fallback.
    h = sharedHarness({minimapAngle = math.pi}, false, true)
    assert(h.fallback.shown)
    h.fallback.scripts.OnDragStart(); assert(h.fallback.scripts.OnUpdate)
    h:cmd("minimap off")
    h:enableLibrary(); h:event("ADDON_LOADED", "Leatrix_Plus")
    assert(h.registerCalls == 1 and h.registered.db.hide)
    assert(not h.fallback.shown and h.fallback.scripts.OnUpdate == nil)
    local sentinel = function() end
    h.registered:SetScript("OnUpdate", sentinel)
    h.fallback.scripts.OnDragStop(); map:SetMaskTexture(); map.OnSizeChanged()
    assert(h.registered.scripts.OnUpdate == sentinel and h.registered.point[1] == "BAG")
    h:event("PLAYER_ENTERING_WORLD"); assert(h.registerCalls == 1 and h.registered.db.hide)
    h = sharedHarness({minimapAngle = 0/0}, "broken", false)
    assert(h.fallback.shown and not h.registered)
    assert(h.env.ForeverThanksDB.minimap.minimapPos == 225)
    h:event("PLAYER_LOGIN"); assert(h.registerCalls == 2 and h.creates == 1)
    print("PASS forever_thanks shared minimap: bag discovery, manager-owned placement, load order, saved position, and hide/show")
end
