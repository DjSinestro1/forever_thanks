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
