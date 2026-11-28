-- Exercise the real options callbacks without a running WoW client.
return function(addon)
    local savedName = addon == "OctoThanks" and "OctoThanksDB" or "ForeverThanksDB"
    local openName = addon == "OctoThanks" and "OpenOctoThanksOptions" or "OpenForeverThanksOptions"
    local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
    local function harness(saved, legacy, character)
        local env = setmetatable({SlashCmdList = {}}, {__index = _G})
        env[savedName] = saved or {}
        env.ForeverThanksCharDB = character or {}
        env.GetTime = function() return 100 end
        env.print = function() end
        env.DEFAULT_CHAT_FRAME = {AddMessage = function() end}
        local root, options, widgets = nil, nil, {}
        local function widget(kind, name)
            local f = {scripts = {}, text = "", kind = kind}
            local function noop() end
            setmetatable(f, {__index = function(_, key)
                if key:find("^Set") or key:find("^Register") or key == "EnableMouse" then return noop end
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
            function f:Show() self.shown = true; self:Fire("OnShow") end
            function f:Hide() self.shown = false; self:Fire("OnHide") end
            function f:IsShown() return self.shown == true end
            function f:SetHeight(height) self.height = height end
            function f:GetHeight() return self.height end
            function f:GetVerticalScroll() return self.scrollOffset or 0 end
            function f:SetVerticalScroll(value) self.scrollOffset = value end
            function f:UpdateScrollChildRect() self.updated = true end
            function f:HighlightText(first, last) self.highlight = {first, last} end
            function f:SetFocus() self.focus = true end
            function f:CreateFontString() return widget("FontString") end
            function f:CreateTexture() return widget("Texture") end
            widgets[#widgets + 1] = f
            if kind == "Frame" and not root then root = f end
            if name == "ForeverThanksOptions" or name == "OctoThanksOptions" then options = f end
            if name then env[name] = f end
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
        env[openName](true); eq(f:IsShown(), false)
        env[openName](true); eq(f:IsShown(), true)
        env[openName](); eq(f:IsShown(), true)
        eq(db.delay, 5); eq(db.cooldown, 60)
        -- Typing 10 must save without Enter and survive closing and reloading.
        f.cooldown:SetText("1"); eq(db.cooldown, 60)
        f.cooldown:SetText("10"); eq(db.cooldown, 10)
        f.cooldown:ClearFocus(); f:Hide(); open()
        eq(f.cooldown:GetText(), "10"); eq(db.cooldown, 10)
        local cooldownReload, cooldownOpen = harness(db, legacy)
        eq(cooldownReload[savedName].cooldown, 10)
        eq(cooldownOpen().cooldown:GetText(), "10")
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
        local function click(label)
            for _, button in ipairs(widgets) do
                if button.kind == "Button" and button.text == label then button:Fire("OnClick"); return end
            end
            error("Missing button: " .. label)
        end
        -- The GUI must edit only the displayed scope and preserve both on reload.
        f.message:SetText("Shared greeting!"); click("Save message")
        eq(db.message, "Shared greeting!")
        f.characterMessage:SetChecked(true); f.characterMessage:Fire("OnClick")
        eq(f.message:GetText(), "")
        f.message:SetText("In-character thanks, {name}!"); click("Save message")
        local character = env.ForeverThanksCharDB
        eq(character.useCharacterMessage, true)
        eq(character.message, "In-character thanks, {name}!")
        eq(db.message, "Shared greeting!")
        local loaded, reopenCharacter = harness(db, legacy, character)
        local c = reopenCharacter()
        eq(c.characterMessage:GetChecked(), true)
        eq(c.message:GetText(), "In-character thanks, {name}!")
        c.characterMessage:SetChecked(false); c.characterMessage:Fire("OnClick")
        eq(c.message:GetText(), "Shared greeting!")
        c.characterMessage:SetChecked(true); c.characterMessage:Fire("OnClick")
        eq(c.message:GetText(), "In-character thanks, {name}!")
        f.characterMessage:SetChecked(true); f.characterMessage:Fire("OnClick")
        click("Reset defaults")
        eq(db.message, "Shared greeting!"); eq(character.message, nil)
        -- There are only two mode buttons; Emote edits its separate custom text.
        for _, button in ipairs(widgets) do assert(button.text ~= "Custom /em") end
        click("Emote")
        eq(db.channel, "EMOTE"); eq(f.message:GetText(), "")
        assert(f.messageLabel:GetText():find("Custom emote", 1, true))
        assert(f.messageHint:GetText():find("Prepare, then Enter", 1, true))
        f.message:SetText("/em thanks {name} for %s!"); click("Save message")
        eq(character.emoteText, "thanks {name} for %s!"); eq(db.message, "Shared greeting!")
        local emoteLoaded, emoteOpen = harness(db, legacy, character)
        local e = emoteOpen()
        eq(emoteLoaded[savedName].channel, "EMOTE")
        eq(e.message:GetText(), "thanks {name} for %s!")
        f.characterMessage:SetChecked(false); f.characterMessage:Fire("OnClick")
        f.message:SetText("shared custom emote"); click("Save message")
        eq(db.emoteText, "shared custom emote")
        click("Whisper"); eq(f.message:GetText(), "Shared greeting!")
        assert(not f.messageHint:GetText():find("Prepare", 1, true))
        click("Emote"); eq(f.message:GetText(), "shared custom emote")
        f.message:SetText(""); click("Save message"); eq(db.emoteText, nil)
        eq(db.message, "Shared greeting!")
    end
    for _, legacy in ipairs({false, true}) do
        local shared = {message = "Original whisper", emoteText = "Original emote"}
        local character = {}
        local env, open = harness(shared, legacy, character)
        local f = open()
        eq(f.replySummary:GetText(), "Replies: Single message")
        f.editReplies:Fire("OnClick")
        local editor = env.ForeverThanksWhisperReplies
        eq(editor.edit:GetText(), "Original whisper")
        assert(editor.shown)
        editor.edit:SetText("  Cheers {name}!  \r\n\nThanks for %s!\nCheers {name}!\n")
        editor.save:Fire("OnClick")
        eq(shared.useWhisperList, true); eq(#shared.whisperReplies, 2)
        eq(shared.whisperReplies[1], "Cheers {name}!"); eq(shared.whisperReplies[2], "Thanks for %s!")
        eq(shared.message, "Original whisper"); eq(shared.emoteText, "Original emote")
        eq(f.replySummary:GetText(), "Replies: Custom list (2)")
        eq(editor.shown, false)
        local reloaded, reopen = harness(shared, legacy, character)
        eq(reopen().replySummary:GetText(), "Replies: Custom list (2)")
        eq(reloaded[savedName].useWhisperList, true)
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("Unsaved change"); editor.cancel:Fire("OnClick")
        eq(shared.whisperReplies[1], "Cheers {name}!")
        f.editReplies:Fire("OnClick")
        for _, invalid in ipairs({"Good line\nbad|text", "Good line\n" .. string.rep("x", 201), "bad\tcontrol"}) do
            editor.edit:SetText(invalid); editor.save:Fire("OnClick")
            assert(editor.shown and editor.edit.highlight)
            eq(shared.whisperReplies[1], "Cheers {name}!")
            assert(editor.validation:GetText():find("Line", 1, true))
        end
        local many = {}
        for i = 1, 101 do many[i] = "Reply " .. i end
        editor.edit:SetText(table.concat(many, "\n")); editor.save:Fire("OnClick")
        assert(editor.validation:GetText():find("100", 1, true))
        eq(#shared.whisperReplies, 2)
        editor.edit:SetText(string.rep("x", 50001)); editor.save:Fire("OnClick")
        assert(editor.validation:GetText():find("Too much text", 1, true))
        eq(#shared.whisperReplies, 2)
        -- A separate character list never overwrites the shared list or either emote.
        f.characterMessage:SetChecked(true); f.characterMessage:Fire("OnClick")
        eq(editor.shown, false)
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("My character's thanks, {name}!\nMy second reply")
        editor.save:Fire("OnClick")
        eq(character.useWhisperList, true); eq(#character.whisperReplies, 2)
        eq(#shared.whisperReplies, 2)
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("Unsaved replacement"); env[openName](true)
        eq(f:IsShown(), false)
        eq(editor.shown, false); eq(character.whisperReplies[2], "My second reply")
        open(); f.editReplies:Fire("OnClick")
        -- Slash scope changes during editing cannot redirect a save to another scope.
        env.SlashCmdList.FOREVERTHANKS("messagescope global")
        editor.edit:SetText("Must not overwrite shared replies"); editor.save:Fire("OnClick")
        eq(shared.whisperReplies[1], "Cheers {name}!"); eq(editor.shown, false)
        open(); f.editReplies:Fire("OnClick")
        editor.restore:Fire("OnClick")
        eq(shared.whisperReplies, nil); eq(shared.useWhisperList, false); eq(shared.message, nil)
        eq(shared.emoteText, "Original emote"); eq(#character.whisperReplies, 2)
        eq(f.replySummary:GetText(), "Replies: Built-in (28)")
        f.editReplies:Fire("OnClick")
        assert(editor.edit:GetText():find("Ayyy", 1, true))
        -- Blank Save also restores defaults, while Escape discards edits.
        editor.edit:SetText("Only one"); editor.save:Fire("OnClick")
        eq(#shared.whisperReplies, 1)
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("  \n\n"); editor.save:Fire("OnClick")
        eq(shared.whisperReplies, nil); eq(f.replySummary:GetText(), "Replies: Built-in (28)")
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("Don't save this"); editor.edit:Fire("OnEscapePressed")
        eq(editor.shown, false); eq(shared.whisperReplies, nil)
        -- Existing single-message controls deactivate but preserve a saved list.
        f.editReplies:Fire("OnClick")
        editor.edit:SetText("Keep this list"); editor.save:Fire("OnClick")
        env.SlashCmdList.FOREVERTHANKS("message My single reply")
        eq(shared.useWhisperList, false); eq(shared.whisperReplies[1], "Keep this list")
        open(); eq(f.replySummary:GetText(), "Replies: Single message")
        -- Cursor movement keeps the current line in view.
        f.editReplies:Fire("OnClick")
        editor.edit.scripts.OnCursorChanged(editor.edit, 0, -400, 5, 14)
        assert(editor.scroll:GetVerticalScroll() > 0)
        editor.edit.scripts.OnCursorChanged(editor.edit, 0, 0, 5, 14)
        eq(editor.scroll:GetVerticalScroll(), 0)
    end
    print("PASS " .. addon .. " whisper list editor: save, cancel, validation, scopes, defaults, and scrolling")
    print("PASS " .. addon .. " GUI autosave, validation, reset, and saved-settings reload (modern/legacy callbacks)")
end
