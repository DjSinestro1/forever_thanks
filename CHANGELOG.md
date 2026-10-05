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
