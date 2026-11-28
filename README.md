# forever_thanks

Friendly automatic thank-you whispers and targeted built-in emotes, plus custom emote drafts for
**World of Warcraft: Forever 1.60.1**, by Sinestro.

## Features

- Thanks players for newly applied or refreshed helpful buffs whose reported duration is **strictly greater than five minutes (300 seconds)**. Three-minute Battle Shout and buffs lasting exactly five minutes are ignored.
- Uses 28 varied thank-you messages and avoids repeating the same reply twice in a row.
- Supports your own random whisper list in a separate **Edit replies** window. Paste one reply per line; use shared lists or a different list for each character.
- Supports custom whispers with `{name}` for the buff caster's character name and `%s` for the buff name.
- Can save a different custom whisper for each character, or use one shared message. Existing shared messages remain the default.
- Sends a private whisper by default, or a targeted emote without requiring the buff caster to be selected.
- In **Emote** mode, leave the field blank for automatic Thank or random animated emotes. With custom text saved, a prompt offers **Prepare emote** after a buff: click it, then press Enter to send. Custom text uses `{name}` and `%s` and does not animate your character.
- Waits five seconds after detecting a qualifying buff before replying.
- Supports fixed `THANK` emotes or random positive emotes such as Salute, Bow, Wave, Cheer, and Applaud.
- Random animated emotes wait for you to stop moving or falling, for up to 10 extra seconds after the configured delay. Default THANK, custom text, and whispers do not use this movement wait.
- Replies to different players are spaced three seconds apart rather than dropping the second reply. Waiting replies expire if they become too old.
- Can suppress whispers when the buff came from a party or raid member while still allowing emotes.
- Includes an ignored-buff list using spell names or spell IDs, useful for buffs such as Campfire.
- Ignores self-buffs, NPC buffs, permanent or unknown-duration effects, short effects such as Renew, and existing buffs restored during login, reloads, portals, or zone/instance transfers.
- Attempts both whisper and emote replies during combat, while still skipping safely when the client hides aura or caster information or blocks the action.
- Includes a saved option to hide the minimap button.
- Settings persist across reloads and logouts.

## Install

Download the release ZIP, not GitHub's source archive. Extract the **forever_thanks** folder into your Forever client's `Interface/AddOns` directory, then restart the client if it was open. Enable `forever_thanks` in the AddOns list. Disable any other automatic thank-you addon to avoid duplicate messages.

The final structure must be:

`Interface/AddOns/forever_thanks/forever_thanks.toc`

## In-game options

Open the settings window with:

`/ft gui`

You can also click the blue Thank You heart button on the minimap's outer edge (bottom-left by default). Drag the button around the minimap to reposition it; its position is saved. The options window controls enabling the addon, Whisper or Emote mode, reply delay, cooldown, group behavior, random emotes, custom messages, and ignored buffs. Settings are saved automatically. Valid delay and cooldown values save as you type; pressing Enter is not required.

Click the minimap icon once to open options and again to close them, including when the icon is inside Leatrix Plus's button bag. `/ft gui` always opens options.

Uncheck **Show minimap button** to hide the button. This choice is saved across reloads and logouts. You can always reopen settings with `/ft gui` and show it again.

**Square minimaps and icon bags:** when Leatrix Plus or another addon provides the shared LibDBIcon/LibDataBroker libraries, Forever Thanks registers a standard icon so Leatrix's minimap button bag can collect it and control its placement. Your existing button position and visibility are preserved. Without those libraries, the standalone button follows round or square minimap edges and adjusts when the map is resized. No separate library download is required.

### Shared or character-specific reply text

Leave **Use character-specific reply text** unchecked to use shared text. Existing custom whispers keep working this way by default.

To give an alt its own roleplay message, check that option in `/ft gui`, type the character's message, and click **Save message**. That character remembers both the text and the checked option across logouts. Other characters keep their own choice. Whisper and custom-emote text are saved separately within each scope.

Switching the checkbox displays the saved text for that scope without deleting the other scope's text. A new character-specific slot starts blank. Saving a blank whisper uses rotating replies; saving a blank custom emote uses built-in Thank or random animations. **Reset defaults** clears only the selected scope's reply text.

Only the custom reply text and its scope choice are character-specific. Modes, cooldowns, reply delays, and the other settings remain shared.

### Make your own whisper reply list

1. Open `/ft gui` and select **Whisper**.
2. Choose shared text or check **Use character-specific reply text** for this character only.
3. Click **Edit replies** next to the reply summary.
4. Enter one reply per line, or paste your whole list. `{name}` inserts the caster and `%s` inserts the buff.
5. Click **Save**. The summary shows **Custom list** and the number of replies.

For example:

```text
Cheers, {name}! Appreciate the %s.
{name}, you're a legend. Thanks!
That buff will come in handy. Much appreciated!
```

Whispers choose randomly from the saved list without repeating the previous reply when there is more than one. You can save up to 100 different replies, each up to 200 bytes before inserting names. Blank lines and identical duplicate lines are ignored. Invalid lines are identified before saving; your previous list stays intact until the new list is valid and saved.

**Cancel**, the X button, or Escape discards unsaved edits. **Restore defaults**, or saving an empty list, restores the 28 built-in whispers for the selected scope. Saving the main **Custom whisper** field switches back to a single reply without deleting your saved list; reopen **Edit replies** and save to reactivate it. **Reset defaults** clears the selected scope's saved list too.

Whisper lists are automatic and do not affect emotes. The same delay, cooldown, buff-duration requirement, and group filters still apply.

### Write a custom emote

1. Open `/ft gui` and select **Emote**.
2. In **Custom emote**, enter `{name}, thanks for the %s!` or your own wording.
3. Click **Save message**.
4. After someone gives you a qualifying buff, click **Prepare emote** on the prompt, then press **Enter** to send.

`{name}` becomes the caster's name and `%s` becomes the buff's name. WoW supplies your character's name at the start, as it does for a manually typed `/em`. You may include a leading `/em` in the settings text if you prefer; it is removed before saving. The same text box edits custom whispers in Whisper mode, and each mode keeps its own text.

With custom text saved, a small prompt appears after the configured reply delay, showing the caster and your message. Click **Prepare emote** to fill the normal chat box, then **press Enter to send**. Escape cancels the chat draft; **Skip** dismisses a pending prompt. Nothing is sent or focused automatically, and an already-open chat message is not overwritten. No whisper or built-in animation is sent as well.

Custom emote prompts expire after 60 seconds and at most five are kept, with one per caster. Disabling the addon, zoning, or changing relevant settings clears pending prompts. The per-caster cooldown starts when you prepare a draft; diagnostics count it as prepared, not confirmed sent, because you may edit or cancel it in chat.

**Why the extra step?** Forever restricts automatic custom text emotes. The addon no longer attempts that blocked send, even inside an instance. Your Enter key sends through the normal game chat instead. Whispers and built-in Thank/random emotes remain automatic when the client permits them.

To return to automatic built-in emotes, clear the custom emote text and click **Save message**. The normal Thank emote is directed at the buff caster by name without targeting them or clicking Prepare. The random-animations checkbox chooses random built-in emotes instead. `/ft preview` shows a local sample without sending it.

## Commands

| Command | Action |
| --- | --- |
| `/ft gui` | Open the in-game options window |
| `/ft minimap on` / `/ft minimap off` | Show or hide the minimap button |
| `/ft status` | Show settings and session diagnostics |
| `/ft on` / `/ft off` | Enable or disable automatic replies |
| `/ft mode whisper` | Send a private whisper; default mode |
| `/ft mode emote` | Offer custom emote drafts, or automatically use Thank/random emotes if the text is blank |
| `/ft delay 5` | Set the reply delay from 0 to 60 seconds |
| `/ft cooldown 60` | Set the per-player cooldown from 10 to 3600 seconds; default 60 |
| `/ft groups on` / `/ft groups off` | Allow or suppress all thanks while grouped |
| `/ft groupwhisper on` / `/ft groupwhisper off` | Allow or suppress whispers to party/raid buff casters |
| `/ft emotes thank` / `/ft emotes random` | Choose fixed THANK or random positive emotes |
| `/ft messagescope global` / `/ft messagescope character` | Choose the shared or character-specific custom whisper |
| `/ft message Thank you {name} for the %s!` | Set a custom whisper; `{name}` becomes the caster's name and `%s` becomes the buff name |
| `/ft message random` | Use the 28 rotating messages in the selected scope |
| `/ft emotetext <text>` | Save custom `/em` text in the selected scope |
| `/ft emotetext default` | Clear custom emote text and restore built-in Thank/random emotes |
| `/ft ignore add <name or ID>` | Add a buff to the ignore list |
| `/ft ignore remove <name or ID>` | Remove a buff from the ignore list |
| `/ft ignore list` | Show ignored buffs |
| `/ft ignore clear` | Clear the ignored-buff list |
| `/ft preview` | Show a local sample without sending anything |
| `/ft debug` | Toggle local chat-attempt diagnostics |

`/foreverthanks` and `/forever_thanks` are aliases for `/ft`.

For example, `Thank you {name} for the %s!` becomes `Thank you Steamboots for the Blessing of Might!`. This works in the custom-whisper field in `/ft gui` as well as with the message command. Use `/ft preview` to check it locally with example names.

The message commands and preview use the selected scope. The Save message button edits custom emote text in Emote mode, and custom whisper text in Whisper mode. The earlier `/ft mode custom` command remains an alias for Emote for compatibility, not a separate mode.

## Important behavior

The addon intentionally ignores buffs that were already present during login, reload, zoning, or instance transfers so it does not thank everyone nearby for old buffs. New qualifying buffs must be detected while the client is ready. Combat does not automatically cancel a reply, but client restrictions, range limits, or unreadable aura data can still prevent it. Blocked actions are not repeatedly retried.

Random animated emotes are selected only after the player is confirmed stationary and not falling. While moving, the addon waits up to 10 additional seconds after the normal reply delay, then discards the reply instead of sending a stale thank-you. If movement information is unavailable or hidden, it uses the same bounded wait. Default THANK does not require readable movement information. This does not guarantee that the client will play an animation or deliver an emote.

When two players buff you close together, their replies queue with three-second anti-spam spacing. Waiting is bounded to avoid sending stale replies. The per-caster cooldown is shared across reply modes: switching from Whisper to Emote does not thank the same player again immediately. `/ft status` shows the last reply decision to help identify cooldown, movement, or client-blocking problems.

Whispers use the caster's realm-qualified name. Emotes use the caster's plain character name and do not read or change your selected target.

All rights reserved. No affiliation with Blizzard Entertainment.
