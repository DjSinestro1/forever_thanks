# 0.1.0.23

- Clicking the minimap icon now toggles the options window: click once to open, again to close.
- Works with both the standalone minimap icon and the icon inside Leatrix Plus's button bag.
- Keeps `/ft gui` as an open-options command. Closing with the icon preserves saved settings and discards unsaved list-editor changes.

# 0.1.0.22

- Fixes compatibility with Leatrix Plus's square minimap and minimap button bag.
- Registers the heart icon with the shared LibDBIcon/LibDataBroker libraries when available, allowing minimap managers to collect and place it normally.
- Keeps collected icons in their bag when zoning instead of forcing them back onto the minimap.
- Preserves the existing icon position and Show minimap button setting, including icons hidden before upgrading.
- Supports round and square minimap edges and resizing when using the standalone button without shared libraries.
- Handles libraries loaded before or after Forever Thanks without showing duplicate icons. No extra library installation is required.

# 0.1.0.21

- Adds a compact whisper-reply summary and Edit replies button in Whisper mode.
- Opens a separate list editor: paste one reply per line, using `{name}` for the caster and `%s` for the buff.
- Randomly chooses from your saved list without repeating the previous reply when multiple replies are available.
- Supports independent shared and character-specific lists, saved across reloads and logouts.
- Allows up to 100 different replies, each up to 200 bytes before inserting names. Ignores blank/duplicate lines and highlights invalid lines without replacing the saved list.
- Includes Save, Cancel, and Restore defaults. Saving the existing single-message field deactivates the list without deleting it.
- Keeps whisper lists separate from emotes and preserves existing timing, cooldowns, group filters, and buff requirements.

# 0.1.0.20

- Stops automatically sending custom text emotes, which could cause the game's "Interface action failed because of an AddOn" error.
- After the reply delay, custom emotes now show a small prompt with the caster's name and your expanded message. Click Prepare emote, then press Enter in the normal chat box to send. Skip dismisses a reply.
- Keeps whispers and built-in Thank/random emotes automatic. Clear the custom emote text to use automatic built-in emotes.
- Preserves existing shared and character-specific messages. The settings window now explains the manual step for custom text.
- Does not open chat without a click or overwrite an active chat message. Pending prompts expire after 60 seconds, coalesce buffs from one caster, and are cleared when disabled, zoning, or changing relevant settings.
- Limits pending custom emotes to five. Diagnostics distinguish prepared drafts from actual chat requests.
- Also includes the updates since 0.1.0.16: cooldowns from 10 to 3600 seconds, shared or character-specific custom emote text, two reply-mode buttons, and fixes for closely spaced buffs from different players being dropped.

# 0.1.0.19

- Simplifies the GUI to two reply modes: Whisper and Emote.
- Renames the text field to Custom emote when Emote is selected, using the same text box as Custom whisper.
- Uses saved custom emote text when provided. Saving a blank field restores the built-in Thank or random animated emotes.
- Preserves whisper and emote text separately in shared and per-character settings. Each reply uses only the selected mode.
- Migrates the previous Custom /em mode to Emote without deleting saved text.

# 0.1.0.18

- Adds a selectable Custom /em text mode alongside Whisper and built-in Emote modes.
- Supports `{name}` for the buff caster and `%s` for the buff name. Text can be entered with or without an `/em` prefix.
- Stores custom emote text separately from whispers, with shared or per-character text settings.
- Custom text emotes do not play an animation. The GUI warns that the client may block automatic custom /em messages; no client restrictions are bypassed.
- Fixes the anti-spam interval dropping the second player's thank-you when buffs arrive close together, such as priest Fortitude followed by Blessing of Wisdom. Replies now queue with three-second spacing and a bounded expiry.
- Applies the stand-still check only to random animated emotes, not default THANK or custom text.
- Adds the last reply decision to `/ft status` and more useful debug reasons for waiting, cooldowns, and rejected requests.

# 0.1.0.17

- Allows per-caster cooldowns from 10 to 3600 seconds in both the GUI and slash command. The previous 30-second minimum rejected a value of 10.
- Keeps the default cooldown at 60 seconds.
- Shows the allowed range beside the GUI field.
- Preserves valid shorter cooldowns across reloads and logouts.

# 0.1.0.16

- Adds an optional character-specific custom whisper for roleplay alts and other characters needing different messages.
- Keeps shared messages as the default and preserves existing custom whispers without migration.
- Adds a Use a character-specific custom whisper checkbox to `/ft gui`. The scope choice and personal message persist for each character.
- Keeps shared and character messages separate when switching scopes. A blank slot uses the rotating replies; it does not overwrite the other scope.
- Adds `/ft messagescope global` and `/ft messagescope character`. Message commands and previews use the selected scope.
- Leaves all other settings shared. Reset defaults clears only the selected scope's custom message.

# 0.1.0.15

- Adds the existing blue-and-gold heart texture to the game's AddOns list instead of the question-mark fallback.
- No changes to reply behavior or combat handling.

# 0.1.0.14

- Adds `{name}` to custom whispers for the buff caster's name, alongside `%s` for the buff name. Example: `Thank you {name} for the %s!`.
- Raises the minimum qualifying buff duration to strictly more than five minutes (300 seconds), for both whispers and emotes.
- Ignores talented three-minute Battle Shout and buffs lasting exactly five minutes.
- Updates the options hint, message confirmation, preview, status output, and documentation.

# 0.1.0.13

- Allows whisper and emote attempts during combat when the client exposes readable buff and caster data.
- Preserves queued replies when entering or leaving combat; unreadable data and client restrictions still fail safely.
- Waits for the player to stop moving or falling before selecting an emote. Replies expire after 10 extra seconds if movement continues or cannot be read.
- Keeps whispers on the normal configured delay regardless of movement.
- Adds a saved Show minimap button checkbox in the options window, plus `/ft minimap on` and `/ft minimap off`. Options remain accessible through `/ft gui`.
- Adds regression tests for combat replies, movement waits and expiry, hidden data, and saved minimap visibility.

# 0.1.0-beta.12

- Fixes reply delay and per-caster cooldown reverting after editing the options window without pressing Enter.
- Saves valid numbers as they are typed, including when another control is clicked or the window is closed.
- Invalid entries restore the last valid value without clearing the other field.
- Adds options-window regression tests for saving, validation, reset, and reloading saved settings.

# 0.1.0-beta.11

- Fixes the black minimap icon using a 128x128 TGA texture of the blue Thank You artwork with the golden heart.
- Places the button on the minimap's outer edge and above map artwork.
- Adds dragging around the minimap, with the position saved between sessions.
- Handles minimap creation after loading and legacy tooltip callbacks.

# 0.1.0-beta.10

- Fixes the options window on ForeverWoW clients without the newer `SetBackdrop` API by using a compatible background texture fallback.
- Makes the minimap button use either `Minimap` or `MinimapCluster`, places it visibly at the minimap corner, and explicitly shows it.

# 0.1.0-beta.9

- Adds an in-game options window opened with `/ft gui` or the new minimap button.
- Adds saved controls for enable/disable, whisper/emote mode, five-second reply delay, cooldown, group handling, and custom messages.
- Adds optional suppression of whispers to party/raid buff casters.
- Adds random positive emotes: Salute, Bow, Wave, Cheer, and Applaud.
- Adds an ignored-buff list that accepts spell names or spell IDs.
- Keeps slash commands available as a troubleshooting and accessibility fallback.
- Adds regression coverage for the new delay, group-caster filter, ignored buffs, random emotes, and five-second default.

# 0.1.0-beta.8

- Fixes false thanks when existing buffs arrive late after login, reload, portals, or instance/zone transfers.
- Adds a five-second minimum silent settling period, extended until player-aura updates are quiet for one second, followed by a final silent snapshot.
- Ignores aura updates between leaving and entering the world, cancels pending replies, and invalidates stale loading timers during rapid transfers.
- Skips old buffs arriving even after settling by checking remaining duration against the full buff duration. Only applications/refreshed buffs reported within five seconds qualify.
- Applies to both whispers and emotes; keeps whisper as the default and preserves saved preferences.
- A real buff received during settling or reported unusually late may intentionally receive no thanks. Status reports the settling phase.
- Adds regression coverage for delayed/batched restoration, aura-ID changes, rapid transfers, settings changes, unreadable data, combat, and later genuine buffs. In-game verification of this fix is still needed.

# 0.1.0-beta.7

- Fixes targeted emotes by using the buff caster's plain character name, preserving spaces; whispers still use Name-Realm.
- Never requires, reads, or changes the player's selected target.
- Fixes false blocked warnings: PerformEmote returns a restriction flag, as used by Blizzard's chat UI, not a success flag.
- The user confirmed a delayed plain-name THANK works after clearing the selected target. Full addon flow remains to be retested in-game.
- Whisper stays the default; saved emote mode and other preferences are preserved.

# 0.1.0-beta.6

- Adds optional targeted THANK emotes via mode emote; automatic whispers remain the default.
- Saves the selected mode; mode whisper restores private replies. The channel command is an alias.
- Preserves duration filters, cooldowns, and 28 whisper replies. Mode changes cancel pending replies.
- No chat-text emotes, retargeting, automatic whisper fallback, or retries when an emote fails.
- Targeted delivery and Classic/Retail automatic emotes still need in-game testing.

# 0.1.0-beta.5

- Restored automatic whispers after automatic SAY failed in the user's Forever test.
- Migrates saved SAY settings to WHISPER on load; the channel command can no longer enable SAY.
- Preserves 28 replies, other saved preferences, buff filters, and cooldowns.

# 0.1.0-beta.4

- Automatically attempts SAY outdoors as well as inside instances, for Forever beta testing.
- Removed manual say drafts and the send command. Optional automatic WHISPER remains available.
- Keeps 28 replies, cooldowns, and out-of-combat restrictions.
- Actual outdoor SAY delivery must be tested in the Forever client. Blocked sends are reported without repeated retries or manual prompts.

# 0.1.0-beta.3

- Corrected outdoor say handling: a local prompt offers /ft send, which opens a prepared /say message; the player presses Enter to submit it.
- Automatic whisper remains available. Say inside instances is attempted where permitted.
- Drafts expire after 30 seconds and cancel on disable, channel change, zoning, or combat.
- Expanded automated tests for outdoor chat restrictions. Still requires in-game testing.

# 0.1.0-beta.2

- Added /ft channel say|whisper with say as the default.
- Added 20 slang-inspired replies, for 28 total; no consecutive random repeats.
- Existing settings without a channel migrate to say; explicit choices persist.
- Preserved buff detection, combat restrictions, and cooldowns across channel changes.
- Diagnostics now report the selected chat channel.

# 0.1.0-beta.1

- Initial Forever-specific beta release.
- Eight rotating thank-you whispers for buffs longer than two minutes.
- Caster GUID lookup supports buffs with no sourceUnit.
- Self/NPC/short-buff filtering, login baselines, cooldowns, and combat restriction handling.
- Saved settings, custom messages, status, and local preview.
- Full addon awaits in-game end-to-end validation; caster lookup and whisper primitives were tested on 1.60.1.
