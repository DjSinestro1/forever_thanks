-- Mock the button API to check placement, click, tooltip, and drag behavior.
return function(addon)
    local env = setmetatable({SlashCmdList = {}}, {__index = _G})
    local handler, button, tooltipOwner, opened
    local function noop() end
    local map = {
        GetFrameLevel = function() return 4 end,
        GetWidth = function() return 140 end,
        GetHeight = function() return 140 end,
        GetCenter = function() return 100, 100 end,
        GetEffectiveScale = function() return 2 end,
    }
    env.Minimap = map
    env.GameTooltip = {SetOwner = function(_, owner) tooltipOwner = owner end,
        SetText = noop, AddLine = noop, Show = noop, Hide = noop}
    env.DEFAULT_CHAT_FRAME = {AddMessage = noop}
    env.print = noop
    env.GetTime = function() return 100 end
    env.GetCursorPosition = function() return 600, 200 end
    env.CreateFrame = function(kind, name)
        local f = {scripts = {}, SetWidth = noop, SetHeight = noop,
            SetFrameStrata = noop, RegisterEvent = noop,
            SetHighlightTexture = noop, ClearAllPoints = noop}
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
    env[openName] = function() opened = true end
    button.scripts.OnClick()
    assert(opened)
    button.scripts.OnDragStart()
    button.scripts.OnUpdate()
    assert(math.abs(button.point[4] - 78) < 0.001)
    assert(math.abs(button.point[5]) < 0.001)
    assert(env[savedName].minimapAngle == 0)
    button.scripts.OnDragStop()
    assert(button.scripts.OnUpdate == nil)
    env.SlashCmdList.FOREVERTHANKS("minimap off")
    assert(env[savedName].showMinimap == false and not button.shown)
    handler(nil, "PLAYER_ENTERING_WORLD")
    assert(not button.shown)
    env.SlashCmdList.FOREVERTHANKS("minimap on")
    assert(env[savedName].showMinimap == true and button.shown)
    assert(env[savedName].minimapAngle == 0)
    -- A hidden preference must survive constructing a new addon instance.
    env.SlashCmdList.FOREVERTHANKS("minimap off")
    button = nil
    chunk = assert(loadfile(addon .. ".lua")); setfenv(chunk, env); chunk(addon)
    handler(nil, "ADDON_LOADED", addon)
    assert(button == nil and env[savedName].showMinimap == false)
    env.SlashCmdList.FOREVERTHANKS("minimap on")
    assert(button and button.shown)
    print("PASS " .. addon .. " minimap texture, placement, tooltip, click, and saved drag")
end
