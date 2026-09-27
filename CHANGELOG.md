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
