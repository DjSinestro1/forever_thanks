-- Exercise the real options callbacks without a running WoW client.
return function(addon)
    local savedName = addon == "OctoThanks" and "OctoThanksDB" or "ForeverThanksDB"
    local openName = addon == "OctoThanks" and "OpenOctoThanksOptions" or "OpenForeverThanksOptions"
    local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
    local function harness(saved, legacy)
        local env = setmetatable({SlashCmdList = {}}, {__index = _G})
        env[savedName] = saved or {}
        env.GetTime = function() return 100 end
        env.print = function() end
        env.DEFAULT_CHAT_FRAME = {AddMessage = function() end}
        local root, options, widgets = nil, nil, {}
        local function widget(kind, name)
            local f = {scripts = {}, text = "", kind = kind}
            local function noop() end
            setmetatable(f, {__index = function(_, key)
                if key:find("^Set") or key:find("^Register") then return noop end
            end})
            function f:SetScript(event, fn) self.scripts[event] = fn end
            function f:Fire(event)
                local fn = self.scripts[event]
                if not fn then return end
                local previous = env.this
                env.this = self
                if legacy then fn() else fn(self) end
                env.this = previous
            end
            function f:SetText(text)
                self.text = tostring(text)
                self:Fire("OnTextChanged")
            end
            function f:GetText() return self.text end
            function f:SetChecked(value) self.checked = value end
            function f:GetChecked() return self.checked end
            function f:ClearFocus() self:Fire("OnEditFocusLost") end
            function f:Show() self:Fire("OnShow") end
            function f:Hide() self:Fire("OnHide") end
            function f:CreateFontString() return widget("FontString") end
            function f:CreateTexture() return widget("Texture") end
            widgets[#widgets + 1] = f
            if kind == "Frame" and not root then root = f end
            if name == "ForeverThanksOptions" or name == "OctoThanksOptions" then options = f end
            return f
        end
        env.CreateFrame = widget
        local chunk = assert(loadfile(addon .. ".lua"))
        setfenv(chunk, env)
        chunk(addon)
        if addon == "forever_thanks" then root.scripts.OnEvent(nil, "ADDON_LOADED", addon) end
        local function open() env[openName](); return options end
        return env, open, widgets
    end
    for _, legacy in ipairs({false, true}) do
        local env, open, widgets = harness(nil, legacy)
        local f, db = open(), env[savedName]
        eq(db.delay, 5); eq(db.cooldown, 60)
        eq(db.showMinimap, true); eq(f.showMinimap:GetChecked(), true)
        f.showMinimap:SetChecked(false); f.showMinimap:Fire("OnClick")
        eq(db.showMinimap, false)
        -- No Enter: closing, other controls, and reopening must retain valid edits.
        f.delay:SetText("7.5"); f.cooldown:SetText("180")
        eq(db.delay, 7.5); eq(db.cooldown, 180)
        for _, button in ipairs(widgets) do
            if button.kind == "Button" and button.text == "Emote" then button:Fire("OnClick") end
        end
        eq(f.delay:GetText(), "7.5"); eq(f.cooldown:GetText(), "180")
        f:Hide(); open()
        eq(f.delay:GetText(), "7.5"); eq(f.cooldown:GetText(), "180")
        -- Invalid or incomplete text must not reset either setting.
        f.delay:SetText(""); f.cooldown:SetText("300")
        eq(db.delay, 7.5); eq(db.cooldown, 300)
        f.delay:ClearFocus()
        eq(f.delay:GetText(), "7.5"); eq(f.cooldown:GetText(), "300")
        for _, invalid in ipairs({"61", "-1", "nope", "nan"}) do
            f.delay:SetText(invalid); f.delay:Fire("OnEnterPressed")
            eq(db.delay, 7.5); eq(f.delay:GetText(), "7.5")
        end
        f.cooldown:SetText("3601"); f:Hide()
        eq(db.cooldown, 300); eq(f.cooldown:GetText(), "300")
        f.delay:SetText("1"); f.cooldown:SetText("240"); f:Hide()
        local reloaded, reopen = harness(db, legacy)
        local r = reopen()
        eq(reloaded[savedName].delay, 1); eq(reloaded[savedName].cooldown, 240)
        eq(reloaded[savedName].showMinimap, false)
        eq(r.showMinimap:GetChecked(), false)
        eq(r.delay:GetText(), "1"); eq(r.cooldown:GetText(), "240")
        -- Programmatic refresh after reset must not restore old edits.
        for _, button in ipairs(widgets) do
            if button.kind == "Button" and button.text == "Reset defaults" then button:Fire("OnClick") end
        end
        eq(db.delay, 5); eq(db.cooldown, 60)
        eq(db.showMinimap, true); eq(f.showMinimap:GetChecked(), true)
        f:Hide(); open(); eq(db.delay, 5); eq(db.cooldown, 60)
    end
    print("PASS " .. addon .. " GUI autosave, validation, reset, and saved-settings reload (modern/legacy callbacks)")
end
